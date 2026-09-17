--!strict

-- Press-and-hold swinging for a held tool, as the pick axe established it
-- (ClientMiningManager, researched 2026-09-16): a fresh press (mouse button,
-- gamepad right trigger, or the touch action button through beginHold /
-- endHold) swings at once and holding repeats on the interval; on touch, a
-- finger that rests still in the free screen area for a short dwell starts a
-- hold, and dragging it afterwards turns the camera while the hold goes on.
-- The owner says when it is enabled, how long the interval is, and what a
-- swing does; returning false from the swing (nothing to hit) leaves the
-- interval unspent, so the next frame tries again. The Hammer uses this; the
-- pick axe still carries its own copy with its pause-after-break rule.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)

local ClientHoldInput = {}
ClientHoldInput.__index = ClientHoldInput

export type Config = {
	isEnabled: () -> boolean,
	getIntervalSec: () -> number,
	-- isFreshPress: the swing comes straight from a press, not a repeat
	swing: (isFreshPress: boolean) -> boolean,
}

export type ClientHoldInput = typeof(setmetatable(
	{} :: {
		config: Config,
		isHolding: boolean,
		lastSwingTime: number,
		holdTouch: InputObject?,
		holdTouchStartTime: number,
		holdTouchStartPosition: Vector3,
	},
	ClientHoldInput
))

-- a touch must rest this long, moving less than this, before it is a hold
-- rather than a look or a tap (the feel constants, not gameplay tuning)
local TOUCH_HOLD_DWELL_SEC = 0.25
local TOUCH_HOLD_MAX_MOVE_PX = 12

local function isSwingInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ClientHoldInput:getIsHolding(): boolean
	return self.isHolding
end

function ClientHoldInput:trySwing(isFreshPress: boolean)
	local now = workspace:GetServerTimeNow()
	if now - self.lastSwingTime < self.config.getIntervalSec() then
		return
	end
	if self.config.swing(isFreshPress) then
		self.lastSwingTime = now
	end
end

function ClientHoldInput:beginHold()
	if not self.config.isEnabled() or ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isHolding = true
	self:trySwing(true)
end

function ClientHoldInput:endHold()
	self.isHolding = false
end

-- the owner calls this when its tool is put away mid-hold
function ClientHoldInput:cancel()
	self.isHolding = false
	self.holdTouch = nil
end

function ClientHoldInput:onStep()
	local touch = self.holdTouch
	if touch and not self.isHolding and workspace:GetServerTimeNow() - self.holdTouchStartTime >= TOUCH_HOLD_DWELL_SEC then
		self:beginHold()
	end
	if not self.isHolding or not self.config.isEnabled() or ClientOverlayManager:isOverlayActive() then
		return
	end
	self:trySwing(false)
end

function ClientHoldInput:connect()
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			if not isGameProcessed and isSwingInput(input) then
				self:beginHold()
			end
		end
	)
	UserInputService.InputEnded:Connect(
		function(input: InputObject)
			if isSwingInput(input) then
				self:endHold()
			end
		end
	)
	UserInputService.TouchStarted:Connect(
		function(touch: InputObject, isGameProcessed: boolean)
			if not self.config.isEnabled() or isGameProcessed or self.holdTouch ~= nil or self.isHolding then
				return
			end
			self.holdTouch = touch
			self.holdTouchStartTime = workspace:GetServerTimeNow()
			self.holdTouchStartPosition = touch.Position
		end
	)
	UserInputService.TouchMoved:Connect(
		function(touch: InputObject)
			-- moving before the dwell is a look; moving after the hold began
			-- is a look that keeps swinging
			if touch == self.holdTouch and not self.isHolding and (touch.Position - self.holdTouchStartPosition).Magnitude > TOUCH_HOLD_MAX_MOVE_PX then
				self.holdTouch = nil
			end
		end
	)
	UserInputService.TouchEnded:Connect(
		function(touch: InputObject)
			if touch == self.holdTouch then
				self.holdTouch = nil
				self:endHold()
			end
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:onStep()
		end
	)
end

function ClientHoldInput.new(config: Config): ClientHoldInput
	local self = setmetatable({}, ClientHoldInput) :: ClientHoldInput
	self.config = config
	self.isHolding = false
	self.lastSwingTime = 0
	self.holdTouch = nil
	self.holdTouchStartTime = 0
	self.holdTouchStartPosition = Vector3.zero
	return self
end

return ClientHoldInput
