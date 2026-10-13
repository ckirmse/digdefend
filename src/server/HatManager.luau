--!strict

-- Hats on characters (cosmetics first pass, 2026-10-12). At startup every
-- hat in GameData/Characters/Hats is loaded from the catalogue once into
-- ReplicatedStorage.GameAssets.Hats, so the server can put one on a
-- character and every client can draw one on a menu avatar. When a
-- player's active character has a hat equipped, their own hat comes off
-- and the equipped one goes on, in the lobby and in a run; with none
-- equipped they keep their own. CharacterManager owns the equip; this
-- manager only loads and dresses.
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HatsData = require("@game/ServerScriptService/GameData/Characters/Hats")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CharacterRules = require("@game/ReplicatedStorage/Shared/CharacterRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Wearables = require("@game/ReplicatedStorage/Shared/Wearables")

local HatManager = {}
HatManager.__index = HatManager

export type HatManager = typeof(setmetatable(
	{} :: {
		folder: Folder?,
		-- the player's own hats, copied before the first swap so "own hat"
		-- can put them back
		ownHatsByPlayer: { [Player]: { Accessory } },
	},
	HatManager
))

local gameController: any -- prevent circular reference by not initializing here
local splendidReplicationManager: any

local HELMET_SLOT_NAME = Enums.getName(Enums.CosmeticSlot, Enums.CosmeticSlot.HELMET) :: string

function HatManager:getCatalogue(): CharacterRules.HatCatalogue
	local catalogue: CharacterRules.HatCatalogue = {}
	for id, entry in HatsData.BY_ID do
		catalogue[id] = {
			name = entry.NAME,
			assetId = entry.ASSET_ID,
		}
	end
	return catalogue
end

function HatManager:isHat(hatId: string): boolean
	return HatsData.BY_ID[hatId] ~= nil
end

function HatManager:getTemplate(hatId: string): Accessory?
	local folder = self.folder
	local template = if folder then folder:FindFirstChild(hatId) else nil
	return if template and template:IsA("Accessory") then template else nil
end

-- the catalogue items come in as a Model holding the Accessory; the
-- Accessory alone is kept, named by our id
function HatManager:loadHats()
	local existingAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local gameAssets: Instance
	if existingAssets then
		gameAssets = existingAssets
	else
		gameAssets = Instance.new("Folder")
		gameAssets.Name = Constants.GAME_ASSETS_FOLDER
		gameAssets.Parent = ReplicatedStorage
	end
	local existing = gameAssets:FindFirstChild(Constants.HAT_TEMPLATES_FOLDER)
	local folder: Instance
	if existing then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = Constants.HAT_TEMPLATES_FOLDER
		folder.Parent = gameAssets
	end
	self.folder = folder :: Folder
	for hatId, entry in HatsData.BY_ID do
		if folder:FindFirstChild(hatId) then
			continue
		end
		local isSuccess, result = pcall(
			function()
				return InsertService:LoadAsset(entry.ASSET_ID)
			end
		)
		if not isSuccess then
			warn(`HatManager: could not load hat {hatId} (asset {entry.ASSET_ID}): {tostring(result)}`)
			continue
		end
		local accessory = result:FindFirstChildWhichIsA("Accessory", true)
		if not accessory then
			warn(`HatManager: asset {entry.ASSET_ID} for hat {hatId} holds no Accessory`)
			result:Destroy()
			continue
		end
		accessory.Name = hatId
		accessory.Parent = folder
		result:Destroy()
	end
end

-- the hat the player's active character has equipped, or nil for their own
function HatManager:getEquippedHatId(player: Player): string?
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return nil
	end
	local hatId = playerData:getActiveCharacter().cosmetics[HELMET_SLOT_NAME]
	return if hatId and self:isHat(hatId) then hatId else nil
end

-- the player's own hats, remembered the first time a character of theirs
-- is seen (a fresh appearance load replaces the copies)
function HatManager:rememberOwnHats(player: Player, character: Model)
	local copies = {}
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and not self:isHat(child.Name) and Wearables.isHatAccessory(child) then
			table.insert(copies, child:Clone())
		end
	end
	self.ownHatsByPlayer[player] = copies
	-- the client's copy, for the menu avatars
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local existing = playerGui:FindFirstChild(Constants.OWN_HATS_FOLDER)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Constants.OWN_HATS_FOLDER
	folder:SetAttribute(Attributes.HAT_SCALE, self:measureHatScale(character))
	for _, copy in copies do
		copy:Clone().Parent = folder
	end
	folder.Parent = playerGui
end

-- a Humanoid scales a worn accessory by one factor for the avatar's build
-- (0.625 on a Rthro body); it is applied the moment the accessory
-- attaches, so a probe worn and dropped in the same frame reads it off
-- without anything replicating
function HatManager:measureHatScale(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local folder = self.folder
	local template = if folder then folder:FindFirstChildWhichIsA("Accessory") else nil
	if not humanoid or not template then
		return 1
	end
	local templateHandle = template:FindFirstChild(Constants.TOOL_HANDLE_PART)
	if not templateHandle or not templateHandle:IsA("BasePart") then
		return 1
	end
	local probe = template:Clone()
	humanoid:AddAccessory(probe)
	local probeHandle = probe:FindFirstChild(Constants.TOOL_HANDLE_PART)
	local scale = if probeHandle and probeHandle:IsA("BasePart") then probeHandle.Size.X / templateHandle.Size.X else 1
	probe:Destroy()
	return scale
end

function HatManager:dress(player: Player)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not humanoid then
		return
	end
	if not self.ownHatsByPlayer[player] then
		self:rememberOwnHats(player, character)
	end
	local hatId = self:getEquippedHatId(player)
	local template = if hatId then self:getTemplate(hatId) else nil
	local wornHat = character:FindFirstChild(hatId or "")
	if template and wornHat then
		return
	end
	Wearables.removeHatAccessories(character)
	if template then
		humanoid:AddAccessory(template:Clone())
		return
	end
	for _, ownHat in self.ownHatsByPlayer[player] do
		humanoid:AddAccessory(ownHat:Clone())
	end
end

-- CharacterManager calls this after a cosmetics change or a new pick
function HatManager:refresh(player: Player)
	self:dress(player)
end

function HatManager:watchPlayer(player: Player)
	player.CharacterAppearanceLoaded:Connect(
		function(character: Model)
			self:rememberOwnHats(player, character)
			-- the Ready sequence may still be running; the pick is read then
			task.defer(
				function()
					self:dress(player)
				end
			)
		end
	)
end

function HatManager:onPlayerReady(player: Player)
	self:dress(player)
end

function HatManager:onPlayerRemoved(player: Player)
	self.ownHatsByPlayer[player] = nil
end

function HatManager:init(gameControllerIn: any, splendidReplicationManagerIn: any)
	gameController = gameControllerIn
	splendidReplicationManager = splendidReplicationManagerIn
	self:loadHats()
	splendidReplicationManager:setGameMetadata(Attributes.CHARACTER_HAT_CATALOGUE, CharacterRules.encodeHatCatalogue(self:getCatalogue()))
	for _, player in Players:GetPlayers() do
		self:watchPlayer(player)
	end
	Players.PlayerAdded:Connect(
		function(player: Player)
			self:watchPlayer(player)
		end
	)
	gameController:registerPlaceManager(self)
end

function HatManager.new(): HatManager
	local self = setmetatable({}, HatManager) :: HatManager
	self.folder = nil
	self.ownHatsByPlayer = {}
	return self
end

return HatManager.new()
