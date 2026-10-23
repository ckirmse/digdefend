--!strict

-- The Ore Scanner as the client sees it (2026-10-22). While the GADGET
-- tool is equipped and the class's gadget is the scanner, the use input
-- (click, tap, or the right trigger) asks the server to sweep
-- (TryUseOreScanner). Every client draws a sweep from NotifyOreScan: a
-- red ForceField sphere grows from nothing to the radius over the sweep
-- time at the origin and fades, then every ore block within the radius
-- (that is one pulse; a use runs pulseCount of them, the next starting
-- as the last highlight fades out),
-- buried or exposed, is found in this client's own copy of the grid
-- (ClientMineManager's, the same cells the mine is drawn from) and
-- highlighted through the rock by its kind: one solid box per block
-- in a Model per resource, each Model under one Highlight in the
-- resource's colour (a Highlight shows through walls, and the engine
-- allows only a few dozen at once, so one per kind, never one per
-- block), faded in, held, and faded out. Nothing here decides anything.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local RockRules = require("@game/ReplicatedStorage/Shared/RockRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientOreScannerManager = {}
ClientOreScannerManager.__index = ClientOreScannerManager

export type ClientOreScannerManager = typeof(setmetatable(
	{} :: {
		scansFolder: Folder?,
		-- every live scan's box for a cell, so a block mined while lit
		-- loses its highlight at once (2026-10-22)
		boxesByCellIndex: { [number]: { BasePart } },
	},
	ClientOreScannerManager
))

local NOTIFY_ORE_SCAN_SHAPE = {
	userId = "integer",
	origin = "vector3",
	radiusStuds = "positiveNumber",
	sweepSec = "positiveNumber",
	revealDelaySec = "nonnegativeNumber",
	holdSec = "nonnegativeNumber",
	fadeSec = "positiveNumber",
	pulseCount = "positiveInteger",
}
local SCANS_FOLDER = "OreScans"
-- the sphere's look: see-through from the start, gone as it reaches full size
local SPHERE_TRANSPARENCY = 0.4
-- the highlight's fill and outline while held (designer, 2026-10-22)
local HIGHLIGHT_FILL_TRANSPARENCY = 0.5
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 0
-- a box a little smaller than the block, so neighbours read apart, and
-- solid: a Highlight draws nothing for a part at transparency 1 and only
-- faintly for a see-through one, and the rock around the box hides the
-- box itself (an exposed ore block has its own part over it)
local BOX_SHARE = 0.9
local BOX_TRANSPARENCY = 0
-- the scan's sound, 3D from the scanner's spot for everyone in range
local SCAN_SOUND_FULL_VOLUME_STUDS = 40
local SCAN_SOUND_RANGE_STUDS = 200
local FEEDBACK_COOLING = "Scanner ready in %d s"
local FEEDBACK_DISPLAY_SEC = 2

local function isUseInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ClientOreScannerManager:getScansFolder(): Folder
	local folder = self.scansFolder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = SCANS_FOLDER
	folder.Parent = workspace
	self.scansFolder = folder
	return folder
end

function ClientOreScannerManager:isActive(): boolean
	local equipped = ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL)
	local gadgetKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_KIND)
	return equipped == Enums.ToolKind.GADGET and gadgetKind == Enums.GadgetKind.ORE_SCANNER
end

function ClientOreScannerManager:getCooldownLeft(): number
	local readyTime = ClientDataManager:getCurrentPlayerAttribute(Attributes.GADGET_READY_TIME)
	return if typeof(readyTime) == "number" then math.max(0, readyTime - workspace:GetServerTimeNow()) else 0
end

function ClientOreScannerManager:use()
	local cooldownLeft = self:getCooldownLeft()
	if cooldownLeft > 0 then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(string.format(FEEDBACK_COOLING, math.ceil(cooldownLeft)), FEEDBACK_DISPLAY_SEC)
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_USE_ORE_SCANNER, {})
end

function ClientOreScannerManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or ClientOverlayManager:isOverlayActive() or not isUseInput(input) or not self:isActive() then
		return
	end
	self:use()
end

-- the sweep: a red sphere from nothing to the radius, fading as it grows
function ClientOreScannerManager:playSphere(origin: Vector3, radiusStuds: number, sweepSec: number)
	local sphere = Instance.new("Part")
	sphere.Name = "OreScanSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Material = Enum.Material.ForceField
	sphere.Color = UiStyle.ORE_SCAN_SPHERE_COLOR
	sphere.Transparency = SPHERE_TRANSPARENCY
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Size = Vector3.zero
	sphere.CFrame = CFrame.new(origin)
	sphere.Parent = self:getScansFolder()
	TweenService:Create(sphere, TweenInfo.new(sweepSec, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = Vector3.one * radiusStuds * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(sphere, sweepSec + 0.1)
end

-- every ore block within the radius, as one box per block grouped by
-- resource; nil when this client has no mine yet
function ClientOreScannerManager:buildOreModels(origin: Vector3, radiusStuds: number): { [number]: Model }
	local models: { [number]: Model } = {}
	local grid = ClientMineManager:getGrid()
	local space = ClientMineManager:getSpace()
	if not grid or not space then
		return models
	end
	local blockSize = space.blockSize
	local boxSize = Vector3.one * blockSize * BOX_SHARE
	local centreDepth, centreHeight, centreWidth = MineSpace.worldToCell(space, origin)
	local reachCells = math.ceil(radiusStuds / blockSize)
	for depth = math.max(centreDepth - reachCells, 0), math.min(centreDepth + reachCells, grid.depth - 1) do
		for height = math.max(centreHeight - reachCells, 0), math.min(centreHeight + reachCells, grid.height - 1) do
			for width = math.max(centreWidth - reachCells, 0), math.min(centreWidth + reachCells, grid.width - 1) do
				local rock = grid.cells[MineGenerator.cellIndex(grid, depth, height, width)]
				local resource = RockRules.rawResourceForRock(rock)
				if not resource then
					continue
				end
				local position = MineSpace.cellToWorld(space, depth, height, width)
				if (position - origin).Magnitude > radiusStuds then
					continue
				end
				local model = models[resource]
				if not model then
					model = Instance.new("Model")
					model.Name = `OreScan{Enums.getName(Enums.RawResource, resource)}`
					models[resource] = model
				end
				local cellIndex = MineGenerator.cellIndex(grid, depth, height, width)
				local box = Instance.new("Part")
				box.Size = boxSize
				box.CFrame = CFrame.new(position)
				box.Transparency = BOX_TRANSPARENCY
				box.Color = UiStyle.ORE_SCAN_COLOR_BY_RESOURCE[resource] or Color3.new(1, 1, 1)
				box.Anchored = true
				box.CanCollide = false
				box.CanQuery = false
				box.CanTouch = false
				box.CastShadow = false
				box.Parent = model
				local boxes = self.boxesByCellIndex[cellIndex]
				if not boxes then
					boxes = {}
					self.boxesByCellIndex[cellIndex] = boxes
				end
				table.insert(boxes, box)
			end
		end
	end
	return models
end

-- the highlights: in over the fade, held, out over the fade, then gone
function ClientOreScannerManager:playHighlights(origin: Vector3, radiusStuds: number, holdSec: number, fadeSec: number)
	local models = self:buildOreModels(origin, radiusStuds)
	for resource, model in models do
		local highlight = Instance.new("Highlight")
		highlight.FillColor = UiStyle.ORE_SCAN_COLOR_BY_RESOURCE[resource] or Color3.new(1, 1, 1)
		highlight.OutlineColor = highlight.FillColor
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = model
		highlight.Parent = model
		model.Parent = self:getScansFolder()
		TweenService:Create(highlight, TweenInfo.new(fadeSec, Enum.EasingStyle.Sine), {
			FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY,
			OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY,
		}):Play()
		task.delay(
			fadeSec + holdSec,
			function()
				if model.Parent then
					TweenService:Create(highlight, TweenInfo.new(fadeSec, Enum.EasingStyle.Sine), {
						FillTransparency = 1,
						OutlineTransparency = 1,
					}):Play()
				end
			end
		)
		Debris:AddItem(model, fadeSec + holdSec + fadeSec + 0.1)
	end
	-- the boxes are forgotten with their scan
	task.delay(
		fadeSec + holdSec + fadeSec + 0.2,
		function()
			for cellIndex, boxes in self.boxesByCellIndex do
				local kept = {}
				for _, box in boxes do
					if box.Parent then
						table.insert(kept, box)
					end
				end
				if #kept > 0 then
					self.boxesByCellIndex[cellIndex] = kept
				else
					self.boxesByCellIndex[cellIndex] = nil
				end
			end
		end
	)
end

-- a block mined out from under its highlight takes the highlight with it
function ClientOreScannerManager:onCellCleared(cellIndex: number)
	local boxes = self.boxesByCellIndex[cellIndex]
	if not boxes then
		return
	end
	self.boxesByCellIndex[cellIndex] = nil
	for _, box in boxes do
		box:Destroy()
	end
end

function ClientOreScannerManager:onScan(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_ORE_SCAN_SHAPE) then
		warn("ClientOreScannerManager: malformed NotifyOreScan")
		return
	end
	local pulseSec = math.max(payload.sweepSec, payload.revealDelaySec + payload.fadeSec + payload.holdSec + payload.fadeSec)
	for pulse = 1, payload.pulseCount do
		task.delay(
			(pulse - 1) * pulseSec,
			function()
				self:playPulse(payload.origin, payload.radiusStuds, payload.sweepSec, payload.revealDelaySec, payload.holdSec, payload.fadeSec)
			end
		)
	end
end

-- one pulse: the sound and the sphere at once, the highlights
-- revealDelaySec later (designer, 2026-10-22: before the sphere is out)
function ClientOreScannerManager:playPulse(origin: Vector3, radiusStuds: number, sweepSec: number, revealDelaySec: number, holdSec: number, fadeSec: number)
	ClientSoundManager:playSfxAt(origin, SoundNames.Sfx.ORE_SCAN, SCAN_SOUND_FULL_VOLUME_STUDS, SCAN_SOUND_RANGE_STUDS)
	self:playSphere(origin, radiusStuds, sweepSec)
	task.delay(
		revealDelaySec,
		function()
			self:playHighlights(origin, radiusStuds, holdSec, fadeSec)
		end
	)
end

function ClientOreScannerManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_ORE_SCAN,
		function(payload: any)
			self:onScan(payload)
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			self:onInputBegan(input, isGameProcessed)
		end
	)
	ClientMineManager:subscribeCellCleared(
		function(cellIndex: number)
			self:onCellCleared(cellIndex)
		end
	)
end

function ClientOreScannerManager.new(): ClientOreScannerManager
	local self = setmetatable({}, ClientOreScannerManager) :: ClientOreScannerManager
	self.scansFolder = nil
	self.boxesByCellIndex = {}
	return self
end

return ClientOreScannerManager.new()
