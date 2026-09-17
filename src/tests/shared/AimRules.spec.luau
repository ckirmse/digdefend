-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local AimRules = require(game:GetService("ReplicatedStorage").Shared.AimRules)

describe(
	"AimRules pitch",
	function()
		it(
			"reads level, up, and down from a look vector in whole degrees",
			function()
				expect(AimRules.pitchFromLook(Vector3.new(0, 0, -1))).toBe(0)
				expect(AimRules.pitchFromLook(Vector3.new(0, 1, -1))).toBe(45)
				expect(AimRules.pitchFromLook(Vector3.new(0, -1, -1))).toBe(-45)
				expect(AimRules.pitchFromLook(Vector3.new(0, 0.5, -0.866))).toBe(30)
				expect(AimRules.pitchFromLook(Vector3.zero)).toBe(0)
			end
		)

		it(
			"rounds and clamps what a client sends",
			function()
				expect(AimRules.clampPitch(12.4)).toBe(12)
				expect(AimRules.clampPitch(12.6)).toBe(13)
				expect(AimRules.clampPitch(400)).toBe(AimRules.MAX_PITCH_DEGREES)
				expect(AimRules.clampPitch(-400)).toBe(-AimRules.MAX_PITCH_DEGREES)
				expect(AimRules.pitchFromLook(Vector3.new(0, 1, 0))).toBe(AimRules.MAX_PITCH_DEGREES)
			end
		)
	end
)

describe(
	"AimRules.shouldSend",
	function()
		it(
			"always sends the first pitch once the interval allows",
			function()
				expect(AimRules.shouldSend(nil, 0, 0, 10, 0.25, 3)).toBe(true)
			end
		)

		it(
			"waits for the interval and for a big enough change",
			function()
				expect(AimRules.shouldSend(10, 20, 9.9, 10, 0.25, 3)).toBe(false)
				expect(AimRules.shouldSend(10, 12, 9, 10, 0.25, 3)).toBe(false)
				expect(AimRules.shouldSend(10, 13, 9, 10, 0.25, 3)).toBe(true)
				expect(AimRules.shouldSend(10, 7, 9, 10, 0.25, 3)).toBe(true)
			end
		)
	end
)
