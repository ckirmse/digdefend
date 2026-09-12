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
}

return module
