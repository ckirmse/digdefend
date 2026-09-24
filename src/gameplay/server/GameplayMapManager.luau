--!strict

-- Validates Studio-authored content for the gameplay place and warns per
-- missing piece so a broken place is obvious in the Output: the templates
-- under GameAssets at startup, and each map folder when MapManager loads it
-- (M14 covers the helicopter pad, M17 the mine entrance, M20 the refinery;
-- later milestones add walls, posts, and stores).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local HelicopterManager = require(script.Parent.Parent.Server.HelicopterManager)

local GameplayMapManager = {}
GameplayMapManager.__index = GameplayMapManager

export type GameplayMapManager = typeof(setmetatable(
	{} :: {
		problems: { string },
	},
	GameplayMapManager
))

function GameplayMapManager:report(problem: string)
	table.insert(self.problems, problem)
	warn("GameplayMapManager: " .. problem)
end

function GameplayMapManager:requireChild(parent: Instance, name: string, className: string?): Instance?
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

function GameplayMapManager:checkHelicopterPad(camp: Folder)
	local pad = self:requireChild(camp, Constants.CAMP_HELICOPTER_PAD_MODEL, "Model")
	if not pad then
		return
	end
	local helicopterSpawn = self:requireChild(pad, Constants.PAD_HELICOPTER_SPAWN_PART, "BasePart")
	if helicopterSpawn and helicopterSpawn:IsA("BasePart") and not helicopterSpawn.Anchored then
		self:report(`{helicopterSpawn:GetFullName()} must be anchored`)
	end
	local spawns = self:requireChild(pad, Constants.CAMP_SPAWNS_FOLDER, "Folder")
	if not spawns then
		return
	end
	local spawnCount = 0
	for _, child in spawns:GetChildren() do
		if not child:IsA("BasePart") then
			self:report(`{child:GetFullName()} should be a BasePart, is a {child.ClassName}`)
			continue
		end
		if not tonumber(child.Name) then
			self:report(`{child:GetFullName()} must be named with its spawn number`)
			continue
		end
		if not child.Anchored then
			self:report(`{child:GetFullName()} must be anchored`)
		end
		spawnCount += 1
	end
	if spawnCount == 0 then
		self:report(`{spawns:GetFullName()} has no numbered spawn parts`)
	end
end

-- the designer's radio (M31): the billboard's part, and the prompt part
-- with its ProximityPrompt; the screen that turns green is optional
function GameplayMapManager:checkRadio(camp: Folder)
	local radio = self:requireChild(camp, Constants.CAMP_RADIO_MODEL, "Model")
	if not radio then
		return
	end
	self:requireChild(radio, Constants.RADIO_GUI_PART, "BasePart")
	local promptPart = self:requireChild(radio, Constants.RADIO_PROMPT_PART, "BasePart")
	if promptPart and not promptPart:FindFirstChildWhichIsA("ProximityPrompt") then
		self:report(`{promptPart:GetFullName()} has no ProximityPrompt`)
	end
end

function GameplayMapManager:checkMineEntrance(camp: Folder)
	local mine = self:requireChild(camp, Constants.CAMP_MINE_FOLDER, "Folder")
	if not mine then
		return
	end
	local entrance = self:requireChild(mine, Constants.MINE_ENTRANCE_PART, "BasePart")
	if entrance and entrance:IsA("BasePart") and not entrance.Anchored then
		self:report(`{entrance:GetFullName()} must be anchored`)
	end
end

function GameplayMapManager:checkRefinery(camp: Folder)
	local refinery = self:requireChild(camp, Constants.CAMP_REFINERY_MODEL, "Model")
	if not refinery then
		return
	end
	-- clients hang the Camp Level billboard on the Refinery as soon as the
	-- Model appears; Atomic streaming makes its parts arrive with it
	if refinery:IsA("Model") and refinery.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
		self:report(`{refinery:GetFullName()} must use Atomic ModelStreamingMode`)
	end
	local promptPart = self:requireChild(refinery, Constants.REFINERY_PROMPT_PART, "BasePart")
	if not promptPart then
		return
	end
	if promptPart:IsA("BasePart") and not promptPart.Anchored then
		self:report(`{promptPart:GetFullName()} must be anchored`)
	end
	if not promptPart:FindFirstChildWhichIsA("ProximityPrompt") then
		self:report(`{promptPart:GetFullName()} needs a ProximityPrompt child`)
	end
end

-- one "<Key>Stand" per stand name, each with the Base the prompt and
-- SurfaceGui live on and the ItemSpawn the display model spins over
function GameplayMapManager:checkStore(camp: Folder, storeName: string, standNames: { string })
	-- a Model or a Folder both serve; the stands inside are what matter
	local store = self:requireChild(camp, storeName)
	if not store then
		return
	end
	for _, standName in standNames do
		local stand = self:requireChild(store, standName, "Model")
		if not stand then
			continue
		end
		local base = self:requireChild(stand, Constants.STAND_BASE_PART, "BasePart")
		if base and base:IsA("BasePart") then
			if not base.Anchored then
				self:report(`{base:GetFullName()} must be anchored`)
			end
			if not base:FindFirstChild(Constants.STAND_GUI) then
				self:report(`{base:GetFullName()} needs a {Constants.STAND_GUI}`)
			end
		end
		local itemSpawn = self:requireChild(stand, Constants.STAND_ITEM_SPAWN_PART, "BasePart")
		if itemSpawn and itemSpawn:IsA("BasePart") and not itemSpawn.Anchored then
			self:report(`{itemSpawn:GetFullName()} must be anchored`)
		end
	end
end

function GameplayMapManager:checkMiningStore(camp: Folder)
	local standNames = {}
	for _, item in Enums.getAllValues(Enums.StoreItem) do
		table.insert(standNames, StoreRules.standNameForItem(item) :: string)
	end
	self:checkStore(camp, Constants.CAMP_MINING_STORE_MODEL, standNames)
end

function GameplayMapManager:checkDefenseStore(camp: Folder)
	local standNames = {}
	for _, kind in Enums.getAllValues(Enums.TrapKind) do
		table.insert(standNames, StoreRules.standNameFromKey(Enums.getName(Enums.TrapKind, kind) :: string))
	end
	self:checkStore(camp, Constants.CAMP_DEFENSE_STORE_MODEL, standNames)
end

-- the Defensive Zones (M26): at least one anchored part whose top face is
-- the build surface; PlacementManager numbers them by name
function GameplayMapManager:checkDefensiveZones(camp: Folder)
	local folder = self:requireChild(camp, Constants.CAMP_DEFENSIVE_ZONES_FOLDER, "Folder")
	if not folder then
		return
	end
	local count = 0
	for _, child in folder:GetChildren() do
		if not child:IsA("BasePart") then
			self:report(`{child:GetFullName()} should be a BasePart, is a {child.ClassName}`)
			continue
		end
		if not child.Anchored then
			self:report(`{child:GetFullName()} must be anchored`)
		end
		count += 1
	end
	if count == 0 then
		self:report(`{folder:GetFullName()} has no zone parts`)
	end
end

-- the fortification markers StructureManager swaps for templates: numbered
-- wall and post models and the gate, each a Model so it has a pivot
function GameplayMapManager:checkFortifications(camp: Folder)
	local prefixByFolder = {
		[Constants.CAMP_WALLS_FOLDER] = Constants.WALL_NAME_PREFIX,
		[Constants.CAMP_POSTS_FOLDER] = Constants.POST_NAME_PREFIX,
	}
	for folderName, prefix in prefixByFolder do
		local folder = self:requireChild(camp, folderName, "Folder")
		if not folder then
			continue
		end
		local seen: { [string]: boolean } = {}
		for _, child in folder:GetChildren() do
			if not child:IsA("Model") then
				self:report(`{child:GetFullName()} should be a Model, is a {child.ClassName}`)
				continue
			end
			if not tonumber(child.Name:sub(#prefix + 1)) or child.Name:sub(1, #prefix) ~= prefix then
				self:report(`{child:GetFullName()} must be named {prefix} and its number`)
			end
			if seen[child.Name] then
				self:report(`{folder:GetFullName()} has more than one {child.Name}`)
			end
			seen[child.Name] = true
		end
		if next(seen) == nil then
			self:report(`{folder:GetFullName()} has no {prefix} models`)
		end
	end
	self:requireChild(camp, Constants.CAMP_GATE_MODEL, "Model")
end

-- the Workbench the crew donates Iron at; clients hang the Fortifications
-- sign on its Prompt part as soon as the Model appears
function GameplayMapManager:checkWorkbench(camp: Folder)
	local workbench = self:requireChild(camp, Constants.CAMP_WORKBENCH_MODEL, "Model")
	if not workbench then
		return
	end
	if workbench:IsA("Model") and workbench.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
		self:report(`{workbench:GetFullName()} must use Atomic ModelStreamingMode`)
	end
	local promptPart = self:requireChild(workbench, Constants.WORKBENCH_PROMPT_PART, "BasePart")
	if promptPart and promptPart:IsA("BasePart") and not promptPart.Anchored then
		self:report(`{promptPart:GetFullName()} must be anchored`)
	end
end

-- one template part per rock, so a client can clone every rock the generator
-- can place; missing ones render as a plain grey cube with a warning
function GameplayMapManager:checkRockTemplates()
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	if not gameAssets then
		self:report(`ReplicatedStorage is missing {Constants.GAME_ASSETS_FOLDER}`)
		return
	end
	local rocks = self:requireChild(gameAssets, Constants.ROCK_TEMPLATES_FOLDER, "Folder")
	if not rocks then
		return
	end
	for _, rockName in Enums.getAllValues(Enums.RockName) do
		local key = Enums.getName(Enums.RockName, rockName) :: string
		local template = rocks:FindFirstChild(key)
		if not template or not template:IsA("BasePart") then
			self:report(`{rocks:GetFullName()} is missing a BasePart template named {key}`)
		end
	end
end

-- every check a loaded map must pass; the map name is in every message
function GameplayMapManager:checkCamp(camp: Folder, mapName: string)
	local before = #self.problems
	self:checkHelicopterPad(camp)
	self:checkRadio(camp)
	self:checkMineEntrance(camp)
	self:checkRefinery(camp)
	self:checkMiningStore(camp)
	self:checkDefenseStore(camp)
	self:checkDefensiveZones(camp)
	self:checkFortifications(camp)
	self:checkWorkbench(camp)
	local found = #self.problems - before
	if found == 0 then
		print(`[GameplayMapManager] map {mapName} check passed`)
	else
		warn(`[GameplayMapManager] map {mapName} check found {found} problem(s)`)
	end
end

function GameplayMapManager:getProblems(): { string }
	return table.clone(self.problems)
end

function GameplayMapManager:init()
	self.problems = {}
	for _, problem in HelicopterManager:getTemplateProblems() do
		self:report(problem)
	end
	self:checkRockTemplates()
	if #self.problems == 0 then
		print("[GameplayMapManager] template check passed")
	else
		warn(`[GameplayMapManager] template check found {#self.problems} problem(s)`)
	end
end

function GameplayMapManager.new(): GameplayMapManager
	local self = setmetatable({}, GameplayMapManager) :: GameplayMapManager
	self.problems = {}
	return self
end

return GameplayMapManager.new()
