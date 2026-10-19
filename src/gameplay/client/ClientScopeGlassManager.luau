--!strict

-- The scope glass (2026-10-19): the ScopeHud ScreenGui, a reticle picture
-- with black all round it, shown over the screen while a scoped weapon is
-- in use. Two owners share it and never overlap: ClientWeaponManager while
-- the Sniper Rifle's scope is raised, and ClientPostManager while a scoped
-- post (the Railgun) is manned, since a manned post refuses the hand
-- weapon's scope. Each hands in the picture to show (Icons.WEAPON_SCOPE,
-- Icons.POST_WEAPON_SCOPE) and takes it down again.
local Players = game:GetService("Players")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ClientCursorManager = require(script.Parent.ClientCursorManager)

local ClientScopeGlassManager = {}
ClientScopeGlassManager.__index = ClientScopeGlassManager

export type ClientScopeGlassManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		reticle: ImageLabel?,
	},
	ClientScopeGlassManager
))

function ClientScopeGlassManager:show(imageId: string?)
	local gui = self.gui
	if not gui then
		return
	end
	local reticle = self.reticle
	if reticle then
		reticle.Image = imageId or ""
	end
	gui.Enabled = true
	-- the glass's reticle is the aim point; the cursor dot stands down
	ClientCursorManager:setDotHidden(true)
end

function ClientScopeGlassManager:hide()
	local gui = self.gui
	if gui then
		gui.Enabled = false
	end
	ClientCursorManager:setDotHidden(false)
end

function ClientScopeGlassManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.SCOPE_HUD_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientScopeGlassManager: no ScopeHud ScreenGui; run scripts/studio/build_scope_hud_gui.luau")
		return
	end
	gui.Enabled = false
	self.gui = gui
	local reticle = gui:FindFirstChild(Constants.SCOPE_HUD_RETICLE)
	self.reticle = if reticle and reticle:IsA("ImageLabel") then reticle else nil
end

function ClientScopeGlassManager.new(): ClientScopeGlassManager
	local self = setmetatable({}, ClientScopeGlassManager) :: ClientScopeGlassManager
	self.gui = nil
	self.reticle = nil
	return self
end

return ClientScopeGlassManager.new()
