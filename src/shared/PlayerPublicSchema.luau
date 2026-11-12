--!strict

-- Maps a server-side snapshot of one player onto the attribute sets the
-- SplendidGames tree carries: the public AllPlayers entry every client sees,
-- and the private CurrentPlayer folder only that player sees. Pure so the
-- public/private split is unit tested.
local Attributes = require(script.Parent.Attributes)
local ClassSchema = require(script.Parent.ClassSchema)
local CosmeticLoadoutSchema = require(script.Parent.CosmeticLoadoutSchema)
local DailyStoreRules = require(script.Parent.DailyStoreRules)
local Enums = require(script.Parent.Enums)
local GachaRules = require(script.Parent.GachaRules)

local PlayerPublicSchema = {}

export type Snapshot = {
	userId: number,
	displayName: string,
	isReady: boolean,
	isAdmin: boolean?,
	diamonds: number?,
	-- every class record (the Class Menu, 2026-11-04) and the class the
	-- player brings; nil only for a snapshot built before the save loaded
	classRecords: ClassSchema.Records?,
	activeClassKind: number?,
	-- the account's one cosmetic loadout (2026-11-04); nil before the save
	cosmetics: CosmeticLoadoutSchema.Loadout?,
	-- the account's class progress (M70), so a class's open skill slot
	-- count can be read beside its record; nil before the save loaded
	classProgress: GachaRules.Progress?,
	maxSkillSlots: number?,
	keys: number?,
	ownedCosmetics: GachaRules.OwnedCosmetics?,
	-- the class cards bought from the rotating store's current set
	storePurchases: DailyStoreRules.Purchases?,
	hasClaimedGroupReward: boolean?,
	hasClaimedStarterPack: boolean?,
	dailyRewardLastClaimedDay: number?,
	dailyRewardNextClaimTime: number?,
	hasFinishedTutorial: boolean?,
	hasFinishedIronTutorial: boolean?,
	hasFinishedUraniumTutorial: boolean?,
	hasFinishedSupplyCrateTutorial: boolean?,
}

type AttributeMap = { [string]: any }

-- public state every client sees for a player (one AllPlayers entry); balances
-- and flags stay private by decision
function PlayerPublicSchema.buildPublicAttributes(snapshot: Snapshot): AttributeMap
	return {
		[Attributes.USER_ID] = snapshot.userId,
		[Attributes.DISPLAY_NAME] = snapshot.displayName,
		[Attributes.IS_READY] = snapshot.isReady,
	}
end

-- the class the player brings and every class record as one JSON string
-- (ClassSchema codec), on CurrentPlayer: kinds travel as enum values, so
-- the client never sees a save's key names, and nil writes blanks so a
-- cleared value still overwrites the old one. The open skill slots are
-- the account's gacha progress on each class, already replicated
function PlayerPublicSchema.buildClassAttributes(records: ClassSchema.Records?, activeClassKind: number?, maxSkillSlots: number?): AttributeMap
	return {
		[Attributes.ACTIVE_CLASS_KIND] = activeClassKind or 0,
		[Attributes.CLASS_RECORDS] = if records then ClassSchema.encodeRecords(records, maxSkillSlots or 0) else "",
	}
end

-- the cosmetic loadout as one JSON string (CosmeticLoadoutSchema codec)
-- on CurrentPlayer; nil writes blanks so a cleared value still overwrites
function PlayerPublicSchema.buildCosmeticAttributes(cosmetics: CosmeticLoadoutSchema.Loadout?): AttributeMap
	return {
		[Attributes.COSMETICS] = if cosmetics then CosmeticLoadoutSchema.encode(cosmetics) else "",
	}
end

-- the account's gacha state (M70): the Keys balance, the class progress
-- map, and the owned cosmetics, each private to the player
function PlayerPublicSchema.buildGachaAttributes(snapshot: Snapshot): AttributeMap
	return {
		[Attributes.KEYS] = snapshot.keys or 0,
		[Attributes.CLASS_PROGRESS] = GachaRules.encodeProgress(snapshot.classProgress or {}),
		[Attributes.OWNED_COSMETICS] = GachaRules.encodeOwnedCosmetics(snapshot.ownedCosmetics or {}),
		[Attributes.STORE_PURCHASES] = DailyStoreRules.encodePurchases(snapshot.storePurchases or DailyStoreRules.getDefaultPurchases()),
	}
end

-- private per-player state (CurrentPlayer attributes); marker-folder sets
-- (completions) are children, not attributes
function PlayerPublicSchema.buildCurrentPlayerAttributes(snapshot: Snapshot): AttributeMap
	local attributes: AttributeMap = {
		[Attributes.USER_ID] = snapshot.userId,
		[Attributes.DIAMONDS] = snapshot.diamonds or 0,
		[Attributes.IS_ADMIN] = snapshot.isAdmin or false,
		[Attributes.HAS_FINISHED_TUTORIAL] = snapshot.hasFinishedTutorial or false,
		[Attributes.HAS_FINISHED_IRON_TUTORIAL] = snapshot.hasFinishedIronTutorial or false,
		[Attributes.HAS_FINISHED_URANIUM_TUTORIAL] = snapshot.hasFinishedUraniumTutorial or false,
		[Attributes.HAS_FINISHED_SUPPLY_CRATE_TUTORIAL] = snapshot.hasFinishedSupplyCrateTutorial or false,
		[Attributes.HAS_CLAIMED_GROUP_REWARD] = snapshot.hasClaimedGroupReward or false,
		[Attributes.HAS_CLAIMED_STARTER_PACK] = snapshot.hasClaimedStarterPack or false,
		[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY] = snapshot.dailyRewardLastClaimedDay or 0,
		[Attributes.DAILY_REWARD_NEXT_CLAIM_TIME] = snapshot.dailyRewardNextClaimTime or 0,
	}
	for name, value in PlayerPublicSchema.buildGachaAttributes(snapshot) do
		attributes[name] = value
	end
	for name, value in PlayerPublicSchema.buildClassAttributes(snapshot.classRecords, snapshot.activeClassKind, snapshot.maxSkillSlots) do
		attributes[name] = value
	end
	for name, value in PlayerPublicSchema.buildCosmeticAttributes(snapshot.cosmetics) do
		attributes[name] = value
	end
	return attributes
end

-- the Enums.ClassKind value a save's class name means, for the snapshot
function PlayerPublicSchema.classKindOf(className: string?): number
	if not className then
		return 0
	end
	return Enums.getValueByName(Enums.ClassKind, className) or 0
end

return PlayerPublicSchema
