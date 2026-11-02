--!strict

-- Maps a server-side snapshot of one player onto the attribute sets the
-- SplendidGames tree carries: the public AllPlayers entry every client sees,
-- and the private CurrentPlayer folder only that player sees. Pure so the
-- public/private split is unit tested.
local Attributes = require(script.Parent.Attributes)
local CharacterSchema = require(script.Parent.CharacterSchema)
local Enums = require(script.Parent.Enums)
local GachaRules = require(script.Parent.GachaRules)

local PlayerPublicSchema = {}

export type Snapshot = {
	userId: number,
	displayName: string,
	isReady: boolean,
	isAdmin: boolean?,
	diamonds: number?,
	-- the character the player brings (M55); nil only for a snapshot built
	-- before the save loaded
	activeCharacter: CharacterSchema.CharacterSave?,
	-- the account's class progress (M70), so a character's open skill
	-- slot count travels with it; nil before the save loaded
	classProgress: GachaRules.Progress?,
	maxSkillSlots: number?,
	keys: number?,
	ownedCosmetics: GachaRules.OwnedCosmetics?,
	dailyRewardLastClaimedDay: number?,
	dailyRewardNextClaimTime: number?,
}

type AttributeMap = { [string]: any }

-- the two attributes each gear row travels as, by Enums.GearSlot
local GEAR_ATTRIBUTES_BY_SLOT: { [number]: { kind: string, stars: string } } = {
	[Enums.GearSlot.WEAPON] = { kind = Attributes.CHARACTER_WEAPON_KIND, stars = Attributes.CHARACTER_WEAPON_STARS },
	[Enums.GearSlot.POST] = { kind = Attributes.CHARACTER_POST_KIND, stars = Attributes.CHARACTER_POST_STARS },
	[Enums.GearSlot.TOWER_1] = { kind = Attributes.CHARACTER_TOWER_1_KIND, stars = Attributes.CHARACTER_TOWER_1_STARS },
	[Enums.GearSlot.TOWER_2] = { kind = Attributes.CHARACTER_TOWER_2_KIND, stars = Attributes.CHARACTER_TOWER_2_STARS },
}

function PlayerPublicSchema.getGearAttributes(gearSlot: number): (string?, string?)
	local entry = GEAR_ATTRIBUTES_BY_SLOT[gearSlot]
	if not entry then
		return nil, nil
	end
	return entry.kind, entry.stars
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

-- one character as attributes: on CurrentPlayer for the active one, and on
-- its own folder under CurrentPlayer.Characters for every one (M55). Kinds
-- travel as enum values, so the client never sees a save's key names;
-- nil writes blanks, so a cleared value still overwrites the old one. The
-- open skill slots are the account's gacha progress on the record's class
-- (M70), so two characters of one class open together
function PlayerPublicSchema.buildCharacterAttributes(record: CharacterSchema.CharacterSave?, classProgress: GachaRules.Progress?, maxSkillSlots: number?): AttributeMap
	local progress = classProgress or {}
	local slotCount = maxSkillSlots or 0
	local classKind = if record then (Enums.getValueByName(Enums.ClassKind, record.classKind) or 0) else 0
	local attributes: AttributeMap = {
		[Attributes.CHARACTER_ID] = if record then record.id else "",
		[Attributes.CHARACTER_NAME] = if record then record.name else "",
		[Attributes.CHARACTER_NIGHTS_SURVIVED] = if record then record.nightsSurvived else 0,
		[Attributes.CHARACTER_CLASS_KIND] = classKind,
		[Attributes.CHARACTER_SKILL_SLOTS_OPEN] = if record then GachaRules.openSkillSlots(progress, classKind, slotCount) else 0,
		[Attributes.CHARACTER_SKILLS] = if record then CharacterSchema.encodeSkills(record.skills, slotCount) else "",
		[Attributes.CHARACTER_COSMETICS] = if record then CharacterSchema.encodeCosmetics(record.cosmetics) else "",
	}
	for gearSlot, names in GEAR_ATTRIBUTES_BY_SLOT do
		local kind, stars = 0, 0
		if record then
			local resolvedKind, resolvedStars = CharacterSchema.getGear(record, gearSlot)
			kind = resolvedKind or 0
			stars = resolvedStars
		end
		attributes[names.kind] = kind
		attributes[names.stars] = stars
	end
	return attributes
end

-- the account's gacha state (M70): the Keys balance, the class progress
-- map, and the owned cosmetics, each private to the player
function PlayerPublicSchema.buildGachaAttributes(snapshot: Snapshot): AttributeMap
	return {
		[Attributes.KEYS] = snapshot.keys or 0,
		[Attributes.CLASS_PROGRESS] = GachaRules.encodeProgress(snapshot.classProgress or {}),
		[Attributes.OWNED_COSMETICS] = GachaRules.encodeOwnedCosmetics(snapshot.ownedCosmetics or {}),
	}
end

-- private per-player state (CurrentPlayer attributes); marker-folder sets
-- (completions) and the character list are children, not attributes
function PlayerPublicSchema.buildCurrentPlayerAttributes(snapshot: Snapshot): AttributeMap
	local attributes: AttributeMap = {
		[Attributes.USER_ID] = snapshot.userId,
		[Attributes.DIAMONDS] = snapshot.diamonds or 0,
		[Attributes.IS_ADMIN] = snapshot.isAdmin or false,
		[Attributes.DAILY_REWARD_LAST_CLAIMED_DAY] = snapshot.dailyRewardLastClaimedDay or 0,
		[Attributes.DAILY_REWARD_NEXT_CLAIM_TIME] = snapshot.dailyRewardNextClaimTime or 0,
	}
	for name, value in PlayerPublicSchema.buildGachaAttributes(snapshot) do
		attributes[name] = value
	end
	for name, value in PlayerPublicSchema.buildCharacterAttributes(snapshot.activeCharacter, snapshot.classProgress, snapshot.maxSkillSlots) do
		attributes[name] = value
	end
	return attributes
end

return PlayerPublicSchema
