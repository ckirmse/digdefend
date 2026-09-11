--!strict

-- Lobby-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the lobby's own managers.
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientPadBillboardManager = require(script.Parent.ClientPadBillboardManager)

ClientDataManager:awaitReady()

ClientPadBillboardManager:init()
