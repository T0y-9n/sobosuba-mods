// Reads of the ranking. Each answer carries rows_read, what D1's free plan counts per day (spec: limits).
// The order is best DESC, best_at, player_id, the players_ranking index. Ranks come from counting the
// index entries ahead, and neighbours from walking the index both ways. A rank reads about one row per
// player ahead (last place reads the whole board once), and the player count reads one row.
export interface Entry { player_id: string; name: string; best: number; rank: number }
interface Read { rows_read: number }
interface Place { player_id: string; name: string; best: number; best_at: number }
const order = "ORDER BY best DESC, best_at, player_id";
// Index entries before / after the player (?1 best, ?2 best_at, ?3 player_id), as range scans on best.
const ahead = "best >= ?1 AND NOT (best = ?1 AND (best_at > ?2 OR (best_at = ?2 AND player_id >= ?3)))";
const behind = "best <= ?1 AND NOT (best = ?1 AND (best_at < ?2 OR (best_at = ?2 AND player_id <= ?3)))";
const ranking = `SELECT player_id, name, best,
  ROW_NUMBER() OVER (${order}) AS rank FROM players`;

async function all<T>(statement: D1PreparedStatement, read: Read): Promise<T[]> {
  const result = await statement.all<T>();
  read.rows_read += result.meta.rows_read;
  return result.results;
}
export async function players(db: D1Database): Promise<{ players: number } & Read> {
  const read = { rows_read: 0 };
  const [count] = await all<{ n: number }>(db.prepare("SELECT n FROM player_count WHERE id = 1"), read);
  return { players: count.n, ...read };
}
async function place(db: D1Database, id: string, read: Read): Promise<{ me: Place; rank: number } | null> {
  const [me] = await all<Place>(db.prepare("SELECT player_id, name, best, best_at FROM players WHERE player_id = ?").bind(id), read);
  if (!me) return null;
  const [before] = await all<{ n: number }>(db.prepare(`SELECT COUNT(*) AS n FROM players WHERE ${ahead}`)
    .bind(me.best, me.best_at, me.player_id), read);
  return { me, rank: before.n + 1 };
}
const entry = (p: Place, rank: number): Entry => ({ player_id: p.player_id, name: p.name, best: p.best, rank });
export async function position(db: D1Database, id: string): Promise<{ row: Entry | null; players: number } & Read> {
  const read = { rows_read: 0 };
  const placed = await place(db, id, read);
  const count = await players(db);
  return { row: placed && entry(placed.me, placed.rank), players: count.players, rows_read: read.rows_read + count.rows_read };
}
export async function page(db: D1Database, limit: number, offset: number): Promise<{ entries: Entry[]; players: number } & Read> {
  const read = { rows_read: 0 };
  const list = await all<Omit<Entry, "rank">>(db.prepare(`SELECT player_id, name, best FROM players ${order} LIMIT ? OFFSET ?`)
    .bind(limit, offset), read);
  const count = await players(db);
  return { entries: list.map((e, i) => ({ ...e, rank: offset + 1 + i })), players: count.players, rows_read: read.rows_read + count.rows_read };
}
// The player's row and span rows on each side; null when the player is not on the board.
export async function around(db: D1Database, id: string, span: number): Promise<({ entries: Entry[]; rank: number; players: number } & Read) | null> {
  const read = { rows_read: 0 };
  const placed = await place(db, id, read);
  if (!placed) return null;
  const { me, rank } = placed;
  const binds = [me.best, me.best_at, me.player_id, span];
  const up = await all<Omit<Entry, "rank">>(db.prepare(`SELECT player_id, name, best FROM players WHERE ${ahead}
    ORDER BY best ASC, best_at DESC, player_id DESC LIMIT ?4`).bind(...binds), read);
  const down = await all<Omit<Entry, "rank">>(db.prepare(`SELECT player_id, name, best FROM players WHERE ${behind} ${order} LIMIT ?4`)
    .bind(...binds), read);
  const count = await players(db);
  const entries = [...up.map((e, i) => ({ ...e, rank: rank - 1 - i })).reverse(), entry(me, rank), ...down.map((e, i) => ({ ...e, rank: rank + 1 + i }))];
  return { entries, rank, players: count.players, rows_read: read.rows_read + count.rows_read };
}
// Up to 100 listed players: one pass of ROW_NUMBER is cheaper than counting ahead for each of them.
export async function friends(db: D1Database, ids: string[]): Promise<{ entries: Entry[] } & Read> {
  const read = { rows_read: 0 };
  const entries = await all<Entry>(db.prepare(`SELECT * FROM (${ranking}) WHERE player_id IN (SELECT value FROM json_each(?)) ORDER BY rank`)
    .bind(JSON.stringify(ids)), read);
  return { entries, ...read };
}
