-- Per-player token bucket that meters every message on the single RemoteEvent.
-- A message spends its handler's cost (default below); the bucket refills
-- continuously up to capacity. Costs are declared per handler so expensive
-- work can be charged more than the message size alone suggests.
return {
	RATE_LIMIT_CAPACITY = 30,
	RATE_LIMIT_REFILL_PER_SEC = 10,
	RATE_LIMIT_DEFAULT_COST = 1,
	RATE_LIMIT_MODERATE_COST = 3,
	RATE_LIMIT_EXPENSIVE_COST = 10,
	-- rejections and drops are reported at most this often per player so an
	-- exploiter cannot turn the warnings themselves into a log flood
	RATE_LIMIT_WARN_INTERVAL_SEC = 5,
}
