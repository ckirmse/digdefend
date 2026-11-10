--!strict

-- The client's one window onto server state: typed reads and change listeners
-- over the SplendidGames tree. Nothing polls and nothing asks the server for
-- data the tree already carries.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ClassSchema = require("@game/ReplicatedStorage/Shared/ClassSchema")
local CosmeticLoadoutSchema = require("@game/ReplicatedStorage/Shared/CosmeticLoadoutSchema")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GachaRules = require("@game/ReplicatedStorage/Shared/GachaRules")
local SkillEffectRules = require("@game/ReplicatedStorage/Shared/SkillEffectRules")

-- the ready wait never gives up; the number only marks the yield as intended
local READY_WAIT_TIMEOUT_SEC = math.huge

local ClientDataManager = {}
ClientDataManager.__index = ClientDataManager

export type PublicData = {
	userId: number,
	displayName: string,
	isReady: boolean,
	-- Enums.ToolKind, 0 when nothing is held
	equippedTool: number,
	-- run state every client may show (gameplay place)
	pickAxeLevel: number,
	isJetPackBurning: boolean,
	-- Enums.WeaponKind carried this run, 0 before it is handed out
	weaponKind: number,
	-- how far up (+) or down (-) the player is looking (AimManager)
	aimPitchDegrees: number,
	-- posts (PostManager): the post claimed, the weapon brought, and the
	-- post being manned; 0 for none
	postIndex: number,
	postWeaponKind: number,
	-- the Binoculars tag this player holds, as BinocularsRules JSON ("" for none)
	binocularsTag: string,
	mannedPostIndex: number,
	-- the compass (CompassManager): where the player stands, nil until first
	-- published, and which dot colour is theirs
	compassPosition: Vector3?,
	compassColorIndex: number,
	-- dead and waiting on a revive (ReviveManager, M32)
	isDead: boolean,
}

-- one class record as the client sees it (the Class Menu, 2026-11-04):
-- the skills in its slots
export type ClassRecord = ClassSchema.ClassSave

export type AllPlayersHandlers = {
	onAdded: ((userId: number, data: PublicData) -> ())?,
	onRemoved: ((userId: number) -> ())?,
	onChanged: ((userId: number, data: PublicData) -> ())?,
}

export type MarkerHandlers = {
	onAdded: ((name: string) -> ())?,
	onRemoved: ((name: string) -> ())?,
}

export type Disconnect = () -> ()

export type ClientDataManager = typeof(setmetatable(
	{} :: {
		root: Instance?,
		gameMetadata: Instance?,
		allPlayers: Instance?,
		currentPlayer: Instance?,
		completions: Instance?,
	},
	ClientDataManager
))

local function readPublicData(folder: Instance): PublicData
	return {
		userId = (folder:GetAttribute(Attributes.USER_ID) :: number?) or 0,
		displayName = (folder:GetAttribute(Attributes.DISPLAY_NAME) :: string?) or "",
		isReady = folder:GetAttribute(Attributes.IS_READY) == true,
		equippedTool = (folder:GetAttribute(Attributes.EQUIPPED_TOOL) :: number?) or 0,
		pickAxeLevel = (folder:GetAttribute(Attributes.PICK_AXE_LEVEL) :: number?) or 1,
		isJetPackBurning = folder:GetAttribute(Attributes.IS_JET_PACK_BURNING) == true,
		weaponKind = (folder:GetAttribute(Attributes.WEAPON_KIND) :: number?) or 0,
		aimPitchDegrees = (folder:GetAttribute(Attributes.AIM_PITCH_DEGREES) :: number?) or 0,
		postIndex = (folder:GetAttribute(Attributes.POST_INDEX) :: number?) or 0,
		postWeaponKind = (folder:GetAttribute(Attributes.POST_WEAPON_KIND) :: number?) or 0,
		binocularsTag = (folder:GetAttribute(Attributes.BINOCULARS_TAG) :: string?) or "",
		mannedPostIndex = (folder:GetAttribute(Attributes.MANNED_POST_INDEX) :: number?) or 0,
		compassPosition = folder:GetAttribute(Attributes.COMPASS_POSITION) :: Vector3?,
		compassColorIndex = (folder:GetAttribute(Attributes.COMPASS_COLOR_INDEX) :: number?) or 1,
		isDead = folder:GetAttribute(Attributes.IS_DEAD) == true,
	}
end

-- yields until the server has fully built the SplendidGames tree;
-- CurrentPlayer appearing is the readiness signal, so it is awaited last.
-- The root can legitimately take longer than Roblox's five-second grace
-- (the gameplay place holds Ready until the helicopter lands), so the wait
-- carries an explicit, effectively endless timeout to say the yield is meant
function ClientDataManager:awaitReady()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local root = playerGui:WaitForChild(Constants.SPLENDID_GAMES_NAME, READY_WAIT_TIMEOUT_SEC) :: Instance
	self.root = root
	self.gameMetadata = root:WaitForChild(Constants.GAME_METADATA_FOLDER)
	self.allPlayers = root:WaitForChild(Constants.ALL_PLAYERS_FOLDER)
	local currentPlayer = root:WaitForChild(Constants.CURRENT_PLAYER_FOLDER)
	self.currentPlayer = currentPlayer
	self.completions = currentPlayer:WaitForChild(Constants.COMPLETIONS_FOLDER)
end

function ClientDataManager:isReady(): boolean
	return self.currentPlayer ~= nil
end

function ClientDataManager:getGameMetadata(key: string): any
	local gameMetadata = self.gameMetadata
	if not gameMetadata then
		return nil
	end
	return gameMetadata:GetAttribute(key)
end

function ClientDataManager:getCurrentPlayerAttribute(key: string): any
	local currentPlayer = self.currentPlayer
	if not currentPlayer then
		return nil
	end
	return currentPlayer:GetAttribute(key)
end

function ClientDataManager:getDiamonds(): number
	local value = self:getCurrentPlayerAttribute(Attributes.DIAMONDS)
	return if typeof(value) == "number" then value else 0
end

function ClientDataManager:getIsAdmin(): boolean
	return self:getCurrentPlayerAttribute(Attributes.IS_ADMIN) == true
end

-- the class gacha's account state (M70), replicated by replicateGacha
function ClientDataManager:getKeys(): number
	local value = self:getCurrentPlayerAttribute(Attributes.KEYS)
	return if typeof(value) == "number" then value else 0
end

function ClientDataManager:getClassProgress(): GachaRules.Progress
	return GachaRules.decodeProgress(self:getCurrentPlayerAttribute(Attributes.CLASS_PROGRESS))
end

function ClientDataManager:getOwnedCosmetics(): GachaRules.OwnedCosmetics
	return GachaRules.decodeOwnedCosmetics(self:getCurrentPlayerAttribute(Attributes.OWNED_COSMETICS))
end

function ClientDataManager:isPaidRandomItemsRestricted(): boolean
	return self:getCurrentPlayerAttribute(Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED) == true
end

-- the class the player brings, as an Enums.ClassKind value; 0 before the
-- attribute lands
function ClientDataManager:getActiveClassKind(): number
	return (self:getCurrentPlayerAttribute(Attributes.ACTIVE_CLASS_KIND) :: number?) or 0
end

-- every class record by class key name (a class never touched is absent)
function ClientDataManager:getClassRecords(): ClassSchema.Records
	return ClassSchema.decodeRecords(self:getCurrentPlayerAttribute(Attributes.CLASS_RECORDS))
end

-- one class's record, empty for a class never touched
function ClientDataManager:getClassRecord(classKind: number): ClassRecord
	local className = Enums.getName(Enums.ClassKind, classKind)
	local record = if className then self:getClassRecords()[className] else nil
	return record or { skills = {} }
end

-- the skill ids the class in play holds, slot order (M56)
function ClientDataManager:getActiveSkillIds(): { string }
	return SkillEffectRules.skillIdsOf(self:getClassRecord(self:getActiveClassKind()))
end

function ClientDataManager:hasSkill(skillId: string): boolean
	return table.find(self:getActiveSkillIds(), skillId) ~= nil
end

-- the account's one cosmetic loadout (Enums.CosmeticSlot key name to
-- skin id), worn with every class (2026-11-04)
function ClientDataManager:getCosmetics(): CosmeticLoadoutSchema.Loadout
	return CosmeticLoadoutSchema.decode(self:getCurrentPlayerAttribute(Attributes.COSMETICS))
end

function ClientDataManager:subscribeCosmetics(handler: () -> ()): Disconnect
	return self:subscribeCurrentPlayerAttribute(Attributes.COSMETICS, handler)
end

-- any change to the class in play, a class record, or the class progress
-- (the Class Menu redraws from all three)
function ClientDataManager:subscribeClasses(handler: () -> ()): Disconnect
	local watched: { [string]: boolean } = {
		[Attributes.ACTIVE_CLASS_KIND] = true,
		[Attributes.CLASS_RECORDS] = true,
		[Attributes.CLASS_PROGRESS] = true,
	}
	local currentPlayer = self.currentPlayer :: Instance
	local connection = currentPlayer.AttributeChanged:Connect(
		function(attributeName: string)
			if watched[attributeName] then
				handler()
			end
		end
	)
	return function()
		connection:Disconnect()
	end
end

function ClientDataManager:hasCompletion(completionKey: string): boolean
	local completions = self.completions
	return completions ~= nil and completions:FindFirstChild(completionKey) ~= nil
end

function ClientDataManager:getDailyRewardLastClaimedDay(): number
	local value = self:getCurrentPlayerAttribute(Attributes.DAILY_REWARD_LAST_CLAIMED_DAY)
	return if typeof(value) == "number" then value else 0
end

function ClientDataManager:getDailyRewardNextClaimTime(): number
	local value = self:getCurrentPlayerAttribute(Attributes.DAILY_REWARD_NEXT_CLAIM_TIME)
	return if typeof(value) == "number" then value else 0
end

function ClientDataManager:getAllPlayerIds(): { number }
	local ids = {}
	local allPlayers = self.allPlayers
	if not allPlayers then
		return ids
	end
	for _, child in allPlayers:GetChildren() do
		local id = tonumber(child.Name)
		if id then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

function ClientDataManager:getPlayerPublicData(userId: number): PublicData?
	local allPlayers = self.allPlayers
	if not allPlayers then
		return nil
	end
	local folder = allPlayers:FindFirstChild(tostring(userId))
	if not folder then
		return nil
	end
	return readPublicData(folder)
end

-- one attribute off a player's AllPlayers entry (a run-state flag a
-- gameplay manager published with setPublicAttribute, such as the jet
-- pack burning); nil for a player not Ready here
function ClientDataManager:getPublicAttribute(userId: number, key: string): any
	local allPlayers = self.allPlayers
	local folder = if allPlayers then allPlayers:FindFirstChild(tostring(userId)) else nil
	return if folder then folder:GetAttribute(key) else nil
end

function ClientDataManager:subscribeCurrentPlayerAttribute(key: string, callback: (value: any) -> ()): Disconnect
	local currentPlayer = self.currentPlayer :: Instance
	local connection = currentPlayer:GetAttributeChangedSignal(key):Connect(
		function()
			callback(currentPlayer:GetAttribute(key))
		end
	)
	return function()
		connection:Disconnect()
	end
end

function ClientDataManager:subscribeGameMetadataAttribute(key: string, callback: (value: any) -> ()): Disconnect
	local gameMetadata = self.gameMetadata :: Instance
	local connection = gameMetadata:GetAttributeChangedSignal(key):Connect(
		function()
			callback(gameMetadata:GetAttribute(key))
		end
	)
	return function()
		connection:Disconnect()
	end
end

local function subscribeMarkerFolder(folder: Instance, handlers: MarkerHandlers): Disconnect
	local connections: { RBXScriptConnection } = {}
	if handlers.onAdded then
		for _, marker in folder:GetChildren() do
			handlers.onAdded(marker.Name)
		end
		table.insert(
			connections,
			folder.ChildAdded:Connect(
				function(marker: Instance)
					(handlers.onAdded :: (string) -> ())(marker.Name)
				end
			)
		)
	end
	if handlers.onRemoved then
		table.insert(
			connections,
			folder.ChildRemoved:Connect(
				function(marker: Instance)
					(handlers.onRemoved :: (string) -> ())(marker.Name)
				end
			)
		)
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end
end

function ClientDataManager:subscribeCompletions(handlers: MarkerHandlers): Disconnect
	return subscribeMarkerFolder(self.completions :: Instance, handlers)
end

function ClientDataManager:subscribeAllPlayers(handlers: AllPlayersHandlers): Disconnect
	local allPlayers = self.allPlayers :: Instance
	local connections: { RBXScriptConnection } = {}

	local function watch(folder: Instance)
		local userId = tonumber(folder.Name)
		if not userId then
			return
		end
		if handlers.onAdded then
			handlers.onAdded(userId, readPublicData(folder))
		end
		table.insert(
			connections,
			folder.AttributeChanged:Connect(
				function()
					if handlers.onChanged then
						handlers.onChanged(userId, readPublicData(folder))
					end
				end
			)
		)
		table.insert(
			connections,
			folder.Destroying:Connect(
				function()
					if handlers.onRemoved then
						handlers.onRemoved(userId)
					end
				end
			)
		)
	end

	for _, folder in allPlayers:GetChildren() do
		watch(folder)
	end
	table.insert(connections, allPlayers.ChildAdded:Connect(watch))

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end
end

function ClientDataManager.new(): ClientDataManager
	local self = setmetatable({}, ClientDataManager) :: ClientDataManager
	self.root = nil
	self.gameMetadata = nil
	self.allPlayers = nil
	self.currentPlayer = nil
	self.completions = nil
	return self
end

return ClientDataManager.new()
