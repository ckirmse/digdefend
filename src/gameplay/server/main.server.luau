--!strict

-- Gameplay-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the gameplay's own managers.
local ArrivalGateManager = require(script.Parent.ArrivalGateManager)

ArrivalGateManager:init()
