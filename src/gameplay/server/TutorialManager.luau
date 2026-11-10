--!strict

-- The first-run walkthrough's one piece of server state (M76, 2026-11-09):
-- whether a player has finished it, a flag on the save
-- (PlayerSaveSchema.hasFinishedTutorial) replicated as the
-- HasFinishedTutorial CurrentPlayer attribute. Everything the tutorial
-- shows and every step it waits on is judged by ClientTutorialManager
-- from state the client already has (the backpack, the balances, the
-- equipped tool, the run's day and phase, the posts), so the server
-- never scripts the lines; it only decides when the walkthrough is over:
-- the dawn after a tutorial player's first night (no skip: designer,
-- 2026-11-09).
-- The flag is saved at once, so a crash a minute later never replays it.
-- Dev tool: resetTutorial clears it and the client starts over.
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

-- the dawn that ends the walkthrough: the first night is over
local FINISHING_DAY = 2

local NO_ARGS_SHAPE = {}

function TutorialManager:isFinished(player: Player): boolean
	local playerData = GameController:getPlayerData(player)
	return playerData == nil or playerData:getHasFinishedTutorial()
end

function TutorialManager:setFinished(player: Player, isFinished: boolean)
	local playerData = GameController:getPlayerData(player)
	if not playerData or playerData:getHasFinishedTutorial() == isFinished then
		return
	end
	playerData:setHasFinishedTutorial(isFinished)
	playerData:saveNow()
	SplendidReplicationManager:replicateTutorial(player)
	print(`[TutorialManager] {player.Name} tutorial {if isFinished then "finished" else "reset"}`)
end

function TutorialManager:onDayStarted(day: number)
	if day < FINISHING_DAY then
		return
	end
	for _, player in GameController:getReadyPlayers() do
		self:setFinished(player, true)
	end
end

function TutorialManager:init()
	GameController:registerPlaceManager(self)
	RunCycleManager:subscribeDayStarted(
		function(day: number, _scalingCount: number)
			self:onDayStarted(day)
		end
	)
	DevTools:registerPlaceCommand(
		TutorialManager.RESET_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, NO_ARGS_SHAPE)
			if not isValid then
				warn("TutorialManager: resetTutorial with invalid args:", err)
				return
			end
			self:setFinished(player, false)
			PlayerFeedbackManager:give(player, "Tutorial reset: it starts over at the next day card")
		end
	)
end

function TutorialManager.new(): TutorialManager
	local self = setmetatable({}, TutorialManager) :: TutorialManager
	return self
end

return TutorialManager.new()
