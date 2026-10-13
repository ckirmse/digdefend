--!strict

-- Roblox draws its arrow cursor at the centre of a first-person view
-- (seen in a live run, 2026-10-13; Studio made it easy to miss). The
-- cursor's image follows the mouse lock every frame: the small dot
-- (Icons.UI.CURSOR_DOT) while the mouse is locked to the centre, so the
-- player always has an aim point, and Roblox's own arrow whenever
-- anything frees the mouse (a menu's modal backdrop, the dev tools, the
-- Developer Console, the Defense Table). Gameplay only: the lobby is
-- third person and keeps the arrow.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Icons = require("@game/ReplicatedStorage/Shared/Icons")

local ClientCursorManager = {}
ClientCursorManager.__index = ClientCursorManager

export type ClientCursorManager = typeof(setmetatable({} :: {}, ClientCursorManager))

local CURSOR_STEP = "CursorFollowsMouseLock"
-- after every system that sets the mouse behaviour for the frame
local CURSOR_PRIORITY = Enum.RenderPriority.Last.Value + 1

function ClientCursorManager:init()
	RunService:BindToRenderStep(
		CURSOR_STEP,
		CURSOR_PRIORITY,
		function()
			local isLocked = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
			-- "" is Roblox's own arrow
			local icon = if isLocked then Icons.UI.CURSOR_DOT else ""
			if UserInputService.MouseIcon ~= icon then
				UserInputService.MouseIcon = icon
			end
			if not UserInputService.MouseIconEnabled then
				UserInputService.MouseIconEnabled = true
			end
		end
	)
end

function ClientCursorManager.new(): ClientCursorManager
	local self = setmetatable({}, ClientCursorManager) :: ClientCursorManager
	return self
end

return ClientCursorManager.new()
