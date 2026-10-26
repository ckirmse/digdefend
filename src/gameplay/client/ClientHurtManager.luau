--!strict

-- The player's own hit feedback (2026-10-26, designer): every drop in the
-- local character's health plays the PlayerHurt sound, theirs alone, and
-- fades the HurtVignette ScreenGui (StarterGui, red edges built by
-- scripts/studio/build_hurt_vignette_gui.luau) in over FADE_IN_SEC and out
-- over FADE_OUT_SEC. Health is read from the Humanoid the server lowers
-- (ReviveManager is the one thing that changes it), so every source of
-- damage, a monster's bite or a Seam's burst, shows the same way with no
-- message of its own; a rise in health (a revive, the Stim Shot) shows
-- nothing. A second hit inside the fade starts it over.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientHurtManager = {}
ClientHurtManager.__index = ClientHurtManager

export type ClientHurtManager = typeof(setmetatable(
	{} :: {
		vignette: ScreenGui?,
		edges: { GuiObject },
		-- each edge's authored transparency, the fade-in's end
		edgeTransparencies: { [GuiObject]: number },
		lastHealth: number?,
		flashToken: number,
		healthConnection: RBXScriptConnection?,
	},
	ClientHurtManager
))

local FADE_IN_SEC = 0.5
local FADE_OUT_SEC = 0.5

function ClientHurtManager:fadeEdges(toAuthored: boolean, seconds: number)
	for _, edge in self.edges do
		local target = if toAuthored then self.edgeTransparencies[edge] or 0 else 1
		TweenService:Create(edge, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = target }):Play()
	end
end

function ClientHurtManager:flash()
	local vignette = self.vignette
	if not vignette then
		return
	end
	self.flashToken += 1
	local token = self.flashToken
	vignette.Enabled = true
	task.spawn(
		function()
			self:fadeEdges(true, FADE_IN_SEC)
			task.wait(FADE_IN_SEC)
			if self.flashToken ~= token then
				return
			end
			self:fadeEdges(false, FADE_OUT_SEC)
			task.wait(FADE_OUT_SEC)
			if self.flashToken == token then
				vignette.Enabled = false
			end
		end
	)
end

function ClientHurtManager:onHealthChanged(health: number)
	local last = self.lastHealth
	self.lastHealth = health
	if last == nil or health >= last then
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.PLAYER_HURT)
	self:flash()
end

function ClientHurtManager:watchCharacter(character: Model)
	local connection = self.healthConnection
	if connection then
		connection:Disconnect()
		self.healthConnection = nil
	end
	local humanoid = character:WaitForChild("Humanoid", Constants.GUI_WAIT_SEC)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	self.lastHealth = humanoid.Health
	self.healthConnection = humanoid.HealthChanged:Connect(
		function(health: number)
			self:onHealthChanged(health)
		end
	)
end

function ClientHurtManager:findVignette()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.HURT_VIGNETTE_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientHurtManager: no HurtVignette ScreenGui; run scripts/studio/build_hurt_vignette_gui.luau")
		return
	end
	gui.Enabled = false
	self.vignette = gui
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(self.edges, child)
			self.edgeTransparencies[child] = child.BackgroundTransparency
			child.BackgroundTransparency = 1
		end
	end
end

function ClientHurtManager:init()
	self:findVignette()
	local player = Players.LocalPlayer
	local character = player.Character
	if character then
		self:watchCharacter(character)
	end
	player.CharacterAdded:Connect(
		function(newCharacter: Model)
			self:watchCharacter(newCharacter)
		end
	)
end

function ClientHurtManager.new(): ClientHurtManager
	local self = setmetatable({}, ClientHurtManager)
	self.vignette = nil
	self.edges = {}
	self.edgeTransparencies = {}
	self.lastHealth = nil
	self.flashToken = 0
	self.healthConnection = nil
	return self
end

return ClientHurtManager.new()
