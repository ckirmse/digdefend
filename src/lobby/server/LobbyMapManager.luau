--!strict

-- Checks the Studio-authored lobby map has every folder and part later
-- systems rely on, and names each missing piece loudly at startup so a
-- broken place fails visibly instead of quietly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")

local LobbyMapManager = {}
LobbyMapManager.__index = LobbyMapManager

export type LobbyMapManager = typeof(setmetatable(
	{} :: {
		problems: { string },
	},
	LobbyMapManager
))

local REQUIRED_PAD_GUI_LABELS = {
	Constants.PAD_GUI_STATUS_LABEL,
	Constants.PAD_GUI_PRIVATE_LABEL,
	Constants.PAD_GUI_PLAYERS_LABEL,
}

local REQUIRED_PAD_PARTS = {
	Constants.PAD_JOIN_COLLISION_PART,
	Constants.PAD_EXIT_SPAWN_PART,
	Constants.PAD_HELICOPTER_SPAWN_PART,
	Constants.PAD_CAMERA_POSITION_PART,
	Constants.PAD_GUI_PART,
}

function LobbyMapManager:report(problem: string)
	table.insert(self.problems, problem)
	warn("LobbyMapManager: " .. problem)
end

function LobbyMapManager:requireChild(parent: Instance, name: string, className: string?): Instance?
	local child = parent:FindFirstChild(name)
	if not child then
		self:report(`{parent:GetFullName()} is missing {name}`)
		return nil
	end
	if className and not child:IsA(className) then
		self:report(`{child:GetFullName()} should be a {className}, is a {child.ClassName}`)
		return nil
	end
	return child
end

function LobbyMapManager:checkSpawnZone()
	local spawnZone = self:requireChild(workspace, Constants.SPAWN_ZONE_FOLDER, "Folder")
	if not spawnZone then
		return
	end
	local spawnCount = 0
	for _, descendant in spawnZone:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			spawnCount += 1
		end
	end
	if spawnCount == 0 then
		self:report(`{spawnZone:GetFullName()} has no SpawnLocation`)
	end
	-- a spawn outside the zone would silently take priority for some joins
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and not descendant:IsDescendantOf(spawnZone) then
			self:report(`stray SpawnLocation outside {Constants.SPAWN_ZONE_FOLDER}: {descendant:GetFullName()}`)
		end
	end
end

function LobbyMapManager:checkHelicopterPads()
	local pads = self:requireChild(workspace, Constants.HELICOPTER_PADS_FOLDER, "Folder")
	if not pads then
		return
	end
	local seenIndexes: { [number]: Instance } = {}
	for _, pad in pads:GetChildren() do
		if not pad:IsA("Model") then
			self:report(`{pad:GetFullName()} should be a Model`)
			continue
		end
		local padIndex = pad:GetAttribute(Attributes.PAD_INDEX)
		if not Validate.isValueType(padIndex, "positiveInteger") or padIndex > Constants.PAD_COUNT then
			self:report(`{pad:GetFullName()} has invalid {Attributes.PAD_INDEX} {tostring(padIndex)}`)
		elseif seenIndexes[padIndex] then
			self:report(`{pad:GetFullName()} duplicates {Attributes.PAD_INDEX} {padIndex} of {seenIndexes[padIndex]:GetFullName()}`)
		else
			seenIndexes[padIndex] = pad
		end
		for _, partName in REQUIRED_PAD_PARTS do
			self:requireChild(pad, partName, "BasePart")
		end
		local guiPart = pad:FindFirstChild(Constants.PAD_GUI_PART)
		local padGui = if guiPart then self:requireChild(guiPart, Constants.PAD_GUI_NAME, "BillboardGui") else nil
		local panel = if padGui then self:requireChild(padGui, Constants.PAD_GUI_PANEL, "Frame") else nil
		if panel then
			for _, labelName in REQUIRED_PAD_GUI_LABELS do
				self:requireChild(panel, labelName, "TextLabel")
			end
		end
	end
	for padIndex = 1, Constants.PAD_COUNT do
		if not seenIndexes[padIndex] then
			self:report(`no pad with {Attributes.PAD_INDEX} {padIndex}`)
		end
	end
end

function LobbyMapManager:checkStore()
	local store = self:requireChild(workspace, Constants.STORE_FOLDER, "Folder")
	if store then
		self:requireChild(store, Constants.STORE_ITEMS_FOLDER, "Folder")
	end
end

function LobbyMapManager:checkEventArea()
	self:requireChild(workspace, Constants.EVENT_AREA_FOLDER, "Folder")
end

function LobbyMapManager:checkHoldingArea()
	local holdingArea = self:requireChild(workspace, Constants.HOLDING_AREA_FOLDER, "Folder")
	if not holdingArea then
		return
	end
	local spawns = self:requireChild(holdingArea, Constants.HOLDING_AREA_SPAWNS_FOLDER, "Folder")
	if spawns and #spawns:GetChildren() == 0 then
		self:report(`{spawns:GetFullName()} has no spawn parts`)
	end
end

function LobbyMapManager:checkHelicopterTemplate()
	local gameAssets = self:requireChild(ReplicatedStorage, Constants.GAME_ASSETS_FOLDER, "Folder")
	if not gameAssets then
		return
	end
	local helicopter = self:requireChild(gameAssets, Constants.HELICOPTER_TEMPLATE, "Model")
	if not helicopter then
		return
	end
	local playerSpawns = self:requireChild(helicopter, Constants.HELICOPTER_PLAYER_SPAWNS_FOLDER, "Folder")
	if playerSpawns and #playerSpawns:GetChildren() == 0 then
		self:report(`{playerSpawns:GetFullName()} has no seat parts`)
	end
end

function LobbyMapManager:getProblems(): { string }
	return table.clone(self.problems)
end

function LobbyMapManager:init()
	self.problems = {}
	self:checkSpawnZone()
	self:checkHelicopterPads()
	self:checkStore()
	self:checkEventArea()
	self:checkHoldingArea()
	self:checkHelicopterTemplate()
	if #self.problems == 0 then
		print("[LobbyMapManager] lobby map check passed")
	else
		warn(`[LobbyMapManager] lobby map check found {#self.problems} problem(s)`)
	end
end

function LobbyMapManager.new(): LobbyMapManager
	local self = setmetatable({}, LobbyMapManager) :: LobbyMapManager
	self.problems = {}
	return self
end

return LobbyMapManager.new()
