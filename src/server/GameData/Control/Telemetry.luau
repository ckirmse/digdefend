--!strict

-- Run records (docs/balance-plan.md, M34, 2026-10-08): one DataStore entry
-- per run holding the run report's numbers with no player identity, so
-- every playthrough can be pulled and averaged. RUN_RECORD_STORE_NAME is a
-- DataStore namespace; bumping it starts an empty store, which is the
-- right move when RunRecordRules.RECORD_VERSION changes shape.
return {
	RUN_RECORD_STORE_NAME = "DigDefendRunRecords_v1",
	RUN_RECORD_KEY_PREFIX = "run_",
	-- the DataStore allows 4,194,304 bytes a key; a 20-day crew-of-six run
	-- is about 150 KB, so a record over this is a bug, not a long run
	MAX_RECORD_BYTES = 1000000,
	-- Studio sessions write too (flagged isStudio) because every playtest
	-- so far is one; API access must be on in the place's settings
	IS_STUDIO_WRITE_ENABLED = true,
	-- a failed write is retried this many times before the dawn gives up;
	-- the next dawn writes the whole record again anyway
	WRITE_ATTEMPTS = 3,
	WRITE_RETRY_SEC = 5,
}
