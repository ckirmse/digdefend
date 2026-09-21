--!strict

-- Gameplay-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the gameplay's own managers.
local StarterGui = game:GetService("StarterGui")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientActionButtonManager = require(script.Parent.ClientActionButtonManager)
local ClientAimManager = require(script.Parent.ClientAimManager)
local ClientBackpackManager = require(script.Parent.ClientBackpackManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientDefenseStoreManager = require(script.Parent.ClientDefenseStoreManager)
local ClientDynamiteManager = require(script.Parent.ClientDynamiteManager)
local ClientIconFlightManager = require(script.Parent.ClientIconFlightManager)
local ClientImpactManager = require(script.Parent.ClientImpactManager)
local ClientJetPackManager = require(script.Parent.ClientJetPackManager)
local ClientMineDevTools = require(script.Parent.ClientMineDevTools)
local ClientMineLightingManager = require(script.Parent.ClientMineLightingManager)
local ClientMineManager = require(script.Parent.ClientMineManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientMiningStoreManager = require(script.Parent.ClientMiningStoreManager)
local ClientOrePickupManager = require(script.Parent.ClientOrePickupManager)
local ClientPlacementDevTools = require(script.Parent.ClientPlacementDevTools)
local ClientPlacementManager = require(script.Parent.ClientPlacementManager)
local ClientPlacementToolManager = require(script.Parent.ClientPlacementToolManager)
local ClientPostDevTools = require(script.Parent.ClientPostDevTools)
local ClientPostManager = require(script.Parent.ClientPostManager)
local ClientPostUpgradeManager = require(script.Parent.ClientPostUpgradeManager)
local ClientRefineryManager = require(script.Parent.ClientRefineryManager)
local ClientRunDevTools = require(script.Parent.ClientRunDevTools)
local ClientStructureDevTools = require(script.Parent.ClientStructureDevTools)
local ClientStructureManager = require(script.Parent.ClientStructureManager)
local ClientToolBarManager = require(script.Parent.ClientToolBarManager)
local ClientTorchManager = require(script.Parent.ClientTorchManager)
local ClientTowerMenuManager = require(script.Parent.ClientTowerMenuManager)
local ClientWorkbenchManager = require(script.Parent.ClientWorkbenchManager)
local ClientTouchLayoutManager = require(script.Parent.ClientTouchLayoutManager)
local ClientWeaponDevTools = require(script.Parent.ClientWeaponDevTools)
local ClientWeaponManager = require(script.Parent.ClientWeaponManager)

ClientDataManager:awaitReady()

-- held tools are real Tool instances (ToolManager) but the custom tool bar
-- is the only bar; Roblox's own hotbar stays off. The player list is off
-- too: a run's crew is at most six people already in view (2026-09-16)
pcall(
	function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
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
ClientStructureManager:init()
ClientWorkbenchManager:init()
ClientDamageableManager:init()
ClientImpactManager:init()
ClientWeaponManager:init()
ClientAimManager:init()
-- after the weapon manager, whose tracer and muzzle effects it borrows
ClientPostManager:init()
ClientPostUpgradeManager:init()
-- placements (M26): the bodies and billboards first, then the build bar
-- and preview that read them, then the menu and the store stands
ClientPlacementManager:init()
ClientPlacementToolManager:init()
ClientTowerMenuManager:init()
ClientDefenseStoreManager:init()
-- after the tool managers it dispatches to
ClientActionButtonManager:init()
ClientJetPackManager:init()
-- after both touch buttons exist; it places them around the jump button
ClientTouchLayoutManager:init()

if ClientDataManager:getIsAdmin() then
	ClientRunDevTools:init()
	ClientMineDevTools:init()
	ClientStructureDevTools:init()
	ClientWeaponDevTools:init()
	ClientPostDevTools:init()
	ClientPlacementDevTools:init()
end
