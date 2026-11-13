-- Builds the worn jet packs under ReplicatedStorage/GameAssets/Wearables:
-- JET_PACK_<level>, one Model per level from the artist's meshes (the same
-- ones the Mining Supplies stand shows, GameAssets/StoreDisplays; in place
-- since 2026-11-13, a grey placeholder before). ClientJetPackManager welds
-- each model's invisible Handle plate to a character's back and switches
-- on every effect and light under the pack's attachments while it burns.
-- Run in either place from the command bar
-- or the MCP execute_luau tool: the meshes are made from their asset ids, so
-- the lobby, which has no StoreDisplays, gets identical copies.
--
-- A level that already has a template is left alone: the artist authors
-- the exhaust by hand (two attachments on the mesh holding particles, smoke,
-- and a light, 2026-11-13) and tunes the seat of the pack in the Explorer,
-- and neither can be rebuilt from here. This script only makes the first
-- copy of a level that has none; delete a template by hand to remake it.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- shared by every level's SurfaceAppearance
local METALNESS_MAP = "rbxassetid://76212287464671"
local ROUGHNESS_MAP = "rbxassetid://130420375588944"
local MESH_COLOR = Color3.fromRGB(163, 162, 165)

local SPECS = {
	{
		level = 1,
		partName = "JetPack01",
		meshId = "rbxassetid://104145431724102",
		colorMap = "rbxassetid://74450175209251",
		size = Vector3.new(1.004, 1.074, 0.544),
	},
	{
		level = 2,
		partName = "JetPack02",
		meshId = "rbxassetid://88640013611063",
		colorMap = "rbxassetid://126361880575063",
		size = Vector3.new(1.120, 1.538, 0.607),
	},
	{
		level = 3,
		partName = "JetPack03",
		meshId = "rbxassetid://84210018023361",
		colorMap = "rbxassetid://86150520782744",
		size = Vector3.new(1.086, 1.757, 0.588),
	},
	{
		level = 4,
		partName = "JetPack04",
		meshId = "rbxassetid://121582097009516",
		colorMap = "rbxassetid://97154600255175",
		size = Vector3.new(1.308, 1.932, 0.682),
	},
	{
		level = 5,
		partName = "JetPack05",
		meshId = "rbxassetid://139473168159412",
		colorMap = "rbxassetid://111881172054413",
		size = Vector3.new(1.586, 2.227, 0.694),
	},
}

-- the seat of the mesh against the Handle plate, from where the artist
-- stood the level 1 pack on the placeholder (2026-11-13): a hair left of
-- centre, its front face this far behind the plate's centre, its top this
-- far above it. A taller pack grows mostly downward so it stays clear of
-- the head.
local HANDLE_SIZE = Vector3.new(1.3, 1.4, 0.2)
local MESH_OFFSET_X = -0.013
local MESH_FRONT_Z = 0.04
local BASE_TOP_Y = 0.63
local BASE_HEIGHT = 1.074
local EXTRA_HEIGHT_UP_SHARE = 0.35
local MOUNT_HEIGHT = 0.2
local MOUNT_TILT_DEGREES = 15

ChangeHistoryService:SetWaypoint("Before wearable templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local wearables = gameAssets:FindFirstChild(Constants.WEARABLE_TEMPLATES_FOLDER)
if not wearables then
	wearables = Instance.new("Folder")
	wearables.Name = Constants.WEARABLE_TEMPLATES_FOLDER
	wearables.Parent = gameAssets
end
-- the one-model placeholder of before 2026-11-13
local legacy = wearables:FindFirstChild(Constants.JET_PACK_TEMPLATE)
if legacy then
	legacy:Destroy()
end

local function prepare(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function weldTo(handle, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = handle
end

local function makeMount(name, x, z, tiltDegrees, handle)
	local mount = Instance.new("Attachment")
	mount.Name = name
	mount.CFrame = CFrame.new(x, MOUNT_HEIGHT, z) * CFrame.Angles(0, 0, math.rad(tiltDegrees))
	mount.Parent = handle
end

local builtCount = 0
for _, spec in SPECS do
	local name = `{Constants.JET_PACK_TEMPLATE}_{spec.level}`
	if wearables:FindFirstChild(name) then
		print("build_wearable_templates: " .. name .. " exists; left as the artist has it")
		continue
	end

	local jetPack = Instance.new("Model")
	jetPack.Name = name

	-- the Handle is an invisible thin back plate; its front (-Z) sits
	-- against the torso and the mesh is welded to it
	local plate = Instance.new("Part")
	plate.Name = Constants.TOOL_HANDLE_PART
	plate.Size = HANDLE_SIZE
	plate.Transparency = 1
	plate.CFrame = CFrame.new(0, 0, 0)
	prepare(plate)
	plate.Parent = jetPack

	local meshY = BASE_TOP_Y + EXTRA_HEIGHT_UP_SHARE * (spec.size.Y - BASE_HEIGHT) - spec.size.Y / 2
	local meshZ = MESH_FRONT_Z + spec.size.Z / 2
	local mesh = InsertService:CreateMeshPartAsync(spec.meshId, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	mesh.Name = spec.partName
	mesh.Size = spec.size
	mesh.Color = MESH_COLOR
	mesh.CFrame = CFrame.new(MESH_OFFSET_X, meshY, meshZ)
	prepare(mesh)
	local surface = Instance.new("SurfaceAppearance")
	surface.ColorMap = spec.colorMap
	surface.MetalnessMap = METALNESS_MAP
	surface.RoughnessMap = ROUGHNESS_MAP
	surface.Parent = mesh
	mesh.Parent = jetPack

	weldTo(plate, mesh)

	-- where the stowed tools hang (designer, 2026-10-12): one attachment on
	-- each side of the pack, the tool's head up, handle down the side
	makeMount(Constants.JET_PACK_PICK_AXE_ATTACHMENT, MESH_OFFSET_X - spec.size.X / 2, meshZ, MOUNT_TILT_DEGREES, plate)
	makeMount(Constants.JET_PACK_HAMMER_ATTACHMENT, MESH_OFFSET_X + spec.size.X / 2, meshZ, -MOUNT_TILT_DEGREES, plate)

	jetPack.PrimaryPart = plate
	jetPack.Parent = wearables
	builtCount += 1
end

ChangeHistoryService:SetWaypoint("After wearable templates")
print("build_wearable_templates: built " .. builtCount .. " jet pack template(s) under " .. wearables:GetFullName())
