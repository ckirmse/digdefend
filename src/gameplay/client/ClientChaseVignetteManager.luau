--!strict

-- The dread of the Chase (M68, designer 2026-10-26): black edges that close
-- in on this player's screen as the nearest Chase nears them. Every frame
-- the ChaseVignette ScreenGui (StarterGui, four gradient edges built by
-- scripts/studio/build_chase_vignette_gui.luau) is set from the distance
-- ClientMonsterManager reports to the nearest drawn floater: nothing past
-- FAR_STUDS, and at NEAR_STUDS the edges at their widest and their
-- authored solidity. Nothing travels for this; the monster snapshots the
-- client already draws from are the only input.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ClientMonsterManager = require(script.Parent.ClientMonsterManager)

local ClientChaseVignetteManager = {}
ClientChaseVignetteManager.__index = ClientChaseVignetteManager

type Edge = {
	frame: GuiObject,
	-- the authored transparency and size: the fully closed-in look
	transparency: number,
	size: UDim2,
	-- which axis the edge grows along (a top or bottom edge grows in Y)
	isVertical: boolean,
}

export type ClientChaseVignetteManager = typeof(setmetatable(
	{} :: {
		vignette: ScreenGui?,
		edges: { Edge },
	},
	ClientChaseVignetteManager
))

-- the distance the dread begins at, and the one it is complete at
local FAR_STUDS = 60
local NEAR_STUDS = 6
-- the edges' reach at the far end, as a share of their authored reach
local FAR_REACH_SHARE = 0.35
-- how the closeness curves: over 1 makes the last stretch the steepest
-- (designer, 2026-10-26: a stronger pass blinded and a halfway one was
-- still too much; the first values stand)
local CLOSENESS_POWER = 1.6

function ClientChaseVignetteManager:findVignette()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.CHASE_VIGNETTE_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientChaseVignetteManager: no ChaseVignette ScreenGui; run scripts/studio/build_chase_vignette_gui.luau")
		return
	end
	gui.Enabled = false
	self.vignette = gui
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(self.edges, {
				frame = child,
				transparency = child.BackgroundTransparency,
				size = child.Size,
				isVertical = child.Size.Y.Scale < 1,
			})
		end
	end
end

-- 0 past FAR_STUDS, 1 at NEAR_STUDS, curved so the last steps are the worst
function ClientChaseVignetteManager:closenessFor(distance: number): number
	if distance >= FAR_STUDS then
		return 0
	end
	local share = 1 - (math.max(distance, NEAR_STUDS) - NEAR_STUDS) / (FAR_STUDS - NEAR_STUDS)
	return share ^ CLOSENESS_POWER
end

function ClientChaseVignetteManager:apply(closeness: number)
	local vignette = self.vignette
	if not vignette then
		return
	end
	if closeness <= 0 then
		vignette.Enabled = false
		return
	end
	vignette.Enabled = true
	local reachShare = FAR_REACH_SHARE + (1 - FAR_REACH_SHARE) * closeness
	for _, edge in self.edges do
		edge.frame.BackgroundTransparency = 1 - (1 - edge.transparency) * closeness
		if edge.isVertical then
			edge.frame.Size = UDim2.fromScale(edge.size.X.Scale, edge.size.Y.Scale * reachShare)
		else
			edge.frame.Size = UDim2.fromScale(edge.size.X.Scale * reachShare, edge.size.Y.Scale)
		end
	end
end

function ClientChaseVignetteManager:step()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		self:apply(0)
		return
	end
	local distance = ClientMonsterManager:nearestFloaterDistance(root.Position)
	self:apply(if distance then self:closenessFor(distance) else 0)
end

function ClientChaseVignetteManager:init()
	self:findVignette()
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function ClientChaseVignetteManager.new(): ClientChaseVignetteManager
	local self = setmetatable({}, ClientChaseVignetteManager)
	self.vignette = nil
	self.edges = {}
	return self
end

return ClientChaseVignetteManager.new()
