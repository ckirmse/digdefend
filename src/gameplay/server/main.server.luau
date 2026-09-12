--!strict

-- Gameplay-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the gameplay's own managers.
local ArrivalManager = require(script.Parent.ArrivalManager)
local BackpackManager = require(script.Parent.BackpackManager)
local GameplayMapManager = require(script.Parent.GameplayMapManager)
local MapManager = require(script.Parent.MapManager)
local MineDevTools = require(script.Parent.MineDevTools)
local MineManager = require(script.Parent.MineManager)
local MiningManager = require(script.Parent.MiningManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local RunDevTools = require(script.Parent.RunDevTools)
local RunManager = require(script.Parent.RunManager)
local ToolManager = require(script.Parent.ToolManager)

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
OrePickupManager:init()
MiningManager:init()

RunDevTools:init()
MineDevTools:init()
