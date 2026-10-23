--!strict

-- The held Tool on this client (ToolManager builds it on the server): plays
-- the swing. Roblox's default Animate script watches a held Tool for a
-- StringValue named "toolanim" and plays the matching tool animation
-- ("Slash" is the forward swing) once, then removes the marker. The
-- animation replicates with the character, so every player sees it.
-- A swing at another pace (a class's Mining Speed, 2026-10-22) cannot go
-- through the marker, whose track the Animate script plays at one speed,
-- so it plays the same slash animation itself on the character's Animator
-- at the scaled speed, which replicates the same way.
local Players = game:GetService("Players")

local ClientHeldToolManager = {}
ClientHeldToolManager.__index = ClientHeldToolManager

export type ClientHeldToolManager = typeof(setmetatable(
	{} :: {
		-- the slash loaded on this character's Animator, for a paced swing
		pacedTrack: AnimationTrack?,
		pacedCharacter: Model?,
	},
	ClientHeldToolManager
))

local TOOL_ANIMATION_MARKER = "toolanim"
local SWING_ANIMATION = "Slash"
-- the Animate script's slot for the slash, whose Animation child is the
-- rig's own (R6 or R15)
local ANIMATE_SCRIPT_NAME = "Animate"
local ANIMATE_SLASH_SLOT = "toolslash"
local PACED_FADE_SEC = 0.1
-- a pace this close to 1 is the plain marker swing
local PACE_TOLERANCE = 0.01

function ClientHeldToolManager:getHeldTool(): Tool?
	local character = Players.LocalPlayer.Character
	return if character then character:FindFirstChildOfClass("Tool") else nil
end

-- the slash track on this character, loaded once per character from the
-- Animate script's own Animation; nil when the rig has none
function ClientHeldToolManager:getPacedTrack(): AnimationTrack?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	if self.pacedCharacter == character and self.pacedTrack then
		return self.pacedTrack
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	local animate = character:FindFirstChild(ANIMATE_SCRIPT_NAME)
	local slot = if animate then animate:FindFirstChild(ANIMATE_SLASH_SLOT) else nil
	local animation = if slot then slot:FindFirstChildOfClass("Animation") else nil
	if not animator or not animation then
		return nil
	end
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	self.pacedTrack = track
	self.pacedCharacter = character
	return track
end

-- one forward swing of whatever is held; a no-op with empty hands.
-- speedScale (1 by default) is how much faster than the authored swing
-- it plays, so the arm keeps time with a class that swings faster
function ClientHeldToolManager:playSwing(speedScale: number?)
	local tool = self:getHeldTool()
	if not tool then
		return
	end
	local scale = speedScale or 1
	if math.abs(scale - 1) > PACE_TOLERANCE then
		local track = self:getPacedTrack()
		if track then
			track:Play(PACED_FADE_SEC)
			track:AdjustSpeed(scale)
			return
		end
	end
	local marker = Instance.new("StringValue")
	marker.Name = TOOL_ANIMATION_MARKER
	marker.Value = SWING_ANIMATION
	marker.Parent = tool
end

function ClientHeldToolManager.new(): ClientHeldToolManager
	local self = setmetatable({}, ClientHeldToolManager) :: ClientHeldToolManager
	self.pacedTrack = nil
	self.pacedCharacter = nil
	return self
end

return ClientHeldToolManager.new()
