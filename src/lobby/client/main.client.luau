--!strict

-- Lobby-only client startup. The shared client starts from
-- StarterPlayerScripts/Client/main; this script wires the lobby's own managers.
local ClientButtonSoundManager = require(script.Parent.Parent.Client.ClientButtonSoundManager)
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientDevConsoleManager = require(script.Parent.Parent.Client.ClientDevConsoleManager)
local ClientClassMenuManager = require(script.Parent.ClientClassMenuManager)
local ClientCrateTutorialManager = require(script.Parent.ClientCrateTutorialManager)
local ClientBadgeMenuManager = require(script.Parent.ClientBadgeMenuManager)
local ClientDailyRewardManager = require(script.Parent.ClientDailyRewardManager)
local ClientGachaDevTools = require(script.Parent.ClientGachaDevTools)
local ClientDiamondStoreManager = require(script.Parent.ClientDiamondStoreManager)
local ClientRestrictedStoreManager = require(script.Parent.ClientRestrictedStoreManager)
local ClientGachaMenuManager = require(script.Parent.ClientGachaMenuManager)
local ClientGearMenuManager = require(script.Parent.ClientGearMenuManager)
local ClientGroupRewardManager = require(script.Parent.ClientGroupRewardManager)
local ClientHudManager = require(script.Parent.ClientHudManager)
local ClientKeyStoreManager = require(script.Parent.ClientKeyStoreManager)
local ClientJetPackManager = require(script.Parent.Parent.Client.ClientJetPackManager)
local ClientPadBillboardManager = require(script.Parent.ClientPadBillboardManager)
local ClientLobbyMusicManager = require(script.Parent.ClientLobbyMusicManager)
local ClientLobbyNpcManager = require(script.Parent.ClientLobbyNpcManager)
local ClientStarterPackManager = require(script.Parent.ClientStarterPackManager)
local ClientStoreSignManager = require(script.Parent.ClientStoreSignManager)
local ClientStoreZoneManager = require(script.Parent.ClientStoreZoneManager)
local ClientPartyMenuManager = require(script.Parent.ClientPartyMenuManager)

ClientDataManager:awaitReady()
ClientButtonSoundManager:init()
ClientDevConsoleManager:init()

-- before the store menus, each of which hands it a banner (M78)
ClientGroupRewardManager:init()
-- the menus before the HUD, whose Classes and Store buttons open them
ClientClassMenuManager:init()
ClientGachaMenuManager:init()
ClientKeyStoreManager:init()
ClientGearMenuManager:init()
ClientDiamondStoreManager:init()
ClientRestrictedStoreManager:init()
-- after the group reward, whose claim menu goes first on arrival (M39)
ClientDailyRewardManager:init()
ClientStarterPackManager:init()
-- the Badges menu (M69), before the HUD whose button opens it
ClientBadgeMenuManager:init()
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
ClientStoreSignManager:init()
-- after the crate menu, whose price and button it reads; off the main
-- thread because it waits for the Tutorial gui
task.spawn(
	function()
		ClientCrateTutorialManager:init()
	end
)
