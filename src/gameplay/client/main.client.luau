--!strict

-- Gameplay-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the gameplay's own managers.
local StarterGui = game:GetService("StarterGui")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientBackpackManager = require(script.Parent.ClientBackpackManager)
local ClientDynamiteManager = require(script.Parent.ClientDynamiteManager)
local ClientIconFlightManager = require(script.Parent.ClientIconFlightManager)
local ClientJetPackManager = require(script.Parent.ClientJetPackManager)
local ClientMineDevTools = require(script.Parent.ClientMineDevTools)
local ClientMineLightingManager = require(script.Parent.ClientMineLightingManager)
local ClientMineManager = require(script.Parent.ClientMineManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientMiningStoreManager = require(script.Parent.ClientMiningStoreManager)
local ClientOrePickupManager = require(script.Parent.ClientOrePickupManager)
local ClientRefineryManager = require(script.Parent.ClientRefineryManager)
local ClientRunDevTools = require(script.Parent.ClientRunDevTools)
local ClientToolBarManager = require(script.Parent.ClientToolBarManager)
local ClientTorchManager = require(script.Parent.ClientTorchManager)

ClientDataManager:awaitReady()

-- held tools are real Tool instances (ToolManager) but the custom tool bar
-- is the only bar; Roblox's own hotbar stays off
pcall(
	function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end
)

ClientMineManager:init()
ClientMineLightingManager:init()
ClientToolBarManager:init()
ClientMiningManager:init()
-- before the backpack and refinery, which fly icons across its layer
ClientIconFlightManager:init()
ClientBackpackManager:init()
ClientOrePickupManager:init()
ClientRefineryManager:init()
ClientMiningStoreManager:init()
ClientDynamiteManager:init()
ClientTorchManager:init()
ClientJetPackManager:init()

if ClientDataManager:getIsAdmin() then
	ClientRunDevTools:init()
	ClientMineDevTools:init()
end
