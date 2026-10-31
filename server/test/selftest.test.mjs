import assert from "node:assert/strict";
import { test } from "node:test";
import { copyFile, cp, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { spawn } from "node:child_process";

// The mod's own self-test (prime_sobo.gd run_selftest) on the game's data, in the standalone debug Godot.
// The debug build checks more than the game's export does: it refused a freed sobo in a typed variable,
// which stopped the self-test after 3+5 merged while the game itself ran it fine (PR 36).
// The game's pck sits inside sobosuba.exe; Godot reads override.cfg next to the main pack, so the exe is
// copied next to a fresh override.cfg and mods folder. Without SOBOSUBA_GAME_PCK the test is skipped.
test("the mod's self-test runs to the end on the game's data in the standalone debug Godot", { timeout: 600000 }, async t => {
  const pck = process.env.SOBOSUBA_GAME_PCK;
  if (!pck || !existsSync(pck)) {
    t.skip(`SOBOSUBA_GAME_PCK not set or missing (${pck ?? ""}); the self-test was not run`);
    return;
  }
  assert.ok(process.env.GODOT_BIN, "Set GODOT_BIN to a standalone Godot 4.7.2 console executable; never the game");
  assert.ok(process.env.SOBOSUBA_QA_ROOT, "Set SOBOSUBA_QA_ROOT to a folder for the tests' work files");
  await mkdir(process.env.SOBOSUBA_QA_ROOT, { recursive: true });
  const directory = await mkdtemp(resolve(process.env.SOBOSUBA_QA_ROOT, "selftest-"));
  const mod = resolve(directory, "mods/prime_sobo");
  await cp(resolve("../mods/prime_sobo"), mod, { recursive: true });
  await writeFile(resolve(mod, "selftest.flag"), "", "utf8");
  const script = resolve(mod, "prime_sobo.gd").replaceAll("\\", "/");
  await writeFile(resolve(directory, "override.cfg"), `[autoload]\n\nPrimeSobo="*${script}"\n`, "utf8");
  const main = resolve(directory, "sobosuba.pck.exe");
  await copyFile(pck, main);

  const child = spawn(process.env.GODOT_BIN, ["--headless", "--main-pack", main],
    { windowsHide: true, timeout: 540000 });
  let output = "";
  // A script error leaves the self-test waiting forever, so stop there instead of at the timeout.
  const read = data => {
    output += data;
    if (output.includes("SCRIPT ERROR")) child.kill();
  };
  child.stdout.on("data", read);
  child.stderr.on("data", read);
  const code = await new Promise((resolve, reject) => { child.on("error", reject); child.on("close", resolve); });
  assert.ok(!output.includes("SCRIPT ERROR"), output.slice(-4000));
  assert.ok(output.includes("[prime_sobo] loaded:"), "the mod was loaded through override.cfg");
  assert.notEqual(code, null, "Godot quit by itself (it was not killed on the timeout)");

  const resultPath = resolve(mod, "selftest_result.txt");
  assert.ok(existsSync(resultPath), `no selftest_result.txt; Godot exited ${code}\n${output.slice(-4000)}`);
  const result = await readFile(resultPath, "utf8");
  console.log(result.trim());
  assert.doesNotMatch(result, /FAIL/);
  assert.match(result, /^pair 3\+5: touched=true merged=true expected_merge=true -> OK$/m);
  assert.match(result, /^check guide toggle: the real settings file is untouched: OK$/m, "the last step ran");
});
