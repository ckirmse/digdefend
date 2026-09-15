--!strict

-- Pure rules for the jet pack (GDD "Jet Pack"): the tank size by level and
-- the fuel bookkeeping the server runs every frame. Fuel is seconds of
-- burn. It refills whenever the pack is not burning, anywhere; running the
-- tank dry locks the pack until it is full again (decided 2026-09-15), which
-- is what keeps a hop from becoming flight. Tuning is passed in from
-- GameData so this stays unit testable.
local JetPackRules = {}

export type Tank = {
	fuelSec: number,
	isBurning: boolean,
	-- set when the tank runs dry; cleared when it is full again
	isLocked: boolean,
}

function JetPackRules.maxFuelForLevel(baseFuelSec: number, fuelPerLevelSec: number, level: number): number
	return baseFuelSec + fuelPerLevelSec * math.max(math.floor(level) - 1, 0)
end

-- burning drains; otherwise the tank refills. Returns the new fuel, whether
-- the pack cut out this step, and whether it is locked afterwards.
function JetPackRules.step(tank: Tank, deltaSec: number, maxFuelSec: number, refillRate: number): (number, boolean, boolean)
	if tank.isBurning then
		local fuel = math.max(tank.fuelSec - deltaSec, 0)
		local isCutOut = fuel <= 0
		return fuel, isCutOut, tank.isLocked or isCutOut
	end
	local fuel = math.min(tank.fuelSec + deltaSec * refillRate, maxFuelSec)
	local isLocked = tank.isLocked and fuel < maxFuelSec
	return fuel, false, isLocked
end

function JetPackRules.canStart(tank: Tank): boolean
	return not tank.isBurning and not tank.isLocked and tank.fuelSec > 0
end

return JetPackRules
