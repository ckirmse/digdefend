-- Builds the Remote Charge's planted model, "REMOTE_CHARGE", under
-- ReplicatedStorage/GameAssets/Gadgets from the designer's ProximityMine
-- model (2026-10-20; kept beside it as the source art, never changed,
-- moved there from the Workspace on the first run along with the
-- RemoteDetonator art, which build_tool_templates.luau turns into the held
-- detonator). The art is a disc standing on edge, its thickness along X,
-- so the copy is laid flat, face up, for ClientRemoteChargeManager to
-- stand on a shadow's ground point; its "Light" part and the light under
-- it are what breathes (Constants.REMOTE_CHARGE_LIGHT_PART). Run from the
-- Studio command bar (or the MCP execute_luau tool) in the gameplay
-- place; it replaces any existing copy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MINE_SOURCE_NAME = "ProximityMine"
local DETONATOR_SOURCE_NAME = "RemoteDetonator"

ChangeHistoryService:SetWaypoint("Before Remote Charge template")

local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
local gadgets = gameAssets:FindFirstChild(Constants.GADGET_TEMPLATES_FOLDER)
-- the source art lives with the templates, out of the world
for _, sourceName in { MINE_SOURCE_NAME, DETONATOR_SOURCE_NAME } do
	local source = gadgets:FindFirstChild(sourceName) or workspace:FindFirstChild(sourceName, true)
	if not source or not source:IsA("Model") then
		error("build_remote_charge_template: no " .. sourceName .. " model under GameAssets.Gadgets or the Workspace")
	end
	if source.Parent ~= gadgets then
		source.Parent = gadgets
	end
end
local existing = gadgets:FindFirstChild(Constants.REMOTE_CHARGE_TEMPLATE)
if existing then
	existing:Destroy()
end

local mine = gadgets[MINE_SOURCE_NAME]:Clone()
mine.Name = Constants.REMOTE_CHARGE_TEMPLATE
local light = mine:FindFirstChild(Constants.REMOTE_CHARGE_LIGHT_PART, true)
if not light or not light:IsA("BasePart") then
	warn("build_remote_charge_template: " .. MINE_SOURCE_NAME .. " has no " .. Constants.REMOTE_CHARGE_LIGHT_PART .. " part; nothing will breathe")
end
local largest: BasePart? = nil
for _, descendant in mine:GetDescendants() do
	if descendant:IsA("BasePart") then
		descendant.Anchored = true
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
		if not largest or descendant.Size.Magnitude > largest.Size.Magnitude then
			largest = descendant
		end
	end
end
mine.PrimaryPart = largest
-- flat, face up: the art stands the disc with its thickness (X) along
-- the world's Y and the copy keeps that; a model with a PrimaryPart
-- pivots by that part's frame times its PivotOffset, so the offset undoes
-- the part's turn and the pivot is level, and a PivotTo onto the ground
-- keeps the disc flat
largest.PivotOffset = largest.CFrame:Inverse() * CFrame.new(largest.Position)
mine.WorldPivot = CFrame.new(largest.Position)
mine.Parent = gadgets

ChangeHistoryService:SetWaypoint("After Remote Charge template")
print("build_remote_charge_template: built GameAssets." .. Constants.GADGET_TEMPLATES_FOLDER .. "." .. Constants.REMOTE_CHARGE_TEMPLATE .. " from " .. MINE_SOURCE_NAME)
