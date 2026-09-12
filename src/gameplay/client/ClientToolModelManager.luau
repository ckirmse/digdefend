--!strict

-- Shows the tool every player holds: each AllPlayers entry carries the
-- public EquippedTool attribute, and this client welds the matching
-- GameAssets/Tools model to that character's right hand. Purely visual and
-- local, so the server never owns a tool model.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)

local ClientToolModelManager = {}
ClientToolModelManager.__index = ClientToolModelManager

type Held = {
	tool: number,
	model: Model,
}

export type ClientToolModelManager = typeof(setmetatable(
	{} :: {
		equippedByUserId: { [number]: number },
		heldByUserId: { [number]: Held },
		warnedTools: { [number]: boolean },
	},
	ClientToolModelManager
))

local HELD_MODEL_NAME = "HeldTool"

local function findHand(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand
	end
	return nil
end

function ClientToolModelManager:getTemplate(tool: number): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local tools = if gameAssets then gameAssets:FindFirstChild(Constants.TOOL_TEMPLATES_FOLDER) else nil
	local key = Enums.getName(Enums.ToolKind, tool)
	local template = if tools and key then tools:FindFirstChild(key) else nil
	if template and template:IsA("Model") and template:FindFirstChild(Constants.TOOL_HANDLE_PART) then
		return template
	end
	if not self.warnedTools[tool] then
		self.warnedTools[tool] = true
		warn(`ClientToolModelManager: no Model with a {Constants.TOOL_HANDLE_PART} for tool {tostring(key)} under GameAssets.{Constants.TOOL_TEMPLATES_FOLDER}`)
	end
	return nil
end

function ClientToolModelManager:remove(userId: number)
	local held = self.heldByUserId[userId]
	if held then
		held.model:Destroy()
		self.heldByUserId[userId] = nil
	end
end

function ClientToolModelManager:attach(userId: number, character: Model, tool: number)
	local hand = findHand(character)
	local template = self:getTemplate(tool)
	if not hand or not template then
		return
	end
	local model = template:Clone()
	model.Name = HELD_MODEL_NAME
	local handle = model:FindFirstChild(Constants.TOOL_HANDLE_PART) :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	local grip = hand:FindFirstChild("RightGripAttachment")
	local gripCFrame = if grip and grip:IsA("Attachment") then grip.CFrame else CFrame.new(0, -1, 0)
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = gripCFrame
	weld.Parent = handle
	model.Parent = character
	self.heldByUserId[userId] = { tool = tool, model = model }
end

function ClientToolModelManager:refresh(userId: number)
	local tool = self.equippedByUserId[userId] or MiningRules.NO_TOOL
	local held = self.heldByUserId[userId]
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	if held and (held.tool ~= tool or held.model.Parent ~= character) then
		self:remove(userId)
		held = nil
	end
	if tool == MiningRules.NO_TOOL or held or not character then
		return
	end
	self:attach(userId, character, tool)
end

function ClientToolModelManager:watchCharacter(player: Player)
	player.CharacterAdded:Connect(
		function(character: Model)
			-- the hand streams in after the model
			character:WaitForChild("Humanoid", 5)
			task.defer(
				function()
					self:refresh(player.UserId)
				end
			)
		end
	)
end

function ClientToolModelManager:init()
	for _, player in Players:GetPlayers() do
		self:watchCharacter(player)
	end
	Players.PlayerAdded:Connect(
		function(player: Player)
			self:watchCharacter(player)
		end
	)
	ClientDataManager:subscribeAllPlayers({
		onAdded = function(userId: number, data: ClientDataManager.PublicData)
			self.equippedByUserId[userId] = data.equippedTool
			self:refresh(userId)
		end,
		onChanged = function(userId: number, data: ClientDataManager.PublicData)
			self.equippedByUserId[userId] = data.equippedTool
			self:refresh(userId)
		end,
		onRemoved = function(userId: number)
			self.equippedByUserId[userId] = nil
			self:remove(userId)
		end,
	})
end

function ClientToolModelManager.new(): ClientToolModelManager
	local self = setmetatable({}, ClientToolModelManager) :: ClientToolModelManager
	self.equippedByUserId = {}
	self.heldByUserId = {}
	self.warnedTools = {}
	return self
end

return ClientToolModelManager.new()
