--!strict

-- The monster position snapshot (GDD "Monster Performance"), M29: how many
-- monsters' places fit in the few bytes an UnreliableRemoteEvent carries.
-- A packet is a header (the server time it was taken, the record count)
-- then one fixed 11-byte record per monster: its id, its position to a
-- quarter stud on each axis, its facing to 1/256 of a turn, its HP share,
-- and a flags byte (what it is doing, a counter that ticks on every attack
-- so the client knows to swing even if a packet was lost, slowed, burning).
-- A packet never passes maxBytes; the encoder splits the records over as
-- many packets as it needs. Pure, unit tested; used by MonsterManager and
-- ClientMonsterManager.
local MonsterSnapshotCodec = {}

export type Record = {
	id: number,
	position: Vector3,
	yawDegrees: number,
	-- 0 to 1
	hpShare: number,
	-- Enums.MonsterAction
	action: number,
	-- 0 to 3, wrapping
	attackCounter: number,
	isSlowed: boolean,
	isBurning: boolean,
}

MonsterSnapshotCodec.HEADER_BYTES = 10
MonsterSnapshotCodec.RECORD_BYTES = 11
MonsterSnapshotCodec.POSITION_STEP_STUDS = 0.25
MonsterSnapshotCodec.MAX_ID = 65535
MonsterSnapshotCodec.ATTACK_COUNTER_WRAP = 4

local INT16_MIN = -32768
local INT16_MAX = 32767
local SLOWED_BIT = 16
local BURNING_BIT = 32

function MonsterSnapshotCodec.recordsPerPacket(maxBytes: number): number
	return math.max(1, (maxBytes - MonsterSnapshotCodec.HEADER_BYTES) // MonsterSnapshotCodec.RECORD_BYTES)
end

local function quantize(value: number): number
	return math.clamp(math.floor(value / MonsterSnapshotCodec.POSITION_STEP_STUDS + 0.5), INT16_MIN, INT16_MAX)
end

local function writeRecord(packet: buffer, offset: number, record: Record)
	buffer.writeu16(packet, offset, record.id)
	buffer.writei16(packet, offset + 2, quantize(record.position.X))
	buffer.writei16(packet, offset + 4, quantize(record.position.Y))
	buffer.writei16(packet, offset + 6, quantize(record.position.Z))
	buffer.writeu8(packet, offset + 8, math.floor((record.yawDegrees % 360) / 360 * 256 + 0.5) % 256)
	-- anything alive shows at least one step, so 0 always means dead
	local hpByte = if record.hpShare <= 0 then 0 else math.clamp(math.ceil(record.hpShare * 255), 1, 255)
	buffer.writeu8(packet, offset + 9, hpByte)
	local flags = (record.action % 4) + (record.attackCounter % MonsterSnapshotCodec.ATTACK_COUNTER_WRAP) * 4
	if record.isSlowed then
		flags += SLOWED_BIT
	end
	if record.isBurning then
		flags += BURNING_BIT
	end
	buffer.writeu8(packet, offset + 10, flags)
end

local function readRecord(packet: buffer, offset: number): Record
	local flags = buffer.readu8(packet, offset + 10)
	local step = MonsterSnapshotCodec.POSITION_STEP_STUDS
	return {
		id = buffer.readu16(packet, offset),
		position = Vector3.new(buffer.readi16(packet, offset + 2) * step, buffer.readi16(packet, offset + 4) * step, buffer.readi16(packet, offset + 6) * step),
		yawDegrees = buffer.readu8(packet, offset + 8) / 256 * 360,
		hpShare = buffer.readu8(packet, offset + 9) / 255,
		action = flags % 4,
		attackCounter = (flags // 4) % MonsterSnapshotCodec.ATTACK_COUNTER_WRAP,
		isSlowed = (flags // SLOWED_BIT) % 2 == 1,
		isBurning = (flags // BURNING_BIT) % 2 == 1,
	}
end

-- the records as packets of at most maxBytes, each stamped with the time;
-- no records, no packets
function MonsterSnapshotCodec.encode(records: { Record }, serverTime: number, maxBytes: number): { buffer }
	local packets = {}
	local perPacket = MonsterSnapshotCodec.recordsPerPacket(maxBytes)
	local total = #records
	local first = 1
	while first <= total do
		local last = math.min(total, first + perPacket - 1)
		local count = last - first + 1
		local packet = buffer.create(MonsterSnapshotCodec.HEADER_BYTES + count * MonsterSnapshotCodec.RECORD_BYTES)
		buffer.writef64(packet, 0, serverTime)
		buffer.writeu16(packet, 8, count)
		for index = first, last do
			writeRecord(packet, MonsterSnapshotCodec.HEADER_BYTES + (index - first) * MonsterSnapshotCodec.RECORD_BYTES, records[index])
		end
		table.insert(packets, packet)
		first = last + 1
	end
	return packets
end

-- the time and records of one packet; nil for anything malformed, since
-- it arrives from the network
function MonsterSnapshotCodec.decode(packet: any): (number?, { Record }?)
	if typeof(packet) ~= "buffer" then
		return nil, nil
	end
	local length = buffer.len(packet)
	if length < MonsterSnapshotCodec.HEADER_BYTES then
		return nil, nil
	end
	local count = buffer.readu16(packet, 8)
	if length ~= MonsterSnapshotCodec.HEADER_BYTES + count * MonsterSnapshotCodec.RECORD_BYTES then
		return nil, nil
	end
	local records: { Record } = {}
	for index = 1, count do
		records[index] = readRecord(packet, MonsterSnapshotCodec.HEADER_BYTES + (index - 1) * MonsterSnapshotCodec.RECORD_BYTES)
	end
	return buffer.readf64(packet, 0), records
end

return MonsterSnapshotCodec
