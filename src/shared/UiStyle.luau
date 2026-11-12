--!strict

-- The shared visual language every GUI reuses: fonts, palette, timings, and
-- text size bounds (CLAUDE.md "UI standards"). Data only, shared so the
-- Studio build scripts under scripts/studio/ and the client managers read the
-- same values. Decided 2026-09-11 (M10); expected to change with real art.
local Enums = require(script.Parent.Enums)

local UiStyle = {}

-- Poppins is a Creator Store font family; Montserrat ships with Roblox
UiStyle.TITLE_FONT_FAMILY = "rbxassetid://11702779409"
UiStyle.BODY_FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"

-- titles are always bold and always ALL CAPS (use formatTitle)
UiStyle.TITLE_FONT = Font.new(UiStyle.TITLE_FONT_FAMILY, Enum.FontWeight.Bold)
UiStyle.BODY_FONT = Font.new(UiStyle.BODY_FONT_FAMILY, Enum.FontWeight.Regular)
UiStyle.BODY_BOLD_FONT = Font.new(UiStyle.BODY_FONT_FAMILY, Enum.FontWeight.SemiBold)
-- a lighter title face for small HUD captions such as the day counter (designer, 2026-09-25)
UiStyle.TITLE_SEMIBOLD_FONT = Font.new(UiStyle.TITLE_FONT_FAMILY, Enum.FontWeight.SemiBold)

UiStyle.BACKGROUND_COLOR = Color3.fromRGB(18, 16, 14)
UiStyle.PANEL_COLOR = Color3.fromRGB(34, 31, 28)
UiStyle.PANEL_TRANSPARENCY = 0.15
UiStyle.ACCENT_COLOR = Color3.fromRGB(245, 200, 80)
UiStyle.ACCENT_STROKE_COLOR = Color3.fromRGB(60, 35, 10)
UiStyle.TEXT_COLOR = Color3.fromRGB(255, 255, 255)
UiStyle.TEXT_MUTED_COLOR = Color3.fromRGB(190, 184, 176)
UiStyle.POSITIVE_COLOR = Color3.fromRGB(90, 230, 100)
-- the loading screen's bar fill, from the designer's Loading mock-up (2026-10-28)
UiStyle.LOADING_FILL_COLOR = Color3.fromRGB(182, 251, 93)
UiStyle.NEGATIVE_COLOR = Color3.fromRGB(240, 80, 70)
-- the day clock's bar by the time of day (designer, 2026-11-11): its
-- authored colour in the morning, this orange at midday, this red at sunset
UiStyle.DAY_CLOCK_MIDDAY_COLOR = Color3.fromRGB(245, 140, 50)
UiStyle.DAY_CLOCK_SUNSET_COLOR = Color3.fromRGB(235, 65, 50)
-- a switch toggle's track, off and on (the Create Party menu's Friends
-- Only switch, designer 2026-10-30)
UiStyle.TOGGLE_OFF_COLOR = Color3.fromRGB(255, 89, 89)
UiStyle.TOGGLE_ON_COLOR = Color3.fromRGB(90, 230, 100)
UiStyle.DISABLED_COLOR = Color3.fromRGB(110, 106, 100)
-- the Robux sign, a glyph every Roblox font carries; a price reads as the
-- glyph then the number (the resource-icon rule, with the glyph as the icon)
UiStyle.ROBUX_GLYPH = utf8.char(0xE002)
-- the Diamond Store's card banner (BEST VALUE and the like), the accent on
-- a dark title
UiStyle.STORE_BANNER_COLOR = Color3.fromRGB(245, 200, 80)
UiStyle.STORE_BANNER_TEXT_COLOR = Color3.fromRGB(34, 31, 28)
-- the tool bar slot's backing picture, plain and for the equipped tool
-- (designer, 2026-10-29)
UiStyle.TOOL_SLOT_COLOR = Color3.fromRGB(0, 0, 0)
UiStyle.TOOL_SLOT_SELECTED_COLOR = Color3.fromRGB(124, 124, 124)
-- the character sheet's REROLL ODDS button: a quiet grey so it never reads as a buy (designer, 2026-10-13)
UiStyle.ODDS_BUTTON_COLOR = Color3.fromRGB(124, 124, 124)
-- the Class Menu's Supply Crate plate, and the Odds plate while it sends
-- the player there (designer, 2026-11-05)
UiStyle.SUPPLY_CRATE_BUTTON_COLOR = Color3.fromRGB(245, 200, 80)
-- every HP bar runs HP_FULL_COLOR to HP_EMPTY_COLOR as the thing weakens
UiStyle.HP_FULL_COLOR = Color3.fromRGB(90, 200, 110)
-- the Ore Scanner (2026-10-22): the sweep's sphere, and the highlight
-- over each ore kind it finds, keyed by Enums.RawResource
UiStyle.ORE_SCAN_SPHERE_COLOR = Color3.fromRGB(255, 40, 40)
UiStyle.ORE_SCAN_COLOR_BY_RESOURCE = {
	[Enums.RawResource.IRON_ORE] = Color3.fromRGB(170, 190, 215),
	[Enums.RawResource.GOLD_ORE] = Color3.fromRGB(255, 200, 40),
	[Enums.RawResource.URANIUM_ORE] = Color3.fromRGB(90, 255, 90),
}
UiStyle.HP_EMPTY_COLOR = Color3.fromRGB(220, 70, 60)
UiStyle.EMPTY_SLOT_COLOR = Color3.fromRGB(52, 48, 44)
-- the announcement box (top centre): blue so it never reads as an error
UiStyle.ANNOUNCEMENT_COLOR = Color3.fromRGB(40, 100, 200)
-- the alert box: danger, red (2026-09-25)
UiStyle.ALERT_COLOR = Color3.fromRGB(190, 40, 40)

-- bullet streaks: every hitscan weapon draws the default, and a post kind
-- listed here draws its own so two guns that fire alike still look
-- different (the Minigun's light blue, 2026-10-19)
UiStyle.TRACER_COLOR = Color3.fromRGB(255, 230, 140)
UiStyle.POST_TRACER_COLORS = {
	[Enums.PostWeaponKind.MINI_GUN] = Color3.fromRGB(150, 210, 255),
	-- the Railgun's bolt is a laser, so red (2026-10-19)
	[Enums.PostWeaponKind.RAIL_GUN] = Color3.fromRGB(255, 60, 60),
}
-- how fast a post kind's streak crosses the world when the default (the
-- hand weapons' 900 studs a second) reads too slow: the Railgun's bolt is
-- twice that, since a sniper's shot should feel instant (2026-10-19)
UiStyle.POST_TRACER_SPEEDS = {
	[Enums.PostWeaponKind.RAIL_GUN] = 1800,
}

-- the compass dot of each crew member, by the colour index the server
-- hands out (GameData/Mining/Compass.PLAYER_COLOR_COUNT of them)
UiStyle.COMPASS_PLAYER_COLORS = {
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(90, 230, 100),
	Color3.fromRGB(255, 150, 40),
	Color3.fromRGB(200, 110, 255),
	Color3.fromRGB(255, 120, 200),
}

UiStyle.CORNER_RADIUS_PX = 10
UiStyle.STROKE_PX = 2

-- UITextSizeConstraint bounds; scaled text is always constrained by these.
-- The minimums are 1 (no floor, decided 2026-09-16): a floor stops scaled
-- text shrinking into a small phone label and clips it instead ("Weapo").
-- Text too small to read is fixed by giving the label more room
UiStyle.TITLE_TEXT_MIN_PX = 1
UiStyle.TITLE_TEXT_MAX_PX = 110
UiStyle.BODY_TEXT_MIN_PX = 1
UiStyle.BODY_TEXT_MAX_PX = 26
UiStyle.LABEL_TEXT_MIN_PX = 1
UiStyle.LABEL_TEXT_MAX_PX = 18
-- the only pixel minimum a layout may carry: Roblox's touch-target floor
UiStyle.TOUCH_TARGET_MIN_PX = 44

UiStyle.HUD_TWEEN_SEC = 0.2
-- a HUD element sliding on or off stage (the day clock, the Refinery HP
-- bar, the Camp Map at dusk and dawn; M33)
UiStyle.HUD_SLIDE_SEC = 0.9
-- how much a HUD element swells (1 = none) when a flying icon lands on it
UiStyle.HUD_BUMP_SCALE = 1.12
UiStyle.BALANCE_FLASH_SEC = 0.6
-- a purchase the player cannot afford: the balance flashes red this many
-- times, each on for this long and off for as long again
UiStyle.BALANCE_SHORT_FLASH_COUNT = 3
UiStyle.BALANCE_SHORT_FLASH_SEC = 0.2

-- the Camp Map (M33): a structure's colour by Enums.StructureHealthBand,
-- the players' dots (each crewmate in their compass colour, the local
-- player ringed), and the monsters' smaller red dots
UiStyle.CAMP_MAP_BAND_COLORS = {
	[Enums.StructureHealthBand.FULL] = Color3.fromRGB(255, 255, 255),
	[Enums.StructureHealthBand.HIGH] = Color3.fromRGB(250, 220, 60),
	[Enums.StructureHealthBand.MID] = Color3.fromRGB(255, 150, 40),
	[Enums.StructureHealthBand.LOW] = Color3.fromRGB(240, 70, 60),
	[Enums.StructureHealthBand.DESTROYED] = Color3.fromRGB(0, 0, 0),
}
UiStyle.CAMP_MAP_LOCAL_PLAYER_RING_COLOR = Color3.fromRGB(255, 255, 255)

-- the rarity ladder's colours (designer, 2026-10-12), the convention most
-- games share: grey, green, blue, purple, gold. An item's name and its
-- rarity word take the colour wherever they show (the character sheet's
-- gear cards and skill rows, the roll screen, the Rank band)
UiStyle.RARITY_COLORS = {
	[Enums.Rarity.COMMON] = Color3.fromRGB(200, 200, 200),
	[Enums.Rarity.UNCOMMON] = Color3.fromRGB(90, 220, 90),
	[Enums.Rarity.RARE] = Color3.fromRGB(80, 150, 255),
	[Enums.Rarity.EPIC] = Color3.fromRGB(190, 100, 255),
	[Enums.Rarity.LEGENDARY] = Color3.fromRGB(255, 170, 40),
}
UiStyle.CAMP_MAP_MONSTER_COLOR = Color3.fromRGB(230, 40, 40)
-- the class gacha's tiles and odds rows by what they hold (M70): a class
-- in the accent gold, a cosmetic in the Rare blue, Keys in the Common grey
UiStyle.GACHA_KIND_COLORS = {
	[Enums.GachaResultKind.CLASS] = Color3.fromRGB(245, 200, 80),
	[Enums.GachaResultKind.SKILL_SLOT] = Color3.fromRGB(245, 200, 80),
	[Enums.GachaResultKind.COSMETIC] = Color3.fromRGB(80, 150, 255),
	[Enums.GachaResultKind.KEYS] = Color3.fromRGB(200, 200, 200),
}
-- the 3D crate opening (M70, designer 2026-11-03): the camera's glide
-- between its shots, the world fading round the crate, the TAP CRATE TO
-- OPEN line, the lid swinging up, the prize card flying out of the crate
-- to the screen's centre, and the card stroke's pulse
UiStyle.GACHA_CAMERA_TWEEN_SEC = 1
UiStyle.GACHA_WORLD_FADE_SEC = 0.8
UiStyle.GACHA_TAP_HINT_FADE_SEC = 0.4
UiStyle.GACHA_LID_OPEN_SEC = 0.7
UiStyle.GACHA_CARD_FLY_SEC = 0.6
UiStyle.GACHA_STROKE_PULSE_SEC = 0.6
-- the panel easing back in after a claim (designer, 2026-11-03)
UiStyle.GACHA_PANEL_FADE_SEC = 0.5
-- the 3D class card (designer, 2026-11-03): its rise out of the crate, a
-- newly earned star's colour turning gold, and the star colours themselves
UiStyle.GACHA_CARD_RISE_SEC = 0.8
-- a maxed class's card sinking back for Keys, twice the rise's pace
-- (designer, 2026-11-04)
-- a cosmetic prize's size at PrizeStart as a share of its PrizeEnd size,
-- grown over the rise (designer, 2026-11-04)
UiStyle.GACHA_PRIZE_START_SCALE_SHARE = 0.2
UiStyle.GACHA_CARD_SINK_SEC = 0.4
-- the Key's rise out of the crate and one full turn about its upright
-- while it waits for the claim (designer, 2026-11-03); a cosmetic prize
-- spins at the same pace, halved to 4 s a turn on 2026-11-04
UiStyle.GACHA_KEY_RISE_SEC = 0.8
UiStyle.GACHA_KEY_SPIN_SEC = 4
-- the landed class card's idle (designer, 2026-11-04): a slow bob about
-- CardEnd, its height as a share of the card's, with a slight tilt
UiStyle.GACHA_CARD_FLOAT_PERIOD_SEC = 3.5
UiStyle.GACHA_CARD_FLOAT_HEIGHT_SHARE = 0.06
UiStyle.GACHA_CARD_FLOAT_TILT_DEGREES = 4
-- the float's swing grows from nothing over this long, so the landed
-- card eases into its drift instead of snapping to it
UiStyle.GACHA_CARD_FLOAT_EASE_IN_SEC = 1.2
UiStyle.GACHA_STAR_FILL_SEC = 0.5
-- the beat between the card landing and its new star lighting (designer)
UiStyle.GACHA_STAR_DELAY_SEC = 0.5
UiStyle.CLASS_CARD_STAR_GOLD_COLOR = Color3.fromRGB(239, 184, 56)
UiStyle.CLASS_CARD_STAR_DARK_COLOR = Color3.fromRGB(17, 17, 17)
-- the Class Menu's unfilled star, on the header's black box (designer,
-- 2026-11-05); the 3D card keeps its own dark
UiStyle.CLASS_MENU_STAR_DARK_COLOR = Color3.fromRGB(27, 42, 53)
-- the gap between the HUD's Diamonds and Keys wallets when both show, as
-- a share of the screen width
UiStyle.HUD_WALLET_GAP_SCALE = 0.01

function UiStyle.formatTitle(text: string): string
	return string.upper(text)
end

return UiStyle
