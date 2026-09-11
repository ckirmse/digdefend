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
UiStyle.EMPTY_SLOT_COLOR = Color3.fromRGB(52, 48, 44)

UiStyle.CORNER_RADIUS_PX = 10
UiStyle.STROKE_PX = 2

-- UITextSizeConstraint bounds; scaled text is always constrained by these
UiStyle.TITLE_TEXT_MIN_PX = 20
UiStyle.TITLE_TEXT_MAX_PX = 110
UiStyle.BODY_TEXT_MIN_PX = 14
UiStyle.BODY_TEXT_MAX_PX = 26
UiStyle.LABEL_TEXT_MIN_PX = 10
UiStyle.LABEL_TEXT_MAX_PX = 18

UiStyle.HUD_TWEEN_SEC = 0.2
UiStyle.BALANCE_FLASH_SEC = 0.6

function UiStyle.formatTitle(text: string): string
	return string.upper(text)
end

return UiStyle
