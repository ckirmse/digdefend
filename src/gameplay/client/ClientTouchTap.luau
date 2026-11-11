--!strict

-- A tap on the world, for a tool whose use is one act (throw, place, fire,
-- inject) rather than a hold (designer, 2026-11-11: the gesture of
-- Minecraft Bedrock's "Joystick & tap to interact", with the aim left on
-- the centre reticle). A finger that goes down in the free screen
-- area (not a gui, not the thumbstick) and lifts again quickly without
-- having moved is a tap; one that moves is a look and one that rests is a
-- hold, and neither calls back. The hold tools (pick axe, weapon, Hammer)
-- have the same tap inside ClientHoldInput and ClientMiningManager.
local UserInputService = game:GetService("UserInputService")

local ClientTouchTap = {}

-- the same feel constants as the hold's dwell: under them a touch is a tap
local TAP_MAX_SEC = 0.25
local TAP_MAX_MOVE_PX = 12

-- onTap gets the screen position the finger lifted from, in pixels
function ClientTouchTap.connect(onTap: (position: Vector2) -> ())
	local tapTouch: InputObject? = nil
	local startTime = 0
	local startPosition = Vector3.zero
	UserInputService.TouchStarted:Connect(
		function(touch: InputObject, isGameProcessed: boolean)
			if isGameProcessed or tapTouch ~= nil then
				return
			end
			tapTouch = touch
			startTime = workspace:GetServerTimeNow()
			startPosition = touch.Position
		end
	)
	UserInputService.TouchEnded:Connect(
		function(touch: InputObject)
			if touch ~= tapTouch then
				return
			end
			tapTouch = nil
			if workspace:GetServerTimeNow() - startTime >= TAP_MAX_SEC then
				return
			end
			if (touch.Position - startPosition).Magnitude > TAP_MAX_MOVE_PX then
				return
			end
			onTap(Vector2.new(touch.Position.X, touch.Position.Y))
		end
	)
end

return ClientTouchTap
