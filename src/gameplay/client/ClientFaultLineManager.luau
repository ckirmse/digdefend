--!strict

-- The Fault Line Drill's crack as this client draws it (2026-10-22). The
-- server decides the hits and sends NotifyPostFaultLine: the crack's
-- points along the ground (FaultLineRules.samplePoints) from where the
-- drill landed, its width, how fast it races, and how long each spike
-- stands. Each point gets a couple of rock spikes cloned from
-- GameAssets/Effects/RockSpike, spread across the width, that burst up
-- out of the ground in turn as the crack races on, stand their second,
-- then sink and go (short lives and few parts, by decision, so a long
-- crack never piles parts into the workspace). The kind's CRACK sound
-- (rock breaking, designer 2026-10-22) is a loop on an anchor that rides
-- the crack's front as it races and stops with it. The drill itself is
-- ClientProjectileManager's; its fire sound is the gunner's own.
-- Nothing here is gameplay: the knockdown rides the monster snapshot.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientFaultLineManager = {}
ClientFaultLineManager.__index = ClientFaultLineManager

-- the crack's sound anchor racing along the points
type Front = {
	anchor: BasePart,
	player: AudioPlayer?,
	points: { Vector3 },
	raceStudsPerSec: number,
	startTime: number,
	lengthStuds: number,
}

export type ClientFaultLineManager = typeof(setmetatable(
	{} :: {
		random: Random,
		hasWarnedTemplate: boolean,
		fronts: { Front },
	},
	ClientFaultLineManager
))

local NOTIFY_POST_FAULT_LINE_SHAPE = {
	userId = "integer",
	weaponKind = { type = "enum", name = "PostWeaponKind" },
	points = { type = "array", elementType = "vector3", nonempty = true },
	widthStuds = "positiveNumber",
	spikeSec = "positiveNumber",
	raceStudsPerSec = "positiveNumber",
}

local TEMPLATE_NAME = "RockSpike"
local SPIKES_PER_POINT = 2
local RISE_SEC = 0.12
local SINK_SEC = 0.3
-- a spike leans up to this far from straight up
local LEAN_DEGREES = 25
local SCALE_MIN = 0.7
local SCALE_MAX = 1.3
-- how far under its half height a waiting spike sits, as a share of its
-- height plus a fixed margin (designer, 2026-10-22: the leaning ones showed)
local BURIED_SHARE = 0.25
local BURIED_EXTRA_STUDS = 0.5
-- the crack's own sound (the kind's CRACK), heard from its racing front
local CRACK_SOUND_FULL_VOLUME_STUDS = 80
local EFFECT_RANGE_STUDS = 500
local FRONT_ANCHOR_NAME = "FaultLineFront"

function ClientFaultLineManager:findTemplate(): BasePart?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local effects = if gameAssets then gameAssets:FindFirstChild(Constants.EFFECT_TEMPLATES_FOLDER) else nil
	local template = if effects then effects:FindFirstChild(TEMPLATE_NAME) else nil
	if template and template:IsA("BasePart") then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientFaultLineManager: no {TEMPLATE_NAME} part under GameAssets.{Constants.EFFECT_TEMPLATES_FOLDER}; run scripts/studio/build_rock_spike.luau`)
	end
	return nil
end

-- one spike: rises from under the ground, stands, sinks and goes
function ClientFaultLineManager:raiseSpike(template: BasePart, groundPosition: Vector3, delaySec: number, standSec: number)
	local random = self.random
	local spike = template:Clone()
	local scale = random:NextNumber(SCALE_MIN, SCALE_MAX)
	spike.Size = template.Size * scale
	local lean = CFrame.Angles(math.rad(random:NextNumber(-LEAN_DEGREES, LEAN_DEGREES)), math.rad(random:NextNumber(0, 360)), math.rad(random:NextNumber(-LEAN_DEGREES, LEAN_DEGREES)))
	local height = spike.Size.Y
	local up = CFrame.new(groundPosition + Vector3.new(0, height / 2, 0)) * lean
	-- buried deeper than its own half height: a leaning spike's top corner
	-- would otherwise poke through the ground before its turn comes
	local down = CFrame.new(groundPosition - Vector3.new(0, height / 2 + height * BURIED_SHARE + BURIED_EXTRA_STUDS, 0)) * lean
	spike.CFrame = down
	spike.Parent = workspace
	task.delay(
		delaySec,
		function()
			if not spike.Parent then
				return
			end
			TweenService:Create(spike, TweenInfo.new(RISE_SEC, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = up }):Play()
			task.delay(
				RISE_SEC + standSec,
				function()
					if not spike.Parent then
						return
					end
					TweenService:Create(spike, TweenInfo.new(SINK_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = down }):Play()
				end
			)
		end
	)
	Debris:AddItem(spike, delaySec + RISE_SEC + standSec + SINK_SEC + 0.1)
end

function ClientFaultLineManager:onFaultLine(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_POST_FAULT_LINE_SHAPE) then
		warn("ClientFaultLineManager: malformed NotifyPostFaultLine")
		return
	end
	local points: { Vector3 } = payload.points
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - points[1]).Magnitude > EFFECT_RANGE_STUDS then
		return
	end
	local set = SoundNames.PostWeaponSfxByKindName[Enums.getName(Enums.PostWeaponKind, payload.weaponKind) :: string]
	if set and set.CRACK then
		self:startFront(points, payload.raceStudsPerSec, set.CRACK)
	end
	local template = self:findTemplate()
	if not template then
		return
	end
	local random = self.random
	local halfWidth = payload.widthStuds / 2
	local origin = points[1]
	for index, point in points do
		local distance = (Vector3.new(point.X, 0, point.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude
		local delaySec = distance / payload.raceStudsPerSec
		local next = points[math.min(index + 1, #points)]
		local previous = points[math.max(index - 1, 1)]
		local along = Vector3.new(next.X - previous.X, 0, next.Z - previous.Z)
		local across = if along.Magnitude > 1e-3 then Vector3.new(-along.Unit.Z, 0, along.Unit.X) else Vector3.xAxis
		for _ = 1, SPIKES_PER_POINT do
			local offset = across * random:NextNumber(-halfWidth, halfWidth)
			self:raiseSpike(template, point + offset, delaySec + random:NextNumber(0, 0.05), payload.spikeSec)
		end
	end
end

-- the sound front: an invisible anchor carrying the loop, started at the
-- crack's first point and moved along the points at the race speed by
-- stepFronts until it reaches the last, where it goes silent and is gone
function ClientFaultLineManager:startFront(points: { Vector3 }, raceStudsPerSec: number, soundName: string)
	local lengthStuds = 0
	for index = 2, #points do
		lengthStuds += (points[index] - points[index - 1]).Magnitude
	end
	local anchor = Instance.new("Part")
	anchor.Name = FRONT_ANCHOR_NAME
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(points[1])
	anchor.Parent = workspace
	local player = ClientSoundManager:attachLoop(anchor, soundName, CRACK_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
	table.insert(self.fronts, {
		anchor = anchor,
		player = player,
		points = points,
		raceStudsPerSec = math.max(raceStudsPerSec, 1),
		startTime = workspace:GetServerTimeNow(),
		lengthStuds = lengthStuds,
	})
end

-- where along the points a distance from the first lands
local function pointAlong(points: { Vector3 }, distance: number): Vector3
	local left = distance
	for index = 2, #points do
		local segment = points[index] - points[index - 1]
		local segmentLength = segment.Magnitude
		if left <= segmentLength then
			return points[index - 1] + (if segmentLength > 1e-6 then segment.Unit * left else Vector3.zero)
		end
		left -= segmentLength
	end
	return points[#points]
end

function ClientFaultLineManager:stepFronts()
	if #self.fronts == 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	local kept = {}
	for _, front in self.fronts do
		local distance = (now - front.startTime) * front.raceStudsPerSec
		if distance >= front.lengthStuds then
			if front.player then
				front.player:Stop()
			end
			front.anchor:Destroy()
			continue
		end
		front.anchor.CFrame = CFrame.new(pointAlong(front.points, distance))
		table.insert(kept, front)
	end
	self.fronts = kept
end

function ClientFaultLineManager:init()
	RunService.RenderStepped:Connect(
		function()
			self:stepFronts()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_POST_FAULT_LINE,
		function(payload: any)
			self:onFaultLine(payload)
		end
	)
end

function ClientFaultLineManager.new(): ClientFaultLineManager
	local self = setmetatable({}, ClientFaultLineManager) :: ClientFaultLineManager
	self.random = Random.new()
	self.hasWarnedTemplate = false
	self.fronts = {}
	return self
end

return ClientFaultLineManager.new()
