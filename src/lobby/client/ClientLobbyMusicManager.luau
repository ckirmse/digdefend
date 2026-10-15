--!strict

-- The lobby's music (designer, 2026-10-14): the track starts silent the
-- moment the player is Ready and rises to its level over a few seconds,
-- then fades out over the takeoff when this player's party launches, and
-- rises again if a failed teleport brings the player back. The
-- track itself is the designer's AudioPlayer under SoundService.Music;
-- this only decides when and how loud.
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientPartyMenuManager = require(script.Parent.ClientPartyMenuManager)

local ClientLobbyMusicManager = {}
ClientLobbyMusicManager.__index = ClientLobbyMusicManager

export type ClientLobbyMusicManager = typeof(setmetatable({} :: {}, ClientLobbyMusicManager))

local VOLUME = 0.2
local FADE_IN_SEC = 10
local FADE_OUT_SEC = 3

function ClientLobbyMusicManager:init()
	ClientSoundManager:fadeInMusic(SoundNames.Music.LOBBY, VOLUME, FADE_IN_SEC, true)
	ClientPartyMenuManager:subscribeDeparting(
		function()
			ClientSoundManager:fadeOutMusic(SoundNames.Music.LOBBY, FADE_OUT_SEC)
		end
	)
	ClientPartyMenuManager:subscribeReturned(
		function()
			ClientSoundManager:fadeInMusic(SoundNames.Music.LOBBY, VOLUME, FADE_IN_SEC, true)
		end
	)
end

function ClientLobbyMusicManager.new(): ClientLobbyMusicManager
	local self = setmetatable({}, ClientLobbyMusicManager) :: ClientLobbyMusicManager
	return self
end

return ClientLobbyMusicManager.new()
