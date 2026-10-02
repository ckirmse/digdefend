--!strict

-- The Walls Table on this client (GDD "Wall Repair"; in the defense
-- building since 2026-10-01): the Fortifications sign floated above it, as
-- the Camp Level sign floats above the Refinery. It shows the shared tier,
-- the crew's Iron pool as a bar reading "pool / required", and a red "Camp
-- Level N required" line while the next tier is locked, all read from
-- GameMetadata. Contributing is the table's ProximityPrompt, which the
-- server hears directly; this client only plays the donor's sound and,
-- when the pool fills, the announcement everyone gets.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientWorkbenchManager = {}
ClientWorkbenchManager.__index = ClientWorkbenchManager

-- one piece of the small wall model on the table: which template family
-- it is, where the designer put it, and how much smaller than the real one
type WallPiece = {
	name: string,
	templatePrefix: string,
	pivot: CFrame,
	scale: number,
	model: Model?,
}

export type ClientWorkbenchManager = typeof(setmetatable(
	{} :: {
		wallModel: Model?,
		wallPieces: { WallPiece },
		billboard: BillboardGui?,
		titleLabel: TextLabel?,
		fill: Frame?,
		progressLabel: TextLabel?,
		lockLabel: TextLabel?,
	},
	ClientWorkbenchManager
))

local NOTIFY_FORTIFICATION_DONATED_SHAPE = {
	amount = "positiveInteger",
}
local NOTIFY_FORTIFICATION_UPGRADED_SHAPE = {
	tier = "positiveInteger",
}

local TITLE_FORMAT = "Fortifications Level %d"
local MAXED_TEXT = "MAX"
-- sentence case like "Camp upgraded to level n" (UI standard: only titles are capitalised)
local UPGRADED_FORMAT = "Fortifications upgraded to level %d"
local FILL_TWEEN_SEC = 0.25
local WAIT_FOR_CAMP_SEC = 30
local STARTING_TIER = 1

local function readNumber(value: any): number
	return if typeof(value) == "number" then value else 0
end

function ClientWorkbenchManager:render()
	local tier = readNumber(ClientDataManager:getGameMetadata(Attributes.FORTIFICATION_TIER))
	local pool = readNumber(ClientDataManager:getGameMetadata(Attributes.FORTIFICATION_POOL))
	local required = readNumber(ClientDataManager:getGameMetadata(Attributes.FORTIFICATION_POOL_REQUIRED))
	local requiredCampLevel = readNumber(ClientDataManager:getGameMetadata(Attributes.FORTIFICATION_REQUIRED_CAMP_LEVEL))
	local campLevel = readNumber(ClientDataManager:getGameMetadata(Attributes.CAMP_LEVEL))
	-- no next tier: the bar reads full and says so
	local isMaxed = required <= 0
	if self.titleLabel then
		self.titleLabel.Text = UiStyle.formatTitle(string.format(TITLE_FORMAT, math.max(tier, 1)))
	end
	if self.progressLabel then
		self.progressLabel.Text = if isMaxed then MAXED_TEXT else `{pool} / {required}`
	end
	if self.fill then
		local share = if isMaxed then 1 else math.clamp(pool / required, 0, 1)
		TweenService:Create(self.fill, TweenInfo.new(FILL_TWEEN_SEC), { Size = UDim2.fromScale(share, 1) }):Play()
	end
	if self.lockLabel then
		self.lockLabel.Visible = not isMaxed and campLevel < requiredCampLevel
		self.lockLabel.Text = string.format(StoreRules.LOCKED_FORMAT, requiredCampLevel)
	end
end

local function findTemplate(templateName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.STRUCTURE_TEMPLATES_FOLDER) else nil
	local template = if folder then folder:FindFirstChild(templateName) else nil
	return if template and template:IsA("Model") then template else nil
end

-- which template family a piece of the small wall model belongs to, from
-- its name: Wall0..n, Post1..n, or the Gate; nil for anything else
local function templatePrefixFor(name: string): string?
	if name == Constants.CAMP_GATE_MODEL then
		return Constants.GATE_TEMPLATE_PREFIX
	elseif string.sub(name, 1, #Constants.POST_NAME_PREFIX) == Constants.POST_NAME_PREFIX then
		return Constants.POST_TEMPLATE_PREFIX
	elseif string.sub(name, 1, #Constants.WALL_NAME_PREFIX) == Constants.WALL_NAME_PREFIX then
		return Constants.WALL_TEMPLATE_PREFIX
	end
	return nil
end

-- the small wall model as of the current fortification tier: every piece
-- is the tier's own template, shrunk to the designer's size and stood
-- where their piece stood, signs stripped; display only (2026-10-01)
function ClientWorkbenchManager:renderWallModel()
	local wallModel = self.wallModel
	if not wallModel then
		return
	end
	local tier = math.max(STARTING_TIER, readNumber(ClientDataManager:getGameMetadata(Attributes.FORTIFICATION_TIER)))
	for _, piece in self.wallPieces do
		local template = findTemplate(`{piece.templatePrefix}_{tier}`)
		if not template then
			continue
		end
		if piece.model then
			piece.model:Destroy()
			piece.model = nil
		end
		local model = template:Clone()
		model.Name = piece.name
		local sign = model:FindFirstChild(Constants.POST_SIGN_MODEL)
		if sign then
			sign:Destroy()
		end
		-- ScaleTo is absolute, and a template may already carry a scale of its own
		model:ScaleTo(model:GetScale() * piece.scale)
		model:PivotTo(piece.pivot)
		model.Parent = wallModel
		piece.model = model
	end
end

-- reads the designer's pieces of the small wall model (their spots, and
-- their heights against the tier-1 templates) then takes them over: from
-- here the model is redrawn locally whenever the tier changes
function ClientWorkbenchManager:attachWallModel(workbench: Model)
	local wallModel = workbench:FindFirstChild(Constants.WALLS_TABLE_WALL_MODEL)
	if not wallModel or not wallModel:IsA("Model") then
		return
	end
	self.wallModel = wallModel
	self.wallPieces = {}
	for _, child in wallModel:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local templatePrefix = templatePrefixFor(child.Name)
		local template = if templatePrefix then findTemplate(`{templatePrefix}_{STARTING_TIER}`) else nil
		if not templatePrefix or not template then
			continue
		end
		local _childCFrame, childSize = child:GetBoundingBox()
		local _templateCFrame, templateSize = template:GetBoundingBox()
		table.insert(self.wallPieces, {
			name = child.Name,
			templatePrefix = templatePrefix,
			pivot = child:GetPivot(),
			scale = if templateSize.Y > 0 then childSize.Y / templateSize.Y else 1,
			model = child,
		})
	end
	self:renderWallModel()
end

-- clones the sign above the Walls Table. Local only: it lives in this
-- player's PlayerGui and adorns the table's Prompt part, so the server
-- never holds a GUI
function ClientWorkbenchManager:attachBillboard()
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.FORTIFICATION_BILLBOARD) else nil
	if not template or not template:IsA("BillboardGui") then
		warn(`ClientWorkbenchManager: no {Constants.FORTIFICATION_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_fortification_billboard.luau`)
		return
	end
	local camp = workspace:WaitForChild(Constants.CAMP_FOLDER, WAIT_FOR_CAMP_SEC)
	local store = if camp then camp:WaitForChild(Constants.CAMP_DEFENSE_STORE_MODEL, WAIT_FOR_CAMP_SEC) else nil
	local tables = if store then store:WaitForChild(Constants.DEFENSE_TABLES_FOLDER, WAIT_FOR_CAMP_SEC) else nil
	local workbench = if tables then tables:WaitForChild(Constants.WALLS_TABLE_MODEL, WAIT_FOR_CAMP_SEC) else nil
	if not workbench or not workbench:IsA("Model") then
		warn(`ClientWorkbenchManager: no {Constants.WALLS_TABLE_MODEL} model in the camp's {Constants.CAMP_DEFENSE_STORE_MODEL} to hang the Fortifications sign on`)
		return
	end
	-- the designer's Gui part on the table is the sign's spot: the
	-- billboard is centred on it with no offset, so moving the part in the
	-- Explorer moves the sign (decided 2026-10-01). With StreamingEnabled
	-- the Model can arrive before its parts, so wait for it by name
	local adornee = workbench:WaitForChild(Constants.DEFENSE_TABLE_GUI_PART, WAIT_FOR_CAMP_SEC)
	if not adornee or not adornee:IsA("BasePart") then
		warn(`ClientWorkbenchManager: the {Constants.WALLS_TABLE_MODEL} model has no {Constants.DEFENSE_TABLE_GUI_PART} part to hang the Fortifications sign on`)
		return
	end
	self:attachWallModel(workbench)
	local billboard = template:Clone()
	billboard.Adornee = adornee
	billboard.StudsOffsetWorldSpace = Vector3.zero
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.billboard = billboard
	local root = billboard:FindFirstChild(Constants.FORTIFICATION_ROOT_FRAME)
	if not root then
		warn("ClientWorkbenchManager: the Fortification billboard has no Root frame")
		return
	end
	local title = root:FindFirstChild(Constants.FORTIFICATION_TITLE_LABEL)
	self.titleLabel = if title and title:IsA("TextLabel") then title else nil
	local bar = root:FindFirstChild(Constants.FORTIFICATION_BAR)
	local fill = if bar then bar:FindFirstChild(Constants.FORTIFICATION_FILL) else nil
	self.fill = if fill and fill:IsA("Frame") then fill else nil
	local progress = if bar then bar:FindFirstChild(Constants.FORTIFICATION_PROGRESS_LABEL) else nil
	self.progressLabel = if progress and progress:IsA("TextLabel") then progress else nil
	local lock = root:FindFirstChild(Constants.FORTIFICATION_LOCK_LABEL)
	self.lockLabel = if lock and lock:IsA("TextLabel") then lock else nil
	self:render()
end

function ClientWorkbenchManager:init()
	-- the camp can take a while to stream in; nothing else waits on the sign
	task.spawn(
		function()
			self:attachBillboard()
		end
	)
	for _, key in { Attributes.FORTIFICATION_TIER, Attributes.FORTIFICATION_POOL, Attributes.FORTIFICATION_POOL_REQUIRED, Attributes.FORTIFICATION_REQUIRED_CAMP_LEVEL, Attributes.CAMP_LEVEL } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function()
				self:render()
			end
		)
	end
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.FORTIFICATION_TIER,
		function()
			self:renderWallModel()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_FORTIFICATION_DONATED,
		function(payload: any)
			if not Validate.isTableShape(payload, NOTIFY_FORTIFICATION_DONATED_SHAPE) then
				warn("ClientWorkbenchManager: malformed NotifyFortificationDonated")
				return
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.COINS_ADDED)
		end
	)
	-- a tier is a beat for the whole crew, announced like a Camp Level
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_FORTIFICATION_UPGRADED,
		function(payload: any)
			if not Validate.isTableShape(payload, NOTIFY_FORTIFICATION_UPGRADED_SHAPE) then
				warn("ClientWorkbenchManager: malformed NotifyFortificationUpgraded")
				return
			end
			ClientPlayerFeedbackManager:announceLocal(string.format(UPGRADED_FORMAT, payload.tier))
			ClientSoundManager:playSfx(SoundNames.Sfx.CAMP_LEVEL_UP)
		end
	)
end

function ClientWorkbenchManager.new(): ClientWorkbenchManager
	local self = setmetatable({}, ClientWorkbenchManager) :: ClientWorkbenchManager
	self.wallModel = nil
	self.wallPieces = {}
	self.billboard = nil
	self.titleLabel = nil
	self.fill = nil
	self.progressLabel = nil
	self.lockLabel = nil
	return self
end

return ClientWorkbenchManager.new()
