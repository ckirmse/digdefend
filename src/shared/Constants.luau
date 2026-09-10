--!strict

local Enums = require(script.Parent.Enums)

local Constants = {}

Constants.LOBBY_PLACE_ID = 133996405589098
Constants.GAMEPLAY_PLACE_ID = 72646464251078

Constants.SPLENDID_GAMES_NAME = "SplendidGames"
Constants.GAME_METADATA_FOLDER = "GameMetadata"
Constants.ALL_PLAYERS_FOLDER = "AllPlayers"
Constants.CURRENT_PLAYER_FOLDER = "CurrentPlayer"

Constants.REMOTE_EVENT_NAME = "GameRemoteEvent"

Constants.SHADOWS_FOLDER = "Shadows"
Constants.CASTERS_FOLDER = "Casters"

Constants.DATA_SCHEMA_VERSION = 1

Constants.DAY_SEC = 86400

function Constants.getPlaceKind(): number
	if game.PlaceId == Constants.LOBBY_PLACE_ID then
		return Enums.PlaceKind.LOBBY
	end
	if game.PlaceId == Constants.GAMEPLAY_PLACE_ID then
		return Enums.PlaceKind.GAMEPLAY
	end
	return Enums.PlaceKind.STUDIO
end

return Constants
