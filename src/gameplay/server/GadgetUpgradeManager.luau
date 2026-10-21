--!strict

-- Gadget upgrades (M67): one level per player per run for the class's
-- gadget, bought with Iron at the Post & Gadget Upgrades table like a
-- post upgrade and reset with the run. The gadget managers read the level
-- (AutoTurretManager picks its stats row by it) and are told when it
-- rises so a standing gadget can grow in place. Only a gadget whose
-- GameData carries a price list is upgradable, and only a gadget that
-- must keep pace with the waves or the mine gets one (designer,
-- 2026-10-21: the turret's damage and the charge's burst do, the flare's
-- pull does not); the price lists are published once as the
-- GadgetUpgradeCatalog GameMetadata JSON for the menu.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GadgetRules = require("@game/ReplicatedStorage/Shared/GadgetRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local AutoTurretData = require("@game/ServerScriptService/GameData/Gadgets/AutoTurret")
local RemoteChargeData = require("@game/ServerScriptService/GameData/Gadgets/RemoteCharge")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local RefineryManager = require(script.Parent.RefineryManager)

local GadgetUpgradeManager = {}
GadgetUpgradeManager.__index = GadgetUpgradeManager

export type UpgradedHandler = (player: Player, level: number) -> ()

export type GadgetUpgradeManager = typeof(setmetatable(
	{} :: {
		catalog: GadgetRules.Catalog,
		levelByPlayer: { [Player]: number },
		upgradedHandlers: { UpgradedHandler },
	},
	GadgetUpgradeManager
))

local TRY_UPGRADE_GADGET_SHAPE = {}
local FEEDBACK_NO_UPGRADE = "This gadget has no upgrades"
local FEEDBACK_MAXED = "Already at the maximum"
local FEEDBACK_NOT_ENOUGH_IRON = "Not enough Iron"

function GadgetUpgradeManager:getCatalog(): GadgetRules.Catalog
	return self.catalog
end

function GadgetUpgradeManager:getLevel(player: Player): number
	return self.levelByPlayer[player] or GadgetRules.STARTING_LEVEL
end

-- told when a player's gadget level rises (AutoTurretManager grows a standing turret)
function GadgetUpgradeManager:subscribeUpgraded(handler: UpgradedHandler)
	table.insert(self.upgradedHandlers, handler)
end

function GadgetUpgradeManager:replicatePlayer(player: Player)
	if player.Parent then
		SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.GADGET_LEVEL, self:getLevel(player))
	end
end

function GadgetUpgradeManager:setLevel(player: Player, level: number)
	self.levelByPlayer[player] = level
	self:replicatePlayer(player)
end

-- one buy: the class's gadget, the next level, the Iron through the Refinery
function GadgetUpgradeManager:upgrade(player: Player)
	if not GameController:isPlayerReady(player) then
		return
	end
	local gadgetKind = CharacterManager:getGadgetKind(player)
	if not GadgetRules.isUpgradable(self.catalog, gadgetKind) then
		PlayerFeedbackManager:give(player, FEEDBACK_NO_UPGRADE)
		return
	end
	local offer = GadgetRules.getUpgradeOffer(self.catalog, gadgetKind, self:getLevel(player))
	if offer.status == Enums.StoreOffer.MAXED then
		PlayerFeedbackManager:give(player, FEEDBACK_MAXED)
		return
	end
	local price = offer.price or 0
	local level = offer.level or GadgetRules.STARTING_LEVEL
	if not GadgetRules.canAfford(RefineryManager:getIronBars(player), price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_IRON)
		return
	end
	local gadgetName = Enums.getPublicName(Enums.GadgetKind, gadgetKind) or "gadget"
	if not RefineryManager:spendIronBars(player, price, `gadget {gadgetName} {level}`) then
		return
	end
	self:setLevel(player, level)
	for _, handler in self.upgradedHandlers do
		handler(player, level)
	end
	NetManager:notifyClient(player, NetEventNames.NOTIFY_GADGET_UPGRADED, {
		level = level,
		price = price,
	})
	print(`[GadgetUpgradeManager] {player.Name} upgraded {gadgetName} to {level} for {price} Iron`)
end

function GadgetUpgradeManager:getNetHandlers()
	return {
		[NetEventNames.TRY_UPGRADE_GADGET] = {
			shape = TRY_UPGRADE_GADGET_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				local isValid = Validate.isTableShape(payload, TRY_UPGRADE_GADGET_SHAPE)
				if isValid then
					self:upgrade(player)
				end
			end,
		},
	}
end

-- a new run starts every gadget over at level 1
function GadgetUpgradeManager:onRunStarted()
	for player in self.levelByPlayer do
		self:setLevel(player, GadgetRules.STARTING_LEVEL)
	end
end

function GadgetUpgradeManager:onPlayerReady(player: Player)
	self:replicatePlayer(player)
end

function GadgetUpgradeManager:onPlayerRemoved(player: Player)
	self.levelByPlayer[player] = nil
end

function GadgetUpgradeManager:init()
	-- every scaling gadget registers its price list here as it is built
	self.catalog = {
		pricesByKind = {
			[Enums.GadgetKind.AUTO_TURRET] = AutoTurretData.UPGRADE_PRICE_IRON_BY_LEVEL,
			[Enums.GadgetKind.REMOTE_CHARGE] = RemoteChargeData.UPGRADE_PRICE_IRON_BY_LEVEL,
		},
	}
	SplendidReplicationManager:setGameMetadata(Attributes.GADGET_UPGRADE_CATALOG, GadgetRules.encodeCatalog(self.catalog))
	GameController:registerPlaceManager(self)
	-- a dev-tool class change swaps the gadget, and the levels bought were the old one's
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if self.levelByPlayer[player] then
				self:setLevel(player, GadgetRules.STARTING_LEVEL)
			end
		end
	)
end

function GadgetUpgradeManager.new(): GadgetUpgradeManager
	local self = setmetatable({}, GadgetUpgradeManager) :: GadgetUpgradeManager
	self.catalog = { pricesByKind = {} }
	self.levelByPlayer = {}
	self.upgradedHandlers = {}
	return self
end

return GadgetUpgradeManager.new()
