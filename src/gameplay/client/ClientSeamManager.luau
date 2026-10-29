--!strict

-- The Seams as this client draws them (M68, GDD "Monster Types": Seam).
-- The server sends every awake Seam's cells (NotifySeams, the whole list,
-- a few dozen numbers) whenever one wakes, steps, spreads, or dies; this
-- manager stands one clone of the designer's block model
-- (GameAssets/Monsters/SEAM: a 4x4x4 Rock with a face on every side) on
-- every such cell, pivoted to the cell's centre, so the Seam is the block.
-- The clone is scaled a hair past the block so it covers the rendered rock
-- underneath, and none of its parts collide or answer a query, so a swing
-- still lands on the rock part under it, which is the cell the server
-- judges. A Seam that just woke (NotifySeamWoken, sent after the list that holds
-- it) plays the Guh sound the designer authored under the model's Rock, from
-- the standing clone, so the wake is heard where the face appeared.
-- A Seam block that was broken (NotifySeamBroken, sent before the list
-- that no longer holds it) bursts rather than drops: its parts vanish with
-- the rock, the Rock's Laugh plays and its Smoke emits for SMOKE_SEC, then
-- the clone goes; and if this client's own player stands within the
-- burst's radius they are shoved back down the tunnel (the client owns
-- its character's physics, so a server-set velocity would be lost; the
-- server did the damage). Sleeping Seams never reach this client.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SeamRules = require("@game/ReplicatedStorage/Shared/SeamRules")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientSeamManager = {}
ClientSeamManager.__index = ClientSeamManager

export type ClientSeamManager = typeof(setmetatable(
	{} :: {
		cells: { SeamRules.Cell },
		-- one standing clone per cell, by SeamRules.cellKey
		blocksByKey: { [string]: Model },
		changedCallbacks: { () -> () },
		-- cells whose wake sound waits for their block to stand
		pendingWakeKeys: { [string]: boolean },
		-- cells whose block is to be played out when the list drops it
		pendingBrokenKeys: { [string]: boolean },
		folder: Folder?,
		hasRequested: boolean,
		hasWarnedTemplate: boolean,
		hasWarnedWakeSound: boolean,
		hasWarnedBreakEffects: boolean,
		isDirty: boolean,
	},
	ClientSeamManager
))

local NOTIFY_SEAMS_SHAPE = {
	cells = { type = "array", elementType = "nonnegativeInteger" },
}
local NOTIFY_SEAM_WOKEN_SHAPE = {
	depth = "nonnegativeInteger",
	height = "nonnegativeInteger",
	width = "nonnegativeInteger",
}
local NOTIFY_SEAM_BROKEN_SHAPE = {
	depth = "nonnegativeInteger",
	height = "nonnegativeInteger",
	width = "nonnegativeInteger",
	radiusStuds = "positiveNumber",
	knockbackStuds = "positiveNumber",
}

local FOLDER_NAME = "Seams"
-- the designer's wake sound under the model's Rock part
local WAKE_SOUND_NAME = "Guh"
-- the designer's laugh and smoke under the Rock, for a cleared block
local BREAK_SOUND_NAME = "Laugh"
local BREAK_SMOKE_NAME = "Smoke"
-- how long the smoke emits, and how long the played-out clone stays for
-- the laugh to finish
local SMOKE_SEC = 0.6
local BREAK_LIFETIME_SEC = 4
-- the clone stands this much larger than the block so it covers the
-- rendered rock under it rather than fighting its surface
local COVER_SCALE = 1.015
-- the shove: studs per second along the way out per stud of knockback,
-- plus a lift so the feet leave the ground
local KNOCKBACK_SPEED_PER_STUD = 2.5
local KNOCKBACK_LIFT_STUDS_PER_SEC = 18

function ClientSeamManager:findTemplate(): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local monsters = if gameAssets then gameAssets:FindFirstChild(Constants.MONSTER_TEMPLATES_FOLDER) else nil
	local template = if monsters then monsters:FindFirstChild(Enums.getName(Enums.MonsterKind, Enums.MonsterKind.SEAM)) else nil
	if template and template:IsA("Model") and template.PrimaryPart then
		return template
	end
	if not self.hasWarnedTemplate then
		self.hasWarnedTemplate = true
		warn(`ClientSeamManager: no SEAM model with a PrimaryPart under GameAssets.{Constants.MONSTER_TEMPLATES_FOLDER}`)
	end
	return nil
end

function ClientSeamManager:getFolder(): Folder
	local folder = self.folder
	if folder and folder.Parent then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	self.folder = folder
	return folder
end

function ClientSeamManager:makeBlock(template: Model, space: MineSpace.MineSpace, cell: SeamRules.Cell): Model
	local block = template:Clone()
	for _, descendant in block:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	block:ScaleTo(COVER_SCALE)
	block:PivotTo(CFrame.new(MineSpace.cellToWorld(space, cell.depth, cell.height, cell.width)))
	block:SetAttribute("Depth", cell.depth)
	block:SetAttribute("Height", cell.height)
	block:SetAttribute("Width", cell.width)
	block.Parent = self:getFolder()
	return block
end

-- stands a block on every awake cell and takes down the ones that left;
-- a cell that is still a Seam keeps its clone, so a drift moves one block
-- and leaves the rest alone
-- whether an awake Seam stands on this cell, as drawn: what the mining HUD
-- asks so the block under the aim can read as a mystery (designer, 2026-10-29)
function ClientSeamManager:isSeamCell(depth: number, height: number, width: number): boolean
	return self.blocksByKey[SeamRules.cellKey(depth, height, width)] ~= nil
end

-- called after every redraw, so a HUD reading isSeamCell can refresh when a
-- Seam wakes or breaks under the aim
function ClientSeamManager:subscribeChanged(callback: () -> ())
	table.insert(self.changedCallbacks, callback)
end

function ClientSeamManager:redraw()
	self.isDirty = false
	local space = ClientMineManager:getSpace()
	local template = self:findTemplate()
	if not space or not template then
		return
	end
	local wanted: { [string]: SeamRules.Cell } = {}
	for _, cell in self.cells do
		wanted[SeamRules.cellKey(cell.depth, cell.height, cell.width)] = cell
	end
	for key, block in self.blocksByKey do
		if not wanted[key] then
			if self.pendingBrokenKeys[key] then
				self.pendingBrokenKeys[key] = nil
				self:playBreak(block)
			else
				block:Destroy()
			end
			self.blocksByKey[key] = nil
		end
	end
	for key, cell in wanted do
		if not self.blocksByKey[key] then
			self.blocksByKey[key] = self:makeBlock(template, space, cell)
		end
	end
	for key in self.pendingWakeKeys do
		if self.blocksByKey[key] then
			self.pendingWakeKeys[key] = nil
			self:playWake(self.blocksByKey[key])
		end
	end
	for _, callback in self.changedCallbacks do
		callback()
	end
end

-- the rock is gone, so the face goes with it: every part turns invisible,
-- the laugh plays and the smoke runs its SMOKE_SEC, and the clone leaves
-- once the laugh has had its time
function ClientSeamManager:playBreak(block: Model)
	local rock = block.PrimaryPart
	for _, descendant in block:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
		elseif descendant:IsA("Decal") then
			descendant.Transparency = 1
		end
	end
	local sound = if rock then rock:FindFirstChild(BREAK_SOUND_NAME) else nil
	if sound and sound:IsA("Sound") then
		sound.TimePosition = 0
		sound:Play()
	end
	local smoke = if rock then rock:FindFirstChild(BREAK_SMOKE_NAME) else nil
	if smoke and smoke:IsA("ParticleEmitter") then
		smoke.Enabled = true
		task.delay(
			SMOKE_SEC,
			function()
				if smoke.Parent then
					smoke.Enabled = false
				end
			end
		)
	end
	if not sound and not smoke and not self.hasWarnedBreakEffects then
		self.hasWarnedBreakEffects = true
		warn(`ClientSeamManager: the SEAM model's Rock has neither a {BREAK_SOUND_NAME} Sound nor a {BREAK_SMOKE_NAME} emitter`)
	end
	Debris:AddItem(block, BREAK_LIFETIME_SEC)
end

function ClientSeamManager:onSeamBroken(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_SEAM_BROKEN_SHAPE)
	if not isValid then
		warn("ClientSeamManager: bad NotifySeamBroken payload:", errorMessage)
		return
	end
	self.pendingBrokenKeys[SeamRules.cellKey(payload.depth, payload.height, payload.width)] = true
	self:shoveLocalPlayer(payload.depth, payload.height, payload.width, payload.radiusStuds, payload.knockbackStuds)
end

function ClientSeamManager:playWake(block: Model)
	local rock = block.PrimaryPart
	local sound = if rock then rock:FindFirstChild(WAKE_SOUND_NAME) else nil
	if sound and sound:IsA("Sound") then
		sound.TimePosition = 0
		sound:Play()
	elseif not self.hasWarnedWakeSound then
		self.hasWarnedWakeSound = true
		warn(`ClientSeamManager: the SEAM model's Rock has no Sound named {WAKE_SOUND_NAME}`)
	end
end

-- the list that holds the woken cell arrives first, so its block usually
-- stands by the next heartbeat; the sound waits for it either way
function ClientSeamManager:onSeamWoken(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_SEAM_WOKEN_SHAPE)
	if not isValid then
		warn("ClientSeamManager: bad NotifySeamWoken payload:", errorMessage)
		return
	end
	self.pendingWakeKeys[SeamRules.cellKey(payload.depth, payload.height, payload.width)] = true
	self.isDirty = true
end

function ClientSeamManager:onSeams(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_SEAMS_SHAPE)
	if not isValid then
		warn("ClientSeamManager: bad NotifySeams payload:", errorMessage)
		return
	end
	self.cells = SeamRules.decodeCells(payload.cells)
	self.isDirty = true
end

-- the shove, for this client's player when they stand in the burst
function ClientSeamManager:shoveLocalPlayer(depth: number, height: number, width: number, radiusStuds: number, knockbackStuds: number)
	local space = ClientMineManager:getSpace()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not space or not root or not root:IsA("BasePart") then
		return
	end
	local blockCentre = MineSpace.cellToWorld(space, depth, height, width)
	local away = root.Position - blockCentre
	if away.Magnitude > radiusStuds then
		return
	end
	local flat = Vector3.new(away.X, 0, away.Z)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else -root.CFrame.LookVector
	root.AssemblyLinearVelocity = direction * knockbackStuds * KNOCKBACK_SPEED_PER_STUD + Vector3.new(0, KNOCKBACK_LIFT_STUDS_PER_SEC, 0)
end

-- the list can arrive before the mine has; the blocks stand once both are
-- here, and the client asks for the list once it can place them
function ClientSeamManager:step()
	if not ClientMineManager:getGrid() then
		return
	end
	if not self.hasRequested then
		self.hasRequested = true
		ClientNetManager:fireServer(NetEventNames.TRY_REQUEST_SEAMS, {})
	end
	if self.isDirty then
		self:redraw()
	end
end

function ClientSeamManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_SEAMS,
		function(payload: any)
			self:onSeams(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_SEAM_WOKEN,
		function(payload: any)
			self:onSeamWoken(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_SEAM_BROKEN,
		function(payload: any)
			self:onSeamBroken(payload)
		end
	)
	RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function ClientSeamManager.new(): ClientSeamManager
	local self = setmetatable({}, ClientSeamManager)
	self.cells = {}
	self.blocksByKey = {}
	self.pendingWakeKeys = {}
	self.pendingBrokenKeys = {}
	self.folder = nil
	self.hasRequested = false
	self.hasWarnedTemplate = false
	self.hasWarnedWakeSound = false
	self.hasWarnedBreakEffects = false
	self.isDirty = false
	self.changedCallbacks = {}
	return self
end

return ClientSeamManager.new()
