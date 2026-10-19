-- Builds GameAssets/Gadgets/AUTO_TURRET from the designer's AutoTurret model
-- (M66): the model is looked for in Workspace first, then as the existing
-- template, cloned under ReplicatedStorage.GameAssets.Gadgets with every
-- part anchored and non-colliding and the Stand as its PrimaryPart. Run from
-- the Studio command bar (or the MCP execute_luau tool) in the gameplay
-- place; the designer's Workspace copy is left where it is. Names must
-- match Constants.GADGET_TEMPLATES_FOLDER / AUTO_TURRET_* (the head part
-- "MachineGun" with its "MuzzleAttachment", the base part "Stand").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local SOURCE_NAME = "AutoTurret"
local TEMPLATE_NAME = "AUTO_TURRET"
local FOLDER_NAME = "Gadgets"
local HEAD_PART = "MachineGun"
local BASE_PART = "Stand"
local MUZZLE_ATTACHMENT = "MuzzleAttachment"

local recording = ChangeHistoryService:TryBeginRecording("Build AUTO_TURRET template")

local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
if not gameAssets then
	gameAssets = Instance.new("Folder")
	gameAssets.Name = "GameAssets"
	gameAssets.Parent = ReplicatedStorage
end
local folder = gameAssets:FindFirstChild(FOLDER_NAME)
if not folder then
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = gameAssets
end

local source = workspace:FindFirstChild(SOURCE_NAME, true) or folder:FindFirstChild(TEMPLATE_NAME)
if not source or not source:IsA("Model") then
	error("build_auto_turret_template: no Workspace." .. SOURCE_NAME .. " model and no existing template")
end

local template = source:Clone()
template.Name = TEMPLATE_NAME
for _, descendant in template:GetDescendants() do
	if descendant:IsA("BasePart") then
		descendant.Anchored = true
		descendant.CanCollide = false
		descendant.CanQuery = false
		descendant.CanTouch = false
	end
end
local base = template:FindFirstChild(BASE_PART)
if base and base:IsA("BasePart") then
	template.PrimaryPart = base
else
	warn("build_auto_turret_template: no " .. BASE_PART .. " part; the client stands the model by its bounding box")
end
if not template:FindFirstChild(HEAD_PART) then
	warn("build_auto_turret_template: no " .. HEAD_PART .. " part; the head will not turn")
end
if not template:FindFirstChild(MUZZLE_ATTACHMENT, true) then
	warn("build_auto_turret_template: no " .. MUZZLE_ATTACHMENT .. "; tracers leave the model's pivot")
end

local existing = folder:FindFirstChild(TEMPLATE_NAME)
if existing then
	existing:Destroy()
end
template.Parent = folder

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print("build_auto_turret_template: built ReplicatedStorage.GameAssets." .. FOLDER_NAME .. "." .. TEMPLATE_NAME)
