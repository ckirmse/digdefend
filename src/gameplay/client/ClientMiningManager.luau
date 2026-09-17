--!strict

-- Mining Mode (GDD "Mining Rock"), active while the local player holds the
-- pick axe: a centre reticle, the block under it highlighted with its name
-- and a health bar (no numbers, decided 2026-09-15) beside the reticle, and a swing per press or per interval while
-- held (mouse button, gamepad right trigger, the touch action button
-- through beginHold/endHold, or a touch hold). Touch follows Minecraft
-- Bedrock's split controls (researched 2026-09-16): a finger that rests
-- still in the free screen area for a short dwell starts a hold on whatever
-- the reticle points at, and dragging that finger afterwards turns the
-- camera while the hold keeps mining; a quick tap or swipe never swings.
-- After a break the hold waits until the reticle has rested on the next
-- block for one interval, so every first hit is intended. Swings are only
-- ever requests (TryHitRock); the crack state and the removal every client
-- shows come back from the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientHeldToolManager = require(script.Parent.ClientHeldToolManager)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientMiningManager = {}
ClientMiningManager.__index = ClientMiningManager

type Target = {
	part: BasePart,
	depth: number,
	height: number,
	width: number,
}

export type ClientMiningManager = typeof(setmetatable(
	{} :: {
		isActive: boolean,
		-- Build Mode (ClientStructureManager) borrows the reticle
		isReticleBorrowed: boolean,
		gui: ScreenGui?,
		reticle: GuiObject?,
		targetLabel: TextLabel?,
		targetBar: GuiObject?,
		targetFill: GuiObject?,
		highlight: Highlight?,
		target: Target?,
		isHolding: boolean,
		-- set when the held target breaks; cleared once a new target has
		-- rested under the reticle for a full interval
		isPausedAfterBreak: boolean,
		targetSinceTime: number,
		-- the touch that may become a hold, from TouchStarted until it lifts,
		-- moves too far too soon, or passes the dwell
		holdTouch: InputObject?,
		holdTouchStartTime: number,
		holdTouchStartPosition: Vector3,
		lastSwingTime: number,
		hitIntervalSec: number,
		reachStuds: number,
		-- remaining hp per cell index as the server last reported it
		remainingHpByCell: { [number]: number },
		aimConnection: RBXScriptConnection?,
		swingConnection: RBXScriptConnection?,
	},
	ClientMiningManager
))

local NOTIFY_ROCK_DAMAGED_SHAPE = {
	depth = "nonnegativeInteger",
	height = "nonnegativeInteger",
	width = "nonnegativeInteger",
	remainingHp = "nonnegativeNumber",
	maxHp = "positiveNumber",
}

local NOTIFY_ROCK_BROKEN_SHAPE = {
	depth = "nonnegativeInteger",
	height = "nonnegativeInteger",
	width = "nonnegativeInteger",
	rock = "positiveInteger",
	breakerUserId = "positiveInteger",
}

local DEFAULT_HIT_INTERVAL_SEC = 0.45
local DEFAULT_REACH_STUDS = 12
-- a touch must rest this long, moving less than this, before it is a hold
-- rather than a look or a tap (the feel constants, not gameplay tuning)
local TOUCH_HOLD_DWELL_SEC = 0.25
local TOUCH_HOLD_MAX_MOVE_PX = 12
-- placeholder hit burst until M46 art
local HIT_PARTICLE_COUNT = 8
local BREAK_PARTICLE_COUNT = 24
local PARTICLE_LIFETIME_SEC = 0.6
-- hits and breaks by other players are heard only nearby
local SOUND_RANGE_STUDS = 60

function ClientMiningManager:setTarget(target: Target?)
	local previous = self.target
	if previous and target and previous.part == target.part then
		return
	end
	self.target = target
	self.targetSinceTime = workspace:GetServerTimeNow()
	local highlight = self.highlight
	if highlight then
		highlight.Adornee = if target then target.part else nil
		highlight.Enabled = target ~= nil
	end
	self:renderTargetLabel()
end

function ClientMiningManager:renderTargetLabel()
	local label = self.targetLabel
	local bar = self.targetBar
	local fill = self.targetFill
	if not label then
		return
	end
	local target = self.target
	local grid = ClientMineManager:getGrid()
	if not target or not grid then
		label.Visible = false
		if bar then
			bar.Visible = false
		end
		return
	end
	local cellIndex = (target.depth * grid.height + target.height) * grid.width + target.width + 1
	local rock = grid.cells[cellIndex]
	label.Text = Enums.getPublicName(Enums.RockName, rock) or "Rock"
	label.Visible = true
	-- bedrock has no hp and so no bar; the fill turns red once the block is crumbling
	local maxHp = ClientMineManager:getRockMaxHp(rock)
	if bar and fill then
		if maxHp then
			local remaining = self.remainingHpByCell[cellIndex] or maxHp
			local fraction = math.clamp(remaining / maxHp, 0, 1)
			fill.Size = UDim2.fromScale(fraction, 1)
			fill.BackgroundColor3 = if MiningRules.crackStage(remaining, maxHp) >= 2 then UiStyle.NEGATIVE_COLOR else UiStyle.POSITIVE_COLOR
			bar.Visible = true
		else
			bar.Visible = false
		end
	end
end

-- what the camera centre is looking at, within reach, among rendered blocks
function ClientMiningManager:aim()
	local camera = workspace.CurrentCamera
	local blocksFolder = workspace:FindFirstChild(Constants.MINE_BLOCKS_FOLDER)
	if not camera or not blocksFolder then
		self:setTarget(nil)
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { blocksFolder }
	local origin = camera.CFrame.Position
	local result = workspace:Raycast(origin, camera.CFrame.LookVector * self.reachStuds, params)
	local part = if result then result.Instance else nil
	if not part or not part:IsA("BasePart") then
		self:setTarget(nil)
		return
	end
	local depth, height, width = ClientMineManager:getCellFromPart(part)
	if not depth then
		self:setTarget(nil)
		return
	end
	self:setTarget({ part = part, depth = depth, height = height :: number, width = width :: number })
end

function ClientMiningManager:swing()
	local target = self.target
	if not target then
		return
	end
	self.lastSwingTime = workspace:GetServerTimeNow()
	ClientHeldToolManager:playSwing()
	ClientNetManager:fireServer(
		NetEventNames.TRY_HIT_ROCK,
		{
			depth = target.depth,
			height = target.height,
			width = target.width,
		}
	)
end

function ClientMiningManager:onSwingStep()
	local now = workspace:GetServerTimeNow()
	self:promoteHoldTouchIfNeeded(now)
	if not self.isHolding or ClientOverlayManager:isOverlayActive() then
		return
	end
	if self.isPausedAfterBreak then
		if not self.target or now - self.targetSinceTime < self.hitIntervalSec then
			return
		end
		self.isPausedAfterBreak = false
	end
	if now - self.lastSwingTime >= self.hitIntervalSec then
		self:swing()
	end
end

local function isSwingInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

-- a fresh press swings at once; holding repeats on the interval
function ClientMiningManager:beginHold()
	if not self.isActive or ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isHolding = true
	-- a deliberate press means the player wants this block
	self.isPausedAfterBreak = false
	if workspace:GetServerTimeNow() - self.lastSwingTime >= self.hitIntervalSec then
		self:swing()
	end
end

function ClientMiningManager:endHold()
	self.isHolding = false
	self.isPausedAfterBreak = false
end

-- a touch in the free screen area (not a gui, not the thumbstick) is a
-- hold candidate; it becomes a hold only after resting for the dwell
function ClientMiningManager:onTouchStarted(touch: InputObject, isGameProcessed: boolean)
	if not self.isActive or isGameProcessed or self.holdTouch ~= nil or self.isHolding then
		return
	end
	self.holdTouch = touch
	self.holdTouchStartTime = workspace:GetServerTimeNow()
	self.holdTouchStartPosition = touch.Position
end

-- moving before the dwell is a look, and the touch stops being a candidate;
-- moving after the hold began is a look that keeps mining
function ClientMiningManager:onTouchMoved(touch: InputObject)
	if touch ~= self.holdTouch or self.isHolding then
		return
	end
	if (touch.Position - self.holdTouchStartPosition).Magnitude > TOUCH_HOLD_MAX_MOVE_PX then
		self.holdTouch = nil
	end
end

function ClientMiningManager:onTouchEnded(touch: InputObject)
	if touch ~= self.holdTouch then
		return
	end
	self.holdTouch = nil
	self:endHold()
end

function ClientMiningManager:promoteHoldTouchIfNeeded(now: number)
	local touch = self.holdTouch
	if not touch or self.isHolding then
		return
	end
	if now - self.holdTouchStartTime >= TOUCH_HOLD_DWELL_SEC then
		self:beginHold()
	end
end

function ClientMiningManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or not isSwingInput(input) then
		return
	end
	self:beginHold()
end

function ClientMiningManager:onInputEnded(input: InputObject)
	if isSwingInput(input) then
		self:endHold()
	end
end

function ClientMiningManager:emitBurst(part: BasePart, count: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(part.Color)
	emitter.Size = NumberSequence.new(0.4, 0.1)
	emitter.Lifetime = NumberRange.new(0.3, PARTICLE_LIFETIME_SEC)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(count)
	task.delay(
		PARTICLE_LIFETIME_SEC,
		function()
			emitter:Destroy()
		end
	)
end

function ClientMiningManager:isNear(part: BasePart): boolean
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude <= SOUND_RANGE_STUDS
end

function ClientMiningManager:onRockDamaged(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_ROCK_DAMAGED_SHAPE)
	if not isValid then
		warn("ClientMiningManager: malformed NotifyRockDamaged")
		return
	end
	local grid = ClientMineManager:getGrid()
	if not grid then
		return
	end
	local cellIndex = (payload.depth * grid.height + payload.height) * grid.width + payload.width + 1
	self.remainingHpByCell[cellIndex] = payload.remainingHp
	ClientMineManager:setCrackStage(payload.depth, payload.height, payload.width, MiningRules.crackStage(payload.remainingHp, payload.maxHp))
	local part = ClientMineManager:getRenderedPart(payload.depth, payload.height, payload.width)
	if part and self:isNear(part) then
		self:emitBurst(part, HIT_PARTICLE_COUNT)
		-- ore rings like metal, filler thuds like rock (decided 2026-09-14)
		local kind = ClientMineManager:getCellRockKind(payload.depth, payload.height, payload.width)
		local soundName = if kind == Enums.RockKind.RESOURCE then SoundNames.Sfx.RESOURCE_HIT else SoundNames.Sfx.ROCK_HIT
		ClientSoundManager:playSfx(soundName)
	end
	local target = self.target
	if target and target.depth == payload.depth and target.height == payload.height and target.width == payload.width then
		self:renderTargetLabel()
	end
end

function ClientMiningManager:onRockBroken(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_ROCK_BROKEN_SHAPE)
	if not isValid then
		warn("ClientMiningManager: malformed NotifyRockBroken")
		return
	end
	local grid = ClientMineManager:getGrid()
	if not grid then
		return
	end
	local cellIndex = (payload.depth * grid.height + payload.height) * grid.width + payload.width + 1
	self.remainingHpByCell[cellIndex] = nil
	local part = ClientMineManager:getRenderedPart(payload.depth, payload.height, payload.width)
	if part and self:isNear(part) then
		-- burst from a throwaway anchor, since the block's part goes back to the pool
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one
		anchor.Color = part.Color
		anchor.CFrame = part.CFrame
		anchor.Parent = workspace
		self:emitBurst(anchor, BREAK_PARTICLE_COUNT)
		task.delay(
			PARTICLE_LIFETIME_SEC + 0.1,
			function()
				anchor:Destroy()
			end
		)
		ClientSoundManager:playSfx(SoundNames.Sfx.ROCK_BREAK)
	end
	ClientMineManager:clearCell(payload.depth, payload.height, payload.width)
	local target = self.target
	if target and target.depth == payload.depth and target.height == payload.height and target.width == payload.width then
		self:setTarget(nil)
		if self.isHolding then
			self.isPausedAfterBreak = true
		end
	end
end

-- the HUD is the reticle plus the target label and bar, which only show
-- with a mining target, so another aiming mode can show the reticle alone
function ClientMiningManager:setReticleBorrowed(isBorrowed: boolean)
	self.isReticleBorrowed = isBorrowed
	local gui = self.gui
	if gui then
		gui.Enabled = self.isActive or isBorrowed
	end
end

function ClientMiningManager:setActive(isActive: boolean)
	if isActive == self.isActive then
		return
	end
	self.isActive = isActive
	local gui = self.gui
	if gui then
		gui.Enabled = isActive or self.isReticleBorrowed
	end
	if isActive then
		self.aimConnection = RunService.RenderStepped:Connect(
			function()
				self:aim()
			end
		)
		self.swingConnection = RunService.Heartbeat:Connect(
			function()
				self:onSwingStep()
			end
		)
	else
		self.isHolding = false
		self.isPausedAfterBreak = false
		self.holdTouch = nil
		self:setTarget(nil)
		if self.aimConnection then
			self.aimConnection:Disconnect()
			self.aimConnection = nil
		end
		if self.swingConnection then
			self.swingConnection:Disconnect()
			self.swingConnection = nil
		end
	end
end

function ClientMiningManager:readTuning()
	local interval = ClientDataManager:getGameMetadata(Attributes.PICK_AXE_HIT_INTERVAL_SEC)
	local reach = ClientDataManager:getGameMetadata(Attributes.PICK_AXE_REACH_STUDS)
	self.hitIntervalSec = if typeof(interval) == "number" then interval else DEFAULT_HIT_INTERVAL_SEC
	self.reachStuds = if typeof(reach) == "number" then reach else DEFAULT_REACH_STUDS
end

function ClientMiningManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.MINING_HUD_GUI_NAME, 10)
	if gui and gui:IsA("ScreenGui") then
		self.gui = gui
		gui.Enabled = false
		local reticle = gui:FindFirstChild(Constants.MINING_RETICLE)
		self.reticle = if reticle and reticle:IsA("GuiObject") then reticle else nil
		local label = gui:FindFirstChild(Constants.MINING_TARGET_LABEL)
		self.targetLabel = if label and label:IsA("TextLabel") then label else nil
		local bar = gui:FindFirstChild(Constants.MINING_TARGET_BAR)
		self.targetBar = if bar and bar:IsA("GuiObject") then bar else nil
		local fill = if bar then bar:FindFirstChild(Constants.MINING_TARGET_FILL) else nil
		self.targetFill = if fill and fill:IsA("GuiObject") then fill else nil
	else
		warn("ClientMiningManager: no MiningHud ScreenGui; run scripts/studio/build_mining_hud_gui.luau")
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "MiningTarget"
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.85
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = workspace
	self.highlight = highlight

	self:readTuning()
	for _, key in { Attributes.PICK_AXE_HIT_INTERVAL_SEC, Attributes.PICK_AXE_REACH_STUDS } do
		ClientDataManager:subscribeGameMetadataAttribute(
			key,
			function()
				self:readTuning()
			end
		)
	end

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_ROCK_DAMAGED,
		function(payload: any)
			self:onRockDamaged(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_ROCK_BROKEN,
		function(payload: any)
			self:onRockBroken(payload)
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	UserInputService.InputEnded:Connect(
		function(input: InputObject)
			self:onInputEnded(input)
		end
	)
	UserInputService.TouchStarted:Connect(
		function(touch: InputObject, isGameProcessed: boolean)
			self:onTouchStarted(touch, isGameProcessed)
		end
	)
	UserInputService.TouchMoved:Connect(
		function(touch: InputObject)
			self:onTouchMoved(touch)
		end
	)
	UserInputService.TouchEnded:Connect(
		function(touch: InputObject)
			self:onTouchEnded(touch)
		end
	)

	local function applyEquipped(value: any)
		self:setActive(value == Enums.ToolKind.PICK_AXE)
	end
	applyEquipped(ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL, applyEquipped)
end

function ClientMiningManager.new(): ClientMiningManager
	local self = setmetatable({}, ClientMiningManager) :: ClientMiningManager
	self.isActive = false
	self.isReticleBorrowed = false
	self.gui = nil
	self.reticle = nil
	self.targetLabel = nil
	self.targetBar = nil
	self.targetFill = nil
	self.highlight = nil
	self.target = nil
	self.isHolding = false
	self.isPausedAfterBreak = false
	self.targetSinceTime = 0
	self.holdTouch = nil
	self.holdTouchStartTime = 0
	self.holdTouchStartPosition = Vector3.zero
	self.lastSwingTime = 0
	self.hitIntervalSec = DEFAULT_HIT_INTERVAL_SEC
	self.reachStuds = DEFAULT_REACH_STUDS
	self.remainingHpByCell = {}
	self.aimConnection = nil
	self.swingConnection = nil
	return self
end

return ClientMiningManager.new()
