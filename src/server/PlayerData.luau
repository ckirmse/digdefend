--!strict

-- The sole owner of one player's persistent state and the only code path that
-- touches ProfileStore. Managers implement business logic; PlayerData is the
-- record of what is true for this player. The lifecycle lives here too, so a
-- system asking "may I act on this player" asks one object.
local HttpService = game:GetService("HttpService")

local ProgressionData = require("@game/ServerScriptService/GameData/Characters/Progression")
local ClassRosterData = require("@game/ServerScriptService/GameData/Classes/Roster")
local HatsData = require("@game/ServerScriptService/GameData/Characters/Hats")
local SkillsData = require("@game/ServerScriptService/GameData/Characters/Skills")
local StarsData = require("@game/ServerScriptService/GameData/Characters/Stars")
local PlayerControlData = require("@game/ServerScriptService/GameData/Control/Player")
local TowersData = require("@game/ServerScriptService/GameData/Defenses/Towers")
local PostWeaponsData = require("@game/ServerScriptService/GameData/Posts/PostWeapons")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")
local CharacterSchema = require("@game/ReplicatedStorage/Shared/CharacterSchema")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerSaveSchema = require("@game/ReplicatedStorage/Shared/PlayerSaveSchema")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local PlayerData = {}
PlayerData.__index = PlayerData

export type SaveData = PlayerSaveSchema.SaveData
export type CharacterSave = CharacterSchema.CharacterSave

export type PlayerData = typeof(setmetatable(
	{} :: {
		player: Player,
		profile: any?,
		lifecycle: number,
		isAdmin: boolean,
		sessionStartTime: number,
		isSaveOnExit: boolean,
		diamonds: number,
		characters: { CharacterSave },
		activeCharacterId: string,
		completions: { [string]: boolean },
		dailyReward: PlayerSaveSchema.DailyRewardSave,
		sessionMeta: PlayerSaveSchema.SessionMetaSave,
		processedPurchaseIds: { string },
		reviveCredits: { [string]: number },
	},
	PlayerData
))

-- every persisted field copies between the save table and this object as-is;
-- adding a field here means adding it to PlayerSaveSchema too
local SAVE_FIELDS = {
	"diamonds",
	"characters",
	"activeCharacterId",
	"completions",
	"dailyReward",
	"sessionMeta",
	"processedPurchaseIds",
	"reviveCredits",
}

local function buildValidSkillIds(): { [string]: boolean }
	local ids = {}
	for id in SkillsData.BY_ID do
		ids[id] = true
	end
	return ids
end

-- the GameData the pure schemas need, gathered once: the character shape
-- (defaults, star bounds, slot thresholds, the skill catalogue's ids) and
-- the account shape around it
local CHARACTER_DEFAULTS: CharacterSchema.Defaults = {
	defaultClassKind = ClassRosterData.DEFAULT_CLASS,
	defaultKindByGearSlot = {
		[Enums.GearSlot.WEAPON] = HandheldData.DEFAULT_WEAPON,
		[Enums.GearSlot.POST] = PostWeaponsData.DEFAULT_POST_WEAPON,
		[Enums.GearSlot.TOWER_1] = TowersData.DEFAULT_TOWER,
		[Enums.GearSlot.TOWER_2] = TowersData.DEFAULT_SECOND_TOWER,
	},
	minStars = StarsData.MIN_STARS,
	maxStars = StarsData.MAX_STARS,
	skillSlotUnlockNights = ProgressionData.SKILL_SLOT_UNLOCK_NIGHTS,
	validSkillIds = buildValidSkillIds(),
	maxNameLength = ProgressionData.MAX_NAME_LENGTH,
	defaultNamePrefix = ProgressionData.DEFAULT_NAME_PREFIX,
	defaultCosmetics = {
		[Enums.getName(Enums.CosmeticSlot, Enums.CosmeticSlot.HELMET) :: string] = HatsData.DEFAULT_HAT_ID,
	},
}

local SCHEMA_DEFAULTS: PlayerSaveSchema.Defaults = {
	startingDiamonds = PlayerControlData.STARTING_DIAMONDS,
	character = CHARACTER_DEFAULTS,
	maxCharacters = ProgressionData.MAX_CHARACTERS,
	generateId = function()
		return HttpService:GenerateGUID(false)
	end,
}

function PlayerData.getDefaultSaveData(): SaveData
	return PlayerSaveSchema.getDefault(SCHEMA_DEFAULTS)
end

-- the character shape's tuning, for managers that reason about a record
-- (open skill slots, star bounds) without requiring GameData themselves
function PlayerData.getCharacterDefaults(): CharacterSchema.Defaults
	return CHARACTER_DEFAULTS
end

function PlayerData.getMaxCharacters(): number
	return SCHEMA_DEFAULTS.maxCharacters
end

function PlayerData:validate(data: any): SaveData
	local validated, repairs = PlayerSaveSchema.validate(data, SCHEMA_DEFAULTS)
	for _, repair in repairs do
		warn("PlayerData: repaired save for", self.player.Name, "-", repair)
	end
	return validated
end

function PlayerData:loadSaveData(data: SaveData)
	-- deep copy so live session state never aliases profile.Data; the profile
	-- only learns about changes when a save explicitly copies state in
	local copied = utils.deepCopy(data) :: any
	local selfAny = self :: any
	for _, field in SAVE_FIELDS do
		selfAny[field] = copied[field]
	end

	local now = workspace:GetServerTimeNow()
	if self.sessionMeta.creationTime == 0 then
		self.sessionMeta.creationTime = math.floor(now)
	end
	self.sessionMeta.sessions += 1
	self.sessionStartTime = now
end

function PlayerData:getSaveData(): SaveData
	local now = workspace:GetServerTimeNow()
	-- snapshot the session so far and restart the clock so repeated saves
	-- never double-count; floor because the schema validates integers
	self.sessionMeta.totalPlaySec = math.floor(self.sessionMeta.totalPlaySec + (now - self.sessionStartTime))
	self.sessionStartTime = now
	self.sessionMeta.saveTime = math.floor(now)

	local selfAny = self :: any
	local data = {}
	for _, field in SAVE_FIELDS do
		data[field] = utils.deepCopy(selfAny[field])
	end
	return (data :: any) :: SaveData
end

-- dev-tool reset to a brand-new player; preserves player/profile/lifecycle/
-- isAdmin (see DEV TOOL CONTRACT in GameController)
function PlayerData:resetToNewPlayer()
	self:loadSaveData(self:validate(PlayerData.getDefaultSaveData()))
end

function PlayerData:getLifecycle(): number
	return self.lifecycle
end

function PlayerData:setLifecycle(lifecycle: number)
	self.lifecycle = lifecycle
end

function PlayerData:isReady(): boolean
	return self.lifecycle == Enums.PlayerLifecycle.READY
end

function PlayerData:getIsAdmin(): boolean
	return self.isAdmin
end

function PlayerData:setIsAdmin(isAdmin: boolean)
	self.isAdmin = isAdmin
end

function PlayerData:getProfile(): any?
	return self.profile
end

function PlayerData:setProfile(profile: any)
	self.profile = profile
end

function PlayerData:setIsSaveOnExit(isSaveOnExit: boolean)
	self.isSaveOnExit = isSaveOnExit
end

function PlayerData:shouldSaveOnExit(): boolean
	return self.isSaveOnExit
end

function PlayerData:getDiamonds(): number
	return self.diamonds
end

function PlayerData:setDiamonds(diamonds: number)
	self.diamonds = math.max(0, math.floor(diamonds))
end

function PlayerData:addDiamonds(amount: number)
	self:setDiamonds(self.diamonds + amount)
end

function PlayerData:canSpendDiamonds(amount: number): boolean
	return amount >= 0 and self.diamonds >= amount
end

function PlayerData:spendDiamonds(amount: number): boolean
	if not self:canSpendDiamonds(amount) then
		return false
	end
	self:setDiamonds(self.diamonds - amount)
	return true
end

-- the live records, in slot order; callers mutate through CharacterManager
-- so every change is replicated
function PlayerData:getCharacters(): { CharacterSave }
	return self.characters
end

function PlayerData:getCharacter(characterId: string): CharacterSave?
	for _, record in self.characters do
		if record.id == characterId then
			return record
		end
	end
	return nil
end

function PlayerData:getActiveCharacterId(): string
	return self.activeCharacterId
end

-- the schema guarantees the active id names a character, so this never
-- returns nil for a loaded save
function PlayerData:getActiveCharacter(): CharacterSave
	return self:getCharacter(self.activeCharacterId) or self.characters[1]
end

function PlayerData:setActiveCharacterId(characterId: string): boolean
	if not self:getCharacter(characterId) then
		return false
	end
	self.activeCharacterId = characterId
	return true
end

-- a new empty character in the next slot, or nil at the cap
function PlayerData:addCharacter(): CharacterSave?
	if #self.characters >= SCHEMA_DEFAULTS.maxCharacters then
		return nil
	end
	local record = PlayerSaveSchema.makeDefaultCharacter(SCHEMA_DEFAULTS, #self.characters + 1)
	table.insert(self.characters, record)
	return record
end

function PlayerData:hasCompletion(completionKey: string): boolean
	return self.completions[completionKey] == true
end

function PlayerData:addCompletion(completionKey: string)
	self.completions[completionKey] = true
end

function PlayerData:getDailyReward(): PlayerSaveSchema.DailyRewardSave
	return self.dailyReward
end

function PlayerData:getSessionMeta(): PlayerSaveSchema.SessionMetaSave
	return self.sessionMeta
end

function PlayerData:hasProcessedPurchase(purchaseId: string): boolean
	return table.find(self.processedPurchaseIds, purchaseId) ~= nil
end

-- newest last; the oldest fall off the front (PlayerSaveSchema's cap)
function PlayerData:addProcessedPurchase(purchaseId: string)
	if self:hasProcessedPurchase(purchaseId) then
		return
	end
	table.insert(self.processedPurchaseIds, purchaseId)
	while #self.processedPurchaseIds > PlayerSaveSchema.MAX_PROCESSED_PURCHASE_IDS do
		table.remove(self.processedPurchaseIds, 1)
	end
end

function PlayerData:getReviveCredits(reviveKind: number): number
	local key = Enums.getName(Enums.ReviveKind, reviveKind)
	return if key then self.reviveCredits[key] or 0 else 0
end

function PlayerData:addReviveCredit(reviveKind: number)
	local key = Enums.getName(Enums.ReviveKind, reviveKind)
	if key then
		self.reviveCredits[key] = (self.reviveCredits[key] or 0) + 1
	end
end

-- false, and nothing spent, when there is no credit of that kind
function PlayerData:spendReviveCredit(reviveKind: number): boolean
	local key = Enums.getName(Enums.ReviveKind, reviveKind)
	if not key or (self.reviveCredits[key] or 0) <= 0 then
		return false
	end
	self.reviveCredits[key] -= 1
	return true
end

-- copies the live state into the profile and asks ProfileStore to write it
-- now, for the few changes that must survive a crash a moment later (a
-- Robux receipt, Diamonds paid at a dawn)
function PlayerData:saveNow()
	local profile = self.profile
	if not profile or not self.isSaveOnExit then
		return
	end
	profile.Data = self:getSaveData()
	profile:Save()
end

function PlayerData:destroy()
	self.profile = nil
end

function PlayerData.new(player: Player): PlayerData
	local self = setmetatable({}, PlayerData) :: PlayerData
	self.player = player
	self.profile = nil
	self.lifecycle = Enums.PlayerLifecycle.LOADING
	self.isAdmin = false
	self.sessionStartTime = workspace:GetServerTimeNow()
	self.isSaveOnExit = true
	local defaults = PlayerData.getDefaultSaveData()
	self.diamonds = defaults.diamonds
	self.characters = defaults.characters
	self.activeCharacterId = defaults.activeCharacterId
	self.completions = defaults.completions
	self.dailyReward = defaults.dailyReward
	self.sessionMeta = defaults.sessionMeta
	self.processedPurchaseIds = defaults.processedPurchaseIds
	self.reviveCredits = defaults.reviveCredits
	return self
end

return PlayerData
