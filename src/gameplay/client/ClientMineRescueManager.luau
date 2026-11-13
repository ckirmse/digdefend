--!strict

-- Puts the local character back on its feet when it ends up inside the
-- mine's rock (2026-11-13: a player fell through the mine and died). The
-- mine's blocks are parts on each client only, and only the exposed shell
-- is rendered, so a character that gets past one face (squeezed through by
-- a knockback, a block that arrived late, a physics push-out) meets no
-- block again and falls until the engine kills it, which the run counts as
-- a death. This asks the client's own copy of the grid, a few times a
-- second, whether the character's root is in a solid cell or under the
-- mine (pure MineGridQuery.isInsideRock), remembers the last spot it stood
-- on the ground outside the rock, and returns it there. The character's
-- physics belong to its own client, so the fix is here; the server needs
-- no part in it.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local MineGridQuery = require("@game/ReplicatedStorage/Shared/MineGridQuery")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientMineRescueManager = {}
ClientMineRescueManager.__index = ClientMineRescueManager

export type ClientMineRescueManager = typeof(setmetatable(
	{} :: {
		lastStandingCFrame: CFrame?,
		insideRockCheckCount: number,
	},
	ClientMineRescueManager
))

local CHECK_INTERVAL_SEC = 0.1
-- this many checks in a row inside the rock before the character is moved,
-- so one odd frame never yanks a player
local CHECKS_BEFORE_RESCUE = 2

function ClientMineRescueManager:isInsideRock(position: Vector3): boolean
	local grid = ClientMineManager:getGrid()
	local space = ClientMineManager:getSpace()
	if not grid or not space then
		return false
	end
	local depth, height, width = MineSpace.worldToCell(space, position)
	return MineGridQuery.isInsideRock(grid, depth, height, width)
end

function ClientMineRescueManager:check()
	local player = Players.LocalPlayer
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	-- a dead body is laid out and moved by ReviveManager, a seated one by its seat
	local isDead = ClientDataManager:getPublicAttribute(player.UserId, Attributes.IS_DEAD) == true
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or humanoid.Sit or isDead then
		self.insideRockCheckCount = 0
		return
	end
	if not self:isInsideRock(root.Position) then
		self.insideRockCheckCount = 0
		-- only a spot with ground under it is worth going back to
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			self.lastStandingCFrame = root.CFrame
		end
		return
	end
	self.insideRockCheckCount += 1
	if self.insideRockCheckCount < CHECKS_BEFORE_RESCUE then
		return
	end
	self.insideRockCheckCount = 0
	local lastStandingCFrame = self.lastStandingCFrame
	if not lastStandingCFrame then
		warn("ClientMineRescueManager: the character is inside the mine's rock and has no standing spot to go back to")
		return
	end
	warn(`ClientMineRescueManager: the character was inside the mine's rock at {root.Position}; put back at {lastStandingCFrame.Position}`)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = lastStandingCFrame
end

function ClientMineRescueManager:init()
	Players.LocalPlayer.CharacterAdded:Connect(
		function()
			-- a new body starts with no history
			self.lastStandingCFrame = nil
			self.insideRockCheckCount = 0
		end
	)
	ClientTicker.every(
		CHECK_INTERVAL_SEC,
		function()
			self:check()
		end
	)
end

function ClientMineRescueManager.new(): ClientMineRescueManager
	local self = setmetatable({}, ClientMineRescueManager) :: ClientMineRescueManager
	self.lastStandingCFrame = nil
	self.insideRockCheckCount = 0
	return self
end

return ClientMineRescueManager.new()
