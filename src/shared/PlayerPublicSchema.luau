--!strict

-- Maps a server-side snapshot of one player onto the attribute sets the
-- SplendidGames tree carries: the public AllPlayers entry every client sees,
-- and the private CurrentPlayer folder only that player sees. Pure so the
-- public/private split is unit tested.
local Attributes = require(script.Parent.Attributes)
local Enums = require(script.Parent.Enums)

local PlayerPublicSchema = {}

export type Snapshot = {
	userId: number,
	displayName: string,
	isReady: boolean,
	isAdmin: boolean?,
	cash: number?,
	-- LoadoutSlot key name -> unlock name
	loadout: { [string]: string }?,
	dailyRewardLastClaimedDay: number?,
	dailyRewardNextClaimTime: number?,
}

type AttributeMap = { [string]: any }

-- attribute name for each loadout slot, keyed by the slot's enum value
local LOADOUT_ATTRIBUTE_BY_SLOT: { [number]: string } = {
	[Enums.LoadoutSlot.WEAPON] = Attributes.LOADOUT_WEAPON,
	[Enums.LoadoutSlot.POST] = Attributes.LOADOUT_POST,
	[Enums.LoadoutSlot.DEFENSE_1] = Attributes.LOADOUT_DEFENSE_1,
	[Enums.LoadoutSlot.DEFENSE_2] = Attributes.LOADOUT_DEFENSE_2,
	[Enums.LoadoutSlot.DEFENSE_3] = Attributes.LOADOUT_DEFENSE_3,
}

function PlayerPublicSchema.getLoadoutAttribute(slot: number): string?
	return LOADOUT_ATTRIBUTE_BY_SLOT[slot]
end

-- public state every client sees for a player (one AllPlayers entry); balances
-- and flags stay private by decision
function PlayerPublicSchema.buildPublicAttributes(snapshot: Snapshot): AttributeMap
	return {
		[Attributes.USER_ID] = snapshot.userId,
		[Attributes.DISPLAY_NAME] = snapshot.displayName,
		[Attributes.IS_READY] = snapshot.isReady,
	}
end

-- private per-player state (CurrentPlayer attributes); marker-folder sets
-- (owned unlocks, completions) are children, not attributes
function PlayerPublicSchema.buildCurrentPlayerAttributes(snapshot: Snapshot): AttributeMap
	local attributes: AttributeMap = {
		[Attributes.USER_ID] = snapshot.userId,
		[Attributes.CASH] = snapshot.cash or 0,
		[Attributes.IS_ADMIN] = snapshot.isAdmin or false,
		[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY] = snapshot.dailyRewardLastClaimedDay or 0,
		[Attributes.DAILY_REWARD_NEXT_CLAIM_TIME] = snapshot.dailyRewardNextClaimTime or 0,
	}
	local loadout = snapshot.loadout or {}
	for slot, attributeName in LOADOUT_ATTRIBUTE_BY_SLOT do
		local slotName = Enums.getName(Enums.LoadoutSlot, slot) :: string
		-- "" rather than nil so an emptied slot still overwrites the old value
		attributes[attributeName] = loadout[slotName] or ""
	end
	return attributes
end

return PlayerPublicSchema
