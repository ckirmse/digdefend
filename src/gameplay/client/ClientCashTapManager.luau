--!strict

-- Cash earned in a run on this client (GDD "Earning Cash"), M32: the
-- server pays (CashTapManager) and the balance arrives as the Cash
-- attribute; this only shows the line that says what was earned and why.
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientCashTapManager = {}
ClientCashTapManager.__index = ClientCashTapManager

export type ClientCashTapManager = typeof(setmetatable({} :: {}, ClientCashTapManager))

local NOTIFY_CASH_EARNED_SHAPE = {
	amount = "positiveInteger",
	reason = "string",
}

local EARNED_FORMAT = "%s. +%d Cash"
local DISPLAY_SEC = 5

function ClientCashTapManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_CASH_EARNED,
		function(payload: any)
			local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_CASH_EARNED_SHAPE)
			if not isValid then
				warn("ClientCashTapManager: malformed NotifyCashEarned:", errorMessage)
				return
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.STORE_PURCHASE)
			ClientPlayerFeedbackManager:giveLocal(string.format(EARNED_FORMAT, payload.reason, payload.amount), DISPLAY_SEC)
		end
	)
end

function ClientCashTapManager.new(): ClientCashTapManager
	local self = setmetatable({}, ClientCashTapManager) :: ClientCashTapManager
	return self
end

return ClientCashTapManager.new()
