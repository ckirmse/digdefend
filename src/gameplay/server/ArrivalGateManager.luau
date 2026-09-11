--!strict

-- The gameplay place's door: only members of the party this server was
-- reserved for may stay (GDD "Only players in that party can enter that
-- gameplay server"). Reserved servers already keep outsiders away; this is
-- the second lock, read from the teleport data the lobby sent (M13). Arrival
-- itself (spawning at the camp pad, loading screen) is M14.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")

local ArrivalGateManager = {}
ArrivalGateManager.__index = ArrivalGateManager

export type ArrivalGateManager = typeof(setmetatable({} :: {}, ArrivalGateManager))

function ArrivalGateManager:checkPlayer(player: Player)
	local joinData = player:GetJoinData()
	local teleportData = if joinData then joinData.TeleportData else nil
	local rejection = PartyRules.getArrivalRejection(teleportData, player.UserId)
	if not rejection then
		return
	end
	-- a Play session in Studio has no teleport data; keep it usable
	if RunService:IsStudio() then
		warn(`ArrivalGateManager: {player.Name} has no valid party join data (allowed in Studio)`)
		return
	end
	warn(`ArrivalGateManager: kicking {player.Name}: {rejection}`)
	player:Kick(rejection)
end

function ArrivalGateManager:init()
	Players.PlayerAdded:Connect(
		function(player: Player)
			self:checkPlayer(player)
		end
	)
	for _, player in Players:GetPlayers() do
		self:checkPlayer(player)
	end
end

function ArrivalGateManager.new(): ArrivalGateManager
	local self = setmetatable({}, ArrivalGateManager) :: ArrivalGateManager
	return self
end

return ArrivalGateManager.new()
