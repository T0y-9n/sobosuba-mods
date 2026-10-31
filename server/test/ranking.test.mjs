import assert from "node:assert/strict";
import { beforeEach, afterEach, test } from "node:test";
import { randomBytes, randomInt, randomUUID, createHash } from "node:crypto";
import { createTestHarness } from "wrangler";

// Real workerd, real local D1, and actual loopback HTTP. No service doubles.
const ipSecret = randomBytes(32).toString("hex");
let server, base, db;
beforeEach(async () => {
  // Each real runtime owns fresh native limiter windows.
  server = createTestHarness({ workers: [{ configPath: "./wrangler.toml",
    secrets: { IP_HASH_SECRET: ipSecret } }] });
  base = (await server.listen()).url;
  await server.getWorker().applyD1Migrations("DB");
  db = (await server.getWorker().getEnv()).DB;
});
afterEach(async () => { await server.close(); });
// A player is a Steam ID (SteamID64 in decimal, spec §3), like the game's own Steam leaderboard.
function steamId() {
  return "7656119" + String(randomInt(0, 10_000_000_000)).padStart(10, "0");
}
function player(fields = {}) {
  return { mod: "prime_sobo", mod_version: "0.2.0", player_id: steamId(),
    player_key: randomBytes(32).toString("hex"), name: "player", score: 100,
    duration_s: 20, prime_chance: 0.10, ...fields };
}
async function request(path, body, ip = "127.0.0.1") {
  const response = await fetch(new URL(path, base), body === undefined ? { headers: { "CF-Connecting-IP": ip } } : {
    method: "POST", headers: { "content-type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify(body) });
  return { status: response.status, body: await response.json(), headers: response.headers };
}

test("health responds on the versioned HTTP route", async () => {
  assert.deepEqual((await request("/v1/health")).body, { ok: true });
});
test("first score registers a player and returns their best rank", async () => {
  const result = await request("/v1/scores", player());
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { ok: true, rank: 1, best: 100, players: 1 });
});
test("leaderboard sorts bests and around includes the requested player's neighbors", async () => {
  const a = player({ name: "first", score: 200 });
  const b = player({ name: "second", score: 200 });
  const c = player({ name: "third", score: 100 });
  for (const p of [a, b, c]) assert.equal((await request("/v1/scores", p)).status, 200);
  const top = await request("/v1/leaderboard?mod=prime_sobo&limit=2");
  assert.equal(top.status, 200);
  assert.deepEqual(top.body.entries.map(e => [e.name, e.best, e.rank]), [["first", 200, 1], ["second", 200, 2]]);
  assert.equal(top.body.players, 3);
  const around = await request(`/v1/leaderboard/around?mod=prime_sobo&player_id=${b.player_id}&span=1`);
  assert.deepEqual(around.body.entries.map(e => e.name), ["first", "second", "third"]);
  assert.equal(around.body.rank, 2);
  assert.deepEqual(around.body.entries.map(e => e.you), [false, true, false]);
  for (const e of around.body.entries) assert.deepEqual(Object.keys(e).sort(), ["best", "name", "rank", "steam_id", "you"]);
  // Rows carry the Steam ID like the game's Steam leaderboard rows (spec §2), so the scores
  // screen draws Steam names and avatars and finds the own row by Steam ID.
  assert.deepEqual(top.body.entries.map(e => e.steam_id), [a.player_id, b.player_id]);
  assert.deepEqual(around.body.entries.map(e => e.steam_id), [a.player_id, b.player_id, c.player_id]);
  for (const e of top.body.entries) assert.deepEqual(Object.keys(e).sort(), ["best", "name", "rank", "steam_id"]);
});

// Each case catches a missing boundary guard through real HTTP, not a private helper.
for (const [label, fields, error] of [
  ["negative score", { score: -2 }, "INVALID_SCORE"],
  ["odd score", { score: 101 }, "INVALID_SCORE"],
  ["fractional score", { score: 2.5 }, "INVALID_SCORE"],
  ["score above cap", { score: 10000002 }, "INVALID_SCORE"],
  ["string score", { score: "100" }, "INVALID_SCORE"],
  ["short duration", { duration_s: 9 }, "INVALID_DURATION"],
  ["long duration", { duration_s: 86401 }, "INVALID_DURATION"],
  ["fractional duration", { duration_s: 10.5 }, "INVALID_DURATION"],
  ["excessive score rate", { score: 502, duration_s: 10 }, "SCORE_RATE"],
  ["wrong mod", { mod: "other" }, "INVALID_MOD"],
  ["negative probability", { prime_chance: -0.01 }, "INVALID_CHANCE"],
  ["probability above one", { prime_chance: 1.01 }, "INVALID_CHANCE"],
  ["non-number probability", { prime_chance: "0.10" }, "INVALID_CHANCE"],
  ["UUID instead of a Steam ID (MOD 0.1.0)", { player_id: randomUUID() }, "INVALID_PLAYER"],
  ["Steam ID one digit short", { player_id: "765611912345678" + "9" }, "INVALID_PLAYER"],
  ["Steam ID one digit long", { player_id: "765611912345678901" }, "INVALID_PLAYER"],
  ["Steam ID outside the individual-account range", { player_id: "76561201234567890" }, "INVALID_PLAYER"],
  ["Steam ID as a number", { player_id: 76561198000000000 }, "INVALID_PLAYER"],
  ["short key", { player_key: "abcd" }, "INVALID_KEY"],
  ["missing version", { mod_version: "" }, "INVALID_VERSION"],
  ["non-string name", { name: 123 }, "INVALID_NAME"],
]) {
  test(`rejects ${label} and retains only rejection reason/time`, async () => {
    const result = await request("/v1/scores", player(fields));
    assert.equal(result.status, 400);
    assert.deepEqual(result.body, { ok: false, error });
    assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM players").first()).n, 0);
    const records = (await db.prepare("SELECT * FROM submissions").all()).results;
    assert.equal(records.length, 1);
    assert.equal(records[0].reason, error);
    assert.equal(records[0].accepted, 0);
    for (const field of ["player_id", "score", "duration_s", "mod_version"]) assert.equal(records[0][field], null);
  });
}
test("zero and the allowed score-rate boundary are accepted", async () => {
  for (const p of [player({ score: 0, duration_s: 10 }), player({ score: 500, duration_s: 10 }),
    player({ score: 100, duration_s: 86400, prime_chance: 0.1009 })]) {
    assert.equal((await request("/v1/scores", p)).status, 200);
  }
});
// The chance climbs with the prime level during a run (mod spec §10); no chance is turned away
// for being some other number (commander 2026-10-31), only one that is not a probability at all.
test("every prime level's chance and the old fixed 10% are accepted", async () => {
  for (const [i, prime_chance] of [0.10, 0.11, 0.13, 0.17, 0.19, 0.23, 0.29, 0.31, 0, 1].entries()) {
    const result = await request("/v1/scores", player({ score: 100 + i * 2, prime_chance }));
    assert.equal(result.status, 200, `prime_chance ${prime_chance}: ${JSON.stringify(result.body)}`);
  }
});
test("names lose controls and trim to 24 Unicode characters; empty names become anon", async () => {
  for (const name of [" \n  ", "  hi\n\tthere  ", "🍀".repeat(25)]) {
    assert.equal((await request("/v1/scores", player({ name }))).status, 200);
  }
  const result = await request("/v1/leaderboard?mod=prime_sobo");
  assert.deepEqual(result.body.entries.map(e => e.name), ["anon", "hithere", "🍀".repeat(24)]);
});
test("names drop line separators and lone surrogates and lose whitespace exposed by the 24-character cut", async () => {
  for (const [name, score] of [["a".repeat(23) + " b", 300], ["x y z", 200], ["lone\ud800x", 100]]) {
    assert.equal((await request("/v1/scores", player({ name, score }))).status, 200);
  }
  const result = await request("/v1/leaderboard?mod=prime_sobo");
  assert.deepEqual(result.body.entries.map(e => e.name), ["a".repeat(23), "xyz", "lonex"]);
});
test("a different key cannot change another player's name/best or consume their player slot", async () => {
  const p = player();
  assert.equal((await request("/v1/scores", p)).status, 200);
  await db.prepare("DELETE FROM rate WHERE key LIKE 'player:%'").run();
  const denied = await request("/v1/scores", { ...p, player_key: randomBytes(32).toString("hex"), score: 200, name: "intruder" });
  assert.equal(denied.status, 403);
  assert.deepEqual(denied.body, { ok: false, error: "KEY_MISMATCH" });
  assert.equal((await request("/v1/scores", { ...p, score: 150 })).status, 200);
  const top = await request("/v1/leaderboard?mod=prime_sobo");
  assert.equal(top.body.entries[0].best, 150);
  assert.equal(top.body.entries[0].name, "player");
});
test("concurrent first submissions with different keys bind the player to exactly one key", async () => {
  const id = steamId();
  const contenders = Array.from({ length: 6 }, (_, i) => player({ player_id: id, name: `k${i}` }));
  const results = await Promise.all(contenders.map(p => request("/v1/scores", p)));
  const winners = results.flatMap((r, i) => r.status === 200 ? [i] : []);
  assert.equal(winners.length, 1);
  assert.ok(results.every((r, i) => i === winners[0] || (r.status === 403 && r.body.error === "KEY_MISMATCH")));
  const row = await db.prepare("SELECT key_hash, name FROM players WHERE player_id=?").bind(id).first();
  assert.equal(row.key_hash, createHash("sha256").update(contenders[winners[0]].player_key).digest("hex"));
  assert.equal(row.name, contenders[winners[0]].name);
});
test("20-second player rate limit is atomic for concurrent submissions", async () => {
  const p = player();
  const result = await Promise.all(Array.from({ length: 8 }, () => request("/v1/scores", p)));
  assert.equal(result.filter(r => r.status === 200).length, 1);
  assert.equal(result.filter(r => r.status === 429 && r.body.error === "PLAYER_RATE").length, 7);
  assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM submissions WHERE accepted=1").first()).n, 1);
});
test("a player's rate window opens after 20 seconds and lower scores preserve the original best time", async () => {
  const p = player({ score: 200 });
  assert.equal((await request("/v1/scores", p)).status, 200);
  const original = await db.prepare("SELECT best_at FROM players WHERE player_id=?").bind(p.player_id).first();
  await db.prepare("UPDATE rate SET window_start=window_start-20001 WHERE key LIKE 'player:%'").run();
  const result = await request("/v1/scores", { ...p, score: 50 });
  assert.deepEqual(result.body, { ok: true, rank: 1, best: 200, players: 1 });
  assert.deepEqual(await db.prepare("SELECT best_at FROM players WHERE player_id=?").bind(p.player_id).first(), original);
});
async function storedRows() {
  return Promise.all(["players", "submissions", "rate"].map(async table =>
    (await db.prepare(`SELECT * FROM ${table} ORDER BY 1`).all()).results));
}

test("native POST limit rejects request 11 before any D1 write and isolates IPs", async () => {
  for (let i = 0; i < 10; i++) assert.equal((await request("/v1/scores", player())).status, 200);
  const before = await storedRows();
  const denied = await request("/v1/scores", player());
  assert.equal(denied.status, 429);
  assert.equal(denied.body.error, "IP_RATE");
  assert.deepEqual(await storedRows(), before);
  assert.equal((await request("/v1/scores", player(), "127.0.0.2")).status, 200);
  assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM rate WHERE key LIKE 'ip:%'").first()).n, 0);
});

test("native POST limit includes invalid bodies and rejects without touching unavailable D1", async () => {
  for (let i = 0; i < 10; i++) assert.equal((await request("/v1/scores", player({ score: -2 }))).status, 400);
  const before = await storedRows();
  await db.prepare("ALTER TABLE submissions RENAME TO submissions_unavailable").run();
  try {
    const denied = await request("/v1/scores", player({ score: -2 }));
    assert.equal(denied.status, 429);
    assert.equal(denied.body.error, "IP_RATE");
  } finally { await db.prepare("ALTER TABLE submissions_unavailable RENAME TO submissions").run(); }
  assert.deepEqual(await storedRows(), before);
});

test("native GET limit includes valid and invalid reads, has a separate POST budget", async () => {
  for (let i = 0; i < 60; i++) {
    const valid = i < 30;
    assert.equal((await request(`/v1/leaderboard?mod=${valid ? "prime_sobo" : "other"}`)).status, valid ? 200 : 400);
  }
  const before = await storedRows();
  const denied = await request("/v1/leaderboard?mod=prime_sobo");
  assert.equal(denied.status, 429);
  assert.equal(denied.body.error, "IP_RATE");
  assert.deepEqual(await storedRows(), before);
  assert.equal((await request("/v1/health", undefined, "127.0.0.2")).status, 200);
  assert.equal((await request("/v1/scores", player())).status, 200);
});

test("no plaintext keys or IP are persisted or exposed by the public leaderboard", async () => {
  const p = player();
  await request("/v1/scores", p);
  const record = await db.prepare("SELECT * FROM players").first();
  assert.equal(record.key_hash.length, 64);
  assert.notEqual(record.key_hash, p.player_key);
  const rates = (await db.prepare("SELECT * FROM rate").all()).results;
  assert.ok(rates.every(r => r.key.startsWith("player:")));
  const text = JSON.stringify({ rates, record, public: (await request("/v1/leaderboard?mod=prime_sobo")).body });
  assert.ok(!text.includes("127.0.0.1"));
  assert.ok(!text.includes(p.player_key));
  const top = (await request("/v1/leaderboard?mod=prime_sobo")).body.entries[0];
  assert.deepEqual(Object.keys(top).sort(), ["best", "name", "rank", "steam_id"]);
  assert.equal(top.steam_id, p.player_id);
});
for (const query of ["mod=other", "mod=prime_sobo&limit=0", "mod=prime_sobo&limit=51", "mod=prime_sobo&limit=1.5",
  "mod=prime_sobo&limit=1e1", "mod=prime_sobo&limit=NaN"]) {
  test(`rejects invalid leaderboard query ${query}`, async () => {
    assert.equal((await request(`/v1/leaderboard?${query}`)).status, 400);
  });
}
// Scores-screen paging (offset). Distinct IPs keep 12 real POSTs under the native per-IP limit.
async function twelvePlayers() {
  for (let i = 0; i < 12; i++) {
    assert.equal((await request("/v1/scores", player({ name: `p${i}`, score: 1000 + i * 2, duration_s: 100 }), `127.0.1.${i + 1}`)).status, 200);
  }
}
test("leaderboard offset skips earlier ranks and numbers rows from offset + 1", async () => {
  await twelvePlayers();
  const second = await request("/v1/leaderboard?mod=prime_sobo&limit=10&offset=10");
  assert.equal(second.status, 200);
  assert.deepEqual(second.body.entries.map(e => [e.rank, e.name, e.best]), [[11, "p1", 1002], [12, "p0", 1000]]);
  assert.equal(second.body.players, 12);
  for (const e of second.body.entries) assert.deepEqual(Object.keys(e).sort(), ["best", "name", "rank", "steam_id"]);
  const first = await request("/v1/leaderboard?mod=prime_sobo&limit=10&offset=0");
  assert.deepEqual(first.body.entries.map(e => [e.rank, e.name]), Array.from({ length: 10 }, (_, i) => [i + 1, `p${11 - i}`]));
  const past = await request("/v1/leaderboard?mod=prime_sobo&limit=10&offset=10000");
  assert.equal(past.status, 200);
  assert.deepEqual(past.body, { ok: true, entries: [], players: 12 });
});
test("a missing offset is 0", async () => {
  await twelvePlayers();
  const missing = await request("/v1/leaderboard?mod=prime_sobo&limit=3");
  assert.deepEqual(missing.body.entries.map(e => [e.rank, e.name]), [[1, "p11"], [2, "p10"], [3, "p9"]]);
});
for (const offset of ["-1", "10001", "1.5", "abc", "1e1", "", "0x1"]) {
  test(`rejects leaderboard offset "${offset}" without rounding`, async () => {
    const result = await request(`/v1/leaderboard?mod=prime_sobo&limit=10&offset=${offset}`);
    assert.equal(result.status, 400);
    assert.deepEqual(result.body, { ok: false, error: "INVALID_QUERY" });
  });
}
test("offset pages read before a submission are not reused: every page and count is new", async () => {
  await request("/v1/scores", player({ name: "upper", score: 200 }));
  await request("/v1/scores", player({ name: "lower", score: 100 }));
  const top = await request("/v1/leaderboard?mod=prime_sobo&limit=1&offset=0");
  assert.deepEqual(top.body.entries.map(e => [e.rank, e.name]), [[1, "upper"]]);
  const next = await request("/v1/leaderboard?mod=prime_sobo&limit=1&offset=1");
  assert.equal(next.headers.get("cache-control"), "no-store");
  assert.deepEqual(next.body.entries.map(e => [e.rank, e.name]), [[2, "lower"]]);
  // A new leader moves everyone down at once, on pages that were read before (offset given or not).
  const leader = player({ name: "late leader", score: 300 });
  await request("/v1/scores", leader);
  const topAfter = await request("/v1/leaderboard?mod=prime_sobo&limit=1");
  assert.deepEqual(topAfter.body, { ok: true, entries: [{ rank: 1, steam_id: leader.player_id, name: "late leader", best: 300 }], players: 3 });
  const nextAfter = await request("/v1/leaderboard?mod=prime_sobo&limit=1&offset=1");
  assert.deepEqual(nextAfter.body, { ok: true, entries: [{ rank: 2, steam_id: top.body.entries[0].steam_id, name: "upper", best: 200 }], players: 3 });
});
test("rejected leaderboard reads are not written as score submissions", async () => {
  for (const path of ["/v1/leaderboard?mod=other", "/v1/leaderboard?mod=prime_sobo&limit=0",
    "/v1/leaderboard/around?mod=prime_sobo&player_id=nope"]) {
    assert.equal((await request(path)).status, 400);
  }
  assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM submissions").first()).n, 0);
});
test("around rejects invalid IDs/spans and distinguishes an unknown player", async () => {
  assert.equal((await request("/v1/leaderboard/around?mod=prime_sobo&player_id=nope")).status, 400);
  // The player is a Steam ID now; a 0.1.0 UUID is no longer a player.
  const uuid = await request(`/v1/leaderboard/around?mod=prime_sobo&player_id=${randomUUID()}`);
  assert.deepEqual([uuid.status, uuid.body], [400, { ok: false, error: "INVALID_PLAYER" }]);
  const id = steamId();
  assert.equal((await request(`/v1/leaderboard/around?mod=prime_sobo&player_id=${id}&span=25`)).status, 400);
  assert.equal((await request(`/v1/leaderboard/around?mod=prime_sobo&player_id=${id}`)).status, 404);
});
// Friends only (spec §2): the MOD passes the player's and their Steam friends' Steam IDs, like the
// game's FRIENDS download of its Steam leaderboard.
test("friends lists only the given players on the board, best first, with their world rank", async () => {
  const ids = [];
  for (const [name, score] of [["w1", 600], ["friendA", 500], ["w3", 400], ["me", 300], ["friendB", 200]]) {
    const p = player({ name, score });
    assert.equal((await request("/v1/scores", p)).status, 200);
    ids.push(p.player_id);
  }
  const [, friendA, , me, friendB] = ids;
  const stranger = steamId();
  const result = await request(`/v1/leaderboard/friends?mod=prime_sobo&ids=${[friendB, me, stranger, friendA].join(",")}`);
  assert.equal(result.status, 200);
  assert.equal(result.headers.get("cache-control"), "no-store");
  assert.deepEqual(result.body, { ok: true, entries: [
    { rank: 2, steam_id: friendA, name: "friendA", best: 500 },
    { rank: 4, steam_id: me, name: "me", best: 300 },
    { rank: 5, steam_id: friendB, name: "friendB", best: 200 },
  ] });
  // Nobody on the board: an empty list, not an error.
  assert.deepEqual((await request(`/v1/leaderboard/friends?mod=prime_sobo&ids=${stranger}`)).body, { ok: true, entries: [] });
});
test("friends accepts 100 Steam IDs and counts no reads as submissions", async () => {
  const ids = Array.from({ length: 100 }, () => steamId());
  const result = await request(`/v1/leaderboard/friends?mod=prime_sobo&ids=${ids.join(",")}`);
  assert.deepEqual([result.status, result.body], [200, { ok: true, entries: [] }]);
  assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM submissions").first()).n, 0);
});
for (const [label, query] of [
  ["missing ids", "mod=prime_sobo"],
  ["empty ids", "mod=prime_sobo&ids="],
  ["101 ids", `mod=prime_sobo&ids=${Array.from({ length: 101 }, () => "76561198000000000").join(",")}`],
  ["a UUID among the ids", `mod=prime_sobo&ids=76561198000000000,${"00000000-0000-4000-8000-000000000000"}`],
  ["an empty id between commas", "mod=prime_sobo&ids=76561198000000000,,76561198000000001"],
  ["a short Steam ID", "mod=prime_sobo&ids=7656119800000000"],
]) {
  test(`friends rejects ${label} with INVALID_QUERY`, async () => {
    const result = await request(`/v1/leaderboard/friends?${query}`);
    assert.deepEqual([result.status, result.body], [400, { ok: false, error: "INVALID_QUERY" }]);
    assert.equal((await db.prepare("SELECT COUNT(*) AS n FROM submissions").first()).n, 0);
  });
}
test("friends without the mod is INVALID_MOD", async () => {
  const result = await request("/v1/leaderboard/friends?ids=76561198000000000");
  assert.deepEqual([result.status, result.body], [400, { ok: false, error: "INVALID_MOD" }]);
});
test("malformed JSON, an oversized body and a wrong content type receive bounded 4xx errors", async () => {
  for (const [body, contentType, status, error] of [["{", "application/json", 400, "INVALID_JSON"],
    ["x".repeat(5000), "application/json", 413, "BODY_TOO_LARGE"], ["{}", "text/plain", 415, "CONTENT_TYPE"]]) {
    const response = await fetch(new URL("/v1/scores", base), { method: "POST",
      headers: { "content-type": contentType, "CF-Connecting-IP": "127.0.0.1" }, body });
    assert.equal(response.status, status);
    assert.deepEqual(await response.json(), { ok: false, error });
  }
});
test("failure to persist a rejection still returns generic JSON instead of an internal exception", async () => {
  await db.prepare("ALTER TABLE submissions RENAME TO submissions_unavailable").run();
  try {
    const response = await fetch(new URL("/v1/scores", base), { method: "POST",
      headers: { "content-type": "application/json", "CF-Connecting-IP": "127.0.0.1" }, body: "{" });
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { ok: false, error: "SERVER_ERROR" });
  } finally { await db.prepare("ALTER TABLE submissions_unavailable RENAME TO submissions").run(); }
});
test("scheduled maintenance expires short-lived rates and 30-day submission diagnostics", async () => {
  const now = Date.now();
  await db.batch([
    db.prepare("INSERT INTO rate VALUES('player:older',?,1)").bind(now - 3600001),
    db.prepare("INSERT INTO rate VALUES('player:expired',?,1)").bind(now - 20001),
    db.prepare("INSERT INTO rate VALUES('player:current',?,1)").bind(now),
    db.prepare("INSERT INTO submissions(id,accepted,reason,created_at) VALUES('expired',0,'INVALID_SCORE',?)").bind(now - 31 * 86400000),
    db.prepare("INSERT INTO submissions(id,accepted,reason,created_at) VALUES('current',0,'INVALID_SCORE',?)").bind(now),
  ]);
  await server.getWorker().scheduled({ cron: "*/15 * * * *", scheduledTime: new Date() });
  assert.deepEqual((await db.prepare("SELECT key FROM rate ORDER BY key").all()).results.map(r => r.key), ["player:current"]);
  assert.deepEqual((await db.prepare("SELECT id FROM submissions ORDER BY id").all()).results.map(r => r.id), ["current"]);
});
test("leaderboard is never reused: no-store, and a GET right after a POST has the new rows and players", async () => {
  // Spec §7 (2026-10-30 11:50): the scores screen counts pages from players like the game's own
  // screen, so a public answer must never be served again (11:48 on the game: players=1 stuck).
  const path = "/v1/leaderboard?mod=prime_sobo&limit=1";
  const original = player({ name: "original", score: 100 });
  await request("/v1/scores", original);
  const first = await request(path);
  assert.equal(first.status, 200);
  assert.equal(first.headers.get("cache-control"), "no-store");
  assert.deepEqual(first.body, { ok: true, entries: [{ rank: 1, steam_id: original.player_id, name: "original", best: 100 }], players: 1 });
  const leader = player({ name: "new leader", score: 200 });
  await request("/v1/scores", leader);
  const after = await request(path);
  assert.equal(after.headers.get("cache-control"), "no-store");
  assert.deepEqual(after.body, { ok: true, entries: [{ rank: 1, steam_id: leader.player_id, name: "new leader", best: 200 }], players: 2 });
  // Extra parameters and cookies neither change the answer nor reach a stored copy.
  const ignored = await fetch(new URL(path + "&ignored=value", base), { headers: { Cookie: "untrusted=value", "CF-Connecting-IP": "127.0.0.1" } });
  assert.equal(ignored.headers.get("cache-control"), "no-store");
  assert.deepEqual(await ignored.json(), after.body);
  const otherLimit = await request("/v1/leaderboard?mod=prime_sobo&limit=2");
  assert.deepEqual(otherLimit.body.entries.map(e => e.name), ["new leader", "original"]);
});
