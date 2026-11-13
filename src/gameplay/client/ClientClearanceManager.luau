--!strict

-- Keeps the local character on its feet in the mine (2026-11-13). The
-- server's ClearanceManager welds a collider over every head so a passage
-- has to be two blocks tall; that collider sits high above the feet, so
-- catching it on a block's edge (a jump, the jet pack, a knockback, walking
-- under a ledge) tips the character over, and Roblox answers a tipped
-- Humanoid with its FallingDown and Ragdoll states: the body lies on the
-- ground for a few seconds before it gets up. Nothing in the game wants
-- those states (a death lays the body down with PlatformStand and the
-- Physics state, ClientReviveManager), so both are switched off and a bump
-- only stops the character. The states of a Humanoid belong to the client
-- that owns the character, which is why this is client code.
local Players = game:GetService("Players")

local ClientClearanceManager = {}
ClientClearanceManager.__index = ClientClearanceManager

export type ClientClearanceManager = typeof(setmetatable({} :: {}, ClientClearanceManager))

local HUMANOID_WAIT_SEC = 10
local TRIP_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
}

function ClientClearanceManager:applyToCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", HUMANOID_WAIT_SEC)
	if not humanoid or not humanoid:IsA("Humanoid") then
		warn(`ClientClearanceManager: {character.Name} has no Humanoid; it can still be knocked over`)
		return
	end
	for _, state in TRIP_STATES do
		humanoid:SetStateEnabled(state, false)
	end
end

function ClientClearanceManager:init()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(
		function(character: Model)
			self:applyToCharacter(character)
		end
	)
	if player.Character then
		self:applyToCharacter(player.Character)
	end
end

function ClientClearanceManager.new(): ClientClearanceManager
	local self = setmetatable({}, ClientClearanceManager) :: ClientClearanceManager
	return self
end

return ClientClearanceManager.new()
