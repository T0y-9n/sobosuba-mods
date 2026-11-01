import { Rejection, readScore, steamId, steamIdList, integerParam } from "./validation";
import { type Entry, position, page, around, friends } from "./board";
interface Env { DB: D1Database; IP_HASH_SECRET: string; POST_RATE: RateLimit; GET_RATE: RateLimit }
function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: {
    "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
  } });
}
async function hash(text: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))))
    .map(b => b.toString(16).padStart(2, "0")).join("");
}
async function frontRate(request: Request, env: Env): Promise<Response | undefined> {
  if (request.method !== "GET" && request.method !== "POST") return;
  const limiter = request.method === "POST" ? env.POST_RATE : env.GET_RATE;
  if (!limiter || !env.IP_HASH_SECRET || env.IP_HASH_SECRET.length < 32) return json({ ok: false, error: "SERVER_CONFIG" }, 503);
  const ip = request.headers.get("CF-Connecting-IP");
  if (!ip) return json({ ok: false, error: "CLIENT_IP_UNAVAILABLE" }, 503);
  // Only a keyed hash enters the short-lived native limiter. No IP accounting in D1.
  const key = await hash(env.IP_HASH_SECRET + ":" + ip);
  if (!(await limiter.limit({ key })).success) return json({ ok: false, error: "IP_RATE" }, 429);
}
// Like a row of the game's Steam leaderboard, a row carries the Steam ID (spec §2).
function publicEntry(entry: Entry) {
  return { rank: entry.rank, steam_id: entry.player_id, name: entry.name, best: entry.best };
}
async function submit(request: Request, env: Env): Promise<Response> {
  const now = Date.now();
  const p = await readScore(request);
  const key = await hash(p.player_key);
  const id = crypto.randomUUID();
  const rateKey = "player:" + p.player_id;
  // D1 batch is a single transaction. The guarded writes decide authorization and
  // the 20-second slot together; a SELECT followed by an unguarded write would race.
  const result = await env.DB.batch([
    env.DB.prepare(`INSERT INTO players(player_id,key_hash,name,best,best_at,created_at) VALUES(?,?,?,0,?,?)
      ON CONFLICT(player_id) DO NOTHING`).bind(p.player_id, key, p.name, now, now),
    env.DB.prepare(`INSERT INTO rate(key,window_start,count)
      SELECT ?,?,1 WHERE EXISTS(SELECT 1 FROM players WHERE player_id=? AND key_hash=?)
      ON CONFLICT(key) DO UPDATE SET
        count=CASE WHEN rate.window_start<=? THEN 1 ELSE rate.count+1 END,
        window_start=CASE WHEN rate.window_start<=? THEN excluded.window_start ELSE rate.window_start END`)
      .bind(rateKey, now, p.player_id, key, now - 20000, now - 20000),
    env.DB.prepare(`INSERT INTO submissions(id,player_id,score,duration_s,mod_version,accepted,created_at)
      SELECT ?,?,?,?,?,1,? WHERE EXISTS(SELECT 1 FROM players WHERE player_id=? AND key_hash=?)
      AND EXISTS(SELECT 1 FROM rate WHERE key=? AND count=1)`)
      .bind(id, p.player_id, p.score, p.duration_s, p.mod_version, now, p.player_id, key, rateKey),
    env.DB.prepare(`UPDATE players SET name=?,
      best_at=CASE WHEN ?>best THEN ? ELSE best_at END, best=MAX(best,?)
      WHERE player_id=? AND EXISTS(SELECT 1 FROM submissions WHERE id=?)`)
      .bind(p.name, p.score, now, p.score, p.player_id, id),
    env.DB.prepare("SELECT key_hash=? AS authorized FROM players WHERE player_id=?").bind(key, p.player_id),
  ]);
  if (!(result[4].results[0] as { authorized: number }).authorized) throw new Rejection("KEY_MISMATCH", 403);
  if (result[2].meta.changes !== 1) throw new Rejection("PLAYER_RATE", 429);
  const placed = await position(env.DB, p.player_id);
  return json({ ok: true, rank: placed.row!.rank, best: placed.row!.best, players: placed.players });
}
async function route(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/v1/health") return json({ ok: true });
    if (request.method === "POST" && url.pathname === "/v1/scores") return submit(request, env);
    if (request.method === "GET" && url.pathname.startsWith("/v1/leaderboard") && url.searchParams.get("mod") !== "prime_sobo")
      throw new Rejection("INVALID_MOD");
    if (request.method === "GET" && url.pathname === "/v1/leaderboard") {
      const limit = integerParam(url.searchParams.get("limit"), 10, 1, 50);
      // Scores-screen paging: rows keep their global rank, starting at offset + 1.
      const offset = integerParam(url.searchParams.get("offset"), 0, 0, 10000);
      // Never reused (spec §7): the scores screen counts pages from players, so every read is fresh
      // from D1 and the answer stays Cache-Control: no-store like every other response.
      const result = await page(env.DB, limit, offset);
      return json({ ok: true, entries: result.entries.map(publicEntry), players: result.players });
    }
    if (request.method === "GET" && url.pathname === "/v1/leaderboard/around") {
      const playerId = url.searchParams.get("player_id") ?? "";
      if (!steamId.test(playerId)) throw new Rejection("INVALID_PLAYER");
      const span = integerParam(url.searchParams.get("span"), 3, 0, 24);
      const result = await around(env.DB, playerId, span);
      if (!result) return json({ ok: false, error: "PLAYER_NOT_FOUND" }, 404);
      return json({ ok: true, entries: result.entries.map(e => ({ ...publicEntry(e), you: e.player_id === playerId })), rank: result.rank, players: result.players });
    }
    if (request.method === "GET" && url.pathname === "/v1/leaderboard/friends") {
      // The game's FRIENDS download: only the listed players on the board, best first, world rank kept.
      const ids = steamIdList(url.searchParams.get("ids"));
      const result = await friends(env.DB, ids);
      return json({ ok: true, entries: result.entries.map(publicEntry) });
    }
    return json({ ok: false, error: "NOT_FOUND" }, 404);
}
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Front-gate failures return here, outside score-rejection persistence.
    try {
      const denied = await frontRate(request, env);
      if (denied) return denied;
    } catch { return json({ ok: false, error: "SERVER_ERROR" }, 503); }
    try { return await route(request, env); }
    catch (error) {
      if (error instanceof Rejection) {
        // Only score-validation/player rejections are diagnostics. Front-gate
        // rejections and all GET errors must never write submissions.
        if (request.method !== "POST" || new URL(request.url).pathname !== "/v1/scores")
          return json({ ok: false, error: error.code }, error.status);
        // Rejected payloads and credential values never enter persistent logs.
        try {
          await env.DB.prepare("INSERT INTO submissions(id,accepted,reason,created_at) VALUES(?,0,?,?)")
            .bind(crypto.randomUUID(), error.code, Date.now()).run();
        } catch { return json({ ok: false, error: "SERVER_ERROR" }, 503); }
        return json({ ok: false, error: error.code }, error.status);
      }
      return json({ ok: false, error: "SERVER_ERROR" }, 503);
    }
  },
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("DELETE FROM rate WHERE window_start<=?").bind(now - 20000),
      env.DB.prepare("DELETE FROM submissions WHERE created_at<?").bind(now - 30 * 86400000),
    ]);
  },
};
