--!strict

-- Gameplay mining dev tools: regenerate the mine in a live session with an
-- optional seed, so a designer can edit the mine file, sync, regenerate, and
-- walk in without restarting the run (GDD "Designer tooling"); and fill or
-- empty the backpack so the full state and overflow drops can be tested
-- without mining fifty ore; and reset the refinery balances and camp
-- progress so a payout can be watched from zero. For the store (M21): grant
-- Gold, jump the camp level, and hand out consumables.
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local BackpackManager = require(script.Parent.BackpackManager)
local MineManager = require(script.Parent.MineManager)
local ToolManager = require(script.Parent.ToolManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RunManager = require(script.Parent.RunManager)

local MineDevTools = {}
MineDevTools.__index = MineDevTools

export type MineDevTools = typeof(setmetatable({} :: {}, MineDevTools))

MineDevTools.REGENERATE_MINE_COMMAND = "regenerateMine"
MineDevTools.FILL_BACKPACK_COMMAND = "fillBackpack"
MineDevTools.EMPTY_BACKPACK_COMMAND = "emptyBackpack"
MineDevTools.RESET_REFINERY_COMMAND = "resetRefinery"
MineDevTools.ADD_GOLD_COMMAND = "addGold"
-- diamonds go through the real payout path, so a level-up fires as in play
MineDevTools.ADD_DIAMONDS_COMMAND = "addDiamonds"
MineDevTools.SET_CAMP_LEVEL_COMMAND = "setCampLevel"
MineDevTools.GIVE_CONSUMABLES_COMMAND = "giveConsumables"

local ADD_DIAMONDS_ARGS_SHAPE = {
	amount = "positiveInteger",
}

local ADD_GOLD_ARGS_SHAPE = {
	amount = "integer",
}
local SET_CAMP_LEVEL_ARGS_SHAPE = {
	level = "positiveInteger",
}
local GIVE_CONSUMABLES_TORCHES = 8
local GIVE_CONSUMABLES_DYNAMITE = 3

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
		MineDevTools.ADD_GOLD_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, ADD_GOLD_ARGS_SHAPE)
			if not isValid then
				warn("MineDevTools: addGold with invalid args:", err)
				return
			end
			RefineryManager:addGoldBars(player, args.amount)
			PlayerFeedbackManager:give(player, `Gold is now {RefineryManager:getGoldBars(player)}`)
		end
	)
	DevTools:registerPlaceCommand(
		MineDevTools.ADD_DIAMONDS_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, ADD_DIAMONDS_ARGS_SHAPE)
			if not isValid then
				warn("MineDevTools: addDiamonds with invalid args:", err)
				return
			end
			RefineryManager:credit(player, { [Enums.RefinedResource.DIAMOND] = args.amount })
			PlayerFeedbackManager:give(player, `Added {args.amount} diamonds; camp level {RefineryManager:getCampLevel()}`)
		end
	)
	DevTools:registerPlaceCommand(
		MineDevTools.SET_CAMP_LEVEL_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, SET_CAMP_LEVEL_ARGS_SHAPE)
			if not isValid then
				warn("MineDevTools: setCampLevel with invalid args:", err)
				return
			end
			RefineryManager:setCampLevel(args.level)
			for _, readyPlayer in GameController:getReadyPlayers() do
				PlayerFeedbackManager:give(readyPlayer, `Camp level set to {RefineryManager:getCampLevel()}`)
			end
		end
	)
	DevTools:registerPlaceCommand(
		MineDevTools.GIVE_CONSUMABLES_COMMAND,
		function(player: Player, _args: { [string]: any })
			ToolManager:addConsumable(player, Enums.ToolKind.TORCH, GIVE_CONSUMABLES_TORCHES)
			ToolManager:addConsumable(player, Enums.ToolKind.DYNAMITE, GIVE_CONSUMABLES_DYNAMITE)
			PlayerFeedbackManager:give(player, `Given {GIVE_CONSUMABLES_TORCHES} torches and {GIVE_CONSUMABLES_DYNAMITE} dynamite`)
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
