--!strict

-- Pure rules for the run's stats in the Results Menu (GDD "Results
-- Menu"), M32: where a player's number stands among the crew's, and how
-- that place is written.
local RunStatsRules = {}

-- a player's place in the crew for one stat: 1 for the highest, and equal
-- numbers share a place (two players tied for the most are both 1st, and
-- the next is 3rd)
function RunStatsRules.rank(ownValue: number, allValues: { number }): number
	local rank = 1
	for _, value in allValues do
		if value > ownValue then
			rank += 1
		end
	end
	return rank
end

-- "1st", "2nd", "3rd", "4th", ... "11th", "21st"
function RunStatsRules.ordinal(place: number): string
	local whole = math.max(1, math.floor(place))
	local lastTwo = whole % 100
	local last = whole % 10
	local suffix = "th"
	if lastTwo < 11 or lastTwo > 13 then
		if last == 1 then
			suffix = "st"
		elseif last == 2 then
			suffix = "nd"
		elseif last == 3 then
			suffix = "rd"
		end
	end
	return `{whole}{suffix}`
end

return RunStatsRules
