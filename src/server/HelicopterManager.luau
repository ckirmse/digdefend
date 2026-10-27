--!strict

-- The one place helicopters are cloned (CLAUDE.md "Central asset location"),
-- for both places: the lobby pads and the camp pad. A helicopter is a
-- server model tagged Tags.HELICOPTER whose HelicopterPhase attribute drives
-- every visual on the clients (ClientHelicopterManager); the server never
-- animates it. A flight (an approach onto a pad, a departure from one;
-- M75) is three more attributes, the server time it began, the pad's
-- CFrame, and the departure's heading, which every client samples through
-- pure HelicopterFlightRules against the flight config this manager
-- publishes once as GameMetadata JSON (GameData/Control/Helicopter), so
-- all clients draw the same flight. Seats are kept Disabled so the engine
-- never auto-seats a passer-by; a caller enables one only for its own Sit
-- call.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local HelicopterFlightRules = require("@game/ReplicatedStorage/Shared/HelicopterFlightRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local HelicopterData = require("@game/ServerScriptService/GameData/Control/Helicopter")
local SpatialSoundManager = require(script.Parent.SpatialSoundManager)
local SplendidReplicationManager = require(script.Parent.SplendidReplicationManager)

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

-- the template's authored Board prompt (M75), wherever the designer put it
function HelicopterManager:getBoardPrompt(helicopter: Model): ProximityPrompt?
	local prompt = helicopter:FindFirstChild(Constants.HELICOPTER_BOARD_PROMPT, true)
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
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
	-- the authored prompt is for the rescue alone, and only once landed
	local boardPrompt = self:getBoardPrompt(helicopter)
	if boardPrompt then
		boardPrompt.Enabled = false
	end
	self:setPhase(helicopter, phase)
	CollectionService:AddTag(helicopter, Tags.HELICOPTER)
	helicopter.Parent = parent
	-- the rotor loop rides on the model and dies with it, but each client
	-- starts and stops it from its own rotor speed (ClientHelicopterManager),
	-- so it is attached silent (decided 2026-09-16)
	local soundPart = helicopter.PrimaryPart or helicopter:FindFirstChildWhichIsA("BasePart")
	if soundPart then
		SpatialSoundManager:attach(soundPart, SoundNames.Sfx.HELICOPTER, true, false)
	end
	return helicopter
end

-- a helicopter in the air on its way to a pad (M75): spawned at the
-- approach part, it flies in from flightStartTime and is on the pad
-- APPROACH_SEC later; the caller lands it then (land). nil when the
-- template is missing
function HelicopterManager:spawnApproaching(approachPart: BasePart, padPart: BasePart, parent: Instance, flightStartTime: number): Model?
	local helicopter = self:spawnAt(approachPart, parent, Enums.HelicopterPhase.APPROACHING)
	if not helicopter then
		return nil
	end
	helicopter:SetAttribute(Attributes.HELICOPTER_PAD_CFRAME, padPart.CFrame)
	helicopter:SetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME, flightStartTime)
	return helicopter
end

-- a flight in progress is shifted (the dev tool's pause lifted)
function HelicopterManager:shiftFlightStart(helicopter: Model, deltaSec: number)
	local startTime = helicopter:GetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME)
	if typeof(startTime) == "number" then
		helicopter:SetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME, startTime + deltaSec)
	end
end

-- the approach is over: the model sits on the pad for real (the clients
-- already drew it there) with its rotor turning
function HelicopterManager:land(helicopter: Model, padPart: BasePart)
	helicopter:PivotTo(padPart.CFrame)
	self:setPhase(helicopter, Enums.HelicopterPhase.SPINNING)
end

-- a launched helicopter stays in the world (renamed, so it is no longer the
-- pad's helicopter) while clients fly it off along the heading (flat; its
-- own facing when none is given), then goes away for good
function HelicopterManager:retire(helicopter: Model, lifetimeSec: number, heading: Vector3?)
	helicopter.Name = Constants.DEPARTED_HELICOPTER_NAME
	local pivot = helicopter:GetPivot()
	helicopter:SetAttribute(Attributes.HELICOPTER_PAD_CFRAME, pivot)
	helicopter:SetAttribute(Attributes.HELICOPTER_HEADING, HelicopterFlightRules.flatDirection(Vector3.zero, HelicopterFlightRules.flatten(heading or pivot.LookVector), pivot.LookVector))
	helicopter:SetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME, workspace:GetServerTimeNow())
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

-- an approach called off mid-air (the run lost under it): the server
-- puts the model where every client is drawing it at this moment (the
-- same pure pose) and sends it away from there, so it turns off rather
-- than vanishing or snapping to its spawn
function HelicopterManager:abortApproach(helicopter: Model, lifetimeSec: number)
	local padCFrame = helicopter:GetAttribute(Attributes.HELICOPTER_PAD_CFRAME)
	local startTime = helicopter:GetAttribute(Attributes.HELICOPTER_FLIGHT_START_TIME)
	local heading: Vector3? = nil
	if typeof(padCFrame) == "CFrame" and typeof(startTime) == "number" then
		local pose = HelicopterFlightRules.approachPose(helicopter:GetPivot().Position, padCFrame, HelicopterData :: any, workspace:GetServerTimeNow() - startTime)
		helicopter:PivotTo(pose)
		heading = pose.LookVector
	end
	self:retire(helicopter, lifetimeSec, heading)
end

-- the flight config reaches every client once, as GameMetadata
function HelicopterManager:init()
	SplendidReplicationManager:setGameMetadata(Attributes.HELICOPTER_FLIGHT_CONFIG, HelicopterFlightRules.encodeConfig(HelicopterData :: any))
end

function HelicopterManager.new(): HelicopterManager
	local self = setmetatable({}, HelicopterManager) :: HelicopterManager
	return self
end

return HelicopterManager.new()
