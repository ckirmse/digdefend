--!strict

-- The client's one window onto server state: typed reads and change listeners
-- over the SplendidGames tree. Nothing polls and nothing asks the server for
-- data the tree already carries.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local CharacterSchema = require("@game/ReplicatedStorage/Shared/CharacterSchema")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerPublicSchema = require("@game/ReplicatedStorage/Shared/PlayerPublicSchema")

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

-- one character as the client sees it (M55), read from the CHARACTER_*
-- attributes on CurrentPlayer (the active one) or on a child of the
-- Characters folder (every one)
export type GearData = {
	kind: number,
	stars: number,
}

export type CharacterData = {
	id: string,
	name: string,
	-- Enums.ClassKind value (M64); 0 before the attribute lands
	classKind: number,
	nightsSurvived: number,
	-- Enums.GearSlot value -> the kind's enum value and its stars
	gear: { [number]: GearData },
	skillSlotsOpen: number,
	-- slot index as a string -> the skill in it
	skills: { [string]: CharacterSchema.SkillSave },
	-- Enums.CosmeticSlot key name -> skin id
	cosmetics: { [string]: string },
}

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
		characters: Instance?,
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
	self.characters = currentPlayer:WaitForChild(Constants.CHARACTERS_FOLDER)
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

local function readCharacter(instance: Instance): CharacterData
	local gear: { [number]: GearData } = {}
	for _, gearSlot in Enums.getAllValues(Enums.GearSlot) do
		local kindAttribute, starsAttribute = PlayerPublicSchema.getGearAttributes(gearSlot)
		gear[gearSlot] = {
			kind = (instance:GetAttribute(kindAttribute :: string) :: number?) or 0,
			stars = (instance:GetAttribute(starsAttribute :: string) :: number?) or 0,
		}
	end
	return {
		id = (instance:GetAttribute(Attributes.CHARACTER_ID) :: string?) or "",
		name = (instance:GetAttribute(Attributes.CHARACTER_NAME) :: string?) or "",
		classKind = (instance:GetAttribute(Attributes.CHARACTER_CLASS_KIND) :: number?) or 0,
		nightsSurvived = (instance:GetAttribute(Attributes.CHARACTER_NIGHTS_SURVIVED) :: number?) or 0,
		gear = gear,
		skillSlotsOpen = (instance:GetAttribute(Attributes.CHARACTER_SKILL_SLOTS_OPEN) :: number?) or 0,
		skills = CharacterSchema.decodeSkills(instance:GetAttribute(Attributes.CHARACTER_SKILLS)),
		cosmetics = CharacterSchema.decodeCosmetics(instance:GetAttribute(Attributes.CHARACTER_COSMETICS)),
	}
end

-- the character the player brings; nil before the tree is ready
function ClientDataManager:getActiveCharacter(): CharacterData?
	local currentPlayer = self.currentPlayer
	if not currentPlayer then
		return nil
	end
	return readCharacter(currentPlayer)
end

function ClientDataManager:getActiveCharacterId(): string
	local characters = self.characters
	if not characters then
		return ""
	end
	return (characters:GetAttribute(Attributes.ACTIVE_CHARACTER_ID) :: string?) or ""
end

-- every character, in no particular order (the folder has no slot order;
-- M37 sorts by name or keeps the server's list order as it decides)
function ClientDataManager:getCharacters(): { CharacterData }
	local list = {}
	local characters = self.characters
	if not characters then
		return list
	end
	for _, child in characters:GetChildren() do
		table.insert(list, readCharacter(child))
	end
	return list
end

-- fires once per attribute the server writes, so a reroll that changes a
-- kind and its stars calls back twice; readers re-read the whole character
function ClientDataManager:subscribeActiveCharacter(handler: (character: CharacterData) -> ()): Disconnect
	local currentPlayer = self.currentPlayer :: Instance
	local connection = currentPlayer.AttributeChanged:Connect(
		function(attributeName: string)
			if string.sub(attributeName, 1, #"Character") == "Character" then
				handler(readCharacter(currentPlayer))
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

-- any change to the character list or the active id: a character added, a
-- card's values, or the pick
function ClientDataManager:subscribeCharacters(handler: () -> ()): Disconnect
	local characters = self.characters :: Instance
	local connections: { RBXScriptConnection } = {}
	local function watch(child: Instance)
		table.insert(
			connections,
			child.AttributeChanged:Connect(
				function()
					handler()
				end
			)
		)
	end
	for _, child in characters:GetChildren() do
		watch(child)
	end
	table.insert(
		connections,
		characters.ChildAdded:Connect(
			function(child: Instance)
				watch(child)
				handler()
			end
		)
	)
	table.insert(
		connections,
		characters.ChildRemoved:Connect(
			function()
				handler()
			end
		)
	)
	table.insert(
		connections,
		characters.AttributeChanged:Connect(
			function()
				handler()
			end
		)
	)
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
	self.characters = nil
	self.completions = nil
	return self
end

return ClientDataManager.new()
