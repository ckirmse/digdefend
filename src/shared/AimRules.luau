--!strict

-- Pure rules for aim replication (M24, reused by mounted post weapons at
-- M25): how a look direction becomes the whole-degree pitch that travels,
-- and when a change is worth a message. Whole degrees keep the public
-- attribute from changing on every tremor of the mouse.
local AimRules = {}

-- straight up and down are never reached by the Roblox camera; the clamp is
-- for what a client might send
AimRules.MAX_PITCH_DEGREES = 85

function AimRules.clampPitch(pitchDegrees: number): number
	return math.clamp(math.round(pitchDegrees), -AimRules.MAX_PITCH_DEGREES, AimRules.MAX_PITCH_DEGREES)
end

-- + looking up, - looking down
function AimRules.pitchFromLook(lookVector: Vector3): number
	if lookVector.Magnitude < 1e-6 then
		return 0
	end
	return AimRules.clampPitch(math.deg(math.asin(math.clamp(lookVector.Unit.Y, -1, 1))))
end

-- a message is due when the pitch moved enough and the last one is old enough
function AimRules.shouldSend(lastSentPitch: number?, pitch: number, lastSendTime: number, now: number, minIntervalSec: number, minChangeDegrees: number): boolean
	if now - lastSendTime < minIntervalSec then
		return false
	end
	return lastSentPitch == nil or math.abs(pitch - lastSentPitch) >= minChangeDegrees
end

return AimRules
