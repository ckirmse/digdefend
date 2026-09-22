--!strict

-- Pure rules for the status effects a target can carry (GDD "Trap Types":
-- status effects), M27. A slow takes a share of the target's speed for a
-- while and the strongest active slow wins, so slows never stack; a stun
-- is a slow of the whole speed; a burn is damage per second for a while,
-- and a fresh burn restarts the clock at the stronger rate. The effects
-- live on the target (DamageableManager), so a Tower, a Trap, or later a
-- weapon applies them the same way, and how far a walking target moves
-- this step is decided here too. Time is passed in so this stays testable.
local StatusRules = {}

export type Slow = {
	-- 0 is no slow, 1 is a full stop
	share: number,
	endTime: number,
}

export type Burn = {
	damagePerSec: number,
	endTime: number,
}

export type Effects = {
	slows: { Slow },
	burn: Burn?,
}

function StatusRules.newEffects(): Effects
	return {
		slows = {},
		burn = nil,
	}
end

function StatusRules.applySlow(effects: Effects, share: number, durationSec: number, now: number)
	if share <= 0 or durationSec <= 0 then
		return
	end
	table.insert(effects.slows, {
		share = math.clamp(share, 0, 1),
		endTime = now + durationSec,
	})
end

function StatusRules.applyStun(effects: Effects, durationSec: number, now: number)
	StatusRules.applySlow(effects, 1, durationSec, now)
end

function StatusRules.applyBurn(effects: Effects, damagePerSec: number, durationSec: number, now: number)
	if damagePerSec <= 0 or durationSec <= 0 then
		return
	end
	local burn = effects.burn
	local endTime = now + durationSec
	if burn and burn.endTime > now then
		burn.damagePerSec = math.max(burn.damagePerSec, damagePerSec)
		burn.endTime = math.max(burn.endTime, endTime)
		return
	end
	effects.burn = {
		damagePerSec = damagePerSec,
		endTime = endTime,
	}
end

-- drops everything that has run out; returns whether anything is left
function StatusRules.prune(effects: Effects, now: number): boolean
	local kept = {}
	for _, slow in effects.slows do
		if slow.endTime > now then
			table.insert(kept, slow)
		end
	end
	effects.slows = kept
	local burn = effects.burn
	if burn and burn.endTime <= now then
		effects.burn = nil
	end
	return #effects.slows > 0 or effects.burn ~= nil
end

-- 1 at full speed, 0 stunned
function StatusRules.speedMultiplier(effects: Effects, now: number): number
	local strongest = 0
	for _, slow in effects.slows do
		if slow.endTime > now then
			strongest = math.max(strongest, slow.share)
		end
	end
	return 1 - strongest
end

function StatusRules.isStunned(effects: Effects, now: number): boolean
	return StatusRules.speedMultiplier(effects, now) <= 0
end

function StatusRules.isBurning(effects: Effects, now: number): boolean
	local burn = effects.burn
	return burn ~= nil and burn.endTime > now
end

-- the burn damage owed for the stretch since the last tick: the rate over
-- however much of that stretch the burn was alive
function StatusRules.burnDamage(effects: Effects, lastTickTime: number, now: number): number
	local burn = effects.burn
	if not burn or now <= lastTickTime then
		return 0
	end
	local alive = math.min(now, burn.endTime) - lastTickTime
	if alive <= 0 then
		return 0
	end
	return burn.damagePerSec * alive
end

-- where a walker gets to this step, and whether it arrived
function StatusRules.moveToward(position: Vector3, destination: Vector3, speedStudsPerSec: number, speedMultiplier: number, deltaSec: number): (Vector3, boolean)
	local offset = destination - position
	local distance = offset.Magnitude
	local step = math.max(0, speedStudsPerSec * speedMultiplier * deltaSec)
	if distance <= step or distance < 1e-6 then
		return destination, true
	end
	return position + offset.Unit * step, false
end

return StatusRules
