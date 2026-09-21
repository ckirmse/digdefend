--!strict

-- The touch action button (GDD "Mining Rock", decided 2026-09-16): one
-- on-screen button beside the jump button that does whatever the equipped
-- tool does. Pick axe: press swings at the highlighted block and holding
-- repeats (ClientMiningManager:beginHold/endHold); a rested touch hold in
-- the free screen area does the same, so one thumb can mine and look.
-- Dynamite: press throws (ClientDynamiteManager:use). Torch: press places
-- (ClientTorchManager:use); those two act only from this button, since a
-- tap is too easy to make by accident. Keyboard and gamepad players never
-- see it. The button lives in GameplayHud
-- (scripts/studio/build_gameplay_hud_gui.luau).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientDynamiteManager = require(script.Parent.ClientDynamiteManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientPlacementToolManager = require(script.Parent.ClientPlacementToolManager)
local ClientStructureManager = require(script.Parent.ClientStructureManager)
local ClientTorchManager = require(script.Parent.ClientTorchManager)
local ClientWeaponManager = require(script.Parent.ClientWeaponManager)

local ClientActionButtonManager = {}
ClientActionButtonManager.__index = ClientActionButtonManager

export type ClientActionButtonManager = typeof(setmetatable(
	{} :: {
		button: GuiButton?,
		label: TextLabel?,
		equippedTool: number?,
		isTouchOnly: boolean,
	},
	ClientActionButtonManager
))

-- tools with an action the button can trigger
local ACTIONABLE_TOOLS = {
	[Enums.ToolKind.PICK_AXE] = true,
	[Enums.ToolKind.DYNAMITE] = true,
	[Enums.ToolKind.TORCH] = true,
	[Enums.ToolKind.HAMMER] = true,
	[Enums.ToolKind.WEAPON] = true,
	[Enums.ToolKind.DEFENSES] = true,
}

function ClientActionButtonManager:onPressed()
	local tool = self.equippedTool
	if tool == Enums.ToolKind.PICK_AXE then
		ClientMiningManager:beginHold()
	elseif tool == Enums.ToolKind.DYNAMITE then
		ClientDynamiteManager:use()
	elseif tool == Enums.ToolKind.TORCH then
		ClientTorchManager:use()
	elseif tool == Enums.ToolKind.HAMMER then
		ClientStructureManager:beginHold()
	elseif tool == Enums.ToolKind.WEAPON then
		ClientWeaponManager:beginHold()
	elseif tool == Enums.ToolKind.DEFENSES then
		ClientPlacementToolManager:build()
	end
end

-- the pick axe, the Hammer, and the weapon are holds; releasing anything
-- else is a no-op
function ClientActionButtonManager:onReleased()
	ClientMiningManager:endHold()
	ClientStructureManager:endHold()
	ClientWeaponManager:endHold()
end

function ClientActionButtonManager:render()
	local button = self.button
	if not button then
		return
	end
	local tool = self.equippedTool
	local isActionable = tool ~= nil and ACTIONABLE_TOOLS[tool :: number] == true
	button.Visible = self.isTouchOnly and isActionable
	local label = self.label
	if label and isActionable then
		label.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.ToolKind, tool :: number) or "?")
	end
end

function ClientActionButtonManager:onEquippedChanged(value: any)
	-- a swap mid-hold must not leave the pick axe or the Hammer swinging,
	-- or the weapon firing
	ClientMiningManager:endHold()
	ClientStructureManager:endHold()
	ClientWeaponManager:endHold()
	self.equippedTool = if typeof(value) == "number" then value else nil
	self:render()
end

function ClientActionButtonManager:init()
	self.isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GAMEPLAY_HUD_GUI_NAME, 10)
	local button = if gui then gui:FindFirstChild(Constants.HUD_ACTION_BUTTON) else nil
	if not button or not button:IsA("GuiButton") then
		warn("ClientActionButtonManager: GameplayHud is missing ActionButton; run scripts/studio/build_gameplay_hud_gui.luau")
		return
	end
	self.button = button
	local label = button:FindFirstChild(Constants.HUD_ACTION_LABEL)
	self.label = if label and label:IsA("TextLabel") then label else nil
	button.MouseButton1Down:Connect(
		function()
			self:onPressed()
		end
	)
	button.MouseButton1Up:Connect(
		function()
			self:onReleased()
		end
	)
	-- a finger that slides off the button ends the hold too
	button.MouseLeave:Connect(
		function()
			self:onReleased()
		end
	)
	self:onEquippedChanged(ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL))
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.EQUIPPED_TOOL,
		function(value: any)
			self:onEquippedChanged(value)
		end
	)
end

function ClientActionButtonManager.new(): ClientActionButtonManager
	local self = setmetatable({}, ClientActionButtonManager) :: ClientActionButtonManager
	self.button = nil
	self.label = nil
	self.equippedTool = nil
	self.isTouchOnly = false
	return self
end

return ClientActionButtonManager.new()
