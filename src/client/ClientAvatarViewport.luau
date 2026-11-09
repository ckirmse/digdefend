--!strict

-- The 3D avatar in a menu (M37, designer: 2026-10-12; the Class Menu's
-- turnable one since 2026-11-04): a copy of the player's own character
-- stood in a ViewportFrame in its rest pose, dressed for a class's
-- loadout (its hat, its pick axe in hand, its jet pack on its back), and
-- either turned slowly on the spot or turned by the player dragging
-- across the frame. One copy of the character is made the first time it
-- is asked for; every viewport gets its own clone, posed from its joints
-- (a straight clone keeps whatever frame of animation the live character
-- was in, since nothing animates inside a viewport), and one Heartbeat
-- loop turns every viewport that is on screen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local CosmeticLoadoutSchema = require("@game/ReplicatedStorage/Shared/CosmeticLoadoutSchema")
local Wearables = require("@game/ReplicatedStorage/Shared/Wearables")

local ClientAvatarViewport = {}
ClientAvatarViewport.__index = ClientAvatarViewport

type Spinner = {
	viewport: ViewportFrame,
	model: Model,
	angle: number,
	-- turns on its own; a dragged one holds still between drags
	isTurning: boolean,
	-- the drag in progress: where the pointer last was
	dragLastX: number?,
	connections: { RBXScriptConnection },
}

export type Options = {
	-- the locked slot's darkened look
	isDimmed: boolean?,
	-- Enums.CosmeticSlot key name -> skin id, the class's loadout
	cosmetics: { [string]: string }?,
	-- turn on the spot (the default) or only when dragged
	isTurning: boolean?,
	-- the player can drag across the frame to turn the avatar
	isDraggable: boolean?,
	-- the facing to start at; the model faces the camera at 0
	startAngle: number?,
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
-- a drag across the whole frame turns the avatar this far
local DRAG_TURNS_PER_FRAME_WIDTH = 1.0
-- the camera stands this far in front of the model, framed on its
-- bounding box, with the field of view narrow enough to fill the card
local AVATAR_FOV = 30
-- the camera stands this many body heights back; the figure's drawn size
-- goes as the inverse, so the 2.0 of the first build was divided by 0.9
-- to draw it a tenth smaller in the same frame (designer, 2026-11-09)
local AVATAR_DISTANCE_FACTOR = 2.0 / 0.9
local DIMMED_COLOR = Color3.fromRGB(70, 70, 70)
-- the pick axe held in the right hand: the model's haft runs along its
-- own Y, so it is turned to stand up out of the grip and lean forward
local PICK_AXE_GRIP_OFFSET = CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, 0.6, 0)
local AVATAR_PICK_AXE_NAME = "AvatarPickAxe"
local AVATAR_JET_PACK_NAME = "AvatarJetPack"

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

local function getGameAssets(): Instance?
	return ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
end

-- the template a slot's skin id names under GameAssets/Cosmetics/<SLOT>;
-- the stock skin is the DEFAULT template, an unknown id nothing
local function findSkinTemplate(slot: number, skinId: string?): Model?
	local gameAssets = getGameAssets()
	local cosmetics = if gameAssets then gameAssets:FindFirstChild(Constants.COSMETIC_TEMPLATES_FOLDER) else nil
	local slotName = Enums.getName(Enums.CosmeticSlot, slot)
	local folder = if cosmetics and slotName then cosmetics:FindFirstChild(slotName) else nil
	if not folder then
		return nil
	end
	local templateName = if skinId == nil or skinId == CosmeticLoadoutSchema.DEFAULT_SKIN_ID then Constants.DEFAULT_SKIN_TEMPLATE else skinId
	local template = folder:FindFirstChild(templateName)
	return if template and template:IsA("Model") then template else nil
end

-- a prop placed by its pivot inside the avatar model, so the avatar's
-- own PivotTo carries it; nothing in a viewport simulates, so no weld
local function placeProp(model: Model, template: Model, name: string, cframe: CFrame)
	local prop = template:Clone()
	prop.Name = name
	for _, descendant in prop:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end
	prop:PivotTo(cframe)
	prop.Parent = model
end

-- the pick axe stands in the right hand's grip, the jet pack hangs from
-- the torso's back attachment
local function applyGearSkins(model: Model, cosmetics: { [string]: string })
	local pickAxeSlot = Enums.getName(Enums.CosmeticSlot, Enums.CosmeticSlot.PICK_AXE) :: string
	local jetPackSlot = Enums.getName(Enums.CosmeticSlot, Enums.CosmeticSlot.JET_PACK) :: string
	local pickAxe = findSkinTemplate(Enums.CosmeticSlot.PICK_AXE, cosmetics[pickAxeSlot])
	local rightHand = model:FindFirstChild("RightHand")
	local grip = if rightHand then rightHand:FindFirstChild("RightGripAttachment") else nil
	if pickAxe and grip and grip:IsA("Attachment") then
		placeProp(model, pickAxe, AVATAR_PICK_AXE_NAME, grip.WorldCFrame * PICK_AXE_GRIP_OFFSET)
	end
	local jetPack = findSkinTemplate(Enums.CosmeticSlot.JET_PACK, cosmetics[jetPackSlot])
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	local back = if torso then torso:FindFirstChild("BodyBackAttachment") else nil
	local handle = if jetPack then jetPack:FindFirstChild(Constants.TOOL_HANDLE_PART) else nil
	if jetPack and back and back:IsA("Attachment") and handle and handle:IsA("BasePart") then
		-- the server's wearOnBack hangs the Handle this far behind the attachment
		local handleOffset = jetPack:GetPivot():Inverse() * handle.CFrame
		placeProp(model, jetPack, AVATAR_JET_PACK_NAME, back.WorldCFrame * CFrame.new(0, 0, handle.Size.Z / 2) * handleOffset:Inverse())
	end
end

-- the class's equipped cosmetics on the preview (Enums.CosmeticSlot key
-- name -> skin id). Hats swap the avatar's own hat for the equipped one
-- (first pass, 2026-10-12); the pick axe and the jet pack are the slot's
-- template under GameAssets/Cosmetics (2026-11-04)
local function applyCosmetics(model: Model, cosmetics: { [string]: string }?)
	if not cosmetics then
		return
	end
	-- the copy was taken from the live character, which wears the active
	-- class's jet pack: it comes off so the shown class's goes on
	local wornJetPack = model:FindFirstChild(Constants.WORN_JET_PACK_MODEL)
	if wornJetPack then
		wornJetPack:Destroy()
	end
	applyGearSkins(model, cosmetics)
	local hatId = cosmetics[Enums.getName(Enums.CosmeticSlot, Enums.CosmeticSlot.HELMET) :: string]
	local gameAssets = getGameAssets()
	local hats = if gameAssets then gameAssets:FindFirstChild(Constants.HAT_TEMPLATES_FOLDER) else nil
	local template = if hats and hatId then hats:FindFirstChild(hatId) else nil
	-- the copy may be wearing another class's hat: always start bare-headed
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

-- a drag across the frame turns the avatar by hand (mouse or touch); the
-- auto turn is off while a drag is held and stays off after
function ClientAvatarViewport:watchDrag(spinner: Spinner)
	local viewport = spinner.viewport
	table.insert(
		spinner.connections,
		viewport.InputBegan:Connect(
			function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					spinner.dragLastX = input.Position.X
					spinner.isTurning = false
				end
			end
		)
	)
	table.insert(
		spinner.connections,
		UserInputService.InputChanged:Connect(
			function(input: InputObject)
				local lastX = spinner.dragLastX
				if lastX == nil then
					return
				end
				if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local width = math.max(viewport.AbsoluteSize.X, 1)
				spinner.angle += (input.Position.X - lastX) / width * DRAG_TURNS_PER_FRAME_WIDTH * math.pi * 2
				spinner.dragLastX = input.Position.X
				spinner.model:PivotTo(CFrame.Angles(0, spinner.angle, 0))
			end
		)
	)
	table.insert(
		spinner.connections,
		UserInputService.InputEnded:Connect(
			function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					spinner.dragLastX = nil
				end
			end
		)
	)
end

-- stands a fresh copy in the viewport in its rest pose, facing the
-- camera, dressed for `options.cosmetics`, and starts it turning (or
-- waiting to be dragged)
function ClientAvatarViewport:fill(viewport: ViewportFrame, options: Options?)
	self:clear(viewport)
	local template = self:getTemplate()
	if not template then
		return
	end
	local settings: Options = options or {}
	local model = template:Clone()
	model:PivotTo(CFrame.new(0, 0, 0))
	restPose(model)
	-- the copy's own accessories come with no joints, so they kept the
	-- frame the character was animated in when it was copied (a mask a
	-- stud off the face after walking into the stall, 2026-11-09): each
	-- is seated on its attachment now that the body is at rest
	for _, child in model:GetChildren() do
		if child:IsA("Accessory") and not Wearables.isAccessoryJointed(child) then
			Wearables.seatAccessory(model, child)
		end
	end
	applyCosmetics(model, settings.cosmetics)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local startAngle = settings.startAngle or 0
	model:PivotTo(CFrame.Angles(0, startAngle, 0))
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = AVATAR_FOV
	local lookAt = boundsCFrame.Position
	-- a character's front is its -Z, so the camera stands on that side and
	-- the model faces it at angle 0
	camera.CFrame = CFrame.lookAt(lookAt - Vector3.new(0, 0, boundsSize.Y * AVATAR_DISTANCE_FACTOR), lookAt)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.ImageColor3 = if settings.isDimmed then DIMMED_COLOR else Color3.new(1, 1, 1)

	local spinner: Spinner = {
		viewport = viewport,
		model = model,
		angle = startAngle,
		isTurning = settings.isTurning ~= false,
		dragLastX = nil,
		connections = {},
	}
	self.spinners[viewport] = spinner
	if settings.isDraggable then
		self:watchDrag(spinner)
	end
	self:startIfNeeded()
end

function ClientAvatarViewport:clear(viewport: ViewportFrame)
	local spinner = self.spinners[viewport]
	if spinner then
		for _, connection in spinner.connections do
			connection:Disconnect()
		end
	end
	self.spinners[viewport] = nil
	viewport:ClearAllChildren()
end

function ClientAvatarViewport:step(deltaSec: number)
	for viewport, spinner in self.spinners do
		-- a card that was destroyed with its menu drops out here
		if viewport.Parent == nil then
			self:clear(viewport)
			continue
		end
		if not viewport.Visible or not spinner.isTurning then
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
