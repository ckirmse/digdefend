--!strict

local Enums = require(script.Parent.Enums)

local Constants = {}

Constants.LOBBY_PLACE_ID = 133996405589098
Constants.GAMEPLAY_PLACE_ID = 72646464251078

Constants.SPLENDID_GAMES_NAME = "SplendidGames"
Constants.GAME_METADATA_FOLDER = "GameMetadata"
Constants.ALL_PLAYERS_FOLDER = "AllPlayers"
Constants.CURRENT_PLAYER_FOLDER = "CurrentPlayer"
-- CurrentPlayer sub-folder: Completions holds name-only marker folders.
-- OwnedUnlocks went with the bought-unlock loadout on 2026-10-12, the
-- Characters folder with the Class Menu on 2026-11-04 (class records
-- travel as one attribute now)
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
-- top-centre blue box for the beats nobody should miss (a day's start)
-- red box under the announcement for danger (a wall down, the Refinery
-- under attack; 2026-09-25)
Constants.PLAYER_FEEDBACK_LABEL = "Message"
-- the resource icon a message can end with ("+5 [diamond]", M33), after the words
Constants.PLAYER_FEEDBACK_ICON = "Icon"
Constants.HUD_GUI_NAME = "HUD"
Constants.HUD_DIAMOND_WALLET = "DiamondWallet"
Constants.HUD_DIAMOND_AMOUNT_LABEL = "DiamondAmount"
-- the Keys wallet beside it (designer, 2026-11-03): shown only while the
-- player holds any Keys; the two are centred as a group (ClientHudManager)
Constants.HUD_KEYS_WALLET = "KeysWallet"
Constants.HUD_KEYS_AMOUNT_LABEL = "KeysAmount"
Constants.HUD_MENU_BUTTONS = "MenuButtons"
Constants.HUD_STORE_BUTTON = "StoreButton"
-- shown in the Store button's place for a player restricted from paid
-- random items; opens the rotating store
Constants.HUD_ROTATING_STORE_BUTTON = "RotatingStoreButton"
-- the Loadout button until 2026-10-12 (M37), the Character button until
-- 2026-10-30, ClassesButton until the designer's restyle of 2026-11-09: it
-- opens the Class Menu. The Daily Rewards button left the HUD on
-- 2026-10-30 (post launch, M39)
Constants.HUD_CLASSES_BUTTON = "ClassButton"
-- opens the Gear Locker (designer, 2026-11-09)
Constants.HUD_GEAR_BUTTON = "GearButton"
-- the picture on a menu button: the Store's crate, the Gear's locker art,
-- and on the Class button the equipped class's own icon, which
-- ClientHudManager keeps current (designer, 2026-11-09)
Constants.HUD_MENU_BUTTON_ICON = "Icon"
-- the hidden controller button picture to the left of each menu button (M72)
Constants.HUD_MENU_BUTTON_GAMEPAD_GLYPH = "GamepadGlyph"
-- SoundService layout (designer-authored in both places): AudioPlayers under
-- these folders, each wired to the AudioDeviceOutput; see SoundNames
-- how long a client manager waits for a Studio-authored instance (a
-- ScreenGui copied into PlayerGui at spawn, a billboard on a streamed
-- part) before warning that it is missing. On a live server the client
-- starts ahead of both, so a plain find misses them (2026-10-13: the
-- character menus and the pad billboards never appeared for a tester)
Constants.GUI_WAIT_SEC = 10
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
-- the designer's full-panel line shown alone while a host sets a run up (2026-10-09)
Constants.PAD_GUI_CONFIGURING_LABEL = "Configuring"
-- "LEAVING IN: Xs" while a party boards, hidden otherwise (designer, 2026-10-30)
Constants.PAD_GUI_TIMER_LABEL = "Timer"
-- helicopter template under GameAssets; the clone on a pad keeps the name
Constants.HELICOPTER_TEMPLATE = "Helicopter"
Constants.HELICOPTER_PLAYER_SPAWNS_FOLDER = "PlayerSpawns"
-- a launched helicopter is renamed to this while clients fly it away
Constants.DEPARTED_HELICOPTER_NAME = "DepartedHelicopter"
-- authored on the template (M75): the Board prompt the rescue enables once
-- it has landed, and the SpotLight lit on the way in
Constants.HELICOPTER_BOARD_PROMPT = "BoardPrompt"
Constants.HELICOPTER_SEARCHLIGHT = "Searchlight"
-- on the camp's HelicopterPad (M75): the part carrying the touchdown dust
-- emitter (every flight runs along the pad's own facing since
-- 2026-10-27, so no heading part)
Constants.PAD_DUST_PART = "Dust"
-- the rider's fixed shots (2026-10-27): where the camera sits once seated,
-- and where it ends after rising with the lift-off
Constants.PAD_RIDE_CAMERA_START_PART = "RideCameraStart"
Constants.PAD_RIDE_CAMERA_END_PART = "RideCameraEnd"
-- and where it drifts to over the rest of the ride, reached as the
-- Results Menu comes (2026-10-27)
Constants.PAD_RIDE_CAMERA_FINAL_PART = "RideCameraFinal"

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
-- death and revives (M32). Camp.Cemetery.Plots holds BaseParts named 1..6,
-- each the size and pose of the Grave template's Ground: a dead player's
-- grave is laid on the lowest free one, and a revived player appears on
-- it. Workspace.DeathRoom
-- exists once in the gameplay place (not per map), a closed room far from
-- every camp whose Spawn part a dead character is moved onto
Constants.CAMP_CEMETERY_FOLDER = "Cemetery"
Constants.CEMETERY_PLOTS_FOLDER = "Plots"
Constants.CEMETERY_PLOT_COUNT = 6
Constants.DEATH_ROOM_MODEL = "DeathRoom"
Constants.DEATH_ROOM_SPAWN_PART = "Spawn"
-- the designer's grave a client lays on each tombstone shadow:
-- GameAssets/Grave, a Model whose PrimaryPart is its Ground, with a
-- SurfaceGui on the stone (DisplayName, Thumbnail, and Day are filled in)
-- and an invisible CameraLocation part: where the dead player's camera
-- stands, looking the way the part faces, while the Results Menu is up
Constants.GRAVE_TEMPLATE = "Grave"
Constants.GRAVE_DISPLAY_NAME_LABEL = "DisplayName"
Constants.GRAVE_THUMBNAIL = "Thumbnail"
Constants.GRAVE_DAY_LABEL = "Day"
Constants.GRAVE_CAMERA_PART = "CameraLocation"
Constants.TOMBSTONE_SHADOWS_FOLDER = "TombstoneShadows"
-- Camp.Mine.Entrance: an anchored part whose position is the mine origin and
-- whose look direction (snapped to an axis) is the mine facing
Constants.CAMP_MINE_FOLDER = "Mine"
Constants.MINE_ENTRANCE_PART = "Entrance"
-- Camp.Refinery: a Model; refining is automatic within a radius of its
-- bounding box (RefineryManager, 2026-10-01), and its top is where the
-- client's ore icons fly to
Constants.CAMP_REFINERY_MODEL = "Refinery"
-- Camp.Refinery.Funnel: the designer's hopper, with an Entrance attachment
-- at its mouth where ore flies in and an Exit attachment over the tray
-- where bars fly out (2026-10-09); the model's top stands in for either
-- when it is missing
Constants.REFINERY_FUNNEL_PART = "Funnel"
Constants.REFINERY_ENTRANCE_ATTACHMENT = "Entrance"
Constants.REFINERY_EXIT_ATTACHMENT = "Exit"
-- Camp.Refinery.Spikes1 / Spikes2: the anchored grinder rollers, each long
-- along its own Z axis; clients spin whichever the model has, neighbours
-- in opposite directions, while a refine runs (2026-10-09; the artist's
-- model of 2026-11-09 keeps Spikes1 alone)
Constants.REFINERY_SPIKE_PARTS = { "Spikes1", "Spikes2" }
-- Camp.Refinery.Refinery: the artist's body mesh (2026-11-09) carrying the
-- attachments the client aims at: IronGoldOreTarget on the left side,
-- where gold and iron ore flies in and bars fly out, UraniumOreTarget on
-- the right for uranium, SmokeParticle with the emitters that run while
-- refining, and TubeFillPlacement, the centre the uranium tube's fill is
-- scaled about
Constants.REFINERY_IRON_GOLD_ORE_TARGET_ATTACHMENT = "IronGoldOreTarget"
Constants.REFINERY_URANIUM_ORE_TARGET_ATTACHMENT = "UraniumOreTarget"
Constants.REFINERY_SMOKE_ATTACHMENT = "SmokeParticle"
Constants.REFINERY_TUBE_FILL_PLACEMENT_ATTACHMENT = "TubeFillPlacement"
-- Camp.Refinery.RefiningGlow: the Neon part under the grinder, transparent
-- while idle, with the RefiningLight PointLight that pulses while refining
Constants.REFINERY_REFINING_GLOW_PART = "RefiningGlow"
Constants.REFINERY_REFINING_LIGHT = "RefiningLight"
-- Camp.Refinery.Refinery_Tube_Fill: the Neon column inside the uranium
-- tube, its Y size the crew's share of the uranium target, holding the
-- UraniumGlow PointLight lit once any uranium is refined
Constants.REFINERY_TUBE_FILL_PART = "Refinery_Tube_Fill"
Constants.REFINERY_URANIUM_GLOW_LIGHT = "UraniumGlow"
-- Camp.MiningStore.Stands: one "<Item>Stand" Model per Enums.StoreItem
-- (the name comes from StoreRules.standNameForItem), each with a Base part
-- carrying the SurfaceGui the client fills in and the ProximityPrompt the
-- server listens to, and an ItemSpawn part where the client spins the
-- display model; the folder keeps them apart from the building (2026-10-01)
Constants.CAMP_MINING_STORE_MODEL = "MiningStore"
Constants.MINING_STORE_STANDS_FOLDER = "Stands"
-- the designer's invisible part at the store's doorway: the tutorial's
-- guide beam bends through it so it does not cut through the wall
-- (2026-11-10); a map without one gets the straight beam
Constants.MINING_STORE_WAYPOINT_PART = "Waypoint"
Constants.STAND_BASE_PART = "Base"
Constants.STAND_ITEM_SPAWN_PART = "ItemSpawn"
Constants.STAND_GUI = "SurfaceGui"
Constants.STAND_NAME_LABEL = "NameLabel"
Constants.STAND_PRICE_BOX = "PriceBox"
Constants.STAND_PRICE_LABEL = "Price"
Constants.STAND_RESOURCE_ICON = "ResourceIcon"
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
-- a Tower template (artist, 2026-11-06) is a Base and a Body that never
-- move once placed and one Barrel that turns about its Hinge attachment
-- and fires from its Fire attachment, both children of the Barrel
Constants.TOWER_BARREL_PART = "Barrel"
Constants.TOWER_HINGE_ATTACHMENT = "Hinge"
Constants.TOWER_FIRE_ATTACHMENT = "Fire"
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
-- the same entry as the designer wants it while the Iron is short; the
-- client copies its colours onto an entry the player cannot afford
Constants.BUILD_BAR_ENTRY_TEMPLATE_UNAVAILABLE = "EntryTemplateUnavailable"
-- the square slot, styled like a tool bar slot: the item's picture inside,
-- the kind (Tower or Trap) as a small icon top-left, the number key top-right
Constants.BUILD_BAR_ENTRY_SLOT = "Slot"
-- the panel picture behind the slot, tinted for the selected entry
Constants.BUILD_BAR_ENTRY_SLOT_BACKING = "ImageLabel"
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
-- the designer's key card floated instead on the mouse scheme (2026-10-29):
-- the mouse to place, R to turn, Q to cancel; its Rotate row is hidden for
-- a kind that cannot turn
Constants.BUILD_BAR_PLACE_PANEL_PC = "PlacePanelPC"
Constants.BUILD_BAR_PLACE_PANEL_PC_ROTATE_ROW = "Rotate"
-- the key card's other rows and what a controller swaps in them (M72): the
-- Place row's picture, each key box (a Frame holding the key's letter), and
-- the Cancel row's hidden controller button picture
Constants.BUILD_BAR_PLACE_PANEL_PC_PLACE_ROW = "Place"
Constants.BUILD_BAR_PLACE_PANEL_PC_CANCEL_ROW = "Cancel"
Constants.BUILD_BAR_PLACE_PANEL_PC_KEY_BOX = "Frame"
Constants.BUILD_BAR_PLACE_PANEL_PC_GAMEPAD_GLYPH = "GamepadGlyph"
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
-- one line of guidance near the top: what a tap does right now, on the
-- designer's pill picture (the frame and the label inside it share the name)
Constants.BUILD_BAR_HINT_FRAME = "Hint"
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
-- the designer's label inside the Sell button carries its words (2026-10-29)
Constants.TOWER_MENU_SELL_TEXT_LABEL = "TextLabel"
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
-- the post's), with CharacterSpawn (the gunner's feet), Prompt (the
-- designer's invisible part carrying the Use ProximityPrompt, moved off
-- the CharacterSpawn on 2026-10-09), HandleLeft / HandleRight (the hands),
-- CameraLocation (welded to the gun), and one MeshPart gun carrying the
-- MuzzleAttachment; the gun is the part that tilts
Constants.POST_WEAPON_TEMPLATES_FOLDER = "PostWeapons"
Constants.POST_WEAPON_CHARACTER_SPAWN_PART = "CharacterSpawn"
Constants.POST_WEAPON_PROMPT_PART = "Prompt"
Constants.POST_WEAPON_HANDLE_LEFT_PART = "HandleLeft"
Constants.POST_WEAPON_HANDLE_RIGHT_PART = "HandleRight"
Constants.POST_WEAPON_CAMERA_PART = "CameraLocation"
Constants.POST_WEAPON_MUZZLE_ATTACHMENT = "MuzzleAttachment"
-- optional: a part that rides the gun and spins about its own X axis while
-- the post fires (the Minigun's barrel cluster, 2026-10-19); a template
-- without one has nothing that spins
Constants.POST_WEAPON_BARREL_PART = "Barrel"
-- the part the aim turns about (under the Spawn, which never moves); a
-- template without one turns about its Spawn
Constants.POST_WEAPON_TURRET_CENTER_PART = "TurretBaseCenter"
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
-- the AA Launcher's lock readout under the reticle (2026-10-20): a
-- vertical bar to its right whose Fill rises with the aimed target's
-- lock, and the line under it (NO TARGET, LOCKING ON TARGET, TARGET
-- LOCKED, CANNOT LOCK GROUND UNITS)
Constants.POST_HUD_LOCK_BAR = "LockBar"
Constants.POST_HUD_LOCK_FILL = "Fill"
Constants.POST_HUD_LOCK_LABEL = "LockLabel"
-- the Missile Launcher's lock count over the reload bar (2026-10-20): the
-- marker reticle on the left and "2 / 3"
Constants.POST_HUD_LOCK_COUNT = "LockCount"
Constants.POST_HUD_LOCK_COUNT_ICON = "Icon"
Constants.POST_HUD_LOCK_COUNT_LABEL = "Label"
-- the status bar under the reticle: heat for a gun that overheats, the
-- reload for one that reloads
Constants.POST_HUD_STATUS_BAR = "StatusBar"
Constants.POST_HUD_STATUS_FILL = "Fill"
-- above the bar: "OVERHEATED" or "RELOADING" while that is so, else hidden
Constants.POST_HUD_STATUS_LABEL = "StatusLabel"
-- beside the bar, for a Sniper (2026-10-19): the Binoculars' tag icon with
-- the button that tags under it, a sheet shrinking down it while the
-- cooldown runs (ClientBinocularsManager)
Constants.POST_HUD_TAG_HINT = "TagHint"
Constants.POST_HUD_TAG_HINT_ICON = "Icon"
Constants.POST_HUD_TAG_HINT_COOLDOWN = "Cooldown"
Constants.POST_HUD_TAG_HINT_LABEL = "Label"
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
-- "REFINERY_<tier>" too (2026-10-09): the map's Refinery is a marker like
-- the walls, swapped for the tier's model; it has no rubble, since its
-- fall ends the run
Constants.REFINERY_TEMPLATE_PREFIX = "REFINERY"
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
-- cosmetic skins (M61 first pass, 2026-11-04): GameAssets/Cosmetics/<SLOT
-- name>/<template>, built by scripts/studio/build_cosmetic_templates.luau
Constants.COSMETIC_TEMPLATES_FOLDER = "Cosmetics"
Constants.JET_PACK_TEMPLATE = "JET_PACK"
-- the name the worn copy carries on a character (ClientJetPackManager,
-- LobbyCharacterManager), so a menu avatar can take it off
Constants.WORN_JET_PACK_MODEL = "WornJetPack"
Constants.JET_PACK_FLAME_PART = "Flame"
-- the attachments on the pack's tanks where the stowed pick axe and hammer
-- skins mount (designer, 2026-10-12; used from M61)
Constants.JET_PACK_PICK_AXE_ATTACHMENT = "PickAxeMount"
Constants.JET_PACK_HAMMER_ATTACHMENT = "HammerMount"
-- the custom tool bar (built by scripts/studio/build_tool_bar_gui.luau)
Constants.TOOL_BAR_GUI_NAME = "ToolBar"
Constants.TOOL_BAR_SLOTS_FRAME = "Slots"
Constants.TOOL_BAR_SLOT_TEMPLATE = "SlotTemplate"
Constants.TOOL_SLOT_ICON = "Icon"
Constants.TOOL_SLOT_LABEL = "Label"
Constants.TOOL_SLOT_KEY_LABEL = "KeyLabel"
Constants.TOOL_SLOT_COUNT_LABEL = "CountLabel"
-- a number the size of the icon, over it: the Stim Shot's effect countdown (2026-10-19)
Constants.TOOL_SLOT_TIMER_LABEL = "TimerLabel"
-- the action word under each slot ("MINE", "SHOOT", ...), outside the square
Constants.TOOL_SLOT_CAPTION_LABEL = "CaptionLabel"
-- the slot's backing picture, tinted for the equipped tool (designer, 2026-10-29)
Constants.TOOL_SLOT_BACKGROUND = "Background"
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
-- the UIGradient under Fill whose transparency hides the spent part of the
-- day, so the fill picture stays registered over the bar's (2026-10-29)
Constants.DAY_CLOCK_FILL_MASK = "Mask"
Constants.DAY_CLOCK_DAY_LABEL = "DayLabel"
-- the Refinery HP bar (scripts/studio/build_refinery_hp_gui.luau, M33):
-- the day clock's box top centre, taken over at night; the home icon, a
-- bar whose Fill is the Refinery's HP share, and "REFINERY HP" under it
-- the big PAUSED word across the screen while the dev tool holds the run
-- (2026-10-07; build_run_paused_gui.luau, ClientRunCycleManager)
Constants.RUN_PAUSED_GUI_NAME = "RunPaused"
Constants.RUN_PAUSED_LABEL = "Label"
-- the rescue countdown in the day clock's spot (2026-10-07;
-- build_rescue_countdown_gui.luau, ClientRescueManager)
Constants.RESCUE_COUNTDOWN_GUI_NAME = "RescueCountdown"
Constants.RESCUE_COUNTDOWN_LABEL = "Label"
-- the designer's RESCUE HELICOPTER INCOMING flash (M75, 2026-10-27), shown
-- once the radio's dispatch message (the Rescue Sound on Camp.Radio) has
-- played
Constants.RESCUE_INCOMING_GUI_NAME = "RescueIncoming"
Constants.RESCUE_INCOMING_LABEL = "TextLabel"
Constants.RADIO_DISPATCH_SOUND = "Rescue"
-- the designer's title card (two TextLabels), held at the end of the ride
-- out before the Results Menu fades in (designer, 2026-10-27)
Constants.RESCUE_TITLE_GUI_NAME = "Title"
-- the card's title is a picture, so a player whose Roblox language is not
-- English gets this auto-localised label shown under it
Constants.RESCUE_TITLE_TRANSLATION_LABEL = "Translation"
Constants.TITLE_ART_LANGUAGE = "en"
Constants.REFINERY_HP_GUI_NAME = "RefineryHp"
Constants.REFINERY_HP_ROOT_FRAME = "Root"
Constants.REFINERY_HP_ICON = "Icon"
Constants.REFINERY_HP_BAR = "Bar"
Constants.REFINERY_HP_FILL = "Fill"
-- the UIGradient on the Fill that hides its spent part (the day clock's
-- way, designer 2026-10-29): the fill picture stays the bar's size
Constants.REFINERY_HP_FILL_MASK = "Mask"
Constants.REFINERY_HP_LABEL = "Label"
-- the Camp Map (scripts/studio/build_camp_map_gui.luau, M33): a square top
-- right that slides in from the right edge at night, drawing every structure shadow from a clone of
-- StructureTemplate (black once rubble, with a DestroyedMarkTemplate
-- clone, a red X, laid over it unturned), each crewmate from
-- PlayerDotTemplate, and each monster from MonsterDotTemplate, all inside Canvas
Constants.CAMP_MAP_GUI_NAME = "CampMap"
Constants.CAMP_MAP_ROOT_FRAME = "Root"
Constants.CAMP_MAP_CANVAS = "Canvas"
Constants.CAMP_MAP_STRUCTURE_TEMPLATE = "StructureTemplate"
Constants.CAMP_MAP_DESTROYED_MARK_TEMPLATE = "DestroyedMarkTemplate"
-- "REFINERY" under the Refinery's box so the map reads north-up at a
-- glance (designer, 2026-10-07)
Constants.CAMP_MAP_REFINERY_LABEL = "RefineryLabel"
Constants.CAMP_MAP_PLAYER_DOT_TEMPLATE = "PlayerDotTemplate"
-- the cone under a crewmate's dot showing which way they face (2026-10-29)
Constants.CAMP_MAP_PLAYER_CONE_TEMPLATE = "PlayerConeTemplate"
Constants.CAMP_MAP_MONSTER_DOT_TEMPLATE = "MonsterDotTemplate"
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
-- the Tutorial ScreenGui (M76, 2026-11-09; scripts/studio/build_tutorial_gui.luau):
-- the guide's dialogue box (the head in a ViewportFrame, the line, and the
-- read bar that drains while a line auto-advances; no NEXT and no SKIP,
-- designer 2026-11-09) and
-- the one HUD arrow ClientTutorialManager parks beside what a line points at
Constants.TUTORIAL_GUI_NAME = "Tutorial"
Constants.TUTORIAL_DIALOG_FRAME = "Dialog"
Constants.TUTORIAL_PORTRAIT_VIEWPORT = "Portrait"
Constants.TUTORIAL_MESSAGE_LABEL = "Message"
Constants.TUTORIAL_READ_BAR = "ReadBar"
Constants.TUTORIAL_ARROW = "Arrow"
-- the Tasks panel (designer, 2026-11-09): the goal a waiting step sets, top right
Constants.TUTORIAL_TASKS_FRAME = "Tasks"
Constants.TUTORIAL_TASK_LABEL = "Task"
-- the guide's head under GameAssets (scripts/studio/build_tutorial_guide_head.luau)
Constants.TUTORIAL_ASSETS_FOLDER = "Tutorial"
Constants.TUTORIAL_GUIDE_HEAD_MODEL = "GuideHead"
-- the guide beam the client clones (designer-tuned in the Explorer, 2026-11-09)
Constants.TUTORIAL_GUIDE_BEAM_TEMPLATE = "GuideBeam"
Constants.GEIGER_COUNTER_GUI_NAME = "GeigerCounter"
Constants.GEIGER_COUNTER_ROOT_FRAME = "Root"
Constants.GEIGER_COUNTER_DIAL = "Dial"
Constants.GEIGER_COUNTER_ICON = "Icon"
Constants.GEIGER_COUNTER_RING_PREFIX = "Ring"
-- the Uranium Seeker's arrow beside the dial (M56): up or down to the
-- nearest uranium once the second ring is lit, hidden otherwise
Constants.GEIGER_COUNTER_DIRECTION_LABEL = "Direction"
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
-- Roblox's own touch controls, built by its PlayerModule in PlayerGui: read
-- to place our touch buttons round the jump button and to hear its presses
Constants.TOUCH_GUI_NAME = "TouchGui"
Constants.TOUCH_CONTROL_FRAME_NAME = "TouchControlFrame"
Constants.TOUCH_JUMP_BUTTON_NAME = "JumpButton"
-- balances (top left): one row per resource, Uranium as "total / target"
Constants.HUD_BALANCES_FRAME = "Balances"
Constants.HUD_BALANCE_IRON_ROW = "IronRow"
Constants.HUD_BALANCE_GOLD_ROW = "GoldRow"
Constants.HUD_BALANCE_URANIUM_ROW = "UraniumRow"
Constants.HUD_BALANCE_ICON = "Icon"
Constants.HUD_BALANCE_VALUE_LABEL = "ValueLabel"
-- BillboardGui and SurfaceGui templates under GameAssets, cloned by clients
Constants.GUI_TEMPLATES_FOLDER = "Gui"
-- the sign floated above the Walls Table: tier title, the shared Iron pool as
-- a bar reading "pool / required"
-- (scripts/studio/build_fortification_billboard.luau)
Constants.FORTIFICATION_BILLBOARD = "Fortification"
Constants.FORTIFICATION_ROOT_FRAME = "Root"
-- the designer's picture plate behind the title (2026-10-30); the title
-- label sits inside it
Constants.FORTIFICATION_BACKGROUND = "Background"
Constants.FORTIFICATION_TITLE_LABEL = "TitleLabel"
Constants.FORTIFICATION_BAR = "Bar"
Constants.FORTIFICATION_FILL = "Fill"
Constants.FORTIFICATION_PROGRESS_LABEL = "ProgressLabel"
Constants.FORTIFICATION_ICON = "Icon"
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
-- the Refinery's HP bar floats this far above the model's top (5.5 until
-- 2026-10-30, lowered by the designer)
Constants.REFINERY_HP_BILLBOARD_LIFT_STUDS = 3.5
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
-- the "HEADSHOT BONUS" callout (scripts/studio/build_headshot_billboard.luau,
-- 2026-10-19): the template, its label, and the workspace folder its
-- throwaway anchors live in
Constants.HEADSHOT_BILLBOARD = "HeadshotBonus"
Constants.HEADSHOT_LABEL = "Label"
Constants.HEADSHOT_FOLDER = "HeadshotBonuses"
-- the dev tool's marker over a sleeping lurker pocket (M62); the folder
-- the markers live in while they are shown
Constants.SPIDER_SPAWN_BILLBOARD = "SpiderSpawn"
Constants.SPIDER_SPAWN_MARKERS_FOLDER = "SpiderSpawnMarkers"
-- the Blockfaces' dev markers (M68) reuse the spider billboard with its own text
Constants.BLOCKFACE_MARKERS_FOLDER = "BlockfaceMarkers"
Constants.CHASE_MARKERS_FOLDER = "ChaseMarkers"
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
-- the tail rotor, a part of the model itself, spun about its own X axis
Constants.HELICOPTER_TAIL_ROTOR_PART = "BackBlades"
-- pad menus (built by scripts/studio/build_create_party_gui.luau and build_queue_gui.luau)
-- the Class Menu (GDD "Classes", the Class Equip Menu of 2026-11-04;
-- scripts/studio/build_class_menu_gui.luau; it replaced the Character
-- Select Menu and the Character Sheet of M37): a header with Back and
-- the Diamonds wallet; on the left a scrolling list with one button per
-- class cloned from the template (its icon, its name under it, a lock in
-- the corner and a grey wash when locked, a stroke on the selected one);
-- in the middle the 3D avatar the player turns by dragging, dressed for
-- the selected class and holding its pick axe, with CUSTOMIZE CLASS
-- APPEARANCE under it; on the right the info panel for the selected class
Constants.CLASS_MENU_GUI_NAME = "ClassMenu"
Constants.CLASS_MENU_BACK_BUTTON = "BackButton"
-- the menu has no wallet of its own since 2026-11-05: its backdrop is
-- clear and the HUD's balances stay on screen under it
-- the class list column: a frame holding the title band (TitleFrame with
-- its Title label) over the scrolling list of the same name (designer,
-- 2026-11-05)
Constants.CLASS_MENU_CLASS_LIST_FRAME = "ClassList"
Constants.CLASS_MENU_CLASS_LIST = "ClassList"
Constants.CLASS_MENU_TITLE_FRAME = "TitleFrame"
Constants.CLASS_MENU_TITLE_LABEL = "Title"
Constants.CLASS_MENU_CLASS_BUTTON_TEMPLATE = "ClassButtonTemplate"
Constants.CLASS_BUTTON_ICON = "Icon"
Constants.CLASS_BUTTON_NAME_LABEL = "NameLabel"
Constants.CLASS_BUTTON_LOCK_ICON = "LockIcon"
-- the EQUIPPED CLASS box under the list: the icon and name of the class
-- in play (designer, 2026-11-05; a stroke and an EQUIPPED word on the
-- list button for a few hours that day)
Constants.CLASS_MENU_EQUIPPED_CLASS = "EquippedClass"
Constants.EQUIPPED_CLASS_ICON = "Icon"
Constants.EQUIPPED_CLASS_TITLE = "Title"
-- the info panel: the ClassHeader frame (the class name, three stars
-- (Star1 to Star3, gold for each tier earned, dark otherwise, as on the
-- gacha card), and the class icon), the Description frame with its one
-- sentence (both frames the designer's, 2026-11-05), the four kit slots (Post Weapon, Weapon, Tower,
-- Gadget, cloned from the template; a tap opens the item's tooltip in
-- the info dialog), the three perk rows (cloned from the template; a
-- locked one reads "N [star] REQUIRED" with a lock, an open one rolls
-- like the old skill rows), the ODDS button, and EQUIP
Constants.CLASS_MENU_INFO_PANEL = "InfoPanel"
Constants.CLASS_INFO_HEADER = "ClassHeader"
Constants.CLASS_INFO_NAME_LABEL = "NameLabel"
Constants.CLASS_INFO_STARS = "Stars"
Constants.CLASS_INFO_STAR_NAME_FORMAT = "Star%d"
Constants.CLASS_INFO_STAR_COUNT = 3
Constants.CLASS_INFO_ICON = "Icon"
Constants.CLASS_INFO_DESCRIPTION_FRAME = "Description"
Constants.CLASS_INFO_DESCRIPTION_LABEL = "DescriptionLabel"
-- the LOADOUT and SKILLS headings over the two columns (designer's
-- layout, 2026-11-04)
Constants.CLASS_INFO_LOADOUT_TITLE = "LoadoutTitle"
Constants.CLASS_INFO_SKILLS_TITLE = "SkillsTitle"
Constants.CLASS_INFO_KIT_ROW = "KitRow"
Constants.CLASS_INFO_KIT_SLOT_TEMPLATE = "KitSlotTemplate"
Constants.KIT_SLOT_ICON = "Icon"
Constants.KIT_SLOT_LABEL = "SlotLabel"
-- the item's own name under the slot word
Constants.KIT_SLOT_ITEM_LABEL = "ItemLabel"
Constants.CLASS_INFO_PERK_ROWS = "PerkRows"
Constants.CLASS_INFO_PERK_ROW_TEMPLATE = "PerkRowTemplate"
-- the row's words sit in the SkillText frame (designer, 2026-11-05), which
-- clips the reel of entries a reroll scrolls through like a slot machine
Constants.PERK_ROW_SKILL_TEXT = "SkillText"
Constants.PERK_ROW_NAME_LABEL = "NameLabel"
Constants.PERK_ROW_DESCRIPTION_LABEL = "DescriptionLabel"
Constants.PERK_ROW_REROLL_BUTTON = "RerollButton"
-- shown once the reel lands: KEEP takes the new skill, X puts the old
-- one back (designer, 2026-11-05; the roll screen's Keep and Undo before)
Constants.PERK_ROW_KEEP_BUTTON = "KeepButton"
Constants.PERK_ROW_CANCEL_BUTTON = "CancelButton"
Constants.PERK_ROW_LOCK_ICON = "LockIcon"
-- the locked row's one line, "UNLOCKED AT 2 [star]" (designer, 2026-11-05;
-- a number and an authored "[star] REQUIRED" label before)
Constants.PERK_ROW_REQUIREMENT_LABEL = "RequirementLabel"
Constants.CLASS_INFO_ODDS_BUTTON = "OddsButton"
-- an ImageButton on the designer's plate since 2026-11-05; its word is
-- the TextLabel child
Constants.CLASS_INFO_EQUIP_BUTTON = "EquipButton"
-- the designer's plate over the Odds and Equip spots on a locked class,
-- sending the player to the Supply Crates (2026-11-05)
Constants.CLASS_INFO_SUPPLY_CRATE_BUTTON = "SupplyCrateButton"
-- the restricted player's plates (designer, 2026-11-10), both roads to
-- the rotating store: RotatingStoreButton stands where SupplyCrateButton
-- does on a locked class and UpgradeButton where OddsButton does on an
-- owned one
Constants.CLASS_INFO_ROTATING_STORE_BUTTON = "RotatingStoreButton"
Constants.CLASS_INFO_UPGRADE_BUTTON = "UpgradeButton"
-- the word label on the Equip, Odds, and Supply Crate plates
Constants.EQUIP_BUTTON_LABEL = "TextLabel"
Constants.CLASS_MENU_INFO_DIALOG = "InfoDialog"
-- the class gacha menu (M70; scripts/studio/build_gacha_gui.luau; the 3D
-- crate opening since 2026-11-03): a panel on the right third of the
-- screen with an X close button, the odds list (or, for a player
-- restricted from paid random items, the classes to buy outright, cloned
-- from the row template), and OPEN CRATE with its price; outside the
-- panel the TAP CRATE TO OPEN line and the prize card with CLAIM
Constants.GACHA_GUI_NAME = "Gacha"
Constants.GACHA_CLOSE_BUTTON = "CloseButton"
Constants.GACHA_ODDS_PANEL = "Odds"
Constants.GACHA_ODDS_ROW_TEMPLATE = "OddsRowTemplate"
Constants.GACHA_ODDS_ROW_NAME_LABEL = "Name"
Constants.GACHA_ODDS_ROW_SHARE_LABEL = "Share"
Constants.GACHA_CLASS_ROW_TEMPLATE = "ClassRowTemplate"
Constants.GACHA_CLASS_ROW_NAME_LABEL = "Name"
Constants.GACHA_CLASS_ROW_PROGRESS_LABEL = "Progress"
Constants.GACHA_CLASS_ROW_BUY_BUTTON = "BuyButton"
Constants.GACHA_ROLL_BUTTON = "RollButton"
Constants.GACHA_ROLL_PRICE_LABEL = "Price"
-- the group reward (M78, the designer's instances of 2026-11-12): the
-- banner in the Supply Crate menu, the rotating store, and the Diamond
-- Store with its line; and the claim menu, whose button carries the
-- amount (ClientGroupRewardManager)
Constants.GROUP_REWARD_BANNER = "GroupReward"
Constants.GROUP_REWARD_BANNER_MESSAGE = "Message"
Constants.GROUP_REWARD_CLAIM_GUI_NAME = "GroupRewardClaim"
Constants.GROUP_REWARD_CLAIM_BUTTON = "ClaimButton"
Constants.GROUP_REWARD_CLAIM_AMOUNT_LABEL = "RewardAmount"
-- Daily Rewards (M39, scripts/studio/build_daily_rewards_gui.luau): the
-- menu, its grid of tiles cloned from one template per state, and the
-- lobby HUD's left-hand stack with the button that opens it
Constants.DAILY_REWARDS_GUI_NAME = "DailyRewards"
Constants.DAILY_REWARDS_BACK_BUTTON = "BackButton"
Constants.DAILY_REWARDS_TILE_GRID = "TileGrid"
Constants.DAILY_REWARDS_TILE_TEMPLATE_LOCKED = "TileTemplate"
Constants.DAILY_REWARDS_TILE_TEMPLATE_READY = "TileTemplateReady"
Constants.DAILY_REWARDS_TILE_TEMPLATE_CLAIMED = "TileTemplateClaimed"
Constants.DAILY_REWARDS_TILE_DAY_LABEL = "DayLabel"
Constants.DAILY_REWARDS_TILE_ICON = "Icon"
Constants.DAILY_REWARDS_TILE_AMOUNT_LABEL = "Amount"
Constants.DAILY_REWARDS_TILE_CLAIM_BUTTON = "ClaimButton"
Constants.DAILY_REWARDS_NEXT_REWARD_LABEL = "NextReward"
-- the Starter Pack (M79, scripts/studio/build_starter_pack_gui.luau): the
-- menu's three item cards, each a picture and a line, the buy button
-- with the struck-through worth and the real price, and the HUD button
-- under Daily Rewards
Constants.STARTER_PACK_GUI_NAME = "StarterPack"
Constants.STARTER_PACK_BACK_BUTTON = "BackButton"
Constants.STARTER_PACK_ITEMS = "Items"
Constants.STARTER_PACK_ITEM_CLASS = "ClassItem"
Constants.STARTER_PACK_ITEM_DIAMONDS = "DiamondsItem"
Constants.STARTER_PACK_ITEM_COSMETIC = "CosmeticItem"
Constants.STARTER_PACK_ITEM_ICON = "Icon"
Constants.STARTER_PACK_ITEM_LABEL = "Amount"
Constants.STARTER_PACK_BUY_BUTTON = "BuyButton"
Constants.STARTER_PACK_VALUE_LABEL = "Value"
Constants.STARTER_PACK_PRICE_LABEL = "Price"
Constants.HUD_STARTER_PACK_BUTTON = "StarterPackButton"
Constants.HUD_LEFT_BUTTONS = "LeftButtons"
Constants.HUD_DAILY_REWARDS_BUTTON = "DailyRewardsButton"
Constants.HUD_BUTTON_ALERT = "Alert"
-- the Badges menu (M69, scripts/studio/build_badges_gui.luau): the grid
-- of badge tiles on the left, cloned from one template (picture, stars,
-- the CLAIM! banner, the claimed check), the info panel on the right
-- (title, picture, stars, description, and the claim button or the
-- reward line in one spot), and the HUD button in the left stack
Constants.BADGES_GUI_NAME = "Badges"
Constants.BADGES_BACK_BUTTON = "BackButton"
Constants.BADGES_LIST = "BadgeList"
Constants.BADGES_TILE_TEMPLATE = "BadgeTemplate"
Constants.BADGES_TILE_ICON = "Icon"
Constants.BADGES_TILE_CLAIM_BANNER = "ClaimBanner"
Constants.BADGES_TILE_CHECK = "Check"
Constants.BADGES_TILE_SELECTED = "Selected"
Constants.BADGES_STARS = "Stars"
Constants.BADGES_STAR_FORMAT = "Star%d"
Constants.BADGES_INFO_PANEL = "InfoPanel"
Constants.BADGES_INFO_TITLE = "Title"
Constants.BADGES_INFO_ICON = "Icon"
Constants.BADGES_INFO_DESCRIPTION = "Description"
Constants.BADGES_INFO_CLAIM_BUTTON = "ClaimButton"
Constants.BADGES_INFO_CLAIM_AMOUNT_LABEL = "RewardAmount"
Constants.BADGES_INFO_REWARD_TEXT = "RewardText"
Constants.BADGES_INFO_REWARD_LABEL = "Label"
Constants.BADGES_INFO_REWARD_ICON = "DiamondIcon"
Constants.HUD_BADGES_BUTTON = "BadgesButton"
-- the designer's KEY STORE plate under OPEN CRATE (2026-11-06): closes the crate menu and opens the Key Store
Constants.GACHA_KEY_STORE_BUTTON = "KeyStoreButton"
Constants.GACHA_TAP_HINT = "TapHint"
-- the headline along the top once a class card has landed (designer,
-- 2026-11-03): NEW CLASS UNLOCKED! or CLASS TIER INCREASED!
Constants.GACHA_REVEAL_TITLE = "RevealTitle"
-- the headline is the designer's picture backing with the words inside
-- it (2026-11-03)
Constants.GACHA_REVEAL_TEXT = "RevealText"
Constants.GACHA_CARD = "Card"
Constants.GACHA_CARD_KIND_LABEL = "Kind"
Constants.GACHA_CARD_NAME_LABEL = "Name"
Constants.GACHA_CARD_DETAIL_LABEL = "Detail"
-- CLAIM sits under either card, so it is the gui's own child (2026-11-03)
Constants.GACHA_CARD_CLAIM_BUTTON = "ClaimButton"
-- the TextLabel child the designer put on the gacha buttons; its Text is the word shown
Constants.GACHA_BUTTON_TEXT_LABEL = "TextLabel"
-- the Diamond Store menu (M40; scripts/studio/build_diamond_store_gui.luau):
-- a header with Back and the wallet, and a row of pack cards cloned from
-- the hidden template, each with its amount, an optional banner across
-- the top, and a BUY button carrying the Robux price
Constants.DIAMOND_STORE_GUI_NAME = "DiamondStore"
Constants.DIAMOND_STORE_BACK_BUTTON = "BackButton"
Constants.DIAMOND_STORE_PACKS = "Packs"
Constants.DIAMOND_STORE_PACK_TEMPLATE = "PackTemplate"
Constants.DIAMOND_STORE_PACK_ICON = "Icon"
Constants.DIAMOND_STORE_PACK_AMOUNT_LABEL = "Amount"
Constants.DIAMOND_STORE_PACK_BANNER = "Banner"
Constants.DIAMOND_STORE_PACK_BANNER_LABEL = "Text"
-- the designer's plate button, copied from the Key Store (2026-11-06)
Constants.DIAMOND_STORE_PACK_BUY_BUTTON = "EquipButton"
Constants.DIAMOND_STORE_PACK_PRICE_LABEL = "Price"
-- the Key Store menu (M61; scripts/studio/build_key_store_gui.luau): Back,
-- the Keys wallet, the scrolling grid of every cosmetic (cloned from the
-- hidden item template, its picture and name) on the left, and on the
-- right the info panel with the picked item's picture, name, slot, and
-- BUY with the Keys price, which reads EQUIP once the item is owned
Constants.KEY_STORE_GUI_NAME = "KeyStore"
Constants.KEY_STORE_BACK_BUTTON = "BackButton"
Constants.KEY_STORE_ITEM_LIST = "ItemList"
Constants.KEY_STORE_ITEM_TEMPLATE = "ItemTemplate"
Constants.KEY_STORE_ITEM_ICON = "Icon"
Constants.KEY_STORE_ITEM_NAME_LABEL = "Name"
Constants.KEY_STORE_ITEM_OWNED_LABEL = "Owned"
Constants.KEY_STORE_INFO_PANEL = "InfoPanel"
Constants.KEY_STORE_INFO_ICON = "Icon"
Constants.KEY_STORE_INFO_NAME_LABEL = "Name"
Constants.KEY_STORE_INFO_SLOT_LABEL = "Slot"
Constants.KEY_STORE_INFO_HINT_LABEL = "Hint"
Constants.KEY_STORE_BUY_BUTTON = "BuyButton"
Constants.KEY_STORE_BUY_PRICE_LABEL = "Price"
Constants.KEY_STORE_EQUIP_BUTTON = "EquipButton"
-- the restricted player's rotating store (2026-11-10; scripts/studio/
-- build_restricted_store_gui.luau): a copy of the KeyStore layout, so
-- its inner names are the KEY_STORE_ ones above, plus the page frame,
-- the Actions frame holding each card's button, and that button's
-- price tab
Constants.RESTRICTED_STORE_GUI_NAME = "RestrictedStoreGui"
Constants.RESTRICTED_STORE_STORE_PAGE = "StorePage"
Constants.RESTRICTED_STORE_PRICE_TAB = "PriceTab"
Constants.RESTRICTED_STORE_ACTIONS = "Actions"
-- the card's frame for a thing that cannot be bought (owned, maxed out);
-- its word is the frame's "TextLabel"
Constants.RESTRICTED_STORE_NOT_AVAILABLE = "NotAvailable"
-- the card's frames for the item's name and its type; each holds one label
Constants.RESTRICTED_STORE_ITEM_HEADER = "Header"
Constants.RESTRICTED_STORE_ITEM_TYPE = "Type"
-- the store page: the countdown to the next set, over the cards
Constants.RESTRICTED_STORE_REFRESH_TIMER = "RefreshTimer"
-- the lobby's two store stalls (designer, 2026-11-03): a Folder each in
-- Workspace, with a MenuTouchPart whose volume opens that stall's menu
-- when the player walks into it (ClientStoreZoneManager)
Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER = "SupplyCrateStore"
Constants.LOBBY_DIAMOND_STORE_FOLDER = "DiamondStore"
Constants.STORE_MENU_TOUCH_PART = "MenuTouchPart"
-- the lobby's two selection stalls (designer, 2026-11-06), each a Folder in
-- Workspace with the same MenuTouchPart: the Gear Locker and the Class Menu
Constants.LOBBY_GEAR_SELECTION_FOLDER = "GearSelection"
Constants.LOBBY_CLASS_SELECTION_FOLDER = "ClassSelection"
-- each stall's name twice (designer, 2026-11-10): the 3DText model of
-- letter meshes everyone sees by default, and a Sign part whose
-- SurfaceGui (off by default) says the same in an auto-localised
-- TextLabel, since translation cannot reach a mesh (ClientStoreSignManager)
Constants.LOBBY_STALL_3D_TEXT_MODEL = "3DText"
Constants.LOBBY_STALL_SIGN_PART = "Sign"

-- the Gear Locker menu (M61, 2026-11-06; scripts/studio/build_gear_menu_gui.luau):
-- the X, the avatar viewport wearing the loadout, and one row per slot the
-- locker shows (pick axes, jet packs; designer 2026-11-06), each a fixed
-- icon-and-name header beside a sideways-scrolling strip of the slot's
-- cards cloned from the hidden template (picture, name, an EQUIPPED tag, a
-- lock on one not owned)
Constants.GEAR_MENU_GUI_NAME = "GearMenu"
Constants.GEAR_MENU_BACK_BUTTON = "BackButton"
Constants.GEAR_MENU_AVATAR = "Avatar"
Constants.GEAR_MENU_ROWS = "Rows"
Constants.GEAR_MENU_ROW_TEMPLATE = "RowTemplate"
Constants.GEAR_MENU_ROW_ICON = "Icon"
Constants.GEAR_MENU_ROW_NAME_LABEL = "Name"
Constants.GEAR_MENU_ROW_ITEM_LIST = "ItemList"
Constants.GEAR_MENU_ITEM_TEMPLATE = "ItemTemplate"
Constants.GEAR_MENU_ITEM_ICON = "Icon"
Constants.GEAR_MENU_ITEM_NAME_LABEL = "Name"
Constants.GEAR_MENU_ITEM_EQUIPPED_LABEL = "Equipped"
Constants.GEAR_MENU_ITEM_LOCK_ICON = "LockIcon"
-- the Supply Crate stall's crate (designer's model, 2026-11-03): the
-- Crate part with the Attachment holding the light and the emitter, the
-- Lid, and the two invisible reference poses the lid tweens between;
-- the ring the stall stands on (the designer's Union, faded during the
-- opening); and the three camera shots (scripts/studio/
-- build_supply_crate_parts.luau)
Constants.SUPPLY_CRATE_MODEL = "SupplyCrate"
Constants.SUPPLY_CRATE_PART = "Crate"
Constants.SUPPLY_CRATE_ATTACHMENT = "Attachment"
Constants.SUPPLY_CRATE_LID = "Lid"
Constants.SUPPLY_CRATE_LID_CLOSED = "LidClosed"
Constants.SUPPLY_CRATE_LID_OPEN = "LidOpen"
Constants.SUPPLY_CRATE_RING = "Union"
Constants.SUPPLY_CRATE_CAMERA_MENU = "CameraMenuOpen"
Constants.SUPPLY_CRATE_CAMERA_SEQUENCE = "CameraOpenSequence"
Constants.SUPPLY_CRATE_CAMERA_OPEN = "CameraOpen"
-- the crate's card poses (designer, 2026-11-03): where the 3D class card
-- starts, flat inside the crate at half size, and where it rises to
Constants.SUPPLY_CRATE_CARD_START = "CardStart"
Constants.SUPPLY_CRATE_CARD_END = "CardEnd"
-- the Key's poses the same way (designer, 2026-11-03): the mesh rises from
-- KeyStart to KeyEnd and spins there until the claim
Constants.SUPPLY_CRATE_KEY_START = "KeyStart"
Constants.SUPPLY_CRATE_KEY_END = "KeyEnd"
-- the poses any cosmetic skin rises between, fitted to PrizeEnd's size
-- by its bounding box (designer-placed, 2026-11-04)
-- the template under GameAssets/Cosmetics/<SLOT> the avatar wears when a
-- class has the stock skin (CosmeticLoadoutSchema.DEFAULT_SKIN_ID) in that slot
Constants.DEFAULT_SKIN_TEMPLATE = "DEFAULT"
Constants.SUPPLY_CRATE_PRIZE_START = "PrizeStart"
Constants.SUPPLY_CRATE_PRIZE_END = "PrizeEnd"
-- the designer's 3D class card under GameAssets/Store (2026-11-03): a Card
-- part (the primary) with a SurfaceGui holding the class name and icon,
-- and three star parts, each with its effects under an Effect attachment
Constants.STORE_ASSETS_FOLDER = "Store"
Constants.CLASS_CARD_TEMPLATE = "ClassCard"
-- the designer's Key mesh beside it, shown for a Keys draw
Constants.KEY_TEMPLATE = "Key"
-- the name a cosmetic skin's clone carries while it flies out of the crate
Constants.GACHA_PRIZE_CLONE = "GachaPrize"
Constants.CLASS_CARD_NAME_LABEL = "ClassName"
Constants.CLASS_CARD_ICON_LABEL = "ImageLabel"
Constants.CLASS_CARD_STAR_NAME_FORMAT = "Star%d"
Constants.CLASS_CARD_STAR_COUNT = 3
Constants.CLASS_CARD_EFFECT_ATTACHMENT = "Effect"
-- the designer's attachment on the card's own part whose emitters burst
-- when the card is a class newly unlocked (2026-11-04)
Constants.CLASS_CARD_BURST_ATTACHMENT = "Attachment"
-- a perk row button's parts: the word (Reroll, Keep, and Cancel alike),
-- the price, its icon
Constants.REROLL_BUTTON_LABEL = "Label"
Constants.REROLL_BUTTON_PRICE_LABEL = "PriceLabel"
Constants.REROLL_BUTTON_PRICE_ICON = "PriceIcon"
-- the cosmetic slots a class loadout shows, in order (designer,
-- 2026-10-13: only these three until the other slots have skins)
Constants.CLASS_COSMETIC_SLOTS = { Enums.CosmeticSlot.PICK_AXE, Enums.CosmeticSlot.JET_PACK }
-- the info dialog over the menu (2026-10-13): a reroll's odds by rarity
-- (the ODDS button) or a kit item's tooltip (tapping its slot)
Constants.INFO_DIALOG_TITLE = "Title"
Constants.INFO_DIALOG_PICTURE = "Picture"
Constants.INFO_DIALOG_ROWS = "Rows"
Constants.INFO_DIALOG_ROW_TEMPLATE = "RowTemplate"
Constants.INFO_ROW_LABEL = "Label"
Constants.INFO_ROW_VALUE = "Value"
Constants.INFO_DIALOG_NOTE = "Note"
Constants.INFO_DIALOG_CLOSE_BUTTON = "CloseButton"
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
-- the Friends Only row: a switch button whose Switch knob sits at the
-- SwitchOff or SwitchOn marker frame (designer, 2026-10-30; an Off / On
-- state label before)
Constants.CREATE_PARTY_FRIENDS_ONLY_ROW = "FriendsOnly"
Constants.CREATE_PARTY_FRIENDS_ONLY_TOGGLE = "ToggleButton"
Constants.TOGGLE_SWITCH = "Switch"
Constants.TOGGLE_SWITCH_OFF = "SwitchOff"
Constants.TOGGLE_SWITCH_ON = "SwitchOn"
Constants.CREATE_PARTY_COUNTDOWN_LABEL = "Countdown"
Constants.CREATE_PARTY_CREATE_BUTTON = "CreateButton"
Constants.CREATE_PARTY_CANCEL_BUTTON = "CancelButton"
-- the Queue Menu (the designer's layout, 2026-10-30): the map and difficulty
-- in one label, the visibility, the CrewMember panel (its heading is its one
-- TextLabel child; CrewSlots holds the hidden Filled and Empty slot
-- templates), and the Buttons frame with the countdown and the two buttons
Constants.QUEUE_MAP_LABEL = "MapLabel"
Constants.QUEUE_VISIBILITY_LABEL = "VisibilityLabel"
Constants.QUEUE_CREW_FRAME = "CrewMember"
Constants.QUEUE_CREW_SLOTS = "CrewSlots"
Constants.QUEUE_CREW_FILLED_TEMPLATE = "FilledTemplate"
Constants.QUEUE_CREW_EMPTY_TEMPLATE = "EmptyTemplate"
Constants.QUEUE_CREW_THUMBNAIL = "Thumbnail"
Constants.QUEUE_CREW_DISPLAY_NAME = "DisplayName"
Constants.QUEUE_BUTTONS_FRAME = "Buttons"
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
-- on a weapon with a SECONDARY (the Assault Rifle's grenade): the
-- designer's GrenadeAttachment under the barrel, carried into the held
-- template under this name, where the grenade leaves (2026-10-19)
Constants.WEAPON_SECONDARY_ATTACHMENT = "Grenade"
-- the designer's own muzzle mark on the source art under GameAssets/Weapons;
-- when present the built template's Muzzle sits there instead of at the
-- measured barrel tip
Constants.WEAPON_SOURCE_MUZZLE_ATTACHMENT = "MuzzleAttachment"
Constants.WEAPON_SOURCE_SECONDARY_ATTACHMENT = "GrenadeAttachment"
-- under the Muzzle attachment, both authored switched off: a light and a
-- smoke emitter the client turns on for a moment on every shot
Constants.WEAPON_MUZZLE_FLASH_LIGHT = "MuzzleFlash"
Constants.WEAPON_MUZZLE_SMOKE_EMITTER = "MuzzleSmoke"
-- a stream weapon's flame, an emitter under the Muzzle pulsed every tick
-- (the Flamethrower, 2026-10-16)
Constants.WEAPON_MUZZLE_FLAME_EMITTER = "MuzzleFlame"

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
-- above the ammo readout, for a weapon with a SECONDARY (the Assault
-- Rifle's grenade launcher, 2026-10-19): its icon, its name, and a bar
-- that empties on the shot and refills over the cooldown
Constants.WEAPON_HUD_SECONDARY_BAR = "SecondaryBar"
Constants.WEAPON_HUD_SECONDARY_ICON = "Icon"
Constants.WEAPON_HUD_SECONDARY_LABEL = "Label"
Constants.WEAPON_HUD_SECONDARY_TRACK = "Track"
Constants.WEAPON_HUD_SECONDARY_FILL = "Fill"
-- touch only: the weapon's aim button (scope, grenade), above the jump button
Constants.WEAPON_HUD_SECONDARY_BUTTON = "SecondaryButton"
Constants.WEAPON_HUD_SECONDARY_BUTTON_LABEL = "Label"
-- the scope view (scripts/studio/build_scope_hud_gui.luau, 2026-10-19):
-- a full-screen gui shown while a scope kind's scope is raised, its
-- Reticle picture set from Icons.WEAPON_SCOPE by weapon kind
Constants.SCOPE_HUD_GUI_NAME = "ScopeHud"
Constants.SCOPE_HUD_RETICLE = "Reticle"

-- the Results Menu (M32): the run's stats, shown at death with the Revive
-- and Spectate buttons and at the end of a run with Return to Lobby. Two
-- designer-authored guis since 2026-10-28 (the built ResultsMenu and its
-- build script are gone), the same children in each, the title the
-- TextLabel inside a Header banner, revealed in stages when it opens
Constants.RESULTS_MENU_WIN_GUI_NAME = "ResultsMenuWin"
Constants.RESULTS_MENU_FAIL_GUI_NAME = "ResultsMenuFail"
Constants.RESULTS_MENU_HEADER = "Header"
Constants.RESULTS_MENU_HEADER_LABEL = "TextLabel"
-- the designer's panel behind the stats, grown from nothing after the
-- banner (2026-10-28)
Constants.RESULTS_MENU_BACKGROUND = "Background"
Constants.RESULTS_MENU_DIALOG = "Dialog"
Constants.RESULTS_MENU_TITLE_LABEL = "Title"
Constants.RESULTS_MENU_STATS = "Stats"
Constants.RESULTS_MENU_ROW_URANIUM_REFINED = "UraniumRefined"
Constants.RESULTS_MENU_ROW_DIAMONDS_EARNED = "DiamondsEarned"
Constants.RESULTS_MENU_ROW_GOLD_REFINED = "GoldRefined"
Constants.RESULTS_MENU_ROW_IRON_REFINED = "IronRefined"
Constants.RESULTS_MENU_ROW_ENEMIES_KILLED = "EnemiesKilled"
Constants.RESULTS_MENU_ROW_DAMAGE_GIVEN = "DamageGiven"
Constants.RESULTS_MENU_ROW_NAME_LABEL = "Name"
Constants.RESULTS_MENU_ROW_ICON = "Icon"
Constants.RESULTS_MENU_ROW_VALUE_LABEL = "Value"
-- the crew column: a header over the rows and each row's place ("2nd");
-- both are hidden for a solo player
Constants.RESULTS_MENU_RANK_HEADER_LABEL = "RankHeader"
Constants.RESULTS_MENU_ROW_RANK_LABEL = "Rank"
Constants.RESULTS_MENU_COUNTDOWN_LABEL = "Countdown"
Constants.RESULTS_MENU_REVIVE_BUTTON = "ReviveButton"
Constants.RESULTS_MENU_REVIVE_LABEL = "Label"
Constants.RESULTS_MENU_REVIVE_PRICE_LABEL = "Price"
Constants.RESULTS_MENU_SPECTATE_BUTTON = "SpectateButton"
Constants.RESULTS_MENU_CLOSE_BUTTON = "CloseButton"
-- the Game Over screen (designer-authored ScreenGui, M32): one TextLabel
-- that reads why, shown over a red-tinted world before the Results Menu.
-- ScreenFade (scripts/studio/build_screen_fade_gui.luau) is the black
-- frame that fades in over it and out over the menu
Constants.GAME_OVER_GUI_NAME = "GameOver"
Constants.GAME_OVER_LABEL = "TextLabel"
Constants.SCREEN_FADE_GUI_NAME = "ScreenFade"
Constants.SCREEN_FADE_FRAME = "Black"
-- the Spectate bar (M32; scripts/studio/build_spectate_gui.luau): who a
-- dead player is watching, arrows to change, and the way back to the
-- Results Menu
Constants.SPECTATE_GUI_NAME = "Spectate"
Constants.SPECTATE_BAR = "Bar"
Constants.SPECTATE_PREVIOUS_BUTTON = "PreviousButton"
Constants.SPECTATE_NEXT_BUTTON = "NextButton"
Constants.SPECTATE_NAME_LABEL = "NameLabel"
Constants.SPECTATE_RESULTS_BUTTON = "ResultsButton"
Constants.SPECTATE_LOBBY_BUTTON = "LobbyButton"
-- right of the bar: the Revive on offer under a countdown, gone when its
-- time is up
Constants.SPECTATE_REVIVE_BOX = "ReviveBox"
Constants.SPECTATE_REVIVE_BUTTON = "ReviveButton"
Constants.SPECTATE_REVIVE_TIMER_LABEL = "Timer"
-- the Give Currency menu (M32; scripts/studio/build_give_currency_gui.luau):
-- a send page and a confirmation page in one dialog
Constants.GIVE_CURRENCY_GUI_NAME = "GiveCurrency"
Constants.GIVE_CURRENCY_DIALOG = "Dialog"
Constants.GIVE_CURRENCY_SEND_PAGE = "SendPage"
Constants.GIVE_CURRENCY_CONFIRM_PAGE = "ConfirmPage"
Constants.GIVE_CURRENCY_THUMBNAIL = "Thumbnail"
Constants.GIVE_CURRENCY_TITLE_LABEL = "Title"
Constants.GIVE_CURRENCY_GOLD_ROW = "GoldRow"
Constants.GIVE_CURRENCY_IRON_ROW = "IronRow"
Constants.GIVE_CURRENCY_ROW_ICON = "Icon"
Constants.GIVE_CURRENCY_ROW_MINUS_BUTTON = "MinusButton"
Constants.GIVE_CURRENCY_ROW_PLUS_BUTTON = "PlusButton"
Constants.GIVE_CURRENCY_ROW_AMOUNT_BOX = "Amount"
Constants.GIVE_CURRENCY_ROW_OWNED_LABEL = "Owned"
Constants.GIVE_CURRENCY_SEND_BUTTON = "SendButton"
Constants.GIVE_CURRENCY_CLOSE_BUTTON = "CloseButton"
Constants.GIVE_CURRENCY_NAME_LABEL = "Name"
Constants.GIVE_CURRENCY_GOLD_AMOUNT = "GoldAmount"
Constants.GIVE_CURRENCY_IRON_AMOUNT = "IronAmount"
Constants.GIVE_CURRENCY_AMOUNT_VALUE_LABEL = "Value"
Constants.GIVE_CURRENCY_CONFIRM_BUTTON = "ConfirmButton"
Constants.GIVE_CURRENCY_BACK_BUTTON = "BackButton"

-- gadgets (M66): the template folder under GameAssets and the Auto
-- Turret's parts (the designer's model: the head carries the muzzle, the
-- Stand is the base), its server shadow folder, and its prompt text
Constants.GADGET_TEMPLATES_FOLDER = "Gadgets"
Constants.AUTO_TURRET_TEMPLATE = "AUTO_TURRET"
Constants.AUTO_TURRET_HEAD_PART = "MachineGun"
Constants.AUTO_TURRET_BASE_PART = "Stand"
Constants.AUTO_TURRET_MUZZLE_ATTACHMENT = "MuzzleAttachment"
Constants.AUTO_TURRET_SHADOW_FOLDER = "AutoTurretShadows"
Constants.AUTO_TURRET_PICK_UP_ACTION_TEXT = "Pick Up"
-- the Remote Charge (2026-10-20): the planted charge's model under
-- GameAssets/Gadgets (build_remote_charge_template.luau), the part of it
-- that blinks, and the server's shadow folder
Constants.REMOTE_CHARGE_TEMPLATE = "REMOTE_CHARGE"
Constants.REMOTE_CHARGE_LIGHT_PART = "Light"
Constants.REMOTE_CHARGE_SHADOW_FOLDER = "RemoteChargeShadows"
-- the gadget variant (ToolManager) the hand holds once the mine is
-- planted: the "GADGET_REMOTE_CHARGE_DETONATOR" template, and the slot's name
Constants.REMOTE_CHARGE_DETONATOR_VARIANT = "DETONATOR"
Constants.REMOTE_CHARGE_DETONATOR_NAME = "Detonator"
-- the Flare (2026-10-20): the lit flare's model under GameAssets/Gadgets
-- (build_flare_template.luau, which also builds the fired flare under
-- GameAssets/Projectiles and keeps the FlareGun art) and the server's
-- shadow folder
Constants.FLARE_TEMPLATE = "FLARE"
Constants.FLARE_SHADOW_FOLDER = "FlareShadows"
-- the Drill Rig's stock billboard (2026-10-22) under GameAssets/Gui
-- (build_drill_rig_billboard.luau): a row per raw resource, the icon
-- and the count, and the Collect prompt's words
Constants.DRILL_RIG_STOCK_BILLBOARD = "DrillRigStock"
Constants.DRILL_RIG_STOCK_ROOT_FRAME = "Root"
Constants.DRILL_RIG_STOCK_ROW_PREFIX = "Row"
Constants.DRILL_RIG_STOCK_ROW_ICON = "Icon"
Constants.DRILL_RIG_STOCK_ROW_COUNT = "Count"
Constants.DRILL_RIG_COLLECT_ACTION_TEXT = "Collect"
-- collision groups (PhysicsService, registered by DynamiteManager,
-- 2026-10-20): every character's parts, and a thrown stick, which passes
-- through them so it leaves the thrower's own body cleanly
Constants.COLLISION_GROUP_CHARACTER = "Character"
Constants.COLLISION_GROUP_DYNAMITE = "Dynamite"
-- the Binoculars' tag callout (scripts/studio/build_tag_billboard.luau,
-- 2026-10-19): the billboard template over a tagged monster, its icon and
-- label, and the workspace folder its anchors live in
Constants.TAG_BILLBOARD = "TagCallout"
-- the Missile Launcher's locked-target marker (2026-10-20): a reticle over
-- every monster the post has locked (ClientLockMarkerManager)
Constants.LOCK_MARKER_BILLBOARD = "LockMarker"
Constants.LOCK_MARKER_ICON = "Icon"
Constants.TAG_ICON = "Icon"
Constants.TAG_LABEL = "Label"
Constants.TAG_FOLDER = "TagCallouts"
-- the Stim Shot's white edge flash (scripts/studio/build_stim_vignette_gui.luau, 2026-10-19)
Constants.STIM_VIGNETTE_GUI_NAME = "StimVignette"
-- the red edge glow on a hit (2026-10-26), the Stim vignette's shape in red
Constants.HURT_VIGNETTE_GUI_NAME = "HurtVignette"
-- the black edges that close in as the Chase nears (M68, 2026-10-26)
Constants.CHASE_VIGNETTE_GUI_NAME = "ChaseVignette"
-- the tool bar's grey cooldown sheet over a slot (build_tool_bar_gui)
Constants.TOOL_SLOT_COOLDOWN_OVERLAY = "CooldownOverlay"
-- the UIGradient on the sheet that hides its spent part, top to bottom
-- (the day clock's way, designer 2026-10-29)
Constants.TOOL_SLOT_COOLDOWN_MASK = "Mask"
-- the gadget block of the Post & Gadget Upgrades menu (M67): its heading
-- in the List, authored by build_post_upgrade_menu_gui; the row is a
-- RowTemplate clone named here
Constants.UPGRADE_MENU_GADGET_TITLE_LABEL = "GadgetTitle"
Constants.UPGRADE_MENU_GADGET_ROW = "Gadget"

return Constants
