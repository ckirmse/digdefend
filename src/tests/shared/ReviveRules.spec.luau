-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local ReviveRules = require(game:GetService("ReplicatedStorage").Shared.ReviveRules)

local function context(overrides: { [string]: boolean }?): ReviveRules.PurchaseContext
	local built = {
		isRunOn = true,
		isBuyerDead = false,
		isTargetDead = false,
		isCrewWiped = false,
		isTeamReviveUsed = false,
		isSolo = false,
	}
	for key, value in overrides or {} do
		(built :: any)[key] = value
	end
	return built
end

describe(
	"ReviveRules",
	function()
		it(
			"takes a hit off health and reports the kill at zero",
			function()
				local health, isKilled = ReviveRules.applyDamage(100, 30, false)
				expect(health).toBe(70)
				expect(isKilled).toBe(false)
				health, isKilled = ReviveRules.applyDamage(20, 20, false)
				expect(health).toBe(0)
				expect(isKilled).toBe(true)
				health, isKilled = ReviveRules.applyDamage(5, 50, false)
				expect(health).toBe(0)
				expect(isKilled).toBe(true)
			end
		)
		it(
			"leaves a just-revived player and a zero hit alone",
			function()
				local health, isKilled = ReviveRules.applyDamage(40, 100, true)
				expect(health).toBe(40)
				expect(isKilled).toBe(false)
				health, isKilled = ReviveRules.applyDamage(40, 0, false)
				expect(health).toBe(40)
				expect(isKilled).toBe(false)
			end
		)
		it(
			"calls the crew wiped only when everyone in the run is dead",
			function()
				expect(ReviveRules.isCrewWiped(3, 2)).toBe(false)
				expect(ReviveRules.isCrewWiped(3, 3)).toBe(true)
				expect(ReviveRules.isCrewWiped(1, 1)).toBe(true)
				expect(ReviveRules.isCrewWiped(0, 0)).toBe(false)
			end
		)
		it(
			"offers the Team Revive to a wiped crew once, and a Revive until its deadline",
			function()
				expect(ReviveRules.offerFor(true, true, true, false, false, 100, 50)).toBe(Enums.ReviveOffer.TEAM)
				-- the Team Revive is spent: each player gets their own back
				expect(ReviveRules.offerFor(true, true, true, true, false, 100, 50)).toBe(Enums.ReviveOffer.SELF)
				expect(ReviveRules.offerFor(true, true, false, false, false, 100, 50)).toBe(Enums.ReviveOffer.SELF)
				expect(ReviveRules.offerFor(true, true, false, false, false, 100, 100)).toBe(Enums.ReviveOffer.NONE)
			end
		)
		it(
			"only ever offers a solo player their own Revive",
			function()
				expect(ReviveRules.offerFor(true, true, true, false, true, 100, 50)).toBe(Enums.ReviveOffer.SELF)
				expect(ReviveRules.offerFor(true, true, true, false, true, 100, 100)).toBe(Enums.ReviveOffer.NONE)
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.TEAM, context({ isCrewWiped = true, isSolo = true }))).toBe(ReviveRules.OUTCOME_CREDIT)
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.SELF, context({ isBuyerDead = true, isCrewWiped = true, isSolo = true }))).toBe(ReviveRules.OUTCOME_APPLY)
			end
		)
		it(
			"offers nothing to the living or once the run is over",
			function()
				expect(ReviveRules.offerFor(false, true, false, false, false, 100, 50)).toBe(Enums.ReviveOffer.NONE)
				expect(ReviveRules.offerFor(true, false, true, false, false, 100, 50)).toBe(Enums.ReviveOffer.NONE)
			end
		)
		it(
			"ends each offer at its own deadline",
			function()
				expect(ReviveRules.offerEndTime(Enums.ReviveOffer.TEAM, 100, 160)).toBe(160)
				expect(ReviveRules.offerEndTime(Enums.ReviveOffer.SELF, 100, 160)).toBe(100)
				expect(ReviveRules.offerEndTime(Enums.ReviveOffer.NONE, 100, 160)).toBe(0)
			end
		)
		it(
			"applies a Revive for a dead buyer and keeps it as a credit otherwise",
			function()
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.SELF, context({ isBuyerDead = true }))).toBe(ReviveRules.OUTCOME_APPLY)
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.SELF, context())).toBe(ReviveRules.OUTCOME_CREDIT)
			end
		)
		it(
			"applies a Friend Revive only while its target is in the game and dead",
			function()
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.FRIEND, context({ isTargetDead = true }))).toBe(ReviveRules.OUTCOME_APPLY)
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.FRIEND, context({ isBuyerDead = true }))).toBe(ReviveRules.OUTCOME_CREDIT)
			end
		)
		it(
			"applies a Team Revive only to a wiped crew that has not used it",
			function()
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.TEAM, context({ isCrewWiped = true }))).toBe(ReviveRules.OUTCOME_APPLY)
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.TEAM, context({ isCrewWiped = true, isTeamReviveUsed = true }))).toBe(ReviveRules.OUTCOME_CREDIT)
				expect(ReviveRules.resolvePurchase(Enums.ReviveKind.TEAM, context())).toBe(ReviveRules.OUTCOME_CREDIT)
			end
		)
		it(
			"turns every purchase into a credit once the run is over",
			function()
				local over = context({ isRunOn = false, isBuyerDead = true, isTargetDead = true, isCrewWiped = true })
				for _, reviveKind in Enums.getAllValues(Enums.ReviveKind) do
					expect(ReviveRules.resolvePurchase(reviveKind, over)).toBe(ReviveRules.OUTCOME_CREDIT)
				end
			end
		)
		it(
			"hands out the first free Cemetery plot",
			function()
				expect(ReviveRules.firstFreePlot(6, {})).toBe(1)
				expect(ReviveRules.firstFreePlot(6, { [1] = true, [2] = true, [4] = true })).toBe(3)
				expect(ReviveRules.firstFreePlot(2, { [1] = true, [2] = true })).toBe(nil)
			end
		)
		it(
			"loses a wiped run only once its deadline has passed",
			function()
				expect(ReviveRules.isWipeLost(0, 500)).toBe(false)
				expect(ReviveRules.isWipeLost(160, 159)).toBe(false)
				expect(ReviveRules.isWipeLost(160, 160)).toBe(true)
			end
		)
	end
)
