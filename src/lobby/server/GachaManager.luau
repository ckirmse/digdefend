--!strict

-- The class gacha (GDD "Class Unlock System", M70): the one loot box the
-- lobby rolls with Diamonds. The pool and the prices are GameData/Gacha;
-- what a draw turns into is pure GachaRules; the record of truth is
-- PlayerData's classProgress, keys, and ownedCosmetics, which this manager
-- is the one writer of. A roll is answered with NotifyGachaResult for the
-- reveal, and the balances reach the client through the SplendidGames
-- tree (replicateDiamonds, replicateGacha, and replicateClasses when a
-- skill slot opened, since the open count rides on every character).
--
-- A player PolicyService reports as restricted from paid random items
-- (Diamonds are bought with Robux, so the gacha counts) cannot roll: they
-- buy a class outright at DIRECT_CLASS_PRICE_DIAMONDS instead (decided
-- 2026-11-02). The policy is asked once at Ready and held here, so the
-- client's own reading of the flag is never what decides.
local PolicyService = game:GetService("PolicyService")

local CosmeticCatalogueData = require("@game/ServerScriptService/GameData/Cosmetics/Catalogue")
local ClassRosterData = require("@game/ServerScriptService/GameData/Classes/Roster")
local GachaData = require("@game/ServerScriptService/GameData/Gacha/Gacha")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CosmeticRules = require("@game/ReplicatedStorage/Shared/CosmeticRules")
local DailyStoreRules = require("@game/ReplicatedStorage/Shared/DailyStoreRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GachaRules = require("@game/ReplicatedStorage/Shared/GachaRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClassManager = require(script.Parent.Parent.Server.ClassManager)
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerData = require(script.Parent.Parent.Server.PlayerData)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local GachaManager = {}
GachaManager.__index = GachaManager

export type GachaManager = typeof(setmetatable(
	{} :: {
		pool: GachaRules.Pool,
		random: Random,
		-- the policy answer per Ready player. Until it has arrived
		-- (isPolicyKnownByPlayer) the player may neither open a crate nor
		-- shop in the rotating store: which of the two is theirs is not
		-- known yet, so both stay shut (2026-11-10; an unanswered player
		-- could roll before)
		isRestrictedByPlayer: { [Player]: boolean },
		isPolicyKnownByPlayer: { [Player]: boolean },
		-- the rotating Gear Store's current set; nil until first asked for
		dailyStore: DailyStoreRules.Store?,
	},
	GachaManager
))

local EMPTY_SHAPE = {}

-- one thing from the rotating store: a class card or a cosmetic
local BUY_STORE_ITEM_SHAPE = {
	classKind = { type = "enum", name = "ClassKind", optional = true },
	cosmeticId = { type = "string", optional = true },
}

local SET_KEYS_ARGS_SHAPE = {
	keys = "nonnegativeInteger",
}

local GRANT_CLASS_STEP_ARGS_SHAPE = {
	classKind = { type = "enum", name = "ClassKind" },
}

local SET_RESTRICTED_ARGS_SHAPE = {
	isRestricted = "boolean",
}

local ROLL_FORCED_ARGS_SHAPE = {
	prizeKey = "string",
}

GachaManager.ROLL_FREE_COMMAND = "rollGachaFree"
-- a free roll whose draw is the named prize (GachaRules.prizeKey), so a
-- tester can see any reveal on demand (2026-11-04)
GachaManager.ROLL_FORCED_COMMAND = "rollGachaForced"
GachaManager.SET_KEYS_COMMAND = "setKeys"
GachaManager.GRANT_CLASS_STEP_COMMAND = "grantClassStep"
GachaManager.SET_RESTRICTED_COMMAND = "setPaidRandomRestricted"
GachaManager.CLEAR_CLASS_PROGRESS_COMMAND = "clearClassProgress"
GachaManager.CLEAR_COSMETICS_COMMAND = "clearCosmetics"
GachaManager.RESET_CRATE_TUTORIAL_COMMAND = "resetCrateTutorial"
GachaManager.RESET_FREE_REROLLS_COMMAND = "resetFreeRerolls"
GachaManager.RESET_STORE_PURCHASES_COMMAND = "resetStorePurchases"

local FEEDBACK_ALREADY_PURCHASED = "You already bought that card today"
local FEEDBACK_POLICY_UNKNOWN = "The store is still loading. Try again in a moment"
-- PolicyService is asked again this often until it answers
local POLICY_RETRY_SEC = 5
local FEEDBACK_RESTRICTED = "Rolling is not available on this account"
local FEEDBACK_NOT_RESTRICTED = "Classes are rolled on this account"
local FEEDBACK_CLASS_OWNED = "You already own that class"
local FEEDBACK_CLASS_NOT_SOLD = "That class is not for sale"
local FEEDBACK_CLASS_NOT_OWNED = "You don't own that class"
local FEEDBACK_CLASS_MAXED = "That class is fully upgraded"
local FEEDBACK_COSMETIC_OWNED = "You already own that"
local FEEDBACK_COSMETIC_NOT_SOLD = "That is not for sale"
local FEEDBACK_NOT_TODAY = "That is not in the store today"
-- the republish runs this long after the set's change, so the clock is
-- safely past it
local DAILY_STORE_REFRESH_GRACE_SEC = 1

function GachaManager:getNetHandlers()
	return {
		[NetEventNames.TRY_ROLL_GACHA] = {
			shape = EMPTY_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:roll(player, false)
			end,
		},
		[NetEventNames.TRY_BUY_STORE_ITEM] = {
			shape = BUY_STORE_ITEM_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:buyStoreItem(player, payload.classKind, payload.cosmeticId)
			end,
		},
	}
end

function GachaManager:getConfig(): GachaRules.Config
	return {
		maxSkillSlots = GachaData.MAX_SKILL_SLOTS,
		keysPerKeysResult = GachaData.KEYS_PER_KEYS_RESULT,
		keysPerCompleteClass = GachaData.KEYS_PER_COMPLETE_CLASS,
		keysPerDuplicateCosmetic = GachaData.KEYS_PER_DUPLICATE_COSMETIC,
	}
end

-- every launch class, the Recruit included since 2026-11-05 (it is always
-- owned, so its card only ever opens a perk slot or pays Keys), every hat,
-- and every skin in the cosmetics catalogue (2026-11-04)
function GachaManager:buildPool(): GachaRules.Pool
	local excluded = table.clone(GachaData.EXCLUDED_KINDS)
	for _, classKind in ClassRosterData.POST_LAUNCH_KINDS do
		table.insert(excluded, classKind)
	end
	local cosmeticIds = {}
	for cosmeticId in CosmeticCatalogueData.BY_ID do
		table.insert(cosmeticIds, cosmeticId)
	end
	table.sort(cosmeticIds)
	return {
		classKinds = GachaRules.poolClassKinds(Enums.getAllValues(Enums.ClassKind), excluded),
		cosmeticIds = cosmeticIds,
		classWeight = GachaData.POOL_WEIGHTS.CLASS,
		cosmeticWeight = GachaData.POOL_WEIGHTS.COSMETIC,
		keysWeight = GachaData.POOL_WEIGHTS.KEYS,
	}
end

function GachaManager:getPublishedConfig(): GachaRules.Config_Published
	return {
		rollPriceDiamonds = GachaData.ROLL_PRICE_DIAMONDS,
		directClassPriceDiamonds = GachaData.DIRECT_CLASS_PRICE_DIAMONDS,
		directUpgradePriceDiamondsBySlot = GachaData.DIRECT_UPGRADE_PRICE_DIAMONDS_BY_SLOT,
		directCosmeticPriceDiamondsByRarity = GachaData.DIRECT_COSMETIC_PRICE_DIAMONDS_BY_RARITY,
		odds = GachaRules.odds(self.pool),
		poolClassKinds = self.pool.classKinds,
		prizes = GachaRules.prizeList(self.pool),
		maxSkillSlots = GachaData.MAX_SKILL_SLOTS,
	}
end

function GachaManager:isRestricted(player: Player): boolean
	return self.isRestrictedByPlayer[player] == true
end

function GachaManager:isPolicyKnown(player: Player): boolean
	return self.isPolicyKnownByPlayer[player] == true
end

-- the answer, from PolicyService or the dev panel's checkbox; the flag
-- goes out before the "known" mark, so a client never sees the policy
-- as known with the old flag still showing
function GachaManager:setRestricted(player: Player, isRestricted: boolean)
	self.isRestrictedByPlayer[player] = isRestricted
	self.isPolicyKnownByPlayer[player] = true
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED, isRestricted)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.IS_PAID_RANDOM_ITEMS_POLICY_KNOWN, true)
end

function GachaManager:isClassInPool(classKind: number): boolean
	return table.find(self.pool.classKinds, classKind) ~= nil
end

-- writes a result into the save and tells the client; shared by the roll
-- and the direct buy so both reveal the same way
function GachaManager:grant(player: Player, playerData: PlayerData.PlayerData, result: GachaRules.Result)
	local keys = GachaRules.applyResult(playerData:getClassProgress(), playerData:getOwnedCosmetics(), result)
	if keys > 0 then
		playerData:addKeys(keys)
	end
	SplendidReplicationManager:replicateGacha(player)
	if result.kind == Enums.GachaResultKind.CLASS or result.kind == Enums.GachaResultKind.SKILL_SLOT then
		SplendidReplicationManager:replicateClasses(player)
	end
	playerData:saveNow()
	NetManager:notifyClient(
		player,
		NetEventNames.NOTIFY_GACHA_RESULT,
		{
			kind = result.kind,
			classKind = result.classKind,
			skillSlot = result.skillSlot,
			cosmeticId = result.cosmeticId,
			keys = result.keys,
			convertedFromKind = result.convertedFromKind,
			convertedClassKind = result.convertedClassKind,
			convertedCosmeticId = result.convertedCosmeticId,
		}
	)
end

-- one roll: the price is spent first, so a player can never see a result
-- they did not pay for; a free roll is the dev tool's, and a forced draw
-- (the dev tool's dropdown) stands in for the random one
function GachaManager:roll(player: Player, isFree: boolean, forcedDraw: GachaRules.Draw?)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	if not isFree and not self:isPolicyKnown(player) then
		PlayerFeedbackManager:give(player, FEEDBACK_POLICY_UNKNOWN)
		return
	end
	if not isFree and self:isRestricted(player) then
		PlayerFeedbackManager:give(player, FEEDBACK_RESTRICTED)
		return
	end
	local draw = forcedDraw or GachaRules.draw(self.random, self.pool)
	if not draw then
		warn("GachaManager: the pool is empty; nothing to roll")
		return
	end
	if not isFree then
		if not playerData:spendDiamonds(GachaData.ROLL_PRICE_DIAMONDS) then
			PlayerFeedbackManager:giveDiamondsShort(player, GachaData.ROLL_PRICE_DIAMONDS, playerData:getDiamonds())
			return
		end
		SplendidReplicationManager:replicateDiamonds(player)
		-- the first crate paid for ends the lobby's Supply Crate lesson
		-- (2026-11-10); grant() below saves it with the prize
		if not playerData:getHasFinishedTutorialPart(Enums.TutorialPart.SUPPLY_CRATE) then
			playerData:setHasFinishedTutorialPart(Enums.TutorialPart.SUPPLY_CRATE, true)
			SplendidReplicationManager:replicateTutorial(player)
		end
	end
	local result = GachaRules.resolve(draw, playerData:getClassProgress(), playerData:getOwnedCosmetics(), self:getConfig())
	self:grant(player, playerData, result)
end

-- a class card sells once per class per day (designer, 2026-11-10):
-- written once the Diamonds are spent and before grant(), which
-- replicates and saves it with the prize
function GachaManager:recordStoreClassPurchase(playerData: PlayerData.PlayerData, classKind: number, storeDay: number)
	local className = Enums.getName(Enums.ClassKind, classKind)
	if className then
		DailyStoreRules.recordClassPurchase(playerData:getStorePurchases(), storeDay, className)
	end
end

-- the restricted player's road: a class outright, with no skill slots,
-- at the direct price; refused for everyone else, since the gacha is the
-- only source of classes by design
function GachaManager:buyClass(player: Player, classKind: number, storeDay: number)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	if not self:isRestricted(player) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_RESTRICTED)
		return
	end
	if not self:isClassInPool(classKind) then
		PlayerFeedbackManager:give(player, FEEDBACK_CLASS_NOT_SOLD)
		return
	end
	if GachaRules.isClassOwned(playerData:getClassProgress(), classKind) then
		PlayerFeedbackManager:give(player, FEEDBACK_CLASS_OWNED)
		return
	end
	if not playerData:spendDiamonds(GachaData.DIRECT_CLASS_PRICE_DIAMONDS) then
		PlayerFeedbackManager:giveDiamondsShort(player, GachaData.DIRECT_CLASS_PRICE_DIAMONDS, playerData:getDiamonds())
		return
	end
	SplendidReplicationManager:replicateDiamonds(player)
	self:recordStoreClassPurchase(playerData, classKind, storeDay)
	self:grant(player, playerData, { kind = Enums.GachaResultKind.CLASS, classKind = classKind, keys = 0 })
end

-- the restricted player's tier: the next skill slot of a class they own,
-- at that slot's price (2026-11-10). A rolling player gets it from a
-- duplicate in a crate, so it is refused for them
function GachaManager:upgradeClass(player: Player, classKind: number, storeDay: number)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	if not self:isRestricted(player) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_RESTRICTED)
		return
	end
	local progress = playerData:getClassProgress()
	if not GachaRules.isClassOwned(progress, classKind) then
		PlayerFeedbackManager:give(player, FEEDBACK_CLASS_NOT_OWNED)
		return
	end
	local price = GachaRules.directUpgradePrice(GachaData.DIRECT_UPGRADE_PRICE_DIAMONDS_BY_SLOT, progress, classKind, GachaData.MAX_SKILL_SLOTS)
	if not price then
		PlayerFeedbackManager:give(player, FEEDBACK_CLASS_MAXED)
		return
	end
	if not playerData:spendDiamonds(price) then
		PlayerFeedbackManager:giveDiamondsShort(player, price, playerData:getDiamonds())
		return
	end
	SplendidReplicationManager:replicateDiamonds(player)
	local skillSlot = GachaRules.openSkillSlots(progress, classKind, GachaData.MAX_SKILL_SLOTS) + 1
	self:recordStoreClassPurchase(playerData, classKind, storeDay)
	self:grant(player, playerData, { kind = Enums.GachaResultKind.SKILL_SLOT, classKind = classKind, skillSlot = skillSlot, keys = 0 })
end

-- the rotating Gear Store's set for the day (designer, 2026-11-10): a
-- pure function of the clock and the catalogue (DailyStoreRules), so
-- every server shows the same; held here and worked out again once the
-- day has turned
function GachaManager:getDailyStore(): DailyStoreRules.Store
	local now = workspace:GetServerTimeNow()
	local store = self.dailyStore
	if store and now < store.refreshTime then
		return store
	end
	local settings = GachaData.DAILY_STORE
	local classIds = {}
	for _, classKind in self.pool.classKinds do
		local className = Enums.getName(Enums.ClassKind, classKind)
		if className then
			table.insert(classIds, className)
		end
	end
	local fresh = DailyStoreRules.build(
		classIds,
		self.pool.cosmeticIds,
		now,
		{
			classCount = settings.CLASS_COUNT,
			cosmeticCount = settings.COSMETIC_COUNT,
			intervalSec = settings.INTERVAL_SEC,
		}
	)
	self.dailyStore = fresh
	return fresh
end

function GachaManager:publishDailyStore()
	SplendidReplicationManager:setGameMetadata(Attributes.DAILY_STORE, DailyStoreRules.encode(self:getDailyStore()))
end

-- publishes the set now and again each time it changes, for as long as
-- the server runs
function GachaManager:runDailyStore()
	self:publishDailyStore()
	task.spawn(
		function()
			while true do
				local waitSec = self:getDailyStore().refreshTime - workspace:GetServerTimeNow()
				task.wait(math.max(waitSec, 0) + DAILY_STORE_REFRESH_GRACE_SEC)
				self:publishDailyStore()
			end
		end
	)
end

-- the restricted player's cosmetic: bought by name for Diamonds, priced
-- by its rarity (2026-11-10). It is granted as a crate result, so it
-- joins the same owned set the crate and the Key Store fill and the
-- client opens the crate on it
function GachaManager:buyCosmetic(player: Player, cosmeticId: string)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	local definition = (CosmeticCatalogueData.BY_ID :: { [string]: any })[cosmeticId]
	local price = if definition then GachaRules.directCosmeticPrice(GachaData.DIRECT_COSMETIC_PRICE_DIAMONDS_BY_RARITY, definition.RARITY) else nil
	if not price then
		warn(`GachaManager: {player.Name} asked to buy cosmetic {cosmeticId}, which has no direct price`)
		PlayerFeedbackManager:give(player, FEEDBACK_COSMETIC_NOT_SOLD)
		return
	end
	if playerData:getOwnedCosmetics()[cosmeticId] then
		PlayerFeedbackManager:give(player, FEEDBACK_COSMETIC_OWNED)
		return
	end
	if not playerData:spendDiamonds(price) then
		PlayerFeedbackManager:giveDiamondsShort(player, price, playerData:getDiamonds())
		return
	end
	SplendidReplicationManager:replicateDiamonds(player)
	self:grant(player, playerData, { kind = Enums.GachaResultKind.COSMETIC, cosmeticId = cosmeticId, keys = 0 })
end

-- one purchase from the rotating store (designer, 2026-11-10): only a
-- restricted player shops there, and only for what is on sale today. A
-- class card is the next step of its class, the class itself when it is
-- not owned and its next tier when it is, as a crate's card would be;
-- each is granted as a crate result (grant sends NotifyGachaResult), so
-- the client plays the crate opening on exactly what was bought
function GachaManager:buyStoreItem(player: Player, classKind: number?, cosmeticId: string?)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	if not self:isRestricted(player) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_RESTRICTED)
		return
	end
	local store = self:getDailyStore()
	if classKind then
		local className = Enums.getName(Enums.ClassKind, classKind)
		if not className or not DailyStoreRules.isClassOnSale(store, className) then
			PlayerFeedbackManager:give(player, FEEDBACK_NOT_TODAY)
			return
		end
		if DailyStoreRules.hasBoughtClass(playerData:getStorePurchases(), store.day, className) then
			PlayerFeedbackManager:give(player, FEEDBACK_ALREADY_PURCHASED)
			return
		end
		if GachaRules.isClassOwned(playerData:getClassProgress(), classKind) then
			self:upgradeClass(player, classKind, store.day)
		else
			self:buyClass(player, classKind, store.day)
		end
	elseif cosmeticId then
		if not DailyStoreRules.isCosmeticOnSale(store, cosmeticId) then
			PlayerFeedbackManager:give(player, FEEDBACK_NOT_TODAY)
			return
		end
		self:buyCosmetic(player, cosmeticId)
	end
end

-- the dev tool's step: the next thing a roll of that class would give,
-- granted without a draw or a price
function GachaManager:grantClassStep(player: Player, classKind: number)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	local draw: GachaRules.Draw = { kind = Enums.GachaResultKind.CLASS, classKind = classKind }
	local result = GachaRules.resolve(draw, playerData:getClassProgress(), playerData:getOwnedCosmetics(), self:getConfig())
	self:grant(player, playerData, result)
end

-- ready-sequence entry (registered through GameController:registerPlaceManager):
-- the policy is asked off the thread, and asked again until it answers.
-- Until then the player can neither roll nor shop (isPolicyKnown), so a
-- restricted player never gets a crate in the gap and a failed call
-- never opens one for them
function GachaManager:onPlayerReady(player: Player)
	self.isRestrictedByPlayer[player] = false
	self.isPolicyKnownByPlayer[player] = false
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.IS_PAID_RANDOM_ITEMS_POLICY_KNOWN, false)
	task.spawn(
		function()
			while true do
				local isSuccess, policy = pcall(
					function()
						return PolicyService:GetPolicyInfoForPlayerAsync(player)
					end
				)
				-- gone, reset, or answered by the dev panel meanwhile
				if self.isPolicyKnownByPlayer[player] ~= false or not GameController:getPlayerData(player) then
					return
				end
				if isSuccess then
					self:setRestricted(player, policy.ArePaidRandomItemsRestricted == true)
					return
				end
				warn(`GachaManager: PolicyService failed for {player.Name}; crates and the store stay shut until it answers. {tostring(policy)}`)
				task.wait(POLICY_RETRY_SEC)
			end
		end
	)
end

-- teardown entry; also the dev-tool reset, after which Ready asks again
function GachaManager:onPlayerRemoved(player: Player)
	self.isRestrictedByPlayer[player] = nil
	self.isPolicyKnownByPlayer[player] = nil
end

function GachaManager:registerDevCommands()
	DevTools:registerPlaceCommand(
		GachaManager.ROLL_FREE_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, EMPTY_SHAPE)
			if not isValid then
				warn("GachaManager: rollGachaFree with invalid args:", err)
				return
			end
			self:roll(player, true)
		end
	)
	DevTools:registerPlaceCommand(
		GachaManager.ROLL_FORCED_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, ROLL_FORCED_ARGS_SHAPE)
			if not isValid then
				warn("GachaManager: rollGachaForced with invalid args:", err)
				return
			end
			local draw = GachaRules.drawForPrizeKey(self.pool, args.prizeKey)
			if not draw then
				PlayerFeedbackManager:give(player, `No prize {args.prizeKey} in the gacha pool`)
				return
			end
			self:roll(player, true, draw)
		end
	)
	DevTools:registerPlaceCommand(
		GachaManager.SET_KEYS_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, SET_KEYS_ARGS_SHAPE)
			if not isValid then
				warn("GachaManager: setKeys with invalid args:", err)
				return
			end
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:addKeys(args.keys - playerData:getKeys())
			SplendidReplicationManager:replicateGacha(player)
			PlayerFeedbackManager:give(player, "Keys set to " .. tostring(playerData:getKeys()))
		end
	)
	DevTools:registerPlaceCommand(
		GachaManager.GRANT_CLASS_STEP_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, GRANT_CLASS_STEP_ARGS_SHAPE)
			if not isValid then
				warn("GachaManager: grantClassStep with invalid args:", err)
				return
			end
			self:grantClassStep(player, args.classKind)
		end
	)
	-- every class and slot forgotten, as a new account; the Recruit is
	-- equipped since the class worn may no longer be owned
	DevTools:registerPlaceCommand(
		GachaManager.CLEAR_CLASS_PROGRESS_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:resetClassProgress()
			SplendidReplicationManager:replicateGacha(player)
			ClassManager:selectClass(player, Enums.ClassKind.RECRUIT)
			playerData:saveNow()
			PlayerFeedbackManager:give(player, "Class progress cleared")
		end
	)
	-- every owned cosmetic forgotten, so a cosmetic draw is new again
	-- rather than converted to Keys (2026-11-04)
	DevTools:registerPlaceCommand(
		GachaManager.CLEAR_COSMETICS_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:resetOwnedCosmetics()
			SplendidReplicationManager:replicateGacha(player)
			playerData:saveNow()
			PlayerFeedbackManager:give(player, "Cosmetics cleared")
		end
	)
	-- every class card in the rotating store buyable again today
	DevTools:registerPlaceCommand(
		GachaManager.RESET_STORE_PURCHASES_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:resetStorePurchases()
			SplendidReplicationManager:replicateGacha(player)
			PlayerFeedbackManager:give(player, "Store purchases reset")
		end
	)
	-- every skill slot's free daily reroll ready again, any offer gone
	DevTools:registerPlaceCommand(
		GachaManager.RESET_FREE_REROLLS_COMMAND,
		function(player: Player, _args: { [string]: any })
			ClassManager:clearFreeRolls(player)
			PlayerFeedbackManager:give(player, "Free rerolls reset")
		end
	)
	-- the Supply Crate lesson unlearnt, so the guide leads to the stall again
	DevTools:registerPlaceCommand(
		GachaManager.RESET_CRATE_TUTORIAL_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:setHasFinishedTutorialPart(Enums.TutorialPart.SUPPLY_CRATE, false)
			SplendidReplicationManager:replicateTutorial(player)
			playerData:saveNow()
			PlayerFeedbackManager:give(player, "Supply Crate tutorial reset")
		end
	)
	DevTools:registerPlaceCommand(
		GachaManager.SET_RESTRICTED_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, SET_RESTRICTED_ARGS_SHAPE)
			if not isValid then
				warn("GachaManager: setPaidRandomRestricted with invalid args:", err)
				return
			end
			if not GameController:getPlayerData(player) then
				return
			end
			self:setRestricted(player, args.isRestricted)
			PlayerFeedbackManager:give(player, if args.isRestricted then "Paid random items restricted" else "Paid random items allowed")
		end
	)
end

function GachaManager:init()
	local catalogueProblems = CosmeticRules.validateCatalogue(CosmeticCatalogueData.BY_ID)
	if #catalogueProblems > 0 then
		error("GachaManager: GameData/Cosmetics/Catalogue is malformed: " .. table.concat(catalogueProblems, "; "))
	end
	-- the names and templates the reveal and the odds list draw skins by
	SplendidReplicationManager:setGameMetadata(Attributes.COSMETIC_CATALOGUE, CosmeticRules.encodeCatalogue(CosmeticRules.publish(CosmeticCatalogueData.BY_ID)))
	-- ClassManager is common code and cannot ask the lobby: it is handed
	-- the question, so a restricted player's reroll is the free daily one
	ClassManager:setPaidRandomRestrictedProvider(
		function(player: Player): boolean
			return self:isRestricted(player)
		end
	)
	self.pool = self:buildPool()
	if #self.pool.classKinds == 0 then
		error("GachaManager: no class is in the gacha pool; check GameData/Gacha/Gacha.EXCLUDED_KINDS and the roster's POST_LAUNCH_KINDS")
	end
	-- the menu draws its price, odds, and class list from this; none of
	-- it changes at runtime
	SplendidReplicationManager:setGameMetadata(Attributes.GACHA_CONFIG, GachaRules.encodeConfig(self:getPublishedConfig()))
	self:runDailyStore()
	self:registerDevCommands()
	GameController:registerPlaceManager(self)
end

function GachaManager.new(): GachaManager
	local self = setmetatable({}, GachaManager) :: GachaManager
	self.pool = { classKinds = {}, cosmeticIds = {}, classWeight = 0, cosmeticWeight = 0, keysWeight = 0 }
	self.random = Random.new()
	self.isRestrictedByPlayer = {}
	self.isPolicyKnownByPlayer = {}
	return self
end

return GachaManager.new()
