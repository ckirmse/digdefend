--!strict

-- Gameplay dev tool: regenerate the mine in a live session, with an optional
-- seed, so a designer can edit the mine file, sync, regenerate, and walk in
-- without restarting the run (GDD "Designer tooling").
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local MineManager = require(script.Parent.MineManager)
local RunManager = require(script.Parent.RunManager)

local MineDevTools = {}
MineDevTools.__index = MineDevTools

export type MineDevTools = typeof(setmetatable({} :: {}, MineDevTools))

MineDevTools.REGENERATE_MINE_COMMAND = "regenerateMine"

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
end

function MineDevTools.new(): MineDevTools
	local self = setmetatable({}, MineDevTools) :: MineDevTools
	return self
end

return MineDevTools.new()
