--!strict

-- Validates Studio-authored content for the gameplay place and warns per
-- missing piece so a broken place is obvious in the Output: the templates
-- under GameAssets at startup, and each map folder when MapManager loads it
-- (M14 covers the helicopter pad, M17 the mine entrance; later milestones
-- add the refinery, walls, posts, and stores).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
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
	self:checkMineEntrance(camp)
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
