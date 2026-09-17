-- Builds the fortification templates under ReplicatedStorage/GameAssets/
-- Structures from the map loaded in Workspace: "WALL_<tier>", "GATE_<tier>"
-- and "POST_<tier>" for every tier (the tier count in GameData/Camp/
-- Structures), plus "WALL_RUBBLE" and "GATE_RUBBLE" for a destroyed one.
-- Tier 1 is a copy of the map's Wall1 / Gate / Post1; higher tiers are the
-- same copy with a placeholder material so an upgrade reads at a glance.
-- Every template keeps the source model's pivot, because StructureManager
-- places a clone with PivotTo at the map marker's pivot.
--
-- The designer reshapes these templates in the Explorer afterwards, so this
-- script NEVER replaces an existing template: it only creates missing ones.
-- Delete a template by hand to have it rebuilt. Run in the gameplay place
-- with the map loaded for editing (scripts/studio/map_tools.luau "load").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MAP_NAME = "DEADMANS_CANYON"
local TIER_COUNT = 3
local WALL_KEY = "WALL"
local GATE_KEY = "GATE"

-- placeholder looks for the tiers above the authored one
local LOOK_BY_TIER = {
	[2] = {
		material = Enum.Material.DiamondPlate,
		color = Color3.fromRGB(140, 145, 150),
	},
	[3] = {
		material = Enum.Material.Concrete,
		color = Color3.fromRGB(90, 92, 98),
	},
}
local RUBBLE_COLOR = Color3.fromRGB(95, 85, 75)
local RUBBLE_HEIGHT_STUDS = 2.5
local RUBBLE_CHUNK_COUNT = 9

local map = workspace:FindFirstChild(MAP_NAME)
assert(map, `load {MAP_NAME} into Workspace first (map_tools.luau, ACTION = "load")`)

ChangeHistoryService:SetWaypoint("Before structure templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
assert(gameAssets, `ReplicatedStorage is missing {Constants.GAME_ASSETS_FOLDER}`)
local structures = gameAssets:FindFirstChild(Constants.STRUCTURE_TEMPLATES_FOLDER)
if not structures then
	structures = Instance.new("Folder")
	structures.Name = Constants.STRUCTURE_TEMPLATES_FOLDER
	structures.Parent = gameAssets
end

local created = {}
local kept = {}

local function isMarkerPart(part: BasePart): boolean
	local name = part.Name
	return name:sub(-#Constants.GATE_DOOR_OPEN_SUFFIX) == Constants.GATE_DOOR_OPEN_SUFFIX
		or name:sub(-#Constants.GATE_DOOR_CLOSED_SUFFIX) == Constants.GATE_DOOR_CLOSED_SUFFIX
end

local function applyLook(model: Model, tier: number)
	local look = LOOK_BY_TIER[tier]
	if not look then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not isMarkerPart(descendant) then
			descendant.Material = look.material
			descendant.Color = look.color
		end
	end
end

local function addTemplate(name: string, build: () -> Model)
	if structures:FindFirstChild(name) then
		table.insert(kept, name)
		return
	end
	local model = build()
	model.Name = name
	-- the whole structure arrives on a client at once, doors included
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = structures
	table.insert(created, name)
end

local function addTiers(key: string, source: Model)
	for tier = 1, TIER_COUNT do
		addTemplate(
			`{key}_{tier}`,
			function()
				local model = source:Clone()
				applyLook(model, tier)
				return model
			end
		)
	end
end

-- a low heap of chunks over the source's footprint, walkable, sharing the
-- source's pivot so it lands where the structure stood
local function buildRubble(source: Model): Model
	local boxCFrame, boxSize = source:GetBoundingBox()
	local random = Random.new(23)
	local model = Instance.new("Model")
	local floorY = -boxSize.Y / 2
	for index = 1, RUBBLE_CHUNK_COUNT do
		local along = (index - 0.5) / RUBBLE_CHUNK_COUNT - 0.5
		local height = RUBBLE_HEIGHT_STUDS * random:NextNumber(0.4, 1)
		local part = Instance.new("Part")
		part.Name = "Chunk"
		part.Anchored = true
		part.Material = Enum.Material.Slate
		part.Color = RUBBLE_COLOR
		part.Size = Vector3.new(boxSize.X * random:NextNumber(0.6, 1.1), height, boxSize.Z / RUBBLE_CHUNK_COUNT * 1.3)
		part.CFrame = boxCFrame
			* CFrame.new(random:NextNumber(-0.6, 0.6), floorY + height / 2, along * boxSize.Z)
			* CFrame.Angles(0, math.rad(random:NextNumber(-20, 20)), math.rad(random:NextNumber(-8, 8)))
		part.Parent = model
	end
	model.WorldPivot = source:GetPivot()
	return model
end

local walls = map:FindFirstChild(Constants.CAMP_WALLS_FOLDER)
local posts = map:FindFirstChild(Constants.CAMP_POSTS_FOLDER)
local wall = walls and walls:FindFirstChild(Constants.WALL_NAME_PREFIX .. "1")
local post = posts and posts:FindFirstChild(Constants.POST_NAME_PREFIX .. "1")
local gate = map:FindFirstChild(Constants.CAMP_GATE_MODEL)
assert(wall and wall:IsA("Model"), "the map has no Walls.Wall1 model")
assert(post and post:IsA("Model"), "the map has no Posts.Post1 model")
assert(gate and gate:IsA("Model"), "the map has no Gate model")

addTiers(WALL_KEY, wall)
addTiers(GATE_KEY, gate)
addTiers(Constants.POST_TEMPLATE_PREFIX, post)
addTemplate(
	`{WALL_KEY}_{Constants.STRUCTURE_RUBBLE_SUFFIX}`,
	function()
		return buildRubble(wall)
	end
)
addTemplate(
	`{GATE_KEY}_{Constants.STRUCTURE_RUBBLE_SUFFIX}`,
	function()
		return buildRubble(gate)
	end
)

ChangeHistoryService:SetWaypoint("After structure templates")
return `created: {table.concat(created, ", ")} | kept: {table.concat(kept, ", ")}`
