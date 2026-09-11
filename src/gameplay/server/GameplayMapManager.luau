--!strict

-- Validates the Studio-authored camp at startup (M14 covers the helicopter
-- pad; later milestones add the mine, refinery, walls, posts, and stores)
-- and warns per missing piece so a broken place is obvious in the Output.
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
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

function GameplayMapManager:checkHelicopterPad()
	local camp = self:requireChild(workspace, Constants.CAMP_FOLDER, "Folder")
	if not camp then
		return
	end
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

function GameplayMapManager:getProblems(): { string }
	return table.clone(self.problems)
end

function GameplayMapManager:init()
	self.problems = {}
	self:checkHelicopterPad()
	for _, problem in HelicopterManager:getTemplateProblems() do
		self:report(problem)
	end
	if #self.problems == 0 then
		print("[GameplayMapManager] camp check passed")
	else
		warn(`[GameplayMapManager] camp check found {#self.problems} problem(s)`)
	end
end

function GameplayMapManager.new(): GameplayMapManager
	local self = setmetatable({}, GameplayMapManager) :: GameplayMapManager
	self.problems = {}
	return self
end

return GameplayMapManager.new()
