--!strict

-- Pure rules for the run record (docs/balance-plan.md, M34, 2026-10-08):
-- the run report's rows turned into the table the server saves in the
-- run-record DataStore, so every run, the designer's and a tester's alike,
-- can be pulled later and averaged against the balance sheet.
--
-- Privacy by construction: the record names nobody. Players are crew
-- slots (1 to 6) in the order they first appear in the run, and neither
-- UserId nor name is written, so there is nothing to erase for a
-- right-to-erasure request and nothing Roblox's privacy rules count as
-- personal data. What is kept: the place version, a fingerprint of the
-- GameData it was played on, whether an admin was in the crew (to tell the
-- designer's runs from testers'), whether it was a Studio session, how many
-- dev commands were used (a forced night taints a day), the map,
-- difficulty, mine seed, and the per-day numbers the report prints.
--
-- Every keyed map is written with string keys, since the JSON the
-- DataStore stores has no number keys.
local RunReportRules = require(script.Parent.RunReportRules)

local RunRecordRules = {}

RunRecordRules.RECORD_VERSION = 1

export type Header = {
	placeVersion: number,
	dataHash: string,
	isStudio: boolean,
	isAdminRun: boolean,
	map: number,
	difficulty: number,
	mineSeed: number,
	startedAtUnix: number,
}

export type PlayerDayRecord = {
	ironRefined: number,
	goldRefined: number,
	uraniumRefined: number,
	trips: number,
	tripSecTotal: number,
	towersBuilt: number,
	towersUpgraded: number,
	placementIronSpent: number,
	repairHp: number,
	repairIron: number,
	enemiesKilled: number,
	damageGiven: number,
	diamondsEarned: number,
	goldHeld: number,
	ironHeld: number,
	mineSec: number,
	postSec: number,
	campSec: number,
	swingsByKind: { [string]: number },
	breaksByKind: { [string]: number },
	deepestDepth: number,
	deepestZone: number,
	deaths: number,
	revives: number,
	damageTaken: number,
	purchases: { RunReportRules.Purchase },
}

export type DayRecord = {
	day: number,
	crew: number,
	nightSec: number?,
	nightKills: number,
	wallDamage: number,
	wallsLost: number,
	refineryDamage: number,
	nightGroups: number,
	nightTargetDifficulty: number,
	clearAfterLastGroupSec: number?,
	structureDamage: { [string]: number },
	damageByMonsterKind: { [string]: number },
	placementsLost: number,
	players: { [string]: PlayerDayRecord },
}

export type Record = {
	recordVersion: number,
	placeVersion: number,
	dataHash: string,
	isStudio: boolean,
	isAdminRun: boolean,
	map: number,
	difficulty: number,
	mineSeed: number,
	startedAtUnix: number,
	endedAtUnix: number?,
	isWon: boolean?,
	endReason: number?,
	devCommands: number,
	crewMax: number,
	days: { DayRecord },
}

local function stringKeys(map: { [any]: number }): { [string]: number }
	local out = {}
	for key, value in map do
		out[tostring(key)] = value
	end
	return out
end

-- the slot of each user id, by first appearance across the rows; a slot
-- is stable for the run so a player's days line up without naming them
function RunRecordRules.slotsByUserId(rows: { RunReportRules.DayRow }): { [number]: number }
	local slots: { [number]: number } = {}
	local nextSlot = 1
	for _, row in rows do
		for _, userId in RunReportRules.sortedUserIds(row) do
			if not slots[userId] then
				slots[userId] = nextSlot
				nextSlot += 1
			end
		end
	end
	return slots
end

function RunRecordRules.playerDayRecord(entry: RunReportRules.PlayerDay): PlayerDayRecord
	return {
		ironRefined = entry.ironRefined,
		goldRefined = entry.goldRefined,
		uraniumRefined = entry.uraniumRefined,
		trips = entry.trips,
		tripSecTotal = entry.tripSecTotal,
		towersBuilt = entry.towersBuilt,
		towersUpgraded = entry.towersUpgraded,
		placementIronSpent = entry.placementIronSpent,
		repairHp = entry.repairHp,
		repairIron = entry.repairIron,
		enemiesKilled = entry.enemiesKilled,
		damageGiven = entry.damageGiven,
		diamondsEarned = entry.diamondsEarned,
		goldHeld = entry.goldHeld,
		ironHeld = entry.ironHeld,
		mineSec = entry.mineSec,
		postSec = entry.postSec,
		campSec = entry.campSec,
		swingsByKind = stringKeys(entry.swingsByKind),
		breaksByKind = stringKeys(entry.breaksByKind),
		deepestDepth = entry.deepestDepth,
		deepestZone = entry.deepestZone,
		deaths = entry.deaths,
		revives = entry.revives,
		damageTaken = entry.damageTaken,
		purchases = table.clone(entry.purchases),
	}
end

function RunRecordRules.dayRecord(row: RunReportRules.DayRow, slots: { [number]: number }): DayRecord
	local players = {}
	for userId, entry in row.players do
		players[tostring(slots[userId])] = RunRecordRules.playerDayRecord(entry)
	end
	return {
		day = row.day,
		crew = row.crew,
		nightSec = row.nightSec,
		nightKills = row.nightKills,
		wallDamage = row.wallDamage,
		wallsLost = row.wallsLost,
		refineryDamage = row.refineryDamage,
		nightGroups = row.nightGroups,
		nightTargetDifficulty = row.nightTargetDifficulty,
		clearAfterLastGroupSec = row.clearAfterLastGroupSec,
		structureDamage = table.clone(row.structureDamage),
		damageByMonsterKind = stringKeys(row.damageByMonsterKind),
		placementsLost = row.placementsLost,
		players = players,
	}
end

-- the whole record from the rows so far; the end fields stay nil until
-- the run ends, so a record saved at a dawn reads as a run in progress
function RunRecordRules.build(header: Header, rows: { RunReportRules.DayRow }, devCommands: number): Record
	local slots = RunRecordRules.slotsByUserId(rows)
	local crewMax = 0
	for _ in slots do
		crewMax += 1
	end
	local days = {}
	for _, row in rows do
		table.insert(days, RunRecordRules.dayRecord(row, slots))
	end
	return {
		recordVersion = RunRecordRules.RECORD_VERSION,
		placeVersion = header.placeVersion,
		dataHash = header.dataHash,
		isStudio = header.isStudio,
		isAdminRun = header.isAdminRun,
		map = header.map,
		difficulty = header.difficulty,
		mineSeed = header.mineSeed,
		startedAtUnix = header.startedAtUnix,
		endedAtUnix = nil,
		isWon = nil,
		endReason = nil,
		devCommands = devCommands,
		crewMax = crewMax,
		days = days,
	}
end

function RunRecordRules.markEnded(record: Record, endedAtUnix: number, isWon: boolean, endReason: number)
	record.endedAtUnix = endedAtUnix
	record.isWon = isWon
	record.endReason = endReason
end

-- the DataStore key: when the run started and a piece of the server's
-- job id, so two servers starting in the same second cannot collide.
-- Studio has no job id, so a caller-made suffix stands in. Keys are
-- limited to 50 characters; this is about 20
function RunRecordRules.key(prefix: string, startedAtUnix: number, jobId: string, fallbackSuffix: string): string
	local suffix = string.sub(jobId, 1, 8)
	if suffix == "" then
		suffix = string.sub(fallbackSuffix, 1, 8)
	end
	return string.format("%s%d_%s", prefix, startedAtUnix, suffix)
end

-- whether a record of this many encoded bytes may be written; the
-- DataStore limit is 4 MB per key and the cap sits well under it
function RunRecordRules.isWithinSize(encodedBytes: number, maxBytes: number): boolean
	return encodedBytes <= maxBytes
end

return RunRecordRules
