--!strict

-- Roblox draws its arrow cursor at the centre of a first-person view
-- (seen in a live run, 2026-10-13; Studio made it easy to miss). The
-- cursor's image follows the mouse lock every frame: the small dot
-- (Icons.UI.CURSOR_DOT) while the mouse is locked to the centre, so the
-- player always has an aim point, and Roblox's own arrow whenever
-- anything frees the mouse (a menu's modal backdrop, the dev tools, the
-- Developer Console, the Defense Table). Gameplay only: the lobby is
-- third person and keeps the arrow. Behind a scope glass
-- (ClientScopeGlassManager) the dot stands down: the glass has its own
-- reticle, and a dot over it read as a stray cursor (2026-10-19). The icon
-- is switched back on only when this manager switched it off: Roblox's
-- freecam (Shift+P) hides the cursor itself, and forcing it on every
-- frame put the arrow in every screenshot (designer, 2026-10-30).
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Icons = require("@game/ReplicatedStorage/Shared/Icons")

local ClientCursorManager = {}
ClientCursorManager.__index = ClientCursorManager

export type ClientCursorManager = typeof(setmetatable(
	{} :: {
		isDotHidden: boolean,
		-- true while this manager has the icon off, so only its own hide is undone
		hasHiddenIcon: boolean,
	},
	ClientCursorManager
))

local CURSOR_STEP = "CursorFollowsMouseLock"
-- after every system that sets the mouse behaviour for the frame
local CURSOR_PRIORITY = Enum.RenderPriority.Last.Value + 1

-- while hidden, a locked mouse shows no dot at all; a freed mouse keeps its arrow
function ClientCursorManager:setDotHidden(isHidden: boolean)
	self.isDotHidden = isHidden
end

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
			local isHideWanted = isLocked and self.isDotHidden
			if isHideWanted and UserInputService.MouseIconEnabled then
				UserInputService.MouseIconEnabled = false
				self.hasHiddenIcon = true
			elseif not isHideWanted and self.hasHiddenIcon then
				UserInputService.MouseIconEnabled = true
				self.hasHiddenIcon = false
			end
		end
	)
end

function ClientCursorManager.new(): ClientCursorManager
	local self = setmetatable({}, ClientCursorManager) :: ClientCursorManager
	self.isDotHidden = false
	self.hasHiddenIcon = false
	return self
end

return ClientCursorManager.new()
