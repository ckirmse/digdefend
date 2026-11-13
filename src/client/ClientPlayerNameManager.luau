--!strict

-- Players' names over their heads, in their compass dot colour (GDD
-- "Compass"), so a dot on the bar can be matched to a person. Roblox's own
-- overhead name cannot be coloured, so it is hidden on every other player
-- (the health bar stays) and the PlayerName billboard template is cloned
-- onto their character instead. It hangs from the HumanoidRootPart, which
-- no animation moves, raised by how far the Head stands above it (designer,
-- 2026-11-13: on the Head it shook with every step of the walk). With
-- streaming a character's parts come and go, so the billboard is hung
-- whenever the parts it needs appear rather than once per spawn.
-- The colour is the public CompassColorIndex the server hands out; the
-- lobby has no compass, so its main.client gives one colour for every
-- name (white; designer, 2026-11-13).
-- Common to both places since 2026-11-13 (gameplay only before): each
-- place's main.client says whether the local player gets a tag too. A run
-- is first person, so it gets none; the lobby is third person, so it does.
-- The player's class picture sits left of the name (designer, 2026-11-13),
-- from the public ActiveClassKind: the template's ClassIcon, slid against
-- the text by layoutBillboard because a name's width is only known once it
-- is drawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.ClientDataManager)

local ClientPlayerNameManager = {}
ClientPlayerNameManager.__index = ClientPlayerNameManager

export type ClientPlayerNameManager = typeof(setmetatable(
	{} :: {
		template: BillboardGui?,
		colorIndexByUserId: { [number]: number },
		classKindByUserId: { [number]: number },
		doesShowLocalPlayer: boolean,
		-- one colour for every name in place of the compass colours
		fixedNameColor: Color3?,
	},
	ClientPlayerNameManager
))

local HEAD_PART = "Head"
local ROOT_PART = "HumanoidRootPart"
-- the space between the icon and the name's first letter, as a share of
-- the billboard's width
local ICON_GAP_SHARE = 0.02

function ClientPlayerNameManager:getColor(userId: number): Color3
	local fixedNameColor = self.fixedNameColor
	if fixedNameColor then
		return fixedNameColor
	end
	local colors = UiStyle.COMPASS_PLAYER_COLORS
	local index = self.colorIndexByUserId[userId] or 1
	return colors[(index - 1) % #colors + 1]
end

function ClientPlayerNameManager:findBillboard(player: Player): BillboardGui?
	local character = player.Character
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	local billboard = if root then root:FindFirstChild(Constants.PLAYER_NAME_BILLBOARD) else nil
	return if billboard and billboard:IsA("BillboardGui") then billboard else nil
end

-- the icon and the name as one centred group: the label keeps its full
-- width and centred text, moved right by half of what the icon takes, and
-- the icon's right edge goes where the drawn text starts. With no icon the
-- name is centred as authored
function ClientPlayerNameManager:layoutBillboard(billboard: BillboardGui)
	local label = billboard:FindFirstChild(Constants.PLAYER_NAME_LABEL)
	local icon = billboard:FindFirstChild(Constants.PLAYER_NAME_CLASS_ICON)
	if not label or not label:IsA("TextLabel") then
		return
	end
	local width = billboard.AbsoluteSize.X
	if not icon or not icon:IsA("GuiObject") or not icon.Visible or width <= 0 then
		label.Position = UDim2.fromScale(0.5, label.Position.Y.Scale)
		return
	end
	local iconShare = icon.AbsoluteSize.X / width
	local textShare = math.min(label.TextBounds.X / width, 1)
	local labelCentre = 0.5 + (iconShare + ICON_GAP_SHARE) / 2
	label.Position = UDim2.fromScale(labelCentre, label.Position.Y.Scale)
	icon.Position = UDim2.fromScale(labelCentre - textShare / 2 - ICON_GAP_SHARE, icon.Position.Y.Scale)
end

-- the name's colour and the class picture, from what the server last said
function ClientPlayerNameManager:renderBillboard(userId: number, billboard: BillboardGui)
	local label = billboard:FindFirstChild(Constants.PLAYER_NAME_LABEL)
	if label and label:IsA("TextLabel") then
		label.TextColor3 = self:getColor(userId)
	end
	local icon = billboard:FindFirstChild(Constants.PLAYER_NAME_CLASS_ICON)
	if icon and icon:IsA("ImageLabel") then
		local iconId: string? = (Icons.CLASS_KIND :: { [number]: string })[self.classKindByUserId[userId] or 0]
		icon.Visible = iconId ~= nil
		icon.Image = iconId or ""
	end
	self:layoutBillboard(billboard)
end

function ClientPlayerNameManager:refresh(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	local billboard = if player then self:findBillboard(player) else nil
	if billboard then
		self:renderBillboard(userId, billboard)
	end
end

-- hangs the tag once the character has both parts it needs: the root to
-- ride on and the Head to measure the height from. The Head's rise over
-- the root is read once, here, so an avatar of any build gets the tag the
-- template's own offset above its head, and the walk never moves it after
function ClientPlayerNameManager:attachIfNeeded(player: Player, character: Model)
	local template = self.template
	local root = character:FindFirstChild(ROOT_PART)
	local head = character:FindFirstChild(HEAD_PART)
	if not template or not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then
		return
	end
	if root:FindFirstChild(Constants.PLAYER_NAME_BILLBOARD) then
		return
	end
	local billboard = template:Clone()
	billboard.Adornee = root
	local headRiseStuds = root.CFrame:PointToObjectSpace(head.Position).Y
	billboard.StudsOffsetWorldSpace = template.StudsOffsetWorldSpace + Vector3.new(0, headRiseStuds, 0)
	local label = billboard:FindFirstChild(Constants.PLAYER_NAME_LABEL)
	if label and label:IsA("TextLabel") then
		label.Text = player.DisplayName
		-- the drawn text grows and shrinks with the camera's distance, and
		-- the icon follows its left end
		label:GetPropertyChangedSignal("TextBounds"):Connect(
			function()
				self:layoutBillboard(billboard)
			end
		)
	end
	billboard:GetPropertyChangedSignal("AbsoluteSize"):Connect(
		function()
			self:layoutBillboard(billboard)
		end
	)
	billboard.Parent = root
	self:renderBillboard(player.UserId, billboard)
end

-- a distance of 0 hides Roblox's name and leaves its health bar alone. By
-- default the viewer's own Humanoid decides how far names show, so the
-- distance on this one is ignored until it is told to decide for itself
function ClientPlayerNameManager:onCharacterChild(player: Player, character: Model, child: Instance)
	if child:IsA("Humanoid") then
		child.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
		child.NameDisplayDistance = 0
	elseif child.Name == HEAD_PART or child.Name == ROOT_PART then
		self:attachIfNeeded(player, character)
	end
end

function ClientPlayerNameManager:watchCharacter(player: Player, character: Model)
	for _, child in character:GetChildren() do
		self:onCharacterChild(player, character, child)
	end
	character.ChildAdded:Connect(
		function(child: Instance)
			self:onCharacterChild(player, character, child)
		end
	)
end

function ClientPlayerNameManager:watchPlayer(player: Player)
	if player == Players.LocalPlayer and not self.doesShowLocalPlayer then
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

function ClientPlayerNameManager:init(doesShowLocalPlayer: boolean, fixedNameColor: Color3?)
	self.doesShowLocalPlayer = doesShowLocalPlayer
	self.fixedNameColor = fixedNameColor
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
			self.classKindByUserId[userId] = data.activeClassKind
			self:refresh(userId)
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			-- the entry changes many times a second (the compass position)
			if self.colorIndexByUserId[userId] ~= data.compassColorIndex or self.classKindByUserId[userId] ~= data.activeClassKind then
				self.colorIndexByUserId[userId] = data.compassColorIndex
				self.classKindByUserId[userId] = data.activeClassKind
				self:refresh(userId)
			end
		end,
		onRemoved = function(userId: number)
			self.colorIndexByUserId[userId] = nil
			self.classKindByUserId[userId] = nil
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
	self.classKindByUserId = {}
	self.doesShowLocalPlayer = false
	self.fixedNameColor = nil
	return self
end

return ClientPlayerNameManager.new()
