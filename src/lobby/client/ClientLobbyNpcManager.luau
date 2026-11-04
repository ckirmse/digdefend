--!strict

-- Animates the lobby's decorative rigs (designer, 2026-11-03): the store
-- salespeople stand at their stalls in an idle loop and wave every so
-- often. A rig is any Model tagged Tags.LOBBY_NPC in Studio with a
-- Humanoid and an Animator, so adding one is a tag, not a code change.
-- Everything plays on the client: a Humanoid animated on the server would
-- replicate every joint for every player, and nothing about the pose
-- matters to anyone but the viewer.
local CollectionService = game:GetService("CollectionService")

local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local ClientLobbyNpcManager = {}
ClientLobbyNpcManager.__index = ClientLobbyNpcManager

type IdleClip = {
	animationId: string,
	-- how many times a draw of this clip runs it back to back
	plays: number,
}

type IdleTrack = {
	track: AnimationTrack,
	plays: number,
}

type NpcView = {
	model: Model,
	-- one track per idle clip; the idle loop plays one at a time
	idleTracks: { IdleTrack },
	waveTrack: AnimationTrack,
	-- the idle and wave loops' threads, stopped when the rig leaves
	idleThread: thread,
	waveThread: thread,
}

export type ClientLobbyNpcManager = typeof(setmetatable(
	{} :: {
		viewsByModel: { [Model]: NpcView },
		random: Random,
	},
	ClientLobbyNpcManager
))

-- Roblox's own R15 Idle1, Idle2, and Wave from the default Animate script.
-- The R6 pair (180435571, 128777973) was tried first and moved nothing: an
-- R6 clip names joints an R15 rig does not have. Each rig draws an idle
-- afresh every time one ends (designer, 2026-11-03), on its own, so the
-- salespeople never stand in step. Idle2 is a 2 s breath against Idle1's
-- 4 s, so a draw of it plays twice (designer, the same day)
local IDLE_CLIPS: { IdleClip } = {
	{
		animationId = "rbxassetid://507766666",
		plays = 1,
	},
	{
		animationId = "rbxassetid://507766951",
		plays = 2,
	},
}
local WAVE_ANIMATION_ID = "rbxassetid://507770239"
-- the pause between waves, drawn fresh each time (designer: 10 to 20 s)
local WAVE_INTERVAL_MIN_SEC = 10
local WAVE_INTERVAL_MAX_SEC = 20
-- the idle keeps playing under the wave; the wave sits above it so the
-- arm wins where both move a joint
local IDLE_PRIORITY = Enum.AnimationPriority.Idle
local WAVE_PRIORITY = Enum.AnimationPriority.Action
local FADE_SEC = 0.3

local function makeAnimation(animationId: string): Animation
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	return animation
end

function ClientLobbyNpcManager:runIdleLoop(view: NpcView)
	while view.model.Parent ~= nil do
		local idleTrack = view.idleTracks[self.random:NextInteger(1, #view.idleTracks)]
		for _ = 1, idleTrack.plays do
			idleTrack.track:Play(FADE_SEC)
			idleTrack.track.Stopped:Wait()
		end
	end
end

function ClientLobbyNpcManager:runWaveLoop(view: NpcView)
	while view.model.Parent ~= nil do
		task.wait(self.random:NextNumber(WAVE_INTERVAL_MIN_SEC, WAVE_INTERVAL_MAX_SEC))
		if view.model.Parent == nil then
			break
		end
		view.waveTrack:Play(FADE_SEC)
		view.waveTrack.Stopped:Wait()
	end
end

function ClientLobbyNpcManager:addRig(model: Instance)
	if not model:IsA("Model") or self.viewsByModel[model] ~= nil then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn(`{Tags.LOBBY_NPC} rig {model:GetFullName()} has no Humanoid.Animator; not animated`)
		return
	end

	local idleTracks: { IdleTrack } = {}
	for _, clip in IDLE_CLIPS do
		local track = animator:LoadAnimation(makeAnimation(clip.animationId))
		track.Priority = IDLE_PRIORITY
		-- played once each, so the loop can draw the next clip at its end
		track.Looped = false
		table.insert(idleTracks, {
			track = track,
			plays = clip.plays,
		})
	end
	local waveTrack = animator:LoadAnimation(makeAnimation(WAVE_ANIMATION_ID))
	waveTrack.Priority = WAVE_PRIORITY
	waveTrack.Looped = false

	local view: NpcView = {
		model = model,
		idleTracks = idleTracks,
		waveTrack = waveTrack,
		idleThread = nil :: any,
		waveThread = nil :: any,
	}
	self.viewsByModel[model] = view
	view.idleThread = task.spawn(
		function()
			self:runIdleLoop(view)
		end
	)
	view.waveThread = task.spawn(
		function()
			self:runWaveLoop(view)
		end
	)
end

function ClientLobbyNpcManager:removeRig(model: Instance)
	local view = self.viewsByModel[model :: Model]
	if view == nil then
		return
	end
	self.viewsByModel[model :: Model] = nil
	task.cancel(view.idleThread)
	task.cancel(view.waveThread)
	for _, idleTrack in view.idleTracks do
		idleTrack.track:Stop()
	end
	view.waveTrack:Stop()
end

function ClientLobbyNpcManager:init()
	for _, model in CollectionService:GetTagged(Tags.LOBBY_NPC) do
		self:addRig(model)
	end
	-- a rig that streams in later, or one the designer tags in Play
	CollectionService:GetInstanceAddedSignal(Tags.LOBBY_NPC):Connect(
		function(model)
			self:addRig(model)
		end
	)
	CollectionService:GetInstanceRemovedSignal(Tags.LOBBY_NPC):Connect(
		function(model)
			self:removeRig(model)
		end
	)
end

function ClientLobbyNpcManager.new(): ClientLobbyNpcManager
	local self = setmetatable({}, ClientLobbyNpcManager) :: ClientLobbyNpcManager
	self.viewsByModel = {}
	self.random = Random.new()
	return self
end

return ClientLobbyNpcManager.new()
