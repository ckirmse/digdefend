--!strict

-- Drives the Studio-authored "Loading" ScreenGui. It lives in ReplicatedFirst;
-- src/first/loading.client.luau parents it to PlayerGui at join time and runs
-- a minimal dot loop until this manager takes over (Attributes.LOADING_HANDOFF).
-- main.client reports progress stages here; the bar tweens to each one and the
-- screen tweens off once startup finishes.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

local ClientLoadingScreenManager = {}
ClientLoadingScreenManager.__index = ClientLoadingScreenManager

export type ClientLoadingScreenManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		mainFrame: Frame?,
		fill: Frame?,
		statusLabel: TextLabel?,
		isShowing: boolean,
		progress: number,
		caption: string,
		loadStatusConnection: RBXScriptConnection?,
		-- the same screen doubles as the departure screen (decided 2026-09-11,
		-- M13; may get its own art later)
		isDeparting: boolean,
	},
	ClientLoadingScreenManager
))

local FILL_TWEEN_SEC = 0.3
local HIDE_TWEEN_SEC = 0.6
-- the join-phase default screen can't be removed, only shortened; guarantee
-- the custom screen is actually seen instead of hiding while still covered
local MIN_VISIBLE_SEC = 2
-- past this the player deserves to know the wait is the connection, not a hang
local SLOW_LOAD_HINT_SEC = 10

local SLOW_LOAD_MESSAGE = "Slow connection, still loading your save..."
local RETRYING_MESSAGE = "Connection trouble, retrying..."

function ClientLoadingScreenManager:renderStatus()
	local statusLabel = self.statusLabel
	if not statusLabel or not self.isShowing then
		return
	end
	local player = Players.LocalPlayer
	local status = player:GetAttribute(Attributes.LOAD_STATUS)
	local gui = self.gui
	local shownAt = if gui then gui:GetAttribute(Attributes.LOADING_SHOWN_AT) else nil
	local elapsed = if typeof(shownAt) == "number" then workspace:GetServerTimeNow() - shownAt else 0
	if status == Enums.LoadStatus.RETRYING then
		statusLabel.Text = RETRYING_MESSAGE
	elseif status ~= Enums.LoadStatus.READY and elapsed >= SLOW_LOAD_HINT_SEC then
		statusLabel.Text = SLOW_LOAD_MESSAGE
	else
		statusLabel.Text = self.caption
	end
end

-- progress is a fraction 0..1; the caption names the stage in progress
function ClientLoadingScreenManager:setProgress(progress: number, caption: string)
	self.progress = math.clamp(progress, 0, 1)
	self.caption = caption
	local fill = self.fill
	if fill then
		TweenService:Create(
			fill,
			TweenInfo.new(FILL_TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(self.progress, 1) }
		):Play()
	end
	self:renderStatus()
end

function ClientLoadingScreenManager:show()
	if self.isShowing then
		return
	end
	self.isShowing = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.LOADING_GUI_NAME) :: ScreenGui
	self.gui = gui
	gui:SetAttribute(Attributes.LOADING_HANDOFF, true)

	local mainFrame = gui:WaitForChild(Constants.LOADING_MAIN_FRAME) :: Frame
	self.mainFrame = mainFrame
	local progressBar = mainFrame:WaitForChild(Constants.LOADING_PROGRESS_BAR) :: Frame
	self.fill = progressBar:WaitForChild(Constants.LOADING_PROGRESS_FILL) :: Frame
	self.statusLabel = mainFrame:WaitForChild(Constants.LOADING_STATUS_LABEL) :: TextLabel

	-- the title image is a slot for art that does not exist yet
	local titleImage = mainFrame:FindFirstChild(Constants.LOADING_TITLE_IMAGE)
	local titleText = mainFrame:FindFirstChild(Constants.LOADING_TITLE_TEXT)
	if titleImage and titleImage:IsA("ImageLabel") and titleText and titleText:IsA("TextLabel") then
		local hasImage = titleImage.Image ~= ""
		titleImage.Visible = hasImage
		titleText.Visible = not hasImage
	end

	gui.Enabled = true
	self:setProgress(self.progress, self.caption)

	local player = Players.LocalPlayer
	self.loadStatusConnection = player:GetAttributeChangedSignal(Attributes.LOAD_STATUS):Connect(
		function()
			self:renderStatus()
		end
	)
	task.delay(
		SLOW_LOAD_HINT_SEC,
		function()
			self:renderStatus()
		end
	)
end

function ClientLoadingScreenManager:hide()
	if not self.isShowing then
		return
	end
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local gui = self.gui
	if gui then
		local shownAt = gui:GetAttribute(Attributes.LOADING_SHOWN_AT)
		if typeof(shownAt) == "number" then
			local remaining = MIN_VISIBLE_SEC - (workspace:GetServerTimeNow() - shownAt)
			if remaining > 0 then
				task.wait(remaining)
			end
		end
	end
	self:setProgress(1, "Ready")
	self.isShowing = false
	local loadStatusConnection = self.loadStatusConnection
	if loadStatusConnection then
		loadStatusConnection:Disconnect()
		self.loadStatusConnection = nil
	end

	local mainFrame = self.mainFrame
	if mainFrame then
		local tween = TweenService:Create(
			mainFrame,
			TweenInfo.new(HIDE_TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(0, -1) }
		)
		tween:Play()
		tween.Completed:Wait()
	end
	if gui then
		gui.Enabled = false
	end
end

-- slides the loading screen in over the takeoff; the bar stays empty so the
-- arrival fill in the gameplay place reads as one continuous load
function ClientLoadingScreenManager:showDeparture(caption: string)
	if self.isShowing or self.isDeparting then
		return
	end
	self.isDeparting = true
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.LOADING_GUI_NAME) :: ScreenGui
	local mainFrame = gui:WaitForChild(Constants.LOADING_MAIN_FRAME) :: Frame
	local progressBar = mainFrame:WaitForChild(Constants.LOADING_PROGRESS_BAR) :: Frame
	local fill = progressBar:WaitForChild(Constants.LOADING_PROGRESS_FILL) :: Frame
	local statusLabel = mainFrame:WaitForChild(Constants.LOADING_STATUS_LABEL) :: TextLabel
	self.gui = gui
	self.mainFrame = mainFrame
	self.fill = fill
	self.statusLabel = statusLabel

	statusLabel.Text = caption
	fill.Size = UDim2.fromScale(0, 1)
	mainFrame.Position = UDim2.fromScale(0, -1)
	gui.Enabled = true
	-- Roblox shows this copy through the teleport instead of its own loading
	-- screen, and the gameplay place's ReplicatedFirst script picks it up on
	-- arrival, so the flight reads as one unbroken screen
	local teleportGui = gui:Clone()
	teleportGui.Enabled = true
	local teleportMain = teleportGui:FindFirstChild(Constants.LOADING_MAIN_FRAME)
	if teleportMain and teleportMain:IsA("Frame") then
		teleportMain.Position = UDim2.fromScale(0, 0)
	end
	TeleportService:SetTeleportGui(teleportGui)
	TweenService:Create(
		mainFrame,
		TweenInfo.new(HIDE_TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0, 0) }
	):Play()
end

-- the teleport failed; the screen leaves the same way the arrival screen does
function ClientLoadingScreenManager:hideDeparture()
	if not self.isDeparting then
		return
	end
	self.isDeparting = false
	local mainFrame = self.mainFrame
	local gui = self.gui
	if not mainFrame then
		return
	end
	local tween = TweenService:Create(
		mainFrame,
		TweenInfo.new(HIDE_TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.fromScale(0, -1) }
	)
	tween:Play()
	tween.Completed:Wait()
	if gui and not self.isShowing and not self.isDeparting then
		gui.Enabled = false
	end
end

function ClientLoadingScreenManager.new(): ClientLoadingScreenManager
	local self = setmetatable({}, ClientLoadingScreenManager) :: ClientLoadingScreenManager
	self.gui = nil
	self.mainFrame = nil
	self.fill = nil
	self.statusLabel = nil
	self.isShowing = false
	self.progress = 0
	self.caption = "Connecting..."
	self.loadStatusConnection = nil
	self.isDeparting = false
	return self
end

return ClientLoadingScreenManager.new()
