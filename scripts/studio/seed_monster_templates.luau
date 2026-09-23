-- Gives every monster kind its own template under
-- ReplicatedStorage/GameAssets/Monsters (M29, decided 2026-09-23): a kind
-- without one gets a copy of SOURCE_NAME, named by its Enums.MonsterKind
-- key ("BRUTE_2") and scaled to its STARTING_SCALE_BY_KEY entry (1 when
-- absent). Existing templates are never touched, so the designer's edits
-- to a monster's look and size are safe; rerun after adding a kind to the
-- enum to give it a starting model. Resize a template in Studio with
-- Model:ScaleTo or the Scale tool: its Proxy part scales with it and is
-- the monster's hit box, and the Proxy's bottom is where its feet stand.
-- A source without a Humanoid-free rig is made by build_monster_templates.
-- Run in the gameplay place from the command bar or the MCP execute_luau tool.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)

-- copied from this template; the placeholder R6 rig until real art exists
local SOURCE_NAME = "ZOMBIE_1"
-- the sizes the monsters had as a Roster SCALE before each got its own model
local STARTING_SCALE_BY_KEY = {
	ZOMBIE_2 = 1.1,
	ZOMBIE_3 = 1.2,
	RUNNER_1 = 0.9,
	RUNNER_2 = 0.95,
	BRUTE_1 = 1.6,
	BRUTE_2 = 1.8,
	BRUTE_3 = 2,
	LAUNCHER_1 = 2,
	BOMBER_1 = 0.9,
	BOMBER_3 = 1.1,
	FLYER_2 = 1.2,
	FLYER_3 = 1.4,
	TITAN_1 = 3.5,
	TITAN_2 = 4,
}

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local monsters = if gameAssets then gameAssets:FindFirstChild(Constants.MONSTER_TEMPLATES_FOLDER) else nil
assert(monsters, "no GameAssets." .. Constants.MONSTER_TEMPLATES_FOLDER .. " folder; run build_monster_templates.luau first")
local source = monsters:FindFirstChild(SOURCE_NAME)
assert(source and source:IsA("Model"), "no " .. SOURCE_NAME .. " template to copy; run build_monster_templates.luau first")

ChangeHistoryService:SetWaypoint("Before seeding monster templates")

local kinds = Enums.getAllValues(Enums.MonsterKind)
table.sort(kinds)
local created = {}
for _, kind in kinds do
	local key = Enums.getName(Enums.MonsterKind, kind) :: string
	if monsters:FindFirstChild(key) then
		continue
	end
	local copy = source:Clone()
	copy.Name = key
	local scale = STARTING_SCALE_BY_KEY[key] or 1
	if scale ~= 1 then
		copy:ScaleTo(copy:GetScale() * scale)
	end
	-- stand the copy on the ground plane at the origin, as the source does
	local proxy = copy:FindFirstChild(Constants.MONSTER_PROXY_PART)
	if proxy and proxy:IsA("BasePart") then
		copy:PivotTo(copy:GetPivot() + Vector3.new(0, -(proxy.Position.Y - proxy.Size.Y / 2), 0))
	end
	copy.Parent = monsters
	table.insert(created, key)
end

ChangeHistoryService:SetWaypoint("After seeding monster templates")
print(`seed_monster_templates: created {#created} template(s): {table.concat(created, ", ")}`)
