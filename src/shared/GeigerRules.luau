--!strict

-- Pure rules for the Geiger Counter (GDD "Geiger Counter"): how far a
-- player is from a uranium rock, how far a level detects, and how many of
-- the dial's rings that lights. Tuning is passed in from GameData so this
-- stays unit testable.
local HttpService = game:GetService("HttpService")

local GeigerRules = {}

-- the distance from a point to the nearest face of a cube-shaped block; 0
-- inside it. Measured to the face rather than the centre so "5 studs away"
-- means what the player sees
function GeigerRules.distanceToBlock(position: Vector3, blockCenter: Vector3, blockSizeStuds: number): number
	local half = blockSizeStuds / 2
	local outsideX = math.max(math.abs(position.X - blockCenter.X) - half, 0)
	local outsideY = math.max(math.abs(position.Y - blockCenter.Y) - half, 0)
	local outsideZ = math.max(math.abs(position.Z - blockCenter.Z) - half, 0)
	return math.sqrt(outsideX * outsideX + outsideY * outsideY + outsideZ * outsideZ)
end

-- how far a level detects; a level outside the list detects nothing below
-- it and the top range above it
function GeigerRules.rangeForLevel(rangeStudsByLevel: { number }, level: number): number
	if #rangeStudsByLevel == 0 then
		return 0
	end
	return rangeStudsByLevel[math.clamp(math.floor(level), 1, #rangeStudsByLevel)]
end

-- how many rings are lit, counted from the inner one: each ring lights
-- once the distance is within its share of the range. No uranium found
-- (nil), or no range, lights none
function GeigerRules.litRingCount(distanceStuds: number?, rangeStuds: number, ringRangeShares: { number }): number
	if not distanceStuds or rangeStuds <= 0 then
		return 0
	end
	local count = 0
	for _, share in ringRangeShares do
		if distanceStuds <= rangeStuds * share then
			count += 1
		end
	end
	return count
end

function GeigerRules.encodeRingShares(ringRangeShares: { number }): string
	return HttpService:JSONEncode(ringRangeShares)
end

-- nil for anything that is not a list of numbers
function GeigerRules.decodeRingShares(encoded: any): { number }?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(decoded) ~= "table" then
		return nil
	end
	local shares: { number } = {}
	for _, share in decoded :: { any } do
		if typeof(share) ~= "number" then
			return nil
		end
		table.insert(shares, share)
	end
	return shares
end

return GeigerRules
