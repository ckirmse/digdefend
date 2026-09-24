-- Gives every monster template under ReplicatedStorage/GameAssets/Monsters
-- a one-part Held body (decided 2026-09-24): the rig's parts unioned into a
-- single UnionOperation in its standing pose, named Constants.MONSTER_HELD_PART
-- and placed exactly where the rig stands. Clients draw it for every monster
-- past the animated few and inside the held distance, so a crowd of hundreds
-- is hundreds of parts, not thousands of parts and joints. It is invisible on
-- the template (like the Proxy) so it never hides the model while editing.
-- Rerun after the designer changes a monster's look; an existing Held is
-- replaced, everything else on the template is left alone. Run in the
-- gameplay place from the command bar or the MCP execute_luau tool.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- parts that are not the monster's body
local SKIPPED_PART_NAMES = {
	[Constants.MONSTER_PROXY_PART] = true,
	[Constants.MONSTER_HELD_PART] = true,
	HumanoidRootPart = true,
}

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local monsters = if gameAssets then gameAssets:FindFirstChild(Constants.MONSTER_TEMPLATES_FOLDER) else nil
assert(monsters, `no {Constants.GAME_ASSETS_FOLDER}.{Constants.MONSTER_TEMPLATES_FOLDER} folder; run build_monster_templates.luau first`)

ChangeHistoryService:SetWaypoint("Before monster held bodies")

local function bakeHeld(template: Model): BasePart?
	local root = template.PrimaryPart
	if not root then
		warn(`bake_monster_held: {template:GetFullName()} has no PrimaryPart, skipped`)
		return nil
	end
	-- the union is made from visible copies so the rig itself is never touched
	local copies: { BasePart } = {}
	for _, descendant in template:GetDescendants() do
		if not descendant:IsA("BasePart") or SKIPPED_PART_NAMES[descendant.Name] or descendant.Transparency >= 1 then
			continue
		end
		local copy = descendant:Clone()
		copy:ClearAllChildren()
		copy.Anchored = true
		copy.Parent = workspace
		table.insert(copies, copy)
	end
	if #copies == 0 then
		warn(`bake_monster_held: {template:GetFullName()} has no visible parts, skipped`)
		return nil
	end
	local first = table.remove(copies, 1) :: BasePart
	local isSuccess, union = pcall(first.UnionAsync, first, copies, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	first:Destroy()
	for _, copy in copies do
		copy:Destroy()
	end
	if not isSuccess or not union then
		warn(`bake_monster_held: union failed for {template:GetFullName()}:`, union)
		return nil
	end
	union.Name = Constants.MONSTER_HELD_PART
	union.UsePartColor = false
	union.Anchored = true
	union.CanCollide = false
	union.CanQuery = false
	union.CanTouch = false
	union.CastShadow = false
	union.Massless = true
	-- invisible on the template so it never hides the rig being edited; the
	-- client shows its own copies at the middle distance
	union.Transparency = 1
	return union
end

local built = 0
for _, template in monsters:GetChildren() do
	if not template:IsA("Model") then
		continue
	end
	local held = bakeHeld(template)
	if not held then
		continue
	end
	local existing = template:FindFirstChild(Constants.MONSTER_HELD_PART)
	if existing then
		existing:Destroy()
	end
	held.Parent = template
	built += 1
end

ChangeHistoryService:SetWaypoint("After monster held bodies")
print(`bake_monster_held: baked {built} Held bod(ies) under {monsters:GetFullName()}`)
