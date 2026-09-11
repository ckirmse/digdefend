--!strict

-- Lobby-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the lobby's own managers.
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientHelicopterManager = require(script.Parent.ClientHelicopterManager)
local ClientHudManager = require(script.Parent.ClientHudManager)
local ClientPadBillboardManager = require(script.Parent.ClientPadBillboardManager)
local ClientPartyMenuManager = require(script.Parent.ClientPartyMenuManager)

ClientDataManager:awaitReady()

ClientHelicopterManager:init()
ClientHudManager:init()
ClientPadBillboardManager:init()
ClientPartyMenuManager:init()
