--!strict

-- Lobby-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the lobby's own managers.
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientCharacterMenuManager = require(script.Parent.ClientCharacterMenuManager)
local ClientCharacterSheetManager = require(script.Parent.ClientCharacterSheetManager)
local ClientHudManager = require(script.Parent.ClientHudManager)
local ClientJetPackManager = require(script.Parent.Parent.Client.ClientJetPackManager)
local ClientPadBillboardManager = require(script.Parent.ClientPadBillboardManager)
local ClientPartyMenuManager = require(script.Parent.ClientPartyMenuManager)

ClientDataManager:awaitReady()

-- the menus before the HUD, whose Character button opens them
ClientCharacterSheetManager:init()
ClientCharacterMenuManager:init()
ClientHudManager:init()
-- after the HUD, whose jet pack bar and touch button it drives
ClientJetPackManager:init()
ClientPadBillboardManager:init()
ClientPartyMenuManager:init()
