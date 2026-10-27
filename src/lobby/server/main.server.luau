--!strict

-- Lobby-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the lobby's own managers.
local LobbyCharacterManager = require(script.Parent.LobbyCharacterManager)
local LobbyMapManager = require(script.Parent.LobbyMapManager)
local PartyManager = require(script.Parent.PartyManager)
local HelicopterManager = require(script.Parent.Parent.Server.HelicopterManager)
local JetPackManager = require(script.Parent.Parent.Server.JetPackManager)

LobbyMapManager:init()
-- the flight config the clients fly every departure from (M75)
HelicopterManager:init()
LobbyCharacterManager:init()
-- the jet pack flies in the lobby as in a run (designer, 2026-10-12)
JetPackManager:init()
PartyManager:init()
