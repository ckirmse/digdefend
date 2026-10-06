--!strict

-- A HUD element that slides on and off stage (M33): the frame's authored
-- position is where it rests on screen, and a hidden position, off one
-- edge, is where it waits. Showing can be delayed so one element follows
-- another (the Refinery HP bar comes down after the day clock has gone
-- up); a change of mind during the delay or the tween wins, so the two
-- can never both be mid-flight toward the same spot. Used by the day
-- clock, the Refinery HP bar, and the Camp Map.
local TweenService = game:GetService("TweenService")

local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")

local ClientHudSlide = {}
ClientHudSlide.__index = ClientHudSlide

export type ClientHudSlide = typeof(setmetatable(
	{} :: {
		frame: GuiObject,
		shownPosition: UDim2,
		hiddenPosition: UDim2,
		isShown: boolean,
		-- bumped by every request, so a delayed or running slide that has
		-- been overtaken does nothing when it fires
		generation: number,
		tween: Tween?,
	},
	ClientHudSlide
))

function ClientHudSlide:getIsShown(): boolean
	return self.isShown
end

-- puts the frame where it belongs at once, for the first draw
function ClientHudSlide:snap(isShown: boolean)
	self.isShown = isShown
	self.generation += 1
	if self.tween then
		self.tween:Cancel()
		self.tween = nil
	end
	self.frame.Position = if isShown then self.shownPosition else self.hiddenPosition
	self.frame.Visible = isShown
end

function ClientHudSlide:setShown(isShown: boolean, delaySec: number)
	if self.isShown == isShown then
		return
	end
	self.isShown = isShown
	self.generation += 1
	local generation = self.generation
	if self.tween then
		self.tween:Cancel()
		self.tween = nil
	end
	local function start()
		if self.generation ~= generation then
			return
		end
		if isShown then
			self.frame.Visible = true
		end
		local tween = TweenService:Create(
			self.frame,
			TweenInfo.new(UiStyle.HUD_SLIDE_SEC, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Position = if isShown then self.shownPosition else self.hiddenPosition }
		)
		self.tween = tween
		tween.Completed:Connect(
			function(state: Enum.PlaybackState)
				if self.generation == generation and not isShown and state == Enum.PlaybackState.Completed then
					self.frame.Visible = false
				end
			end
		)
		tween:Play()
	end
	if delaySec > 0 then
		task.delay(delaySec, start)
	else
		start()
	end
end

-- the frame's current position is its place on screen
function ClientHudSlide.new(frame: GuiObject, hiddenPosition: UDim2): ClientHudSlide
	local self = setmetatable({}, ClientHudSlide) :: ClientHudSlide
	self.frame = frame
	self.shownPosition = frame.Position
	self.hiddenPosition = hiddenPosition
	self.isShown = frame.Visible
	self.generation = 0
	self.tween = nil
	return self
end

return ClientHudSlide
