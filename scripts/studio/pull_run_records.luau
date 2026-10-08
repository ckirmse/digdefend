-- Pulls the saved run records (docs/balance-plan.md, M34) from the
-- run-record DataStore and prints them to the Output: one line per run,
-- then per-day averages over the runs that match the FILTER, so a batch
-- of playtests reads as one table against the balance sheet. Run through
-- the Studio MCP execute_luau in the Edit datamodel of the Gameplay place
-- (API access must be on). Records hold no player identity: players are
-- crew slots.
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

-- which runs the averages are over; nil matches everything
local FILTER = {
	-- "deadbeef": only runs played on that GameData fingerprint
	dataHash = nil,
	-- Enums.Map / Enums.Difficulty values
	map = nil,
	difficulty = nil,
	-- true: only the designer's runs; false: only testers'
	isAdminRun = nil,
	-- true: only finished runs
	isEnded = nil,
	-- runs with more dev commands than this are left out (nil: any)
	maxDevCommands = nil,
}
-- how many of the newest runs to read
MAX_RUNS = 40

-- the Studio command thread cannot require(), so the data module is loaded
-- from its source
local TelemetryData = loadstring(ServerScriptService.GameData.Control.Telemetry.Source)()
local store = DataStoreService:GetDataStore(TelemetryData.RUN_RECORD_STORE_NAME)

local function matches(record)
	for field, wanted in FILTER do
		if wanted == nil then
			continue
		end
		if field == "isEnded" then
			if (record.endedAtUnix ~= nil) ~= wanted then
				return false
			end
		elseif field == "maxDevCommands" then
			if (record.devCommands or 0) > wanted then
				return false
			end
		elseif record[field] ~= wanted then
			return false
		end
	end
	return true
end

-- newest first: keys start with the start time
local keys = {}
local pages = store:ListKeysAsync(TelemetryData.RUN_RECORD_KEY_PREFIX)
while true do
	for _, item in pages:GetCurrentPage() do
		table.insert(keys, item.KeyName)
	end
	if pages.IsFinished then
		break
	end
	pages:AdvanceToNextPageAsync()
end
table.sort(
	keys,
	function(a, b)
		return a > b
	end
)

local records = {}
for index, key in keys do
	if index > MAX_RUNS then
		break
	end
	local isSuccess, record = pcall(
		function()
			return store:GetAsync(key)
		end
	)
	if isSuccess and record then
		record.key = key
		table.insert(records, record)
	else
		warn("[pull_run_records] could not read", key, record)
	end
end

local lines = { string.format("[pull_run_records] %d run(s) in the store, %d read", #keys, #records) }
local matched = {}
for _, record in records do
	local isMatch = matches(record)
	if isMatch then
		table.insert(matched, record)
	end
	local lastDay = record.days[#record.days]
	table.insert(lines, string.format(
		"  %s %s| data %s place v%d%s%s | map %d diff %d crew %d | %d day(s)%s | dev cmds %d%s",
		record.key,
		if isMatch then "" else "(filtered out) ",
		record.dataHash,
		record.placeVersion,
		if record.isStudio then " studio" else "",
		if record.isAdminRun then " admin" else "",
		record.map,
		record.difficulty,
		record.crewMax,
		#record.days,
		if record.endedAtUnix then (if record.isWon then ", won" else ", lost") else ", in progress",
		record.devCommands or 0,
		if lastDay then string.format(" | last day %d: night %s, walls lost %d", lastDay.day, if lastDay.nightSec then string.format("%.0fs", lastDay.nightSec) else "-", lastDay.wallsLost) else ""
	))
end

-- per-day averages per player over the matched runs
local byDay = {}
for _, record in matched do
	for _, day in record.days do
		local bucket = byDay[day.day]
		if not bucket then
			bucket = { runs = 0, players = 0, gold = 0, iron = 0, uranium = 0, trips = 0, mineSec = 0, campSec = 0, postSec = 0, swings = 0, deepest = 0, wallDamage = 0, wallsLost = 0, refineryDamage = 0, nightSec = 0, nights = 0, deaths = 0 }
			byDay[day.day] = bucket
		end
		bucket.runs += 1
		bucket.wallDamage += day.wallDamage
		bucket.wallsLost += day.wallsLost
		bucket.refineryDamage += day.refineryDamage
		if day.nightSec then
			bucket.nightSec += day.nightSec
			bucket.nights += 1
		end
		for _, player in day.players do
			bucket.players += 1
			bucket.gold += player.goldRefined
			bucket.iron += player.ironRefined
			bucket.uranium += player.uraniumRefined
			bucket.trips += player.trips
			bucket.mineSec += player.mineSec
			bucket.campSec += player.campSec
			bucket.postSec += player.postSec
			bucket.deaths += player.deaths
			bucket.deepest += player.deepestDepth
			for _, count in player.swingsByKind do
				bucket.swings += count
			end
		end
	end
end
local days = {}
for day in byDay do
	table.insert(days, day)
end
table.sort(days)
table.insert(lines, string.format("  averages over %d matched run(s), per player per day:", #matched))
for _, day in days do
	local b = byDay[day]
	local p = math.max(b.players, 1)
	table.insert(lines, string.format(
		"    day %2d (%d run(s)): gold %5.0f iron %5.0f uranium %4.1f trips %4.1f | mine %4.0fs camp %4.0fs post %4.0fs swings %4.0f deepest %3.0f deaths %.1f | night %4.0fs wall dmg %5.0f walls lost %.1f refinery dmg %5.0f",
		day,
		b.runs,
		b.gold / p,
		b.iron / p,
		b.uranium / p,
		b.trips / p,
		b.mineSec / p,
		b.campSec / p,
		b.postSec / p,
		b.swings / p,
		b.deepest / p,
		b.deaths / p,
		b.nightSec / math.max(b.nights, 1),
		b.wallDamage / b.runs,
		b.wallsLost / b.runs,
		b.refineryDamage / b.runs
	))
end
print(table.concat(lines, "\n"))
return string.format("%d read, %d matched", #records, #matched)
