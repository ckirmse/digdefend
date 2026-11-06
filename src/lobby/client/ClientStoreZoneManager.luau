--!strict

-- The lobby's store stalls open their menus by walking in (designer,
-- 2026-11-03): each stall Folder in Workspace holds a MenuTouchPart, an
-- invisible non-colliding volume, and stepping into it opens that stall's
-- menu, the Supply Crate stall its choice screen (the crate or the Key
-- Store, designer 2026-11-05) and the Diamond stall the Diamond Store. The check is the local root's position against each
-- part's box every Heartbeat rather than Touched, which fires again on
-- every step and never says reliably when the player left; a menu opens
-- once per entry and not again until the player has walked out. Nothing
-- here talks to the server: the menus are already client overlays.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientClassMenuManager = require(script.Parent.ClientClassMenuManager)
local ClientDiamondStoreManager = require(script.Parent.ClientDiamondStoreManager)
local ClientGachaMenuManager = require(script.Parent.ClientGachaMenuManager)
local ClientGearMenuManager = require(script.Parent.ClientGearMenuManager)

local ClientStoreZoneManager = {}
ClientStoreZoneManager.__index = ClientStoreZoneManager

type Zone = {
	part: BasePart,
	openMenu: () -> (),
	isInside: boolean,
}

export type ClientStoreZoneManager = typeof(setmetatable(
	{} :: {
		zones: { Zone },
	},
	ClientStoreZoneManager
))

local function isPositionInPart(position: Vector3, part: BasePart): boolean
	local relative = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

function ClientStoreZoneManager:findZonePart(folderName: string): BasePart?
	-- waited for, not found: on a live server the client can start before
	-- the lobby has streamed in
	local folder = workspace:WaitForChild(folderName, Constants.GUI_WAIT_SEC)
	local part = folder and folder:WaitForChild(Constants.STORE_MENU_TOUCH_PART, Constants.GUI_WAIT_SEC)
	if not part or not part:IsA("BasePart") then
		warn(`ClientStoreZoneManager: no {folderName}.{Constants.STORE_MENU_TOUCH_PART} part in Workspace; that stall opens no menu`)
		return nil
	end
	return part
end

function ClientStoreZoneManager:addZone(folderName: string, openMenu: () -> ())
	local part = self:findZonePart(folderName)
	if not part then
		return
	end
	table.insert(self.zones, {
		part = part,
		openMenu = openMenu,
		isInside = false,
	})
end

function ClientStoreZoneManager:step()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local position = root.Position
	for _, zone in self.zones do
		local isInside = isPositionInPart(position, zone.part)
		if isInside == zone.isInside then
			continue
		end
		zone.isInside = isInside
		-- a zone entered while another menu is up (or while this one is
		-- still closing) is not re-armed until the player walks out again
		if isInside and not ClientOverlayManager:isOverlayActive() then
			zone.openMenu()
		end
	end
end

function ClientStoreZoneManager:init()
	self:addZone(
		Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER,
		function()
			ClientGachaMenuManager:openMenu()
		end
	)
	self:addZone(
		Constants.LOBBY_DIAMOND_STORE_FOLDER,
		function()
			ClientDiamondStoreManager:openMenu()
		end
	)
	-- the two selection stalls (designer, 2026-11-06)
	self:addZone(
		Constants.LOBBY_GEAR_SELECTION_FOLDER,
		function()
			ClientGearMenuManager:openMenu()
		end
	)
	self:addZone(
		Constants.LOBBY_CLASS_SELECTION_FOLDER,
		function()
			ClientClassMenuManager:openMenu()
		end
	)
	if #self.zones == 0 then
		return
	end
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function ClientStoreZoneManager.new(): ClientStoreZoneManager
	local self = setmetatable({}, ClientStoreZoneManager) :: ClientStoreZoneManager
	self.zones = {}
	return self
end

return ClientStoreZoneManager.new()
