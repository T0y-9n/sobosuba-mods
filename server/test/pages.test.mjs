import assert from "node:assert/strict";
import { test } from "node:test";
import { createTestHarness } from "wrangler";
import { randomBytes, randomInt } from "node:crypto";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { createServer, connect } from "node:net";

// Scores-screen transport (page + own rank) in standalone Godot against the real Worker and local D1.
// "warmed" reads page 2 before Godot submits: the server must not serve that answer again
// (no cache, spec §7), so Godot's page 2 after its POST is new in both scenarios.
for (const scenario of ["direct", "warmed"]) test(`standalone Godot scores-screen pages (${scenario}): real HTTPRequest, workerd and D1`, async () => {
  assert.ok(process.env.GODOT_BIN, "Set GODOT_BIN to a standalone Godot 4.7.2 console executable; never the game");
  assert.ok(process.env.SOBOSUBA_QA_ROOT, "Set SOBOSUBA_QA_ROOT to a folder for the tests' work files");
  const root = process.env.SOBOSUBA_QA_ROOT;
  await mkdir(root, { recursive: true });
  const directory = await mkdtemp(resolve(root, "online-pages-"));
  await writeFile(resolve(directory, "project.godot"), `[application]
config/name="Prime Scores Screen Transport Check"
`, "utf8");
  const server = createTestHarness({ workers: [{ configPath: "./wrangler.toml",
    secrets: { IP_HASH_SECRET: randomBytes(32).toString("hex") } }] });
  let proxy;
  let quick;
  const connections = new Set();
  try {
    const { url } = await server.listen();
    await server.getWorker().applyD1Migrations("DB");
    const port = createServer();
    await new Promise(resolve => port.listen(0, "127.0.0.1", resolve));
    const closedPort = port.address().port;
    await new Promise(resolve => port.close(resolve));
    // Real TCP proxy that holds the real Worker's answer for six seconds; it never makes up a reply.
    proxy = createServer(socket => {
      const upstream = connect(Number(url.port), "127.0.0.1");
      connections.add(socket); connections.add(upstream);
      socket.pipe(upstream);
      const timer = setTimeout(() => upstream.pipe(socket), 6000);
      const close = () => { clearTimeout(timer); socket.destroy(); upstream.destroy(); connections.delete(socket); connections.delete(upstream); };
      socket.on("error", close); upstream.on("error", close); socket.on("close", close);
    });
    await new Promise(resolve => proxy.listen(0, "127.0.0.1", resolve));
    // The same real proxy holding the answer two seconds (inside the five-second budget): an older
    // scores-screen read that comes back after a newer one.
    quick = createServer(socket => {
      const upstream = connect(Number(url.port), "127.0.0.1");
      connections.add(socket); connections.add(upstream);
      socket.pipe(upstream);
      const timer = setTimeout(() => upstream.pipe(socket), 2000);
      const close = () => { clearTimeout(timer); socket.destroy(); upstream.destroy(); connections.delete(socket); connections.delete(upstream); };
      socket.on("error", close); upstream.on("error", close); socket.on("close", close);
    });
    await new Promise(resolve => quick.listen(0, "127.0.0.1", resolve));
    // Eleven real players (1000, 1004, ..., 1040). Distinct IPs stay under the native POST limit.
    const fillers = Array.from({ length: 11 }, () => "7656119" + String(randomInt(0, 10_000_000_000)).padStart(10, "0"));
    const godotSteamId = "7656119" + String(randomInt(0, 10_000_000_000)).padStart(10, "0");
    for (let i = 0; i < 11; i++) {
      const response = await fetch(new URL("/v1/scores", url), { method: "POST", headers: {
        "content-type": "application/json", "CF-Connecting-IP": `127.0.2.${i + 1}` }, body: JSON.stringify({
        mod: "prime_sobo", mod_version: "0.2.0", player_id: fillers[i], player_key: randomBytes(32).toString("hex"),
        name: `filler${i}`, score: 1000 + i * 4, duration_s: 100, prime_chance: 0.10 }) });
      assert.equal(response.status, 200);
    }
    if (scenario === "warmed") {
      const warm = await fetch(new URL("/v1/leaderboard?mod=prime_sobo&limit=10&offset=10", url), { headers: { "CF-Connecting-IP": "127.0.3.1" } });
      assert.equal(warm.status, 200);
      assert.deepEqual((await warm.json()).entries.map(e => [e.rank, e.best]), [[11, 1000]]);
    }
    const child = spawn(process.env.GODOT_BIN, ["--headless", "--path", directory,
      "--script", resolve("test/online_pages.gd"), "--", resolve("../mods/prime_sobo/prime_online.gd"),
      url.origin, directory, `http://127.0.0.1:${closedPort}`, `http://127.0.0.1:${proxy.address().port}`, scenario,
      godotSteamId, fillers[0], fillers[10], `http://127.0.0.1:${quick.address().port}`],
      { windowsHide: true, timeout: 60000 });
    let output = "";
    child.stdout.on("data", data => { output += data; });
    child.stderr.on("data", data => { output += data; });
    const code = await new Promise((resolve, reject) => { child.on("error", reject); child.on("close", resolve); });
    console.log(output.trim());
    assert.equal(code, 0, output);
    assert.ok(!output.includes("SCRIPT ERROR"), output);
    assert.ok(!output.includes("ERROR:"), output);
    assert.ok(output.includes("PAGES_DONE"), output);
    const db = (await server.getWorker().getEnv()).DB;
    // Only Godot's one real submission joins the eleven players; page/own reads write nothing.
    assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM players").first()).n, 12);
    assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM submissions").first()).n, 12);
  } finally {
    for (const socket of connections) socket.destroy();
    if (proxy) await new Promise(resolve => proxy.close(resolve));
    if (quick) await new Promise(resolve => quick.close(resolve));
    await server.close();
  }
});
