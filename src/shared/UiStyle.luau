--!strict

-- The shared visual language every GUI reuses: fonts, palette, timings, and
-- text size bounds (CLAUDE.md "UI standards"). Data only, shared so the
-- Studio build scripts under scripts/studio/ and the client managers read the
-- same values. Decided 2026-09-11 (M10); expected to change with real art.
local UiStyle = {}

-- Poppins is a Creator Store font family; Montserrat ships with Roblox
UiStyle.TITLE_FONT_FAMILY = "rbxassetid://11702779409"
UiStyle.BODY_FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"

-- titles are always bold and always ALL CAPS (use formatTitle)
UiStyle.TITLE_FONT = Font.new(UiStyle.TITLE_FONT_FAMILY, Enum.FontWeight.Bold)
UiStyle.BODY_FONT = Font.new(UiStyle.BODY_FONT_FAMILY, Enum.FontWeight.Regular)
UiStyle.BODY_BOLD_FONT = Font.new(UiStyle.BODY_FONT_FAMILY, Enum.FontWeight.SemiBold)

UiStyle.BACKGROUND_COLOR = Color3.fromRGB(18, 16, 14)
UiStyle.PANEL_COLOR = Color3.fromRGB(34, 31, 28)
UiStyle.PANEL_TRANSPARENCY = 0.15
UiStyle.ACCENT_COLOR = Color3.fromRGB(245, 200, 80)
UiStyle.ACCENT_STROKE_COLOR = Color3.fromRGB(60, 35, 10)
UiStyle.TEXT_COLOR = Color3.fromRGB(255, 255, 255)
UiStyle.TEXT_MUTED_COLOR = Color3.fromRGB(190, 184, 176)
UiStyle.POSITIVE_COLOR = Color3.fromRGB(90, 230, 100)
UiStyle.NEGATIVE_COLOR = Color3.fromRGB(240, 80, 70)
UiStyle.DISABLED_COLOR = Color3.fromRGB(110, 106, 100)
-- every HP bar runs HP_FULL_COLOR to HP_EMPTY_COLOR as the thing weakens
UiStyle.HP_FULL_COLOR = Color3.fromRGB(90, 200, 110)
UiStyle.HP_EMPTY_COLOR = Color3.fromRGB(220, 70, 60)
UiStyle.EMPTY_SLOT_COLOR = Color3.fromRGB(52, 48, 44)
-- the announcement box (top centre): blue so it never reads as an error
UiStyle.ANNOUNCEMENT_COLOR = Color3.fromRGB(40, 100, 200)

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
-- how much a HUD element swells (1 = none) when a flying icon lands on it
UiStyle.HUD_BUMP_SCALE = 1.12
UiStyle.BALANCE_FLASH_SEC = 0.6

function UiStyle.formatTitle(text: string): string
	return string.upper(text)
end

return UiStyle
