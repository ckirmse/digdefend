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
function Wearables.isHatAccessory(accessory: Accessory): boolean
	local handle = accessory:FindFirstChild(Constants.TOOL_HANDLE_PART)
	return accessory.AccessoryType == Enum.AccessoryType.Hat
		or (handle ~= nil and handle:FindFirstChild("HatAttachment") ~= nil)
end

-- the player's own hat comes off when a character has one equipped
function Wearables.removeHatAccessories(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and Wearables.isHatAccessory(child) then
			child:Destroy()
		end
	end
end

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
	local handleAttachment = handle:FindFirstChildOfClass("Attachment")
	local rigAttachment = if handleAttachment then character:FindFirstChild(handleAttachment.Name, true) else nil
	local anchor: BasePart? = nil
	if handleAttachment and rigAttachment and rigAttachment:IsA("Attachment") and rigAttachment.Parent and rigAttachment.Parent:IsA("BasePart") then
		anchor = rigAttachment.Parent
		handle.CFrame = rigAttachment.WorldCFrame * handleAttachment.CFrame:Inverse()
	else
		local head = character:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return nil
		end
		anchor = head
		handle.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0) * accessory.AttachmentPoint:Inverse()
	end
	local weld = Instance.new("Weld")
	weld.Part0 = anchor
	weld.Part1 = handle
	weld.C0 = (anchor :: BasePart).CFrame:Inverse() * handle.CFrame
	weld.Parent = handle
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
