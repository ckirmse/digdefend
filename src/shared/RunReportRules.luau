--!strict

-- Pure rules for the run report (docs/balance-plan.md, M34): the numbers
-- a dawn closes for the day just played, and the lines they print as. The
-- server's RunReportManager feeds events in; this only accumulates and
-- formats, so it is unit testable. Every number is per day: the ore each
-- player carried to the Refinery, their trips and how long each took,
-- the towers and traps bought and upgraded, how the night went (how long
-- it lasted, the kills, the damage the walls and the Refinery took, the
-- repairs paid for), so the balance model's assumptions can be calibrated
-- against what players really did.
local RunReportRules = {}

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

-- player lines in a fixed order (by user id) so two reports line up
function RunReportRules.sortedUserIds(row: DayRow): { number }
	local ids = {}
	for userId in row.players do
		table.insert(ids, userId)
	end
	table.sort(ids)
	return ids
end

function RunReportRules.formatDay(row: DayRow): { string }
	local lines = { RunReportRules.formatDayHeader(row) }
	for _, userId in RunReportRules.sortedUserIds(row) do
		table.insert(lines, RunReportRules.formatPlayerLine(row.players[userId]))
	end
	return lines
end

-- the whole run, with a totals line per player at the end
function RunReportRules.formatReport(report: Report, title: string): { string }
	local lines = { title }
	local totalsByUserId: { [number]: PlayerDay } = {}
	local nightSecTotal = 0
	local nightsFought = 0
	for _, row in report.rows do
		for _, line in RunReportRules.formatDay(row) do
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
	end
	return lines
end

return RunReportRules
