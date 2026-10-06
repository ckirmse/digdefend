--!strict

-- The sole owner of one player's persistent state and the only code path that
-- touches ProfileStore. Managers implement business logic; PlayerData is the
-- record of what is true for this player. The lifecycle lives here too, so a
-- system asking "may I act on this player" asks one object.
local PlayerControlData = require("@game/ServerScriptService/GameData/Control/Player")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerSaveSchema = require("@game/ReplicatedStorage/Shared/PlayerSaveSchema")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local PlayerData = {}
PlayerData.__index = PlayerData

export type SaveData = PlayerSaveSchema.SaveData

export type PlayerData = typeof(setmetatable(
	{} :: {
		player: Player,
		profile: any?,
		lifecycle: number,
		isAdmin: boolean,
		sessionStartTime: number,
		isSaveOnExit: boolean,
		diamonds: number,
		ownedUnlocks: { [string]: boolean },
		loadout: { [string]: string },
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
	"ownedUnlocks",
	"loadout",
	"completions",
	"dailyReward",
	"sessionMeta",
	"processedPurchaseIds",
	"reviveCredits",
}

local SCHEMA_DEFAULTS: PlayerSaveSchema.Defaults = {
	startingDiamonds = PlayerControlData.STARTING_DIAMONDS,
}

function PlayerData.getDefaultSaveData(): SaveData
	return PlayerSaveSchema.getDefault(SCHEMA_DEFAULTS)
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

function PlayerData:hasUnlock(unlockName: string): boolean
	return self.ownedUnlocks[unlockName] == true
end

function PlayerData:addUnlock(unlockName: string)
	self.ownedUnlocks[unlockName] = true
end

function PlayerData:getOwnedUnlockNames(): { string }
	local names = {}
	for name in self.ownedUnlocks do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function PlayerData:getLoadoutSlot(slot: number): string?
	local slotName = Enums.getName(Enums.LoadoutSlot, slot)
	if not slotName then
		return nil
	end
	return self.loadout[slotName]
end

-- nil clears the slot; equipping requires ownership so a save never claims
-- an item the player lacks
function PlayerData:setLoadoutSlot(slot: number, unlockName: string?): boolean
	local slotName = Enums.getName(Enums.LoadoutSlot, slot)
	if not slotName then
		return false
	end
	if unlockName ~= nil and not self:hasUnlock(unlockName) then
		return false
	end
	self.loadout[slotName] = unlockName
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
	self.ownedUnlocks = defaults.ownedUnlocks
	self.loadout = defaults.loadout
	self.completions = defaults.completions
	self.dailyReward = defaults.dailyReward
	self.sessionMeta = defaults.sessionMeta
	self.processedPurchaseIds = defaults.processedPurchaseIds
	self.reviveCredits = defaults.reviveCredits
	return self
end

return PlayerData
