--!strict

-- Owns the SplendidGames tree in each player's PlayerGui: GameMetadata (global),
-- AllPlayers (public entry per Ready player), CurrentPlayer (private state).
-- Managers change PlayerData and then call a replicate* method here; nothing
-- else writes the tree.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local PlayerPublicSchema = require("@game/ReplicatedStorage/Shared/PlayerPublicSchema")
local PlayerData = require(script.Parent.PlayerData)

local SplendidReplicationManager = {}
SplendidReplicationManager.__index = SplendidReplicationManager

type AttributeMap = { [string]: any }

export type SplendidReplicationManager = typeof(setmetatable(
	{} :: {
		serverStartTime: number,
		-- place managers contribute global config here (setGameMetadata)
		extraGameMetadata: AttributeMap,
		-- per-player run state a place manager publishes (setPublicAttribute /
		-- setCurrentPlayerAttribute), kept so a tree rewrite or a late viewer
		-- still gets it
		extraPublicByUserId: { [number]: AttributeMap },
		extraCurrentPlayerByUserId: { [number]: AttributeMap },
	},
	SplendidReplicationManager
))

local gameController: any -- prevent circular reference by not initializing here

local function writeAttributes(instance: Instance, attributes: AttributeMap)
	for name, value in attributes do
		instance:SetAttribute(name, value)
	end
end

-- keeps a folder's marker children equal to a set of names, touching only
-- what changed so client listeners fire once per real change
local function syncMarkerFolder(folder: Instance, names: { [string]: boolean })
	for _, child in folder:GetChildren() do
		if not names[child.Name] then
			child:Destroy()
		end
	end
	for name in names do
		if folder:FindFirstChild(name) then
			continue
		end
		local marker = Instance.new("Folder")
		marker.Name = name
		marker.Parent = folder
	end
end

-- keeps the Characters folder equal to the player's list (M55): one child
-- folder per character named by its id and carrying the same attribute set
-- as the active character on CurrentPlayer, plus the active id on the
-- folder itself, so the select menu can draw every card and a late viewer
-- gets them all
local function syncCharactersFolder(folder: Instance, playerData: any)
	local unlockNights = PlayerData.getCharacterDefaults().skillSlotUnlockNights
	local records = playerData:getCharacters()
	local keep: { [string]: boolean } = {}
	for _, record in records do
		keep[record.id] = true
		local existing = folder:FindFirstChild(record.id)
		local child: Instance
		if existing then
			child = existing
		else
			child = Instance.new("Folder")
			child.Name = record.id
		end
		writeAttributes(child, PlayerPublicSchema.buildCharacterAttributes(record, unlockNights))
		if child.Parent ~= folder then
			child.Parent = folder
		end
	end
	for _, child in folder:GetChildren() do
		if not keep[child.Name] then
			child:Destroy()
		end
	end
	folder:SetAttribute(Attributes.ACTIVE_CHARACTER_ID, playerData:getActiveCharacterId())
end

local function snapshot(player: Player, playerData: any): PlayerPublicSchema.Snapshot
	local dailyReward = playerData:getDailyReward()
	return {
		userId = player.UserId,
		displayName = player.DisplayName,
		isReady = true,
		isAdmin = playerData:getIsAdmin(),
		diamonds = playerData:getDiamonds(),
		activeCharacter = playerData:getActiveCharacter(),
		skillSlotUnlockNights = PlayerData.getCharacterDefaults().skillSlotUnlockNights,
		dailyRewardLastClaimedDay = dailyReward.lastClaimedDay,
		dailyRewardNextClaimTime = dailyReward.nextClaimTime,
	}
end

function SplendidReplicationManager:getRoot(player: Player): Instance?
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	return playerGui:FindFirstChild(Constants.SPLENDID_GAMES_NAME)
end

function SplendidReplicationManager:getCurrentPlayerFolder(player: Player): Instance?
	local root = self:getRoot(player)
	if not root then
		return nil
	end
	return root:FindFirstChild(Constants.CURRENT_PLAYER_FOLDER)
end

function SplendidReplicationManager:buildGameMetadataAttributes(): AttributeMap
	local attributes: AttributeMap = {
		[Attributes.SERVER_START_TIME] = self.serverStartTime,
		[Attributes.SCHEMA_VERSION] = Constants.DATA_SCHEMA_VERSION,
		[Attributes.PLACE_KIND] = Constants.getPlaceKind(),
	}
	for key, value in self.extraGameMetadata do
		attributes[key] = value
	end
	return attributes
end

-- global config from a place manager; reaches players already Ready and
-- every player who becomes Ready later
function SplendidReplicationManager:setGameMetadata(key: string, value: any)
	self.extraGameMetadata[key] = value
	self:updateGameMetadata(key, value)
end

function SplendidReplicationManager:writeCurrentPlayer(player: Player, playerData: any, currentPlayer: Instance)
	writeAttributes(currentPlayer, PlayerPublicSchema.buildCurrentPlayerAttributes(snapshot(player, playerData)))
	writeAttributes(currentPlayer, self.extraCurrentPlayerByUserId[player.UserId] or {})
	local characters = currentPlayer:FindFirstChild(Constants.CHARACTERS_FOLDER)
	if characters then
		syncCharactersFolder(characters, playerData)
	end
	local completions = currentPlayer:FindFirstChild(Constants.COMPLETIONS_FOLDER)
	if completions then
		syncMarkerFolder(completions, playerData.completions)
	end
end

function SplendidReplicationManager:buildPlayerTree(player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end
	if self:getRoot(player) then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")

	local root = Instance.new("ScreenGui")
	root.Name = Constants.SPLENDID_GAMES_NAME
	root.ResetOnSpawn = false

	local gameMetadata = Instance.new("Folder")
	gameMetadata.Name = Constants.GAME_METADATA_FOLDER
	writeAttributes(gameMetadata, self:buildGameMetadataAttributes())
	gameMetadata.Parent = root

	local allPlayers = Instance.new("Folder")
	allPlayers.Name = Constants.ALL_PLAYERS_FOLDER
	allPlayers.Parent = root

	local currentPlayer = Instance.new("Folder")
	currentPlayer.Name = Constants.CURRENT_PLAYER_FOLDER
	local characters = Instance.new("Folder")
	characters.Name = Constants.CHARACTERS_FOLDER
	characters.Parent = currentPlayer
	local completions = Instance.new("Folder")
	completions.Name = Constants.COMPLETIONS_FOLDER
	completions.Parent = currentPlayer
	self:writeCurrentPlayer(player, playerData, currentPlayer)
	currentPlayer.Parent = root

	-- parent the whole tree last so the client sees a fully seeded
	-- SplendidGames / CurrentPlayer as its single atomic readiness signal
	root.Parent = playerGui

	for _, other in gameController:getReadyPlayers() do
		self:createOrUpdateAllPlayersEntry(player, other)
	end
end

function SplendidReplicationManager:createOrUpdateAllPlayersEntry(viewerPlayer: Player, subjectPlayer: Player)
	local root = self:getRoot(viewerPlayer)
	if not root then
		return
	end
	local allPlayers = root:FindFirstChild(Constants.ALL_PLAYERS_FOLDER)
	if not allPlayers then
		return
	end
	local subjectData = gameController:getPlayerData(subjectPlayer)
	if not subjectData then
		return
	end

	local key = tostring(subjectPlayer.UserId)
	local entry = allPlayers:FindFirstChild(key)
	if not entry then
		entry = Instance.new("Folder")
		entry.Name = key
		entry.Parent = allPlayers
	end
	writeAttributes(entry :: Instance, PlayerPublicSchema.buildPublicAttributes(snapshot(subjectPlayer, subjectData)))
	writeAttributes(entry :: Instance, self.extraPublicByUserId[subjectPlayer.UserId] or {})
end

-- run state about one player every client may see (the equipped tool)
function SplendidReplicationManager:setPublicAttribute(player: Player, key: string, value: any)
	local extras = self.extraPublicByUserId[player.UserId]
	if not extras then
		extras = {}
		self.extraPublicByUserId[player.UserId] = extras
	end
	extras[key] = value
	self:updateAllPlayersEntry(player)
end

-- run state only that player sees (tool slots, pick axe level)
function SplendidReplicationManager:setCurrentPlayerAttribute(player: Player, key: string, value: any)
	local extras = self.extraCurrentPlayerByUserId[player.UserId]
	if not extras then
		extras = {}
		self.extraCurrentPlayerByUserId[player.UserId] = extras
	end
	extras[key] = value
	local currentPlayer = self:getCurrentPlayerFolder(player)
	if currentPlayer then
		currentPlayer:SetAttribute(key, value)
	end
end

function SplendidReplicationManager:updateAllPlayersEntry(subjectPlayer: Player)
	for _, viewer in gameController:getReadyPlayers() do
		self:createOrUpdateAllPlayersEntry(viewer, subjectPlayer)
	end
end

function SplendidReplicationManager:onPlayerReady(player: Player)
	self:buildPlayerTree(player)
	for _, other in gameController:getReadyPlayers() do
		if other ~= player then
			self:createOrUpdateAllPlayersEntry(other, player)
		end
	end
end

function SplendidReplicationManager:onPlayerRemoved(player: Player)
	self.extraPublicByUserId[player.UserId] = nil
	self.extraCurrentPlayerByUserId[player.UserId] = nil
	local key = tostring(player.UserId)
	for _, viewer in gameController:getReadyPlayers() do
		local root = self:getRoot(viewer)
		if not root then
			continue
		end
		local allPlayers = root:FindFirstChild(Constants.ALL_PLAYERS_FOLDER)
		if not allPlayers then
			continue
		end
		local entry = allPlayers:FindFirstChild(key)
		if entry then
			entry:Destroy()
		end
	end
end

-- rewrites the existing tree in place for the reset-player dev tool; the
-- ScreenGui is never destroyed because ClientDataManager caches these
-- Instance references (see DEV TOOL CONTRACT in GameController)
function SplendidReplicationManager:resetPlayerTree(player: Player)
	local playerData = gameController:getPlayerData(player)
	local currentPlayer = self:getCurrentPlayerFolder(player)
	if not playerData or not currentPlayer then
		return
	end
	self:writeCurrentPlayer(player, playerData, currentPlayer)
	self:updateAllPlayersEntry(player)
end

function SplendidReplicationManager:replicateDiamonds(player: Player)
	local playerData = gameController:getPlayerData(player)
	local currentPlayer = self:getCurrentPlayerFolder(player)
	if not playerData or not currentPlayer then
		return
	end
	currentPlayer:SetAttribute(Attributes.DIAMONDS, playerData:getDiamonds())
end

-- the active character's attributes on CurrentPlayer and the whole list
-- under Characters; CharacterManager calls this after every change
function SplendidReplicationManager:replicateCharacters(player: Player)
	local playerData = gameController:getPlayerData(player)
	local currentPlayer = self:getCurrentPlayerFolder(player)
	if not playerData or not currentPlayer then
		return
	end
	local unlockNights = PlayerData.getCharacterDefaults().skillSlotUnlockNights
	writeAttributes(currentPlayer, PlayerPublicSchema.buildCharacterAttributes(playerData:getActiveCharacter(), unlockNights))
	local characters = currentPlayer:FindFirstChild(Constants.CHARACTERS_FOLDER)
	if characters then
		syncCharactersFolder(characters, playerData)
	end
end

function SplendidReplicationManager:replicateCompletions(player: Player)
	local playerData = gameController:getPlayerData(player)
	local currentPlayer = self:getCurrentPlayerFolder(player)
	if not playerData or not currentPlayer then
		return
	end
	local completions = currentPlayer:FindFirstChild(Constants.COMPLETIONS_FOLDER)
	if completions then
		syncMarkerFolder(completions, playerData.completions)
	end
end

function SplendidReplicationManager:replicateDailyReward(player: Player)
	local playerData = gameController:getPlayerData(player)
	local currentPlayer = self:getCurrentPlayerFolder(player)
	if not playerData or not currentPlayer then
		return
	end
	local dailyReward = playerData:getDailyReward()
	currentPlayer:SetAttribute(Attributes.DAILY_REWARD_LAST_CLAIMED_DAY, dailyReward.lastClaimedDay)
	currentPlayer:SetAttribute(Attributes.DAILY_REWARD_NEXT_CLAIM_TIME, dailyReward.nextClaimTime)
end

function SplendidReplicationManager:updateGameMetadata(key: string, value: any)
	-- a place manager may register config before GameController:init has run;
	-- the value then reaches players through buildGameMetadataAttributes
	if gameController == nil then
		return
	end
	for _, player in gameController:getReadyPlayers() do
		local root = self:getRoot(player)
		if not root then
			continue
		end
		local gameMetadata = root:FindFirstChild(Constants.GAME_METADATA_FOLDER)
		if gameMetadata then
			gameMetadata:SetAttribute(key, value)
		end
	end
end

function SplendidReplicationManager:init(gameControllerIn: any)
	gameController = gameControllerIn
	self.serverStartTime = workspace:GetServerTimeNow()
end

function SplendidReplicationManager.new(): SplendidReplicationManager
	local self = setmetatable({}, SplendidReplicationManager) :: SplendidReplicationManager
	self.serverStartTime = 0
	self.extraGameMetadata = {}
	self.extraPublicByUserId = {}
	self.extraCurrentPlayerByUserId = {}
	return self
end

return SplendidReplicationManager.new()
