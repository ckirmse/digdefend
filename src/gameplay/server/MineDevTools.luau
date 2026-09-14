--!strict

-- Gameplay mining dev tools: regenerate the mine in a live session with an
-- optional seed, so a designer can edit the mine file, sync, regenerate, and
-- walk in without restarting the run (GDD "Designer tooling"); and fill or
-- empty the backpack so the full state and overflow drops can be tested
-- without mining fifty ore; and reset the refinery balances and camp
-- progress so a payout can be watched from zero.
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local BackpackManager = require(script.Parent.BackpackManager)
local MineManager = require(script.Parent.MineManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RunManager = require(script.Parent.RunManager)

local MineDevTools = {}
MineDevTools.__index = MineDevTools

export type MineDevTools = typeof(setmetatable({} :: {}, MineDevTools))

MineDevTools.REGENERATE_MINE_COMMAND = "regenerateMine"
MineDevTools.FILL_BACKPACK_COMMAND = "fillBackpack"
MineDevTools.EMPTY_BACKPACK_COMMAND = "emptyBackpack"
MineDevTools.RESET_REFINERY_COMMAND = "resetRefinery"

local REGENERATE_MINE_ARGS_SHAPE = {
	seed = { type = "positiveInteger", optional = true },
}

function MineDevTools:regenerateMine(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, REGENERATE_MINE_ARGS_SHAPE)
	if not isValid then
		warn("MineDevTools: regenerateMine with invalid args:", err)
		return
	end
	local map = RunManager:getMap()
	local difficulty = RunManager:getDifficulty()
	if not map or not difficulty then
		PlayerFeedbackManager:give(player, "No run has started yet")
		return
	end
	local isGenerated = MineManager:generate(map, difficulty, args.seed)
	if isGenerated then
		PlayerFeedbackManager:give(player, "Mine regenerated (see the Output for the report)")
	else
		PlayerFeedbackManager:give(player, "Mine generation failed (see the Output)")
	end
end

function MineDevTools:init()
	DevTools:registerPlaceCommand(
		MineDevTools.REGENERATE_MINE_COMMAND,
		function(player: Player, args: { [string]: any })
			self:regenerateMine(player, args)
		end
	)
	DevTools:registerPlaceCommand(
		MineDevTools.FILL_BACKPACK_COMMAND,
		function(player: Player, _args: { [string]: any })
			BackpackManager:fill(player)
			PlayerFeedbackManager:give(player, "Backpack filled")
		end
	)
	DevTools:registerPlaceCommand(
		MineDevTools.EMPTY_BACKPACK_COMMAND,
		function(player: Player, _args: { [string]: any })
			BackpackManager:empty(player)
			PlayerFeedbackManager:give(player, "Backpack emptied")
		end
	)
	DevTools:registerPlaceCommand(
		MineDevTools.RESET_REFINERY_COMMAND,
		function(_player: Player, _args: { [string]: any })
			RefineryManager:resetProgress()
			for _, readyPlayer in GameController:getReadyPlayers() do
				PlayerFeedbackManager:give(readyPlayer, "Refinery balances and camp progress reset")
			end
		end
	)
end

function MineDevTools.new(): MineDevTools
	local self = setmetatable({}, MineDevTools) :: MineDevTools
	return self
end

return MineDevTools.new()
