--!strict

-- Gives every character an invisible collider over its head (GDD
-- "Mining", decided 2026-09-29), so a player needs a two-block passage:
-- Roblox lets only the torso of an R15 character collide, and a one-block
-- hole let the head into the rock above and the camera into the empty
-- mine behind it. The part is welded to the Head, never queried or
-- touched (weapon rays and prompts ignore it), and switched off while the
-- character sits, so a helicopter cabin does not press on it. Tuning in
-- GameData/Mining/Clearance.
local Players = game:GetService("Players")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ClearanceData = require("@game/ServerScriptService/GameData/Mining/Clearance")

local ClearanceManager = {}
ClearanceManager.__index = ClearanceManager

export type ClearanceManager = typeof(setmetatable({} :: {}, ClearanceManager))

local HEAD_PART_NAME = "Head"
local HEAD_WAIT_SEC = 10

function ClearanceManager:applyToCharacter(character: Model)
	local head = character:WaitForChild(HEAD_PART_NAME, HEAD_WAIT_SEC)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not head:IsA("BasePart") or not humanoid or character:FindFirstChild(Constants.CHARACTER_CLEARANCE_PART) then
		return
	end
	local collider = Instance.new("Part")
	collider.Name = Constants.CHARACTER_CLEARANCE_PART
	collider.Size = Vector3.new(ClearanceData.WIDTH_STUDS, ClearanceData.HEIGHT_STUDS, ClearanceData.WIDTH_STUDS)
	collider.Transparency = 1
	collider.Massless = true
	collider.CanCollide = true
	collider.CanQuery = false
	collider.CanTouch = false
	collider.CastShadow = false
	collider.CFrame = head.CFrame * CFrame.new(0, ClearanceData.LIFT_STUDS, 0)
	local weld = Instance.new("Weld")
	weld.Part0 = head
	weld.Part1 = collider
	weld.C0 = CFrame.new(0, ClearanceData.LIFT_STUDS, 0)
	weld.Parent = collider
	collider.Parent = character
	-- a seated character is welded to its seat and needs no headroom
	humanoid.Seated:Connect(
		function(isSeated: boolean)
			collider.CanCollide = not isSeated
		end
	)
	collider.CanCollide = not humanoid.Sit
end

function ClearanceManager:watchPlayer(player: Player)
	player.CharacterAdded:Connect(
		function(character: Model)
			self:applyToCharacter(character)
		end
	)
	if player.Character then
		self:applyToCharacter(player.Character)
	end
end

function ClearanceManager:init()
	for _, player in Players:GetPlayers() do
		self:watchPlayer(player)
	end
	Players.PlayerAdded:Connect(
		function(player: Player)
			self:watchPlayer(player)
		end
	)
end

function ClearanceManager.new(): ClearanceManager
	local self = setmetatable({}, ClearanceManager) :: ClearanceManager
	return self
end

return ClearanceManager.new()
