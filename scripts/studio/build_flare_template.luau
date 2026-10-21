-- Builds the Flare's placeholder models under
-- ReplicatedStorage/GameAssets/Gadgets (2026-10-20) until the designer's
-- art lands, when each is replaced by a model of the same name:
--   Flare: the source art build_tool_templates.luau turns into the held
--     GADGET_FLARE, a short red tube with a pale cap, standing upright.
--   FLARE: the thrown and lit flare every client clones (the same tube;
--     ClientFlareManager adds the fire and light).
-- Run from the Studio command bar (or the MCP execute_luau tool) in the
-- gameplay place; it replaces any existing copy of each.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local SOURCE_NAME = "Flare"
local TUBE_COLOR = Color3.fromRGB(200, 40, 40)
local CAP_COLOR = Color3.fromRGB(240, 230, 200)

ChangeHistoryService:SetWaypoint("Before Flare templates")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local gadgets = gameAssets:FindFirstChild(Constants.GADGET_TEMPLATES_FOLDER)
for _, name in { SOURCE_NAME, Constants.FLARE_TEMPLATE } do
	local existing = gadgets:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local function makePart(name, size, color, material, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function buildFlare(name: string): Model
	local flare = Instance.new("Model")
	flare.Name = name
	local tube = makePart("Tube", Vector3.new(0.35, 1.2, 0.35), TUBE_COLOR, Enum.Material.SmoothPlastic, CFrame.new(0, 0.6, 0), flare)
	makePart("Cap", Vector3.new(0.38, 0.2, 0.38), CAP_COLOR, Enum.Material.Neon, CFrame.new(0, 1.3, 0), flare)
	flare.PrimaryPart = tube
	flare.Parent = gadgets
	return flare
end

buildFlare(SOURCE_NAME)
buildFlare(Constants.FLARE_TEMPLATE)

ChangeHistoryService:SetWaypoint("After Flare templates")
print("build_flare_template: built GameAssets." .. Constants.GADGET_TEMPLATES_FOLDER .. "." .. SOURCE_NAME .. " and " .. Constants.FLARE_TEMPLATE)
