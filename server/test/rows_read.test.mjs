import assert from "node:assert/strict";
import { before, after, test } from "node:test";
import { randomBytes } from "node:crypto";
import { createTestHarness } from "wrangler";
import { players, position, page, around, friends } from "../src/board.ts";

// D1's free plan counts rows read per day (5 million). A game end reads position, the top 5 and
// around span 2, so those must not read the whole board each time. Real workerd and real local D1.
const N = 3000;
const ranking = `SELECT player_id, name, best,
  ROW_NUMBER() OVER (ORDER BY best DESC, best_at, player_id) AS rank FROM players`;
const sid = i => "7656119" + String(i).padStart(10, "0");
let server, base, db;
before(async () => {
  server = createTestHarness({ workers: [{ configPath: "./wrangler.toml", secrets: { IP_HASH_SECRET: randomBytes(32).toString("hex") } }] });
  base = (await server.listen()).url;
  await server.getWorker().applyD1Migrations("DB");
  db = (await server.getWorker().getEnv()).DB;
  // Ties on purpose: about four players share each best, and best_at repeats every three.
  await db.prepare(`WITH RECURSIVE s(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM s WHERE i+1<?)
    INSERT INTO players(player_id,key_hash,name,best,best_at,created_at)
    SELECT '7656119' || printf('%010d', i), 'x', 'p' || i, ((i * 7919) % ?) * 2, 1000 + (i % 3), 1000 FROM s`).bind(N, N / 4).run();
});
after(async () => { await server.close(); });
const reference = async () => (await db.prepare(ranking).all()).results;
const rows = list => list.map(e => [e.player_id, e.name, e.best, e.rank]);

test("pages, around and friends give the same rows and ranks as ROW_NUMBER, ties included", async () => {
  const board = await reference();
  for (const [limit, offset] of [[5, 0], [10, 0], [10, 1000], [50, N - 3], [10, N]]) {
    assert.deepEqual(rows((await page(db, limit, offset)).entries), rows(board.slice(offset, offset + limit)), `page ${limit} ${offset}`);
  }
  for (const rank of [1, 2, 3, N / 2, N - 1, N]) {
    const id = board[rank - 1].player_id;
    assert.equal((await position(db, id)).row.rank, rank);
    for (const span of [0, 2, 24]) {
      const got = await around(db, id, span);
      assert.equal(got.rank, rank);
      assert.deepEqual(rows(got.entries), rows(board.slice(Math.max(0, rank - 1 - span), rank + span)), `around ${rank} span ${span}`);
    }
  }
  const ids = [board[0], board[N / 2], board[N - 1]].map(e => e.player_id).concat(sid(N + 5));
  assert.deepEqual(rows((await friends(db, ids)).entries), rows([board[0], board[N / 2], board[N - 1]]));
  assert.equal(await around(db, sid(N + 5), 2), null);
  assert.equal((await players(db)).players, N);
});

test("a game end reads about two rows per player ahead, not the whole board", async () => {
  const board = await reference();
  for (const rank of [1, N / 2, N]) {
    const id = board[rank - 1].player_id;
    const read = (await position(db, id)).rows_read + (await page(db, 5, 0)).rows_read + (await around(db, id, 2)).rows_read;
    assert.ok(read <= 2 * rank + 60, `rank ${rank} read ${read} rows (limit ${2 * rank + 60})`);
  }
  assert.ok((await players(db)).rows_read <= 2, "the player count is one row");
  const deep = (await page(db, 10, 1000)).rows_read;
  assert.ok(deep <= 1010 + 20, `a page at offset 1000 read ${deep} rows`);
});

test("the player count follows new players, repeat scores and deleted rows", async () => {
  const count = async () => (await players(db)).players;
  const real = async () => (await db.prepare("SELECT COUNT(*) AS n FROM players").first()).n;
  const p = { mod: "prime_sobo", mod_version: "1.23-1.0.0", player_id: sid(N + 1), player_key: randomBytes(32).toString("hex"),
    name: "new", score: 100, duration_s: 20, prime_chance: 0.11 };
  const post = body => fetch(new URL("/v1/scores", base), { method: "POST",
    headers: { "content-type": "application/json", "CF-Connecting-IP": "127.0.0.1" }, body: JSON.stringify(body) }).then(r => r.json());
  const first = await post(p);
  assert.equal(first.players, await real());
  assert.equal(await count(), await real());
  await db.prepare("DELETE FROM rate").run();
  await post({ ...p, score: 200 });
  assert.equal(await count(), await real(), "a repeat score adds no player");
  await db.prepare("DELETE FROM players WHERE player_id IN (?, ?)").bind(sid(N + 1), sid(0)).run();
  assert.equal(await count(), await real(), "deleted rows leave the count");
});
