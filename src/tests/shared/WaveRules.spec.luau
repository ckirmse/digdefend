-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local WaveRules = require(game:GetService("ReplicatedStorage").Shared.WaveRules)

local function group(time: number, location: number, enemies: { { number } }): WaveRules.Group
	local counts = {}
	for _, pair in enemies do
		table.insert(counts, {
			KIND = pair[1],
			COUNT = pair[2],
		})
	end
	return {
		ENEMIES = counts,
		SPAWN_LOCATION = location,
		SPAWN_TIME_SEC = time,
	}
end

describe(
	"WaveRules.waveForNight",
	function()
		it(
			"plays the night's own wave, else replays the latest before it",
			function()
				local waves = {
					{ NIGHT = 1, GROUPS = {} },
					{ NIGHT = 3, GROUPS = {} },
				}
				expect((WaveRules.waveForNight(waves, 1) :: WaveRules.Wave).NIGHT).toBe(1)
				expect((WaveRules.waveForNight(waves, 2) :: WaveRules.Wave).NIGHT).toBe(1)
				expect((WaveRules.waveForNight(waves, 7) :: WaveRules.Wave).NIGHT).toBe(3)
				expect(WaveRules.waveForNight({ { NIGHT = 4, GROUPS = {} } }, 2)).toBe(nil)
			end
		)
	end
)

describe(
	"WaveRules groups",
	function()
		it(
			"orders groups by time and keeps authored order on ties",
			function()
				local first = group(10, 1, {})
				local second = group(0, 2, {})
				local third = group(10, 3, {})
				local ordered = WaveRules.orderedGroups({ NIGHT = 1, GROUPS = { first, second, third } })
				expect(ordered[1]).toBe(second)
				expect(ordered[2]).toBe(first)
				expect(ordered[3]).toBe(third)
			end
		)
		it(
			"lists every monster a group spawns",
			function()
				expect(WaveRules.groupKinds(group(0, 1, { { 5, 2 }, { 7, 1 }, { 9, 0 } }))).toEqual({ 5, 5, 7 })
			end
		)
	end
)

describe(
	"WaveRules timing",
	function()
		it(
			"moves every remaining group up by what the next one had left",
			function()
				local later = group(40, 1, {})
				local latest = group(70, 1, {})
				-- night fell at 100; the field emptied at 120, 20 s before the next group
				local shift = WaveRules.shiftForEmptyField(WaveRules.dueTime(later, 100, 0), 120)
				expect(shift).toBe(20)
				expect(WaveRules.dueTime(later, 100, shift)).toBe(120)
				expect(WaveRules.dueTime(latest, 100, shift)).toBe(150)
				expect(WaveRules.shiftForEmptyField(100, 130)).toBe(0)
			end
		)
		it(
			"scatters within the radius around the spawn",
			function()
				local random = Random.new(7)
				local center = Vector3.new(500, 2, -40)
				for _ = 1, 50 do
					local point = WaveRules.scatter(center, 15, random)
					expect(point.Y).toBe(2)
					expect((Vector3.new(point.X, 2, point.Z) - center).Magnitude <= 15 + 1e-6).toBe(true)
				end
			end
		)
	end
)
