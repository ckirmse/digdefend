--!strict

-- Gameplay-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the gameplay's own managers.
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientMineDevTools = require(script.Parent.ClientMineDevTools)
local ClientMineManager = require(script.Parent.ClientMineManager)
local ClientRunDevTools = require(script.Parent.ClientRunDevTools)

ClientDataManager:awaitReady()

ClientMineManager:init()

if ClientDataManager:getIsAdmin() then
	ClientRunDevTools:init()
	ClientMineDevTools:init()
end
