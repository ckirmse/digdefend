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
		-- the policy answer per Ready player; absent until it arrives,
		-- which counts as not restricted
		isRestrictedByPlayer: { [Player]: boolean },
	},
	GachaManager
))

local EMPTY_SHAPE = {}

local BUY_CLASS_SHAPE = {
	classKind = { type = "enum", name = "ClassKind" },
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

local FEEDBACK_RESTRICTED = "Rolling is not available on this account"
local FEEDBACK_NOT_RESTRICTED = "Classes are rolled on this account"
local FEEDBACK_CLASS_OWNED = "You already own that class"
local FEEDBACK_CLASS_NOT_SOLD = "That class is not for sale"

function GachaManager:getNetHandlers()
	return {
		[NetEventNames.TRY_ROLL_GACHA] = {
			shape = EMPTY_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:roll(player, false)
			end,
		},
		[NetEventNames.TRY_BUY_CLASS] = {
			shape = BUY_CLASS_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:buyClass(player, payload.classKind)
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
		odds = GachaRules.odds(self.pool),
		poolClassKinds = self.pool.classKinds,
		prizes = GachaRules.prizeList(self.pool),
		maxSkillSlots = GachaData.MAX_SKILL_SLOTS,
	}
end

function GachaManager:isRestricted(player: Player): boolean
	return self.isRestrictedByPlayer[player] == true
end

function GachaManager:setRestricted(player: Player, isRestricted: boolean)
	self.isRestrictedByPlayer[player] = isRestricted
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED, isRestricted)
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
	end
	local result = GachaRules.resolve(draw, playerData:getClassProgress(), playerData:getOwnedCosmetics(), self:getConfig())
	self:grant(player, playerData, result)
end

-- the restricted player's road: a class outright, with no skill slots,
-- at the direct price; refused for everyone else, since the gacha is the
-- only source of classes by design
function GachaManager:buyClass(player: Player, classKind: number)
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
	self:grant(player, playerData, { kind = Enums.GachaResultKind.CLASS, classKind = classKind, keys = 0 })
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
-- the policy is asked off the thread, and until it answers the player may
-- roll (the answer is false for almost everyone and never for long)
function GachaManager:onPlayerReady(player: Player)
	self.isRestrictedByPlayer[player] = false
	task.spawn(
		function()
			local isSuccess, policy = pcall(
				function()
					return PolicyService:GetPolicyInfoForPlayerAsync(player)
				end
			)
			if not isSuccess then
				warn(`GachaManager: PolicyService failed for {player.Name}; treating as not restricted. {tostring(policy)}`)
				return
			end
			if self.isRestrictedByPlayer[player] == nil or not GameController:getPlayerData(player) then
				return
			end
			self:setRestricted(player, policy.ArePaidRandomItemsRestricted == true)
		end
	)
end

-- teardown entry; also the dev-tool reset, after which Ready asks again
function GachaManager:onPlayerRemoved(player: Player)
	self.isRestrictedByPlayer[player] = nil
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
	self.pool = self:buildPool()
	if #self.pool.classKinds == 0 then
		error("GachaManager: no class is in the gacha pool; check GameData/Gacha/Gacha.EXCLUDED_KINDS and the roster's POST_LAUNCH_KINDS")
	end
	-- the menu draws its price, odds, and class list from this; none of
	-- it changes at runtime
	SplendidReplicationManager:setGameMetadata(Attributes.GACHA_CONFIG, GachaRules.encodeConfig(self:getPublishedConfig()))
	self:registerDevCommands()
	GameController:registerPlaceManager(self)
end

function GachaManager.new(): GachaManager
	local self = setmetatable({}, GachaManager) :: GachaManager
	self.pool = { classKinds = {}, cosmeticIds = {}, classWeight = 0, cosmeticWeight = 0, keysWeight = 0 }
	self.random = Random.new()
	self.isRestrictedByPlayer = {}
	return self
end

return GachaManager.new()
