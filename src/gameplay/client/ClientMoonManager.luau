--!strict

-- The map's moon (designer, 2026-10-21): the Moon folder under the camp
-- holds the Moon model and two marker parts, MoonStart (its daytime
-- place, below the rim) and MoonEnd (its place in the night sky), kept
-- inside a Markers model so the camp's persistent streaming carries them
-- to every client (a bare part 400 studs up would never stream in). The
-- model rises from MoonStart to MoonEnd over the night's first RISE_SEC
-- (from the night phase's start, held still through a pause), holds
-- there through the night, and over the DAWN stage (night end back to day
-- start, the same stretch the clock turns to morning) comes back down
-- from wherever it had got to, so a dawn forced mid-climb turns it round
-- (designer, 2026-10-21); it sits at MoonStart through the day. Driven
-- from the run cycle manager's sky-applied hook, so it is placed right
-- after the sky each frame from the same stage and share, and lands
-- right for a late joiner or a dev-tool jump. Visual only: the parts
-- are the map's, found when the camp has been cloned in.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientRunCycleManager = require(script.Parent.ClientRunCycleManager)

local ClientMoonManager = {}
ClientMoonManager.__index = ClientMoonManager

export type ClientMoonManager = typeof(setmetatable(
	{} :: {
		moon: Model?,
		-- the markers' frames, read once so moving the moon never matters
		startCFrame: CFrame?,
		endCFrame: CFrame?,
		-- the share last placed, so an unchanged frame writes nothing
		shownShare: number?,
		-- how high the moon was when the night ended, the top of its descent
		-- (1 for a joiner who never saw the night)
		riseAtNightEnd: number?,
	},
	ClientMoonManager
))

local MOON_FOLDER = "Moon"
local MOON_MODEL = "Moon"
local MOON_START = "MoonStart"
local MOON_END = "MoonEnd"
-- the climb from MoonStart to MoonEnd, from the night's start
local RISE_SEC = 30

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

-- the moon and its markers under the camp, found again whenever the camp
-- is replaced (a new run) or has not arrived yet
function ClientMoonManager:findMoon(): boolean
	local moon = self.moon
	if moon and moon.Parent and self.startCFrame and self.endCFrame then
		return true
	end
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	local folder = if camp then camp:FindFirstChild(MOON_FOLDER, true) else nil
	if not folder then
		return false
	end
	local model = folder:FindFirstChild(MOON_MODEL)
	local startPart = folder:FindFirstChild(MOON_START, true)
	local endPart = folder:FindFirstChild(MOON_END, true)
	if not model or not model:IsA("Model") or not startPart or not startPart:IsA("BasePart") or not endPart or not endPart:IsA("BasePart") then
		return false
	end
	-- the markers are the designer's guides, never drawn
	startPart.Transparency = 1
	endPart.Transparency = 1
	self.moon = model
	self.startCFrame = startPart.CFrame
	self.endCFrame = endPart.CFrame
	self.shownShare = nil
	return true
end

-- seconds since the night phase began, the clock held through a pause
function ClientMoonManager:nightElapsedSec(): number
	local startTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PHASE_START_TIME), 0)
	local now = workspace:GetServerTimeNow()
	local pauseStartTime = readNumber(ClientDataManager:getGameMetadata(Attributes.RUN_PAUSE_START_TIME), 0)
	if pauseStartTime > 0 then
		now = pauseStartTime
	end
	return math.max(now - startTime, 0)
end

-- how far up the moon is for a sky stage: 0 at MoonStart, 1 at MoonEnd
function ClientMoonManager:riseShare(stage: number, share: number): number
	if stage == Enums.SkyStage.DUSK or stage == Enums.SkyStage.NIGHT then
		local rise = math.clamp(self:nightElapsedSec() / RISE_SEC, 0, 1)
		self.riseAtNightEnd = rise
		return rise
	elseif stage == Enums.SkyStage.DAWN then
		return (self.riseAtNightEnd or 1) * (1 - share)
	end
	self.riseAtNightEnd = nil
	return 0
end

function ClientMoonManager:onSkyApplied(stage: number, share: number)
	if not self:findMoon() then
		return
	end
	local riseShare = math.clamp(self:riseShare(stage, share), 0, 1)
	if self.shownShare == riseShare then
		return
	end
	self.shownShare = riseShare
	local moon = self.moon :: Model
	local startCFrame = self.startCFrame :: CFrame
	local endCFrame = self.endCFrame :: CFrame
	moon:PivotTo(startCFrame:Lerp(endCFrame, riseShare))
end

function ClientMoonManager:init()
	ClientRunCycleManager:subscribeSkyApplied(
		function(stage: number, share: number)
			self:onSkyApplied(stage, share)
		end
	)
end

function ClientMoonManager.new(): ClientMoonManager
	local self = setmetatable({}, ClientMoonManager) :: ClientMoonManager
	self.moon = nil
	self.startCFrame = nil
	self.endCFrame = nil
	self.shownShare = nil
	self.riseAtNightEnd = nil
	return self
end

return ClientMoonManager.new()
