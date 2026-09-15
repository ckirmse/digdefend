--!strict

-- Gameplay-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the gameplay's own managers.
local ArrivalManager = require(script.Parent.ArrivalManager)
local BackpackManager = require(script.Parent.BackpackManager)
local BootsManager = require(script.Parent.BootsManager)
local DynamiteManager = require(script.Parent.DynamiteManager)
local GameplayMapManager = require(script.Parent.GameplayMapManager)
local JetPackManager = require(script.Parent.JetPackManager)
local MapManager = require(script.Parent.MapManager)
local MineDevTools = require(script.Parent.MineDevTools)
local MineManager = require(script.Parent.MineManager)
local MiningManager = require(script.Parent.MiningManager)
local MiningStoreManager = require(script.Parent.MiningStoreManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local RefineryManager = require(script.Parent.RefineryManager)
local RunDevTools = require(script.Parent.RunDevTools)
local RunManager = require(script.Parent.RunManager)
local ToolManager = require(script.Parent.ToolManager)
local TorchManager = require(script.Parent.TorchManager)

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

ToolManager:init()
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

RunDevTools:init()
MineDevTools:init()
