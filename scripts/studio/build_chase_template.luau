-- Builds the "CHASE" template under ReplicatedStorage/GameAssets/Monsters
-- (M68, 2026-10-26) from the designer's rig: a Workspace model named
-- "Rig" (or ServerStorage.Sources.ChaseRig), an R15 character wearing the
-- company Hard Hat with the red Eyes union welded to its Head and the
-- Smoke emitter on its root, its face texture cleared. The template is a
-- copy with no Humanoid or scripts (its Sounds stay; ClientMonsterManager animates
-- through an AnimationController's Animator), its HumanoidRootPart as the
-- PrimaryPart, every part uncollidable and massless, an invisible Proxy
-- the size of the bounding box (the hit box and the far-away block, its
-- bottom the feet), and the feet pivoted to y = 0 facing -Z (the client
-- turns a floater's -Z to the camera). Run from the Studio command bar (or
-- the MCP execute_luau tool) in the gameplay place; it replaces any
-- existing copy. The placeholder plate it replaced (2026-10-26, earlier the
-- same day) was a flat decal.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local TEMPLATE_NAME = "CHASE"

local function findSource(): Model
	local fromWorkspace = workspace:FindFirstChild("Rig")
	if fromWorkspace and fromWorkspace:IsA("Model") then
		return fromWorkspace
	end
	local sources = ServerStorage:FindFirstChild("Sources")
	local fromSources = sources and sources:FindFirstChild("ChaseRig")
	assert(fromSources and fromSources:IsA("Model"), "build_chase_template: no Workspace.Rig or ServerStorage.Sources.ChaseRig")
	return fromSources
end

ChangeHistoryService:SetWaypoint("Before CHASE template")

local source = findSource()
local monsters = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER):FindFirstChild(Constants.MONSTER_TEMPLATES_FOLDER)
local existing = monsters:FindFirstChild(TEMPLATE_NAME)
if existing then
	existing:Destroy()
end

local template = source:Clone()
template.Name = TEMPLATE_NAME
for _, descendant in template:GetDescendants() do
	-- Sounds stay: the designer's MinerTheme loop on the root is the Chase's
	if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Humanoid") then
		descendant:Destroy()
	end
end
local root = template:FindFirstChild("HumanoidRootPart")
assert(root and root:IsA("BasePart"), "build_chase_template: the rig has no HumanoidRootPart")
template.PrimaryPart = root
for _, descendant in template:GetDescendants() do
	if descendant:IsA("BasePart") then
		descendant.Anchored = descendant == root
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
		descendant.CastShadow = false
		descendant.Massless = true
	end
end

-- a rig jointed with AnimationConstraints animates only under physics,
-- which the renderer's anchored, massless rigs never run (2026-10-26: the
-- Animator played at full weight and no limb moved); every constraint
-- becomes the Motor6D the Cave Spider and the wave rigs use, which the
-- Animator drives directly
for _, descendant in template:GetDescendants() do
	if descendant:IsA("AnimationConstraint") then
		local attachment0 = descendant.Attachment0
		local attachment1 = descendant.Attachment1
		local part0 = attachment0 and attachment0.Parent
		local part1 = attachment1 and attachment1.Parent
		if attachment0 and attachment1 and part0 and part1 and part0:IsA("BasePart") and part1:IsA("BasePart") then
			local motor = Instance.new("Motor6D")
			motor.Name = descendant.Name
			motor.Part0 = part0
			motor.Part1 = part1
			motor.C0 = attachment0.CFrame
			motor.C1 = attachment1.CFrame
			motor.Parent = part1
		end
		descendant:Destroy()
	end
end

local controller = template:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController")
controller.Parent = template
if not controller:FindFirstChildOfClass("Animator") then
	Instance.new("Animator").Parent = controller
end

-- the feet are the parts' lowest point (GetBoundingBox ran lower than the
-- parts on this rig, and PivotTo did not move it, 2026-10-26): every part is
-- shifted so the feet sit at y = 0 under the root, and the Proxy stands on
-- the same floor around the bounding box
local function partsBottom(): number
	local minY = math.huge
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("BasePart") then
			minY = math.min(minY, descendant.Position.Y - descendant.Size.Y / 2)
		end
	end
	return minY
end
local shift = Vector3.new(-root.Position.X, -partsBottom(), -root.Position.Z)
for _, descendant in template:GetDescendants() do
	if descendant:IsA("BasePart") then
		descendant.CFrame = descendant.CFrame + shift
	end
end
template.WorldPivot = root.CFrame

local boxCFrame, boxSize = template:GetBoundingBox()
local proxy = Instance.new("Part")
proxy.Name = Constants.MONSTER_PROXY_PART
proxy.Size = boxSize
proxy.CFrame = CFrame.new(boxCFrame.Position.X, partsBottom() + boxSize.Y / 2, boxCFrame.Position.Z) * (root.CFrame - root.CFrame.Position)
proxy.Transparency = 1
proxy.Anchored = true
proxy.CanCollide = false
proxy.CanQuery = false
proxy.CanTouch = false
proxy.CastShadow = false
proxy.Massless = true
proxy.Parent = template
template.Parent = monsters

ChangeHistoryService:SetWaypoint("After CHASE template")
print("build_chase_template: built GameAssets." .. Constants.MONSTER_TEMPLATES_FOLDER .. "." .. TEMPLATE_NAME .. " from " .. source:GetFullName())
