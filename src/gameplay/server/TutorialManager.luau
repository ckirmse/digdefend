--!strict

-- The first-run walkthrough's one piece of server state (M76, 2026-11-09):
-- whether a player has finished it, a flag on the save
-- (PlayerSaveSchema.hasFinishedTutorial) replicated as the
-- HasFinishedTutorial CurrentPlayer attribute. Everything the tutorial
-- shows and every step it waits on is judged by ClientTutorialManager
-- from state the client already has (the backpack, the balances, the
-- equipped tool, the run's day and phase, the posts), so the server
-- never scripts the lines; it only records that a part is over when
-- the client says its last line has ended (TryFinishTutorial, designer
-- 2026-11-10; the dawn after the first night marked it before, so a
-- player who left mid-walkthrough never saw the rest). Three parts are
-- kept apart (Enums.TutorialPart): the walkthrough, whose last line is
-- the morning's goodbye, and the Iron and Uranium side lessons, so a
-- walkthrough played again does not repeat a lesson already learnt.
-- The flag is saved at once, so a crash a minute later never replays it.
-- Dev tool: resetTutorial clears all three and the client starts over.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local RunCycleManager = require(script.Parent.RunCycleManager)

local TutorialManager = {}
TutorialManager.__index = TutorialManager

export type TutorialManager = typeof(setmetatable({} :: {}, TutorialManager))

TutorialManager.RESET_COMMAND = "resetTutorial"

-- the walkthrough's goodbye is said the morning after the first night,
-- so a finish claimed before that day is refused
local FINISHING_DAY = 2

local NO_ARGS_SHAPE = {}
local TRY_FINISH_TUTORIAL_SHAPE = {
	part = { type = "enum", name = "TutorialPart" },
}

function TutorialManager:setFinished(player: Player, part: number, isFinished: boolean): boolean
	local playerData = GameController:getPlayerData(player)
	if not playerData or playerData:getHasFinishedTutorialPart(part) == isFinished then
		return false
	end
	playerData:setHasFinishedTutorialPart(part, isFinished)
	print(`[TutorialManager] {player.Name} tutorial part {Enums.getName(Enums.TutorialPart, part)} {if isFinished then "finished" else "reset"}`)
	return true
end

function TutorialManager:saveAndReplicate(player: Player)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	playerData:saveNow()
	SplendidReplicationManager:replicateTutorial(player)
end

function TutorialManager:handleTryFinishTutorial(player: Player, payload: { [string]: any })
	local part: number = payload.part
	if part == Enums.TutorialPart.SUPPLY_CRATE then
		-- the lobby lesson is the server's to finish (GachaManager, at the
		-- first crate paid for), never a claim from a client
		return
	end
	if part == Enums.TutorialPart.MAIN and RunCycleManager:getDay() < FINISHING_DAY then
		warn(`TutorialManager: {player.Name} claimed the walkthrough's end on day {RunCycleManager:getDay()}`)
		return
	end
	if self:setFinished(player, part, true) then
		self:saveAndReplicate(player)
	end
end

function TutorialManager:getNetHandlers(): { [string]: any }
	return {
		[NetEventNames.TRY_FINISH_TUTORIAL] = {
			shape = TRY_FINISH_TUTORIAL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleTryFinishTutorial(player, payload)
			end,
		},
	}
end

function TutorialManager:init()
	GameController:registerPlaceManager(self)
	DevTools:registerPlaceCommand(
		TutorialManager.RESET_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("TutorialManager: resetTutorial with invalid args:", err)
				return
			end
			local hasChanged = false
			for _, part in Enums.getAllValues(Enums.TutorialPart) do
				hasChanged = self:setFinished(player, part, false) or hasChanged
			end
			if hasChanged then
				self:saveAndReplicate(player)
			end
			PlayerFeedbackManager:give(player, "Tutorial reset: it starts over at the next day card")
		end
	)
end

function TutorialManager.new(): TutorialManager
	local self = setmetatable({}, TutorialManager) :: TutorialManager
	return self
end

return TutorialManager.new()
