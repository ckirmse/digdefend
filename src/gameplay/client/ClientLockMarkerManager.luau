--!strict

-- The Missile Launcher's locked targets as the gunner sees them
-- (2026-10-20): every monster the mounted post has locked wears the
-- LockMarker billboard (the Machine Gun's reticle picture) over its body
-- and a green Highlight around whatever body the monster manager draws
-- it with, both on a throwaway anchor moved every frame, like the
-- Binoculars' tag. ClientPostManager names the locked ids each frame
-- (getLockedIds); the markers come and go with them, so a volley or a
-- dismount clears them. This manager exists because ClientMonsterManager
-- requires ClientPostManager, so the post manager cannot ask the monster
-- manager for bodies itself.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientMonsterManager = require(script.Parent.ClientMonsterManager)
local ClientPostManager = require(script.Parent.ClientPostManager)

local ClientLockMarkerManager = {}
ClientLockMarkerManager.__index = ClientLockMarkerManager

type MarkerView = {
	highlight: Highlight,
	anchor: BasePart,
	billboard: BillboardGui?,
	adornee: Instance?,
}

export type ClientLockMarkerManager = typeof(setmetatable(
	{} :: {
		viewById: { [string]: MarkerView },
		folder: Folder?,
		hasWarnedTemplate: boolean,
	},
	ClientLockMarkerManager
))

local FOLDER_NAME = "LockMarkers"
-- the marker floats this far over the body's centre
local MARKER_LIFT_STUDS = 3
local HIGHLIGHT_FILL_TRANSPARENCY = 0.75
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 0

function ClientLockMarkerManager:getFolder(): Folder
	local folder = self.folder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	self.folder = folder
	return folder
end

function ClientLockMarkerManager:findTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.LOCK_MARKER_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientLockMarkerManager: no {Constants.LOCK_MARKER_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_lock_marker_billboard.luau`)
	end
	return nil
end

function ClientLockMarkerManager:addView(damageableId: string)
	local folder = self:getFolder()
	local highlight = Instance.new("Highlight")
	highlight.Name = `Lock{damageableId}`
	highlight.FillColor = UiStyle.POSITIVE_COLOR
	highlight.OutlineColor = UiStyle.POSITIVE_COLOR
	highlight.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
	highlight.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = folder
	local anchor = Instance.new("Part")
	anchor.Name = `LockAnchor{damageableId}`
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = folder
	local template = self:findTemplate()
	local billboard: BillboardGui? = nil
	if template then
		local clone = template:Clone()
		local icon = clone:FindFirstChild(Constants.LOCK_MARKER_ICON, true)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = Icons.LOCK_MARKER
		end
		clone.Adornee = anchor
		clone.Enabled = false
		clone.Parent = anchor
		billboard = clone
	end
	self.viewById[damageableId] = {
		highlight = highlight,
		anchor = anchor,
		billboard = billboard,
		adornee = nil,
	}
end

function ClientLockMarkerManager:removeView(damageableId: string)
	local view = self.viewById[damageableId]
	if not view then
		return
	end
	self.viewById[damageableId] = nil
	view.highlight:Destroy()
	view.anchor:Destroy()
end

-- every frame: a marker per locked id, following its body
function ClientLockMarkerManager:step()
	local lockedIds = ClientPostManager:getLockedIds()
	local wanted: { [string]: boolean } = {}
	for _, id in lockedIds do
		wanted[id] = true
		if not self.viewById[id] then
			self:addView(id)
		end
	end
	for id, view in self.viewById do
		if not wanted[id] then
			self:removeView(id)
			continue
		end
		local position = ClientMonsterManager:getBodyPosition(id)
		local adornee = ClientMonsterManager:getBodyInstance(id)
		local billboard = view.billboard
		if not position then
			view.highlight.Enabled = false
			if billboard then
				billboard.Enabled = false
			end
			continue
		end
		view.anchor.CFrame = CFrame.new(position + Vector3.new(0, MARKER_LIFT_STUDS, 0))
		if billboard then
			billboard.Enabled = true
		end
		if view.adornee ~= adornee then
			view.adornee = adornee
			view.highlight.Adornee = adornee
		end
		view.highlight.Enabled = adornee ~= nil
	end
end

function ClientLockMarkerManager:init()
	RunService.RenderStepped:Connect(
		function()
			self:step()
		end
	)
end

function ClientLockMarkerManager.new(): ClientLockMarkerManager
	local self = setmetatable({}, ClientLockMarkerManager) :: ClientLockMarkerManager
	self.viewById = {}
	self.folder = nil
	self.hasWarnedTemplate = false
	return self
end

return ClientLockMarkerManager.new()
