--!strict

-- The pure rules of the Sniper's Binoculars tag (2026-10-19): when a tag
-- is live, when the next may be made, how far a cooldown has run for the
-- tool slot's overlay, and the codec for the one public attribute a tag
-- travels as (BinocularsTag on the tagger's AllPlayers entry: the tagged
-- body's damageable id and the server time the tag ends, or "" for none).
local HttpService = game:GetService("HttpService")

local BinocularsRules = {}

export type Tag = {
	damageableId: string,
	endTime: number,
}

BinocularsRules.NO_TAG = ""

function BinocularsRules.isTagLive(endTime: number, now: number): boolean
	return now < endTime
end

-- a fresh player has never tagged: nil is always ready
function BinocularsRules.isCooldownOver(lastTagTime: number?, now: number, cooldownSec: number): boolean
	if lastTagTime == nil then
		return true
	end
	return now - lastTagTime >= cooldownSec
end

-- how much of the cooldown is left, 1 at the tag and 0 when ready (the
-- post HUD's tag hint)
function BinocularsRules.cooldownShare(cooldownEndTime: number, cooldownSec: number, now: number): number
	if cooldownSec <= 0 then
		return 0
	end
	return math.clamp((cooldownEndTime - now) / cooldownSec, 0, 1)
end

function BinocularsRules.encodeTag(tag: Tag?): string
	if not tag then
		return BinocularsRules.NO_TAG
	end
	return HttpService:JSONEncode({
		id = tag.damageableId,
		endTime = tag.endTime,
	})
end

-- nil for "" and for anything this module did not encode
function BinocularsRules.decodeTag(encoded: any): Tag?
	if typeof(encoded) ~= "string" or encoded == BinocularsRules.NO_TAG then
		return nil
	end
	local isSuccess, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.id) ~= "string" or typeof(decoded.endTime) ~= "number" then
		return nil
	end
	return {
		damageableId = decoded.id,
		endTime = decoded.endTime,
	}
end

return BinocularsRules
