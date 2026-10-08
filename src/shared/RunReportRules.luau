--!strict

-- Pure rules for the run report (docs/balance-plan.md, M34): the numbers
-- a dawn closes for the day just played, and the lines they print as. The
-- server's RunReportManager feeds events in; this only accumulates and
-- formats, so it is unit testable. Every number is per day: the ore each
-- player carried to the Refinery, their trips and how long each took,
-- the towers and traps bought and upgraded, how the night went (how long
-- it lasted, the kills, the damage the walls and the Refinery took, the
-- repairs paid for), so the balance model's assumptions can be calibrated
-- against what players really did. Since 2026-10-08 it also records how
-- the day was spent (where each player stood, what they swung at, how deep
-- they got, every purchase, deaths) and how the night was lost (which
-- structure took what from which monster kind, how long the last group
-- took to die), because those are the model's guessed assumptions.
local RunReportRules = {}

-- the key for stone in the swing and break counts; ore uses its
-- Enums.RawResource value
RunReportRules.STONE_KEY = 0

export type Purchase = {
	label: string,
	gold: number,
	iron: number,
}

export type PlayerDay = {
	name: string,
	ironRefined: number,
	goldRefined: number,
	uraniumRefined: number,
	-- payouts at the Refinery, and the seconds between one and the next
	trips: number,
	tripSecTotal: number,
	-- the Iron spent at the Defense Table, by action
	towersBuilt: number,
	towersUpgraded: number,
	placementIronSpent: number,
	-- Hammer repairs: the HP put back and the Iron it cost
	repairHp: number,
	repairIron: number,
	enemiesKilled: number,
	damageGiven: number,
	diamondsEarned: number,
	-- the Gold and Iron in hand when the day closed (2026-10-06): refined
	-- minus spent, so a pile that never gets used shows as a pile
	goldHeld: number,
	ironHeld: number,
	-- where the player stood, sampled: inside the mine, manning a post, or
	-- anywhere else in camp (the model's MINING_SHARE_OF_DAY and overhead)
	mineSec: number,
	postSec: number,
	campSec: number,
	-- pick axe swings and the rocks they broke, by STONE_KEY or ore
	-- (the model's ORE_SELECTIVITY and URANIUM_SELECTIVITY)
	swingsByKind: { [number]: number },
	breaksByKind: { [number]: number },
	-- the deepest block hit and the zone it was in, 1-based like the mine
	-- report (the model's ZONE_ADVANCE_SHARE); 0 until a swing lands
	deepestDepth: number,
	deepestZone: number,
	deaths: number,
	revives: number,
	damageTaken: number,
	-- every Gold or Iron spend that is not already a column above, in order
	purchases: { Purchase },
}

export type DayRow = {
	day: number,
	crew: number,
	-- the night that ended this day: nil until it has
	nightSec: number?,
	nightKills: number,
	wallDamage: number,
	wallsLost: number,
	refineryDamage: number,
	-- the wave as spawned: its groups, the generator's target, and how
	-- long the field took to clear after the last group arrived
	nightGroups: number,
	nightTargetDifficulty: number,
	clearAfterLastGroupSec: number?,
	-- damage by structure id and by the monster kind that dealt it
	structureDamage: { [string]: number },
	damageByMonsterKind: { [number]: number },
	placementsLost: number,
	players: { [number]: PlayerDay },
}

export type Report = {
	rows: { DayRow },
}

function RunReportRules.newPlayerDay(name: string): PlayerDay
	return {
		name = name,
		ironRefined = 0,
		goldRefined = 0,
		uraniumRefined = 0,
		trips = 0,
		tripSecTotal = 0,
		towersBuilt = 0,
		towersUpgraded = 0,
		placementIronSpent = 0,
		repairHp = 0,
		repairIron = 0,
		enemiesKilled = 0,
		damageGiven = 0,
		diamondsEarned = 0,
		goldHeld = 0,
		ironHeld = 0,
		mineSec = 0,
		postSec = 0,
		campSec = 0,
		swingsByKind = {},
		breaksByKind = {},
		deepestDepth = 0,
		deepestZone = 0,
		deaths = 0,
		revives = 0,
		damageTaken = 0,
		purchases = {},
	}
end

function RunReportRules.newDayRow(day: number, crew: number): DayRow
	return {
		day = day,
		crew = crew,
		nightSec = nil,
		nightKills = 0,
		wallDamage = 0,
		wallsLost = 0,
		refineryDamage = 0,
		nightGroups = 0,
		nightTargetDifficulty = 0,
		clearAfterLastGroupSec = nil,
		structureDamage = {},
		damageByMonsterKind = {},
		placementsLost = 0,
		players = {},
	}
end

-- the player's entry in a row, made on first sight
function RunReportRules.playerDay(row: DayRow, userId: number, name: string): PlayerDay
	local entry = row.players[userId]
	if not entry then
		entry = RunReportRules.newPlayerDay(name)
		row.players[userId] = entry
	end
	return entry
end

-- the average seconds between a player's payouts, nil before the second
function RunReportRules.averageTripSec(entry: PlayerDay): number?
	if entry.trips < 2 then
		return nil
	end
	return entry.tripSecTotal / (entry.trips - 1)
end

-- one swing on a rock: counted by kind, and the tunnel front moved if it
-- is the deepest yet
function RunReportRules.recordSwing(entry: PlayerDay, kindKey: number, isBroken: boolean, depth: number, zone: number)
	entry.swingsByKind[kindKey] = (entry.swingsByKind[kindKey] or 0) + 1
	if isBroken then
		entry.breaksByKind[kindKey] = (entry.breaksByKind[kindKey] or 0) + 1
	end
	if depth > entry.deepestDepth then
		entry.deepestDepth = depth
		entry.deepestZone = zone
	end
end

function RunReportRules.recordPurchase(entry: PlayerDay, label: string, gold: number, iron: number)
	table.insert(entry.purchases, {
		label = label,
		gold = gold,
		iron = iron,
	})
end

function RunReportRules.recordStructureDamage(row: DayRow, structureId: string, amount: number, monsterKind: number?)
	row.structureDamage[structureId] = (row.structureDamage[structureId] or 0) + amount
	if monsterKind then
		row.damageByMonsterKind[monsterKind] = (row.damageByMonsterKind[monsterKind] or 0) + amount
	end
end

local function addCounts(into: { [number]: number }, from: { [number]: number })
	for key, count in from do
		into[key] = (into[key] or 0) + count
	end
end

-- a's numbers plus b's, for the totals at the end of the run; the held
-- balances and the tunnel front are the last day's, not a sum
function RunReportRules.accumulatePlayerDay(total: PlayerDay, entry: PlayerDay)
	total.ironRefined += entry.ironRefined
	total.goldRefined += entry.goldRefined
	total.uraniumRefined += entry.uraniumRefined
	total.trips += entry.trips
	total.tripSecTotal += entry.tripSecTotal
	total.towersBuilt += entry.towersBuilt
	total.towersUpgraded += entry.towersUpgraded
	total.placementIronSpent += entry.placementIronSpent
	total.repairHp += entry.repairHp
	total.repairIron += entry.repairIron
	total.enemiesKilled += entry.enemiesKilled
	total.damageGiven += entry.damageGiven
	total.diamondsEarned += entry.diamondsEarned
	total.goldHeld = entry.goldHeld
	total.ironHeld = entry.ironHeld
	total.mineSec += entry.mineSec
	total.postSec += entry.postSec
	total.campSec += entry.campSec
	addCounts(total.swingsByKind, entry.swingsByKind)
	addCounts(total.breaksByKind, entry.breaksByKind)
	if entry.deepestDepth > total.deepestDepth then
		total.deepestDepth = entry.deepestDepth
		total.deepestZone = entry.deepestZone
	end
	total.deaths += entry.deaths
	total.revives += entry.revives
	total.damageTaken += entry.damageTaken
	for _, purchase in entry.purchases do
		table.insert(total.purchases, purchase)
	end
end

local function formatOptionalSec(value: number?): string
	return if value then string.format("%.0fs", value) else "-"
end

-- one line per player for a day, the same columns every time so the
-- Output reads as a table when the lines are stacked
function RunReportRules.formatPlayerLine(entry: PlayerDay): string
	return string.format(
		"    %-16s iron %5d  gold %5d  uranium %3d | trips %2d (avg %4s) | towers +%d ^%d (%d iron) | repaired %d hp for %d iron | kills %3d  dmg %6.0f | diamonds +%d | holds gold %5d iron %5d",
		string.sub(entry.name, 1, 16),
		entry.ironRefined,
		entry.goldRefined,
		entry.uraniumRefined,
		entry.trips,
		formatOptionalSec(RunReportRules.averageTripSec(entry)),
		entry.towersBuilt,
		entry.towersUpgraded,
		entry.placementIronSpent,
		entry.repairHp,
		entry.repairIron,
		entry.enemiesKilled,
		entry.damageGiven,
		entry.diamondsEarned,
		entry.goldHeld,
		entry.ironHeld
	)
end

-- "stone 180/41 gold 22/9 ..." as swings/breaks, in a fixed kind order
local KIND_COLUMNS = {
	{ key = RunReportRules.STONE_KEY, label = "stone" },
	{ key = 2, label = "gold" },
	{ key = 1, label = "iron" },
	{ key = 3, label = "uranium" },
}

function RunReportRules.formatSwings(entry: PlayerDay): string
	local parts = {}
	for _, column in KIND_COLUMNS do
		table.insert(parts, string.format("%s %d/%d", column.label, entry.swingsByKind[column.key] or 0, entry.breaksByKind[column.key] or 0))
	end
	return table.concat(parts, " ")
end

-- a run of the same purchase (thirty-five fortification donations) reads
-- as one entry with a count
function RunReportRules.formatPurchases(entry: PlayerDay): string
	if #entry.purchases == 0 then
		return "nothing"
	end
	local parts = {}
	local index = 1
	while index <= #entry.purchases do
		local purchase = entry.purchases[index]
		local count = 1
		while index + count <= #entry.purchases do
			local next = entry.purchases[index + count]
			if next.label ~= purchase.label or next.gold ~= purchase.gold or next.iron ~= purchase.iron then
				break
			end
			count += 1
		end
		local cost = if purchase.gold > 0 then string.format("%dg", purchase.gold) else string.format("%di", purchase.iron)
		table.insert(parts, if count > 1 then string.format("%s %s x%d", purchase.label, cost, count) else string.format("%s %s", purchase.label, cost))
		index += count
	end
	return table.concat(parts, ", ")
end

-- the second line per player: how the day was spent, under the numbers line
function RunReportRules.formatPlayerActivityLine(entry: PlayerDay): string
	local front = if entry.deepestDepth > 0 then string.format("block %d (zone %d)", entry.deepestDepth, entry.deepestZone) else "none"
	return string.format(
		"      %-14s mine %4.0fs  post %4.0fs  camp %4.0fs | swings/breaks: %s | deepest %s | deaths %d  revives %d  took %4.0f | bought: %s",
		string.sub(entry.name, 1, 14),
		entry.mineSec,
		entry.postSec,
		entry.campSec,
		RunReportRules.formatSwings(entry),
		front,
		entry.deaths,
		entry.revives,
		entry.damageTaken,
		RunReportRules.formatPurchases(entry)
	)
end

-- the day's header: the night's numbers when it has been fought
function RunReportRules.formatDayHeader(row: DayRow): string
	if row.nightSec == nil then
		return string.format("  day %2d  crew %d  (night not fought)", row.day, row.crew)
	end
	return string.format(
		"  day %2d  crew %d  night %4.0fs  kills %3d  wall dmg %5.0f  walls lost %d  refinery dmg %5.0f",
		row.day,
		row.crew,
		row.nightSec :: number,
		row.nightKills,
		row.wallDamage,
		row.wallsLost,
		row.refineryDamage
	)
end

local function sortedKeys<K>(map: { [K]: number }): { K }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(
		keys,
		function(a: K, b: K)
			if map[a] == map[b] then
				return tostring(a) < tostring(b)
			end
			return map[a] > map[b]
		end
	)
	return keys
end

-- the night's detail under the header: the wave's shape, then damage by
-- structure and by monster kind, biggest first. monsterKindName turns an
-- Enums.MonsterKind value into its name so this stays free of Enums
function RunReportRules.formatNightDetail(row: DayRow, monsterKindName: (kind: number) -> string): string?
	if row.nightSec == nil then
		return nil
	end
	local structures = {}
	for _, id in sortedKeys(row.structureDamage) do
		table.insert(structures, string.format("%s %.0f", id, row.structureDamage[id]))
	end
	local kinds = {}
	for _, kind in sortedKeys(row.damageByMonsterKind) do
		table.insert(kinds, string.format("%s %.0f", monsterKindName(kind), row.damageByMonsterKind[kind]))
	end
	return string.format(
		"    night: %d group(s), target %.0f, clear %s after the last group | placements lost %d | by structure: %s | by kind: %s",
		row.nightGroups,
		row.nightTargetDifficulty,
		formatOptionalSec(row.clearAfterLastGroupSec),
		row.placementsLost,
		if #structures > 0 then table.concat(structures, ", ") else "none",
		if #kinds > 0 then table.concat(kinds, ", ") else "none"
	)
end

-- player lines in a fixed order (by user id) so two reports line up
function RunReportRules.sortedUserIds(row: DayRow): { number }
	local ids = {}
	for userId in row.players do
		table.insert(ids, userId)
	end
	table.sort(ids)
	return ids
end

function RunReportRules.formatDay(row: DayRow, monsterKindName: (kind: number) -> string): { string }
	local lines = { RunReportRules.formatDayHeader(row) }
	local detail = RunReportRules.formatNightDetail(row, monsterKindName)
	if detail then
		table.insert(lines, detail)
	end
	for _, userId in RunReportRules.sortedUserIds(row) do
		local entry = row.players[userId]
		table.insert(lines, RunReportRules.formatPlayerLine(entry))
		table.insert(lines, RunReportRules.formatPlayerActivityLine(entry))
	end
	return lines
end

-- the whole run, with a totals line per player at the end
function RunReportRules.formatReport(report: Report, title: string, monsterKindName: (kind: number) -> string): { string }
	local lines = { title }
	local totalsByUserId: { [number]: PlayerDay } = {}
	local nightSecTotal = 0
	local nightsFought = 0
	for _, row in report.rows do
		for _, line in RunReportRules.formatDay(row, monsterKindName) do
			table.insert(lines, line)
		end
		if row.nightSec then
			nightSecTotal += row.nightSec
			nightsFought += 1
		end
		for userId, entry in row.players do
			local total = totalsByUserId[userId]
			if not total then
				total = RunReportRules.newPlayerDay(entry.name)
				totalsByUserId[userId] = total
			end
			RunReportRules.accumulatePlayerDay(total, entry)
		end
	end
	table.insert(lines, string.format("  totals over %d day(s), %d night(s) fought, %.0fs of night", #report.rows, nightsFought, nightSecTotal))
	local ids = {}
	for userId in totalsByUserId do
		table.insert(ids, userId)
	end
	table.sort(ids)
	for _, userId in ids do
		table.insert(lines, RunReportRules.formatPlayerLine(totalsByUserId[userId]))
		table.insert(lines, RunReportRules.formatPlayerActivityLine(totalsByUserId[userId]))
	end
	return lines
end

return RunReportRules
