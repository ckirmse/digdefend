--!strict

-- Gameplay-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the gameplay's own managers.
local AimManager = require(script.Parent.AimManager)
local ArrivalManager = require(script.Parent.ArrivalManager)
local BackpackManager = require(script.Parent.BackpackManager)
local BootsManager = require(script.Parent.BootsManager)
local DamageableManager = require(script.Parent.DamageableManager)
local DefenseStoreManager = require(script.Parent.DefenseStoreManager)
local DynamiteManager = require(script.Parent.DynamiteManager)
local GameplayMapManager = require(script.Parent.GameplayMapManager)
local JetPackManager = require(script.Parent.JetPackManager)
local MapManager = require(script.Parent.MapManager)
local MineDevTools = require(script.Parent.MineDevTools)
local MineManager = require(script.Parent.MineManager)
local MiningManager = require(script.Parent.MiningManager)
local MiningStoreManager = require(script.Parent.MiningStoreManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local PlacementDevTools = require(script.Parent.PlacementDevTools)
local PlacementManager = require(script.Parent.PlacementManager)
local PostDevTools = require(script.Parent.PostDevTools)
local PostManager = require(script.Parent.PostManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RunDevTools = require(script.Parent.RunDevTools)
local RunManager = require(script.Parent.RunManager)
local StructureDevTools = require(script.Parent.StructureDevTools)
local StructureManager = require(script.Parent.StructureManager)
local ToolManager = require(script.Parent.ToolManager)
local TorchManager = require(script.Parent.TorchManager)
local TowerBehaviorManager = require(script.Parent.TowerBehaviorManager)
local TrapBehaviorManager = require(script.Parent.TrapBehaviorManager)
local WeaponDevTools = require(script.Parent.WeaponDevTools)
local WeaponManager = require(script.Parent.WeaponManager)

GameplayMapManager:init()
RunManager:init()
MapManager:init()

-- run-start order matters: the map must exist before the helicopter is
-- placed on its pad and before the mine reads the entrance part
RunManager:subscribeRunStarted(
	function(map: number, _difficulty: number)
		MapManager:loadMap(map)
	end
)
ArrivalManager:init()
MineManager:init()
RunManager:subscribeRunStarted(
	function(map: number, difficulty: number)
		MineManager:onRunStarted(map, difficulty)
	end
)

-- the target registry steps its walkers, burns, and slows; before every
-- manager that hurts or reads targets
DamageableManager:init()
ToolManager:init()
-- right after the tools, so the weapon is the second slot (GDD "Mining
-- Tools": bought tools come after Pick Axe and Weapon)
WeaponManager:init()
AimManager:init()
BackpackManager:init()
BootsManager:init()
JetPackManager:init()
OrePickupManager:init()
MiningManager:init()
DynamiteManager:init()
TorchManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		TorchManager:onRunStarted()
	end
)
-- after the mine, so the refinery reads the run's uranium target and camp level
RefineryManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		RefineryManager:onRunStarted()
	end
)
-- after the refinery, which owns the Gold the store spends
MiningStoreManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		MiningStoreManager:onRunStarted()
	end
)
-- after the tools (everyone is handed a Hammer) and the refinery, which
-- owns the Iron repairs spend and the Camp Level the Refinery's HP follows
StructureManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		StructureManager:onRunStarted()
	end
)
-- after the structures, whose post models it claims and hangs weapons on,
-- and the refinery, which owns the Gold a claim and an upgrade spend.
-- StructureManager subscribed to the run first, so the fresh post models
-- exist by the time PostManager resets and binds them
PostManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		PostManager:onRunStarted()
	end
)
-- after the tools (Repair Mode is the Hammer) and the refinery, which owns
-- the Iron a build, an upgrade, and a Trap spend; it reads the fresh map's
-- Defensive Zones at run start
PlacementManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		PlacementManager:onRunStarted()
	end
)
-- after the placements they read every Heartbeat and the target registry
-- they hurt, slow, and (the Traps) block
TowerBehaviorManager:init()
TrapBehaviorManager:init()
-- after the placements, whose inventory it fills
DefenseStoreManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		DefenseStoreManager:onRunStarted()
	end
)

RunDevTools:init()
MineDevTools:init()
StructureDevTools:init()
WeaponDevTools:init()
PostDevTools:init()
PlacementDevTools:init()
