import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { spawn } from "node:child_process";

// Prime mode on/off (spec §7) in standalone Godot on real files. No server, no game.
test("standalone Godot prime settings: the switch and the mode a run keeps, on real files", async () => {
  assert.ok(process.env.GODOT_BIN, "Set GODOT_BIN to a standalone Godot 4.7.2 console executable; never the game");
  assert.ok(process.env.SOBOSUBA_QA_ROOT, "Set SOBOSUBA_QA_ROOT to a folder for the tests' work files");
  const root = process.env.SOBOSUBA_QA_ROOT;
  await mkdir(root, { recursive: true });
  const directory = await mkdtemp(resolve(root, "online-settings-"));
  await writeFile(resolve(directory, "project.godot"), `[application]
config/name="Prime Settings Check"
`, "utf8");
  const child = spawn(process.env.GODOT_BIN, ["--headless", "--path", directory,
    "--script", resolve("test/settings.gd"), "--", resolve("../mods/prime_sobo/prime_settings.gd"), directory],
    { windowsHide: true, timeout: 30000 });
  let output = "";
  child.stdout.on("data", data => { output += data; });
  child.stderr.on("data", data => { output += data; });
  const code = await new Promise((resolve, reject) => { child.on("error", reject); child.on("close", resolve); });
  console.log(output.trim());
  assert.equal(code, 0, output);
  assert.ok(!output.includes("SCRIPT ERROR"), output);
  assert.ok(!output.includes("ERROR:"), output);
  assert.ok(output.includes("SETTINGS_DONE failures=0"), output);
});

// The run's caller (prime_sobo.gd needs the game, so it is read here, never run): the id it hands
// start_run comes from save_id_of(has_save, md5), so a save that is there but whose MD5 could not be
// read is never passed as "" (no save), and the game's self-test 10 runs that case on the real file.
test("prime_sobo.gd passes start_run a save id that tells an unreadable save from no save", async () => {
  const { readFile } = await import("node:fs/promises");
  const lines = (await readFile(resolve("../mods/prime_sobo/prime_sobo.gd"), "utf8")).split(/\r?\n/)
    .map(line => line.replace(/#.*$/, ""));
  const begin = lines.findIndex(line => /^func on_game_mode_start\(/.test(line));
  assert.ok(begin >= 0, "on_game_mode_start is there");
  const end = lines.findIndex((line, i) => i > begin && /^func /.test(line));
  const body = lines.slice(begin, end).join("\n");
  assert.match(body, /prime_settings\.save_id_of\(has_save,/, "the run's save id comes from save_id_of(has_save, ...)");
  const assigned = body.split("\n").filter(line => /\bsave_id\b[^=(]*=[^=]/.test(line));
  assert.ok(assigned.length > 0 && assigned.every(line => line.includes("prime_settings.save_id_of(has_save,")),
    `every save id the run is given comes from save_id_of, never "" for a save that is there: ${assigned}`);
  const runs = lines.filter(line => line.includes("prime_settings.start_run("));
  assert.ok(runs.some(line => line.includes("save_id_of(true, \"\")")), "self-test 10 starts a run over a save whose MD5 could not be read");
});

// "send scores" (spec §8) on the game's settings screen. prime_sobo.gd needs the game, so it is read
// here, never run: the switch sits right under prime balls and decides whether a run's score is sent.
test("prime_sobo.gd puts send scores under prime balls and sends only while it is on", async () => {
  const { readFile } = await import("node:fs/promises");
  const source = (await readFile(resolve("../mods/prime_sobo/prime_sobo.gd"), "utf8")).split(/\r?\n/)
    .map(line => line.replace(/#.*$/, "")).join("\n");
  const body = name => {
    const start = source.indexOf(`\nfunc ${name}(`);
    assert.ok(start >= 0, `${name} is there`);
    const next = source.indexOf("\nfunc ", start + 1);
    return source.slice(start, next < 0 ? undefined : next);
  };
  assert.match(source, /const SEND_TEXT:= "send scores"/, "the switch reads send scores");
  assert.match(source, /\n\tinstall_prime_toggle\(menu\)\n\tinstall_send_toggle\(menu\)\n/, "the switch is installed right after prime balls");
  assert.match(body("install_send_toggle"), /prime_toggle\.add_sibling\(/, "it goes right under prime balls");
  assert.match(body("_ready"), /online\.send_scores = prime_settings\.send_scores/, "the saved choice is used from the start");
  const pressed = body("set_send_scores");
  assert.match(pressed, /prime_settings\.set_send_scores\(value\)/, "pressing writes the choice");
  assert.match(pressed, /online\.send_scores = prime_settings\.send_scores/, "pressing decides the next sends by the choice that was written");
  assert.doesNotMatch(source, /visibility/, "nothing else is told to the server");
});

// The mod's own words follow the game's language (spec §9): prime_text.gd in standalone Godot,
// switched through the real TranslationServer to each language the game offers. No game.
test("standalone Godot prime_text.gd: the mod's words in each of the game's languages", async () => {
  assert.ok(process.env.GODOT_BIN, "Set GODOT_BIN to a standalone Godot 4.7.2 console executable; never the game");
  assert.ok(process.env.SOBOSUBA_QA_ROOT, "Set SOBOSUBA_QA_ROOT to a folder for the tests' work files");
  const root = process.env.SOBOSUBA_QA_ROOT;
  await mkdir(root, { recursive: true });
  const directory = await mkdtemp(resolve(root, "prime-text-"));
  await writeFile(resolve(directory, "project.godot"), `[application]
config/name="Prime Text Check"
`, "utf8");
  const child = spawn(process.env.GODOT_BIN, ["--headless", "--path", directory,
    "--script", resolve("test/text.gd"), "--", resolve("../mods/prime_sobo/prime_text.gd")],
    { windowsHide: true, timeout: 30000 });
  let output = "";
  child.stdout.on("data", data => { output += data; });
  child.stderr.on("data", data => { output += data; });
  const code = await new Promise((resolve, reject) => { child.on("error", reject); child.on("close", resolve); });
  console.log(output.trim());
  assert.equal(code, 0, output);
  assert.ok(!output.includes("SCRIPT ERROR"), output);
  assert.ok(output.includes("TEXT_DONE failures=0"), output);
});

test("prime_sobo.gd shows its switches and lines in the game's language, and again when it changes", async () => {
  const { readFile } = await import("node:fs/promises");
  const source = (await readFile(resolve("../mods/prime_sobo/prime_sobo.gd"), "utf8")).split(/\r?\n/)
    .map(line => line.replace(/#.*$/, "")).join("\n");
  const body = name => {
    const start = source.indexOf(`\nfunc ${name}(`);
    assert.ok(start >= 0, `${name} is there`);
    const next = source.indexOf("\nfunc ", start + 1);
    return source.slice(start, next < 0 ? undefined : next);
  };
  assert.match(source, /load\(mod_dir\(\)\.path_join\("prime_text\.gd"\)\)/, "the words come from prime_text.gd");
  assert.doesNotMatch(source, /label\.text = (TOGGLE_TEXT|SEND_TEXT)\b/, "no switch keeps the English word");
  // The game's self-test compared the prime balls switch with the English words and failed in Japanese
  // (2026-10-31 02:58 on the real game).
  assert.doesNotMatch(source, /label\.text [!=]= "(prime balls|send scores)"/, "the self-test compares the switches in the game's language");
  assert.doesNotMatch(source, /get_locale\(\)\.begins_with\("ja"\)/, "no line is Japanese-or-English only");
  assert.match(body("_notification"), /NOTIFICATION_TRANSLATION_CHANGED/, "a language change is noticed");
  assert.match(body("refresh_texts"), /guide_label\.text/, "and the lines are written again");
  assert.match(body("install_guide_toggle"), /\.theme = load\("res:\/\/ui\/theme\.tres"\)/, "the guide switch uses the game's theme, whose font the game swaps per language");
  assert.doesNotMatch(body("install_guide_toggle"), /settings\.font =/, "the line under it keeps no font of its own");
});

// The settings switch takes effect from the next new game, unlike the guide's, which starts the run
// again. Its description says so (2026-10-31 16:45 on the real game: switching it off from the
// settings did not start a new game, and nothing said why).
test("prime balls description says the switch from the settings takes effect from a new game", async () => {
  const { readFile } = await import("node:fs/promises");
  const words = await readFile(resolve("../mods/prime_sobo/prime_text.gd"), "utf8");
  const start = words.indexOf('"prime balls description": {');
  assert.ok(start >= 0, "prime balls description is there");
  const block = words.slice(start, words.indexOf("},", start));
  const line = locale => block.match(new RegExp(`"${locale}": "([^"]*)"`))?.[1] ?? "";
  assert.match(line("en"), /new game/i, `English: ${line("en")}`);
  assert.match(line("ja"), /ニューゲーム/, `Japanese: ${line("ja")}`);
});

// The board after a run, the scores screen and the world ranking lines follow the game's language
// too: every word the player reads is in prime_text.gd, and the scores screen uses the game's font.
test("the mod's scripts keep their words in prime_text.gd, so every line follows the game's language", async () => {
  const { readFile, readdir } = await import("node:fs/promises");
  const code = async name => (await readFile(resolve("../mods/prime_sobo", name), "utf8")).split(/\r?\n/)
    .map(line => line.replace(/#.*$/, "")).join("\n");
  for (const name of (await readdir(resolve("../mods/prime_sobo"))).filter(name => name.endsWith(".gd") && name !== "prime_text.gd")) {
    const match = (await code(name)).match(/.*[　-ヿ一-鿿＀-￯].*/);
    assert.equal(match, null, `${name} has no Japanese of its own: ${match?.[0]?.trim()}`);
  }
  const screen = await code("prime_scores_screen.gd");
  assert.doesNotMatch(screen, /japanese_font\(\)/, "the scores screen uses the game's font for the language");
  const open = screen.slice(screen.indexOf("\nfunc open("), screen.indexOf("\nfunc ", screen.indexOf("\nfunc open(") + 1));
  assert.match(open, /heading\.text = word\("scores heading"\)/, "the heading is written in the language when the screen opens");
});

// prime balls on the game's "how to play" guide (spec §9). prime_sobo.gd needs the game, so it is read
// here, never run; the game's self-test presses the switch on a real run.
test("prime_sobo.gd puts prime balls on the guide while it shows, and pressing starts the run again", async () => {
  const { readFile } = await import("node:fs/promises");
  const source = (await readFile(resolve("../mods/prime_sobo/prime_sobo.gd"), "utf8")).split(/\r?\n/)
    .map(line => line.replace(/#.*$/, "")).join("\n");
  const body = name => {
    const start = source.indexOf(`\nfunc ${name}(`);
    assert.ok(start >= 0, `${name} is there`);
    const next = source.indexOf("\nfunc ", start + 1);
    return source.slice(start, next < 0 ? undefined : next);
  };
  assert.match(source, /\n\tinstall_send_toggle\(menu\)\n\tinstall_guide_toggle\(\)\n/, "the guide switch is made after the settings switches");
  assert.match(body("install_guide_toggle"), /Ui\._0\.add_child\(/, "it sits on the screen layer the game's side panels use");
  // A copy of the button's own Label, shown under the guide, crashed the game when a new run began
  // (2026-10-31 on the real game: the copy without that line did not crash). The line is a new Label.
  assert.match(body("install_guide_toggle"), /Label\.new\(\)/, "the line under the switch is a new Label");
  assert.doesNotMatch(body("install_guide_toggle"), /label\.duplicate\(/, "no copy of the game's Label is shown during a run");
  const place = body("place_guide_toggle");
  assert.match(place, /\.instructions\b/, "it follows the game's guide");
  assert.match(place, /current_control/, "it shows only while the guide shows its controls");
  assert.match(place, /demo_explanation/, "not with the demo note");
  assert.match(body("_process"), /place_guide_toggle\(\)/, "placed every frame, also while prime mode is off");
  const pressed = body("on_guide_toggle_pressed");
  assert.match(pressed, /set_prime_enabled\(prime_settings\.enabled == false\)/, "pressing flips and writes the switch");
  assert.match(pressed, /GameModeManager\.start_game_mode\(GameModeManager\.current_mode\.scene_file_path\)/, "then starts the run again like the game's new game");
  assert.match(body("refresh_prime_toggle"), /guide_toggle/, "the guide switch shows the same state as the settings one");
  assert.match(body("run_selftest"), /await selftest_guide_toggle\(lines\)\n\tfinish_selftest\(lines\)/, "the self-test presses it last, since it starts runs again");
});
