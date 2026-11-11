--!strict

-- The dev panel's Performance section (2026-11-11, after a phone showed
-- CPU 28 ms and GPU 49 ms a frame): a small stats window that stays up with
-- the panel closed (frame times, draw calls, triangles, memory, read from
-- the Stats service a few times a second), and switches that turn one kind
-- of rendering work off on this client alone, so the cost of each can be
-- read off the window on the device itself. Every switch remembers what it
-- changed and puts exactly that back when unticked. Things made after a
-- switch was ticked (a pooled monster, a new particle) are not caught; tick
-- it again to sweep them up. Common to both places; admins only.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local ClientDevTools = require(script.Parent.ClientDevTools)
local Iris = require(script.Parent.Iris)

local ClientPerformanceDevTools = {}
ClientPerformanceDevTools.__index = ClientPerformanceDevTools

-- one switch: its label, what it turns off, and the undo for what it changed
type Switch = {
	label: string,
	state: any,
	apply: () -> { () -> () },
	undo: { () -> () },
}

export type ClientPerformanceDevTools = typeof(setmetatable(
	{} :: {
		showStats: any,
		statsSize: any,
		statsLines: { string },
		statsReadTime: number,
		frameCount: number,
		frameCountStartTime: number,
		framesPerSecond: number,
		switches: { Switch },
		hiddenContainerStates: { [Instance]: any },
		hiddenContainerUndo: { [Instance]: { () -> () } },
	},
	ClientPerformanceDevTools
))

local STATS_REFRESH_SEC = 0.25
local FPS_WINDOW_SEC = 1
local MS_PER_SEC = 1000
-- the dev panel's own gui must survive the "hide every ScreenGui" switch
local IRIS_GUI_NAME_PATTERN = "Iris"
-- top-level Workspace containers offered as "hide" switches
local MAX_CONTAINER_SWITCHES = 24

-- the Stats service's properties by name, so a property this engine
-- version lacks reads as "?" instead of stopping the panel
local function readStat(name: string): number?
	local isSuccess, value = pcall(
		function(): any
			return (Stats :: any)[name]
		end
	)
	return if isSuccess and typeof(value) == "number" then value else nil
end

local function formatCount(value: number?): string
	return if value then string.format("%d", value) else "?"
end

local function formatMs(seconds: number?): string
	return if seconds then string.format("%.1f ms", seconds * MS_PER_SEC) else "?"
end

-- a property set and kept: the gameplay sky (ClientRunCycleManager:stepSky)
-- rewrites Lighting and its effects from the presets every frame, so a
-- plain write there lasts one frame and the switch shows nothing; the hold
-- writes the value back whenever something else changes it
local function holdProperty(target: Instance, property: string, value: any): () -> ()
	local instance = target :: any
	local previous = instance[property]
	instance[property] = value
	local connection = target:GetPropertyChangedSignal(property):Connect(
		function()
			if instance[property] ~= value then
				instance[property] = value
			end
		end
	)
	return function()
		connection:Disconnect()
		if target.Parent then
			instance[property] = previous
		end
	end
end

-- sets a property on every matching descendant and returns the undo list;
-- isHeld keeps it against other writers (see holdProperty)
local function setOnDescendants(root: Instance, className: string, property: string, value: any, isHeld: boolean?): { () -> () }
	local undo: { () -> () } = {}
	for _, descendant in root:GetDescendants() do
		if not descendant:IsA(className) then
			continue
		end
		local instance = descendant :: any
		local previous = instance[property]
		if isHeld then
			table.insert(undo, holdProperty(descendant, property, value))
			continue
		end
		if previous == value then
			continue
		end
		instance[property] = value
		table.insert(
			undo,
			function()
				if descendant.Parent then
					instance[property] = previous
				end
			end
		)
	end
	return undo
end

local function appendAll(target: { () -> () }, source: { () -> () })
	for _, entry in source do
		table.insert(target, entry)
	end
end

function ClientPerformanceDevTools:readStatsLines(): { string }
	local memoryMb = Stats:GetTotalMemoryUsageMb()
	return {
		string.format("FPS %d   Memory %d MB", self.framesPerSecond, memoryMb),
		`Render CPU {formatMs(readStat("RenderCPUFrameTime"))}   GPU {formatMs(readStat("RenderGPUFrameTime"))}`,
		`Frame {formatMs(readStat("FrameTime"))}   Heartbeat {formatMs(readStat("HeartbeatTime"))}   Physics {formatMs(readStat("PhysicsStepTime"))}`,
		`Scene draw calls {formatCount(readStat("SceneDrawcallCount"))}   triangles {formatCount(readStat("SceneTriangleCount"))}`,
		`Shadow draw calls {formatCount(readStat("ShadowsDrawcallCount"))}   triangles {formatCount(readStat("ShadowsTriangleCount"))}`,
		`UI draw calls 2D {formatCount(readStat("UI2DDrawcallCount"))}   3D {formatCount(readStat("UI3DDrawcallCount"))}`,
		`Instances {formatCount(readStat("InstanceCount"))}   moving parts {formatCount(readStat("MovingPrimitivesCount"))}`,
		`Graphics quality {tostring(UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value)} (0 is Automatic)`,
	}
end

function ClientPerformanceDevTools:renderStatsWindow()
	if not self.showStats:get() then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now - self.statsReadTime >= STATS_REFRESH_SEC then
		self.statsReadTime = now
		self.statsLines = self:readStatsLines()
	end
	Iris.Window({ "Performance" }, { size = self.statsSize, isOpened = self.showStats })
	for _, line in self.statsLines do
		Iris.Text({ line })
	end
	Iris.End()
end

function ClientPerformanceDevTools:setSwitch(switch: Switch, isOn: boolean)
	for _, undo in switch.undo do
		undo()
	end
	switch.undo = if isOn then switch.apply() else {}
end

-- a whole Workspace container made invisible on this client: a part at
-- full transparency is not drawn, so the window shows what it was costing
function ClientPerformanceDevTools:hideContainer(container: Instance): { () -> () }
	local undo: { () -> () } = {}
	appendAll(undo, setOnDescendants(container, "BasePart", "LocalTransparencyModifier", 1))
	appendAll(undo, setOnDescendants(container, "Decal", "LocalTransparencyModifier", 1))
	return undo
end

function ClientPerformanceDevTools:renderContainerSwitches()
	Iris.Text({ "Hide a Workspace container (this client):" })
	local shown = 0
	for _, child in workspace:GetChildren() do
		if shown >= MAX_CONTAINER_SWITCHES then
			break
		end
		if not (child:IsA("Folder") or child:IsA("Model")) or Players:GetPlayerFromCharacter(child) then
			continue
		end
		shown += 1
		local state = self.hiddenContainerStates[child]
		if not state then
			state = Iris.State(false)
			self.hiddenContainerStates[child] = state
		end
		local checkbox = Iris.Checkbox({ `Hide {child.Name}` }, { isChecked = state })
		if checkbox.checked() or checkbox.unchecked() then
			for _, undo in self.hiddenContainerUndo[child] or {} do
				undo()
			end
			self.hiddenContainerUndo[child] = if state:get() then self:hideContainer(child) else {}
		end
	end
end

function ClientPerformanceDevTools:renderSection()
	Iris.Separator()
	Iris.Text({ "Performance (this client only)" })
	Iris.Checkbox({ "Stats window (stays up with this panel closed)" }, { isChecked = self.showStats })
	for _, switch in self.switches do
		local checkbox = Iris.Checkbox({ switch.label }, { isChecked = switch.state })
		if checkbox.checked() or checkbox.unchecked() then
			self:setSwitch(switch, switch.state:get())
		end
	end
	self:renderContainerSwitches()
end

function ClientPerformanceDevTools:addSwitch(label: string, apply: () -> { () -> () })
	table.insert(
		self.switches,
		{
			label = label,
			state = Iris.State(false),
			apply = apply,
			undo = {},
		}
	)
end

function ClientPerformanceDevTools:buildSwitches()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	self:addSwitch(
		"Shadows off (Lighting.GlobalShadows)",
		function(): { () -> () }
			return { holdProperty(Lighting, "GlobalShadows", false) }
		end
	)
	self:addSwitch(
		"Lights off (Point, Spot, Surface)",
		function(): { () -> () }
			return setOnDescendants(workspace, "Light", "Enabled", false)
		end
	)
	self:addSwitch(
		"Post effects off (Lighting and camera)",
		function(): { () -> () }
			local undo = setOnDescendants(Lighting, "PostEffect", "Enabled", false, true)
			local camera = workspace.CurrentCamera
			if camera then
				appendAll(undo, setOnDescendants(camera, "PostEffect", "Enabled", false))
			end
			return undo
		end
	)
	self:addSwitch(
		"Particles, beams, and trails off",
		function(): { () -> () }
			local undo = setOnDescendants(workspace, "ParticleEmitter", "Enabled", false)
			appendAll(undo, setOnDescendants(workspace, "Beam", "Enabled", false))
			appendAll(undo, setOnDescendants(workspace, "Trail", "Enabled", false))
			return undo
		end
	)
	self:addSwitch(
		"Highlights off",
		function(): { () -> () }
			local undo = setOnDescendants(workspace, "Highlight", "Enabled", false)
			appendAll(undo, setOnDescendants(playerGui, "Highlight", "Enabled", false))
			return undo
		end
	)
	self:addSwitch(
		"Billboards and surface guis off",
		function(): { () -> () }
			local undo: { () -> () } = {}
			for _, root in { workspace :: Instance, playerGui :: Instance } do
				appendAll(undo, setOnDescendants(root, "BillboardGui", "Enabled", false))
				appendAll(undo, setOnDescendants(root, "SurfaceGui", "Enabled", false))
			end
			return undo
		end
	)
	self:addSwitch(
		"Every ScreenGui off (HUD and menus; not this panel)",
		function(): { () -> () }
			local undo: { () -> () } = {}
			for _, gui in playerGui:GetChildren() do
				if not gui:IsA("ScreenGui") or not gui.Enabled or string.find(gui.Name, IRIS_GUI_NAME_PATTERN, 1, true) then
					continue
				end
				gui.Enabled = false
				table.insert(
					undo,
					function()
						gui.Enabled = true
					end
				)
			end
			return undo
		end
	)
end

function ClientPerformanceDevTools:countFrame()
	self.frameCount += 1
	local now = workspace:GetServerTimeNow()
	local elapsed = now - self.frameCountStartTime
	if elapsed >= FPS_WINDOW_SEC then
		self.framesPerSecond = math.floor(self.frameCount / elapsed + 0.5)
		self.frameCount = 0
		self.frameCountStartTime = now
	end
end

function ClientPerformanceDevTools:init()
	self.showStats = Iris.State(false)
	self.statsSize = Iris.State(Vector2.new(360, 230))
	self.frameCountStartTime = workspace:GetServerTimeNow()
	self:buildSwitches()
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
	-- its own render pass, so the window lives on with the panel closed;
	-- a closed window emits nothing (Iris walks every widget each cycle)
	Iris:Connect(
		function()
			self:renderStatsWindow()
		end
	)
	RunService.RenderStepped:Connect(
		function()
			self:countFrame()
		end
	)
end

function ClientPerformanceDevTools.new(): ClientPerformanceDevTools
	local self = setmetatable({}, ClientPerformanceDevTools) :: ClientPerformanceDevTools
	self.showStats = nil
	self.statsSize = nil
	self.statsLines = {}
	self.statsReadTime = 0
	self.frameCount = 0
	self.frameCountStartTime = 0
	self.framesPerSecond = 0
	self.switches = {}
	self.hiddenContainerStates = {}
	self.hiddenContainerUndo = {}
	return self
end

return ClientPerformanceDevTools.new()
