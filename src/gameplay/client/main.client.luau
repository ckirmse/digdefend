--!strict

-- Gameplay-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the gameplay's own managers.
local StarterGui = game:GetService("StarterGui")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientActionButtonManager = require(script.Parent.ClientActionButtonManager)
local ClientAimManager = require(script.Parent.ClientAimManager)
local ClientBackpackManager = require(script.Parent.ClientBackpackManager)
local ClientCampMapManager = require(script.Parent.ClientCampMapManager)
local ClientDiamondTapManager = require(script.Parent.ClientDiamondTapManager)
local ClientCompassManager = require(script.Parent.ClientCompassManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientDefenseTableManager = require(script.Parent.ClientDefenseTableManager)
local ClientDynamiteManager = require(script.Parent.ClientDynamiteManager)
local ClientGeigerCounterManager = require(script.Parent.ClientGeigerCounterManager)
local ClientGiveCurrencyManager = require(script.Parent.ClientGiveCurrencyManager)
local ClientIconFlightManager = require(script.Parent.ClientIconFlightManager)
local ClientImpactManager = require(script.Parent.ClientImpactManager)
local ClientJetPackManager = require(script.Parent.ClientJetPackManager)
local ClientMineDevTools = require(script.Parent.ClientMineDevTools)
local ClientMineManager = require(script.Parent.ClientMineManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientMiningStoreManager = require(script.Parent.ClientMiningStoreManager)
local ClientMonsterDevTools = require(script.Parent.ClientMonsterDevTools)
local ClientMonsterManager = require(script.Parent.ClientMonsterManager)
local ClientOrePickupManager = require(script.Parent.ClientOrePickupManager)
local ClientPlayerNameManager = require(script.Parent.ClientPlayerNameManager)
local ClientPlacementDevTools = require(script.Parent.ClientPlacementDevTools)
local ClientPlacementManager = require(script.Parent.ClientPlacementManager)
local ClientRescueManager = require(script.Parent.ClientRescueManager)
local ClientReviveManager = require(script.Parent.ClientReviveManager)
local ClientRunCycleManager = require(script.Parent.ClientRunCycleManager)
local ClientTowerBehaviorManager = require(script.Parent.ClientTowerBehaviorManager)
local ClientTrapBehaviorManager = require(script.Parent.ClientTrapBehaviorManager)
local ClientPostDevTools = require(script.Parent.ClientPostDevTools)
local ClientPostManager = require(script.Parent.ClientPostManager)
local ClientPostUpgradeManager = require(script.Parent.ClientPostUpgradeManager)
local ClientRefineryHpManager = require(script.Parent.ClientRefineryHpManager)
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
local ClientWeaponUpgradeManager = require(script.Parent.ClientWeaponUpgradeManager)

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
ClientWeaponUpgradeManager:init()
-- after the targets and the posts: it registers with the first as the
-- monsters' body provider and borrows the second's blast effect
ClientMonsterManager:init()
-- placements (M26): the bodies and billboards first; the Tower Menu and
-- the Defense Table that read them come further down
ClientPlacementManager:init()
-- after the placements and the targets, whose bodies the effects run between
ClientTowerBehaviorManager:init()
ClientTrapBehaviorManager:init()
-- the day clock reads GameMetadata the server set before anyone was Ready
ClientRunCycleManager:init()
-- the Refinery HP bar that takes the clock's place at night
ClientRefineryHpManager:init()
-- the locator bar that hangs under the day clock
ClientCompassManager:init()
-- the night's overhead map of the camp; after the structures and the
-- monsters it draws
ClientCampMapManager:init()
-- the uranium dial beside the day clock; it asks the mine manager for distances
ClientGeigerCounterManager:init()
-- crewmates' overhead names, in their compass dot colours
ClientPlayerNameManager:init()
ClientRescueManager:init()
-- death and revives (M32): the Results Menu, Spectate Mode (which it
-- starts, and which points the mine renderer at the watched player), and
-- the tombstones
ClientReviveManager:init()
ClientDiamondTapManager:init()
ClientGiveCurrencyManager:init()
ClientTowerMenuManager:init()
-- Build Mode's overhead view: after the placements it taps, the Tower Menu
-- it opens, and the tool bar it hides
ClientDefenseTableManager:init()
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
	ClientMonsterDevTools:init()
end
