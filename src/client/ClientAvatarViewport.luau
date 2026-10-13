--!strict

-- The spinning 3D avatar on a Character Menu card (M37, designer:
-- 2026-10-12): a copy of the player's own character stood in a
-- ViewportFrame in its rest pose and turned slowly on the spot. One copy
-- of the character is made the first time it is asked for; every viewport
-- gets its own clone, posed from its joints (a straight clone keeps
-- whatever frame of animation the live character was in, since nothing
-- animates inside a viewport), dressed for the character it shows, and
-- one Heartbeat loop turns every viewport that is on screen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Wearables = require("@game/ReplicatedStorage/Shared/Wearables")

local ClientAvatarViewport = {}
ClientAvatarViewport.__index = ClientAvatarViewport

type Spinner = {
	viewport: ViewportFrame,
	model: Model,
	angle: number,
}

export type ClientAvatarViewport = typeof(setmetatable(
	{} :: {
		template: Model?,
		spinners: { [ViewportFrame]: Spinner },
		heartbeat: RBXScriptConnection?,
	},
	ClientAvatarViewport
))

local TURN_DEGREES_PER_SEC = 40
-- the camera stands this far in front of the model, framed on its
-- bounding box, with the field of view narrow enough to fill the card
local AVATAR_FOV = 30
local AVATAR_DISTANCE_FACTOR = 2.0
local DIMMED_COLOR = Color3.fromRGB(70, 70, 70)

-- puts every part where its joints say it rests: walk the rig from the
-- root, clear each joint's animation transform (this rig's limbs hang on
-- AnimationConstraints between rig attachments; a Motor6D rig is covered
-- too), and seat each joined part from its joint's offsets. WeldConstraints
-- carry no offsets, so theirs are read off the model before anything moves.
-- A weld is followed from whichever side the walk reaches first: Roblox's
-- AccessoryWeld runs from the accessory's Handle to the Head, so a hair or
-- a back accessory would otherwise be left at the animated frame it was
-- cloned in (hair hanging in front of the face on the cards, 2026-10-13)
local function restPose(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local jointsByPart0: { [BasePart]: { Instance } } = {}
	local weldOffsets: { [WeldConstraint]: CFrame } = {}
	for _, descendant in model:GetDescendants() do
		local part0: BasePart? = nil
		if descendant:IsA("AnimationConstraint") then
			local attachment0 = descendant.Attachment0
			local parent0 = if attachment0 then attachment0.Parent else nil
			part0 = if parent0 and parent0:IsA("BasePart") then parent0 else nil
		elseif descendant:IsA("Motor6D") or descendant:IsA("Weld") then
			part0 = descendant.Part0
		elseif descendant:IsA("WeldConstraint") and descendant.Part0 and descendant.Part1 then
			part0 = descendant.Part0
			weldOffsets[descendant] = descendant.Part0.CFrame:Inverse() * descendant.Part1.CFrame
		end
		if part0 then
			local joints = jointsByPart0[part0] or {}
			table.insert(joints, descendant)
			jointsByPart0[part0] = joints
		end
		-- a weld is indexed under both its parts so the walk can cross it
		-- from either side; an AnimationConstraint always runs rig-outward
		if (descendant:IsA("Motor6D") or descendant:IsA("Weld") or descendant:IsA("WeldConstraint")) and descendant.Part1 then
			local part1 = descendant.Part1 :: BasePart
			local joints = jointsByPart0[part1] or {}
			table.insert(joints, descendant)
			jointsByPart0[part1] = joints
		end
	end
	local visited: { [BasePart]: boolean } = { [root] = true }
	local queue: { BasePart } = { root }
	while #queue > 0 do
		local part = table.remove(queue, 1) :: BasePart
		for _, joint in jointsByPart0[part] or {} do
			local child: BasePart? = nil
			if joint:IsA("AnimationConstraint") then
				joint.Transform = CFrame.identity
				local attachment0, attachment1 = joint.Attachment0, joint.Attachment1
				local parent1 = if attachment1 then attachment1.Parent else nil
				if attachment0 and attachment1 and parent1 and parent1:IsA("BasePart") then
					child = parent1
					parent1.CFrame = part.CFrame * attachment0.CFrame * attachment1.CFrame:Inverse()
				end
			elseif joint:IsA("Motor6D") or joint:IsA("Weld") then
				if joint:IsA("Motor6D") then
					joint.Transform = CFrame.identity
				end
				if joint.Part0 == part then
					child = joint.Part1
					if child then
						child.CFrame = part.CFrame * joint.C0 * joint.C1:Inverse()
					end
				else
					child = joint.Part0
					if child then
						child.CFrame = part.CFrame * joint.C1 * joint.C0:Inverse()
					end
				end
			elseif joint:IsA("WeldConstraint") then
				if joint.Part0 == part then
					child = joint.Part1
					if child then
						child.CFrame = part.CFrame * weldOffsets[joint]
					end
				else
					child = joint.Part0
					if child then
						child.CFrame = part.CFrame * weldOffsets[joint]:Inverse()
					end
				end
			end
			if child and not visited[child] then
				visited[child] = true
				table.insert(queue, child)
			end
		end
	end
end

-- the character's equipped cosmetics on the preview (Enums.CosmeticSlot
-- key name -> skin id). Hats swap the avatar's own hat for the equipped
-- one (first pass, 2026-10-12); the gear skins join with M61's art
local function applyCosmetics(model: Model, cosmetics: { [string]: string }?)
	if not cosmetics then
		return
	end
	local hatId = cosmetics[Enums.getName(Enums.CosmeticSlot, Enums.CosmeticSlot.HELMET) :: string]
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local hats = if gameAssets then gameAssets:FindFirstChild(Constants.HAT_TEMPLATES_FOLDER) else nil
	local template = if hats and hatId then hats:FindFirstChild(hatId) else nil
	-- the copy was taken from the live character, which may be wearing
	-- another character's hat: always start bare-headed
	Wearables.removeHatAccessories(model)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local ownHats = if playerGui then playerGui:FindFirstChild(Constants.OWN_HATS_FOLDER) else nil
	if template and template:IsA("Accessory") then
		-- a template is raw catalogue size; the live character's Humanoid
		-- would scale it to the build, so the server's measured factor does
		local scale = if ownHats then ownHats:GetAttribute(Attributes.HAT_SCALE) else nil
		Wearables.wearAccessory(model, template, if typeof(scale) == "number" then scale else 1)
		return
	end
	-- the player's own hats, as the server copied them (already worn size)
	if not ownHats then
		return
	end
	for _, ownHat in ownHats:GetChildren() do
		if ownHat:IsA("Accessory") then
			Wearables.wearAccessory(model, ownHat)
		end
	end
end

-- a copy of the player's own character, made once so an avatar that loads
-- late is still caught the first time a menu opens
function ClientAvatarViewport:getTemplate(): Model?
	if self.template then
		return self.template
	end
	local character = Players.LocalPlayer.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return nil
	end
	character.Archivable = true
	local copy = character:Clone()
	copy.Name = "Avatar"
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	self.template = copy
	return copy
end

-- stands a fresh copy in the viewport in its rest pose, facing the
-- camera, dressed in `cosmetics`, and starts it turning; `isDimmed` is the
-- locked slot's darkened look
function ClientAvatarViewport:fill(viewport: ViewportFrame, isDimmed: boolean, cosmetics: { [string]: string }?)
	self:clear(viewport)
	local template = self:getTemplate()
	if not template then
		return
	end
	local model = template:Clone()
	model:PivotTo(CFrame.new(0, 0, 0))
	restPose(model)
	applyCosmetics(model, cosmetics)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = AVATAR_FOV
	local lookAt = boundsCFrame.Position
	camera.CFrame = CFrame.lookAt(lookAt + Vector3.new(0, 0, boundsSize.Y * AVATAR_DISTANCE_FACTOR), lookAt)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.ImageColor3 = if isDimmed then DIMMED_COLOR else Color3.new(1, 1, 1)

	self.spinners[viewport] = {
		viewport = viewport,
		model = model,
		angle = 0,
	}
	self:startIfNeeded()
end

function ClientAvatarViewport:clear(viewport: ViewportFrame)
	self.spinners[viewport] = nil
	viewport:ClearAllChildren()
end

function ClientAvatarViewport:step(deltaSec: number)
	for viewport, spinner in self.spinners do
		-- a card that was destroyed with its menu drops out here
		if viewport.Parent == nil then
			self.spinners[viewport] = nil
			continue
		end
		if not viewport.Visible then
			continue
		end
		spinner.angle += math.rad(TURN_DEGREES_PER_SEC) * deltaSec
		spinner.model:PivotTo(CFrame.Angles(0, spinner.angle, 0))
	end
	if next(self.spinners) == nil then
		self:stop()
	end
end

function ClientAvatarViewport:startIfNeeded()
	if self.heartbeat then
		return
	end
	self.heartbeat = RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function ClientAvatarViewport:stop()
	local heartbeat = self.heartbeat
	if heartbeat then
		heartbeat:Disconnect()
		self.heartbeat = nil
	end
end

function ClientAvatarViewport.new(): ClientAvatarViewport
	local self = setmetatable({}, ClientAvatarViewport) :: ClientAvatarViewport
	self.template = nil
	self.spinners = {}
	self.heartbeat = nil
	return self
end

return ClientAvatarViewport.new()
