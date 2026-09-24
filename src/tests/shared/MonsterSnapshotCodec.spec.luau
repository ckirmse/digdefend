-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local MonsterSnapshotCodec = require(game:GetService("ReplicatedStorage").Shared.MonsterSnapshotCodec)

local function record(id: number, overrides: { [string]: any }?): MonsterSnapshotCodec.Record
	local value: { [string]: any } = {
		id = id,
		position = Vector3.new(12.3, -4.1, 250.6),
		yawDegrees = 90,
		hpShare = 0.5,
		action = 2,
		attackCounter = 3,
		isSlowed = true,
		isBurning = false,
	}
	for key, override in overrides or {} do
		value[key] = override
	end
	return value :: any
end

describe(
	"MonsterSnapshotCodec",
	function()
		it(
			"round-trips a record to a quarter stud",
			function()
				local packets = MonsterSnapshotCodec.encode({ record(4321) }, 1234.5, 900)
				expect(#packets).toBe(1)
				expect(buffer.len(packets[1])).toBe(MonsterSnapshotCodec.HEADER_BYTES + MonsterSnapshotCodec.RECORD_BYTES)
				local serverTime, records = MonsterSnapshotCodec.decode(packets[1])
				expect(serverTime).toBe(1234.5)
				local decoded = (records :: { MonsterSnapshotCodec.Record })[1]
				expect(decoded.id).toBe(4321)
				expect(decoded.position.X).toBeCloseTo(12.25, 5)
				expect(decoded.position.Y).toBeCloseTo(-4, 5)
				expect(decoded.position.Z).toBeCloseTo(250.5, 5)
				expect(decoded.yawDegrees).toBeCloseTo(90, 5)
				expect(decoded.hpShare).toBeCloseTo(128 / 255, 5)
				expect(decoded.action).toBe(2)
				expect(decoded.attackCounter).toBe(3)
				expect(decoded.isSlowed).toBe(true)
				expect(decoded.isBurning).toBe(false)
			end
		)
		it(
			"keeps a sliver of HP above zero and wraps the attack counter",
			function()
				local packets = MonsterSnapshotCodec.encode({
					record(1, { hpShare = 0.0001, attackCounter = 5, isBurning = true }),
					record(2, { hpShare = 0 }),
				}, 0, 900)
				local _, records = MonsterSnapshotCodec.decode(packets[1])
				local decoded = records :: { MonsterSnapshotCodec.Record }
				expect(decoded[1].hpShare).toBeGreaterThan(0)
				expect(decoded[1].attackCounter).toBe(1)
				expect(decoded[1].isBurning).toBe(true)
				expect(decoded[2].hpShare).toBe(0)
			end
		)
		it(
			"clamps positions beyond the reach of sixteen bits",
			function()
				local packets = MonsterSnapshotCodec.encode({ record(1, { position = Vector3.new(99999, 0, -99999) }) }, 0, 900)
				local _, records = MonsterSnapshotCodec.decode(packets[1])
				local decoded = (records :: { MonsterSnapshotCodec.Record })[1]
				expect(decoded.position.X).toBeCloseTo(32767 * 0.25, 5)
				expect(decoded.position.Z).toBeCloseTo(-32768 * 0.25, 5)
			end
		)
		it(
			"splits records over packets that never pass the size limit",
			function()
				local records = {}
				for id = 1, 200 do
					table.insert(records, record(id))
				end
				local packets = MonsterSnapshotCodec.encode(records, 7, 900)
				local perPacket = MonsterSnapshotCodec.recordsPerPacket(900)
				expect(perPacket).toBe(80)
				expect(#packets).toBe(3)
				local total = 0
				for _, packet in packets do
					expect(buffer.len(packet) <= 900).toBe(true)
					local _, decoded = MonsterSnapshotCodec.decode(packet)
					total += #(decoded :: { MonsterSnapshotCodec.Record })
				end
				expect(total).toBe(200)
				expect(#MonsterSnapshotCodec.encode({}, 0, 900)).toBe(0)
			end
		)
		it(
			"rejects anything that is not a well-formed packet",
			function()
				expect(MonsterSnapshotCodec.decode("hello")).toBe(nil)
				expect(MonsterSnapshotCodec.decode(buffer.create(3))).toBe(nil)
				local packet = MonsterSnapshotCodec.encode({ record(1) }, 0, 900)[1]
				local truncated = buffer.create(buffer.len(packet) - 1)
				buffer.copy(truncated, 0, packet, 0, buffer.len(truncated))
				expect(MonsterSnapshotCodec.decode(truncated)).toBe(nil)
			end
		)
		it(
			"visits each record as plain numbers and hands back the time",
			function()
				local packets = MonsterSnapshotCodec.encode({ record(7), record(9, { hpShare = 0 }) }, 42, 900)
				local seen = {}
				local serverTime = MonsterSnapshotCodec.forEachRecord(
					packets[1],
					function(id: number, x: number, y: number, z: number, yawDegrees: number, hpShare: number, action: number, attackCounter: number, isSlowed: boolean, isBurning: boolean)
						table.insert(seen, { id, x, y, z, yawDegrees, hpShare, action, attackCounter, isSlowed, isBurning })
					end
				)
				expect(serverTime).toBe(42)
				expect(#seen).toBe(2)
				expect(seen[1][1]).toBe(7)
				expect(seen[1][2]).toBeCloseTo(12.25, 5)
				expect(seen[1][5]).toBeCloseTo(90, 5)
				expect(seen[1][7]).toBe(2)
				expect(seen[1][9]).toBe(true)
				expect(seen[2][6]).toBe(0)
				expect(MonsterSnapshotCodec.forEachRecord("junk", function() end)).toBe(nil)
			end
		)
	end
)
