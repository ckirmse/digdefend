--!strict

-- Every message on the single RemoteEvent is named here. Client→server names
-- start with "Try"; server→client names start with "Notify". The prefix is a
-- reminder that clients request and the server decides.
local module

module = {
	TRY_DEV_TOOL = "TryDevTool",
	-- helicopter pad parties (GDD "Helicopter Pads"); joining is by touch, not message
	TRY_CREATE_PARTY = "TryCreateParty",
	TRY_LEAVE_PARTY = "TryLeaveParty",
	TRY_LAUNCH_PARTY = "TryLaunchParty",
	NOTIFY_PLAYER_FEEDBACK = "NotifyPlayerFeedback",
	-- tells one client which pad menu to show (Enums.PartyMenu) and whether it hosts
	NOTIFY_PARTY_MENU = "NotifyPartyMenu",
	-- the generated mine (gameplay place): a header with dimensions, placement,
	-- and chunk count, then the run-length-encoded cells in buffer chunks
	-- (MineGridCodec); a version ties chunks to their header so a regenerate
	-- mid-stream cannot mix two mines
	NOTIFY_MINE_HEADER = "NotifyMineHeader",
	NOTIFY_MINE_CHUNK = "NotifyMineChunk",
	-- the client asks for the mine once its handlers are connected; the server
	-- never pushes it at Ready, because the RemoteEvent does not queue
	-- messages fired before the client connects (that lost the mine on slow loads)
	TRY_REQUEST_MINE = "TryRequestMine",
	-- tools and mining (gameplay place, GDD "Tools" and "Mining Rock")
	TRY_EQUIP_TOOL = "TryEquipTool",
	TRY_HIT_ROCK = "TryHitRock",
	-- every client: a block took damage (crack state) or broke (clear the cell)
	NOTIFY_ROCK_DAMAGED = "NotifyRockDamaged",
	NOTIFY_ROCK_BROKEN = "NotifyRockBroken",
	-- to one client: ore reached their backpack (from a break or a pickup)
	-- with the world position it came from, so its icon flies into the HUD
	-- backpack; the counts themselves arrive as attributes
	NOTIFY_ORE_COLLECTED = "NotifyOreCollected",
	-- to the refining player: what left their backpack (the suck-in), then,
	-- after the grind, what was paid out (the fly-to-HUD); balances arrive as
	-- attributes. Refining itself is a ProximityPrompt trigger, not a message
	NOTIFY_REFINE_STARTED = "NotifyRefineStarted",
	NOTIFY_REFINE_COMPLETED = "NotifyRefineCompleted",
}

return module
