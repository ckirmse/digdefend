--!strict

-- Places the touch buttons around Roblox's own jump button (decided
-- 2026-09-16). Roblox builds its touch controls in PlayerGui.TouchGui, so
-- the live jump button's position and size are readable here; the weapon's
-- secondary button (scope, grenade) goes directly above it at the jump
-- button's size, the backpack and fuel stack goes one button's height
-- above it (the room the JET button
-- took until 2026-11-11, when the jump button took the jet pack over; the
-- stack keeps its height, designer the same day), and both follow
-- the jump button whenever it moves or resizes (a rotation, a resolution
-- change). The build
-- script's own positions are only the fallback when there is no jump
-- button. This is
-- the one place offsets are computed from Roblox's GUI, and the reason is
-- the GUI standard's rule that nothing may sit where Roblox can cover it.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")

local ClientTouchLayoutManager = {}
ClientTouchLayoutManager.__index = ClientTouchLayoutManager

export type ClientTouchLayoutManager = typeof(setmetatable(
	{} :: {
		jumpButton: GuiObject?,
		secondaryButton: GuiObject?,
		rightStack: GuiObject?,
	},
	ClientTouchLayoutManager
))

-- gap between our buttons and the jump button, as a fraction of its size
local GAP_FRACTION = 0.15
local JUMP_BUTTON_WAIT_SEC = 10

function ClientTouchLayoutManager:layout()
	local jump = self.jumpButton
	if not jump then
		return
	end
	local size = jump.AbsoluteSize
	local position = jump.AbsolutePosition
	local gap = size.X * GAP_FRACTION
	-- AbsolutePosition is measured from the same origin for both guis
	-- (neither ignores the top bar inset), so no inset arithmetic here
	local secondary = self.secondaryButton
	if secondary then
		secondary.AnchorPoint = Vector2.new(0, 0)
		secondary.Size = UDim2.fromOffset(size.X, size.Y)
		secondary.Position = UDim2.fromOffset(position.X, position.Y - size.Y - gap)
	end
	-- the stack keeps its scale size; only its bottom edge is pinned, a
	-- button's height and two gaps above the jump button
	local stack = self.rightStack
	if stack then
		stack.AnchorPoint = Vector2.new(1, 1)
		stack.Position = UDim2.fromOffset(position.X + size.X, position.Y - size.Y - gap * 2)
	end
end

function ClientTouchLayoutManager:getJumpButton(): GuiObject?
	return self.jumpButton
end

-- Post Weapon Mode has no jumping: the jump button gives way to an Exit
-- button in the same spot (decided 2026-09-18)
function ClientTouchLayoutManager:setJumpButtonHidden(isHidden: boolean)
	local jump = self.jumpButton
	if jump then
		jump.Visible = not isHidden
	end
end

function ClientTouchLayoutManager:watchJumpButton(jump: GuiObject)
	self.jumpButton = jump
	jump:GetPropertyChangedSignal("AbsolutePosition"):Connect(
		function()
			self:layout()
		end
	)
	jump:GetPropertyChangedSignal("AbsoluteSize"):Connect(
		function()
			self:layout()
		end
	)
	self:layout()
end

function ClientTouchLayoutManager:init()
	if not UserInputService.TouchEnabled then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GAMEPLAY_HUD_GUI_NAME, 10)
	if not gui then
		return
	end
	local stack = gui:FindFirstChild(Constants.HUD_RIGHT_STACK)
	local weaponGui = playerGui:WaitForChild(Constants.WEAPON_HUD_GUI_NAME, 10)
	local secondary = if weaponGui then weaponGui:FindFirstChild(Constants.WEAPON_HUD_SECONDARY_BUTTON) else nil
	self.secondaryButton = if secondary and secondary:IsA("GuiObject") then secondary else nil
	self.rightStack = if stack and stack:IsA("GuiObject") then stack else nil
	-- the touch gui is built by Roblox's PlayerModule shortly after spawn
	task.spawn(
		function()
			local touchGui = playerGui:WaitForChild(Constants.TOUCH_GUI_NAME, JUMP_BUTTON_WAIT_SEC)
			local frame = if touchGui then touchGui:WaitForChild(Constants.TOUCH_CONTROL_FRAME_NAME, JUMP_BUTTON_WAIT_SEC) else nil
			local jump = if frame then frame:WaitForChild(Constants.TOUCH_JUMP_BUTTON_NAME, JUMP_BUTTON_WAIT_SEC) else nil
			if jump and jump:IsA("GuiObject") then
				self:watchJumpButton(jump)
			else
				warn("ClientTouchLayoutManager: no TouchGui jump button found; touch buttons keep their built-in positions")
			end
		end
	)
end

function ClientTouchLayoutManager.new(): ClientTouchLayoutManager
	local self = setmetatable({}, ClientTouchLayoutManager) :: ClientTouchLayoutManager
	self.jumpButton = nil
	self.secondaryButton = nil
	self.rightStack = nil
	return self
end

return ClientTouchLayoutManager.new()
