-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local RunReportRules = require(game:GetService("ReplicatedStorage").Shared.RunReportRules)
local RunRecordRules = require(game:GetService("ReplicatedStorage").Shared.RunRecordRules)

local function header()
	return {
		placeVersion = 12,
		dataHash = "deadbeef",
		isStudio = true,
		isAdminRun = true,
		map = 1,
		difficulty = 1,
		mineSeed = 42,
		startedAtUnix = 1700000000,
	}
end

local function rows()
	local first = RunReportRules.newDayRow(1, 2)
	local alice = RunReportRules.playerDay(first, 500, "Alice")
	alice.goldRefined = 72
	RunReportRules.recordSwing(alice, 2, true, 6, 1)
	RunReportRules.recordPurchase(alice, "Pick Axe 2", 30, 0)
	local bob = RunReportRules.playerDay(first, 20, "Bob")
	bob.ironRefined = 10
	first.nightSec = 40
	RunReportRules.recordStructureDamage(first, "Wall2", 300, 1)
	local second = RunReportRules.newDayRow(2, 3)
	RunReportRules.playerDay(second, 500, "Alice")
	RunReportRules.playerDay(second, 20, "Bob")
	local carol = RunReportRules.playerDay(second, 900, "Carol")
	carol.deaths = 1
	return { first, second }
end

describe(
	"RunRecordRules",
	function()
		it(
			"gives each user a crew slot by first appearance, in user id order",
			function()
				local slots = RunRecordRules.slotsByUserId(rows())
				expect(slots[20]).toBe(1)
				expect(slots[500]).toBe(2)
				expect(slots[900]).toBe(3)
			end
		)
		it(
			"writes no user id and no name anywhere in the record",
			function()
				local record = RunRecordRules.build(header(), rows(), 0)
				local function walk(value: any)
					if typeof(value) == "table" then
						for key, child in value do
							expect(key).never.toBe("name")
							expect(key).never.toBe("userId")
							expect(key).never.toBe(500)
							expect(key).never.toBe("500")
							walk(child)
						end
					elseif typeof(value) == "string" then
						expect(value).never.toContain("Alice")
						expect(value).never.toContain("Bob")
						expect(value).never.toContain("Carol")
					end
				end
				walk(record)
				expect(record.crewMax).toBe(3)
				expect(record.days[1].players["2"].goldRefined).toBe(72)
				expect(record.days[2].players["3"].deaths).toBe(1)
			end
		)
		it(
			"keeps every keyed map under string keys for the JSON",
			function()
				local record = RunRecordRules.build(header(), rows(), 2)
				local alice = record.days[1].players["2"]
				expect(alice.swingsByKind["2"]).toBe(1)
				expect(alice.breaksByKind["2"]).toBe(1)
				expect(alice.purchases[1].label).toBe("Pick Axe 2")
				expect(record.days[1].damageByMonsterKind["1"]).toBe(300)
				expect(record.days[1].structureDamage.Wall2).toBe(300)
				expect(record.devCommands).toBe(2)
				expect(record.recordVersion).toBe(RunRecordRules.RECORD_VERSION)
			end
		)
		it(
			"carries the header and reads as in progress until marked ended",
			function()
				local record = RunRecordRules.build(header(), rows(), 0)
				expect(record.dataHash).toBe("deadbeef")
				expect(record.placeVersion).toBe(12)
				expect(record.isAdminRun).toBe(true)
				expect(record.endedAtUnix).toBeNil()
				expect(record.isWon).toBeNil()
				RunRecordRules.markEnded(record, 1700001000, false, 2)
				expect(record.endedAtUnix).toBe(1700001000)
				expect(record.isWon).toBe(false)
				expect(record.endReason).toBe(2)
			end
		)
		it(
			"makes a short key from the start time and the job id",
			function()
				local key = RunRecordRules.key("run_", 1700000000, "0123456789abcdef-ffff", "zzzz")
				expect(key).toBe("run_1700000000_01234567")
				expect(#key).toBeLessThanOrEqual(50)
				-- Studio has no job id
				expect(RunRecordRules.key("run_", 1700000000, "", "abcdefghij")).toBe("run_1700000000_abcdefgh")
			end
		)
		it(
			"refuses a record over the size cap",
			function()
				expect(RunRecordRules.isWithinSize(999, 1000)).toBe(true)
				expect(RunRecordRules.isWithinSize(1001, 1000)).toBe(false)
			end
		)
	end
)
