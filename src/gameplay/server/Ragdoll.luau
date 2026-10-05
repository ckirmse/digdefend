--!strict

-- Turns a character limp and back (M32: a dead player's body drops where
-- it fell for the Game Over screen). A character's limbs are held in pose
-- by one joint each. On today's avatars that joint is an
-- AnimationConstraint with a BallSocketConstraint already beside it, so
-- going limp is switching the AnimationConstraint off and letting the
-- socket carry the limb. An older rig uses Motor6Ds and has no sockets, so
-- one is built per joint here. Either way the joint is switched off, never
-- removed, and the joint that holds the root part is left alone so the
-- camera has something to follow; undoing it is switching the joints back
-- on. The character is never killed (that would respawn it), so its
-- Humanoid is told not to need a neck while it is limp. The owning client
-- puts the Humanoid in its Physics state so it stops trying to stand
-- (ClientReviveManager); this module only handles the joints.
local Ragdoll = {}

-- its presence on a character is what says the character is limp; it
-- also holds the sockets built for an older rig
local SOCKETS_FOLDER = "RagdollSockets"
local ATTACHMENT_NAME = "RagdollAttachment"
local ROOT_PART = "HumanoidRootPart"
-- how far a built joint may swing and twist, in degrees
local SWING_LIMIT_DEGREES = 50
local TWIST_LIMIT_DEGREES = 35

local function isRootPart(part: Instance?): boolean
	return part ~= nil and part.Name == ROOT_PART
end

function Ragdoll.isApplied(character: Model): boolean
	return character:FindFirstChild(SOCKETS_FOLDER) ~= nil
end

function Ragdoll.apply(character: Model)
	if Ragdoll.isApplied(character) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = SOCKETS_FOLDER
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("AnimationConstraint") then
			local attachment0 = descendant.Attachment0
			local attachment1 = descendant.Attachment1
			if attachment0 and attachment1 and not isRootPart(attachment0.Parent) and not isRootPart(attachment1.Parent) then
				descendant.Enabled = false
			end
		elseif descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if not part0 or not part1 or isRootPart(part0) or isRootPart(part1) then
				continue
			end
			local attachment0 = Instance.new("Attachment")
			attachment0.Name = ATTACHMENT_NAME
			attachment0.CFrame = descendant.C0
			attachment0.Parent = part0
			local attachment1 = Instance.new("Attachment")
			attachment1.Name = ATTACHMENT_NAME
			attachment1.CFrame = descendant.C1
			attachment1.Parent = part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = descendant.Name
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.LimitsEnabled = true
			socket.UpperAngle = SWING_LIMIT_DEGREES
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -TWIST_LIMIT_DEGREES
			socket.TwistUpperAngle = TWIST_LIMIT_DEGREES
			socket.Parent = folder
			descendant.Enabled = false
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RequiresNeck = false
	end
	folder.Parent = character
end

function Ragdoll.remove(character: Model)
	local folder = character:FindFirstChild(SOCKETS_FOLDER)
	if not folder then
		return
	end
	folder:Destroy()
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("AnimationConstraint") or descendant:IsA("Motor6D") then
			descendant.Enabled = true
		elseif descendant:IsA("Attachment") and descendant.Name == ATTACHMENT_NAME then
			descendant:Destroy()
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RequiresNeck = true
	end
end

return Ragdoll
