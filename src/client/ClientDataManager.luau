--!strict

-- The client's one window onto server state: typed reads and change listeners
-- over the SplendidGames tree. Nothing polls and nothing asks the server for
-- data the tree already carries.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local PlayerPublicSchema = require("@game/ReplicatedStorage/Shared/PlayerPublicSchema")

local ClientDataManager = {}
ClientDataManager.__index = ClientDataManager

export type PublicData = {
	userId: number,
	displayName: string,
	isReady: boolean,
	-- Enums.ToolKind, 0 when nothing is held
	equippedTool: number,
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
		ownedUnlocks: Instance?,
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
	}
end

-- yields until the server has fully built the SplendidGames tree;
-- CurrentPlayer appearing is the readiness signal, so it is awaited last
function ClientDataManager:awaitReady()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local root = playerGui:WaitForChild(Constants.SPLENDID_GAMES_NAME)
	self.root = root
	self.gameMetadata = root:WaitForChild(Constants.GAME_METADATA_FOLDER)
	self.allPlayers = root:WaitForChild(Constants.ALL_PLAYERS_FOLDER)
	local currentPlayer = root:WaitForChild(Constants.CURRENT_PLAYER_FOLDER)
	self.currentPlayer = currentPlayer
	self.ownedUnlocks = currentPlayer:WaitForChild(Constants.OWNED_UNLOCKS_FOLDER)
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

function ClientDataManager:getCash(): number
	local value = self:getCurrentPlayerAttribute(Attributes.CASH)
	return if typeof(value) == "number" then value else 0
end

function ClientDataManager:getIsAdmin(): boolean
	return self:getCurrentPlayerAttribute(Attributes.IS_ADMIN) == true
end

function ClientDataManager:hasUnlock(unlockName: string): boolean
	local ownedUnlocks = self.ownedUnlocks
	return ownedUnlocks ~= nil and ownedUnlocks:FindFirstChild(unlockName) ~= nil
end

function ClientDataManager:getOwnedUnlockNames(): { string }
	local names = {}
	local ownedUnlocks = self.ownedUnlocks
	if not ownedUnlocks then
		return names
	end
	for _, marker in ownedUnlocks:GetChildren() do
		table.insert(names, marker.Name)
	end
	table.sort(names)
	return names
end

-- nil when the slot is empty
function ClientDataManager:getLoadoutSlot(slot: number): string?
	local attributeName = PlayerPublicSchema.getLoadoutAttribute(slot)
	if not attributeName then
		return nil
	end
	local value = self:getCurrentPlayerAttribute(attributeName)
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	return value
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

function ClientDataManager:subscribeOwnedUnlocks(handlers: MarkerHandlers): Disconnect
	return subscribeMarkerFolder(self.ownedUnlocks :: Instance, handlers)
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
	self.ownedUnlocks = nil
	self.completions = nil
	return self
end

return ClientDataManager.new()
