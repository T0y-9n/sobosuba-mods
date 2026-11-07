extends RefCounted
## Prime levels (spec §10). The game opens bigger spawns as a run goes on (SpawnPool, seven stages);
## each open stage is one prime level, and the chance of a prime spawn climbs through the primes.

const CHANCES: Array[float] = [0.11, 0.13, 0.17, 0.19, 0.23, 0.29, 0.31]


## The level for the game's current_spawn_pool: how many spawn tiers are open, from 1 to 7.
static func level_of(open_tiers: Array) -> int:
	return clampi(open_tiers.size(), 1, CHANCES.size())


static func chance_of(level: int) -> float:
	return CHANCES[clampi(level, 1, CHANCES.size()) - 1]
