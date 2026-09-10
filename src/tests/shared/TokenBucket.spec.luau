-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local TokenBucket = require(game:GetService("ServerScriptService").Server.TokenBucket)

describe(
	"TokenBucket",
	function()
		it(
			"starts full and spends down to empty",
			function()
				local bucket = TokenBucket.new(3, 1, 0)
				expect(bucket:getTokens()).toBe(3)
				expect(bucket:tryTake(1, 0)).toBe(true)
				expect(bucket:tryTake(1, 0)).toBe(true)
				expect(bucket:tryTake(1, 0)).toBe(true)
				expect(bucket:tryTake(1, 0)).toBe(false)
				expect(bucket:getTokens()).toBe(0)
			end
		)

		it(
			"rejects a cost larger than the remaining tokens without spending",
			function()
				local bucket = TokenBucket.new(5, 1, 0)
				expect(bucket:tryTake(4, 0)).toBe(true)
				expect(bucket:tryTake(2, 0)).toBe(false)
				expect(bucket:getTokens()).toBe(1)
			end
		)

		it(
			"refills with elapsed time and caps at capacity",
			function()
				local bucket = TokenBucket.new(10, 2, 0)
				expect(bucket:tryTake(10, 0)).toBe(true)
				expect(bucket:tryTake(1, 0.25)).toBe(false)
				expect(bucket:tryTake(1, 0.5)).toBe(true)
				bucket:refill(100)
				expect(bucket:getTokens()).toBe(10)
			end
		)

		it(
			"ignores clocks that run backwards",
			function()
				local bucket = TokenBucket.new(10, 1, 50)
				expect(bucket:tryTake(5, 50)).toBe(true)
				bucket:refill(40)
				expect(bucket:getTokens()).toBe(5)
			end
		)

		it(
			"lets a sustained sender through at exactly the refill rate",
			function()
				local bucket = TokenBucket.new(30, 10, 0)
				local accepted = 0
				for tick = 1, 100 do
					if bucket:tryTake(1, tick * 0.1) then
						accepted += 1
					end
				end
				-- 30 stored plus 10 per second over 10 seconds
				expect(accepted).toBe(100)
			end
		)

		it(
			"drops a burst that exceeds capacity plus refill",
			function()
				local bucket = TokenBucket.new(30, 10, 0)
				local accepted = 0
				for _ = 1, 100 do
					if bucket:tryTake(1, 0) then
						accepted += 1
					end
				end
				expect(accepted).toBe(30)
			end
		)
	end
)
