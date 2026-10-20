-- Builds the "NapalmShell" projectile template under
-- ReplicatedStorage/GameAssets/Projectiles from the designer's TntBomb
-- MeshPart (kept beside it as the source art, never changed; 2026-10-20,
-- the Mortar mesh before it the same day): the Napalm Mortar's shell,
-- flown by ClientProjectileManager as one anchored part. The bomb stands
-- along its Y, so the TailAttachment sits at +Y (the fuse end) and the
-- nose is -Y: ClientProjectileManager turns whatever end is opposite the
-- tail down the flight. Run from the Studio command bar (or the MCP
-- execute_luau tool) in the gameplay place; it replaces any existing
-- copy. The template's name must match GameData/Posts/PostWeapons'
-- MORTAR.PROJECTILE.TEMPLATE.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local SOURCE_NAME = "TntBomb"
local TEMPLATE_NAME = "NapalmShell"

ChangeHistoryService:SetWaypoint("Before NapalmShell projectile")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local projectiles = gameAssets:FindFirstChild(Constants.PROJECTILE_TEMPLATES_FOLDER)
local source = projectiles:FindFirstChild(SOURCE_NAME) or workspace:FindFirstChild(SOURCE_NAME)
if not source or not source:IsA("BasePart") then
	error("build_mortar_projectile: no " .. SOURCE_NAME .. " part under GameAssets.Projectiles or Workspace")
end
-- the source art is kept with the templates, out of the world
if source.Parent ~= projectiles then
	source.Parent = projectiles
end
local existing = projectiles:FindFirstChild(TEMPLATE_NAME)
if existing then
	existing:Destroy()
end

local shell = source:Clone()
shell.Name = TEMPLATE_NAME
shell.Anchored = true
shell.CanCollide = false
shell.CanQuery = false
shell.CanTouch = false
shell.CastShadow = false
shell.Massless = true
shell.CFrame = CFrame.new()
shell.Parent = projectiles

-- the tail at the fuse end (+Y); the nose flies -Y
local tail = Instance.new("Attachment")
tail.Name = Constants.PROJECTILE_TAIL_ATTACHMENT
tail.Position = Vector3.new(0, shell.Size.Y / 2, 0)
tail.Parent = shell

ChangeHistoryService:SetWaypoint("After NapalmShell projectile")
print("Built GameAssets.Projectiles." .. TEMPLATE_NAME .. " from " .. SOURCE_NAME)
