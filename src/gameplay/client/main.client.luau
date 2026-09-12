--!strict

-- Gameplay-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the gameplay's own managers.
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientBackpackManager = require(script.Parent.ClientBackpackManager)
local ClientMineDevTools = require(script.Parent.ClientMineDevTools)
local ClientMineManager = require(script.Parent.ClientMineManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientOrePickupManager = require(script.Parent.ClientOrePickupManager)
local ClientRunDevTools = require(script.Parent.ClientRunDevTools)
local ClientToolBarManager = require(script.Parent.ClientToolBarManager)
local ClientToolModelManager = require(script.Parent.ClientToolModelManager)

ClientDataManager:awaitReady()

ClientMineManager:init()
ClientToolBarManager:init()
ClientToolModelManager:init()
ClientMiningManager:init()
ClientBackpackManager:init()
ClientOrePickupManager:init()

if ClientDataManager:getIsAdmin() then
	ClientRunDevTools:init()
	ClientMineDevTools:init()
end
