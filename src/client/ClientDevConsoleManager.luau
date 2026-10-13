--!strict

-- The Developer Console (F9) is unusable in a first-person run: the camera
-- holds the mouse, so its tabs cannot be clicked (2026-10-13, a tester
-- could not reach the Server tab). While the console is open this drops
-- the player to the classic camera and frees the mouse every frame, the
-- way ClientDevTools does for its own panels, and restores the camera
-- mode it found when the console closes. Anyone may open the console, so
-- this is common and never admin-gated.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local ClientDevConsoleManager = {}
ClientDevConsoleManager.__index = ClientDevConsoleManager

export type ClientDevConsoleManager = typeof(setmetatable(
	{} :: {
		isConsoleOpen: boolean,
		-- the camera mode to go back to when the console closes
		savedCameraMode: Enum.CameraMode?,
	},
	ClientDevConsoleManager
))

local POLL_SEC = 0.25
local MOUSE_RELEASE_STEP = "DevConsoleMouseRelease"
local MOUSE_RELEASE_PRIORITY = Enum.RenderPriority.Last.Value

local function isConsoleVisible(): boolean
	local isSuccess, isVisible = pcall(
		function()
			return StarterGui:GetCore("DevConsoleVisible")
		end
	)
	return isSuccess and isVisible == true
end

function ClientDevConsoleManager:setConsoleOpen(isOpen: boolean)
	if isOpen == self.isConsoleOpen then
		return
	end
	self.isConsoleOpen = isOpen
	local player = Players.LocalPlayer
	if isOpen then
		self.savedCameraMode = player.CameraMode
		player.CameraMode = Enum.CameraMode.Classic
		RunService:BindToRenderStep(
			MOUSE_RELEASE_STEP,
			MOUSE_RELEASE_PRIORITY,
			function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		)
	else
		RunService:UnbindFromRenderStep(MOUSE_RELEASE_STEP)
		local savedCameraMode: Enum.CameraMode? = self.savedCameraMode
		if savedCameraMode then
			player.CameraMode = savedCameraMode
		end
		self.savedCameraMode = nil
	end
end

function ClientDevConsoleManager:init()
	task.spawn(
		function()
			while true do
				self:setConsoleOpen(isConsoleVisible())
				task.wait(POLL_SEC)
			end
		end
	)
end

function ClientDevConsoleManager.new(): ClientDevConsoleManager
	local self = setmetatable({}, ClientDevConsoleManager) :: ClientDevConsoleManager
	self.isConsoleOpen = false
	self.savedCameraMode = nil
	return self
end

return ClientDevConsoleManager.new()
