--!strict

-- Boots (GDD "Boots"): the one thing they do is walk speed. The level is run
-- state held here and applied to the character's Humanoid on upgrade and on
-- every spawn, so speed is never trusted from the client. Everyone starts at
-- level 1, Roblox's default speed; the Mining Supplies Store raises it.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BootsData = require("@game/ServerScriptService/GameData/Mining/Boots")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local BootsManager = {}
BootsManager.__index = BootsManager

export type BootsManager = typeof(setmetatable(
	{} :: {
		levelByPlayer: { [Player]: number },
	},
	BootsManager
))

local STARTING_LEVEL = 1

function BootsManager:getLevel(player: Player): number
	return self.levelByPlayer[player] or STARTING_LEVEL
end

function BootsManager:getWalkSpeed(player: Player): number
	local speeds = BootsData.WALK_SPEED_BY_LEVEL
	local level = math.clamp(self:getLevel(player), 1, #speeds)
	return speeds[level]
end

function BootsManager:applyToCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = self:getWalkSpeed(player)
	end
end

function BootsManager:apply(player: Player)
	local character = player.Character
	if character then
		self:applyToCharacter(player, character)
	end
end

function BootsManager:replicate(player: Player)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.BOOTS_LEVEL, self:getLevel(player))
end

function BootsManager:setLevel(player: Player, level: number)
	if not self.levelByPlayer[player] then
		return
	end
	self.levelByPlayer[player] = level
	self:apply(player)
	self:replicate(player)
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state survives
function BootsManager:onPlayerReady(player: Player)
	if not self.levelByPlayer[player] then
		self.levelByPlayer[player] = STARTING_LEVEL
		player.CharacterAdded:Connect(
			function(character: Model)
				self:applyToCharacter(player, character)
			end
		)
	end
	self:apply(player)
	self:replicate(player)
end

function BootsManager:init()
	GameController:registerPlaceManager(self)
	-- not a teardown entry: a dev-tool reset must not strip the run's upgrades
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.levelByPlayer[player] = nil
		end
	)
end

function BootsManager.new(): BootsManager
	local self = setmetatable({}, BootsManager) :: BootsManager
	self.levelByPlayer = {}
	return self
end

return BootsManager.new()
