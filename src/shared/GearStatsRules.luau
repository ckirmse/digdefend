--!strict

-- The stats page behind a gear card on the Character Sheet (M37,
-- 2026-10-13): the base numbers of a weapon, post weapon, or tower kind
-- as label and value rows. The server builds the whole catalogue from
-- GameData once and publishes it as GameMetadata JSON; the client never
-- reads GameData. Pure, so every row is unit tested. Towers reuse the
-- Tower Menu's own formatter (PlacementRules) so the two screens agree.
local CharacterSchema = require(script.Parent.CharacterSchema)
local Enums = require(script.Parent.Enums)
local PlacementRules = require(script.Parent.PlacementRules)

local GearStatsRules = {}

export type StatRow = {
	label: string,
	value: string,
}

-- gear slot -> kind -> rows
export type GearStatsCatalogue = { [number]: { [number]: { StatRow } } }

-- the raw GameData/Weapons/Handheld entry
export type WeaponData = {
	DAMAGE: number,
	FIRE_INTERVAL_SEC: number,
	RANGE_STUDS: number,
	MAGAZINE_SIZE: number,
	RELOAD_SEC: number,
}

-- the raw GameData/Posts/PostWeapons entry
export type PostWeaponData = {
	DAMAGE: number,
	FIRE_INTERVAL_SEC: number,
	RANGE_STUDS: number,
	TURN_SPEED_DEGREES_PER_SEC: number,
	RELOAD_SEC: number?,
	HEAT: { FULL_SEC: number, COOL_SEC: number }?,
	PROJECTILE: { SPLASH_RADIUS_STUDS: number }?,
}

local function row(label: string, value: string): StatRow
	return { label = label, value = value }
end

-- a count with no trailing zeros ("1.7", "60")
local function formatNumber(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return tostring(math.floor(rounded))
	end
	return string.format("%.1f", rounded)
end

local function fireRateText(intervalSec: number): string
	if intervalSec <= 0 then
		return "0/s"
	end
	return formatNumber(1 / intervalSec) .. "/s"
end

function GearStatsRules.weaponRows(data: WeaponData): { StatRow }
	return {
		row("Damage", formatNumber(data.DAMAGE)),
		row("Fire rate", fireRateText(data.FIRE_INTERVAL_SEC)),
		row("Range", formatNumber(data.RANGE_STUDS) .. " studs"),
		row("Magazine", formatNumber(data.MAGAZINE_SIZE)),
		row("Reload", formatNumber(data.RELOAD_SEC) .. "s"),
	}
end

-- the launcher's reload is its fire rate, so a kind with RELOAD_SEC lists
-- that and not a rate; an overheating gun lists how long it fires and
-- cools; a rocket lists its splash
function GearStatsRules.postWeaponRows(data: PostWeaponData): { StatRow }
	local rows = { row("Damage", formatNumber(data.DAMAGE)) }
	if data.RELOAD_SEC then
		table.insert(rows, row("Reload", formatNumber(data.RELOAD_SEC) .. "s"))
	else
		table.insert(rows, row("Fire rate", fireRateText(data.FIRE_INTERVAL_SEC)))
	end
	table.insert(rows, row("Range", formatNumber(data.RANGE_STUDS) .. " studs"))
	table.insert(rows, row("Turn speed", formatNumber(data.TURN_SPEED_DEGREES_PER_SEC) .. " deg/s"))
	local heat = data.HEAT
	if heat then
		table.insert(rows, row("Overheat after", formatNumber(heat.FULL_SEC) .. "s"))
		table.insert(rows, row("Cooldown", formatNumber(heat.COOL_SEC) .. "s"))
	end
	local projectile = data.PROJECTILE
	if projectile then
		table.insert(rows, row("Splash", formatNumber(projectile.SPLASH_RADIUS_STUDS) .. " studs"))
	end
	return rows
end

-- the tower as built (level 1), in the rows and words the Tower Menu uses
function GearStatsRules.towerRows(data: PlacementRules.TowerData): { StatRow }
	local rows: { StatRow } = {}
	local stats = PlacementRules.towerStats(data, PlacementRules.STARTING_LEVEL)
	for _, stat in PlacementRules.towerStatRows(data) do
		local label = Enums.getPublicName(Enums.TowerStat, stat) or "?"
		table.insert(rows, row(label, PlacementRules.towerStatText(stat, stats)))
	end
	return rows
end

-- JSON keys are strings, so the slot and kind numbers travel as names
-- and come back as enum values; an unknown name is dropped with a warning
-- rather than crashing the sheet
function GearStatsRules.encodeCatalogue(catalogue: GearStatsCatalogue): string
	local HttpService = game:GetService("HttpService")
	local bySlotName: { [string]: { [string]: { StatRow } } } = {}
	for gearSlot, byKind in catalogue do
		local slotName = Enums.getName(Enums.GearSlot, gearSlot)
		local gearEnum = CharacterSchema.getGearEnum(gearSlot)
		if not slotName or not gearEnum then
			continue
		end
		local byKindName: { [string]: { StatRow } } = {}
		for kind, rows in byKind do
			local kindName = Enums.getName(gearEnum, kind)
			if kindName then
				byKindName[kindName] = rows
			end
		end
		bySlotName[slotName] = byKindName
	end
	return HttpService:JSONEncode(bySlotName)
end

function GearStatsRules.decodeCatalogue(encoded: any): GearStatsCatalogue
	local catalogue: GearStatsCatalogue = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return catalogue
	end
	local HttpService = game:GetService("HttpService")
	local isSuccess, bySlotName = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(bySlotName) ~= "table" then
		warn("GearStatsRules: bad gear stats catalogue JSON")
		return catalogue
	end
	for slotName, byKindName in bySlotName do
		local gearSlot = Enums.getValueByName(Enums.GearSlot, slotName)
		local gearEnum = if gearSlot then CharacterSchema.getGearEnum(gearSlot) else nil
		if not gearSlot or not gearEnum or typeof(byKindName) ~= "table" then
			continue
		end
		local byKind: { [number]: { StatRow } } = {}
		for kindName, rows in byKindName do
			local kind = Enums.getValueByName(gearEnum, kindName)
			if kind and typeof(rows) == "table" then
				byKind[kind] = rows
			end
		end
		catalogue[gearSlot] = byKind
	end
	return catalogue
end


return GearStatsRules
