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
-- the invisible full-screen button under every menu (ClientOverlayManager);
-- both places (scripts/studio/build_overlay_backdrop_gui.luau)
Constants.OVERLAY_BACKDROP_GUI_NAME = "OverlayBackdrop"
Constants.OVERLAY_BACKDROP_BUTTON = "Backdrop"
-- the admin dev panel's stand-in menu, both places (build_dev_test_menu_gui.luau)
Constants.DEV_TEST_MENU_GUI_NAME = "DevTestMenu"
Constants.DEV_TEST_MENU_DIALOG = "Dialog"
Constants.PLAYER_FEEDBACK_GUI_NAME = "PlayerFeedback"
Constants.PLAYER_FEEDBACK_BOX = "FeedbackBox"
-- top-centre blue box for the beats nobody should miss (Camp Level up)
Constants.PLAYER_FEEDBACK_ANNOUNCEMENT_BOX = "AnnouncementBox"
-- red box under the announcement for danger (a wall down, the Refinery
-- under attack; 2026-09-25)
Constants.PLAYER_FEEDBACK_ALERT_BOX = "AlertBox"
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

-- gameplay map layout (Studio-authored; GameplayMapManager checks it when a
-- map loads). Every map is a Folder under ServerStorage/Maps named by its
-- Enums.Map key; MapManager clones the run's map into Workspace as Camp.
Constants.MAPS_FOLDER = "Maps"
Constants.CAMP_FOLDER = "Camp"
-- the map's scenery, the one part of the camp left to stream by distance
Constants.CAMP_ENVIRONMENT_FOLDER = "Environment"
Constants.CAMP_HELICOPTER_PAD_MODEL = "HelicopterPad"
-- the designer's radio table that calls the rescue (M31): Camp.Radio, with
-- the billboard on GuiPart, the authored prompt on PromptPart, and the
-- screen (Radio.Radio.Screen: a SurfaceGui and a SpotLight) that turns
-- green once the quota is met
Constants.CAMP_RADIO_MODEL = "Radio"
Constants.RADIO_GUI_PART = "GuiPart"
Constants.RADIO_PROMPT_PART = "PromptPart"
Constants.RADIO_INNER_MODEL = "Radio"
Constants.RADIO_SCREEN_PART = "Screen"
Constants.RADIO_SCREEN_GUI = "SurfaceGui"
Constants.RADIO_SCREEN_FRAME = "Frame"
Constants.RADIO_SCREEN_BACKGROUND = "Background"
Constants.RADIO_SCREEN_LABEL = "TextLabel"
Constants.RADIO_SCREEN_LIGHT = "SpotLight"
-- BaseParts named 1..6; players are placed on them in arrival order
Constants.CAMP_SPAWNS_FOLDER = "Spawns"
-- Camp.Mine.Entrance: an anchored part whose position is the mine origin and
-- whose look direction (snapped to an axis) is the mine facing
Constants.CAMP_MINE_FOLDER = "Mine"
Constants.MINE_ENTRANCE_PART = "Entrance"
-- Camp.Refinery: a Model; refining is automatic within a radius of its
-- bounding box (RefineryManager, 2026-10-01), and its top is where the
-- client's ore icons fly to
Constants.CAMP_REFINERY_MODEL = "Refinery"
-- Camp.MiningStore.Stands: one "<Item>Stand" Model per Enums.StoreItem
-- (the name comes from StoreRules.standNameForItem), each with a Base part
-- carrying the SurfaceGui the client fills in and the ProximityPrompt the
-- server listens to, and an ItemSpawn part where the client spins the
-- display model; the folder keeps them apart from the building (2026-10-01)
Constants.CAMP_MINING_STORE_MODEL = "MiningStore"
Constants.MINING_STORE_STANDS_FOLDER = "Stands"
Constants.STAND_BASE_PART = "Base"
Constants.STAND_ITEM_SPAWN_PART = "ItemSpawn"
Constants.STAND_GUI = "SurfaceGui"
Constants.STAND_NAME_LABEL = "NameLabel"
Constants.STAND_PRICE_BOX = "PriceBox"
Constants.STAND_PRICE_LABEL = "Price"
Constants.STAND_RESOURCE_ICON = "ResourceIcon"
-- "Camp Level N required" under the price on an upgrade stand, shown in red only while unmet
Constants.STAND_CAMP_LEVEL_LABEL = "CampLevel"
-- display models for the store stands under GameAssets: "<KEY>_<level>" for
-- upgrade tracks and "<KEY>" for consumables (scripts/studio/build_store_displays.luau)
Constants.STORE_DISPLAY_TEMPLATES_FOLDER = "StoreDisplays"
-- Camp.DefenseStore: the defense building, which holds every defense menu
-- (decided 2026-10-01): a Tables folder with one designer-authored Model
-- per table, each with an anchored Prompt part the owning server manager
-- puts the ProximityPrompt on. TowerTable enters Build Mode
-- (DefenseTableManager), PostUpgradeTable opens the post upgrade menu
-- (PostManager, ClientPostUpgradeManager), WeaponUpgradeTable the weapon
-- upgrade menu (WeaponManager, ClientWeaponUpgradeManager), and WallsTable
-- takes Iron toward the fortification tier (StructureManager)
Constants.CAMP_DEFENSE_STORE_MODEL = "DefenseStore"
Constants.DEFENSE_TABLES_FOLDER = "Tables"
Constants.TOWER_TABLE_MODEL = "TowerTable"
Constants.POST_UPGRADE_TABLE_MODEL = "PostUpgradeTable"
Constants.WEAPON_UPGRADE_TABLE_MODEL = "WeaponUpgradeTable"
Constants.WALLS_TABLE_MODEL = "WallsTable"
Constants.DEFENSE_TABLE_PROMPT_PART = "Prompt"
-- inside WallsTable: the Gui part the Fortifications sign is centred on,
-- placed by the designer (its position is the sign's), and the small
-- model of the camp's wall line
Constants.DEFENSE_TABLE_GUI_PART = "Gui"
Constants.WALLS_TABLE_WALL_MODEL = "WallModel"
-- inside PostUpgradeTable: the small post model the designer placed, which
-- sets the display's spot and size; each client redraws it locally as the
-- current tier's post with its own loadout post weapon on top, display only
Constants.POST_UPGRADE_TABLE_DISPLAY_POST = "DisplayPost"
-- Camp.DefensiveZones (M26): one anchored BasePart per Defensive Zone; its
-- top face is the build surface and its size and rotation define the grid
-- (PlacementRules.measureZone). PlacementManager numbers them by name
Constants.CAMP_DEFENSIVE_ZONES_FOLDER = "DefensiveZones"
-- Tower and Trap models under GameAssets, one per Enums.TowerKind /
-- Enums.TrapKind key, each a Model whose pivot is the centre of its base
-- (scripts/studio/build_tower_templates.luau, build_trap_templates.luau)
Constants.TOWER_TEMPLATES_FOLDER = "Towers"
Constants.TRAP_TEMPLATES_FOLDER = "Traps"
-- Monster puppets under GameAssets (M29), one per monster kind key: a
-- Humanoid-free rig the client moves by its anchored root, plus a one-part
-- Proxy drawn in its place far away (scripts/studio/build_monster_templates.luau)
Constants.MONSTER_TEMPLATES_FOLDER = "Monsters"
Constants.MONSTER_PROXY_PART = "Proxy"
-- the one-part baked body a template may carry for the middle distance
Constants.MONSTER_HELD_PART = "Held"
-- Camp.WaveAreas and Camp.CampArea (M29): anchored parts whose footprints
-- are where monsters may walk (GDD "Wave Area"); MonsterPathManager lays
-- one grid over all of them. Camp.MonsterSpawns holds one part per spawn
-- location, named by its number ("1", "2", ...)
Constants.CAMP_WAVE_AREAS_FOLDER = "WaveAreas"
Constants.CAMP_CAMP_AREA_FOLDER = "CampArea"
Constants.CAMP_MONSTER_SPAWNS_FOLDER = "MonsterSpawns"
-- the monster position stream's UnreliableRemoteEvent, created by the server
Constants.MONSTER_SNAPSHOT_EVENT_NAME = "MonsterSnapshotEvent"
-- the client-only Workspace folders of placement bodies and grid lines
Constants.PLACEMENT_BODIES_FOLDER = "PlacementBodies"
Constants.PLACEMENT_GRID_FOLDER = "PlacementGrid"
-- Build Mode's two ScreenGuis (scripts/studio/build_build_bar_gui.luau),
-- shown while the player is at the Defense Table. BuildSurface sits under
-- every HUD and is one invisible full-screen Modal button: it frees the
-- first-person mouse and hears every tap and drag on the world
Constants.BUILD_SURFACE_GUI_NAME = "BuildSurface"
Constants.BUILD_SURFACE_BUTTON = "Surface"
-- BuildBar: the scrolling row of Tower and Trap entries along the bottom,
-- the Exit button, the Tower counter, the hint, and the two panels that
-- float beside what they act on
Constants.BUILD_BAR_GUI_NAME = "BuildBar"
Constants.BUILD_BAR_ENTRIES_FRAME = "Entries"
Constants.BUILD_BAR_ENTRY_TEMPLATE = "EntryTemplate"
-- the square slot, styled like a tool bar slot: the item's picture inside,
-- the kind (Tower or Trap) as a small icon top-left, the number key top-right
Constants.BUILD_BAR_ENTRY_SLOT = "Slot"
Constants.BUILD_BAR_ENTRY_ICON = "Icon"
Constants.BUILD_BAR_ENTRY_TYPE_ICON = "TypeIcon"
Constants.BUILD_BAR_ENTRY_NAME_LABEL = "NameLabel"
Constants.BUILD_BAR_ENTRY_PRICE_ROW = "PriceRow"
Constants.BUILD_BAR_ENTRY_PRICE_ICON = "ResourceIcon"
Constants.BUILD_BAR_ENTRY_PRICE_LABEL = "Price"
Constants.BUILD_BAR_ENTRY_KEY_LABEL = "KeyLabel"
-- always up in Build Mode: "EXIT", back to the character at the table
Constants.BUILD_BAR_EXIT_BUTTON = "ExitButton"
-- floats under the ghost: Place with the Iron price, and Cancel to put the
-- ghost away
Constants.BUILD_BAR_PLACE_PANEL = "PlacePanel"
Constants.BUILD_BAR_PLACE_BUTTON = "PlaceButton"
Constants.BUILD_BAR_CANCEL_BUTTON = "CancelButton"
Constants.BUILD_BAR_ROTATE_BUTTON = "RotateButton"
-- floats under one of the player's own Traps once tapped: Sell with the
-- Iron it returns, and Close
Constants.BUILD_BAR_SELL_PANEL = "SellPanel"
Constants.BUILD_BAR_SELL_BUTTON = "SellButton"
-- beside Sell: picks the Trap up as a ghost to set down on other cells
Constants.BUILD_BAR_MOVE_BUTTON = "MoveButton"
Constants.BUILD_BAR_CLOSE_BUTTON = "CloseButton"
-- inside the Place and Sell buttons (and the Tower Menu's Upgrade button):
-- the word, then the Iron icon and the number
Constants.BUILD_BAR_BUILD_PRICE_ROW = "PriceRow"
Constants.BUILD_BAR_BUILD_PRICE_ICON = "ResourceIcon"
Constants.BUILD_BAR_BUILD_PRICE_LABEL = "Price"
Constants.BUILD_BAR_BUILD_TEXT_LABEL = "Text"
-- one line of guidance near the top: what a tap does right now
Constants.BUILD_BAR_HINT_LABEL = "Hint"
-- "2 / 5" beside a Tower icon: Towers standing against the per-player limit
Constants.BUILD_BAR_TOWER_COUNT_FRAME = "TowerCount"
Constants.BUILD_BAR_TOWER_COUNT_ICON = "Icon"
Constants.BUILD_BAR_TOWER_COUNT_LABEL = "Label"
-- the TowerMenu ScreenGui (scripts/studio/build_tower_menu_gui.luau): the
-- owner's Upgrade/Sell menu in the tower defense layout
Constants.TOWER_MENU_GUI_NAME = "TowerMenu"
Constants.TOWER_MENU_DIALOG = "Dialog"
Constants.TOWER_MENU_CLOSE_BUTTON = "CloseButton"
Constants.TOWER_MENU_PORTRAIT = "Portrait"
Constants.TOWER_MENU_NAME_LABEL = "NameLabel"
Constants.TOWER_MENU_LEVEL_LABEL = "LevelLabel"
Constants.TOWER_MENU_PRIORITY_FRAME = "Priority"
Constants.TOWER_MENU_PRIORITY_VALUE_LABEL = "ValueLabel"
Constants.TOWER_MENU_STATS_FRAME = "Stats"
Constants.TOWER_MENU_STAT_ROW_TEMPLATE = "RowTemplate"
Constants.TOWER_MENU_STAT_NAME_LABEL = "NameLabel"
Constants.TOWER_MENU_STAT_VALUE_LABEL = "ValueLabel"
Constants.TOWER_MENU_STAT_NEXT_LABEL = "NextLabel"
Constants.TOWER_MENU_STAT_ARROW_LABEL = "ArrowLabel"
Constants.TOWER_MENU_SELL_BUTTON = "SellButton"
-- beside Sell: closes the menu and picks the Tower up to set down elsewhere
Constants.TOWER_MENU_MOVE_BUTTON = "MoveButton"
Constants.TOWER_MENU_UPGRADE_BUTTON = "UpgradeButton"
Constants.TOWER_MENU_UPGRADE_NAME_LABEL = "NameLabel"
Constants.TOWER_MENU_UPGRADE_PRICE_ROW = "PriceRow"
Constants.TOWER_MENU_PIPS = "Pips"
Constants.TOWER_MENU_PIP_PREFIX = "Pip"
Constants.TOWER_MENU_UPGRADE_STATS_FRAME = "UpgradeStats"
-- the info billboard every placement carries
-- (scripts/studio/build_placement_billboard.luau): name, HP bar, owner
Constants.PLACEMENT_INFO_BILLBOARD = "PlacementInfo"
Constants.PLACEMENT_INFO_ROOT_FRAME = "Root"
Constants.PLACEMENT_INFO_NAME_LABEL = "NameLabel"
Constants.PLACEMENT_INFO_BAR = "Bar"
Constants.PLACEMENT_INFO_FILL = "Fill"
Constants.PLACEMENT_INFO_OWNER_LABEL = "OwnerLabel"
-- Camp.Walls (Wall1..n), Camp.Posts (Post1..n) and Camp.Gate are placement
-- markers (M23): at run start the server swaps each for the fortification
-- tier's template at the marker's pivot, and again on upgrade or destruction
Constants.CAMP_WALLS_FOLDER = "Walls"
Constants.CAMP_POSTS_FOLDER = "Posts"
Constants.CAMP_GATE_MODEL = "Gate"
Constants.WALL_NAME_PREFIX = "Wall"
Constants.POST_NAME_PREFIX = "Post"
-- inside every post template: Sign (Model) > Sign (Part) > SurfaceGui >
-- DefensePostNumber, which the server fills in with the post's number
Constants.POST_SIGN_MODEL = "Sign"
Constants.POST_SIGN_PART = "Sign"
Constants.POST_SIGN_NUMBER_LABEL = "DefensePostNumber"
-- the rest of the sign (M25): "UNCLAIMED" plus the claim price row while nobody
-- owns it; the owner's headshot, display name, and weapon name once claimed
Constants.POST_SIGN_UNCLAIMED_LABEL = "Unclaimed"
-- the row under it, "CLAIM FOR" + Gold Bar icon + number (decided 2026-09-18);
-- a client that already owns a post hides it on every sign
Constants.POST_SIGN_THUMBNAIL = "PlayerThumbnail"
Constants.POST_SIGN_DISPLAY_NAME_LABEL = "DisplayName"
Constants.POST_SIGN_POST_TYPE_LABEL = "PostType"
-- inside every post template: the Spawn cylinder the claimed weapon stands
-- on (its X axis is up, its +Z faces out of the camp)
Constants.POST_SPAWN_PART = "Spawn"
-- post weapon models under GameAssets, one per Enums.PostWeaponKind key.
-- Each is a Model whose PrimaryPart is its own Spawn cylinder (matched to
-- the post's), with CharacterSpawn (the gunner's feet, carrying the Use
-- prompt), HandleLeft / HandleRight (the hands), CameraLocation (welded to
-- the gun), and one MeshPart gun carrying the MuzzleAttachment; the gun is
-- the part that tilts
Constants.POST_WEAPON_TEMPLATES_FOLDER = "PostWeapons"
Constants.POST_WEAPON_CHARACTER_SPAWN_PART = "CharacterSpawn"
Constants.POST_WEAPON_HANDLE_LEFT_PART = "HandleLeft"
Constants.POST_WEAPON_HANDLE_RIGHT_PART = "HandleRight"
Constants.POST_WEAPON_CAMERA_PART = "CameraLocation"
Constants.POST_WEAPON_MUZZLE_ATTACHMENT = "MuzzleAttachment"
-- projectile models under GameAssets (a rocket): one part with a
-- TailAttachment; the nose is the far end from it. The trail is authored
-- as ParticleEmitters (and lights) under the attachment; a bare attachment
-- gets a placeholder trail. Clients clone and fly them; the server flies
-- only numbers
Constants.PROJECTILE_TEMPLATES_FOLDER = "Projectiles"
-- burst effects under GameAssets/Effects: an anchored part whose
-- ParticleEmitters each fire their BurstCount attribute of particles once
-- and whose lights flash for BLAST_FLASH_SEC; a missing one gets a
-- placeholder blast
Constants.EFFECT_TEMPLATES_FOLDER = "Effects"
Constants.PROJECTILE_TAIL_ATTACHMENT = "TailAttachment"
-- the folder in the camp the server parents spawned weapons and benches to
Constants.CAMP_POST_WEAPONS_FOLDER = "PostWeapons"
-- the camp children a bullet flies straight through (decided 2026-09-30:
-- the wall line curves and a post must be able to cover every wall, so the
-- fortifications and the mounted guns never stop a hitscan shot; rockets
-- still burst on them)
Constants.BULLET_PASS_THROUGH_CAMP_CHILDREN = {
	Constants.CAMP_WALLS_FOLDER,
	Constants.CAMP_POSTS_FOLDER,
	Constants.CAMP_GATE_MODEL,
	Constants.CAMP_POST_WEAPONS_FOLDER,
}
-- the PostHud ScreenGui (scripts/studio/build_post_hud_gui.luau): the touch
-- Fire button, the touch Exit button that stands in for the hidden jump
-- button, and the "how to exit" hint for keyboard and gamepad
Constants.POST_HUD_GUI_NAME = "PostHud"
Constants.POST_HUD_EXIT_BUTTON = "ExitButton"
Constants.POST_HUD_FIRE_BUTTON = "FireButton"
Constants.POST_HUD_EXIT_HINT_LABEL = "ExitHint"
-- the weapon's own reticle image, centred; shown only for kinds with one in Icons
Constants.POST_HUD_RETICLE = "Reticle"
-- the status bar under the reticle: heat for a gun that overheats, the
-- reload for one that reloads
Constants.POST_HUD_STATUS_BAR = "StatusBar"
Constants.POST_HUD_STATUS_FILL = "Fill"
-- above the bar: "OVERHEATED" or "RELOADING" while that is so, else hidden
Constants.POST_HUD_STATUS_LABEL = "StatusLabel"
-- the upgrade menu ScreenGuis: PostUpgrade
-- (scripts/studio/build_post_upgrade_menu_gui.luau) and WeaponUpgrade, a
-- copy of it (scripts/studio/build_weapon_upgrade_menu_gui.luau); both
-- share the child names below
Constants.POST_UPGRADE_GUI_NAME = "PostUpgrade"
Constants.WEAPON_UPGRADE_GUI_NAME = "WeaponUpgrade"
Constants.UPGRADE_MENU_DIALOG = "Dialog"
Constants.UPGRADE_MENU_TITLE_LABEL = "Title"
Constants.UPGRADE_MENU_LIST = "List"
Constants.UPGRADE_MENU_ROW_TEMPLATE = "RowTemplate"
Constants.UPGRADE_MENU_ROW_NAME_LABEL = "Name"
Constants.UPGRADE_MENU_ROW_PIPS = "Pips"
Constants.UPGRADE_MENU_ROW_PIP_PREFIX = "Pip"
Constants.UPGRADE_MENU_ROW_BUTTON = "UpgradeButton"
Constants.UPGRADE_MENU_ROW_PRICE_LABEL = "Price"
Constants.UPGRADE_MENU_ROW_RESOURCE_ICON = "ResourceIcon"
Constants.UPGRADE_MENU_ROW_LOCK_LABEL = "Lock"
Constants.UPGRADE_MENU_CLOSE_BUTTON = "CloseButton"
-- inside every gate template: the two leaves, authored shut, and a marker
-- part per leaf ("DoorLeftOpen") whose CFrame is its open pose; a Closed
-- marker is optional and overrides the leaf's own pose
Constants.GATE_DOOR_MODEL = "GateDoor"
Constants.GATE_DOOR_LEFT_PART = "DoorLeft"
Constants.GATE_DOOR_RIGHT_PART = "DoorRight"
Constants.GATE_DOOR_OPEN_SUFFIX = "Open"
Constants.GATE_DOOR_CLOSED_SUFFIX = "Closed"
-- fortification templates under GameAssets: "WALL_<tier>", "GATE_<tier>",
-- "POST_<tier>", plus "WALL_RUBBLE" and "GATE_RUBBLE" for a destroyed one
-- (scripts/studio/build_structure_templates.luau)
Constants.STRUCTURE_TEMPLATES_FOLDER = "Structures"
Constants.STRUCTURE_RUBBLE_SUFFIX = "RUBBLE"
Constants.POST_TEMPLATE_PREFIX = "POST"
-- "WALL_<tier>" and "GATE_<tier>" beside them
Constants.WALL_TEMPLATE_PREFIX = "WALL"
Constants.GATE_TEMPLATE_PREFIX = "GATE"
-- optional per-map terrain: the part bounding the terrain to snapshot and
-- the TerrainRegion the snapshot is stored in (scripts/studio/map_tools.luau)
Constants.MAP_TERRAIN_BOUNDS_PART = "TerrainBounds"
Constants.MAP_TERRAIN_REGION = "TerrainSnapshot"
-- the Edit-mode mine preview map_tools.luau draws in Workspace; MapManager
-- removes it at run start so a designer's guide never shows in Play
Constants.MINE_PREVIEW_FOLDER = "MinePreview"
-- rock templates under GameAssets, one per Enums.RockName key; clients clone
-- them into the client-only MineBlocks folder in Workspace
Constants.ROCK_TEMPLATES_FOLDER = "Rocks"
Constants.MINE_BLOCKS_FOLDER = "MineBlocks"
-- the GDD fixes every rock as a 4-stud cube; structural, not tuning
Constants.MINE_BLOCK_SIZE_STUDS = 4
-- the invisible collider ClearanceManager welds over every character's
-- head, so a mine passage has to be two blocks tall
Constants.CHARACTER_CLEARANCE_PART = "Clearance"
-- held tool models under GameAssets, one per Enums.ToolKind key, each with a
-- Handle part the client welds to the character's right hand
-- the pick axe has one model per level, "PICK_AXE_<level>"
Constants.TOOL_TEMPLATES_FOLDER = "Tools"
Constants.TOOL_HANDLE_PART = "Handle"
-- the jet pack worn on the back (GameAssets/Wearables/JET_PACK) and the
-- attachment its Handle welds to; its Flame part is shown while burning
Constants.WEARABLE_TEMPLATES_FOLDER = "Wearables"
Constants.JET_PACK_TEMPLATE = "JET_PACK"
Constants.JET_PACK_FLAME_PART = "Flame"
-- the custom tool bar (built by scripts/studio/build_tool_bar_gui.luau)
Constants.TOOL_BAR_GUI_NAME = "ToolBar"
Constants.TOOL_BAR_SLOTS_FRAME = "Slots"
Constants.TOOL_BAR_SLOT_TEMPLATE = "SlotTemplate"
Constants.TOOL_SLOT_ICON = "Icon"
Constants.TOOL_SLOT_LABEL = "Label"
Constants.TOOL_SLOT_KEY_LABEL = "KeyLabel"
Constants.TOOL_SLOT_COUNT_LABEL = "CountLabel"
-- the action word under each slot ("MINE", "SHOOT", ...), outside the square
Constants.TOOL_SLOT_CAPTION_LABEL = "CaptionLabel"
Constants.MAX_TOOL_SLOTS = 9
-- mining mode HUD (built by scripts/studio/build_mining_hud_gui.luau)
Constants.MINING_HUD_GUI_NAME = "MiningHud"
Constants.MINING_RETICLE = "Reticle"
Constants.MINING_TARGET_LABEL = "TargetLabel"
-- the rock's remaining HP as a bar under the name, no numbers (decided 2026-09-15)
Constants.MINING_TARGET_BAR = "TargetBar"
Constants.MINING_TARGET_FILL = "Fill"
-- gameplay HUD (built by scripts/studio/build_gameplay_hud_gui.luau)
-- the day clock (M28): its own HUD ScreenGui top centre
Constants.DAY_CLOCK_GUI_NAME = "DayClock"
Constants.DAY_CLOCK_ROOT_FRAME = "Root"
Constants.DAY_CLOCK_PHASE_ICON = "PhaseIcon"
-- one picture and one gradient per Enums.ClockPhase under PhaseIcon; the
-- client shows the pair for the current phase and hides the rest
Constants.DAY_CLOCK_PHASE_ICON_DAY = "IconDay"
Constants.DAY_CLOCK_PHASE_ICON_DUSK = "IconDusk"
Constants.DAY_CLOCK_PHASE_ICON_NIGHT = "IconNight"
Constants.DAY_CLOCK_PHASE_GRADIENT_DAY = "UIGradientDay"
Constants.DAY_CLOCK_PHASE_GRADIENT_DUSK = "UIGradientDusk"
Constants.DAY_CLOCK_PHASE_GRADIENT_NIGHT = "UIGradientNight"
Constants.DAY_CLOCK_BAR = "Bar"
Constants.DAY_CLOCK_FILL = "Fill"
Constants.DAY_CLOCK_DAY_LABEL = "DayLabel"
-- the compass (scripts/studio/build_compass_gui.luau): a locator bar hung
-- directly under the day clock. Markers slide along the Markers frame: the
-- one HomeIcon (the Refinery) and a clone of PlayerDotTemplate per
-- crewmate; each carries an up and a down arrow for a target above or below
Constants.COMPASS_GUI_NAME = "Compass"
Constants.COMPASS_ROOT_FRAME = "Root"
Constants.COMPASS_BAR = "Bar"
Constants.COMPASS_MARKERS_FRAME = "Markers"
Constants.COMPASS_HOME_ICON = "HomeIcon"
Constants.COMPASS_PLAYER_DOT_TEMPLATE = "PlayerDotTemplate"
Constants.COMPASS_ARROW_UP = "ArrowUp"
Constants.COMPASS_ARROW_DOWN = "ArrowDown"
-- the Geiger Counter (scripts/studio/build_geiger_counter_gui.luau): a
-- round dial to the right of the day clock, shown in mining mode. The raw
-- uranium icon sits in the middle of three rings, Ring1 (inner) to Ring3
-- (outer); the client shows as many as GeigerRules says are lit
Constants.GEIGER_COUNTER_GUI_NAME = "GeigerCounter"
Constants.GEIGER_COUNTER_ROOT_FRAME = "Root"
Constants.GEIGER_COUNTER_DIAL = "Dial"
Constants.GEIGER_COUNTER_ICON = "Icon"
Constants.GEIGER_COUNTER_RING_PREFIX = "Ring"
-- a crewmate's name over their head in their compass dot colour
-- (GameAssets/Gui/PlayerName, scripts/studio/build_player_name_billboard.luau)
Constants.PLAYER_NAME_BILLBOARD = "PlayerName"
Constants.PLAYER_NAME_LABEL = "NameLabel"
-- the "DAY N" / "NIGHT N" card shown for a moment at every dawn and dusk
-- (designer-authored ScreenGui, M28)
Constants.DAY_NIGHT_NUMBER_GUI_NAME = "DayNightNumber"
Constants.DAY_NIGHT_NUMBER_LABEL = "TextLabel"
Constants.GAMEPLAY_HUD_GUI_NAME = "GameplayHud"
-- the right-edge stack, hung from the top-right corner: the backpack button
-- with the jet pack bar directly under it (decided 2026-09-15; both always
-- visible; moved to the top on 2026-09-16 so it clears the touch buttons)
Constants.HUD_RIGHT_STACK = "RightStack"
Constants.HUD_BACKPACK_BUTTON = "BackpackButton"
Constants.HUD_BACKPACK_ICON = "Icon"
Constants.HUD_BACKPACK_COUNT_LABEL = "CountLabel"
Constants.HUD_BACKPACK_FULL_LABEL = "FullLabel"
-- jet pack fuel bar under the backpack button: an icon on the left and the
-- fill track beside it; the touch-only burn button sits above the jump button
Constants.HUD_JET_PACK_BAR = "JetPackBar"
Constants.HUD_JET_PACK_ICON = "Icon"
Constants.HUD_JET_PACK_TRACK = "Track"
Constants.HUD_JET_PACK_FILL = "Fill"
Constants.HUD_JET_PACK_BUTTON = "JetPackButton"
-- touch-only action button beside the jump button: one button that does
-- whatever the equipped tool does (swing, throw, place), so moving the
-- camera never swings the pick axe (decided 2026-09-16)
Constants.HUD_ACTION_BUTTON = "ActionButton"
Constants.HUD_ACTION_ICON = "Icon"
Constants.HUD_ACTION_LABEL = "Label"
-- balances (top left): one row per resource, Uranium as "total / target"
Constants.HUD_BALANCES_FRAME = "Balances"
Constants.HUD_BALANCE_IRON_ROW = "IronRow"
Constants.HUD_BALANCE_GOLD_ROW = "GoldRow"
Constants.HUD_BALANCE_URANIUM_ROW = "UraniumRow"
Constants.HUD_BALANCE_ICON = "Icon"
Constants.HUD_BALANCE_VALUE_LABEL = "ValueLabel"
-- BillboardGui and SurfaceGui templates under GameAssets, cloned by clients
Constants.GUI_TEMPLATES_FOLDER = "Gui"
Constants.CAMP_LEVEL_ICON = "Icon"
-- how far above the Refinery's top the billboard floats, in studs
-- the sign floated above the Walls Table: tier title, the shared Iron pool as
-- a bar reading "pool / required", and the Camp Level lock line
-- (scripts/studio/build_fortification_billboard.luau)
Constants.FORTIFICATION_BILLBOARD = "Fortification"
Constants.FORTIFICATION_ROOT_FRAME = "Root"
Constants.FORTIFICATION_TITLE_LABEL = "TitleLabel"
Constants.FORTIFICATION_BAR = "Bar"
Constants.FORTIFICATION_FILL = "Fill"
Constants.FORTIFICATION_PROGRESS_LABEL = "ProgressLabel"
Constants.FORTIFICATION_ICON = "Icon"
Constants.FORTIFICATION_LOCK_LABEL = "LockLabel"
-- the Repair Mode HP bar cloned onto every structure shadow while the Hammer
-- is equipped (scripts/studio/build_structure_hp_billboard.luau)
Constants.STRUCTURE_HP_BILLBOARD = "StructureHp"
-- the Refinery's own copy of it: the name half as big again inside a
-- NameRow, beside the compass's home icon (2026-09-30)
Constants.STRUCTURE_HP_REFINERY_BILLBOARD = "RefineryHp"
Constants.STRUCTURE_HP_NAME_ROW = "NameRow"
Constants.STRUCTURE_HP_HOME_ICON = "HomeIcon"
Constants.STRUCTURE_HP_ROOT_FRAME = "Root"
Constants.STRUCTURE_HP_NAME_LABEL = "NameLabel"
Constants.STRUCTURE_HP_BAR = "Bar"
Constants.STRUCTURE_HP_FILL = "Fill"
Constants.STRUCTURE_HP_VALUE_LABEL = "ValueLabel"
-- under the bar, only on the structure under the reticle: what a swing
-- costs, as "4 [Iron Bar icon] for 10 HP"
Constants.STRUCTURE_HP_COST_ROW = "CostRow"
Constants.STRUCTURE_HP_COST_AMOUNT_LABEL = "AmountLabel"
Constants.STRUCTURE_HP_COST_ICON = "Icon"
Constants.STRUCTURE_HP_COST_GAIN_LABEL = "GainLabel"
-- the Refinery's HP bar floats this far above the model's top (the spot
-- the Camp Level billboard had until 2026-09-29)
Constants.REFINERY_HP_BILLBOARD_LIFT_STUDS = 5.5
-- the radio's sign (M31), GameAssets/Gui/RescueRadio
Constants.RESCUE_RADIO_BILLBOARD = "RescueRadio"
Constants.RESCUE_RADIO_ROOT_FRAME = "Root"
Constants.RESCUE_RADIO_TITLE_LABEL = "TitleLabel"
Constants.RESCUE_RADIO_URANIUM_ROW = "UraniumRow"
Constants.RESCUE_RADIO_URANIUM_ICON = "Icon"
Constants.RESCUE_RADIO_URANIUM_LABEL = "UraniumLabel"
Constants.RESCUE_RADIO_STATUS_LABEL = "StatusLabel"
-- full-screen frame the refinery's flying icons are parented to, and the
-- hidden ImageLabel inside it that ClientIconFlightManager clones per icon
Constants.HUD_FLY_LAYER = "FlyLayer"
Constants.HUD_FLY_ICON_TEMPLATE = "FlyIconTemplate"
-- the world-space flight icon (GameAssets/Gui/FlightIcon, built by
-- scripts/studio/build_flight_icon_billboard.luau): ore into the Refinery
-- and bars out of it fly through the world, so a moving camera cannot
-- strand them (2026-09-29). The clones ride throwaway parts in a
-- workspace folder of this name
Constants.FLIGHT_ICON_BILLBOARD = "FlightIcon"
Constants.FLIGHT_ICON_IMAGE = "Icon"
Constants.FLIGHT_ICON_FOLDER = "FlightIcons"
-- the ore icon on each face of a ground pickup's plate (GameAssets/Gui/
-- OrePickupFace, built by scripts/studio/build_ore_pickup_face_gui.luau):
-- a lit SurfaceGui, since a Decal read dark in the mine (2026-09-29)
Constants.ORE_PICKUP_FACE_GUI = "OrePickupFace"
Constants.ORE_PICKUP_FACE_IMAGE = "Icon"
-- backpack contents menu (built by scripts/studio/build_backpack_menu_gui.luau)
Constants.BACKPACK_MENU_GUI_NAME = "Backpack"
Constants.BACKPACK_MENU_LIST = "List"
Constants.BACKPACK_MENU_ROW_TEMPLATE = "RowTemplate"
Constants.BACKPACK_ROW_ICON = "Icon"
Constants.BACKPACK_ROW_NAME_LABEL = "NameLabel"
Constants.BACKPACK_ROW_AMOUNT_LABEL = "AmountLabel"
Constants.BACKPACK_MENU_EMPTY_LABEL = "EmptyLabel"
Constants.BACKPACK_MENU_CLOSE_BUTTON = "CloseButton"
-- server folder holding ore pickup shadow parts
Constants.ORE_PICKUPS_FOLDER = "OrePickups"
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

-- on every weapon template: an Attachment at the barrel tip, where tracers
-- start (scripts/studio/build_tool_templates.luau)
Constants.WEAPON_MUZZLE_ATTACHMENT = "Muzzle"
-- under the Muzzle attachment, both authored switched off: a light and a
-- smoke emitter the client turns on for a moment on every shot
Constants.WEAPON_MUZZLE_FLASH_LIGHT = "MuzzleFlash"
Constants.WEAPON_MUZZLE_SMOKE_EMITTER = "MuzzleSmoke"

-- GameAssets/Effects: designer-authored looks for effects the client
-- builds, starting with the bullet hole Decal (ClientImpactManager)
Constants.EFFECT_TEMPLATES_FOLDER = "Effects"
Constants.BULLET_HOLE_DECAL = "BulletHole"
-- the client-only workspace folder of damageable targets' visible bodies
Constants.DAMAGEABLE_BODIES_FOLDER = "DamageableBodies"

-- the Weapon Mode ammo readout (scripts/studio/build_weapon_hud_gui.luau);
-- tapping it reloads
Constants.WEAPON_HUD_GUI_NAME = "WeaponHud"
Constants.WEAPON_HUD_AMMO_BUTTON = "AmmoButton"
Constants.WEAPON_HUD_AMMO_LABEL = "AmmoLabel"

return Constants
