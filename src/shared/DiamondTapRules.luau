--!strict

-- Pure rules for Diamonds earned in a run (GDD "Earning Diamonds"), M32: which
-- night milestones a dawn pays. DiamondTapManager pays with these.
local DiamondTapRules = {}

-- the Diamonds owed at a dawn for every milestone night passed since the last
-- one paid, and the night to remember as paid. A day that starts over (the
-- Team Revive) or a night with no milestone pays nothing
function DiamondTapRules.unpaidMilestoneDiamonds(diamondsByNight: { [number]: number }, lastPaidNight: number, nightsSurvived: number): (number, number)
	if nightsSurvived <= lastPaidNight then
		return 0, lastPaidNight
	end
	local total = 0
	for night, diamonds in diamondsByNight do
		if night > lastPaidNight and night <= nightsSurvived then
			total += diamonds
		end
	end
	return total, nightsSurvived
end

-- nights survived is the dawns reached: the run's day less one
function DiamondTapRules.nightsSurvived(day: number): number
	return math.max(0, math.floor(day) - 1)
end

return DiamondTapRules
