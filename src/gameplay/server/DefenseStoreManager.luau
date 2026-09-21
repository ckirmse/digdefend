--!strict

-- The Defense Store (GDD "Buying Traps"), M26: one stand per Trap kind in
-- the camp's DefenseStore model, each with a ProximityPrompt the server
-- hears directly (never a client message), exactly like the Mining
-- Supplies Store. A trigger is a purchase: the Camp Level line, the
-- carried-kinds limit, and the Iron are checked here, Iron Bars are spent,
-- and PlacementManager takes the Trap into the buyer's inventory. The
-- prices and requirements travel to the clients inside the defense
-- catalogue PlacementManager publishes, so every client draws its own stands.
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlacementRules = require("@game/ReplicatedStorage/Shared/PlacementRules")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local TrapsData = require("@game/ServerScriptService/GameData/Defenses/Traps")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local MapManager = require(script.Parent.MapManager)
local PlacementManager = require(script.Parent.PlacementManager)
local RefineryManager = require(script.Parent.RefineryManager)

local DefenseStoreManager = {}
DefenseStoreManager.__index = DefenseStoreManager

export type DefenseStoreManager = typeof(setmetatable(
	{} :: {
		promptConnections: { RBXScriptConnection },
	},
	DefenseStoreManager
))

local FEEDBACK_NOT_ENOUGH_IRON = "You don't have enough Iron Bars"
local FEEDBACK_KIND_LIMIT_FORMAT = "You can only carry %d kinds of Trap"

function DefenseStoreManager:buy(player: Player, kind: number)
	if not GameController:isPlayerReady(player) then
		return
	end
	local trap = TrapsData.BY_KIND[kind]
	if not trap then
		warn(`DefenseStoreManager: no GameData/Defenses/Traps entry for trap {kind}`)
		return
	end
	if RefineryManager:getCampLevel() < trap.REQUIRED_CAMP_LEVEL then
		PlayerFeedbackManager:give(player, string.format(StoreRules.LOCKED_FORMAT, trap.REQUIRED_CAMP_LEVEL))
		return
	end
	if not PlacementRules.canCarryTrap(PlacementManager:getTrapCounts(player), kind, TrapsData.MAX_TRAP_KINDS_CARRIED) then
		PlayerFeedbackManager:give(player, string.format(FEEDBACK_KIND_LIMIT_FORMAT, TrapsData.MAX_TRAP_KINDS_CARRIED))
		return
	end
	local price = trap.PRICE_IRON
	if not PlacementRules.canAfford(RefineryManager:getIronBars(player), price) or not RefineryManager:spendIronBars(player, price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	PlacementManager:addTrap(player, kind, 1)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_TRAP_PURCHASED, {
		kind = kind,
		price = price,
	})
	print(`[DefenseStoreManager] {player.Name} bought a {Enums.getPublicName(Enums.TrapKind, kind)} for {price} Iron`)
end

function DefenseStoreManager:bindStand(store: Instance, kind: number)
	local standName = StoreRules.standNameFromKey(Enums.getName(Enums.TrapKind, kind) or "?")
	local stand = store:FindFirstChild(standName)
	local base = if stand then stand:FindFirstChild(Constants.STAND_BASE_PART) else nil
	if not base or not base:IsA("BasePart") then
		warn(`DefenseStoreManager: {store:GetFullName()} has no {standName}.{Constants.STAND_BASE_PART}; that Trap cannot be bought`)
		return
	end
	-- the prompt is created here so a stand authored in Studio needs only its
	-- Base and ItemSpawn
	local prompt = base:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = base
	end
	local livePrompt = prompt :: ProximityPrompt
	livePrompt.ActionText = TrapsData.BUY_PROMPT_ACTION_TEXT
	livePrompt.ObjectText = Enums.getPublicName(Enums.TrapKind, kind) or ""
	livePrompt.HoldDuration = TrapsData.BUY_PROMPT_HOLD_SEC
	livePrompt.MaxActivationDistance = TrapsData.BUY_PROMPT_MAX_DISTANCE_STUDS
	livePrompt.RequiresLineOfSight = false
	livePrompt.Enabled = true
	table.insert(
		self.promptConnections,
		livePrompt.Triggered:Connect(
			function(player: Player)
				self:buy(player, kind)
			end
		)
	)
end

-- binds the loaded camp's stands; the previous camp's connections die with
-- its instances but are dropped here so a restart never hears two prompts
function DefenseStoreManager:bindStands()
	for _, connection in self.promptConnections do
		connection:Disconnect()
	end
	self.promptConnections = {}
	local camp = MapManager:getCamp()
	local store = if camp then camp:FindFirstChild(Constants.CAMP_DEFENSE_STORE_MODEL) else nil
	if not store then
		warn("DefenseStoreManager: the loaded camp has no DefenseStore; no Traps can be bought")
		return
	end
	for _, kind in Enums.getAllValues(Enums.TrapKind) do
		self:bindStand(store, kind)
	end
end

function DefenseStoreManager:onRunStarted()
	self:bindStands()
end

function DefenseStoreManager:init()
end

function DefenseStoreManager.new(): DefenseStoreManager
	local self = setmetatable({}, DefenseStoreManager) :: DefenseStoreManager
	self.promptConnections = {}
	return self
end

return DefenseStoreManager.new()
