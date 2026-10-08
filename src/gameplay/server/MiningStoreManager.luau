--!strict

-- The Mining Supplies Store (GDD "Mining Supplies Store"): one stand per
-- item in the camp's MiningStore model, each with a ProximityPrompt the
-- server hears directly (never a client message). A trigger is a purchase
-- request: the offer is worked out here from the catalogue and the buyer's
-- level on that track; Gold Bars are spent and
-- the owning manager raises the level or hands over the consumables. The
-- catalogue itself is published once as GameMetadata JSON so every client
-- draws its own stands (what the next level is differs per player).
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local MiningSuppliesData = require("@game/ServerScriptService/GameData/Store/MiningSupplies")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local BackpackManager = require(script.Parent.BackpackManager)
local BootsManager = require(script.Parent.BootsManager)
local CompassManager = require(script.Parent.CompassManager)
local GeigerCounterManager = require(script.Parent.GeigerCounterManager)
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
local FEEDBACK_OWNED = "Already owned"
local FEEDBACK_GEIGER_COUNTER_BOUGHT = "The Geiger Counter is visible when mining"
-- level 1 is not owning one, so the buy that reaches level 2 is the first
local GEIGER_COUNTER_FIRST_LEVEL = 2
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
	elseif item == Enums.StoreItem.COMPASS then
		return CompassManager:getLevel(player)
	elseif item == Enums.StoreItem.GEIGER_COUNTER then
		return GeigerCounterManager:getLevel(player)
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
	elseif item == Enums.StoreItem.COMPASS then
		CompassManager:setLevel(player, level)
	elseif item == Enums.StoreItem.GEIGER_COUNTER then
		GeigerCounterManager:setLevel(player, level)
	end
end

function MiningStoreManager:buy(player: Player, item: number)
	if not GameController:isPlayerReady(player) then
		return
	end
	local offer = StoreRules.getOffer(self.catalog, item, self:getLevel(player, item))
	if not offer then
		warn(`MiningStoreManager: no catalogue entry for item {item}`)
		return
	end
	if offer.status == Enums.StoreOffer.MAXED then
		PlayerFeedbackManager:give(player, if offer.isSinglePurchase then FEEDBACK_OWNED else FEEDBACK_MAXED)
		return
	end
	local price = offer.price or 0
	if not StoreRules.canAfford(RefineryManager:getGoldBars(player), price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_GOLD)
		return
	end
	if not RefineryManager:spendGoldBars(player, price, StoreRules.nameText(item, offer)) then
		return
	end
	local consumable = self.catalog.consumables[item]
	if offer.level then
		self:applyUpgrade(player, item, offer.level)
		-- the dial only shows with the pick axe out, so a first-time buyer
		-- standing in the store would otherwise see nothing happen
		if item == Enums.StoreItem.GEIGER_COUNTER and offer.level == GEIGER_COUNTER_FIRST_LEVEL then
			PlayerFeedbackManager:give(player, FEEDBACK_GEIGER_COUNTER_BOUGHT)
		end
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
		-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person (2026-09-29)
		prompt.ClickablePrompt = false
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
	local stands = if store then store:FindFirstChild(Constants.MINING_STORE_STANDS_FOLDER) else nil
	if not stands then
		warn(`MiningStoreManager: the loaded camp has no {Constants.CAMP_MINING_STORE_MODEL}.{Constants.MINING_STORE_STANDS_FOLDER}; nothing can be bought`)
		return
	end
	for _, item in Enums.getAllValues(Enums.StoreItem) do
		self:bindStand(stands, item)
	end
end

function MiningStoreManager:onRunStarted()
	self:bindStands()
end

function MiningStoreManager:init()
	-- prices from the store data
	local upgrades: { [number]: StoreRules.UpgradeTrack } = {}
	for item, track in MiningSuppliesData.UPGRADES do
		upgrades[item] = {
			priceByLevel = track.priceByLevel,
			startsUnowned = (track :: any).startsUnowned == true,
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
