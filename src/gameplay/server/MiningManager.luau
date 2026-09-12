--!strict

-- Server side of Mining Mode (GDD "Mining Rock"): every swing arrives as
-- TryHitRock with a grid cell and is checked here before MineManager takes
-- damage: pick axe equipped, a diggable block, the player close enough, and
-- not faster than the pick axe swings. Results go to every client so the
-- crack state and the removal are seen by all.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PickAxeData = require("@game/ServerScriptService/GameData/Mining/PickAxe")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local MineManager = require(script.Parent.MineManager)
local ToolManager = require(script.Parent.ToolManager)

local MiningManager = {}
MiningManager.__index = MiningManager

export type MiningManager = typeof(setmetatable(
	{} :: {
		lastHitTimeByPlayer: { [Player]: number },
	},
	MiningManager
))

local TRY_HIT_ROCK_SHAPE = {
	depth = "nonnegativeInteger",
	height = "nonnegativeInteger",
	width = "nonnegativeInteger",
}

function MiningManager:getPlayerPosition(player: Player): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function MiningManager:handleHit(player: Player, depth: number, height: number, width: number)
	if ToolManager:getEquippedTool(player) ~= Enums.ToolKind.PICK_AXE then
		return
	end
	local rock = MineManager:getRockAt(depth, height, width)
	if not rock or rock == MineGenerator.AIR then
		return
	end
	local definition = RockDefinitionsData.ROCKS[rock]
	if not definition or not definition.hp then
		-- bedrock and gates: nothing to do, and no reason to warn
		return
	end
	local space = MineManager:getSpace()
	local playerPosition = self:getPlayerPosition(player)
	if not space or not playerPosition then
		return
	end
	local blockCenter = MineSpace.cellToWorld(space, depth, height, width)
	if not MiningRules.isWithinReach(playerPosition, blockCenter, PickAxeData.REACH_STUDS, PickAxeData.REACH_TOLERANCE_STUDS) then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not MiningRules.canHit(self.lastHitTimeByPlayer[player], now, PickAxeData.HIT_COOLDOWN_SEC) then
		return
	end
	self.lastHitTimeByPlayer[player] = now

	local damage = MiningRules.damageForLevel(PickAxeData.DAMAGE_BY_LEVEL, ToolManager:getPickAxeLevel(player))
	local isBroken, remainingHp = MineManager:applyDamage(depth, height, width, damage)
	if isBroken then
		NetManager:notifyAllClients(NetEventNames.NOTIFY_ROCK_BROKEN, {
			depth = depth,
			height = height,
			width = width,
			rock = rock,
			breakerUserId = player.UserId,
		})
	else
		NetManager:notifyAllClients(NetEventNames.NOTIFY_ROCK_DAMAGED, {
			depth = depth,
			height = height,
			width = width,
			remainingHp = remainingHp,
			maxHp = definition.hp,
		})
	end
end

function MiningManager:getNetHandlers()
	return {
		[NetEventNames.TRY_HIT_ROCK] = {
			shape = TRY_HIT_ROCK_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleHit(player, payload.depth, payload.height, payload.width)
			end,
		},
	}
end

function MiningManager:onPlayerRemoved(player: Player)
	self.lastHitTimeByPlayer[player] = nil
end

function MiningManager:init()
	-- the client swings on its own clock and aims within reach; both numbers
	-- come from here so the data has one home
	SplendidReplicationManager:setGameMetadata(Attributes.PICK_AXE_HIT_INTERVAL_SEC, PickAxeData.HIT_INTERVAL_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.PICK_AXE_REACH_STUDS, PickAxeData.REACH_STUDS)
	GameController:registerPlaceManager(self)
end

function MiningManager.new(): MiningManager
	local self = setmetatable({}, MiningManager) :: MiningManager
	self.lastHitTimeByPlayer = {}
	return self
end

return MiningManager.new()
