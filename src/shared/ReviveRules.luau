--!strict

-- Pure rules for death and the three revives (GDD "Health and Revives"),
-- M32: what a hit does to a player's health, when the crew is wiped, what
-- a dead player is offered, and what a paid revive turns into. ReviveManager
-- runs the flow with these.
local Enums = require(script.Parent.Enums)

local ReviveRules = {}

-- what a purchase (or a saved credit) becomes: the revive happens, or it
-- cannot apply and is kept as a credit, never refused
ReviveRules.OUTCOME_APPLY = "apply"
ReviveRules.OUTCOME_CREDIT = "credit"

export type PurchaseContext = {
	isRunOn: boolean,
	isBuyerDead: boolean,
	-- a Friend Revive's target: still in the game and still dead
	isTargetDead: boolean,
	isCrewWiped: boolean,
	isTeamReviveUsed: boolean,
	-- one player in the run: there is no crew to revive
	isSolo: boolean,
}

-- health after a hit and whether it killed; a player who cannot be hurt
-- right now (just revived) keeps what they had
function ReviveRules.applyDamage(health: number, amount: number, isInvulnerable: boolean): (number, boolean)
	if isInvulnerable or amount <= 0 then
		return health, false
	end
	local left = math.max(0, health - amount)
	return left, left <= 0
end

-- every player in the run is dead; an empty server is not a wipe
function ReviveRules.isCrewWiped(playerCount: number, deadCount: number): boolean
	return playerCount > 0 and deadCount >= playerCount
end

-- the Team Revive is offered to a wiped crew of two or more once per run;
-- otherwise a dead player is offered their own Revive until its deadline.
-- A solo player is only ever offered their own Revive (decided
-- 2026-10-05): it brings them back where the run stands, with no day
-- started over, as often as they buy it
function ReviveRules.offerFor(isDead: boolean, isRunOn: boolean, isCrewWiped: boolean, isTeamReviveUsed: boolean, isSolo: boolean, selfDeadline: number, now: number): number
	if not isDead or not isRunOn then
		return Enums.ReviveOffer.NONE
	end
	if isCrewWiped and not isTeamReviveUsed and not isSolo then
		return Enums.ReviveOffer.TEAM
	end
	if now < selfDeadline then
		return Enums.ReviveOffer.SELF
	end
	return Enums.ReviveOffer.NONE
end

-- when the offer above runs out: the wipe's deadline for a Team Revive,
-- the player's own for a Revive, 0 for none
function ReviveRules.offerEndTime(offer: number, selfDeadline: number, wipeDeadline: number): number
	if offer == Enums.ReviveOffer.TEAM then
		return wipeDeadline
	elseif offer == Enums.ReviveOffer.SELF then
		return selfDeadline
	end
	return 0
end

-- by the time the server hears of a purchase the Robux is spent, so a
-- revive that can no longer happen becomes a credit
function ReviveRules.resolvePurchase(reviveKind: number, context: PurchaseContext): string
	if not context.isRunOn then
		return ReviveRules.OUTCOME_CREDIT
	end
	local canApply = false
	if reviveKind == Enums.ReviveKind.SELF then
		canApply = context.isBuyerDead
	elseif reviveKind == Enums.ReviveKind.FRIEND then
		canApply = context.isTargetDead
	elseif reviveKind == Enums.ReviveKind.TEAM then
		canApply = context.isCrewWiped and not context.isTeamReviveUsed and not context.isSolo
	end
	return if canApply then ReviveRules.OUTCOME_APPLY else ReviveRules.OUTCOME_CREDIT
end

-- the first free plot of the Cemetery, or nil when every plot is taken
function ReviveRules.firstFreePlot(plotCount: number, isTaken: { [number]: boolean }): number?
	for index = 1, plotCount do
		if not isTaken[index] then
			return index
		end
	end
	return nil
end

-- a wiped crew that nobody revived by the deadline has lost the run
function ReviveRules.isWipeLost(wipeDeadline: number, now: number): boolean
	return wipeDeadline > 0 and now >= wipeDeadline
end

return ReviveRules
