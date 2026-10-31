import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { execFileSync } from "node:child_process";

// What gets published (README, the mod, the server and its tests) names one place for scores:
// the mod's own public entrance. Nothing in it points at the account behind that entrance or at
// folders on the machine it was written on. Notes for the people working on it are not published.
const ENTRANCE = "https://sobosuba-ranking.pages.dev";
const UNPUBLISHED = /^(NOTES\.md|gitco\.json|docs\/)/;
const repo = resolve("..");

function publishedFiles() {
  return execFileSync("git", ["ls-files"], { cwd: repo, encoding: "utf8" })
    .split(/\r?\n/).filter(path => path && !UNPUBLISHED.test(path) && path !== "server/test/public.test.mjs");
}

test("online.cfg sends to the mod's public entrance", async () => {
  const cfg = await readFile(resolve(repo, "mods/prime_sobo/online.cfg"), "utf8");
  assert.match(cfg, /^server_url="([^"]*)"$/m);
  assert.equal(cfg.match(/^server_url="([^"]*)"$/m)[1], ENTRANCE);
});

test("published files name no account host and no local work folder", async () => {
  const found = [];
  for (const path of publishedFiles()) {
    const text = await readFile(resolve(repo, path), "utf8");
    for (const pattern of [/workers\.dev/, /_AI_WORK_BUFFER/, /[A-Z]:[\\/]Users[\\/]/]) {
      if (pattern.test(text)) found.push(`${path}: ${pattern}`);
    }
  }
  assert.deepEqual(found, []);
});

test("README says where scores go and what the author does with Steam IDs, in English and Japanese", async () => {
  const readme = await readFile(resolve(repo, "README.md"), "utf8");
  for (const heading of ["### Where scores go", "### 点数の送り先"]) {
    const start = readme.indexOf(heading);
    assert.ok(start >= 0, `${heading} is there`);
    const next = readme.indexOf("\n### ", start + heading.length);
    const section = readme.slice(start, next < 0 ? undefined : next);
    assert.ok(section.includes(ENTRANCE.replace("https://", "")), `${heading} names the entrance`);
    assert.match(section, /Steam ID/, `${heading} talks about Steam IDs`);
  }
});

// The world ranking sends Steam IDs even with send scores off, and the ranking itself shows them,
// so README must not say otherwise. Anyone can claim an ID first, so the section warns about it.
test("README is exact about what is sent and shown, and warns that the first sender holds an ID's row", async () => {
  const readme = await readFile(resolve(repo, "README.md"), "utf8");
  for (const wrong of ["While it's off nothing is sent", "切っている間は何も送らず", "given to anyone", "人に渡したり"]) {
    assert.ok(!readme.includes(wrong), `README still says "${wrong}"`);
  }
  for (const [heading, first] of [["### Where scores go", /sends a score for a Steam ID first/], ["### 点数の送り先", /最初に点数を送った人/]]) {
    const start = readme.indexOf(heading);
    const section = readme.slice(start, readme.indexOf("\n### ", start + heading.length));
    assert.match(section, first, `${heading} warns that the first sender holds the row`);
  }
});

// Before going public (2026-10-31 18:07): the MIT license covers only the code written for this mod,
// the parts that follow the game's code stay the developer's, and we follow the developer's word.
// tools/ is not published, the limit of the score checks is stated, and the credits name Kinkan（Maccha）.
test("LICENSE and README say what the license covers, what the checks can't catch, and who helped", async () => {
  const license = await readFile(resolve(repo, "LICENSE"), "utf8");
  const readme = await readFile(resolve(repo, "README.md"), "utf8");
  for (const [text, where] of [[license, "LICENSE"], [readme, "README"]]) {
    assert.match(text, /covers only the code written for this mod/, `${where} limits the license in English`);
    assert.match(text, /この MOD のために書いたコードだけ/, `${where} limits the license in Japanese`);
    assert.match(text, /take (it )?down/, `${where} says we follow the developer`);
  }
  assert.match(license, /MIT License/, "the MIT text stays");
  assert.doesNotMatch(readme, /`tools\/`/, "README does not point at tools/");
  assert.match(readme, /can't be told apart/, "README states the limit of the checks in English");
  assert.match(readme, /見分けられません/, "README states the limit of the checks in Japanese");
  assert.equal(readme.split("Kinkan（Maccha）").length - 1, 2, "the credits name Kinkan（Maccha） in both languages");
});

// The version is "<game>-<mod>" (2026-10-31 18:26): 1.2.3-1.0.0 is mod 1.0.0 for sobosuba 1.2.3.
// The first release said 1.23 by misreading the game's 1.2.3 (fixed 2026-10-31 23:4x).
// The server takes it as it is ([\w.-], so no "+"), and README says which game version it was made for.
test("the mod's version names the game version it was made for, and README says so", async () => {
  const online = await readFile(resolve(repo, "mods/prime_sobo/prime_online.gd"), "utf8");
  const version = online.match(/^const MOD_VERSION:= "([^"]*)"/m)?.[1];
  assert.equal(version, "1.2.3-1.0.0");
  assert.match(version, /^[\w.-]{1,32}$/, "the server's mod_version check takes it");
  const readme = await readFile(resolve(repo, "README.md"), "utf8");
  assert.match(readme, /made for sobosuba 1\.2\.3\./, "README names the game version in English");
  assert.match(readme, /`1\.2\.3-1\.0\.0`/, "README explains the version");
  assert.doesNotMatch(readme, /sobosuba 1\.23\b/, "the misread 1.23 is gone");
  assert.equal(readme.split("sobosuba 1.2.3").length - 1 >= 2, true, "and in Japanese");
});

// The game part must be the game's own config/version, read from the decompiled game when it is at hand.
test("the game part of the mod's version is the game's config/version when its source is at hand", async t => {
  const project = process.env.SOBOSUBA_GAME_SRC ? resolve(process.env.SOBOSUBA_GAME_SRC, "project.godot.txt") : "";
  if (!project || !existsSync(project)) {
    t.skip(`game source not found (${project}); the game version was not compared`);
    return;
  }
  const game = (await readFile(project, "utf8")).replaceAll("\0", "").match(/config\/version\s*=\s*"([^"]+)"/)?.[1];
  assert.ok(game, "project.godot has config/version");
  const online = await readFile(resolve(repo, "mods/prime_sobo/prime_online.gd"), "utf8");
  const version = online.match(/^const MOD_VERSION:= "([^"]*)"/m)?.[1];
  assert.equal(version.split("-")[0], game);
});

// What changed is written where players look (2026-10-31 21:14), in English and Japanese, and every
// release of the mod has its entry. Server-only changes are listed too, with no new mod version.
test("CHANGELOG has the mod's version and the server change, in English and Japanese", async () => {
  const log = (await readFile(resolve(repo, "CHANGELOG.md"), "utf8")).replace(/\r\n/g, "\n");
  const online = await readFile(resolve(repo, "mods/prime_sobo/prime_online.gd"), "utf8");
  const version = online.match(/^const MOD_VERSION:= "([^"]*)"/m)[1];
  const [en, ja] = log.split("## 日本語");
  assert.ok(ja, "there is a Japanese part");
  for (const [part, server] of [[en, /nothing to reinstall/], [ja, /入れ直しは要りません/]]) {
    assert.match(part, new RegExp(`^### ${version.replace(/\./g, "\\.")}\\b`, "m"), "the mod's version has an entry");
    assert.match(part, server, "the server change says the mod is unchanged");
  }
});

// The credits match the announcement in #sobosuba (2026-10-31 19:31): keepee for the game and the OK,
// and Kinkan（Maccha） as a test player, in both languages.
test("the credits thank keepee and name Kinkan（Maccha） as a test player", async () => {
  const readme = (await readFile(resolve(repo, "README.md"), "utf8")).replace(/\r\n/g, "\n");
  const en = readme.split("### Special thanks")[1]?.split("###")[0] ?? "";
  const ja = readme.split("### 謝辞")[1]?.split("###")[0] ?? "";
  assert.match(en, /^- keepee, for making sobosuba and saying yes to mods$/m);
  assert.match(en, /^- Kinkan（Maccha）, test player$/m);
  assert.match(ja, /^- sobosuba を作り、MOD を認めてくれた keepee さん$/m);
  assert.match(ja, /^- テストプレイヤーの Kinkan（Maccha）さん$/m);
});
