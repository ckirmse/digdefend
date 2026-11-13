--!strict

-- Lobby-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the lobby's own managers.
local DailyRewardManager = require(script.Parent.DailyRewardManager)
local BadgeManager = require(script.Parent.Parent.Server.BadgeManager)
local DiamondStoreManager = require(script.Parent.DiamondStoreManager)
local GachaManager = require(script.Parent.GachaManager)
local GroupRewardManager = require(script.Parent.GroupRewardManager)
local KeyStoreManager = require(script.Parent.KeyStoreManager)
local LobbyCharacterManager = require(script.Parent.LobbyCharacterManager)
local LobbyMapManager = require(script.Parent.LobbyMapManager)
local PartyManager = require(script.Parent.PartyManager)
local StarterPackManager = require(script.Parent.StarterPackManager)
local HelicopterManager = require(script.Parent.Parent.Server.HelicopterManager)
local JetPackManager = require(script.Parent.Parent.Server.JetPackManager)

-- badges (M69): the award path, before the managers that earn through it
BadgeManager:init()
LobbyMapManager:init()
-- the flight config the clients fly every departure from (M75)
HelicopterManager:init()
LobbyCharacterManager:init()
-- the jet pack flies in the lobby as in a run (designer, 2026-10-12)
JetPackManager:init()
PartyManager:init()
-- the class gacha (M70): rolls, the restricted player's direct buy, and
-- the dev commands behind the Gacha dev panel
GachaManager:init()
-- the stall's second menu: Keys buy cosmetics by name (M61)
KeyStoreManager:init()
DiamondStoreManager:init()
-- the one-time game pass: a class card, Diamonds, and a skin (M79);
-- after the gacha, whose rules pay the card
StarterPackManager:init()
-- a reward a day, claimed from the lobby's Daily Rewards menu (M39)
DailyRewardManager:init()
-- Diamonds once per account for a member of the group (M78)
GroupRewardManager:init()
