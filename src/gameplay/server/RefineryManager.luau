--!strict

-- The Refinery (GDD "Refining Ore", "Resources"): the camp's proximity prompt
-- that turns a player's whole backpack into Iron Bars and Gold Bars (private
-- balances), Diamonds (the shared Camp Level pool), and Uranium (the shared
-- rescue count). Run state lives in Lua here; the private balances are
-- CurrentPlayer attributes and the shared progress is GameMetadata, so every
-- client reads the same numbers. Refining is a ProximityPrompt trigger the
-- server hears directly, never a client message, so there is nothing to
-- validate beyond the player's lifecycle.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local RefineryRules = require("@game/ReplicatedStorage/Shared/RefineryRules")
local PartyScalingData = require("@game/ServerScriptService/GameData/Control/PartyScaling")
local LevelData = require("@game/ServerScriptService/GameData/Camp/Level")
local RefineryData = require("@game/ServerScriptService/GameData/Refinery/Refinery")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local BackpackManager = require(script.Parent.BackpackManager)
local MapManager = require(script.Parent.MapManager)
local MineManager = require(script.Parent.MineManager)

local RefineryManager = {}
RefineryManager.__index = RefineryManager

type Balances = {
	ironBars: number,
	goldBars: number,
}

export type RefineryManager = typeof(setmetatable(
	{} :: {
		balancesByPlayer: { [Player]: Balances },
		campLevel: number,
		diamondPool: number,
		uraniumTotal: number,
		isBusy: boolean,
		prompt: ProximityPrompt?,
		promptConnection: RBXScriptConnection?,
	},
	RefineryManager
))

local DEFAULT_CAMP_LEVEL = 1

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

function RefineryManager:getCampLevel(): number
	return self.campLevel
end

function RefineryManager:getUraniumTotal(): number
	return self.uraniumTotal
end

-- the mine's solo target scaled by the current crew (dawn sampling is M28)
function RefineryManager:getUraniumTarget(): number
	local definition = MineManager:getDefinition()
	local baseTarget = if definition then definition.uraniumTarget else 0
	local playerCount = #GameController:getReadyPlayers()
	return RefineryRules.uraniumTarget(baseTarget, playerCount, PartyScalingData.URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT)
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
	SplendidReplicationManager:setGameMetadata(Attributes.CAMP_LEVEL, self.campLevel)
	SplendidReplicationManager:setGameMetadata(Attributes.CAMP_DIAMONDS, self.diamondPool)
	SplendidReplicationManager:setGameMetadata(Attributes.CAMP_DIAMONDS_REQUIRED, RefineryRules.diamondsRequired(LevelData.DIAMONDS_REQUIRED_BY_LEVEL, self.campLevel) or 0)
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
	end
	local diamonds = refined[Enums.RefinedResource.DIAMOND] or 0
	if diamonds > 0 then
		local level, pool, gained = RefineryRules.applyDiamonds(self.campLevel, self.diamondPool, diamonds, LevelData.DIAMONDS_REQUIRED_BY_LEVEL)
		self.campLevel = level
		self.diamondPool = pool
		if gained > 0 then
			-- store upgrade tiers unlock on this at M22
			print(`[RefineryManager] camp level {level}`)
		end
	end
	self.uraniumTotal += refined[Enums.RefinedResource.URANIUM] or 0
	self:replicateShared()
end

function RefineryManager:setPromptEnabled(isEnabled: boolean)
	local prompt = self.prompt
	if prompt then
		prompt.Enabled = isEnabled
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
	self:setPromptEnabled(false)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_REFINE_STARTED, {
		ore = toEntries(ore),
		durationSec = RefineryData.REFINE_DURATION_SEC,
	})
	task.delay(
		RefineryData.REFINE_DURATION_SEC,
		function()
			self.isBusy = false
			self:setPromptEnabled(true)
			self:credit(player, refined)
			if player.Parent == Players then
				NetManager:notifyClient(player, NetEventNames.NOTIFY_REFINE_COMPLETED, {
					refined = toEntries(refined),
				})
			end
		end
	)
end

-- binds the loaded camp's prompt; the previous camp's connection dies with
-- its instance but is dropped here so a restart never hears two prompts
function RefineryManager:bindPrompt()
	local previous = self.promptConnection
	if previous then
		previous:Disconnect()
		self.promptConnection = nil
	end
	self.prompt = nil
	local camp = MapManager:getCamp()
	local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
	local promptPart = if refinery then refinery:FindFirstChild(Constants.REFINERY_PROMPT_PART) else nil
	local prompt = if promptPart then promptPart:FindFirstChildWhichIsA("ProximityPrompt") else nil
	if not prompt then
		warn("RefineryManager: the loaded camp has no Refinery prompt; refining is unavailable")
		return
	end
	prompt.ActionText = RefineryData.PROMPT_ACTION_TEXT
	prompt.ObjectText = RefineryData.PROMPT_OBJECT_TEXT
	prompt.MaxActivationDistance = RefineryData.PROMPT_MAX_DISTANCE_STUDS
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Enabled = not self.isBusy
	self.prompt = prompt
	self.promptConnection = prompt.Triggered:Connect(
		function(player: Player)
			self:refine(player)
		end
	)
end

-- a run (or a dev-tool restart) starts the shared progress over
function RefineryManager:onRunStarted()
	self.campLevel = DEFAULT_CAMP_LEVEL
	self.diamondPool = 0
	self.uraniumTotal = 0
	self:bindPrompt()
	self:replicateShared()
end

-- dev tool: clear every balance and the shared progress
function RefineryManager:resetProgress()
	for player, balances in self.balancesByPlayer do
		balances.ironBars = 0
		balances.goldBars = 0
		self:replicatePlayer(player)
	end
	self.campLevel = DEFAULT_CAMP_LEVEL
	self.diamondPool = 0
	self.uraniumTotal = 0
	self:replicateShared()
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
	GameController:registerPlaceManager(self)
end

function RefineryManager.new(): RefineryManager
	local self = setmetatable({}, RefineryManager) :: RefineryManager
	self.balancesByPlayer = {}
	self.campLevel = DEFAULT_CAMP_LEVEL
	self.diamondPool = 0
	self.uraniumTotal = 0
	self.isBusy = false
	self.prompt = nil
	self.promptConnection = nil
	return self
end

return RefineryManager.new()
