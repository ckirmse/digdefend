--!strict

-- The Geiger Counter (GDD "Geiger Counter"): bought in the Mining Supplies
-- Store, then upgraded for more range. The level is run state held here
-- (level 1 = not owned, the shape every store track has) and published
-- privately with the range that level detects at, so the client never
-- needs GameData. The detecting itself is the client's: it already holds
-- the whole mine grid, and the dial is only a hint, so there is nothing
-- for the server to validate.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local GeigerRules = require("@game/ReplicatedStorage/Shared/GeigerRules")
local GeigerCounterData = require("@game/ServerScriptService/GameData/Mining/GeigerCounter")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local GeigerCounterManager = {}
GeigerCounterManager.__index = GeigerCounterManager

export type GeigerCounterManager = typeof(setmetatable(
	{} :: {
		levelByPlayer: { [Player]: number },
	},
	GeigerCounterManager
))

local STARTING_LEVEL = 1

function GeigerCounterManager:getLevel(player: Player): number
	return self.levelByPlayer[player] or STARTING_LEVEL
end

function GeigerCounterManager:replicate(player: Player)
	local level = self:getLevel(player)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.GEIGER_COUNTER_RANGE_STUDS, GeigerRules.rangeForLevel(GeigerCounterData.RANGE_STUDS_BY_LEVEL, level))
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.GEIGER_COUNTER_LEVEL, level)
end

function GeigerCounterManager:setLevel(player: Player, level: number)
	if not self.levelByPlayer[player] then
		return
	end
	self.levelByPlayer[player] = level
	self:replicate(player)
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state survives
function GeigerCounterManager:onPlayerReady(player: Player)
	if not self.levelByPlayer[player] then
		self.levelByPlayer[player] = STARTING_LEVEL
	end
	self:replicate(player)
end

function GeigerCounterManager:init()
	GameController:registerPlaceManager(self)
	SplendidReplicationManager:setGameMetadata(Attributes.GEIGER_COUNTER_RING_SHARES, GeigerRules.encodeRingShares(GeigerCounterData.RING_RANGE_SHARES))
	SplendidReplicationManager:setGameMetadata(Attributes.GEIGER_COUNTER_SCAN_INTERVAL_SEC, GeigerCounterData.SCAN_INTERVAL_SEC)
	-- not a teardown entry: a dev-tool reset must not strip the run's upgrades
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.levelByPlayer[player] = nil
		end
	)
end

function GeigerCounterManager.new(): GeigerCounterManager
	local self = setmetatable({}, GeigerCounterManager) :: GeigerCounterManager
	self.levelByPlayer = {}
	return self
end

return GeigerCounterManager.new()
