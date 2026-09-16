--!strict

-- The Mining Supplies Store (GDD "Mining Supplies Store"): one stand per
-- item in the camp's MiningStore model, each with a ProximityPrompt the
-- server hears directly (never a client message). A trigger is a purchase
-- request: the offer is worked out here from the catalogue, the buyer's
-- level on that track, and the crew's Camp Level; Gold Bars are spent and
-- the owning manager raises the level or hands over the consumables. The
-- catalogue itself is published once as GameMetadata JSON so every client
-- draws its own stands (what the next level is differs per player).
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local LevelData = require("@game/ServerScriptService/GameData/Camp/Level")
local MiningSuppliesData = require("@game/ServerScriptService/GameData/Store/MiningSupplies")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local BackpackManager = require(script.Parent.BackpackManager)
local BootsManager = require(script.Parent.BootsManager)
local JetPackManager = require(script.Parent.JetPackManager)
local MapManager = require(script.Parent.MapManager)
local RefineryManager = require(script.Parent.RefineryManager)
local ToolManager = require(script.Parent.ToolManager)

local MiningStoreManager = {}
MiningStoreManager.__index = MiningStoreManager

export type MiningStoreManager = typeof(setmetatable(
	{} :: {
		catalog: StoreRules.Catalog,
		promptConnections: { RBXScriptConnection },
	},
	MiningStoreManager
))

local FEEDBACK_MAXED = "Already maxed out"
local FEEDBACK_NOT_ENOUGH_GOLD = "Not enough Gold"

function MiningStoreManager:getCatalog(): StoreRules.Catalog
	return self.catalog
end

function MiningStoreManager:getLevel(player: Player, item: number): number
	if item == Enums.StoreItem.PICK_AXE then
		return ToolManager:getPickAxeLevel(player)
	elseif item == Enums.StoreItem.BOOTS then
		return BootsManager:getLevel(player)
	elseif item == Enums.StoreItem.BACKPACK then
		return BackpackManager:getLevel(player)
	elseif item == Enums.StoreItem.JET_PACK then
		return JetPackManager:getLevel(player)
	end
	return 1
end

function MiningStoreManager:applyUpgrade(player: Player, item: number, level: number)
	if item == Enums.StoreItem.PICK_AXE then
		ToolManager:setPickAxeLevel(player, level)
	elseif item == Enums.StoreItem.BOOTS then
		BootsManager:setLevel(player, level)
	elseif item == Enums.StoreItem.BACKPACK then
		BackpackManager:setLevel(player, level)
	elseif item == Enums.StoreItem.JET_PACK then
		JetPackManager:setLevel(player, level)
	end
end

function MiningStoreManager:buy(player: Player, item: number)
	if not GameController:isPlayerReady(player) then
		return
	end
	local offer = StoreRules.getOffer(self.catalog, item, self:getLevel(player, item), RefineryManager:getCampLevel())
	if not offer then
		warn(`MiningStoreManager: no catalogue entry for item {item}`)
		return
	end
	if offer.status == Enums.StoreOffer.MAXED then
		PlayerFeedbackManager:give(player, FEEDBACK_MAXED)
		return
	end
	if offer.status == Enums.StoreOffer.LOCKED then
		PlayerFeedbackManager:give(player, string.format(StoreRules.LOCKED_FORMAT, offer.requiredCampLevel or 0))
		return
	end
	local price = offer.price or 0
	if not StoreRules.canAfford(RefineryManager:getGoldBars(player), price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_GOLD)
		return
	end
	if not RefineryManager:spendGoldBars(player, price) then
		return
	end
	local consumable = self.catalog.consumables[item]
	if offer.level then
		self:applyUpgrade(player, item, offer.level)
	elseif consumable then
		ToolManager:addConsumable(player, consumable.tool, consumable.amount)
	end
	NetManager:notifyClient(player, NetEventNames.NOTIFY_STORE_PURCHASE, {
		item = item,
		price = price,
	})
	print(`[MiningStoreManager] {player.Name} bought {StoreRules.nameText(item, offer)} for {price} Gold`)
end

function MiningStoreManager:bindStand(store: Instance, item: number)
	local standName = StoreRules.standNameForItem(item) :: string
	local stand = store:FindFirstChild(standName)
	local base = if stand then stand:FindFirstChild(Constants.STAND_BASE_PART) else nil
	if not base or not base:IsA("BasePart") then
		warn(`MiningStoreManager: {store:GetFullName()} has no {standName}.{Constants.STAND_BASE_PART}; that item cannot be bought`)
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
	livePrompt.ActionText = MiningSuppliesData.PROMPT_ACTION_TEXT
	livePrompt.ObjectText = Enums.getPublicName(Enums.StoreItem, item) or ""
	livePrompt.HoldDuration = MiningSuppliesData.PROMPT_HOLD_SEC
	livePrompt.MaxActivationDistance = MiningSuppliesData.PROMPT_MAX_DISTANCE_STUDS
	livePrompt.RequiresLineOfSight = false
	livePrompt.Enabled = true
	table.insert(
		self.promptConnections,
		livePrompt.Triggered:Connect(
			function(player: Player)
				self:buy(player, item)
			end
		)
	)
end

-- binds the loaded camp's stands; the previous camp's connections die with
-- its instances but are dropped here so a restart never hears two prompts
function MiningStoreManager:bindStands()
	for _, connection in self.promptConnections do
		connection:Disconnect()
	end
	self.promptConnections = {}
	local camp = MapManager:getCamp()
	local store = if camp then camp:FindFirstChild(Constants.CAMP_MINING_STORE_MODEL) else nil
	if not store then
		warn("MiningStoreManager: the loaded camp has no MiningStore; nothing can be bought")
		return
	end
	for _, item in Enums.getAllValues(Enums.StoreItem) do
		self:bindStand(store, item)
	end
end

function MiningStoreManager:onRunStarted()
	self:bindStands()
end

function MiningStoreManager:init()
	-- prices from the store data, the Camp Level gate from the level data
	local upgrades: { [number]: StoreRules.UpgradeTrack } = {}
	for item, track in MiningSuppliesData.UPGRADES do
		upgrades[item] = {
			priceByLevel = track.priceByLevel,
			requiredCampLevelByLevel = LevelData.MINING_UPGRADE_REQUIRED_CAMP_LEVEL_BY_LEVEL,
		}
	end
	self.catalog = {
		upgrades = upgrades,
		consumables = MiningSuppliesData.CONSUMABLES,
	}
	SplendidReplicationManager:setGameMetadata(Attributes.STORE_CATALOG, StoreRules.encodeCatalog(self.catalog))
end

function MiningStoreManager.new(): MiningStoreManager
	local self = setmetatable({}, MiningStoreManager) :: MiningStoreManager
	self.catalog = { upgrades = {}, consumables = {} }
	self.promptConnections = {}
	return self
end

return MiningStoreManager.new()
