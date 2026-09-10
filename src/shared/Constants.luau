--!strict

local Constants = {}

Constants.LOBBY_PLACE_ID = 133996405589098
Constants.GAMEPLAY_PLACE_ID = 72646464251078

export type PlaceKind = "Lobby" | "Gameplay" | "Studio"

function Constants.getPlaceKind(): PlaceKind
	if game.PlaceId == Constants.LOBBY_PLACE_ID then
		return "Lobby"
	end
	if game.PlaceId == Constants.GAMEPLAY_PLACE_ID then
		return "Gameplay"
	end
	-- Local place files and unpublished Studio sessions have PlaceId 0
	return "Studio"
end

return Constants
