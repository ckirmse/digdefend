-- Converts designer rigs into monster puppets under
-- ReplicatedStorage/GameAssets/Monsters (M29). Every monster is drawn only on
-- clients, hundreds at once, so the template is stripped to what a client
-- moves and animates: no Humanoid (its state machine and physics are the most
-- expensive part of a character), no scripts, no collision or queries, the
-- HumanoidRootPart anchored as the one part code moves (every other part
-- hangs off it by the rig's own Motor6Ds), and an AnimationController the
-- client plays the clips named in GameData/Monsters/Roster through. A
-- one-part Proxy the size and colour of the rig is added for far-away
-- drawing.
-- The source rig is read and never changed. Run in the gameplay place from
-- the command bar or the MCP execute_luau tool; it replaces any existing copy
-- of each listed template and leaves other templates alone. Run
-- bake_monster_held.luau afterwards to give the new template its Held body.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

-- source rig in Workspace -> template name (the monster kind key)
local SOURCES = {
	{
		sourceName = "Rig",
		templateName = "ZOMBIE_1",
	},
}

-- instances a Humanoid-free client puppet has no use for
local STRIPPED_CLASSES = {
	"Humanoid",
	"Script",
	"LocalScript",
	"ModuleScript",
	"BodyColors",
	"Shirt",
	"Pants",
	"ShirtGraphic",
	"Sound",
}

ChangeHistoryService:SetWaypoint("Before monster templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = Constants.GAME_ASSETS_FOLDER
	gameAssets.Parent = ReplicatedStorage
end
local monsters = gameAssets:FindFirstChild(Constants.MONSTER_TEMPLATES_FOLDER)
if not monsters then
	monsters = Instance.new("Folder")
	monsters.Name = Constants.MONSTER_TEMPLATES_FOLDER
	monsters.Parent = gameAssets
end

local function isStripped(instance: Instance): boolean
	for _, className in STRIPPED_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local function buildTemplate(source: Model, templateName: string): Model
	local rig = source:Clone()
	rig.Name = templateName

	-- BodyColors only paints through a Humanoid; the parts already carry the
	-- painted colours, which survive once it is gone
	for _, descendant in rig:GetDescendants() do
		if isStripped(descendant) then
			descendant:Destroy()
		end
	end

	local root = rig:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		warn(`build_monster_templates: {source:GetFullName()} has no HumanoidRootPart, skipped`)
		rig:Destroy()
		return nil
	end
	rig.PrimaryPart = root

	for _, descendant in rig:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		descendant.Anchored = descendant == root
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
		-- hundreds of shadow casters is a phone's worst frame; none of them cast
		descendant.CastShadow = false
		descendant.Massless = true
	end

	local animationController = Instance.new("AnimationController")
	animationController.Parent = rig
	local animator = Instance.new("Animator")
	animator.Parent = animationController

	-- measured before the Proxy exists so it does not enlarge the box
	local boxCFrame, boxSize = rig:GetBoundingBox()
	local bottomY = boxCFrame.Position.Y - boxSize.Y / 2

	local torso = rig:FindFirstChild("Torso") or rig:FindFirstChild("UpperTorso")
	local proxy = Instance.new("Part")
	proxy.Name = Constants.MONSTER_PROXY_PART
	proxy.Size = boxSize
	proxy.CFrame = CFrame.new(boxCFrame.Position) * root.CFrame.Rotation
	proxy.Color = if torso and torso:IsA("BasePart") then torso.Color else root.Color
	proxy.Material = Enum.Material.SmoothPlastic
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CanTouch = false
	proxy.CastShadow = false
	-- invisible on the template so it never hides the model while editing;
	-- the client shows its own copies far away
	proxy.Transparency = 1
	proxy.Parent = rig

	-- the source is usually standing in Workspace; the template sits at the
	-- origin so a clone's pivot is predictable
	rig:PivotTo(CFrame.new(0, root.Position.Y - bottomY, 0))
	return rig
end

local built = 0
for _, entry in SOURCES do
	local source = workspace:FindFirstChild(entry.sourceName)
	if not source or not source:IsA("Model") then
		warn(`build_monster_templates: no Model named {entry.sourceName} in Workspace, skipped`)
		continue
	end
	local template = buildTemplate(source, entry.templateName)
	if not template then
		continue
	end
	local existing = monsters:FindFirstChild(entry.templateName)
	if existing then
		existing:Destroy()
	end
	template.Parent = monsters
	built += 1
end

ChangeHistoryService:SetWaypoint("After monster templates")
print(`build_monster_templates: built {built} monster template(s) under {monsters:GetFullName()}`)
