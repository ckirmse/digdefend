--!strict

-- Gameplay-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the gameplay's own managers.
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientRunDevTools = require(script.Parent.ClientRunDevTools)

ClientDataManager:awaitReady()

ClientRunDevTools:init()
