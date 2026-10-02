-- Builds the "WeaponUpgrade" ScreenGui under StarterGui as a copy of the
-- live "PostUpgrade" one (GDD "Weapon Upgrades", decided 2026-10-01): the
-- two menus are the same build, so the designer's tuning of the post menu
-- carries over and both read alike. Only the title text differs; the rows
-- are cloned from RowTemplate by ClientWeaponUpgradeManager (Damage, Ammo,
-- Range). Run from the Studio command bar (or the MCP execute_luau tool)
-- in the gameplay place after build_post_upgrade_menu_gui.luau; it
-- replaces any existing copy. Names must match Constants.UPGRADE_MENU_*.
local StarterGui = game:GetService("StarterGui")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local UiStyle = require(game.ReplicatedStorage.Shared.UiStyle)

local SOURCE_NAME = "PostUpgrade"
local GUI_NAME = "WeaponUpgrade"
local TITLE_TEXT = "Upgrade Rifle"

ChangeHistoryService:SetWaypoint("Before WeaponUpgrade gui")

local source = StarterGui:FindFirstChild(SOURCE_NAME)
assert(source and source:IsA("ScreenGui"), "StarterGui has no PostUpgrade ScreenGui; run build_post_upgrade_menu_gui.luau first")

local existing = StarterGui:FindFirstChild(GUI_NAME)
if existing then
	existing:Destroy()
end

local gui = source:Clone()
gui.Name = GUI_NAME
gui.Enabled = false
local dialog = gui:FindFirstChild("Dialog")
local title = if dialog then dialog:FindFirstChild("Title") else nil
if title and title:IsA("TextLabel") then
	title.Text = UiStyle.formatTitle(TITLE_TEXT)
end
gui.Parent = StarterGui

ChangeHistoryService:SetWaypoint("After WeaponUpgrade gui")
print("build_weapon_upgrade_menu_gui: built StarterGui." .. GUI_NAME .. " from " .. SOURCE_NAME)
