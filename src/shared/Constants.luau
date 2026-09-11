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

-- ScreenGuis authored in Studio (scripts/studio/*.luau rebuild them)
Constants.LOADING_GUI_NAME = "Loading"
Constants.LOADING_MAIN_FRAME = "Main"
Constants.LOADING_TITLE_IMAGE = "TitleImage"
Constants.LOADING_TITLE_TEXT = "TitleText"
Constants.LOADING_PROGRESS_BAR = "ProgressBar"
Constants.LOADING_PROGRESS_FILL = "Fill"
Constants.LOADING_STATUS_LABEL = "Status"
Constants.PLAYER_FEEDBACK_GUI_NAME = "PlayerFeedback"
Constants.PLAYER_FEEDBACK_BOX = "FeedbackBox"
Constants.PLAYER_FEEDBACK_LABEL = "Message"
Constants.HUD_GUI_NAME = "HUD"
Constants.HUD_CASH_WALLET = "CashWallet"
Constants.HUD_CASH_AMOUNT_LABEL = "CashAmount"
Constants.HUD_LOADOUT_STRIP = "LoadoutStrip"
Constants.HUD_MENU_BUTTONS = "MenuButtons"
Constants.HUD_STORE_BUTTON = "StoreButton"
Constants.HUD_LOADOUT_BUTTON = "LoadoutButton"
Constants.HUD_DAILY_REWARDS_BUTTON = "DailyRewardsButton"
-- SoundService layout (designer-authored in both places): AudioPlayers under
-- these folders, each wired to the AudioDeviceOutput; see SoundNames
Constants.SFX_FOLDER = "Sfx"
Constants.MUSIC_FOLDER = "Music"
Constants.REMOTE_EVENT_NAME = "GameRemoteEvent"
-- client-only BindableEvent; server feedback travels as NotifyPlayerFeedback on the RemoteEvent
Constants.PLAYER_FEEDBACK_LOCAL_EVENT_NAME = "GivePlayerFeedbackLocal"

-- dev tools are gated to this Roblox group at or above this rank
Constants.ADMIN_GROUP_ID = 571203718
Constants.ADMIN_MIN_RANK = 254

-- the one central ReplicatedStorage folder every clonable asset lives under
Constants.GAME_ASSETS_FOLDER = "GameAssets"

-- lobby Workspace layout (Studio-authored; LobbyMapManager checks it at startup)
Constants.SPAWN_ZONE_FOLDER = "SpawnZone"
Constants.HELICOPTER_PADS_FOLDER = "HelicopterPads"
Constants.STORE_FOLDER = "Store"
Constants.STORE_ITEMS_FOLDER = "Items"
Constants.EVENT_AREA_FOLDER = "EventArea"
Constants.HOLDING_AREA_FOLDER = "HoldingArea"
Constants.HOLDING_AREA_SPAWNS_FOLDER = "Spawns"
Constants.PAD_COUNT = 6
-- parts every helicopter pad model must contain
Constants.PAD_JOIN_COLLISION_PART = "JoinCollision"
Constants.PAD_EXIT_SPAWN_PART = "ExitSpawn"
Constants.PAD_HELICOPTER_SPAWN_PART = "HelicopterSpawn"
Constants.PAD_CAMERA_POSITION_PART = "CameraPositionPart"
Constants.PAD_GUI_PART = "GuiPart"
Constants.PAD_GUI_NAME = "PadGui"
-- TextLabels inside PadGui (built by scripts/studio/build_pad_gui.luau)
Constants.PAD_GUI_PANEL = "Panel"
Constants.PAD_GUI_STATUS_LABEL = "Status"
Constants.PAD_GUI_PRIVATE_LABEL = "Private"
Constants.PAD_GUI_PLAYERS_LABEL = "Players"
-- helicopter template under GameAssets; the clone on a pad keeps the name
Constants.HELICOPTER_TEMPLATE = "Helicopter"
Constants.HELICOPTER_PLAYER_SPAWNS_FOLDER = "PlayerSpawns"
-- a launched helicopter is renamed to this while clients fly it away
Constants.DEPARTED_HELICOPTER_NAME = "DepartedHelicopter"

-- gameplay Workspace layout (Studio-authored; GameplayMapManager checks it at startup)
Constants.CAMP_FOLDER = "Camp"
Constants.CAMP_HELICOPTER_PAD_MODEL = "HelicopterPad"
-- BaseParts named 1..6; players are placed on them in arrival order
Constants.CAMP_SPAWNS_FOLDER = "Spawns"
-- the rotor hub part (blades are welded to it) inside the rotor model; the
-- designer's spelling
Constants.HELICOPTER_ROTOR_MODEL = "Rotar"
Constants.HELICOPTER_ROTOR_PART = "Rotar"
-- pad menus (built by scripts/studio/build_create_party_gui.luau and build_queue_gui.luau)
Constants.CREATE_PARTY_GUI_NAME = "CreateParty"
Constants.QUEUE_GUI_NAME = "Queue"
Constants.MENU_DIALOG_FRAME = "Dialog"
Constants.CREATE_PARTY_MAP_CAROUSEL = "MapCarousel"
Constants.CREATE_PARTY_DIFFICULTY_CAROUSEL = "DifficultyCarousel"
Constants.CAROUSEL_PREVIOUS_BUTTON = "PreviousButton"
Constants.CAROUSEL_NEXT_BUTTON = "NextButton"
Constants.CAROUSEL_THUMBNAIL = "Thumbnail"
Constants.CAROUSEL_NAME_LABEL = "NameLabel"
Constants.CAROUSEL_LOCK_ICON = "LockIcon"
Constants.CAROUSEL_REQUIREMENT_LABEL = "RequirementLabel"
Constants.CREATE_PARTY_PLAYERS_STEPPER = "PlayersStepper"
Constants.STEPPER_MINUS_BUTTON = "MinusButton"
Constants.STEPPER_PLUS_BUTTON = "PlusButton"
Constants.STEPPER_VALUE_LABEL = "ValueLabel"
Constants.CREATE_PARTY_FRIENDS_ONLY_TOGGLE = "FriendsOnlyToggle"
Constants.TOGGLE_STATE_LABEL = "StateLabel"
Constants.CREATE_PARTY_COUNTDOWN_LABEL = "Countdown"
Constants.CREATE_PARTY_CREATE_BUTTON = "CreateButton"
Constants.CREATE_PARTY_CANCEL_BUTTON = "CancelButton"
Constants.QUEUE_MAP_LABEL = "MapLabel"
Constants.QUEUE_DIFFICULTY_LABEL = "DifficultyLabel"
Constants.QUEUE_PLAYERS_LABEL = "PlayersLabel"
Constants.QUEUE_VISIBILITY_LABEL = "VisibilityLabel"
Constants.QUEUE_HOST_LABEL = "HostLabel"
Constants.QUEUE_COUNTDOWN_LABEL = "Countdown"
Constants.QUEUE_LAUNCH_BUTTON = "LaunchButton"
Constants.QUEUE_EXIT_BUTTON = "ExitButton"

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
