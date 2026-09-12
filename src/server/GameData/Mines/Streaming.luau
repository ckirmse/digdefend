--!strict

-- How the generated mine reaches clients and how they render it (M17). The
-- server sends these to the client in the mine header, so the client never
-- requires GameData.
return {
	-- encoded bytes per NotifyMineChunk message and the pause between chunks,
	-- so a low-bandwidth phone receives the mine over several frames
	CHUNK_BYTES = 4096,
	CHUNK_INTERVAL_SEC = 0.05,
	-- clients render exposed blocks within this many blocks of the player
	-- (Chebyshev distance), rechecked when the player changes cell
	STREAM_RADIUS_BLOCKS = 24,
	-- hard cap on rendered block parts per client; nearest win
	MAX_RENDERED_BLOCKS = 6000,
	-- how often a client checks whether the player moved to a new cell
	STREAM_POLL_SEC = 0.2,
}
