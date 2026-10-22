--!strict

-- The outdoors heard while the player is out of the mine (2026-10-21):
-- the OutdoorAmbience loop, 2D, faded in over FADE_IN_SEC as the player
-- steps out of the mine's grid and out over the quicker FADE_OUT_SEC as
-- they step in; through the night it sits at NIGHT_SHARE of its volume
-- under the night song, eased down over NIGHT_FADE_DOWN_SEC as night
-- falls and back up over NIGHT_FADE_UP_SEC at the night's end
-- (designer, 2026-10-21).
-- Whether they are in the mine is decided here, on this client alone,
-- from its own copy of the grid (ClientMineManager) with the same cell
-- test the server's run report uses (MineSpace.containsPosition), so
-- nothing travels over the network. The fade carries on from whatever
-- volume the loop has reached (ClientSoundManager:fadeMusicTo), so a
-- quick back and forth through the mouth never jumps or restarts it. No
-- character (dead, or between spawns) counts as indoors: silence.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientAmbienceManager = {}
ClientAmbienceManager.__index = ClientAmbienceManager

export type ClientAmbienceManager = typeof(setmetatable(
	{} :: {
		-- nil until the first sample, so the first answer always applies
		isOutdoors: boolean?,
		isNight: boolean,
		sampleAccumulatorSec: number,
	},
	ClientAmbienceManager
))

-- a full fade: silence to the authored volume on the way out of the
-- mine, and the quicker drop to silence on the way in (designer, 2026-10-21)
local FADE_IN_SEC = 3
local FADE_OUT_SEC = 1.5
-- the night's share of the authored volume, and how long the drop to it
-- and the climb back take (the fade is rate-based, so a half swing over
-- 3 s is a full-swing rate of 6 s)
local NIGHT_SHARE = 0.5
local NIGHT_FADE_DOWN_SEC = 3
local NIGHT_FADE_UP_SEC = 1
-- how often the player's position is checked against the grid
local SAMPLE_SEC = 0.2

function ClientAmbienceManager:isPlayerOutdoors(): boolean
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	local grid = ClientMineManager:getGrid()
	local space = ClientMineManager:getSpace()
	if not grid or not space then
		-- no mine yet (the arrival): the camp is outdoors
		return true
	end
	return not MineSpace.containsPosition(space, grid.depth, grid.height, grid.width, root.Position)
end

-- the level the loop should sit at: silent indoors, the night's share
-- at night, full by day
function ClientAmbienceManager:targetShare(): number
	if not self.isOutdoors then
		return 0
	end
	return if self.isNight then NIGHT_SHARE else 1
end

function ClientAmbienceManager:apply(isOutdoors: boolean)
	if self.isOutdoors == isOutdoors then
		return
	end
	self.isOutdoors = isOutdoors
	ClientSoundManager:fadeMusicTo(SoundNames.Music.OUTDOOR_AMBIENCE, self:targetShare(), if isOutdoors then FADE_IN_SEC else FADE_OUT_SEC)
end

-- night falling or ending moves the outdoor level between full and the
-- night's share; the swing is half the volume, so the rate is doubled
function ClientAmbienceManager:applyNight(isNight: boolean)
	if self.isNight == isNight then
		return
	end
	self.isNight = isNight
	if not self.isOutdoors then
		return
	end
	local swingSec = if isNight then NIGHT_FADE_DOWN_SEC else NIGHT_FADE_UP_SEC
	ClientSoundManager:fadeMusicTo(SoundNames.Music.OUTDOOR_AMBIENCE, self:targetShare(), swingSec / (1 - NIGHT_SHARE))
end

function ClientAmbienceManager:step(deltaSec: number)
	self.sampleAccumulatorSec += deltaSec
	if self.sampleAccumulatorSec < SAMPLE_SEC then
		return
	end
	self.sampleAccumulatorSec = 0
	self:apply(self:isPlayerOutdoors())
end

function ClientAmbienceManager:init()
	self.isNight = ClientDataManager:getGameMetadata(Attributes.IS_NIGHT) == true
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.IS_NIGHT,
		function(value: any)
			self:applyNight(value == true)
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function ClientAmbienceManager.new(): ClientAmbienceManager
	local self = setmetatable({}, ClientAmbienceManager) :: ClientAmbienceManager
	self.isOutdoors = nil
	self.isNight = false
	self.sampleAccumulatorSec = 0
	return self
end

return ClientAmbienceManager.new()
