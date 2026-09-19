-- Builds the placeholder POST_WORKBENCH template under GameAssets.Structures
-- (GDD "Claiming a Post"): the small bench that appears beside a claimed
-- post, where its owner buys upgrades. A Model with an invisible anchored
-- Prompt part on top, which PostManager gives the Upgrade ProximityPrompt.
-- It also adds a WorkbenchSpawn marker part to every POST_<tier> template
-- that lacks one, on the opposite side of the stairs from the sign, which
-- is where PostManager stands the bench. The designer moves the markers
-- (and reshapes the bench) in the Explorer afterwards, so this script never
-- replaces an existing bench or marker: delete one by hand to have it
-- rebuilt. Run in the gameplay place.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local TOP_SIZE = Vector3.new(4, 0.4, 2)
local TOP_HEIGHT_STUDS = 2.6
local LEG_SIZE = Vector3.new(0.4, TOP_HEIGHT_STUDS, 0.4)
local WOOD_COLOR = Color3.fromRGB(120, 85, 50)
local MARKER_SIZE = Vector3.new(4, 0.2, 2)
-- in a post template's pivot space its X is up, the sign sits at Y +10.3
-- and Z -22.4, and the stairs (Y 0) run down to the camp floor, which on
-- Deadmans Canyon is 7.5 below the pivot; the bench mirrors the sign
-- across the stairs, on the floor
local MARKER_OFFSET = Vector3.new(-7.5, -10.3, -22.4)
-- marker up = pivot X, marker faces the stairs (pivot +Y)
local MARKER_ROTATION = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0))

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local structures = gameAssets and gameAssets:FindFirstChild(Constants.STRUCTURE_TEMPLATES_FOLDER)
assert(structures, "GameAssets.Structures is missing; run build_structure_templates.luau first")

ChangeHistoryService:SetWaypoint("Before post workbench")

local report = {}

local function addPart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cframe
	part.Parent = parent
	return part
end

if structures:FindFirstChild(Constants.POST_WORKBENCH_TEMPLATE) then
	table.insert(report, `{Constants.POST_WORKBENCH_TEMPLATE} already exists; left alone`)
else
	local bench = Instance.new("Model")
	bench.Name = Constants.POST_WORKBENCH_TEMPLATE
	local top = addPart(bench, "Top", TOP_SIZE, CFrame.new(0, TOP_HEIGHT_STUDS + TOP_SIZE.Y / 2, 0), WOOD_COLOR, Enum.Material.WoodPlanks)
	for _, corner in { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) } do
		local x = corner.X * (TOP_SIZE.X / 2 - LEG_SIZE.X)
		local z = corner.Y * (TOP_SIZE.Z / 2 - LEG_SIZE.Z)
		addPart(bench, "Leg", LEG_SIZE, CFrame.new(x, TOP_HEIGHT_STUDS / 2, z), WOOD_COLOR, Enum.Material.Wood)
	end
	local surfaceY = TOP_HEIGHT_STUDS + TOP_SIZE.Y
	-- a toolbox and an ammo tin so it reads as a gunner's bench
	addPart(bench, "Toolbox", Vector3.new(1.4, 0.7, 0.8), CFrame.new(-1, surfaceY + 0.35, 0), Color3.fromRGB(180, 40, 40), Enum.Material.Metal)
	addPart(bench, "AmmoTin", Vector3.new(0.9, 0.5, 0.6), CFrame.new(1, surfaceY + 0.25, 0.2), Color3.fromRGB(80, 100, 60), Enum.Material.Metal)
	local prompt = addPart(bench, Constants.WORKBENCH_PROMPT_PART, Vector3.new(1, 1, 1), CFrame.new(0, surfaceY + 0.5, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	prompt.Transparency = 1
	prompt.CanCollide = false
	prompt.CanQuery = false
	prompt.CanTouch = false
	-- no PrimaryPart: with one set, PivotTo would use that part's pivot and
	-- bury the legs. The pivot is the floor under the bench's centre, which
	-- is where PostManager stands it on the WorkbenchSpawn marker
	bench.WorldPivot = CFrame.new(0, 0, 0)
	bench.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	bench.Parent = structures
	table.insert(report, `built {bench:GetFullName()}`)
end

for _, template in structures:GetChildren() do
	if not template:IsA("Model") or template.Name:sub(1, #Constants.POST_TEMPLATE_PREFIX + 1) ~= Constants.POST_TEMPLATE_PREFIX .. "_" then
		continue
	end
	if template.Name == Constants.POST_WORKBENCH_TEMPLATE then
		continue
	end
	if template:FindFirstChild(Constants.POST_WORKBENCH_SPAWN_PART) then
		table.insert(report, `{template.Name} already has a {Constants.POST_WORKBENCH_SPAWN_PART}; left alone`)
		continue
	end
	local marker = addPart(template, Constants.POST_WORKBENCH_SPAWN_PART, MARKER_SIZE, template:GetPivot() * CFrame.new(MARKER_OFFSET) * MARKER_ROTATION, Color3.fromRGB(60, 200, 60), Enum.Material.SmoothPlastic)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	table.insert(report, `added {marker:GetFullName()}`)
end

ChangeHistoryService:SetWaypoint("After post workbench")
return table.concat(report, "\n")
