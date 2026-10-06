--!strict

-- Gameplay-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the gameplay's own managers.
local AimManager = require(script.Parent.AimManager)
local ArrivalManager = require(script.Parent.ArrivalManager)
local BackpackManager = require(script.Parent.BackpackManager)
local BalanceAudit = require(script.Parent.BalanceAudit)
local BootsManager = require(script.Parent.BootsManager)
local DiamondTapManager = require(script.Parent.DiamondTapManager)
local ClearanceManager = require(script.Parent.ClearanceManager)
local CompassManager = require(script.Parent.CompassManager)
local DamageableManager = require(script.Parent.DamageableManager)
local DefenseTableManager = require(script.Parent.DefenseTableManager)
local DynamiteManager = require(script.Parent.DynamiteManager)
local GameplayMapManager = require(script.Parent.GameplayMapManager)
local GeigerCounterManager = require(script.Parent.GeigerCounterManager)
local GiveCurrencyManager = require(script.Parent.GiveCurrencyManager)
local JetPackManager = require(script.Parent.JetPackManager)
local MapManager = require(script.Parent.MapManager)
local MineDevTools = require(script.Parent.MineDevTools)
local MineManager = require(script.Parent.MineManager)
local MonsterDevTools = require(script.Parent.MonsterDevTools)
local MonsterManager = require(script.Parent.MonsterManager)
local MonsterPathManager = require(script.Parent.MonsterPathManager)
local MonsterWaveManager = require(script.Parent.MonsterWaveManager)
local MiningManager = require(script.Parent.MiningManager)
local MiningStoreManager = require(script.Parent.MiningStoreManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local PlacementDevTools = require(script.Parent.PlacementDevTools)
local PlacementManager = require(script.Parent.PlacementManager)
local PostDevTools = require(script.Parent.PostDevTools)
local PostManager = require(script.Parent.PostManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RescueDevTools = require(script.Parent.RescueDevTools)
local RescueManager = require(script.Parent.RescueManager)
local ReviveDevTools = require(script.Parent.ReviveDevTools)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleDevTools = require(script.Parent.RunCycleDevTools)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunDevTools = require(script.Parent.RunDevTools)
local RunPauseManager = require(script.Parent.RunPauseManager)
local RunManager = require(script.Parent.RunManager)
local RunStatsManager = require(script.Parent.RunStatsManager)
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
-- the run's numbers for the Results Menu (M32): right after the registry
-- whose hits it counts, and before the refinery, which reports to it
RunStatsManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		RunStatsManager:onRunStarted()
	end
)
ToolManager:init()
-- right after the tools, so the weapon is the second slot (GDD "Mining
-- Tools": bought tools come after Pick Axe and Weapon)
WeaponManager:init()
-- it binds the fresh camp's Weapons Table and starts the run's upgrades over
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		WeaponManager:onRunStarted()
	end
)
AimManager:init()
BackpackManager:init()
BootsManager:init()
ClearanceManager:init()
JetPackManager:init()
-- the compass reads the fresh camp's Refinery at run start
CompassManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		CompassManager:onRunStarted()
	end
)
GeigerCounterManager:init()
OrePickupManager:init()
MiningManager:init()
DynamiteManager:init()
TorchManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		TorchManager:onRunStarted()
	end
)
-- after the mine, so the refinery reads the run's uranium target
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
-- owns the Iron repairs spend
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
-- the Defense Table (Build Mode): after the tools it locks, and before the
-- placements, which ask it who may build; it binds the fresh camp's table
DefenseTableManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		DefenseTableManager:onRunStarted()
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
-- the monsters (M29): the path grid reads the fresh camp once the
-- structures stand and the last run's placements are gone (both subscribed
-- above), then the monsters themselves register in the target registry and
-- attack the structures, placements, and players
MonsterPathManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		MonsterPathManager:onRunStarted()
	end
)
MonsterManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		MonsterManager:onRunStarted()
	end
)
-- the day and night loop: last, so every manager that reacts to a dawn or
-- a dusk exists, and after the structures (subscribed above) so the fresh
-- gate stands when day 1 opens it. The gate follows the night flag, and
-- the Refinery falling loses the run
RunCycleManager:init()
RunCycleManager:subscribeNightChanged(
	function(isNight: boolean)
		StructureManager:setNight(isNight)
	end
)
StructureManager:subscribeRefineryDestroyed(
	function()
		RunCycleManager:loseRefinery()
	end
)
-- after the gate (subscribed above), so a night's first monsters meet it
-- shut; the wave clears the night when its last monster dies
MonsterWaveManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		MonsterWaveManager:onRunStarted()
	end
)
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		RunCycleManager:onRunStarted()
	end
)
-- the dev tool's pause (2026-10-02): a holder every loop reads, so it goes
-- first, before the loops it stops subscribe to it
RunPauseManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		RunPauseManager:onRunStarted()
	end
)
-- the rescue (M31): after the refinery it listens to, the run cycle it
-- moves, and the wave manager it hands the final wave; it binds the fresh
-- camp's radio at run start
RescueManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		RescueManager:onRunStarted()
	end
)

-- death and revives (M32): after everything a dead player lets go of
-- (tools, posts, Build Mode) and the run cycle it reads and restarts. The
-- Team Revive starts the day over, so first the wave still to come is
-- cancelled, every monster is removed, and a rescue under way is called off
ReviveManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		ReviveManager:onRunStarted()
	end
)
ReviveManager:subscribeTeamRevived(
	function()
		MonsterWaveManager:stop()
		MonsterManager:killAll()
		RescueManager:cancel()
	end
)
-- Diamonds earned in the run: it listens for each dawn
DiamondTapManager:init()
RunManager:subscribeRunStarted(
	function(_map: number, _difficulty: number)
		DiamondTapManager:onRunStarted()
	end
)
-- after the refinery, whose balances it moves between players
GiveCurrencyManager:init()

RunDevTools:init()
RunCycleDevTools:init()
RescueDevTools:init()
ReviveDevTools:init()
MineDevTools:init()
StructureDevTools:init()
WeaponDevTools:init()
PostDevTools:init()
PlacementDevTools:init()
MonsterDevTools:init()
-- last, so a missed balance target is the final startup line
BalanceAudit:init()
