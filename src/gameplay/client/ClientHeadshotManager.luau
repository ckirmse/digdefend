--!strict

-- The "HEADSHOT BONUS" callout (2026-10-19): when this player's shot lands
-- in a target's head zone (WeaponRules.isHeadshot on the server, sent back
-- as isHeadshot on NotifyWeaponFired), the HeadshotBonus billboard
-- template is cloned over that body on a throwaway anchored part, rises,
-- fades, and is gone a second later. Only the shooter's client draws it;
-- everyone else sees only the hit flash.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)

local ClientHeadshotManager = {}
ClientHeadshotManager.__index = ClientHeadshotManager

export type ClientHeadshotManager = typeof(setmetatable(
	{} :: {
		folder: Folder?,
		hasWarnedTemplate: boolean,
	},
	ClientHeadshotManager
))

-- the callout starts this far above the body's centre and rises this much
local LIFT_STUDS = 4
local RISE_STUDS = 3
local LIFE_SEC = 1.1

function ClientHeadshotManager:getFolder(): Folder
	local folder = self.folder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.HEADSHOT_FOLDER
	folder.Parent = workspace
	self.folder = folder
	return folder
end

function ClientHeadshotManager:findTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.HEADSHOT_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientHeadshotManager: no {Constants.HEADSHOT_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_headshot_billboard.luau`)
	end
	return nil
end

-- the callout over the body the id names, if this client knows where it is
function ClientHeadshotManager:showBonus(hitId: string)
	local position = ClientDamageableManager:getBodyPosition(hitId)
	local template = self:findTemplate()
	if not position or not template then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = Constants.HEADSHOT_BILLBOARD
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(position)
	local billboard = template:Clone()
	billboard.Adornee = anchor
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LIFT_STUDS, 0)
	billboard.Parent = anchor
	anchor.Parent = self:getFolder()
	local tweenInfo = TweenInfo.new(LIFE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, tweenInfo, { StudsOffsetWorldSpace = Vector3.new(0, LIFT_STUDS + RISE_STUDS, 0) }):Play()
	local label = billboard:FindFirstChild(Constants.HEADSHOT_LABEL)
	if label and label:IsA("TextLabel") then
		TweenService:Create(label, tweenInfo, { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, tweenInfo, { Transparency = 1 }):Play()
		end
	end
	task.delay(
		LIFE_SEC,
		function()
			anchor:Destroy()
		end
	)
end

function ClientHeadshotManager:init()
	self:findTemplate()
end

function ClientHeadshotManager.new(): ClientHeadshotManager
	local self = setmetatable({}, ClientHeadshotManager) :: ClientHeadshotManager
	self.folder = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientHeadshotManager.new()
