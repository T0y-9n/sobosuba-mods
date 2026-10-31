export interface Score {
  mod: "prime_sobo"; mod_version: string; player_id: string; player_key: string;
  name: string; score: number; duration_s: number; prime_chance: number;
}
export class Rejection extends Error {
  constructor(readonly code: string, readonly status = 400) { super(code); }
}
// A player is a Steam ID: SteamID64 of an individual account, in decimal (spec §3).
export const steamId = /^7656119\d{10}$/;
export function validate(value: unknown): Score {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Rejection("INVALID_BODY");
  const p = value as Record<string, unknown>;
  if (p.mod !== "prime_sobo") throw new Rejection("INVALID_MOD");
  if (typeof p.player_id !== "string" || !steamId.test(p.player_id)) throw new Rejection("INVALID_PLAYER");
  if (typeof p.player_key !== "string" || !/^[0-9a-f]{64}$/.test(p.player_key)) throw new Rejection("INVALID_KEY");
  if (typeof p.mod_version !== "string" || !/^[\w.-]{1,32}$/.test(p.mod_version)) throw new Rejection("INVALID_VERSION");
  if (typeof p.score !== "number" || !Number.isSafeInteger(p.score) || p.score < 0 || p.score > 10000000 || p.score % 2 !== 0)
    throw new Rejection("INVALID_SCORE");
  if (typeof p.duration_s !== "number" || !Number.isSafeInteger(p.duration_s) || p.duration_s < 10 || p.duration_s > 86400)
    throw new Rejection("INVALID_DURATION");
  if (p.score / p.duration_s > 50) throw new Rejection("SCORE_RATE");
  // The chance climbs with the prime level during a run (mod spec §10); any probability is kept.
  if (typeof p.prime_chance !== "number" || !Number.isFinite(p.prime_chance) || p.prime_chance < 0 || p.prime_chance > 1)
    throw new Rejection("INVALID_CHANCE");
  if (typeof p.name !== "string") throw new Rejection("INVALID_NAME");
  // Line/paragraph separators break board rows like controls; lone surrogates cannot be stored as UTF-8.
  // Trim again after the cut so a space at position 24 is not kept as a trailing space.
  const name = Array.from(p.name.replace(/[\p{Cc}\p{Cf}\p{Cs}\p{Zl}\p{Zp}]/gu, "").trim()).slice(0, 24).join("").trim() || "anon";
  return { mod: p.mod, player_id: p.player_id, player_key: p.player_key, mod_version: p.mod_version,
    score: p.score, duration_s: p.duration_s, prime_chance: p.prime_chance, name };
}
export async function readScore(request: Request): Promise<Score> {
  if (request.headers.get("content-type")?.split(";")[0].trim() !== "application/json")
    throw new Rejection("CONTENT_TYPE", 415);
  const reader = request.body?.getReader();
  if (!reader) throw new Rejection("INVALID_JSON");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > 4096) { await reader.cancel(); throw new Rejection("BODY_TOO_LARGE", 413); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  let data: unknown;
  try { data = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes)); }
  catch { throw new Rejection("INVALID_JSON"); }
  return validate(data);
}
// "friends only": the player's and their Steam friends' Steam IDs, 1 to 100, comma separated.
export function steamIdList(value: string | null): string[] {
  const ids = (value ?? "").split(",");
  if (ids.length > 100 || !ids.every(id => steamId.test(id))) throw new Rejection("INVALID_QUERY");
  return ids;
}
export function integerParam(value: string | null, fallback: number, min: number, max: number): number {
  if (value === null) return fallback;
  if (!/^\d+$/.test(value)) throw new Rejection("INVALID_QUERY");
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n < min || n > max) throw new Rejection("INVALID_QUERY");
  return n;
}
