--!strict

-- The Refinery (GDD "Refining Ore", "Resources"): the camp machine that
-- turns a player's whole backpack into Iron Bars and Gold Bars (private
-- balances) and Uranium (the shared rescue count). Run state lives in Lua here; the private balances are
-- CurrentPlayer attributes and the shared progress is GameMetadata, so every
-- client reads the same numbers. Refining is automatic (decided 2026-10-01,
-- replacing the proximity prompt): every REFINE_POLL_SEC the server looks
-- for a Ready player standing within REFINE_RADIUS_STUDS of the Refinery
-- with ore in the backpack, so there is no client message to validate.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local RefineryRules = require("@game/ReplicatedStorage/Shared/RefineryRules")
local DifficultyData = require("@game/ServerScriptService/GameData/Control/Difficulty")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local RefineryData = require("@game/ServerScriptService/GameData/Refinery/Refinery")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local BackpackManager = require(script.Parent.BackpackManager)
local MapManager = require(script.Parent.MapManager)
local MineManager = require(script.Parent.MineManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunManager = require(script.Parent.RunManager)
local RunStatsManager = require(script.Parent.RunStatsManager)

local RefineryManager = {}
RefineryManager.__index = RefineryManager

type Balances = {
	ironBars: number,
	goldBars: number,
}

export type RefineryManager = typeof(setmetatable(
	{} :: {
		balancesByPlayer: { [Player]: Balances },
		uraniumTotal: number,
		isBusy: boolean,
		uraniumChangedHandlers: { () -> () },
		-- every payout, with what it paid (the run report, M34)
		creditedHandlers: { (player: Player, refined: { [number]: number }) -> () },
		-- every spend, with what it bought when the caller said (the run
		-- report, M34); resource is an Enums.RefinedResource
		spentHandlers: { (player: Player, resource: number, amount: number, reason: string?) -> () },
		-- the loaded camp's Refinery, flat, for the radius check; nil until a run
		refineryPosition: Vector3?,
		pollAccumulatorSec: number,
	},
	RefineryManager
))

local function toEntries(contents: { [number]: number }): { { resource: number, amount: number } }
	local entries = {}
	for resource, amount in contents do
		table.insert(entries, {
			resource = resource,
			amount = amount,
		})
	end
	return entries
end

function RefineryManager:getBalances(player: Player): Balances?
	return self.balancesByPlayer[player]
end

function RefineryManager:getGoldBars(player: Player): number
	local balances = self.balancesByPlayer[player]
	return if balances then balances.goldBars else 0
end

-- the Mining Supplies Store pays from here; false leaves the balance
-- untouched. reason names the purchase for the run report; a caller the
-- report already counts another way (repairs, placements) passes nothing
function RefineryManager:spendGoldBars(player: Player, amount: number, reason: string?): boolean
	local balances = self.balancesByPlayer[player]
	if not balances or amount < 0 or balances.goldBars < amount then
		return false
	end
	balances.goldBars -= amount
	self:replicatePlayer(player)
	self:fireSpent(player, Enums.RefinedResource.GOLD_BAR, amount, reason)
	return true
end

function RefineryManager:getIronBars(player: Player): number
	local balances = self.balancesByPlayer[player]
	return if balances then balances.ironBars else 0
end

-- structure repairs and the fortification upgrade pay from here
function RefineryManager:spendIronBars(player: Player, amount: number, reason: string?): boolean
	local balances = self.balancesByPlayer[player]
	if not balances or amount < 0 or balances.ironBars < amount then
		return false
	end
	balances.ironBars -= amount
	self:replicatePlayer(player)
	self:fireSpent(player, Enums.RefinedResource.IRON_BAR, amount, reason)
	return true
end

function RefineryManager:fireSpent(player: Player, resource: number, amount: number, reason: string?)
	if amount <= 0 then
		return
	end
	for _, handler in self.spentHandlers do
		handler(player, resource, amount, reason)
	end
end

function RefineryManager:addIronBars(player: Player, amount: number)
	local balances = self.balancesByPlayer[player]
	if not balances then
		return
	end
	balances.ironBars = math.max(balances.ironBars + amount, 0)
	self:replicatePlayer(player)
end

-- dev tools: grant Gold, so the store can be tested without a mining trip
function RefineryManager:addGoldBars(player: Player, amount: number)
	local balances = self.balancesByPlayer[player]
	if not balances then
		return
	end
	balances.goldBars = math.max(balances.goldBars + amount, 0)
	self:replicatePlayer(player)
end

function RefineryManager:getUraniumTotal(): number
	return self.uraniumTotal
end

-- the mine's solo target scaled by the current crew (dawn sampling is M28)
function RefineryManager:getUraniumTarget(): number
	local definition = MineManager:getDefinition()
	local baseTarget = if definition then definition.uraniumTarget else 0
	-- the crew size sampled at dawn (M28), never the live count
	local playerCount = RunCycleManager:getScalingCount()
	local difficulty = RunManager:getDifficulty()
	local difficultyMultiplier = if difficulty then DifficultyData.URANIUM_TARGET_MULTIPLIER[difficulty] else 1
	return RefineryRules.uraniumTarget(baseTarget, playerCount, PartyScalingData.URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT, difficultyMultiplier)
end

-- the rescue (M31) listens for the target being reached
function RefineryManager:subscribeCredited(handler: (player: Player, refined: { [number]: number }) -> ())
	table.insert(self.creditedHandlers, handler)
end

function RefineryManager:subscribeSpent(handler: (player: Player, resource: number, amount: number, reason: string?) -> ())
	table.insert(self.spentHandlers, handler)
end

function RefineryManager:subscribeUraniumChanged(handler: () -> ())
	table.insert(self.uraniumChangedHandlers, handler)
end

function RefineryManager:fireUraniumChanged()
	for _, handler in self.uraniumChangedHandlers do
		handler()
	end
end

-- dev tool: uranium refined out of thin air
function RefineryManager:addUranium(amount: number)
	self.uraniumTotal += math.max(0, math.floor(amount))
	self:replicateShared()
	self:fireUraniumChanged()
end

function RefineryManager:replicatePlayer(player: Player)
	local balances = self.balancesByPlayer[player]
	if not balances then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.BALANCE_IRON_BARS, balances.ironBars)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.BALANCE_GOLD_BARS, balances.goldBars)
end

function RefineryManager:replicateShared()
	SplendidReplicationManager:setGameMetadata(Attributes.URANIUM_TOTAL, self.uraniumTotal)
	SplendidReplicationManager:setGameMetadata(Attributes.URANIUM_TARGET, self:getUraniumTarget())
end

-- pays out one refine; the player may have left during the grind, in which
-- case the shared resources still count and the private ones are lost
function RefineryManager:credit(player: Player, refined: { [number]: number })
	local balances = self.balancesByPlayer[player]
	if balances then
		balances.ironBars += refined[Enums.RefinedResource.IRON_BAR] or 0
		balances.goldBars += refined[Enums.RefinedResource.GOLD_BAR] or 0
		self:replicatePlayer(player)
		RunStatsManager:addRefined(player, refined[Enums.RefinedResource.IRON_BAR] or 0, refined[Enums.RefinedResource.GOLD_BAR] or 0, refined[Enums.RefinedResource.URANIUM] or 0)
	end
	local uranium = refined[Enums.RefinedResource.URANIUM] or 0
	self.uraniumTotal += uranium
	self:replicateShared()
	if uranium > 0 then
		self:fireUraniumChanged()
	end
	for _, handler in self.creditedHandlers do
		handler(player, refined)
	end
end

function RefineryManager:refine(player: Player)
	if not GameController:isPlayerReady(player) then
		return
	end
	if self.isBusy then
		PlayerFeedbackManager:give(player, "The Refinery is busy")
		return
	end
	local contents = BackpackManager:getContents(player)
	if not contents or next(contents) == nil then
		PlayerFeedbackManager:give(player, "Nothing to refine")
		return
	end
	local ore = BackpackManager:takeAll(player)
	local refined = RefineryRules.convert(ore, RefineryData.RATE_BY_RAW)
	self.isBusy = true
	-- to everyone, naming the player: the crew sees the ore go in and the
	-- bars come out; only that player's own client plays the sounds and
	-- moves a HUD (2026-10-05)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_REFINE_STARTED, {
		userId = player.UserId,
		ore = toEntries(ore),
		durationSec = RefineryData.REFINE_DURATION_SEC,
	})
	task.delay(
		RefineryData.REFINE_DURATION_SEC,
		function()
			self.isBusy = false
			self:credit(player, refined)
			if player.Parent == Players then
				NetManager:notifyAllClients(NetEventNames.NOTIFY_REFINE_COMPLETED, {
					userId = player.UserId,
					refined = toEntries(refined),
				})
			end
		end
	)
end

-- whether a player stands inside the refining ring, across the ground
function RefineryManager:isPlayerAtRefinery(player: Player): boolean
	local position = self.refineryPosition
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not position or not root or not root:IsA("BasePart") then
		return false
	end
	local offset = root.Position - position
	return Vector2.new(offset.X, offset.Z).Magnitude <= RefineryData.REFINE_RADIUS_STUDS
end

-- the automatic refine: the first Ready player found inside the ring with
-- ore in the backpack is refined; the machine is busy for the grind, and
-- anyone else inside waits for the next poll
function RefineryManager:pollRefinery()
	if self.isBusy or not self.refineryPosition then
		return
	end
	for _, player in Players:GetPlayers() do
		if not GameController:isPlayerReady(player) or not self:isPlayerAtRefinery(player) then
			continue
		end
		local contents = BackpackManager:getContents(player)
		if contents and next(contents) ~= nil then
			self:refine(player)
			return
		end
	end
end

-- reads where the loaded camp's Refinery stands; the ring is centred on
-- its bounding box, so the authored Prompt part is no longer needed
function RefineryManager:bindRefinery()
	self.refineryPosition = nil
	local camp = MapManager:getCamp()
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	if not refinery or not refinery:IsA("Model") then
		warn("RefineryManager: the loaded camp has no Refinery model; refining is unavailable")
		return
	end
	local boundsCFrame = refinery:GetBoundingBox()
	self.refineryPosition = boundsCFrame.Position
end

-- a run (or a dev-tool restart) starts the shared progress over
function RefineryManager:onRunStarted()
	self.uraniumTotal = 0
	self:bindRefinery()
	self:replicateShared()
end

-- dev tool: clear every balance and the shared progress
function RefineryManager:resetProgress()
	for player, balances in self.balancesByPlayer do
		balances.ironBars = 0
		balances.goldBars = 0
		self:replicatePlayer(player)
	end
	self.uraniumTotal = 0
	self:replicateShared()
	self:fireUraniumChanged()
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state survives
function RefineryManager:onPlayerReady(player: Player)
	if not self.balancesByPlayer[player] then
		self.balancesByPlayer[player] = {
			ironBars = 0,
			goldBars = 0,
		}
	end
	self:replicatePlayer(player)
	-- the crew size changed, so the uranium target may have
	self:replicateShared()
end

function RefineryManager:onPlayerRemoved(player: Player)
	self.balancesByPlayer[player] = nil
	self:replicateShared()
end

function RefineryManager:init()
	SplendidReplicationManager:setGameMetadata(Attributes.REFINE_DURATION_SEC, RefineryData.REFINE_DURATION_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.REFINE_RADIUS_STUDS, RefineryData.REFINE_RADIUS_STUDS)
	GameController:registerPlaceManager(self)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self.pollAccumulatorSec += deltaSec
			if self.pollAccumulatorSec < RefineryData.REFINE_POLL_SEC then
				return
			end
			self.pollAccumulatorSec = 0
			self:pollRefinery()
		end
	)
	-- a smaller crew means a smaller target: republish it and let the rescue
	-- re-check the radio, since the total may already meet the new target
	RunCycleManager:subscribeScalingCountChanged(
		function()
			self:replicateShared()
			self:fireUraniumChanged()
		end
	)
end

function RefineryManager.new(): RefineryManager
	local self = setmetatable({}, RefineryManager) :: RefineryManager
	self.balancesByPlayer = {}
	self.uraniumTotal = 0
	self.isBusy = false
	self.uraniumChangedHandlers = {}
	self.creditedHandlers = {}
	self.spentHandlers = {}
	self.refineryPosition = nil
	self.pollAccumulatorSec = 0
	return self
end

return RefineryManager.new()
