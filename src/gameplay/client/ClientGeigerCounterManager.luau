--!strict

-- The Geiger Counter on this client (GDD "Geiger Counter"): the dial beside
-- the day clock, shown only in mining mode (the pick axe equipped) once
-- the counter is owned. A few times a second it asks ClientMineManager how
-- far the nearest uranium rock is, buried or not, and lights as many rings
-- as GeigerRules says for the range the player's level detects at; with
-- nothing in range no ring shows. The server publishes the level and its
-- range and the ring distances privately. Nothing here
-- decides anything: the dial is a hint drawn from the grid this client
-- already holds.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GeigerRules = require("@game/ReplicatedStorage/Shared/GeigerRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientGeigerCounterManager = {}
ClientGeigerCounterManager.__index = ClientGeigerCounterManager

export type ClientGeigerCounterManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		-- inner ring first
		rings: { GuiObject },
		litRingCount: number,
		stopScanning: (() -> ())?,
	},
	ClientGeigerCounterManager
))

-- GeigerCounterLevel at or above this is owning the counter
local OWNED_LEVEL = 2
-- the server publishes the real numbers (GameData/Mining/GeigerCounter)
local DEFAULT_RING_STUDS = { 20, 13, 8 }
local DEFAULT_SCAN_INTERVAL_SEC = 0.2
-- the 2D loop for each count of lit rings; none for zero. Played on this
-- client only, so nobody else hears a crewmate's counter
local RING_SOUND_BY_COUNT: { [number]: string } = {
	[1] = SoundNames.Sfx.GEIGER_1,
	[2] = SoundNames.Sfx.GEIGER_2,
	[3] = SoundNames.Sfx.GEIGER_3,
}

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientGeigerCounterManager:isShown(): boolean
	local isOwned = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.GEIGER_COUNTER_LEVEL), 1) >= OWNED_LEVEL
	return isOwned and ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL) == Enums.ToolKind.PICK_AXE
end

function ClientGeigerCounterManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.GEIGER_COUNTER_GUI_NAME, 10)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientGeigerCounterManager: no GeigerCounter ScreenGui; run scripts/studio/build_geiger_counter_gui.luau")
		return
	end
	local root = gui:FindFirstChild(Constants.GEIGER_COUNTER_ROOT_FRAME)
	local dial = if root then root:FindFirstChild(Constants.GEIGER_COUNTER_DIAL) else nil
	if not dial then
		warn("ClientGeigerCounterManager: the GeigerCounter ScreenGui has no Dial; rebuild it with scripts/studio/build_geiger_counter_gui.luau")
		return
	end
	-- Ring1, Ring2, ... for as many as the designer authored
	local rings: { GuiObject } = {}
	while true do
		local ring = dial:FindFirstChild(Constants.GEIGER_COUNTER_RING_PREFIX .. (#rings + 1))
		if not ring or not ring:IsA("GuiObject") then
			break
		end
		ring.Visible = false
		table.insert(rings, ring)
	end
	gui.Enabled = false
	self.gui = gui
	self.rings = rings
end

function ClientGeigerCounterManager:setLitRingCount(count: number)
	if self.litRingCount == count then
		return
	end
	local previousSound = RING_SOUND_BY_COUNT[self.litRingCount]
	local sound = RING_SOUND_BY_COUNT[count]
	self.litRingCount = count
	for index, ring in self.rings do
		ring.Visible = index <= count
	end
	-- one loop at a time: the old count's stops before the new one starts
	if previousSound and previousSound ~= sound then
		ClientSoundManager:stopSfxLoop(previousSound)
	end
	if sound then
		ClientSoundManager:setSfxLoopLevel(sound, 1)
	end
end

function ClientGeigerCounterManager:scan()
	local rangeStuds = readNumber(ClientDataManager:getCurrentPlayerAttribute(Attributes.GEIGER_COUNTER_RANGE_STUDS), 0)
	local position = ClientMineManager:getPlayerPosition()
	if not position or rangeStuds <= 0 then
		self:setLitRingCount(0)
		return
	end
	local ringStuds = GeigerRules.decodeRingStuds(ClientDataManager:getCurrentPlayerAttribute(Attributes.GEIGER_COUNTER_RING_STUDS)) or DEFAULT_RING_STUDS
	local distance = ClientMineManager:getNearestUraniumDistance(position, rangeStuds)
	self:setLitRingCount(GeigerRules.litRingCount(distance, ringStuds))
end

-- the dial is drawn, and the mine scanned, only while it is shown
function ClientGeigerCounterManager:refreshShown()
	local gui = self.gui
	if not gui then
		return
	end
	local isShown = self:isShown()
	gui.Enabled = isShown
	if isShown and not self.stopScanning then
		local intervalSec = readNumber(ClientDataManager:getGameMetadata(Attributes.GEIGER_COUNTER_SCAN_INTERVAL_SEC), DEFAULT_SCAN_INTERVAL_SEC)
		self.stopScanning = ClientTicker.every(
			intervalSec,
			function()
				self:scan()
			end
		)
		self:scan()
	elseif not isShown and self.stopScanning then
		self.stopScanning()
		self.stopScanning = nil
		self:setLitRingCount(0)
	end
end

function ClientGeigerCounterManager:init()
	self:findGui()
	if not self.gui then
		return
	end
	for _, key in { Attributes.GEIGER_COUNTER_LEVEL, Attributes.EQUIPPED_TOOL } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			key,
			function()
				self:refreshShown()
			end
		)
	end
	self:refreshShown()
end

function ClientGeigerCounterManager.new(): ClientGeigerCounterManager
	local self = setmetatable({}, ClientGeigerCounterManager) :: ClientGeigerCounterManager
	self.gui = nil
	self.rings = {}
	self.litRingCount = 0
	self.stopScanning = nil
	return self
end

return ClientGeigerCounterManager.new()
