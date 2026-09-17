--!strict

-- Pure rules for camp structures with HP (GDD "Walls", "Gate", "Wall
-- Repair"): max HP per tier, what one Hammer swing repairs and costs, what
-- the fortification upgrade costs, and how the crew's donations fill it. Tuning is passed in from GameData
-- so this stays unit testable.
local StructureRules = {}

export type KindData = {
	MAX_HP_BY_TIER: { number },
}

function StructureRules.topTier(kindData: KindData): number
	return #kindData.MAX_HP_BY_TIER
end

function StructureRules.maxHp(kindData: KindData, tier: number): number
	local clamped = math.clamp(math.floor(tier), 1, StructureRules.topTier(kindData))
	return kindData.MAX_HP_BY_TIER[clamped]
end

-- one Hammer swing: the HP it adds (a whole chunk, or whatever is missing)
-- and the Iron it costs (the chunk price, or a short last chunk's share
-- rounded up, never less than 1). Both are 0 at full HP
function StructureRules.repairChunk(maxHp: number, hp: number, chunkHp: number, chunkIron: number): (number, number)
	local missing = math.clamp(maxHp - hp, 0, maxHp)
	if missing <= 0 or chunkHp <= 0 then
		return 0, 0
	end
	local gained = math.min(chunkHp, missing)
	return gained, math.max(1, math.ceil(chunkIron * gained / chunkHp))
end

-- rubble stands back up once its HP reaches this share of the maximum
function StructureRules.isRebuilt(hp: number, maxHp: number, standShare: number): boolean
	return hp > 0 and hp >= maxHp * math.clamp(standShare, 0, 1)
end

-- where a swing lands: the closest point of the structure's bounds, so a
-- long wall can be repaired from anywhere along it
function StructureRules.isWithinReach(playerPosition: Vector3, boundsCFrame: CFrame, boundsSize: Vector3, reachStuds: number, toleranceStuds: number): boolean
	local relative = boundsCFrame:PointToObjectSpace(playerPosition)
	local half = boundsSize / 2
	local closest = Vector3.new(math.clamp(relative.X, -half.X, half.X), math.clamp(relative.Y, -half.Y, half.Y), math.clamp(relative.Z, -half.Z, half.Z))
	return (relative - closest).Magnitude <= reachStuds + toleranceStuds
end

function StructureRules.canSwing(lastSwingTime: number?, now: number, cooldownSec: number): boolean
	return lastSwingTime == nil or now - lastSwingTime >= cooldownSec
end

-- Iron to take the whole fortification (gate, walls, and the look of the
-- posts share one tier) from `tier` to the next; nil at the top tier
function StructureRules.upgradeCost(upgradeIronToTier: { number }, tier: number): number?
	return upgradeIronToTier[math.floor(tier) + 1]
end

-- an upgrade keeps each structure's share of HP, rounded up, so it is never
-- a cheap mass repair; a destroyed structure stays destroyed
function StructureRules.hpAfterUpgrade(hp: number, oldMaxHp: number, newMaxHp: number): number
	if hp <= 0 or oldMaxHp <= 0 then
		return 0
	end
	return math.min(newMaxHp, math.ceil(newMaxHp * math.min(hp, oldMaxHp) / oldMaxHp))
end

-- one press at the Workbench: the Iron it moves into the shared pool (a whole
-- donation, or whatever the pool still needs, so the pool never overfills)
-- and whether that fills it. Nothing moves once there is no next tier
function StructureRules.donate(pool: number, required: number?, donationIron: number): (number, boolean)
	if required == nil or donationIron <= 0 then
		return 0, false
	end
	local amount = math.clamp(required - pool, 0, donationIron)
	return amount, amount > 0 and pool + amount >= required
end

-- the Camp Level needed to reach `tier`; a tier past the table is never locked
function StructureRules.requiredCampLevel(requiredByTier: { number }, tier: number): number
	return requiredByTier[math.floor(tier)] or 1
end

return StructureRules
