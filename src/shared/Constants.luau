--!strict

local Enums = require(script.Parent.Enums)

local Constants = {}

Constants.LOBBY_PLACE_ID = 133996405589098
Constants.GAMEPLAY_PLACE_ID = 72646464251078

Constants.SPLENDID_GAMES_NAME = "SplendidGames"
Constants.GAME_METADATA_FOLDER = "GameMetadata"
Constants.ALL_PLAYERS_FOLDER = "AllPlayers"
Constants.CURRENT_PLAYER_FOLDER = "CurrentPlayer"
-- CurrentPlayer sub-folders whose children are name-only marker folders
Constants.OWNED_UNLOCKS_FOLDER = "OwnedUnlocks"
Constants.COMPLETIONS_FOLDER = "Completions"

Constants.REMOTE_EVENT_NAME = "GameRemoteEvent"
-- client-only BindableEvent; server feedback travels as NotifyPlayerFeedback on the RemoteEvent
Constants.PLAYER_FEEDBACK_LOCAL_EVENT_NAME = "GivePlayerFeedbackLocal"

-- dev tools are gated to this Roblox group at or above this rank
Constants.ADMIN_GROUP_ID = 571203718
Constants.ADMIN_MIN_RANK = 254

-- the one central ReplicatedStorage folder every clonable asset lives under
Constants.GAME_ASSETS_FOLDER = "GameAssets"

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
