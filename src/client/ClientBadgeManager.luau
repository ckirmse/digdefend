--!strict

-- Badges on the client (M69): the toast. The server earns, pays, and
-- saves a badge (BadgeManager) and says so with NotifyBadgeEarned; this
-- puts one line in the feedback box, "Badge earned: <name>", and plays
-- the reward sound. The Diamonds are not in the line: they are claimed
-- in the lobby's Badges menu (ClientBadgeMenuManager). Common, since
-- badges are earned in the lobby and in a run. Several badges landing
-- together (a rescue can earn five) are shown one after another.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientNetManager = require(script.Parent.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.ClientSoundManager)

local ClientBadgeManager = {}
ClientBadgeManager.__index = ClientBadgeManager

type Toast = {
	badgeKind: number,
}

export type ClientBadgeManager = typeof(setmetatable(
	{} :: {
		queue: { Toast },
		isShowing: boolean,
	},
	ClientBadgeManager
))

-- each toast holds the box this long before the next
local TOAST_SEC = 3
local TOAST_FORMAT = "Badge earned: %s"

function ClientBadgeManager:showNext()
	local toast = table.remove(self.queue, 1)
	if not toast then
		self.isShowing = false
		return
	end
	self.isShowing = true
	local name = Enums.getPublicName(Enums.BadgeKind, toast.badgeKind) or "Badge"
	ClientPlayerFeedbackManager:giveLocal(string.format(TOAST_FORMAT, name), TOAST_SEC)
	ClientSoundManager:playSfx(SoundNames.Sfx.BADGE_EARNED)
	task.delay(
		TOAST_SEC,
		function()
			self:showNext()
		end
	)
end

function ClientBadgeManager:onBadgeEarned(payload: { [string]: any })
	if typeof(payload.badgeKind) ~= "number" then
		return
	end
	table.insert(self.queue, { badgeKind = payload.badgeKind })
	if not self.isShowing then
		self:showNext()
	end
end

-- after ClientNetManager and the feedback box
function ClientBadgeManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_BADGE_EARNED,
		function(payload: { [string]: any })
			self:onBadgeEarned(payload)
		end
	)
end

function ClientBadgeManager.new(): ClientBadgeManager
	local self = setmetatable({}, ClientBadgeManager) :: ClientBadgeManager
	self.queue = {}
	self.isShowing = false
	return self
end

return ClientBadgeManager.new()
