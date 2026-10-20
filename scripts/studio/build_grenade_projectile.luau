-- Builds the "Grenade" projectile template under
-- ReplicatedStorage/GameAssets/Projectiles from the designer's
-- GrenadeLauncherAmmo model (kept beside it as the source art, never
-- changed; 2026-10-19): the Assault Rifle's grenade, flown by
-- ClientProjectileManager as one anchored part (the shell) with the head
-- welded on, its nose along -X like the Rocket's and a TailAttachment at
-- +X for the trail. The art is a few tenths of a stud long, so the copy
-- is scaled up to a hand grenade's size. Run from the Studio command bar
-- (or the MCP execute_luau tool) in the gameplay place; it replaces any
-- existing copy. The template's name must match
-- GameData/Weapons/Handheld's SECONDARY.TEMPLATE.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local SOURCE_NAME = "GrenadeLauncherAmmo"
local TEMPLATE_NAME = "Grenade"
-- how long the flown grenade is, in studs
local LENGTH_STUDS = 0.9

ChangeHistoryService:SetWaypoint("Before Grenade projectile")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local projectiles = gameAssets:FindFirstChild(Constants.PROJECTILE_TEMPLATES_FOLDER)
local source = projectiles:FindFirstChild(SOURCE_NAME) or workspace:FindFirstChild(SOURCE_NAME)
if not source or not source:IsA("Model") then
	error("build_grenade_projectile: no " .. SOURCE_NAME .. " model under GameAssets.Projectiles or Workspace")
end
-- the source art is kept with the templates, out of the world
if source.Parent ~= projectiles then
	source.Parent = projectiles
end
local existing = projectiles:FindFirstChild(TEMPLATE_NAME)
if existing then
	existing:Destroy()
end

local copy = source:Clone()
local _, bounds = copy:GetBoundingBox()
copy:ScaleTo(copy:GetScale() * LENGTH_STUDS / math.max(bounds.X, bounds.Y, bounds.Z))
local shell = copy:FindFirstChildWhichIsA("BasePart")
if not shell then
	error("build_grenade_projectile: " .. SOURCE_NAME .. " has no part")
end
for _, descendant in copy:GetDescendants() do
	if descendant:IsA("BasePart") then
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
		descendant.CastShadow = false
		descendant.Massless = true
		if descendant ~= shell then
			-- the head rides on the shell: unanchored and welded, so the
			-- shell's CFrame each frame carries it
			descendant.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = shell
			weld.Part1 = descendant
			weld.Parent = shell
		end
	elseif descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
		descendant:Destroy()
	end
end
shell.Anchored = true
shell.Name = TEMPLATE_NAME
shell.Parent = projectiles
copy:Destroy()

-- the tail at the back of the shell (+X; the nose flies -X like the Rocket)
local tail = Instance.new("Attachment")
tail.Name = Constants.PROJECTILE_TAIL_ATTACHMENT
tail.Position = Vector3.new(shell.Size.X / 2, 0, 0)
tail.Parent = shell

ChangeHistoryService:SetWaypoint("After Grenade projectile")
print("Built GameAssets.Projectiles." .. TEMPLATE_NAME .. " from " .. SOURCE_NAME)
