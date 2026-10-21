--!strict

-- The sun's rays through sunset (designer, 2026-10-21): over the day's
-- last RISE_SEC (inside dusk; the whole dusk at first, which lit up the
-- moment dusk began) the SunRays effect's Intensity and Spread rise from
-- the preset's values to SUNSET_INTENSITY and SUNSET_SPREAD, reaching
-- them as night falls (intensity 1 blinded; designer), and
-- the preset's own values are back the moment the night starts. The
-- lighting presets (ClientRunCycleManager:stepSky, every RenderStepped)
-- write the SunRays every frame from the map's stages, which have no
-- sunset window of their own, so this lays its blend over the preset's
-- write through the run cycle manager's sky-applied hook (right after
-- the write, before the render; a Heartbeat write of its own was never
-- drawn), and only while the clock is inside dusk; outside it the
-- presets are untouched. Read off the run clock, held still through a
-- pause, so a late joiner and the Skip to sunset dev tool land on the
-- right value.
local Lighting = game:GetService("Lighting")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local LightingPresets = require("@game/ReplicatedStorage/Shared/LightingPresets")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientRunCycleManager = require(script.Parent.ClientRunCycleManager)

local ClientSunsetRaysManager = {}
ClientSunsetRaysManager.__index = ClientSunsetRaysManager

export type ClientSunsetRaysManager = typeof(setmetatable({} :: {}, ClientSunsetRaysManager))

local SUNSET_INTENSITY = 0.25
local SUNSET_SPREAD = 0.6
-- the rise fills the day's last seconds
local RISE_SEC = 25
-- the preset's values when its SunRays block names none
local DEFAULT_INTENSITY = 0.15
local DEFAULT_SPREAD = 0
local SUN_RAYS_NAME = "SunRays"

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

-- how far through the rise the clock is, 0 at RISE_SEC before night to
-- 1 at night; nil before the rise begins
function ClientSunsetRaysManager:duskProgress(): number?
	local runState = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_STATE), Enums.RunState.WAITING)
	if runState ~= Enums.RunState.DAY then
		return nil
	end
	local endTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_END_TIME), 0)
	local now = workspace:GetServerTimeNow()
	local pauseStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PAUSE_START_TIME), 0)
	if pauseStartTime > 0 then
		now = pauseStartTime
	end
	local secondsLeft = endTime - now
	if secondsLeft > RISE_SEC then
		return nil
	end
	return math.clamp(1 - secondsLeft / RISE_SEC, 0, 1)
end

-- the day end preset's own rays, the blend's starting point
function ClientSunsetRaysManager:baseValues(): (number, number)
	local map = ClientDataManager:getGameMetadata(Attributes.RUN_MAP)
	local presets = LightingPresets.forMap(if typeof(map) == "number" then map else nil)
	local sunRays = presets.DAY_END.CHILDREN[SUN_RAYS_NAME]
	local intensity = if sunRays then readNumber(sunRays.Intensity, DEFAULT_INTENSITY) else DEFAULT_INTENSITY
	local spread = if sunRays then readNumber(sunRays.Spread, DEFAULT_SPREAD) else DEFAULT_SPREAD
	return intensity, spread
end

function ClientSunsetRaysManager:step()
	local progress = self:duskProgress()
	if progress == nil then
		return
	end
	local sunRays = Lighting:FindFirstChild(SUN_RAYS_NAME)
	if not sunRays or not sunRays:IsA("SunRaysEffect") then
		return
	end
	local baseIntensity, baseSpread = self:baseValues()
	sunRays.Intensity = baseIntensity + (SUNSET_INTENSITY - baseIntensity) * progress
	sunRays.Spread = baseSpread + (SUNSET_SPREAD - baseSpread) * progress
end

function ClientSunsetRaysManager:init()
	ClientRunCycleManager:subscribeSkyApplied(
		function()
			self:step()
		end
	)
end

function ClientSunsetRaysManager.new(): ClientSunsetRaysManager
	local self = setmetatable({}, ClientSunsetRaysManager) :: ClientSunsetRaysManager
	return self
end

return ClientSunsetRaysManager.new()
