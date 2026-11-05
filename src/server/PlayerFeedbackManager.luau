--!strict

-- The one place server systems route short player-facing messages through.
-- The client shows them in the PlayerFeedback ScreenGui (M9).
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local NetManager = require(script.Parent.NetManager)

local PlayerFeedbackManager = {}
PlayerFeedbackManager.__index = PlayerFeedbackManager

export type PlayerFeedbackManager = typeof(setmetatable({} :: {}, PlayerFeedbackManager))

local DEFAULT_DISPLAY_SEC = 3

function PlayerFeedbackManager:give(player: Player, message: string, displaySec: number?)
	NetManager:notifyClient(
		player,
		NetEventNames.NOTIFY_PLAYER_FEEDBACK,
		{
			message = message,
			displaySec = displaySec or DEFAULT_DISPLAY_SEC,
		}
	)
end

-- a Diamonds purchase refused for want of Diamonds: not a line of text
-- but its own event, so the lobby client can run the whole answer (the
-- fail sound, the wallet flash, the message, and the pack prompt) from
-- the price and the balance (designer, 2026-11-04)
function PlayerFeedbackManager:giveDiamondsShort(player: Player, priceDiamonds: number, balance: number)
	NetManager:notifyClient(
		player,
		NetEventNames.NOTIFY_DIAMONDS_SHORT,
		{
			priceDiamonds = priceDiamonds,
			balance = balance,
		}
	)
end

function PlayerFeedbackManager.new(): PlayerFeedbackManager
	local self = setmetatable({}, PlayerFeedbackManager) :: PlayerFeedbackManager
	return self
end

return PlayerFeedbackManager.new()
