--!strict

-- Gameplay-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the gameplay's own managers.
local ArrivalManager = require(script.Parent.ArrivalManager)
local GameplayMapManager = require(script.Parent.GameplayMapManager)
local RunDevTools = require(script.Parent.RunDevTools)
local RunManager = require(script.Parent.RunManager)

GameplayMapManager:init()
RunManager:init()
ArrivalManager:init()
RunDevTools:init()
