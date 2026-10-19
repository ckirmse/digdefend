--!strict

-- Gameplay dev tools for the Auto Turret (M66): hurt the admin's standing
-- turret by an amount (the loss path and the greyed button, without
-- waiting on a wave to reach the camp) and bring a lost turret back before
-- dawn so the next placement is tried at once.
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local AutoTurretManager = require(script.Parent.AutoTurretManager)

local AutoTurretDevTools = {}
AutoTurretDevTools.__index = AutoTurretDevTools

export type AutoTurretDevTools = typeof(setmetatable({} :: {}, AutoTurretDevTools))

AutoTurretDevTools.DAMAGE_AUTO_TURRET_COMMAND = "damageAutoTurret"
AutoTurretDevTools.RESTORE_AUTO_TURRET_COMMAND = "restoreAutoTurret"

local DAMAGE_AUTO_TURRET_ARGS_SHAPE = {
	amount = "positiveInteger",
}
local NO_ARGS_SHAPE = {}

function AutoTurretDevTools:init()
	DevTools:registerPlaceCommand(
		AutoTurretDevTools.DAMAGE_AUTO_TURRET_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, DAMAGE_AUTO_TURRET_ARGS_SHAPE)
			if not isValid then
				warn("AutoTurretDevTools: damageAutoTurret with invalid args:", err)
				return
			end
			local turret = AutoTurretManager:getPlayerTurret(player)
			if not turret then
				PlayerFeedbackManager:give(player, "No Auto Turret standing")
				return
			end
			AutoTurretManager:damage(turret.id, args.amount, nil)
		end
	)
	DevTools:registerPlaceCommand(
		AutoTurretDevTools.RESTORE_AUTO_TURRET_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("AutoTurretDevTools: restoreAutoTurret with invalid args:", err)
				return
			end
			AutoTurretManager:restore(player)
			PlayerFeedbackManager:give(player, "Auto Turret restored")
		end
	)
end

function AutoTurretDevTools.new(): AutoTurretDevTools
	local self = setmetatable({}, AutoTurretDevTools) :: AutoTurretDevTools
	return self
end

return AutoTurretDevTools.new()
