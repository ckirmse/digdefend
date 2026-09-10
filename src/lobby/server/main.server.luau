--!strict

-- Lobby-only server startup. The shared GameController starts from
-- ServerScriptService/Server/main; this script wires the lobby's own managers.
local LobbyMapManager = require(script.Parent.LobbyMapManager)

LobbyMapManager:init()
