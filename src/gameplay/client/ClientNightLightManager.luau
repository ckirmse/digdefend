--!strict

-- The map's night lighting (designer, 2026-10-21): every light tagged
-- NightLight rises from 0 to a brightness of 1 over the day's last
-- RISE_SEC, reaching 1 as night falls, and every mesh tagged
-- NightLightBulb turns from clear to solid alongside it; both go out over
-- NIGHT_END_FADE_SEC at dawn. The level is read off the run clock every
-- frame (the phase end the day clock uses, held still through a pause),
-- not tweened from an event, so a late joiner, a paused run, and the
-- Skip to sunset dev tool all land on the right level; only the dawn
-- fade is a ramp of its own. The tagged instances are the map's, cloned
-- in with it, and found through CollectionService as they stream in.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)

local ClientNightLightManager = {}
ClientNightLightManager.__index = ClientNightLightManager

export type ClientNightLightManager = typeof(setmetatable(
	{} :: {
		-- the level last written to the instances, 0 (day) to 1 (night)
		shownLevel: number,
	},
	ClientNightLightManager
))

-- the lights' brightness at night
local NIGHT_BRIGHTNESS = 1
-- the lights come up over this many seconds before night falls
local RISE_SEC = 30
-- how long the lights take to go out at dawn
local NIGHT_END_FADE_SEC = 0.5
-- a write is skipped for a change smaller than this
local LEVEL_EPSILON = 0.002

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

-- where the run clock puts the lights: 0 through the day, climbing over
-- its last RISE_SEC, 1 through the night and the rescue (night rules), 0
-- before the first day; a finished run keeps whatever it had
function ClientNightLightManager:targetLevel(): number?
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.WAITING)
	if runState == Enums.RunState.NIGHT or runState == Enums.RunState.RESCUE then
		return 1
	end
	if runState ~= Enums.RunState.DAY then
		return if runState == Enums.RunState.WAITING then 0 else nil
	end
	local endTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0)
	local now = workspace:GetServerTimeNow()
	local pauseStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PAUSE_START_TIME), 0)
	if pauseStartTime > 0 then
		now = pauseStartTime
	end
	local secondsLeft = endTime - now
	return math.clamp(1 - secondsLeft / RISE_SEC, 0, 1)
end

function ClientNightLightManager:apply(level: number)
	for _, light in CollectionService:GetTagged(Tags.NIGHT_LIGHT) do
		if light:IsA("Light") then
			light.Brightness = level * NIGHT_BRIGHTNESS
		end
	end
	for _, bulb in CollectionService:GetTagged(Tags.NIGHT_LIGHT_BULB) do
		if bulb:IsA("BasePart") then
			bulb.Transparency = 1 - level
		end
	end
end

-- a rise follows the clock exactly; a fall (dawn) is ramped over
-- NIGHT_END_FADE_SEC so the lights go out rather than snap
function ClientNightLightManager:step(deltaSec: number)
	local target = self:targetLevel()
	if target == nil then
		return
	end
	local level = target
	if target < self.shownLevel then
		level = math.max(target, self.shownLevel - deltaSec / NIGHT_END_FADE_SEC)
	end
	if math.abs(level - self.shownLevel) < LEVEL_EPSILON then
		return
	end
	self.shownLevel = level
	self:apply(level)
end

-- an instance streaming in mid-run takes the current level at once
function ClientNightLightManager:onTaggedAdded(instance: Instance)
	if instance:IsA("Light") then
		instance.Brightness = self.shownLevel * NIGHT_BRIGHTNESS
	elseif instance:IsA("BasePart") then
		instance.Transparency = 1 - self.shownLevel
	end
end

function ClientNightLightManager:init()
	self:apply(0)
	CollectionService:GetInstanceAddedSignal(Tags.NIGHT_LIGHT):Connect(
		function(instance: Instance)
			self:onTaggedAdded(instance)
		end
	)
	CollectionService:GetInstanceAddedSignal(Tags.NIGHT_LIGHT_BULB):Connect(
		function(instance: Instance)
			self:onTaggedAdded(instance)
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function ClientNightLightManager.new(): ClientNightLightManager
	local self = setmetatable({}, ClientNightLightManager) :: ClientNightLightManager
	self.shownLevel = 0
	return self
end

return ClientNightLightManager.new()
