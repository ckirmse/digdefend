-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local RunReportRules = require(game:GetService("ReplicatedStorage").Shared.RunReportRules)

local function kindName(kind: number): string
	return "Kind" .. kind
end

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
			"lists players by user id, a numbers line and an activity line each",
			function()
				local lines = RunReportRules.formatDay(sampleRow(), kindName)
				expect(#lines).toBe(5)
				expect(lines[2]).toContain("Bob")
				expect(lines[3]).toContain("Bob")
				expect(lines[4]).toContain("Alice")
				expect(lines[4]).toContain("trips  3 (avg  45s)")
				expect(lines[4]).toContain("towers +1 ^0 (20 iron)")
				expect(lines[2]).toContain("kills   7")
				expect(lines[5]).toContain("bought: nothing")
			end
		)
		it(
			"counts swings and breaks by kind and keeps the deepest block",
			function()
				local entry = RunReportRules.newPlayerDay("Cy")
				RunReportRules.recordSwing(entry, RunReportRules.STONE_KEY, false, 3, 1)
				RunReportRules.recordSwing(entry, RunReportRules.STONE_KEY, true, 9, 2)
				RunReportRules.recordSwing(entry, 2, true, 7, 1)
				RunReportRules.recordSwing(entry, 2, false, 4, 1)
				expect(entry.swingsByKind[RunReportRules.STONE_KEY]).toBe(2)
				expect(entry.breaksByKind[RunReportRules.STONE_KEY]).toBe(1)
				expect(entry.swingsByKind[2]).toBe(2)
				expect(entry.breaksByKind[2]).toBe(1)
				expect(entry.deepestDepth).toBe(9)
				expect(entry.deepestZone).toBe(2)
				expect(RunReportRules.formatSwings(entry)).toBe("stone 2/1 gold 2/1 iron 0/0 uranium 0/0")
				local line = RunReportRules.formatPlayerActivityLine(entry)
				expect(line).toContain("deepest block 9 (zone 2)")
			end
		)
		it(
			"lists purchases in order with their currency",
			function()
				local entry = RunReportRules.newPlayerDay("Cy")
				RunReportRules.recordPurchase(entry, "Pick Axe 2", 30, 0)
				RunReportRules.recordPurchase(entry, "fortifications", 0, 10)
				expect(RunReportRules.formatPurchases(entry)).toBe("Pick Axe 2 30g, fortifications 10i")
				RunReportRules.recordPurchase(entry, "fortifications", 0, 10)
				RunReportRules.recordPurchase(entry, "fortifications", 0, 10)
				RunReportRules.recordPurchase(entry, "Torch", 5, 0)
				expect(RunReportRules.formatPurchases(entry)).toBe("Pick Axe 2 30g, fortifications 10i x3, Torch 5g")
				entry.mineSec = 200
				entry.deaths = 1
				local line = RunReportRules.formatPlayerActivityLine(entry)
				expect(line).toContain("mine  200s")
				expect(line).toContain("deaths 1")
				expect(line).toContain("bought: Pick Axe 2 30g, fortifications 10i")
			end
		)
		it(
			"details a fought night by structure and by monster kind, biggest first",
			function()
				local row = RunReportRules.newDayRow(2, 1)
				expect(RunReportRules.formatNightDetail(row, kindName)).toBeNil()
				row.nightSec = 50
				RunReportRules.recordStructureDamage(row, "Wall3", 100, 4)
				RunReportRules.recordStructureDamage(row, "Gate", 300, 1)
				RunReportRules.recordStructureDamage(row, "Wall3", 50, nil)
				row.nightGroups = 3
				row.nightTargetDifficulty = 120.4
				row.clearAfterLastGroupSec = 12.6
				row.placementsLost = 2
				local detail = RunReportRules.formatNightDetail(row, kindName) :: string
				expect(detail).toContain("3 group(s), target 120, clear 13s after the last group")
				expect(detail).toContain("placements lost 2")
				expect(detail).toContain("by structure: Gate 300, Wall3 150")
				expect(detail).toContain("by kind: Kind1 300, Kind4 100")
				expect(RunReportRules.formatDay(row, kindName)[2]).toBe(detail)
			end
		)
		it(
			"accumulates a day into a total, holding the last balances and the deepest front",
			function()
				local total = RunReportRules.newPlayerDay("Cy")
				local first = RunReportRules.newPlayerDay("Cy")
				first.goldRefined = 10
				first.goldHeld = 5
				first.mineSec = 100
				RunReportRules.recordSwing(first, 2, true, 8, 1)
				RunReportRules.recordPurchase(first, "a", 1, 0)
				local second = RunReportRules.newPlayerDay("Cy")
				second.goldRefined = 20
				second.goldHeld = 7
				second.mineSec = 50
				RunReportRules.recordSwing(second, 2, false, 6, 1)
				RunReportRules.accumulatePlayerDay(total, first)
				RunReportRules.accumulatePlayerDay(total, second)
				expect(total.goldRefined).toBe(30)
				expect(total.goldHeld).toBe(7)
				expect(total.mineSec).toBe(150)
				expect(total.swingsByKind[2]).toBe(2)
				expect(total.breaksByKind[2]).toBe(1)
				expect(total.deepestDepth).toBe(8)
				expect(#total.purchases).toBe(1)
			end
		)
		it(
			"totals every player over the run",
			function()
				local report = { rows = { sampleRow(), sampleRow() } }
				report.rows[1].nightSec = 60
				report.rows[2].nightSec = 80
				local lines = RunReportRules.formatReport(report, "Run report", kindName)
				expect(lines[1]).toBe("Run report")
				local totals = lines[#lines - 4]
				expect(totals).toContain("2 day(s), 2 night(s) fought, 140s of night")
				expect(lines[#lines - 1]).toContain("Alice")
				expect(lines[#lines - 1]).toContain("iron    80")
				expect(lines[#lines - 1]).toContain("trips  6")
				expect(lines[#lines]).toContain("Alice")
				expect(lines[#lines]).toContain("bought: nothing")
			end
		)
	end
)
