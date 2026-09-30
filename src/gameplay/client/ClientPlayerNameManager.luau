--!strict

-- Crewmates' names over their heads, in their compass dot colour (GDD
-- "Compass"), so a dot on the bar can be matched to a person. Roblox's own
-- overhead name cannot be coloured, so it is hidden on every other player
-- (the health bar stays) and the PlayerName billboard template is cloned
-- onto their Head instead. The colour is the public CompassColorIndex the
-- server hands out. With streaming a character's Head comes and goes, so
-- the billboard is hung whenever a Head appears rather than once per spawn.
-- The local player is first person and gets none.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)

local ClientPlayerNameManager = {}
ClientPlayerNameManager.__index = ClientPlayerNameManager

export type ClientPlayerNameManager = typeof(setmetatable(
	{} :: {
		template: BillboardGui?,
		colorIndexByUserId: { [number]: number },
	},
	ClientPlayerNameManager
))

local HEAD_PART = "Head"

function ClientPlayerNameManager:getColor(userId: number): Color3
	local colors = UiStyle.COMPASS_PLAYER_COLORS
	local index = self.colorIndexByUserId[userId] or 1
	return colors[(index - 1) % #colors + 1]
end

function ClientPlayerNameManager:findLabel(player: Player): TextLabel?
	local character = player.Character
	local head = if character then character:FindFirstChild(HEAD_PART) else nil
	local billboard = if head then head:FindFirstChild(Constants.PLAYER_NAME_BILLBOARD) else nil
	local label = if billboard then billboard:FindFirstChild(Constants.PLAYER_NAME_LABEL) else nil
	return if label and label:IsA("TextLabel") then label else nil
end

function ClientPlayerNameManager:refreshColor(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	local label = if player then self:findLabel(player) else nil
	if label then
		label.TextColor3 = self:getColor(userId)
	end
end

function ClientPlayerNameManager:attachToHead(player: Player, head: Instance)
	local template = self.template
	if not template or not head:IsA("BasePart") or head:FindFirstChild(Constants.PLAYER_NAME_BILLBOARD) then
		return
	end
	local billboard = template:Clone()
	billboard.Adornee = head
	local label = billboard:FindFirstChild(Constants.PLAYER_NAME_LABEL)
	if label and label:IsA("TextLabel") then
		label.Text = player.DisplayName
		label.TextColor3 = self:getColor(player.UserId)
	end
	billboard.Parent = head
end

-- a distance of 0 hides Roblox's name and leaves its health bar alone. By
-- default the viewer's own Humanoid decides how far names show, so the
-- distance on this one is ignored until it is told to decide for itself
function ClientPlayerNameManager:onCharacterChild(player: Player, child: Instance)
	if child:IsA("Humanoid") then
		child.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
		child.NameDisplayDistance = 0
	elseif child.Name == HEAD_PART then
		self:attachToHead(player, child)
	end
end

function ClientPlayerNameManager:watchCharacter(player: Player, character: Model)
	for _, child in character:GetChildren() do
		self:onCharacterChild(player, child)
	end
	character.ChildAdded:Connect(
		function(child: Instance)
			self:onCharacterChild(player, child)
		end
	)
end

function ClientPlayerNameManager:watchPlayer(player: Player)
	if player == Players.LocalPlayer then
		return
	end
	if player.Character then
		self:watchCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(
		function(character: Model)
			self:watchCharacter(player, character)
		end
	)
end

function ClientPlayerNameManager:init()
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.PLAYER_NAME_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		warn(`ClientPlayerNameManager: no {Constants.PLAYER_NAME_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_player_name_billboard.luau`)
		return
	end
	self.template = template
	ClientDataManager:subscribeAllPlayers({
		onAdded = function(userId: number, data: ClientDataManager.PublicData)
			self.colorIndexByUserId[userId] = data.compassColorIndex
			self:refreshColor(userId)
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			if self.colorIndexByUserId[userId] ~= data.compassColorIndex then
				self.colorIndexByUserId[userId] = data.compassColorIndex
				self:refreshColor(userId)
			end
		end,
		onRemoved = function(userId: number)
			self.colorIndexByUserId[userId] = nil
		end,
	})
	for _, player in Players:GetPlayers() do
		self:watchPlayer(player)
	end
	Players.PlayerAdded:Connect(
		function(player: Player)
			self:watchPlayer(player)
		end
	)
end

function ClientPlayerNameManager.new(): ClientPlayerNameManager
	local self = setmetatable({}, ClientPlayerNameManager) :: ClientPlayerNameManager
	self.template = nil
	self.colorIndexByUserId = {}
	return self
end

return ClientPlayerNameManager.new()
