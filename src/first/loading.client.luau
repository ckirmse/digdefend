--!strict

-- Runs before anything else replicates: shows the Studio-authored "Loading"
-- ScreenGui (kept under ReplicatedFirst) immediately and removes the default
-- Roblox loading screen. Keeps a minimal dot animation going until
-- ClientLoadingScreenManager takes over. No requires allowed here: waiting on
-- ReplicatedStorage would defeat the point of ReplicatedFirst.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- literals because Attributes.luau and Constants.luau are not replicated yet
local LOADING_HANDOFF = "LoadingHandoff"
local LOADING_SHOWN_AT = "LoadingShownAt"
local LOADING_GUI_NAME = "Loading"
local MAIN_FRAME = "Main"
local STATUS_LABEL = "Status"
-- above every HUD and dialog ScreenGui so nothing enabled during startup shows through
local LOADING_DISPLAY_ORDER = 10000

local DOT_INTERVAL_SEC = 1
local MAX_DOT_COUNT = 3

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = script.Parent:WaitForChild(LOADING_GUI_NAME) :: ScreenGui
gui.IgnoreGuiInset = true
gui.DisplayOrder = LOADING_DISPLAY_ORDER
gui.ResetOnSpawn = false
gui.Enabled = true
gui.Parent = playerGui
gui:SetAttribute(LOADING_SHOWN_AT, workspace:GetServerTimeNow())

ReplicatedFirst:RemoveDefaultLoadingScreen()

local statusLabel = gui:WaitForChild(MAIN_FRAME):WaitForChild(STATUS_LABEL) :: TextLabel

task.spawn(
	function()
		local dotCount = 0
		while gui:GetAttribute(LOADING_HANDOFF) == nil do
			statusLabel.Text = "LOADING" .. string.rep(".", dotCount)
			dotCount = (dotCount + 1) % (MAX_DOT_COUNT + 1)
			task.wait(DOT_INTERVAL_SEC)
		end
	end
)
