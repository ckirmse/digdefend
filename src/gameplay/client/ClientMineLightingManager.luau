--!strict

-- Darkness inside the mine (decided 2026-09-15): Roblox's sky light reaches
-- into a one-block-thick shell of client blocks through its coarse lighting
-- voxels, so tunnels stay lit whatever Lighting.Ambient says. Lighting is
-- client-writable, so this client dims the sun and sky light itself while
-- the local character is inside the mine grid, blending from the place's
-- daytime look at the mouth to full dark by FULL_DARK_DEPTH_STUDS in, so
-- walking in or out never shows a step. PointLights (torches, blasts, the
-- jet pack flame) are unaffected, which is what makes torches matter.
local Lighting = game:GetService("Lighting")

local MineGridQuery = require("@game/ReplicatedStorage/Shared/MineGridQuery")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientMineLightingManager = {}
ClientMineLightingManager.__index = ClientMineLightingManager

export type ClientMineLightingManager = typeof(setmetatable(
	{} :: {
		darkness: number,
		outsideBrightness: number,
		outsideAmbient: Color3,
		outsideOutdoorAmbient: Color3,
		outsideEnvironmentDiffuse: number,
		outsideEnvironmentSpecular: number,
	},
	ClientMineLightingManager
))

local POLL_SEC = 0.1
-- darkness ramps from none at the mine mouth to full this far in along the
-- mine's forward axis (decided 2026-09-15 in play), so the first area is
-- workable without a torch and depth is what makes torches matter
local FULL_DARK_DEPTH_STUDS = 100
-- what full darkness looks like with no torch nearby; the environment scales
-- are the skybox's image-based light, which reaches everywhere the sky does not
local INSIDE_BRIGHTNESS = 0
local INSIDE_ENVIRONMENT_SCALE = 0
local INSIDE_AMBIENT = Color3.fromRGB(10, 10, 14)
local INSIDE_OUTDOOR_AMBIENT = Color3.fromRGB(10, 10, 14)

-- 0 outside the mine or at its mouth, 1 at full depth
function ClientMineLightingManager:measureDarkness(): number
	local position = ClientMineManager:getPlayerPosition()
	local grid = ClientMineManager:getGrid()
	local space = ClientMineManager:getSpace()
	if not position or not grid or not space then
		return 0
	end
	local depth, height, width = MineSpace.worldToCell(space, position)
	if not MineGridQuery.isInBounds(grid, depth, height, width) then
		return 0
	end
	local depthStuds = (position - space.origin):Dot(space.forward)
	return math.clamp(depthStuds / FULL_DARK_DEPTH_STUDS, 0, 1)
end

function ClientMineLightingManager:apply(darkness: number)
	if math.abs(darkness - self.darkness) < 0.001 then
		return
	end
	self.darkness = darkness
	Lighting.Brightness = self.outsideBrightness + (INSIDE_BRIGHTNESS - self.outsideBrightness) * darkness
	Lighting.Ambient = self.outsideAmbient:Lerp(INSIDE_AMBIENT, darkness)
	Lighting.OutdoorAmbient = self.outsideOutdoorAmbient:Lerp(INSIDE_OUTDOOR_AMBIENT, darkness)
	Lighting.EnvironmentDiffuseScale = self.outsideEnvironmentDiffuse + (INSIDE_ENVIRONMENT_SCALE - self.outsideEnvironmentDiffuse) * darkness
	Lighting.EnvironmentSpecularScale = self.outsideEnvironmentSpecular + (INSIDE_ENVIRONMENT_SCALE - self.outsideEnvironmentSpecular) * darkness
end

function ClientMineLightingManager:init()
	-- the place's daytime look is the outside baseline; M28 will move it
	self.outsideBrightness = Lighting.Brightness
	self.outsideAmbient = Lighting.Ambient
	self.outsideOutdoorAmbient = Lighting.OutdoorAmbient
	self.outsideEnvironmentDiffuse = Lighting.EnvironmentDiffuseScale
	self.outsideEnvironmentSpecular = Lighting.EnvironmentSpecularScale
	ClientTicker.every(
		POLL_SEC,
		function()
			self:apply(self:measureDarkness())
		end
	)
end

function ClientMineLightingManager.new(): ClientMineLightingManager
	local self = setmetatable({}, ClientMineLightingManager) :: ClientMineLightingManager
	self.darkness = 0
	self.outsideBrightness = 0
	self.outsideAmbient = Color3.new()
	self.outsideOutdoorAmbient = Color3.new()
	self.outsideEnvironmentDiffuse = 0
	self.outsideEnvironmentSpecular = 0
	return self
end

return ClientMineLightingManager.new()
