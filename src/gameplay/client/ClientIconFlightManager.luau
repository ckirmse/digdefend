--!strict

-- Flies a 2D resource icon across the screen: ore into the backpack button,
-- ore into the Refinery, refined bars into their balance row. Every flight
-- crosses the GameplayHud FlyLayer so it renders above the HUD, and every
-- landing reports back so the caller can play the pop and bump its target.
-- One place owns the look (image from Icons, disc fallback, size bounds) so
-- every flight in the game reads the same.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")

local ClientIconFlightManager = {}
ClientIconFlightManager.__index = ClientIconFlightManager

export type ClientIconFlightManager = typeof(setmetatable(
	{} :: {
		flyLayer: Frame?,
		iconTemplate: ImageLabel?,
	},
	ClientIconFlightManager
))

local FLIGHT_SEC = 0.55
local BUMP_SCALE_NAME = "Bump"

function ClientIconFlightManager:getLayer(): Frame?
	return self.flyLayer
end

-- how far inside the viewport an off-screen origin is pushed
local EDGE_MARGIN_PX = 24

function ClientIconFlightManager:screenCenterOf(guiObject: GuiObject): Vector2
	return guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2
end

-- a world point on screen, or nil when the camera cannot see it
function ClientIconFlightManager:worldToScreen(position: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local point, isOnScreen = camera:WorldToViewportPoint(position)
	if not isOnScreen then
		return nil
	end
	return Vector2.new(point.X, point.Y)
end

-- the same point, but never nil: a world point the camera cannot see is
-- pushed to the nearest viewport edge (mirrored when it is behind the
-- camera), so ore collected at the player's feet in first person still
-- flies in from the bottom of the screen
function ClientIconFlightManager:worldToScreenOrEdge(position: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local point, isOnScreen = camera:WorldToViewportPoint(position)
	local viewport = camera.ViewportSize
	if isOnScreen then
		return Vector2.new(point.X, point.Y)
	end
	local x, y = point.X, point.Y
	if point.Z < 0 then
		x = viewport.X - x
		y = viewport.Y - y
	end
	local margin = EDGE_MARGIN_PX
	return Vector2.new(math.clamp(x, margin, viewport.X - margin), math.clamp(y, margin, viewport.Y - margin))
end

-- a layer-relative scale position from an absolute screen point, so icons
-- follow the GUI standard of scale everywhere
function ClientIconFlightManager:toLayerScale(point: Vector2): UDim2
	local layer = self.flyLayer
	if not layer or layer.AbsoluteSize.X <= 0 or layer.AbsoluteSize.Y <= 0 then
		return UDim2.fromScale(0.5, 0.5)
	end
	local relative = point - layer.AbsolutePosition
	return UDim2.fromScale(relative.X / layer.AbsoluteSize.X, relative.Y / layer.AbsoluteSize.Y)
end

-- the icon is an image when Icons has one; otherwise a coloured disc with a
-- hairline so it still reads against any background. onLanded always fires,
-- at once when there is no layer to fly across
function ClientIconFlightManager:fly(imageId: string?, color: Color3, from: Vector2, to: Vector2, delaySec: number, onLanded: (() -> ())?)
	local layer = self.flyLayer
	if not layer then
		if onLanded then
			onLanded()
		end
		return
	end
	local template = self.iconTemplate
	if not template then
		if onLanded then
			onLanded()
		end
		return
	end
	-- the look (size, bounds, the disc's corner and hairline) is the
	-- template's, authored in StarterGui; only the image and colour are set here
	local isImage = not Icons.isPlaceholder(imageId)
	local icon = template:Clone()
	icon.Name = "FlyIcon"
	icon.Position = self:toLayerScale(from)
	icon.Image = if isImage then imageId :: string else ""
	icon.BackgroundColor3 = color
	icon.BackgroundTransparency = if isImage then 1 else 0
	local stroke = icon:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = not isImage
	end
	icon.Visible = true
	icon.Parent = layer
	task.delay(
		delaySec,
		function()
			if not icon.Parent then
				return
			end
			local tween = TweenService:Create(icon, TweenInfo.new(FLIGHT_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = self:toLayerScale(to) })
			tween.Completed:Connect(
				function()
					icon:Destroy()
					if onLanded then
						onLanded()
					end
				end
			)
			tween:Play()
		end
	)
end

-- a quick swell that settles back, so a landing reads as an impact. Scale,
-- not position, because rows inside a UIListLayout ignore Position
function ClientIconFlightManager:bump(frame: GuiObject)
	local scale = frame:FindFirstChild(BUMP_SCALE_NAME)
	if not scale or not scale:IsA("UIScale") then
		scale = Instance.new("UIScale")
		scale.Name = BUMP_SCALE_NAME
		scale.Parent = frame
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = UiStyle.HUD_BUMP_SCALE
	TweenService:Create(uiScale, TweenInfo.new(UiStyle.HUD_TWEEN_SEC, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
end

-- how much of an amount each of a flight's icons carries, so a HUD number
-- can step up or down as icons land; the first icons take the remainder
function ClientIconFlightManager.splitAmount(amount: number, iconCount: number): { number }
	local shares = {}
	local base = amount // iconCount
	local remainder = amount % iconCount
	for index = 1, iconCount do
		shares[index] = base + (if index <= remainder then 1 else 0)
	end
	return shares
end

function ClientIconFlightManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GAMEPLAY_HUD_GUI_NAME, 10)
	local flyLayer = if gui then gui:FindFirstChild(Constants.HUD_FLY_LAYER) else nil
	local template = if flyLayer then flyLayer:FindFirstChild(Constants.HUD_FLY_ICON_TEMPLATE) else nil
	if flyLayer and flyLayer:IsA("Frame") and template and template:IsA("ImageLabel") then
		self.flyLayer = flyLayer
		self.iconTemplate = template
		template.Visible = false
	else
		warn("ClientIconFlightManager: GameplayHud has no FlyLayer.FlyIconTemplate; icons will not fly. Run scripts/studio/build_gameplay_hud_gui.luau")
	end
end

function ClientIconFlightManager.new(): ClientIconFlightManager
	local self = setmetatable({}, ClientIconFlightManager) :: ClientIconFlightManager
	self.flyLayer = nil
	self.iconTemplate = nil
	return self
end

return ClientIconFlightManager.new()
