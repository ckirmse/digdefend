--!strict

-- Every button clicks (designer, 2026-10-13; menus only at first, the HUD
-- too the same day): every GuiButton under any ScreenGui, present now or
-- cloned in later (cards, rows, items), plays SoundNames.Sfx.BUTTON_CLICK
-- when activated. A button that should sound different carries the
-- Attributes.BUTTON_SOUND attribute naming its Sfx player instead (the
-- reroll buttons), and one that should stay silent carries it empty; both
-- set by the GUI's build script, so no manager wires its own click sounds.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientSoundManager = require(script.Parent.ClientSoundManager)

local ClientButtonSoundManager = {}
ClientButtonSoundManager.__index = ClientButtonSoundManager

export type ClientButtonSoundManager = typeof(setmetatable(
	{} :: {
		-- the buttons already wired, so a button seen twice clicks once
		wired: { [GuiButton]: boolean },
	},
	ClientButtonSoundManager
))

function ClientButtonSoundManager:wireIfNeeded(instance: Instance)
	if not instance:IsA("GuiButton") or self.wired[instance] or not instance:FindFirstAncestorWhichIsA("ScreenGui") then
		return
	end
	self.wired[instance] = true
	instance.Activated:Connect(
		function()
			local override = instance:GetAttribute(Attributes.BUTTON_SOUND)
			if override == "" then
				return
			end
			ClientSoundManager:playSfx(if typeof(override) == "string" then override else SoundNames.Sfx.BUTTON_CLICK)
		end
	)
	instance.Destroying:Connect(
		function()
			self.wired[instance] = nil
		end
	)
end

function ClientButtonSoundManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	for _, descendant in playerGui:GetDescendants() do
		self:wireIfNeeded(descendant)
	end
	playerGui.DescendantAdded:Connect(
		function(descendant: Instance)
			self:wireIfNeeded(descendant)
		end
	)
end

function ClientButtonSoundManager.new(): ClientButtonSoundManager
	local self = setmetatable({}, ClientButtonSoundManager) :: ClientButtonSoundManager
	self.wired = {}
	return self
end

return ClientButtonSoundManager.new()
