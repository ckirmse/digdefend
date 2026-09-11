--!strict

-- The one place helicopters are cloned (CLAUDE.md "Central asset location"),
-- for both places: the lobby pads and the camp pad. A helicopter is a
-- server model tagged Tags.HELICOPTER whose HelicopterPhase attribute drives
-- every visual on the clients (ClientHelicopterManager); the server never
-- animates it. Seats are kept Disabled so the engine never auto-seats a
-- passer-by; a caller enables one only for its own Sit call.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local HelicopterManager = {}
HelicopterManager.__index = HelicopterManager

export type HelicopterManager = typeof(setmetatable({} :: {}, HelicopterManager))

function HelicopterManager:getTemplate(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local template = if gameAssets then gameAssets:FindFirstChild(Constants.HELICOPTER_TEMPLATE) else nil
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

-- what a map validator reports about the template at startup
function HelicopterManager:getTemplateProblems(): { string }
	local problems = {}
	local template = self:getTemplate()
	if not template then
		table.insert(problems, `ReplicatedStorage.{Constants.GAME_ASSETS_FOLDER} is missing the {Constants.HELICOPTER_TEMPLATE} Model`)
		return problems
	end
	local playerSpawns = template:FindFirstChild(Constants.HELICOPTER_PLAYER_SPAWNS_FOLDER)
	if not playerSpawns then
		table.insert(problems, `{template:GetFullName()} is missing {Constants.HELICOPTER_PLAYER_SPAWNS_FOLDER}`)
		return problems
	end
	if #playerSpawns:GetChildren() == 0 then
		table.insert(problems, `{playerSpawns:GetFullName()} has no seats`)
	end
	for _, spawn in playerSpawns:GetChildren() do
		if not spawn:IsA("Seat") then
			table.insert(problems, `{spawn:GetFullName()} must be a Seat, not a {spawn.ClassName}`)
		end
	end
	local rotorModel = template:FindFirstChild(Constants.HELICOPTER_ROTOR_MODEL)
	local rotor = if rotorModel then rotorModel:FindFirstChild(Constants.HELICOPTER_ROTOR_PART) else nil
	if not rotor or not rotor:IsA("BasePart") then
		table.insert(problems, `{template:GetFullName()} is missing {Constants.HELICOPTER_ROTOR_MODEL}.{Constants.HELICOPTER_ROTOR_PART}`)
	end
	return problems
end

-- seats in name order so Seat1 is always the first taken
function HelicopterManager:getSeats(helicopter: Model): { Seat }
	local seats: { Seat } = {}
	local spawns = helicopter:FindFirstChild(Constants.HELICOPTER_PLAYER_SPAWNS_FOLDER)
	if not spawns then
		return seats
	end
	for _, child in spawns:GetChildren() do
		if child:IsA("Seat") then
			table.insert(seats, child)
		end
	end
	table.sort(
		seats,
		function(a: Seat, b: Seat)
			return a.Name < b.Name
		end
	)
	return seats
end

function HelicopterManager:setPhase(helicopter: Model, phase: number)
	helicopter:SetAttribute(Attributes.HELICOPTER_PHASE, phase)
end

-- a fresh helicopter on a spawn part; nil (already reported by the map
-- validator) when the template or spawn is missing
function HelicopterManager:spawnAt(spawnPart: BasePart, parent: Instance, phase: number): Model?
	local template = self:getTemplate()
	if not template then
		return nil
	end
	local helicopter = template:Clone()
	helicopter:PivotTo(spawnPart.CFrame)
	for _, seat in self:getSeats(helicopter) do
		seat.Disabled = true
	end
	self:setPhase(helicopter, phase)
	CollectionService:AddTag(helicopter, Tags.HELICOPTER)
	helicopter.Parent = parent
	return helicopter
end

-- a launched helicopter stays in the world (renamed, so it is no longer the
-- pad's helicopter) while clients fly it off, then goes away for good
function HelicopterManager:retire(helicopter: Model, lifetimeSec: number)
	helicopter.Name = Constants.DEPARTED_HELICOPTER_NAME
	self:setPhase(helicopter, Enums.HelicopterPhase.FLYING)
	task.delay(
		lifetimeSec,
		function()
			if helicopter.Parent then
				helicopter:Destroy()
			end
		end
	)
end

function HelicopterManager.new(): HelicopterManager
	local self = setmetatable({}, HelicopterManager) :: HelicopterManager
	return self
end

return HelicopterManager.new()
