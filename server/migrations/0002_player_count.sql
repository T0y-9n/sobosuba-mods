-- The board's size in one row, so a read does not count every player (D1 bills rows read).
CREATE TABLE player_count (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  n INTEGER NOT NULL
);
INSERT INTO player_count(id, n) SELECT 1, COUNT(*) FROM players;
CREATE TRIGGER player_count_insert AFTER INSERT ON players
BEGIN
  UPDATE player_count SET n = n + 1 WHERE id = 1;
END;
CREATE TRIGGER player_count_delete AFTER DELETE ON players
BEGIN
  UPDATE player_count SET n = n - 1 WHERE id = 1;
END;
