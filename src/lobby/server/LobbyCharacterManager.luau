--!strict

-- Dresses every character in the lobby (designer, 2026-10-12): any Roblox
-- back accessory comes off so the company jet pack, which every client
-- wears on every character through ClientJetPackManager (the same pack
-- that flies in a run, since the jet pack works in the lobby too), has
-- the back to itself. Stripping is the server's job so every client sees
-- the same character.
local Players = game:GetService("Players")

local Wearables = require("@game/ReplicatedStorage/Shared/Wearables")

local LobbyCharacterManager = {}
LobbyCharacterManager.__index = LobbyCharacterManager

export type LobbyCharacterManager = typeof(setmetatable({} :: {}, LobbyCharacterManager))

function LobbyCharacterManager:dress(character: Model)
	-- the accessories arrive with the appearance, a moment after the rig
	task.defer(
		function()
			if character.Parent ~= nil then
				Wearables.removeBackAccessories(character)
			end
		end
	)
end

function LobbyCharacterManager:watchPlayer(player: Player)
	player.CharacterAppearanceLoaded:Connect(
		function(character: Model)
			self:dress(character)
		end
	)
	local character = player.Character
	if character and character:FindFirstChild("Humanoid") then
		self:dress(character)
	end
end

function LobbyCharacterManager:init()
	for _, player in Players:GetPlayers() do
		self:watchPlayer(player)
	end
	Players.PlayerAdded:Connect(
		function(player: Player)
			self:watchPlayer(player)
		end
	)
end

function LobbyCharacterManager.new(): LobbyCharacterManager
	local self = setmetatable({}, LobbyCharacterManager) :: LobbyCharacterManager
	return self
end

return LobbyCharacterManager.new()
