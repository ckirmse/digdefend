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

-- the swing chunk for a tier; a tier past the tables repairs like the
-- last listed one
function StructureRules.repairChunkForTier(chunkHpByTier: { number }, chunkIronByTier: { number }, tier: number): (number, number)
	local index = math.clamp(math.floor(tier), 1, math.max(#chunkHpByTier, 1))
	return chunkHpByTier[index] or 0, chunkIronByTier[math.min(index, #chunkIronByTier)] or 0
end

-- what one press at the Walls Table moves at this tier: the base donation
-- doubled per tier above the first, so a level 2 camp contributes 20 and a
-- level 3 camp 40 (designer, 2026-10-08: the same number of presses buys
-- each level as the prices climb)
function StructureRules.donationForTier(baseDonationIron: number, tier: number): number
	return baseDonationIron * 2 ^ math.max(math.floor(tier) - 1, 0)
end

-- a crew's price for the next tier: the solo price times the crew's
-- multiplier, rounded up to whole donations so the pool fills exactly
function StructureRules.scaledUpgradeCost(cost: number?, multiplier: number, donationIron: number): number?
	if cost == nil then
		return nil
	end
	local unit = math.max(donationIron, 1)
	return math.ceil(cost * math.max(multiplier, 1) / unit) * unit
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

-- the number a map gives a numbered structure ("Wall3" is wall 3); nil for
-- an id without a trailing number (the Gate, the Refinery)
function StructureRules.numberFromId(id: string): number?
	local digits = string.match(id, "(%d+)$")
	return if digits then tonumber(digits) else nil
end

-- a map's "Wall0" models are decoration that joins the fortification line
-- to the terrain (decided 2026-09-30): filled from the wall template so
-- they match the tier, but with no HP, no repair, and nothing for the
-- monsters to attack. A map may have any number of them
StructureRules.DECORATIVE_WALL_NUMBER = 0

function StructureRules.isDecorativeWall(id: string): boolean
	return StructureRules.numberFromId(id) == StructureRules.DECORATIVE_WALL_NUMBER
end

-- how far a point is from the nearest face of an oriented box; 0 inside it
function StructureRules.distanceToBox(position: Vector3, boxCFrame: CFrame, boxSize: Vector3): number
	local localPosition = boxCFrame:PointToObjectSpace(position)
	local half = boxSize / 2
	local clamped = Vector3.new(
		math.clamp(localPosition.X, -half.X, half.X),
		math.clamp(localPosition.Y, -half.Y, half.Y),
		math.clamp(localPosition.Z, -half.Z, half.Z)
	)
	return (localPosition - clamped).Magnitude
end

-- how far along a ray it first meets an oriented box; nil when it misses
-- or the box lies beyond maxDistance. A ray starting inside the box meets
-- it at 0. This is how a player aims the Hammer at a wall that is rubble:
-- at the space the wall stood in, not at the pile on the ground
function StructureRules.rayBoxDistance(origin: Vector3, direction: Vector3, boxCFrame: CFrame, boxSize: Vector3, maxDistance: number): number?
	local localOrigin = boxCFrame:PointToObjectSpace(origin)
	local localDirection = boxCFrame:VectorToObjectSpace(direction)
	local half = boxSize / 2
	local nearest = 0
	local farthest = maxDistance
	for _, axis in { "X", "Y", "Z" } do
		local start = (localOrigin :: any)[axis]
		local step = (localDirection :: any)[axis]
		local limit = (half :: any)[axis]
		if math.abs(step) < 1e-6 then
			-- running alongside this pair of faces: inside them or never
			if math.abs(start) > limit then
				return nil
			end
		else
			local first = (-limit - start) / step
			local second = (limit - start) / step
			if first > second then
				first, second = second, first
			end
			nearest = math.max(nearest, first)
			farthest = math.min(farthest, second)
			if nearest > farthest then
				return nil
			end
		end
	end
	return nearest
end

return StructureRules
