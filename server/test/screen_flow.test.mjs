import assert from "node:assert/strict";
import { test } from "node:test";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

// The prime scores screen runs the game's ScoresScreen flow, but a game function that reads the
// author's ScoreManager (the Steam leaderboard data) must never run on it: each one is overridden
// with the same flow reading the prime records (spec §5). Checked on the real MOD file.
// The names are the game's ScoresScreen functions that read ScoreManager (decompiled 2026-10-30).
const READS_SCORE_MANAGER = [
  "_ready", "_on_clear_local_scores_confirm_release_press", "refresh_leaderboard",
  "refresh_friends_leaderboard", "_on_my_score_release_press", "_on_steam_leaderboard_updated",
  "go_to_own_friends_entry", "generate_steam_leaderboard", "generate_friends_leaderboard",
  "generate_local_leaderboard", "is_my_score_disabled", "get_page_count",
  "should_request_remote_on_page_change", "get_own_friends_index",
];

function code(path) {
  // GDScript without comments (the MOD's comments name ScoreManager when they explain the flow).
  return readFileSync(path, "utf8").split(/\r?\n/).map(line => line.replace(/#.*$/, ""));
}
function functions(lines) {
  return new Set(lines.flatMap(line => /^func\s+(\w+)\s*\(/.exec(line)?.slice(1) ?? []));
}

test("the prime scores screen overrides every game ScoresScreen function that reads ScoreManager", () => {
  const screen = code(resolve("../mods/prime_sobo/prime_scores_screen.gd"));
  const own = functions(screen);
  const missing = READS_SCORE_MANAGER.filter(name => !own.has(name));
  assert.deepEqual(missing, [], `game functions that would read the author's ScoreManager on the prime screen: ${missing}`);
  const reads = screen.filter(line => line.includes("ScoreManager"));
  assert.deepEqual(reads, [], "the prime scores screen itself never reads ScoreManager");
});

// The screen's world reads go through the transport's latest-only reads (tested on real HTTP with a
// real slow proxy in online_pages.gd), and each answer that comes back stale is dropped before it
// can replace the rows or show the failure text.
test("the prime scores screen reads the world only through the latest-only reads and drops stale answers", () => {
  const screen = code(resolve("../mods/prime_sobo/prime_scores_screen.gd"));
  const text = screen.join("\n");
  for (const direct of ["fetch_page(", "fetch_own_rank(", "fetch_friends("])
    assert.ok(!text.includes(direct), `the screen calls ${direct} directly, where an older answer would win`);
  for (const read of ["screen_page", "screen_own_rank", "screen_friends"]) {
    const call = screen.findIndex(line => line.includes(`await online.${read}(`));
    assert.ok(call >= 0, `the screen reads through online.${read}`);
    // The answer is checked for stale within the next few lines, before anything else uses it.
    const after = screen.slice(call + 1, call + 4).join("\n");
    assert.match(after, /\.get\("stale", false\)\)?:?\s*\n?\s*return|if \w+\.get\("stale", false\):\s*\n\s*return/, `online.${read}: a stale answer is dropped right away`);
  }
});

// The list above follows the game. When the decompiled game source is at hand (read only, never
// copied into this repo), the list must equal what the game's scores_screen.gd actually reads.
test("the list of ScoreManager readers matches the game's scores_screen.gd when its source is at hand", t => {
  const source = process.env.SOBOSUBA_GAME_SRC
    ? resolve(process.env.SOBOSUBA_GAME_SRC, "ui/menu/screens/scores_screen/scores_screen.gd") : "";
  if (!source || !existsSync(source)) {
    t.diagnostic(`game source not found (${source}); only the list in this file was checked`);
    return;
  }
  const readers = new Set();
  let current = "";
  for (const line of code(source)) {
    current = /^func\s+(\w+)\s*\(/.exec(line)?.[1] ?? current;
    if (line.includes("ScoreManager")) readers.add(current);
  }
  assert.deepEqual([...readers].sort(), [...READS_SCORE_MANAGER].sort());
});
