--!strict

-- The single top-level orchestrator: requires every manager, wires them
-- together through init(), and assembles the full network protocol in one
-- place so it can be read top to bottom.
local Players = game:GetService("Players")

local NetManager = require(script.Parent.NetManager)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)

local GameController = {}
GameController.__index = GameController

export type GameController = typeof(setmetatable(
	{} :: {
		netManager: typeof(NetManager),
		playerFeedbackManager: typeof(PlayerFeedbackManager),
	},
	GameController
))

-- Until the player lifecycle lands (M6) every connected player counts as Ready.
function GameController:isPlayerReady(player: Player): boolean
	return player.Parent == Players
end

function GameController:init()
	-- the full network protocol, assembled in one place; managers that handle
	-- client messages expose getNetHandlers() and are listed here
	local netHandlers: NetManager.NetHandlers = {}
	local handlerOwners: { any } = {}
	for _, manager in handlerOwners do
		for eventName, entry in manager:getNetHandlers() do
			if netHandlers[eventName] then
				error("GameController: duplicate net handler for " .. eventName)
			end
			netHandlers[eventName] = entry
		end
	end

	self.netManager = NetManager
	NetManager:init(self, netHandlers)

	self.playerFeedbackManager = PlayerFeedbackManager
end

function GameController.new(): GameController
	local self = setmetatable({}, GameController) :: GameController
	self.netManager = NetManager
	self.playerFeedbackManager = PlayerFeedbackManager
	return self
end

local gameController = GameController.new()
gameController:init()

return gameController
