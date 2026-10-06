-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local RunReportRules = require(game:GetService("ReplicatedStorage").Shared.RunReportRules)

local function sampleRow()
	local row = RunReportRules.newDayRow(3, 2)
	local alice = RunReportRules.playerDay(row, 20, "Alice")
	alice.ironRefined = 40
	alice.goldRefined = 12
	alice.trips = 3
	alice.tripSecTotal = 90
	alice.towersBuilt = 1
	alice.placementIronSpent = 20
	alice.goldHeld = 123
	alice.ironHeld = 45
	local bob = RunReportRules.playerDay(row, 10, "Bob")
	bob.uraniumRefined = 2
	bob.enemiesKilled = 7
	bob.damageGiven = 412.4
	return row
end

describe(
	"RunReportRules",
	function()
		it(
			"makes a player's entry once and keeps it",
			function()
				local row = RunReportRules.newDayRow(1, 1)
				local first = RunReportRules.playerDay(row, 5, "Cy")
				first.trips = 2
				expect(RunReportRules.playerDay(row, 5, "Cy")).toBe(first)
				expect(RunReportRules.playerDay(row, 5, "Cy").trips).toBe(2)
			end
		)
		it(
			"averages the gaps between payouts, none before the second",
			function()
				local entry = RunReportRules.newPlayerDay("Cy")
				expect(RunReportRules.averageTripSec(entry)).toBeNil()
				entry.trips = 1
				expect(RunReportRules.averageTripSec(entry)).toBeNil()
				entry.trips = 3
				entry.tripSecTotal = 90
				expect(RunReportRules.averageTripSec(entry)).toBe(45)
			end
		)
		it(
			"heads a day with its night once fought, and says so until then",
			function()
				local row = sampleRow()
				expect(RunReportRules.formatDayHeader(row)).toContain("night not fought")
				row.nightSec = 95.4
				row.nightKills = 11
				row.wallDamage = 300
				row.wallsLost = 1
				local header = RunReportRules.formatDayHeader(row)
				expect(header).toContain("day  3")
				expect(header).toContain("night   95s")
				expect(header).toContain("walls lost 1")
			end
		)
		it(
			"ends a player's line with the balances held",
			function()
				local row = sampleRow()
				local line = RunReportRules.formatPlayerLine(row.players[20])
				expect(line).toContain("holds gold   123 iron    45")
			end
		)
		it(
			"lists players by user id with the same columns",
			function()
				local lines = RunReportRules.formatDay(sampleRow())
				expect(#lines).toBe(3)
				expect(lines[2]).toContain("Bob")
				expect(lines[3]).toContain("Alice")
				expect(lines[3]).toContain("trips  3 (avg  45s)")
				expect(lines[3]).toContain("towers +1 ^0 (20 iron)")
				expect(lines[2]).toContain("kills   7")
			end
		)
		it(
			"totals every player over the run",
			function()
				local report = { rows = { sampleRow(), sampleRow() } }
				report.rows[1].nightSec = 60
				report.rows[2].nightSec = 80
				local lines = RunReportRules.formatReport(report, "Run report")
				expect(lines[1]).toBe("Run report")
				local totals = lines[#lines - 2]
				expect(totals).toContain("2 day(s), 2 night(s) fought, 140s of night")
				expect(lines[#lines]).toContain("Alice")
				expect(lines[#lines]).toContain("iron    80")
				expect(lines[#lines]).toContain("trips  6")
			end
		)
	end
)
