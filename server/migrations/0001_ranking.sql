CREATE TABLE players (
  player_id TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL,
  name TEXT NOT NULL,
  best INTEGER NOT NULL,
  best_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX players_ranking ON players(best DESC, best_at, player_id);
CREATE TABLE submissions (
  id TEXT PRIMARY KEY,
  player_id TEXT,
  score INTEGER,
  duration_s INTEGER,
  mod_version TEXT,
  accepted INTEGER NOT NULL,
  reason TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX submissions_created ON submissions(created_at);
CREATE TABLE rate (
  key TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
);
CREATE INDEX rate_expiry ON rate(window_start);
