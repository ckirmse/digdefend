--!strict

-- The models on the Tower table's map (designer, 2026-11-13): the designer's
-- MapToken parts (MapToken1, MapToken2, ...) mark spots, and each player sees
-- a small copy of their own class's Tower standing on every one, the Sentry
-- Gun for a Recruit. The same idea as the post on the Post Upgrade table
-- (ClientPostUpgradeManager): the authored parts say where and how big, and
-- the client draws its own display there, to look at only. A token is hidden
-- on this client alone, never destroyed, so a class with no Tower to show
-- (one the published catalogue leaves out) keeps the plain tokens. The Tower
-- kind comes from the ClassCatalogue GameMetadata, so nothing here asks the
-- server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local ClassCatalogueRules = require("@game/ReplicatedStorage/Shared/ClassCatalogueRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)

local ClientTowerTableManager = {}
ClientTowerTableManager.__index = ClientTowerTableManager

export type ClientTowerTableManager = typeof(setmetatable(
	{} :: {
		tableModel: Model?,
		tokens: { BasePart },
		displays: { Model },
	},
	ClientTowerTableManager
))

local WAIT_FOR_CAMP_SEC = 30
local DISPLAY_NAME = "DisplayTower"
-- a Tower stands this many times as tall as the token it replaces, so the
-- designer sizes the display by sizing the token
local HEIGHT_PER_TOKEN_HEIGHT = 2.2

-- a display is only to look at: nothing on it moves, collides, or answers
local function freezeDisplay(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		elseif descendant:IsA("ProximityPrompt") or descendant:IsA("Sound") or descendant:IsA("ParticleEmitter") or descendant:IsA("Light") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
end

-- the Tower the local player's class brings; nil when the catalogue does
-- not list the class or the place has no template for its Tower
function ClientTowerTableManager:findOwnTowerTemplate(): Model?
	local catalogue = ClassCatalogueRules.decode(ClientDataManager:getGameMetadata(Attributes.CLASS_CATALOGUE))
	local entry = ClassCatalogueRules.findEntry(catalogue, ClientDataManager:getActiveClassKind())
	local templateName = if entry then Enums.getName(Enums.TowerKind, entry.kit.tower) else nil
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.TOWER_TEMPLATES_FOLDER) else nil
	local template = if folder and templateName then folder:FindFirstChild(templateName) else nil
	return if template and template:IsA("Model") then template else nil
end

function ClientTowerTableManager:clearDisplays()
	for _, display in self.displays do
		display:Destroy()
	end
	table.clear(self.displays)
end

-- a copy of the template on one token: scaled by the token's height, turned
-- the way the token is turned, its underside on the token's underside
function ClientTowerTableManager:standOnToken(template: Model, token: BasePart, parent: Instance)
	local _templateCFrame, templateSize = template:GetBoundingBox()
	if templateSize.Y <= 0 then
		return
	end
	local display = template:Clone()
	display.Name = DISPLAY_NAME
	freezeDisplay(display)
	-- ScaleTo is absolute, and a template may already carry a scale of its own
	display:ScaleTo(display:GetScale() * token.Size.Y * HEIGHT_PER_TOKEN_HEIGHT / templateSize.Y)
	display:PivotTo(token.CFrame)
	local boundsCFrame, boundsSize = display:GetBoundingBox()
	local displayBottom = boundsCFrame.Position - token.CFrame.UpVector * (boundsSize.Y / 2)
	local tokenBottom = token.Position - token.CFrame.UpVector * (token.Size.Y / 2)
	display:PivotTo(display:GetPivot() + (tokenBottom - displayBottom))
	display.Parent = parent
	table.insert(self.displays, display)
end

function ClientTowerTableManager:renderDisplays()
	local tableModel = self.tableModel
	if not tableModel then
		return
	end
	self:clearDisplays()
	local template = self:findOwnTowerTemplate()
	for _, token in self.tokens do
		-- hidden for this client only; the plain token stays when there is no Tower to show
		token.LocalTransparencyModifier = if template then 1 else 0
		if template then
			self:standOnToken(template, token, tableModel)
		end
	end
end

function ClientTowerTableManager:attachTable()
	local camp = workspace:WaitForChild(Constants.CAMP_FOLDER, WAIT_FOR_CAMP_SEC)
	local store = if camp then camp:WaitForChild(Constants.CAMP_DEFENSE_STORE_MODEL, WAIT_FOR_CAMP_SEC) else nil
	local tables = if store then store:WaitForChild(Constants.DEFENSE_TABLES_FOLDER, WAIT_FOR_CAMP_SEC) else nil
	local tableModel = if tables then tables:WaitForChild(Constants.TOWER_TABLE_MODEL, WAIT_FOR_CAMP_SEC) else nil
	if not tableModel or not tableModel:IsA("Model") then
		warn(`ClientTowerTableManager: no {Constants.TOWER_TABLE_MODEL} model in the camp's {Constants.CAMP_DEFENSE_STORE_MODEL}; no Towers on the table`)
		return
	end
	self.tableModel = tableModel
	table.clear(self.tokens)
	for _, child in tableModel:GetChildren() do
		if child:IsA("BasePart") and string.match(child.Name, Constants.TOWER_TABLE_TOKEN_PATTERN) then
			table.insert(self.tokens, child)
		end
	end
	if #self.tokens == 0 then
		warn(`ClientTowerTableManager: {Constants.TOWER_TABLE_MODEL} has no MapToken parts; no Towers on the table`)
	end
	self:renderDisplays()
	-- a new run brings a new camp and a new table; follow it
	tableModel.AncestryChanged:Connect(
		function()
			if not tableModel:IsDescendantOf(workspace) then
				self.tableModel = nil
				table.clear(self.tokens)
				table.clear(self.displays)
				task.spawn(
					function()
						self:attachTable()
					end
				)
			end
		end
	)
end

function ClientTowerTableManager:init()
	-- the camp can take a while to stream in; nothing else waits on the display
	task.spawn(
		function()
			self:attachTable()
		end
	)
	ClientDataManager:subscribeClasses(
		function()
			self:renderDisplays()
		end
	)
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.CLASS_CATALOGUE,
		function()
			self:renderDisplays()
		end
	)
end

function ClientTowerTableManager.new(): ClientTowerTableManager
	local self = setmetatable({}, ClientTowerTableManager) :: ClientTowerTableManager
	self.tableModel = nil
	self.tokens = {}
	self.displays = {}
	return self
end

return ClientTowerTableManager.new()
