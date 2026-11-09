--!strict

-- The sole owner of one player's persistent state and the only code path that
-- touches ProfileStore. Managers implement business logic; PlayerData is the
-- record of what is true for this player. The lifecycle lives here too, so a
-- system asking "may I act on this player" asks one object.
local HttpService = game:GetService("HttpService")

local GachaData = require("@game/ServerScriptService/GameData/Gacha/Gacha")
local ClassRosterData = require("@game/ServerScriptService/GameData/Classes/Roster")
local SkillsData = require("@game/ServerScriptService/GameData/Characters/Skills")
local PlayerControlData = require("@game/ServerScriptService/GameData/Control/Player")
local ClassSchema = require("@game/ReplicatedStorage/Shared/ClassSchema")
local CosmeticLoadoutSchema = require("@game/ReplicatedStorage/Shared/CosmeticLoadoutSchema")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerSaveSchema = require("@game/ReplicatedStorage/Shared/PlayerSaveSchema")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local PlayerData = {}
PlayerData.__index = PlayerData

export type SaveData = PlayerSaveSchema.SaveData
export type ClassSave = ClassSchema.ClassSave

export type PlayerData = typeof(setmetatable(
	{} :: {
		player: Player,
		profile: any?,
		lifecycle: number,
		isAdmin: boolean,
		sessionStartTime: number,
		isSaveOnExit: boolean,
		diamonds: number,
		classes: ClassSchema.Records,
		activeClassKind: string,
		completions: { [string]: boolean },
		dailyReward: PlayerSaveSchema.DailyRewardSave,
		sessionMeta: PlayerSaveSchema.SessionMetaSave,
		processedPurchaseIds: { string },
		reviveCredits: { [string]: number },
		classProgress: { [string]: number },
		keys: number,
		ownedCosmetics: { [string]: boolean },
	},
	PlayerData
))

-- every persisted field copies between the save table and this object as-is;
-- adding a field here means adding it to PlayerSaveSchema too
local SAVE_FIELDS = {
	"diamonds",
	"classes",
	"cosmetics",
	"activeClassKind",
	"completions",
	"dailyReward",
	"sessionMeta",
	"processedPurchaseIds",
	"reviveCredits",
	"classProgress",
	"keys",
	"ownedCosmetics",
}

local function buildValidSkillIds(): { [string]: boolean }
	local ids = {}
	for id in SkillsData.BY_ID do
		ids[id] = true
	end
	return ids
end

-- the GameData the pure schemas need, gathered once: the class record
-- shape (the slot cap, the skill catalogue's ids), the skins a new
-- account wears, and the account shape around them
local CLASS_DEFAULTS: ClassSchema.Defaults = {
	maxSkillSlots = GachaData.MAX_SKILL_SLOTS,
	validSkillIds = buildValidSkillIds(),
}

local SCHEMA_DEFAULTS: PlayerSaveSchema.Defaults = {
	startingDiamonds = PlayerControlData.STARTING_DIAMONDS,
	class = CLASS_DEFAULTS,
	-- no slot has a default skin: an unset slot is the stock art (the Hard
	-- Hat was the helmet's until hats went, 2026-11-09)
	defaultCosmetics = {},
	defaultClassKind = ClassRosterData.DEFAULT_CLASS,
}

function PlayerData.getDefaultSaveData(): SaveData
	return PlayerSaveSchema.getDefault(SCHEMA_DEFAULTS)
end

-- the class record shape's tuning, for managers that reason about a
-- record (open skill slots) without requiring GameData themselves
function PlayerData.getClassDefaults(): ClassSchema.Defaults
	return CLASS_DEFAULTS
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

-- the live class records; callers mutate through ClassManager so every
-- change is replicated
function PlayerData:getClassRecords(): ClassSchema.Records
	return self.classes
end

-- a class's record by its Enums.ClassKind key name, made from the
-- defaults the first time it is asked for, so a save stays small until a
-- class is touched
function PlayerData:getClassRecord(className: string): ClassSave
	local record = self.classes[className]
	if not record then
		record = ClassSchema.getDefault(CLASS_DEFAULTS)
		self.classes[className] = record
	end
	return record
end

function PlayerData:getActiveClassName(): string
	return self.activeClassKind
end

-- the schema guarantees the active class names a real one, so the
-- fallback only guards a save that has not loaded
function PlayerData:getActiveClassKind(): number
	return Enums.getValueByName(Enums.ClassKind, self.activeClassKind) or ClassRosterData.DEFAULT_CLASS
end

-- the account's one cosmetic loadout (Enums.CosmeticSlot key name to
-- skin id); CosmeticManager is the one writer, so every change is
-- replicated
function PlayerData:getCosmetics(): CosmeticLoadoutSchema.Loadout
	return self.cosmetics
end

function PlayerData:getActiveClassRecord(): ClassSave
	return self:getClassRecord(self.activeClassKind)
end

function PlayerData:setActiveClassKind(classKind: number): boolean
	local className = Enums.getName(Enums.ClassKind, classKind)
	if not className then
		return false
	end
	self.activeClassKind = className
	return true
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

-- the class gacha's account state (M70); GachaManager is the one writer
-- of progress and cosmetics, and reads the live tables to resolve a roll
function PlayerData:getClassProgress(): { [string]: number }
	return self.classProgress
end

-- back to a new account's classes (the free one alone), for the dev tool
function PlayerData:resetClassProgress()
	self.classProgress = PlayerSaveSchema.getDefaultClassProgress(SCHEMA_DEFAULTS)
end

function PlayerData:getOwnedCosmetics(): { [string]: boolean }
	return self.ownedCosmetics
end

-- a cosmetic bought in the Key Store (M61); the gacha writes the same set
-- through GachaRules.applyResult
function PlayerData:addOwnedCosmetic(cosmeticId: string)
	self.ownedCosmetics[cosmeticId] = true
end

-- back to a new account's cosmetics (the default hat alone), for the dev
-- tool; a character still wearing a cleared skin keeps it, since what is
-- worn is never checked against what is owned
function PlayerData:resetOwnedCosmetics()
	self.ownedCosmetics = PlayerSaveSchema.getDefaultOwnedCosmetics(SCHEMA_DEFAULTS)
end

function PlayerData:getKeys(): number
	return self.keys
end

function PlayerData:addKeys(amount: number)
	self.keys = math.max(0, math.floor(self.keys + amount))
end

function PlayerData:spendKeys(amount: number): boolean
	if amount < 0 or self.keys < amount then
		return false
	end
	self.keys -= amount
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
