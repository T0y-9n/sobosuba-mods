import assert from "node:assert/strict";
import { test } from "node:test";
import { createTestHarness } from "wrangler";
import { randomBytes, randomInt } from "node:crypto";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { spawn } from "node:child_process";
import { createServer, connect } from "node:net";

for (const scenario of ["first", "outside_top"]) test(`standalone Godot ${scenario}: real files, HTTPRequest, workerd and D1`, async () => {
  assert.ok(process.env.GODOT_BIN, "Set GODOT_BIN to a standalone Godot 4.7.2 console executable; never the game");
  assert.ok(process.env.SOBOSUBA_QA_ROOT, "Set SOBOSUBA_QA_ROOT to a folder for the tests' work files");
  const root = process.env.SOBOSUBA_QA_ROOT;
  await mkdir(root, { recursive: true });
  const directory = await mkdtemp(resolve(root, "online-"));
  await writeFile(resolve(directory, "project.godot"), `[application]
config/name="Prime Online Transport Check"
[display]
window/size/viewport_width=512
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep_height"
`, "utf8");
  const server = createTestHarness({ workers: [{ configPath: "./wrangler.toml",
    secrets: { IP_HASH_SECRET: randomBytes(32).toString("hex") } }] });
  let proxy;
  const connections = new Set();
  try {
    const { url } = await server.listen();
    await server.getWorker().applyD1Migrations("DB");
    const port = createServer();
    await new Promise(resolve => port.listen(0, "127.0.0.1", resolve));
    const closedPort = port.address().port;
    await new Promise(resolve => port.close(resolve));
    proxy = createServer(socket => {
      const upstream = connect(Number(url.port), "127.0.0.1");
      connections.add(socket); connections.add(upstream);
      socket.pipe(upstream);
      const timer = setTimeout(() => upstream.pipe(socket), 6000);
      const close = () => { clearTimeout(timer); socket.destroy(); upstream.destroy(); connections.delete(socket); connections.delete(upstream); };
      socket.on("error", close); upstream.on("error", close); socket.on("close", close);
    });
    await new Promise(resolve => proxy.listen(0, "127.0.0.1", resolve));
    if (scenario === "outside_top") {
      for (let i = 0; i < 5; i++) {
        const response = await fetch(new URL("/v1/scores", url), { method: "POST", headers: {
          "content-type": "application/json", "CF-Connecting-IP": "127.0.0.1" }, body: JSON.stringify({
          mod: "prime_sobo", mod_version: "0.1.0", player_id: "7656119" + String(randomInt(0, 10_000_000_000)).padStart(10, "0"), player_key: randomBytes(32).toString("hex"),
          name: `leader${i}`, score: 200 + i * 2, duration_s: 20, prime_chance: 0.10 }) });
        assert.equal(response.status, 200);
      }
    }
    // A public read before Godot registers itself must not leave a stale answer behind.
    const warm = await fetch(new URL("/v1/leaderboard?mod=prime_sobo&limit=5", url));
    assert.equal(warm.status, 200);
    // The Steam ID the game would read from Steam (prime_sobo.gd sets it on the transport).
    const godotSteamId = "7656119" + String(randomInt(0, 10_000_000_000)).padStart(10, "0");
    const displayArgs =process.env.SOBOSUBA_RENDER === "1" ? ["--rendering-method", "gl_compatibility"] : ["--headless"];
    const child = spawn(process.env.GODOT_BIN, [...displayArgs, "--path", directory,
      "--script", resolve("test/online.gd"), "--", resolve("../mods/prime_sobo/prime_online.gd"),
      url.origin, directory, `http://127.0.0.1:${closedPort}`, `http://127.0.0.1:${proxy.address().port}`,
      scenario === "first" ? "1" : "6", godotSteamId, scenario === "first" ? "fresh" : "legacy"], { windowsHide: true, timeout: 25000 });
    let output = "";
    child.stdout.on("data", data => { output += data; });
    child.stderr.on("data", data => { output += data; });
    const code = await new Promise((resolve, reject) => { child.on("error", reject); child.on("close", resolve); });
    assert.equal(code, 0, output);
    assert.ok(!output.includes("SCRIPT ERROR"), output);
    assert.ok(!output.includes("ERROR:"), output);
    console.log(output.trim());
    const db = (await server.getWorker().getEnv()).DB;
    const expected = scenario === "first" ? 1 : 6;
    assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM players").first()).n, expected);
    assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM submissions WHERE accepted=1").first()).n, expected);
    // Godot's row is its Steam ID with the Steam name (not the name in online.cfg), version 1.23-1.0.0.
    const own = await db.prepare("SELECT p.name, s.mod_version FROM players p JOIN submissions s ON s.player_id=p.player_id WHERE p.player_id=?").bind(godotSteamId).first();
    assert.deepEqual(own, { name: "Godot player", mod_version: "1.23-1.0.0" });
  } finally {
    for (const socket of connections) socket.destroy();
    if (proxy) await new Promise(resolve => proxy.close(resolve));
    await server.close();
  }
});
