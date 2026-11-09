--!strict

-- Server side of Mining Mode (GDD "Mining Rock"): every swing arrives as
-- TryHitRock with a grid cell and is checked here before MineManager takes
-- damage: pick axe equipped, a diggable block, the player close enough, and
-- not faster than the pick axe swings. Results go to every client so the
-- crack state and the removal are seen by all.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BackpackRules = require("@game/ReplicatedStorage/Shared/BackpackRules")
local ClassRules = require("@game/ReplicatedStorage/Shared/ClassRules")
local RockRules = require("@game/ReplicatedStorage/Shared/RockRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineGenerator = require("@game/ReplicatedStorage/Shared/MineGenerator")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local PickAxeData = require("@game/ServerScriptService/GameData/Mining/PickAxe")
local RockDefinitionsData = require("@game/ServerScriptService/GameData/Rocks/RockDefinitions")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local BackpackManager = require(script.Parent.BackpackManager)
local ClassManager = require(script.Parent.Parent.Server.ClassManager)
local MineManager = require(script.Parent.MineManager)
local OrePickupManager = require(script.Parent.OrePickupManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local SkillManager = require(script.Parent.SkillManager)
local ToolManager = require(script.Parent.ToolManager)

local MiningManager = {}
MiningManager.__index = MiningManager

export type MiningManager = typeof(setmetatable(
	{} :: {
		-- the Clean Break's roll (M56)
		random: Random,
		lastHitTimeByPlayer: { [Player]: number },
		-- every swing that landed: the rock it hit and whether it broke
		-- (the run report, M34)
		hitHandlers: { (player: Player, depth: number, height: number, width: number, rock: number, isBroken: boolean) -> () },
		-- offered every validated swing before it lands; true takes it (M68)
		hitInterceptor: ((player: Player, depth: number, height: number, width: number) -> boolean)?,
	},
	MiningManager
))

local TRY_HIT_ROCK_SHAPE = {
	depth = "nonnegativeInteger",
	height = "nonnegativeInteger",
	width = "nonnegativeInteger",
}

function MiningManager:subscribeHit(handler: (player: Player, depth: number, height: number, width: number, rock: number, isBroken: boolean) -> ())
	table.insert(self.hitHandlers, handler)
end

-- the one hook before a swing lands (M68, the Blockface): a validated swing at
-- a cell is offered to the interceptor first, and a true answer means it
-- was taken and the pick's own damage is never applied
function MiningManager:setHitInterceptor(interceptor: ((player: Player, depth: number, height: number, width: number) -> boolean)?)
	self.hitInterceptor = interceptor
end

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
		-- bedrock: nothing to do, and no reason to warn
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
	-- the class's mining speed shortens the cooldown as it does the
	-- client's swing (2026-10-22)
	if not MiningRules.canHit(self.lastHitTimeByPlayer[player], now, PickAxeData.HIT_COOLDOWN_SEC / ClassManager:getModifier(player, Enums.ClassModifier.MINING_SPEED)) then
		return
	end
	self.lastHitTimeByPlayer[player] = now

	-- a swing at a Blockface's block is the Blockface's to answer (M68): the
	-- interceptor breaks the block itself and announces it, whatever the
	-- pick's damage
	local interceptor = self.hitInterceptor
	if interceptor and interceptor(player, depth, height, width) then
		return
	end

	-- the class's mining power scales the pick axe's rung (M64)
	local damage = ClassRules.scaleAmount(
		MiningRules.damageForLevel(PickAxeData.DAMAGE_BY_LEVEL, ToolManager:getPickAxeLevel(player)),
		ClassManager:getModifier(player, Enums.ClassModifier.MINING_POWER)
	)
	-- the skills on a swing (M56): the Hardened Pick hits uranium harder,
	-- the Rich Seam's first swing at a whole gold rock is worth extra
	-- hits, and the Clean Break breaks the rock outright now and then
	if RockRules.isUraniumRock(rock) then
		damage *= SkillManager:multiplierFor(player, "HARDENED_PICK", "URANIUM_DAMAGE_MULTIPLIER")
	end
	if definition.resource == Enums.RawResource.GOLD_ORE and SkillManager:has(player, "RICH_SEAM") and MineManager:getDamageAt(depth, height, width) == 0 then
		damage += damage * SkillManager:param("RICH_SEAM", "GOLD_FIRST_HIT_BONUS_HITS", 0)
	end
	if SkillManager:has(player, "CLEAN_BREAK") and self.random:NextNumber() < SkillManager:param("CLEAN_BREAK", "ONE_SWING_BREAK_CHANCE", 0) then
		damage = definition.hp
	end
	local isBroken, remainingHp = MineManager:applyDamage(depth, height, width, damage)
	for _, handler in self.hitHandlers do
		handler(player, depth, height, width, rock, isBroken)
	end
	if isBroken then
		NetManager:notifyAllClients(NetEventNames.NOTIFY_ROCK_BROKEN, {
			depth = depth,
			height = height,
			width = width,
			rock = rock,
			breakerUserId = player.UserId,
		})
		-- the Mother Lode counts every rock, resource or not
		local isMotherLode = SkillManager:countBreak(player)
		self:awardOre(player, definition, blockCenter, isMotherLode)
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

-- the ore inside a broken resource rock goes to the breaker; what does not
-- fit lands on the ground (GDD "Collecting Ore"). Party size is the current
-- Ready count until M28 samples it at dawn.
function MiningManager:awardOre(player: Player, definition: any, blockCenter: Vector3, isMotherLode: boolean?)
	if definition.kind ~= Enums.RockKind.RESOURCE or not definition.resource or not definition.yield then
		return
	end
	-- the crew size sampled at dawn (M28), never the live count
	local playerCount = RunCycleManager:getScalingCount()
	local amount = BackpackRules.yieldForBreak(definition.yield, definition.resource, playerCount, PartyScalingData.ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT)
	-- the class's ore yield (the Prospector's 1.2, applied 2026-10-22),
	-- rounded so a block never pays a fraction
	local yieldScale: number = ClassManager:getModifier(player, Enums.ClassModifier.ORE_YIELD)
	amount = math.floor(amount * yieldScale + 0.5)
	if isMotherLode then
		amount *= SkillManager:param("MOTHER_LODE", "ORE_MULTIPLIER", 1)
	end
	local _, overflow = BackpackManager:add(player, definition.resource, amount, blockCenter)
	if overflow > 0 then
		OrePickupManager:drop(blockCenter, definition.resource, overflow)
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

-- the swing interval this player's class gives them, on CurrentPlayer so
-- their client swings at their pace; the GameMetadata copy is the base
function MiningManager:publishHitInterval(player: Player)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.PICK_AXE_HIT_INTERVAL_SEC, PickAxeData.HIT_INTERVAL_SEC / ClassManager:getModifier(player, Enums.ClassModifier.MINING_SPEED))
end

function MiningManager:onPlayerReady(player: Player)
	self:publishHitInterval(player)
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
	ClassManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if GameController:isPlayerReady(player) then
				self:publishHitInterval(player)
			end
		end
	)
	-- the Steady Swing lands or leaves (M56)
	ClassManager:subscribeSkillsChanged(
		function(player: Player)
			if GameController:isPlayerReady(player) then
				self:publishHitInterval(player)
			end
		end
	)
end

function MiningManager.new(): MiningManager
	local self = setmetatable({}, MiningManager) :: MiningManager
	self.lastHitTimeByPlayer = {}
	self.hitHandlers = {}
	self.random = Random.new()
	return self
end

return MiningManager.new()
