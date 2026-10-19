--!strict

-- The Binoculars as the client sees them (2026-10-19). Two jobs. While a
-- Sniper mans their post, the aim button (right mouse, the left trigger)
-- asks the server to tag whatever the post camera's look ray meets
-- (TryTagMonster), refused here with the fail sound while the server's
-- next-tag time has not come; the charge is never interrupted. For every
-- player's tag (the BinocularsTag public attribute, read through the
-- all-players subscription), the tagged monster is dressed for everyone:
-- a Highlight that follows whichever body the monster manager draws it
-- with, and the TagCallout billboard ("TAGGED BY <name>") over it on a
-- throwaway anchor moved every frame. The Camp Map and compass ask
-- isTagged / forEachTagPosition for their marks. A tag comes down when its
-- end time passes or the attribute clears. The PostHud's TagHint (the tag
-- icon, the button under it, a sheet shrinking down it while the cooldown
-- runs) shows a mounted Sniper on keyboard or gamepad that the tag is
-- theirs and when; touch has no Tag button yet, so the hint stays hidden.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BinocularsRules = require("@game/ReplicatedStorage/Shared/BinocularsRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientMonsterManager = require(script.Parent.ClientMonsterManager)
local ClientPostManager = require(script.Parent.ClientPostManager)

local ClientBinocularsManager = {}
ClientBinocularsManager.__index = ClientBinocularsManager

type TagView = {
	userId: number,
	tag: BinocularsRules.Tag,
	highlight: Highlight,
	anchor: BasePart,
	billboard: BillboardGui?,
	adornee: Instance?,
}

export type ClientBinocularsManager = typeof(setmetatable(
	{} :: {
		viewByUserId: { [number]: TagView },
		tagHint: GuiObject?,
		tagHintCooldown: GuiObject?,
		tagHintLabel: TextLabel?,
		tagHintIcon: ImageLabel?,
		tagHintStroke: UIStroke?,
		folder: Folder?,
		hasWarnedTemplate: boolean,
		lastTagTime: number,
	},
	ClientBinocularsManager
))

-- the callout floats this far above the body's centre
local CALLOUT_LIFT_STUDS = 4.5
local HIGHLIGHT_FILL_TRANSPARENCY = 0.7
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 0
local FEEDBACK_COOLING = "Binoculars recharging."
local FEEDBACK_DISPLAY_SEC = 1.5
local TAGGED_BY_FORMAT = "Tagged by %s"
local TAG_HINT_KEYBOARD = "Right click\nto tag"
local TAG_HINT_GAMEPAD = "LT to tag"
local TAG_HINT_COOLING = "Recharging"
-- the icon dims this much while the tag recharges
local TAG_HINT_COOLING_ICON_TRANSPARENCY = 0.5

-- the aim button: free on a post, which has no scope of its own to raise
local function isTagInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton2
		or input.KeyCode == Enum.KeyCode.ButtonL2
end

function ClientBinocularsManager:getFolder(): Folder
	local folder = self.folder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = Constants.TAG_FOLDER
	folder.Parent = workspace
	self.folder = folder
	return folder
end

function ClientBinocularsManager:findTemplate(): BillboardGui?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local guiFolder = if gameAssets then gameAssets:FindFirstChild(Constants.GUI_TEMPLATES_FOLDER) else nil
	local template = if guiFolder then guiFolder:FindFirstChild(Constants.TAG_BILLBOARD) else nil
	if template and template:IsA("BillboardGui") then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientBinocularsManager: no {Constants.TAG_BILLBOARD} BillboardGui under GameAssets.{Constants.GUI_TEMPLATES_FOLDER}; run scripts/studio/build_tag_billboard.luau`)
	end
	return nil
end

-- whether any player's live tag is on this body (the Camp Map's dots)
function ClientBinocularsManager:isTagged(damageableId: string): boolean
	for _, view in self.viewByUserId do
		if view.tag.damageableId == damageableId then
			return true
		end
	end
	return false
end

-- the drawn position of every tagged body (the compass's marks)
function ClientBinocularsManager:forEachTagPosition(callback: (position: Vector3) -> ())
	for _, view in self.viewByUserId do
		local position = ClientMonsterManager:getBodyPosition(view.tag.damageableId)
		if position then
			callback(position)
		end
	end
end

function ClientBinocularsManager:removeView(userId: number)
	local view = self.viewByUserId[userId]
	if not view then
		return
	end
	self.viewByUserId[userId] = nil
	view.highlight:Destroy()
	view.anchor:Destroy()
end

-- a player's tag changed: the old callout comes down and, for a live tag, a new one goes up
function ClientBinocularsManager:applyPublicData(userId: number, data: ClientDataManager.PublicData)
	local tag = BinocularsRules.decodeTag(data.binocularsTag)
	local existing = self.viewByUserId[userId]
	if existing and tag and existing.tag.damageableId == tag.damageableId and existing.tag.endTime == tag.endTime then
		return
	end
	self:removeView(userId)
	if not tag or not BinocularsRules.isTagLive(tag.endTime, workspace:GetServerTimeNow()) then
		return
	end
	local folder = self:getFolder()
	local highlight = Instance.new("Highlight")
	highlight.Name = `Tag{userId}`
	highlight.FillColor = UiStyle.ACCENT_COLOR
	highlight.OutlineColor = UiStyle.ACCENT_COLOR
	highlight.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
	highlight.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = folder
	local anchor = Instance.new("Part")
	anchor.Name = `TagAnchor{userId}`
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
		local label = clone:FindFirstChild(Constants.TAG_LABEL, true)
		if label and label:IsA("TextLabel") then
			label.Text = UiStyle.formatTitle(string.format(TAGGED_BY_FORMAT, data.displayName))
		end
		local icon = clone:FindFirstChild(Constants.TAG_ICON, true)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = Icons.TAG_RETICLE
		end
		clone.Adornee = anchor
		clone.Enabled = false
		clone.Parent = anchor
		billboard = clone
	end
	self.viewByUserId[userId] = {
		userId = userId,
		tag = tag,
		highlight = highlight,
		anchor = anchor,
		billboard = billboard,
		adornee = nil,
	}
	if userId == Players.LocalPlayer.UserId then
		ClientSoundManager:playSfx(SoundNames.Sfx.BINOCULARS_TAG)
	end
end

-- every frame: the callout and outline follow the body; a tag past its
-- time comes down here too, so a late attribute never leaves one hanging
function ClientBinocularsManager:stepViews()
	local now = workspace:GetServerTimeNow()
	for userId, view in self.viewByUserId do
		if not BinocularsRules.isTagLive(view.tag.endTime, now) then
			self:removeView(userId)
			continue
		end
		local position = ClientMonsterManager:getBodyPosition(view.tag.damageableId)
		local adornee = ClientMonsterManager:getBodyInstance(view.tag.damageableId)
		local billboard = view.billboard
		if not position then
			view.highlight.Enabled = false
			if billboard then
				billboard.Enabled = false
			end
			continue
		end
		view.anchor.CFrame = CFrame.new(position + Vector3.new(0, CALLOUT_LIFT_STUDS, 0))
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

-- the use input: the look ray to the server, refused here while cooling
-- so the hand never asks for what the server would refuse
function ClientBinocularsManager:tryTag()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cooldownEndTime = ClientDataManager:getCurrentPlayerAttribute(Attributes.BINOCULARS_COOLDOWN_END_TIME)
	if typeof(cooldownEndTime) == "number" and workspace:GetServerTimeNow() < cooldownEndTime then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_COOLING, FEEDBACK_DISPLAY_SEC)
		return
	end
	ClientNetManager:fireServer(
		NetEventNames.TRY_TAG_MONSTER,
		{
			origin = camera.CFrame.Position,
			direction = camera.CFrame.LookVector,
		}
	)
end

-- the hint beside the post's status bar: shown to a mounted Sniper on
-- keyboard or gamepad, the sheet down it the cooldown's share
function ClientBinocularsManager:renderTagHint(now: number)
	local tagHint = self.tagHint
	if not tagHint then
		return
	end
	local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
	local isShown = self:canTag() and not isTouchOnly
	tagHint.Visible = isShown
	if not isShown then
		return
	end
	local cooldownEndTime = ClientDataManager:getCurrentPlayerAttribute(Attributes.BINOCULARS_COOLDOWN_END_TIME)
	local cooldownSec = ClientDataManager:getGameMetadata(Attributes.BINOCULARS_COOLDOWN_SEC)
	local share = BinocularsRules.cooldownShare(
		if typeof(cooldownEndTime) == "number" then cooldownEndTime else 0,
		if typeof(cooldownSec) == "number" then cooldownSec else 0,
		now
	)
	local cooldown = self.tagHintCooldown
	if cooldown then
		cooldown.Visible = share > 0
		cooldown.Size = UDim2.fromScale(1, share)
	end
	local isCooling = share > 0
	local label = self.tagHintLabel
	if label then
		local isGamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
		local hint = if isCooling then TAG_HINT_COOLING elseif isGamepad then TAG_HINT_GAMEPAD else TAG_HINT_KEYBOARD
		label.Text = UiStyle.formatTitle(hint)
		label.TextColor3 = if isCooling then UiStyle.TEXT_MUTED_COLOR else UiStyle.TEXT_COLOR
	end
	-- green outline and a solid icon when ready; red and dimmed while recharging
	local stroke = self.tagHintStroke
	if stroke then
		stroke.Color = if isCooling then UiStyle.NEGATIVE_COLOR else UiStyle.POSITIVE_COLOR
	end
	local icon = self.tagHintIcon
	if icon then
		icon.ImageTransparency = if isCooling then TAG_HINT_COOLING_ICON_TRANSPARENCY else 0
	end
end

function ClientBinocularsManager:findTagHint()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.POST_HUD_GUI_NAME, 10)
	local tagHint = if gui then gui:FindFirstChild(Constants.POST_HUD_TAG_HINT) else nil
	if not tagHint or not tagHint:IsA("GuiObject") then
		warn("ClientBinocularsManager: PostHud has no TagHint; run scripts/studio/build_post_hud_gui.luau")
		return
	end
	tagHint.Visible = false
	self.tagHint = tagHint
	local cooldown = tagHint:FindFirstChild(Constants.POST_HUD_TAG_HINT_COOLDOWN, true)
	self.tagHintCooldown = if cooldown and cooldown:IsA("GuiObject") then cooldown else nil
	local label = tagHint:FindFirstChild(Constants.POST_HUD_TAG_HINT_LABEL)
	self.tagHintLabel = if label and label:IsA("TextLabel") then label else nil
	local icon = tagHint:FindFirstChild(Constants.POST_HUD_TAG_HINT_ICON)
	self.tagHintIcon = if icon and icon:IsA("ImageLabel") then icon else nil
	if self.tagHintIcon then
		self.tagHintIcon.Image = Icons.TAG_RETICLE
	end
	self.tagHintStroke = tagHint:FindFirstChildOfClass("UIStroke")
end

-- a Sniper at their post, with no menu up
function ClientBinocularsManager:canTag(): boolean
	local gadgetKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_KIND)
	return gadgetKind == Enums.GadgetKind.BINOCULARS and ClientPostManager:getIsMounted()
end

function ClientBinocularsManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or ClientOverlayManager:isOverlayActive() or not isTagInput(input) or not self:canTag() then
		return
	end
	self:tryTag()
end

function ClientBinocularsManager:init()
	self:findTemplate()
	self:findTagHint()
	ClientDataManager:subscribeAllPlayers({
		onAdded = function(userId: number, data: ClientDataManager.PublicData)
			self:applyPublicData(userId, data)
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			self:applyPublicData(userId, data)
		end,
		onRemoved = function(userId: number)
			self:removeView(userId)
		end,
	})
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	RunService.RenderStepped:Connect(
		function()
			self:stepViews()
			self:renderTagHint(workspace:GetServerTimeNow())
		end
	)
end

function ClientBinocularsManager.new(): ClientBinocularsManager
	local self = setmetatable({}, ClientBinocularsManager) :: ClientBinocularsManager
	self.viewByUserId = {}
	self.tagHint = nil
	self.tagHintCooldown = nil
	self.tagHintLabel = nil
	self.tagHintIcon = nil
	self.tagHintStroke = nil
	self.folder = nil
	self.hasWarnedTemplate = false
	self.lastTagTime = 0
	return self
end

return ClientBinocularsManager.new()
