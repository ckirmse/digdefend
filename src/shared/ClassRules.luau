--!strict

-- Pure class rules (GDD "Classes"), M64: what a class row says a run
-- should use. A class row is the GameData/Classes/Roster entry handed in
-- by the server, so this module has no GameData of its own and every rule
-- is unit tested. The one idea here is the modifier table: a stat the
-- class scales is a number in MODIFIERS, and every other stat is 1.0, so
-- the place a stat is computed asks `modifier` and never checks the class.
local Enums = require(script.Parent.Enums)

local ClassRules = {}

export type Kit = {
	-- Enums.WeaponKind
	WEAPON: number,
	-- Enums.PostWeaponKind
	POST: number,
	-- Enums.TowerKind, exactly one (decided 2026-10-19)
	TOWER: number,
	-- Enums.GadgetKind
	GADGET: number,
}

export type ClassData = {
	KIT: Kit,
	-- Enums.ClassModifier -> the scale; absent means 1.0
	MODIFIERS: { [number]: number },
}

ClassRules.DEFAULT_MODIFIER = 1.0

-- the two stats every class states outright, 1.0 included (decided
-- 2026-10-19): speed and mining strength are the body of a class and a
-- designer reading the roster should see both side by side, where every
-- other modifier appears only when a class moves it. Health was a third
-- for an afternoon and dropped as one variable too many
ClassRules.CORE_MODIFIERS = {
	Enums.ClassModifier.MOVE_SPEED,
	Enums.ClassModifier.MINING_POWER,
}

-- the scale a class puts on one stat; 1.0 for a stat it leaves alone and
-- for no class at all, so a caller never needs a nil check
function ClassRules.modifier(classData: ClassData?, classModifier: number): number
	if not classData then
		return ClassRules.DEFAULT_MODIFIER
	end
	local scale = classData.MODIFIERS[classModifier]
	return if scale ~= nil then scale else ClassRules.DEFAULT_MODIFIER
end

-- a scaled integer amount (a price, a capacity, a repair chunk), rounded
-- to the nearest whole number so a half-price trap never costs a fraction
function ClassRules.scaleAmount(amount: number, scale: number): number
	return math.floor(amount * scale + 0.5)
end

-- the kit item a gear slot names, as its kind enum value; nil for the
-- second tower row, which no class fills (one tower each; the row stays
-- in the save schema until the menus are redrawn for classes)
function ClassRules.kitKind(classData: ClassData?, gearSlot: number): number?
	if not classData then
		return nil
	end
	local kit = classData.KIT
	if gearSlot == Enums.GearSlot.WEAPON then
		return kit.WEAPON
	elseif gearSlot == Enums.GearSlot.POST then
		return kit.POST
	elseif gearSlot == Enums.GearSlot.TOWER_1 then
		return kit.TOWER
	end
	return nil
end

-- the towers a class may build: its one tower, as a list because the
-- placement code reads a loadout of kinds (empty for no class)
function ClassRules.towerKinds(classData: ClassData?): { number }
	if not classData then
		return {}
	end
	return { classData.KIT.TOWER }
end

-- the gadget a class carries (Enums.GadgetKind); NONE for no class
function ClassRules.gadgetKind(classData: ClassData?): number
	if not classData then
		return Enums.GadgetKind.NONE
	end
	return classData.KIT.GADGET
end

-- every problem with a roster row, as messages naming the field, so the
-- server can refuse a class whose kit points at nothing at startup
-- (isKindKnown answers whether a gear slot's kind has GameData behind it)
function ClassRules.rosterRowProblems(classData: any, isKindKnown: (gearSlot: number, kind: number) -> boolean): { string }
	local problems: { string } = {}
	if typeof(classData) ~= "table" or typeof(classData.KIT) ~= "table" then
		table.insert(problems, "no KIT")
		return problems
	end
	local kit = classData.KIT
	if not Enums.isValidValue(Enums.WeaponKind, kit.WEAPON) or not isKindKnown(Enums.GearSlot.WEAPON, kit.WEAPON) then
		table.insert(problems, "KIT.WEAPON is not a built weapon")
	end
	if not Enums.isValidValue(Enums.PostWeaponKind, kit.POST) or not isKindKnown(Enums.GearSlot.POST, kit.POST) then
		table.insert(problems, "KIT.POST is not a built post weapon")
	end
	if kit.TOWERS ~= nil then
		table.insert(problems, "KIT.TOWERS is gone: a class carries exactly one TOWER")
	end
	if not Enums.isValidValue(Enums.TowerKind, kit.TOWER) or not isKindKnown(Enums.GearSlot.TOWER_1, kit.TOWER) then
		table.insert(problems, "KIT.TOWER is not a built tower")
	end
	if not Enums.isValidValue(Enums.GadgetKind, kit.GADGET) then
		table.insert(problems, "KIT.GADGET is not a gadget")
	end
	if typeof(classData.MODIFIERS) ~= "table" then
		table.insert(problems, "no MODIFIERS table")
	else
		for classModifier, scale in classData.MODIFIERS do
			if not Enums.isValidValue(Enums.ClassModifier, classModifier) then
				table.insert(problems, "MODIFIERS has an unknown key " .. tostring(classModifier))
			elseif typeof(scale) ~= "number" or scale < 0 then
				table.insert(problems, "MODIFIERS[" .. tostring(classModifier) .. "] is not a non-negative number")
			end
		end
		for _, coreModifier in ClassRules.CORE_MODIFIERS do
			if classData.MODIFIERS[coreModifier] == nil then
				table.insert(problems, "MODIFIERS does not state the core stat " .. (Enums.getName(Enums.ClassModifier, coreModifier) or tostring(coreModifier)))
			end
		end
	end
	return problems
end

return ClassRules
