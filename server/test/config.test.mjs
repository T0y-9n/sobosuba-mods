import assert from "node:assert/strict";
import { test } from "node:test";
import { randomBytes, randomInt } from "node:crypto";
import { resolve } from "node:path";
import { createTestHarness } from "wrangler";

test("missing native limiter bindings refuse GET and POST before D1", async () => {
  // A real misconfigured runtime, not a replacement limiter or database.
  const server = createTestHarness({ workers: [{ config: {
    name: "ranking-missing-limiters", main: resolve("src/index.ts"), compatibility_date: "2026-10-29",
    vars: { IP_HASH_SECRET: randomBytes(32).toString("hex") },
    d1_databases: [{ binding: "DB", database_name: "local-config-check", database_id: "local-only", migrations_dir: resolve("migrations") }],
  } }] });
  try {
    const { url } = await server.listen();
    await server.getWorker().applyD1Migrations("DB");
    const get = await fetch(new URL("/v1/leaderboard?mod=prime_sobo", url));
    const post = await fetch(new URL("/v1/scores", url), { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({
      mod: "prime_sobo", mod_version: "0.1.0", player_id: "7656119" + String(randomInt(0, 10_000_000_000)).padStart(10, "0"), player_key: randomBytes(32).toString("hex"),
      name: "config check", score: 100, duration_s: 20, prime_chance: 0.10,
    }) });
    assert.deepEqual([get.status, post.status], [503, 503]);
    assert.deepEqual(await get.json(), { ok: false, error: "SERVER_CONFIG" });
    assert.deepEqual(await post.json(), { ok: false, error: "SERVER_CONFIG" });
    const db = (await server.getWorker().getEnv()).DB;
    for (const table of ["players", "submissions", "rate"]) {
      assert.equal((await db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first()).n, 0);
    }
  } finally { await server.close(); }
});
