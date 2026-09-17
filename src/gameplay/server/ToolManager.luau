--!strict

-- Each player's tools for the run (GDD "Tools"): the slot list in stable
-- order, which one is equipped, and the pick axe level. Run state, not
-- persistent, held in Lua and replicated as attributes: the equipped tool is
-- public so every client shows the held model; slots and level are private.
-- Everyone starts with a pick axe; WeaponManager hands out the weapon and
-- says which Enums.WeaponKind fills the WEAPON slot. Consumables from
-- the Mining Supplies Store (torch, dynamite) hold a count beside their slot
-- and leave the bar when it reaches zero.
--
-- The held model is a real Roblox Tool (decided 2026-09-15, as in both
-- reference games): the Humanoid grips it, plays the arm pose, and keeps it
-- visible in first person, on every client, for free. The Tool is only the
-- visual vehicle: it is built here from the GameAssets/Tools template when
-- a tool is equipped and destroyed when it is not, never stored in
-- player.Backpack. A Roblox-side unequip (Backspace, death) parks the Tool
-- in the Backpack, which is treated as an unequip request.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local ToolManager = {}
ToolManager.__index = ToolManager

type ToolState = {
	slots: { number },
	equipped: number,
	pickAxeLevel: number,
	-- the Enums.WeaponKind in the WEAPON slot; 0 until WeaponManager sets it
	weaponKind: number,
	-- consumables only: how many of each are held
	countByTool: { [number]: number },
}

export type ToolManager = typeof(setmetatable(
	{} :: {
		stateByPlayer: { [Player]: ToolState },
		heldToolByPlayer: { [Player]: Tool },
		warnedTemplates: { [string]: boolean },
	},
	ToolManager
))

-- the default grip holds the haft upright with the head running left to
-- right across the body; a quarter turn about the haft points the head
-- forward at the rock (measured 2026-09-16)
local PICK_AXE_GRIP = CFrame.Angles(0, math.rad(90), 0)

local TRY_EQUIP_TOOL_SHAPE = {
	-- an Enums.ToolKind, or MiningRules.NO_TOOL to unequip
	tool = "nonnegativeInteger",
}

local STARTING_PICK_AXE_LEVEL = 1

function ToolManager:getState(player: Player): ToolState?
	return self.stateByPlayer[player]
end

function ToolManager:getEquippedTool(player: Player): number
	local state = self.stateByPlayer[player]
	return if state then state.equipped else MiningRules.NO_TOOL
end

function ToolManager:getPickAxeLevel(player: Player): number
	local state = self.stateByPlayer[player]
	return if state then state.pickAxeLevel else STARTING_PICK_AXE_LEVEL
end

function ToolManager:hasTool(player: Player, tool: number): boolean
	local state = self.stateByPlayer[player]
	return state ~= nil and table.find(state.slots, tool) ~= nil
end

function ToolManager:getToolCount(player: Player, tool: number): number
	local state = self.stateByPlayer[player]
	return if state then state.countByTool[tool] or 0 else 0
end

-- the store raised the level; the pick axe model every client shows follows
-- the public attribute
function ToolManager:setPickAxeLevel(player: Player, level: number)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	state.pickAxeLevel = level
	self:replicate(player)
end

function ToolManager:getWeaponKind(player: Player): number
	local state = self.stateByPlayer[player]
	return if state then state.weaponKind else 0
end

-- which weapon the WEAPON slot holds; public so every client can name it
function ToolManager:setWeaponKind(player: Player, weaponKind: number)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	state.weaponKind = weaponKind
	self:replicate(player)
end

-- a purchase or a pickup: the slot appears with the first one held
function ToolManager:addConsumable(player: Player, tool: number, amount: number)
	local state = self.stateByPlayer[player]
	if not state or not MiningRules.isConsumable(tool) or amount <= 0 then
		return
	end
	state.countByTool[tool] = (state.countByTool[tool] or 0) + amount
	if not table.find(state.slots, tool) then
		table.insert(state.slots, tool)
	end
	self:replicate(player)
end

-- spends one; the slot goes with the last one, unequipping it. Returns
-- false when none are held, so a use never goes through unpaid
function ToolManager:consume(player: Player, tool: number): boolean
	local state = self.stateByPlayer[player]
	if not state then
		return false
	end
	local count = state.countByTool[tool] or 0
	if count <= 0 then
		return false
	end
	count -= 1
	if count == 0 then
		state.countByTool[tool] = nil
		local index = table.find(state.slots, tool)
		if index then
			table.remove(state.slots, index)
		end
		if state.equipped == tool then
			state.equipped = MiningRules.NO_TOOL
		end
	else
		state.countByTool[tool] = count
	end
	self:replicate(player)
	return true
end

-- "PICK_AXE_3", "WEAPON_RIFLE", "TORCH": the GameAssets/Tools model for what a player holds
function ToolManager:templateNameFor(player: Player, tool: number): string
	local key = Enums.getName(Enums.ToolKind, tool) or "?"
	if tool == Enums.ToolKind.PICK_AXE then
		return `{key}_{self:getPickAxeLevel(player)}`
	end
	if tool == Enums.ToolKind.WEAPON then
		return WeaponRules.templateNameFor(self:getWeaponKind(player))
	end
	return key
end

function ToolManager:findTemplate(templateName: string): Model?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local tools = if gameAssets then gameAssets:FindFirstChild(Constants.TOOL_TEMPLATES_FOLDER) else nil
	local template = if tools then tools:FindFirstChild(templateName) else nil
	if template and template:IsA("Model") and template:FindFirstChild(Constants.TOOL_HANDLE_PART) then
		return template
	end
	if not self.warnedTemplates[templateName] then
		self.warnedTemplates[templateName] = true
		warn(`ToolManager: no Model with a {Constants.TOOL_HANDLE_PART} named {templateName} under GameAssets.{Constants.TOOL_TEMPLATES_FOLDER}; run scripts/studio/build_tool_templates.luau`)
	end
	return nil
end

function ToolManager:removeHeldTool(player: Player)
	local held = self.heldToolByPlayer[player]
	if held then
		self.heldToolByPlayer[player] = nil
		held:Destroy()
	end
end

-- builds the Tool for the equipped kind from its template: the template's
-- parts move into the Tool (its Handle is what the Humanoid grips, the rest
-- stay welded to it) and the Tool goes on the character
function ToolManager:syncHeldTool(player: Player)
	local state = self.stateByPlayer[player]
	local character = player.Character
	local held = self.heldToolByPlayer[player]
	local wantedName = if state and state.equipped ~= MiningRules.NO_TOOL then self:templateNameFor(player, state.equipped) else nil
	if held and (wantedName == nil or held:GetAttribute(Attributes.TOOL_TEMPLATE) ~= wantedName or held.Parent ~= character) then
		self:removeHeldTool(player)
		held = nil
	end
	if not state or not wantedName or held or not character or not character:FindFirstChildOfClass("Humanoid") then
		return
	end
	local template = self:findTemplate(wantedName)
	if not template then
		return
	end
	local tool = Instance.new("Tool")
	tool.Name = Enums.getPublicName(Enums.ToolKind, state.equipped) or wantedName
	if state.equipped == Enums.ToolKind.WEAPON then
		tool.Name = Enums.getPublicName(Enums.WeaponKind, state.weaponKind) or wantedName
	end
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- clicks are read by the mining, weapon, torch, and dynamite managers, not the Tool
	tool.ManualActivationOnly = true
	tool.ToolTip = ""
	if state.equipped == Enums.ToolKind.PICK_AXE then
		tool.Grip = PICK_AXE_GRIP
	end
	tool:SetAttribute(Attributes.TOOL_TEMPLATE, wantedName)
	local model = template:Clone()
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			child.Anchored = false
			child.CanCollide = false
			child.CanQuery = false
			child.CanTouch = false
			child.Massless = true
		end
		child.Parent = tool
	end
	model:Destroy()
	self.heldToolByPlayer[player] = tool
	tool.Parent = character
	tool.AncestryChanged:Connect(
		function(_child: Instance, parent: Instance?)
			-- Roblox unequip paths park the Tool in player.Backpack; that is
			-- an unequip here, never storage
			if parent and parent:IsA("Backpack") and self.heldToolByPlayer[player] == tool then
				self:setEquippedTool(player, MiningRules.NO_TOOL)
			end
		end
	)
end

function ToolManager:replicate(player: Player)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	self:syncHeldTool(player)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.EQUIPPED_TOOL, state.equipped)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.EQUIPPED_TOOL, state.equipped)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.TOOL_SLOTS, MiningRules.encodeToolSlots(state.slots))
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.TOOL_COUNTS, MiningRules.encodeToolCounts(state.countByTool))
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.PICK_AXE_LEVEL, state.pickAxeLevel)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.PICK_AXE_LEVEL, state.pickAxeLevel)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.WEAPON_KIND, state.weaponKind)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_KIND, state.weaponKind)
end

function ToolManager:grantTool(player: Player, tool: number)
	local state = self.stateByPlayer[player]
	if not state or table.find(state.slots, tool) then
		return
	end
	table.insert(state.slots, tool)
	self:replicate(player)
end

function ToolManager:setEquippedTool(player: Player, tool: number)
	local state = self.stateByPlayer[player]
	if not state then
		return
	end
	if tool ~= MiningRules.NO_TOOL and not table.find(state.slots, tool) then
		warn(`ToolManager: {player.Name} tried to equip tool {tool} they do not have`)
		return
	end
	if state.equipped == tool then
		return
	end
	state.equipped = tool
	self:replicate(player)
end

function ToolManager:getNetHandlers()
	return {
		[NetEventNames.TRY_EQUIP_TOOL] = {
			shape = TRY_EQUIP_TOOL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				local tool = payload.tool
				if tool ~= MiningRules.NO_TOOL and not Enums.isValidValue(Enums.ToolKind, tool) then
					warn(`ToolManager: {player.Name} sent unknown tool {tool}`)
					return
				end
				self:setEquippedTool(player, tool)
			end,
		},
	}
end

-- ready-sequence entry: a fresh arrival gets the starting pick axe; a
-- dev-tool reset does not replay this, so run state survives it
function ToolManager:onPlayerReady(player: Player)
	if self.stateByPlayer[player] then
		self:replicate(player)
		return
	end
	self.stateByPlayer[player] = {
		slots = {},
		equipped = MiningRules.NO_TOOL,
		pickAxeLevel = STARTING_PICK_AXE_LEVEL,
		weaponKind = 0,
		countByTool = {},
	}
	-- a respawn arrives with the Roblox side of the old Tool gone; the
	-- equipped kind is still held here, so the Tool is rebuilt on the new body
	player.CharacterAdded:Connect(
		function(character: Model)
			character:WaitForChild("Humanoid", 5)
			self:syncHeldTool(player)
		end
	)
	self:grantTool(player, Enums.ToolKind.PICK_AXE)
end

function ToolManager:init()
	GameController:registerPlaceManager(self)
	-- not a teardown entry: a dev-tool reset must not strip the run's tools
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.stateByPlayer[player] = nil
			self.heldToolByPlayer[player] = nil
		end
	)
end

function ToolManager.new(): ToolManager
	local self = setmetatable({}, ToolManager) :: ToolManager
	self.stateByPlayer = {}
	self.heldToolByPlayer = {}
	self.warnedTemplates = {}
	return self
end

return ToolManager.new()
