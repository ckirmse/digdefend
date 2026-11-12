--!strict

-- The group reward's one rule (M78), shared so the server's claim and
-- the client's claim menu can never disagree about who may claim.
local GroupRewardRules = {}

-- the reward is there to claim for a member of the group who has not
-- had it yet
function GroupRewardRules.canClaim(isInGroup: boolean, hasClaimed: boolean): boolean
	return isInGroup and not hasClaimed
end

return GroupRewardRules
