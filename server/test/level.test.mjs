import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { spawn } from "node:child_process";

// Prime levels (mod spec §10) in standalone Godot on the real prime_level.gd. No game.
test("standalone Godot prime_level.gd: the game's open spawn tiers give the level and its chance", async () => {
  assert.ok(process.env.GODOT_BIN, "Set GODOT_BIN to a standalone Godot 4.7.2 console executable; never the game");
  assert.ok(process.env.SOBOSUBA_QA_ROOT, "Set SOBOSUBA_QA_ROOT to a folder for the tests' work files");
  const root = process.env.SOBOSUBA_QA_ROOT;
  await mkdir(root, { recursive: true });
  const directory = await mkdtemp(resolve(root, "prime-level-"));
  await writeFile(resolve(directory, "project.godot"), `[application]
config/name="Prime Level Check"
`, "utf8");
  const child = spawn(process.env.GODOT_BIN, ["--headless", "--path", directory,
    "--script", resolve("test/level.gd"), "--", resolve("../mods/prime_sobo/prime_level.gd")],
    { windowsHide: true, timeout: 30000 });
  let output = "";
  child.stdout.on("data", data => { output += data; });
  child.stderr.on("data", data => { output += data; });
  const code = await new Promise((resolve, reject) => { child.on("error", reject); child.on("close", resolve); });
  console.log(output.trim());
  assert.equal(code, 0, output);
  assert.ok(!output.includes("SCRIPT ERROR"), output);
  assert.ok(output.includes("LEVEL_DONE failures=0"), output);
});

// prime_sobo.gd and prime_scores.gd need the game, so they are read here, never run.
async function code(name) {
  return (await readFile(resolve(`../mods/prime_sobo/${name}`), "utf8")).split(/\r?\n/)
    .map(line => line.replace(/#.*$/, "")).join("\n");
}

function body(source, name) {
  const lines = source.split("\n");
  const begin = lines.findIndex(line => line.startsWith(`func ${name}(`));
  assert.ok(begin >= 0, `${name} is there`);
  const end = lines.findIndex((line, i) => i > begin && /^(func |var |const |@)/.test(line));
  return lines.slice(begin, end < 0 ? undefined : end).join("\n");
}

test("the prime roll and the sent chance both come from the level of the game's own spawn pool", async () => {
  const sobo = await code("prime_sobo.gd");
  assert.doesNotMatch(sobo, /PRIME_CHANCE/, "no fixed chance is left");
  assert.match(body(sobo, "roll_prime"), /randf\(\) < run_chance\(\)/);
  assert.match(body(sobo, "run_chance"), /prime_level\.chance_of\(current_level\(\)\)/);
  assert.match(body(sobo, "current_level"), /spawn_pool\.current_spawn_pool/);
  assert.match(await code("prime_scores.gd"), /submit_score\.call_deferred\(score, duration_s, get_parent\(\)\.run_chance\(\)\)/);
});

test("the level line is a new Label on the game's right panel under its big score, shown only in a prime run", async () => {
  const sobo = await code("prime_sobo.gd");
  const install = body(sobo, "install_level_label");
  assert.match(install, /Label\.new\(\)/);
  assert.doesNotMatch(install, /duplicate\(/, "the game's own Label is never copied (spec §9 crashed on that)");
  // The big score in a run is LiveScoreDisplay's SDFLabel on RightSidePanel; CurrentScoreNumber is not in the classic run.
  assert.match(install, /RightSidePanel/);
  const refresh = body(sobo, "refresh_level_label");
  assert.match(refresh, /run_prime/);
  assert.match(refresh, /word\("level"\)/);
});
