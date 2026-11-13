--!strict

-- Worn models on a character (the jet pack, M21; the lobby and the menu
-- avatars since 2026-10-12): the one place a back item is stripped and a
-- template welded to the back, so the lobby server, the gameplay client,
-- and the menu avatars dress a character the same way. Takes instances,
-- so it is not unit tested; the rules it applies are small.
local Constants = require(script.Parent.Constants)

local Wearables = {}

-- the fallback seat of a worn model when the rig has no back attachment
local DEFAULT_BACK_OFFSET = CFrame.new(0, 0, 0.6)

-- the worn jet pack has one template per level, as the pick axe does
function Wearables.jetPackTemplateName(level: number): string
	return `{Constants.JET_PACK_TEMPLATE}_{level}`
end

local function getTorso(character: Model): BasePart?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

-- a Roblox back accessory (a backpack, wings, a cape) comes off so the
-- worn model has the back to itself (designer, 2026-10-12)
function Wearables.removeBackAccessories(character: Model)
	for _, child in character:GetChildren() do
		if not child:IsA("Accessory") then
			continue
		end
		local handle = child:FindFirstChild(Constants.TOOL_HANDLE_PART)
		local isBack = child.AccessoryType == Enum.AccessoryType.Back
			or (handle ~= nil and handle:FindFirstChild("BodyBackAttachment") ~= nil)
		if isBack then
			child:Destroy()
		end
	end
end

-- a legacy catalogue hat reports Unknown, so its hat attachment tells
-- a Humanoid shrinks or grows a worn accessory to the avatar's build; a
-- rig without one gets the same treatment here: the handle, its mesh, and
-- every attachment offset by one factor
local function scaleAccessory(accessory: Accessory, handle: BasePart, scale: number)
	if scale == 1 then
		return
	end
	handle.Size = handle.Size * scale
	local mesh = handle:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.Scale = mesh.Scale * scale
	end
	for _, child in handle:GetChildren() do
		if child:IsA("Attachment") then
			child.Position = child.Position * scale
		end
	end
	accessory.AttachmentPoint = accessory.AttachmentPoint.Rotation + accessory.AttachmentPoint.Position * scale
end

-- puts an accessory on a rig that has no Humanoid to do it (a menu
-- avatar): the handle's attachment meets the rig's attachment of the same
-- name; a legacy hat with no attachment hangs from the top of the head by
-- its AttachmentPoint. `scale` is the Humanoid's build factor (1 for a
-- copy that was already worn)
-- the rig's attachment an accessory's handle attachment meets: the one
-- of the same name on a body part, never on another accessory's handle
local function findRigAttachment(character: Model, name: string): Attachment?
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == name then
			local parent = descendant.Parent
			local owner = if parent then parent.Parent else nil
			if parent and parent:IsA("BasePart") and not (owner and owner:IsA("Accessory")) then
				return descendant
			end
		end
	end
	return nil
end

-- seats an accessory already in the rig on the body part its handle
-- attachment names (a legacy hat with none hangs from the top of the
-- head by its AttachmentPoint) and welds it there; false when the rig has
-- nothing to hang it from. A copied character's accessories arrive with
-- no joints, so without this they keep the animated frame they were
-- copied in (a mask a stud off the face, 2026-11-09)
function Wearables.seatAccessory(character: Model, accessory: Accessory): boolean
	local handle = accessory:FindFirstChild(Constants.TOOL_HANDLE_PART)
	if not handle or not handle:IsA("BasePart") then
		return false
	end
	local handleAttachment = handle:FindFirstChildOfClass("Attachment")
	local rigAttachment = if handleAttachment then findRigAttachment(character, handleAttachment.Name) else nil
	local anchor: BasePart? = nil
	if handleAttachment and rigAttachment and rigAttachment.Parent and rigAttachment.Parent:IsA("BasePart") then
		anchor = rigAttachment.Parent
		handle.CFrame = rigAttachment.WorldCFrame * handleAttachment.CFrame:Inverse()
	else
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return false
		end
		anchor = head
		handle.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0) * accessory.AttachmentPoint:Inverse()
	end
	for _, child in handle:GetChildren() do
		if child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("Motor6D") then
			child:Destroy()
		end
	end
	local weld = Instance.new("Weld")
	weld.Part0 = anchor
	weld.Part1 = handle
	weld.C0 = (anchor :: BasePart).CFrame:Inverse() * handle.CFrame
	weld.Parent = handle
	return true
end

-- whether an accessory's handle is joined to anything
function Wearables.isAccessoryJointed(accessory: Accessory): boolean
	local handle = accessory:FindFirstChild(Constants.TOOL_HANDLE_PART)
	if not handle then
		return false
	end
	for _, child in handle:GetChildren() do
		if (child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("Motor6D")) and child.Part0 and child.Part1 then
			return true
		end
	end
	return false
end

function Wearables.wearAccessory(character: Model, template: Accessory, scale: number?): Accessory?
	local templateHandle = template:FindFirstChild(Constants.TOOL_HANDLE_PART)
	if not templateHandle or not templateHandle:IsA("BasePart") then
		return nil
	end
	local accessory = template:Clone()
	local handle = accessory:FindFirstChild(Constants.TOOL_HANDLE_PART) :: BasePart
	scaleAccessory(accessory, handle, scale or 1)
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	if not Wearables.seatAccessory(character, accessory) then
		return nil
	end
	accessory.Parent = character
	return accessory
end

-- a copy of the template welded to the character's back by its Handle;
-- nil when the rig has no torso to hang it from
function Wearables.wearOnBack(character: Model, template: Model, modelName: string): Model?
	local torso = getTorso(character)
	local templateHandle = template:FindFirstChild(Constants.TOOL_HANDLE_PART)
	if not torso or not templateHandle or not templateHandle:IsA("BasePart") then
		return nil
	end
	local existing = character:FindFirstChild(modelName)
	if existing then
		existing:Destroy()
	end
	local model = template:Clone()
	model.Name = modelName
	local handle = model:FindFirstChild(Constants.TOOL_HANDLE_PART) :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	local back = torso:FindFirstChild("BodyBackAttachment")
	local backCFrame = if back and back:IsA("Attachment") then back.CFrame else DEFAULT_BACK_OFFSET
	local weld = Instance.new("Weld")
	weld.Part0 = torso
	weld.Part1 = handle
	weld.C0 = backCFrame * CFrame.new(0, 0, handle.Size.Z / 2)
	weld.Parent = handle
	model.Parent = character
	return model
end

return Wearables
