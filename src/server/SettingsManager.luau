--!strict

-- The account's small preferences (2026-11-09): so far one, whether the
-- controls panel is collapsed to its tab. PlayerData is the record of
-- truth; this manager is the one writer, takes the client's toggle, and
-- publishes the state as a CurrentPlayer attribute at Ready and on every
-- change, so the panel opens the way the player left it on any device.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlayerData = require(script.Parent.PlayerData)

local SettingsManager = {}
SettingsManager.__index = SettingsManager

export type SettingsManager = typeof(setmetatable({} :: {}, SettingsManager))

local gameController: any -- prevent circular reference by not initializing here
local splendidReplicationManager: any

local SET_CONTROLS_PANEL_HIDDEN_SHAPE = {
	isHidden = "boolean",
}

function SettingsManager:getNetHandlers()
	return {
		[NetEventNames.TRY_SET_CONTROLS_PANEL_HIDDEN] = {
			shape = SET_CONTROLS_PANEL_HIDDEN_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:setControlsPanelHidden(player, payload.isHidden == true)
			end,
		},
	}
end

function SettingsManager:getPlayerData(player: Player): PlayerData.PlayerData?
	return gameController:getPlayerData(player)
end

function SettingsManager:replicate(player: Player)
	local playerData = self:getPlayerData(player)
	if not playerData then
		return
	end
	splendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.CONTROLS_PANEL_HIDDEN, playerData:getIsControlsPanelHidden())
end

function SettingsManager:setControlsPanelHidden(player: Player, isHidden: boolean)
	local playerData = self:getPlayerData(player)
	if not playerData then
		return
	end
	playerData:setIsControlsPanelHidden(isHidden)
	self:replicate(player)
end

-- ready-sequence entry; a dev-tool reset replays it over the defaults
function SettingsManager:onPlayerReady(player: Player)
	self:replicate(player)
end

function SettingsManager:init(gameControllerIn: any, splendidReplicationManagerIn: any)
	gameController = gameControllerIn
	splendidReplicationManager = splendidReplicationManagerIn
	gameController:registerPlaceManager(self)
end

function SettingsManager.new(): SettingsManager
	local self = setmetatable({}, SettingsManager) :: SettingsManager
	return self
end

return SettingsManager.new()
