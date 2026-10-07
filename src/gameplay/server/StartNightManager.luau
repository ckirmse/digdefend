--!strict

-- The Start Night button (designer, 2026-10-07): in the last
-- START_NIGHT_WINDOW_SEC of a day every living player gets a button under
-- the jet pack bar, and once all of them have pressed it the rest of the
-- day is skipped and the night falls (RunCycleManager:forceNight, the same
-- short dusk blend as the dev tool), so a crew that is ready does not wait
-- out the sunset. Votes are per day and cleared at every dawn; a player who
-- leaves or dies drops out of the count, so the remaining crew can still
-- start it. What clients need is GameMetadata: the window, the count of
-- votes, and how many are needed.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local RunCycleData = require("@game/ServerScriptService/GameData/Control/RunCycle")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunPauseManager = require(script.Parent.RunPauseManager)

local StartNightManager = {}
StartNightManager.__index = StartNightManager

export type StartNightManager = typeof(setmetatable(
	{} :: {
		votedUserIds: { [number]: boolean },
	},
	StartNightManager
))

local TRY_START_NIGHT_SHAPE = {}

-- whether the day is in its last window, by server time (held by a pause)
function StartNightManager:isWindowOpen(): boolean
	if RunCycleManager:getRunState() ~= Enums.RunState.DAY or RunPauseManager:isPaused() then
		return false
	end
	local now = workspace:GetServerTimeNow()
	return RunCycleManager:getPhaseEndTime() - now <= RunCycleData.START_NIGHT_WINDOW_SEC
end

function StartNightManager:countVotes(): (number, number)
	local living = ReviveManager:getLivingPlayers()
	local votes = 0
	for _, player in living do
		if self.votedUserIds[player.UserId] then
			votes += 1
		end
	end
	return votes, #living
end

function StartNightManager:replicate()
	local votes, needed = self:countVotes()
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_START_NIGHT_VOTES, votes)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_START_NIGHT_NEEDED, needed)
end

function StartNightManager:startIfAgreed()
	if not self:isWindowOpen() then
		return
	end
	local votes, needed = self:countVotes()
	if needed > 0 and votes >= needed then
		print(`[StartNightManager] the crew started the night early ({votes} of {needed})`)
		RunCycleManager:forceNight(true)
	end
end

function StartNightManager:handleTryStartNight(player: Player)
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return
	end
	if not self:isWindowOpen() or self.votedUserIds[player.UserId] then
		return
	end
	self.votedUserIds[player.UserId] = true
	self:replicate()
	self:startIfAgreed()
end

function StartNightManager:clearVotes()
	self.votedUserIds = {}
	self:replicate()
end

function StartNightManager:onPlayerRemoved(player: Player)
	self.votedUserIds[player.UserId] = nil
	self:replicate()
	self:startIfAgreed()
end

function StartNightManager:getNetHandlers()
	return {
		[NetEventNames.TRY_START_NIGHT] = {
			shape = TRY_START_NIGHT_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:handleTryStartNight(player)
			end,
		},
	}
end

function StartNightManager:init()
	GameController:registerPlaceManager(self)
	SplendidReplicationManager:setGameMetadata(Attributes.RUN_START_NIGHT_WINDOW_SEC, RunCycleData.START_NIGHT_WINDOW_SEC)
	self:replicate()
	-- a new day starts the vote over; the night clears it so a stale count
	-- never shows when the next window opens
	RunCycleManager:subscribeNightChanged(
		function(_isNight: boolean)
			self:clearVotes()
		end
	)
end

function StartNightManager.new(): StartNightManager
	local self = setmetatable({}, StartNightManager) :: StartNightManager
	self.votedUserIds = {}
	return self
end

return StartNightManager.new()
