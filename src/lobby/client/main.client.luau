--!strict

-- Lobby-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the lobby's own managers.
local ClientButtonSoundManager = require(script.Parent.Parent.Client.ClientButtonSoundManager)
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientDevConsoleManager = require(script.Parent.Parent.Client.ClientDevConsoleManager)
local ClientClassMenuManager = require(script.Parent.ClientClassMenuManager)
local ClientGachaDevTools = require(script.Parent.ClientGachaDevTools)
local ClientDiamondStoreManager = require(script.Parent.ClientDiamondStoreManager)
local ClientGachaMenuManager = require(script.Parent.ClientGachaMenuManager)
local ClientHudManager = require(script.Parent.ClientHudManager)
local ClientJetPackManager = require(script.Parent.Parent.Client.ClientJetPackManager)
local ClientPadBillboardManager = require(script.Parent.ClientPadBillboardManager)
local ClientLobbyMusicManager = require(script.Parent.ClientLobbyMusicManager)
local ClientLobbyNpcManager = require(script.Parent.ClientLobbyNpcManager)
local ClientStoreZoneManager = require(script.Parent.ClientStoreZoneManager)
local ClientPartyMenuManager = require(script.Parent.ClientPartyMenuManager)

ClientDataManager:awaitReady()
ClientButtonSoundManager:init()
ClientDevConsoleManager:init()

-- the menus before the HUD, whose Classes and Store buttons open them
ClientClassMenuManager:init()
ClientGachaMenuManager:init()
ClientDiamondStoreManager:init()
ClientGachaDevTools:init()
ClientHudManager:init()
-- after the HUD, whose jet pack bar and touch button it drives
ClientJetPackManager:init()
ClientPadBillboardManager:init()
ClientPartyMenuManager:init()
-- after the party menu, whose launch it listens for
ClientLobbyMusicManager:init()
ClientLobbyNpcManager:init()
-- after both store menus, which it opens
ClientStoreZoneManager:init()
