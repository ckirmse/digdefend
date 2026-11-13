--!strict

-- Badges (M69): which badges a fact about a player earns. Pure, so every
-- rule the designer agreed is unit tested apart from the managers that
-- gather the facts (BadgeManager, the gameplay BadgeTrackerManager).
-- Every function returns badge kinds in ascending order; the caller
-- awards them and the save decides which are new.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local BadgeRules = {}

BadgeRules.MAX_STARS = 5

-- one entry of GameData/Run/Badges.BY_KIND
export type Definition = {
	BADGE_ID: number,
	DIAMONDS: number,
	STARS: number,
	DESCRIPTION: string,
	ICON: string?,
	COUNTER: number?,
	THRESHOLD: number?,
	NIGHT: number?,
}

export type Definitions = { [number]: Definition }

-- one badge as the Badges menu reads it (the BadgeCatalogue GameMetadata)
export type PublishedBadge = {
	kind: number,
	diamonds: number,
	stars: number,
	description: string,
	icon: string,
}

-- a set of badge kinds, as the client holds the earned and the claimed
export type KindSet = { [number]: boolean }

-- a badge for one player: not earned, earned with its reward waiting, or
-- earned and paid
export type BadgeState = "LOCKED" | "CLAIMABLE" | "CLAIMED"

-- GameData/Run/Badges.RULES
export type Rules = {
	SPEED_RUN_MAX_DAY: number,
	FULL_CREW_SIZE: number,
	QUIET_WEEK_NIGHTS: number,
	ONE_MAN_ARMY_KILLS: number,
	COLLECTOR_CLASSES: number,
	LUCKY_7_DAY: number,
}

-- what the tracker knows about one player's won run
export type RescueSummary = {
	difficulty: number,
	-- the most players the run held at once
	crewSize: number,
	-- the day the helicopter left on
	day: number,
	hasTakenDamage: boolean,
	isRefineryDamaged: boolean,
}

local function isNonnegativeInteger(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value == math.floor(value)
end

local function isPositiveInteger(value: any): boolean
	return isNonnegativeInteger(value) and value > 0
end

-- the problems with the badge table, in order; empty means every badge
-- kind has a well-formed entry
function BadgeRules.validate(definitions: Definitions, rules: Rules): { string }
	local problems = {}
	for _, kind in Enums.getAllValues(Enums.BadgeKind) do
		local name = Enums.getName(Enums.BadgeKind, kind) or tostring(kind)
		local definition = definitions[kind]
		if not definition then
			table.insert(problems, `{name} has no entry`)
			continue
		end
		if not isNonnegativeInteger(definition.BADGE_ID) then
			table.insert(problems, `{name} needs a BADGE_ID (0 until the badge exists on Roblox)`)
		end
		if not isPositiveInteger(definition.DIAMONDS) then
			table.insert(problems, `{name} needs a positive whole DIAMONDS`)
		end
		if not isPositiveInteger(definition.STARS) or definition.STARS > BadgeRules.MAX_STARS then
			table.insert(problems, `{name} needs STARS from 1 to {BadgeRules.MAX_STARS}`)
		end
		if typeof(definition.DESCRIPTION) ~= "string" or definition.DESCRIPTION == "" then
			table.insert(problems, `{name} needs a DESCRIPTION`)
		end
		if definition.ICON ~= nil and typeof(definition.ICON) ~= "string" then
			table.insert(problems, `{name} has an ICON that is not a string`)
		end
		if definition.COUNTER ~= nil or definition.THRESHOLD ~= nil then
			if not Enums.isValidValue(Enums.BadgeCounter, definition.COUNTER) or not isPositiveInteger(definition.THRESHOLD) then
				table.insert(problems, `{name} needs both a COUNTER and a positive whole THRESHOLD`)
			end
		end
		if definition.NIGHT ~= nil and not isPositiveInteger(definition.NIGHT) then
			table.insert(problems, `{name} needs a positive whole NIGHT`)
		end
	end
	for ruleName, value in rules :: { [string]: any } do
		if not isPositiveInteger(value) then
			table.insert(problems, `RULES.{ruleName} must be a positive whole number`)
		end
	end
	return problems
end

local function sorted(kinds: { number }): { number }
	table.sort(kinds)
	return kinds
end

-- the lifetime badges a counter's value has reached
function BadgeRules.kindsForCounter(definitions: Definitions, counter: number, value: number): { number }
	local kinds = {}
	for kind, definition in definitions do
		local threshold = definition.THRESHOLD
		if definition.COUNTER == counter and threshold and value >= threshold then
			table.insert(kinds, kind)
		end
	end
	return sorted(kinds)
end

-- the survival badges for a player alive at the dawn after a night
function BadgeRules.kindsForNight(definitions: Definitions, night: number): { number }
	local kinds = {}
	for kind, definition in definitions do
		local badgeNight = definition.NIGHT
		if badgeNight and night >= badgeNight then
			table.insert(kinds, kind)
		end
	end
	return sorted(kinds)
end

-- the badges a rescue earns the player who boarded. A Nightmare win is
-- also a Hard one
function BadgeRules.kindsForRescue(summary: RescueSummary, rules: Rules): { number }
	local kinds = { Enums.BadgeKind.RESCUED }
	if summary.difficulty >= Enums.Difficulty.HARD then
		table.insert(kinds, Enums.BadgeKind.HARD_RESCUE)
	end
	if summary.difficulty >= Enums.Difficulty.NIGHTMARE then
		table.insert(kinds, Enums.BadgeKind.NIGHTMARE_RESCUE)
	end
	if summary.crewSize >= rules.FULL_CREW_SIZE then
		table.insert(kinds, Enums.BadgeKind.FULL_CREW)
	end
	if summary.crewSize == 1 then
		table.insert(kinds, Enums.BadgeKind.LONE_MINER)
	end
	if not summary.hasTakenDamage then
		table.insert(kinds, Enums.BadgeKind.NOT_A_SCRATCH)
	end
	if summary.day <= rules.SPEED_RUN_MAX_DAY then
		table.insert(kinds, Enums.BadgeKind.SPEED_RUN)
	end
	if not summary.isRefineryDamaged then
		table.insert(kinds, Enums.BadgeKind.UNTOUCHED_REFINERY)
	end
	return sorted(kinds)
end

-- the class badges an account's gacha progress earns (class key name to
-- skill slots open; an entry means the class is owned): one class with
-- every slot open, and enough classes owned
function BadgeRules.kindsForClassProgress(progress: { [string]: number }, maxSkillSlots: number, rules: Rules): { number }
	local kinds = {}
	local ownedCount = 0
	local hasMaxedClass = false
	for _, slots in progress do
		ownedCount += 1
		if slots >= maxSkillSlots then
			hasMaxedClass = true
		end
	end
	if hasMaxedClass then
		table.insert(kinds, Enums.BadgeKind.CLASS_ACT)
	end
	if ownedCount >= rules.COLLECTOR_CLASSES then
		table.insert(kinds, Enums.BadgeKind.COLLECTOR)
	end
	return sorted(kinds)
end

-- Quiet Week's count of quiet nights in a row after one more night
function BadgeRules.nextQuietStreak(streak: number, wasStructureDamaged: boolean): number
	return if wasStructureDamaged then 0 else streak + 1
end

function BadgeRules.getState(isEarned: boolean, isClaimed: boolean): BadgeState
	if not isEarned then
		return "LOCKED"
	end
	return if isClaimed then "CLAIMED" else "CLAIMABLE"
end

-- whether the reward can be paid now: earned, and not paid before
function BadgeRules.canClaim(isEarned: boolean, isClaimed: boolean): boolean
	return BadgeRules.getState(isEarned, isClaimed) == "CLAIMABLE"
end

-- how many earned badges still hold their reward
function BadgeRules.countClaimable(earned: KindSet, claimed: KindSet): number
	local count = 0
	for kind in earned do
		if not claimed[kind] then
			count += 1
		end
	end
	return count
end

-- the menu's list, in the enum's order. A badge's picture is its own
-- ICON, else the one found for it (the Roblox badge's), else the default
function BadgeRules.publish(definitions: Definitions, iconByKind: { [number]: string }, defaultIcon: string): { PublishedBadge }
	local published = {}
	local kinds = Enums.getAllValues(Enums.BadgeKind)
	table.sort(kinds)
	for _, kind in kinds do
		local definition = definitions[kind]
		if not definition then
			continue
		end
		local icon: string = definition.ICON or ""
		if icon == "" then
			icon = iconByKind[kind] or defaultIcon
		end
		table.insert(
			published,
			{
				kind = kind,
				diamonds = definition.DIAMONDS,
				stars = definition.STARS,
				description = definition.DESCRIPTION,
				icon = icon,
			}
		)
	end
	return published
end

-- the menu's order (designer, 2026-11-12): the earned badges first, then
-- the locked, each group from the fewest stars to the most and in the
-- enum's order within a star level. A new list; the catalogue is untouched
function BadgeRules.sortForMenu(published: { PublishedBadge }, earned: KindSet): { PublishedBadge }
	local sortedBadges = table.clone(published)
	table.sort(
		sortedBadges,
		function(first: PublishedBadge, second: PublishedBadge): boolean
			local isFirstEarned = earned[first.kind] == true
			local isSecondEarned = earned[second.kind] == true
			if isFirstEarned ~= isSecondEarned then
				return isFirstEarned
			end
			if first.stars ~= second.stars then
				return first.stars < second.stars
			end
			return first.kind < second.kind
		end
	)
	return sortedBadges
end

function BadgeRules.encodeCatalogue(published: { PublishedBadge }): string
	return HttpService:JSONEncode(published)
end

-- nil for anything that is not a well-formed list
function BadgeRules.decodeCatalogue(encoded: any): { PublishedBadge }?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return nil
	end
	local published = {}
	for _, entry in decoded do
		if
			typeof(entry) ~= "table"
			or not Enums.isValidValue(Enums.BadgeKind, entry.kind)
			or typeof(entry.diamonds) ~= "number"
			or typeof(entry.stars) ~= "number"
			or typeof(entry.description) ~= "string"
			or typeof(entry.icon) ~= "string"
		then
			return nil
		end
		table.insert(
			published,
			{
				kind = entry.kind,
				diamonds = entry.diamonds,
				stars = entry.stars,
				description = entry.description,
				icon = entry.icon,
			}
		)
	end
	return published
end

-- a save's set (enum key name -> true) as a sorted list of enum values,
-- so the client never sees a save's key names
function BadgeRules.encodeKinds(savedSet: { [string]: boolean }): string
	local kinds = {}
	for name, isSet in savedSet do
		local kind = Enums.getValueByName(Enums.BadgeKind, name)
		if kind and isSet == true then
			table.insert(kinds, kind)
		end
	end
	table.sort(kinds)
	return HttpService:JSONEncode(kinds)
end

function BadgeRules.decodeKinds(encoded: any): KindSet
	local set: KindSet = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return set
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return set
	end
	for _, kind in decoded do
		if Enums.isValidValue(Enums.BadgeKind, kind) then
			set[kind] = true
		end
	end
	return set
end

return BadgeRules
