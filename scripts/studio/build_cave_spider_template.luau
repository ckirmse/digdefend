-- Turns the designer's CaveSpider model in Workspace into the CAVE_SPIDER
-- monster template under ReplicatedStorage/GameAssets/Monsters (M62,
-- 2026-10-08), the way build_monster_templates does for a rig. The source
-- must be rigged first (rig_cave_spider.luau: a HumanoidRootPart at the
-- body's centre facing the head, and Motor6Ds down the legs), so the
-- clone keeps the joints the Animation Editor and the client's animator
-- drive; the model is scaled for the mine, an invisible Proxy the size of
-- the body is its hit box and far drawing, and an AnimationController is
-- added. The source model is never changed. Run in the gameplay place
-- through the MCP execute_luau tool (the Studio command thread cannot
-- require, so Constants is loaded from its source); the Held body is baked
-- at the end of this file.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local function load(module)
	local chunk = loadstring(module.Source)
	local environment = setmetatable({ script = module }, { __index = getfenv(0) })
	setfenv(chunk, environment)
	return chunk()
end
local Constants = load(ReplicatedStorage.Shared.Constants)

local SOURCE_NAME = "CaveSpider"
local TEMPLATE_NAME = "CAVE_SPIDER"
-- the model is 6.2 studs long as authored; 0.9 (designer, 2026-10-08: a
-- quarter off the 1.2 tried earlier, after a detour to 0.3) makes it 5.6
-- studs long, longer than a 4-stud cell, so its legs reach the walls
local SCALE = 0.9
-- the head is toward -X in the authored model
local FORWARD = Vector3.new(-1, 0, 0)

-- the designer's model lives in ServerStorage.Sources (moved out of
-- Workspace on 2026-10-08 so it never loads at run time); a copy left in
-- Workspace while it is being animated is taken first
local ServerStorage = game:GetService("ServerStorage")
local sourcesFolder = ServerStorage:FindFirstChild("Sources")
local source = workspace:FindFirstChild(SOURCE_NAME, true) or (if sourcesFolder then sourcesFolder:FindFirstChild(SOURCE_NAME) else nil)
assert(source and source:IsA("Model"), "no Model named " .. SOURCE_NAME .. " in Workspace or ServerStorage.Sources")
local gameAssets = ReplicatedStorage[Constants.GAME_ASSETS_FOLDER]
local monsters = gameAssets[Constants.MONSTER_TEMPLATES_FOLDER]

ChangeHistoryService:SetWaypoint("Before the Cave Spider template")

local model = source:Clone()
model.Name = TEMPLATE_NAME
for _, descendant in model:GetDescendants() do
	if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Humanoid") or descendant:IsA("Sound") then
		descendant:Destroy()
	end
end

local root = model:FindFirstChild("HumanoidRootPart")
assert(root and root:IsA("BasePart"), SOURCE_NAME .. " has no HumanoidRootPart; run rig_cave_spider.luau first")
local hasMotor = false
for _, descendant in model:GetDescendants() do
	if descendant:IsA("Motor6D") then
		hasMotor = true
		break
	end
end
assert(hasMotor, SOURCE_NAME .. " has no Motor6Ds; run rig_cave_spider.luau first")
model.PrimaryPart = root

for _, descendant in model:GetDescendants() do
	if descendant:IsA("BasePart") then
		descendant.Anchored = descendant == root
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
		descendant.CastShadow = false
		descendant.Massless = true
	end
end

model:ScaleTo(model:GetScale() * SCALE)

-- the rigged source carries its own controller; an older one gets one here
local animationController = model:FindFirstChildOfClass("AnimationController")
if not animationController then
	animationController = Instance.new("AnimationController")
	animationController.Parent = model
end
if not animationController:FindFirstChildOfClass("Animator") then
	local animator = Instance.new("Animator")
	animator.Parent = animationController
end

-- measured after the scale and before the Proxy exists
local boxCFrame, boxSize = model:GetBoundingBox()
local bottomY = boxCFrame.Position.Y - boxSize.Y / 2
local proxy = Instance.new("Part")
proxy.Name = Constants.MONSTER_PROXY_PART
-- the box in the root's frame: its length runs along the root's look
proxy.Size = Vector3.new(boxSize.Z, boxSize.Y, boxSize.X)
proxy.CFrame = CFrame.new(boxCFrame.Position) * root.CFrame.Rotation
local body = model:FindFirstChild("Abdomen")
proxy.Color = if body and body:IsA("BasePart") then body.Color else Color3.new(0.2, 0.2, 0.2)
proxy.Material = Enum.Material.SmoothPlastic
proxy.Anchored = true
proxy.CanCollide = false
proxy.CanQuery = false
proxy.CanTouch = false
proxy.CastShadow = false
proxy.Transparency = 1
proxy.Parent = model

-- the template sits at the origin with its feet on the ground plane
model:PivotTo(CFrame.lookAlong(Vector3.new(0, root.Position.Y - bottomY, 0), FORWARD))

local existing = monsters:FindFirstChild(TEMPLATE_NAME)
if existing then
	existing:Destroy()
end
model.Parent = monsters

-- the Held body, as bake_monster_held.luau makes it
local skipped = { [Constants.MONSTER_PROXY_PART] = true, [Constants.MONSTER_HELD_PART] = true, HumanoidRootPart = true }
local copies = {}
for _, descendant in model:GetDescendants() do
	if descendant:IsA("BasePart") and not skipped[descendant.Name] and descendant.Transparency < 1 then
		local copy = descendant:Clone()
		copy:ClearAllChildren()
		copy.Anchored = true
		copy.Parent = workspace
		table.insert(copies, copy)
	end
end
local first = table.remove(copies, 1)
local isSuccess, union = pcall(first.UnionAsync, first, copies, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
first:Destroy()
for _, copy in copies do
	copy:Destroy()
end
if isSuccess and union then
	union.Name = Constants.MONSTER_HELD_PART
	union.UsePartColor = false
	union.Anchored = true
	union.CanCollide = false
	union.CanQuery = false
	union.CanTouch = false
	union.CastShadow = false
	union.Massless = true
	union.Transparency = 1
	union.Parent = model
else
	warn("build_cave_spider_template: the Held union failed:", union)
end

ChangeHistoryService:SetWaypoint("After the Cave Spider template")
print(string.format("build_cave_spider_template: %s rebuilt, proxy %s, root %.2f studs above the feet, held %s", TEMPLATE_NAME, tostring(proxy.Size), root.Position.Y - bottomY, tostring(isSuccess and union ~= nil)))
