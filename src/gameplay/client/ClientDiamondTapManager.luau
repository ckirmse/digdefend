--!strict

-- Diamonds earned in a run on this client (GDD "Earning Diamonds"), M32: the
-- server pays (DiamondTapManager) and the balance arrives as the Diamonds
-- attribute; this only shows the line that says what was earned and why,
-- "Day 2 Milestone Reached: +5 [diamond]", the amount ending in the icon
-- (a resource is its icon, never a word).
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientDiamondTapManager = {}
ClientDiamondTapManager.__index = ClientDiamondTapManager

export type ClientDiamondTapManager = typeof(setmetatable({} :: {}, ClientDiamondTapManager))

local NOTIFY_DIAMONDS_EARNED_SHAPE = {
	amount = "positiveInteger",
	reason = "string",
}

local EARNED_FORMAT = "%s: +%d"
local DISPLAY_SEC = 5

function ClientDiamondTapManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_DIAMONDS_EARNED,
		function(payload: any)
			local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_DIAMONDS_EARNED_SHAPE)
			if not isValid then
				warn("ClientDiamondTapManager: malformed NotifyDiamondsEarned:", errorMessage)
				return
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.STORE_PURCHASE)
			ClientPlayerFeedbackManager:giveLocal(string.format(EARNED_FORMAT, payload.reason, payload.amount), DISPLAY_SEC, Icons.UI.DIAMONDS)
		end
	)
end

function ClientDiamondTapManager.new(): ClientDiamondTapManager
	local self = setmetatable({}, ClientDiamondTapManager) :: ClientDiamondTapManager
	return self
end

return ClientDiamondTapManager.new()
