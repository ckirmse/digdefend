--!strict

-- The pure side of the skills' effects on a run (M56, designed with the
-- designer 2026-11-09). A skill does one of two things: it multiplies a
-- class modifier (the same axis a class buff or debuff rides, so every
-- system keeps reading one number through ClassManager:getModifier), or
-- it changes a rule at one hook, which the gameplay SkillManager answers
-- from the skill set. The functions here are the arithmetic both share,
-- unit tested; the numbers live in GameData/Characters/SkillEffects.
local SkillEffectRules = {}

export type Effect = {
	MODIFIERS: { [number]: number }?,
	PARAMS: { [string]: any }?,
}
export type EffectsById = { [string]: Effect }
export type Modifiers = { [number]: number }

-- the skill ids a class record holds, slot order; none for no record
function SkillEffectRules.skillIdsOf(record: { skills: { [string]: { skillId: string } } }?): { string }
	local ids: { string } = {}
	if not record then
		return ids
	end
	local slots: { number } = {}
	for key in record.skills do
		local slot = tonumber(key)
		if slot then
			table.insert(slots, slot)
		end
	end
	table.sort(slots)
	for _, slot in slots do
		local skill = record.skills[tostring(slot)]
		if skill and typeof(skill.skillId) == "string" then
			table.insert(ids, skill.skillId)
		end
	end
	return ids
end

-- the class's modifiers with every held skill's multiplied in, one table
-- a system or a menu reads as before; a skill with no MODIFIERS, or an id
-- the effects do not know, changes nothing
function SkillEffectRules.combineModifiers(classModifiers: Modifiers, skillIds: { string }, effectsById: EffectsById): Modifiers
	local combined: Modifiers = {}
	for classModifier, scale in classModifiers do
		combined[classModifier] = scale
	end
	for _, skillId in skillIds do
		local effect = effectsById[skillId]
		local modifiers = if effect then effect.MODIFIERS else nil
		if not modifiers then
			continue
		end
		for classModifier, scale in modifiers do
			combined[classModifier] = (combined[classModifier] or 1) * scale
		end
	end
	return combined
end

-- a named number of a skill's PARAMS; the fallback when the skill or the
-- key is unknown, so a hook never reads nil
function SkillEffectRules.param(effectsById: EffectsById, skillId: string, key: string, fallback: number): number
	local effect = effectsById[skillId]
	local params = if effect then effect.PARAMS else nil
	local value = if params then params[key] else nil
	return if typeof(value) == "number" then value else fallback
end

-- whether this break is one the Mother Lode pays double on: every nth,
-- counted from the player's first
function SkillEffectRules.isNthBreak(breakCount: number, everyNth: number): boolean
	return everyNth > 0 and breakCount > 0 and breakCount % everyNth == 0
end

-- the headshot multiple a weapon fires with: its own where it has one,
-- else the Headhunter's for a holder, else none (1)
function SkillEffectRules.headshotMultiplier(weaponMultiplier: number, hasHeadhunter: boolean, headhunterMultiplier: number): number
	if weaponMultiplier > 1 then
		return weaponMultiplier
	end
	return if hasHeadhunter then headhunterMultiplier else 1
end

-- the Last Stand's fire rate multiple for a player at this health share
function SkillEffectRules.fireRateMultiplier(health: number, maxHealth: number, hasLastStand: boolean, healthShareBelow: number, multiplier: number): number
	if not hasLastStand or maxHealth <= 0 then
		return 1
	end
	return if health / maxHealth < healthShareBelow then multiplier else 1
end

-- a Generous donation: the Iron counted into the pool for the Iron paid,
-- never past what the tier still needs
function SkillEffectRules.donationCredit(paidIron: number, multiplier: number, remainingIron: number): number
	return math.max(0, math.min(math.floor(paidIron * multiplier + 0.5), remainingIron))
end

return SkillEffectRules
