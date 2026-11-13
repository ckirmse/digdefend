--!strict

-- The Starter Pack (M79, designer 2026-11-12): a game pass that pays a
-- class card, Diamonds, and a pick axe skin, once per account. The
-- contents are GameData/Store/StarterPack; the record that they were
-- paid is the save's hasClaimedStarterPack, which this manager is the
-- one writer of.
--
-- A game pass is not a developer product: there is no receipt. Roblox
-- only says "this account owns the pass" (UserOwnsGamePassAsync), so the
-- contents are paid by comparing that with the save's flag, in two
-- places: at Ready (a pass bought on the website, or one whose payout a
-- crash lost), and after the purchase prompt closes. The prompt's
-- "finished" signal can be faked by a cheating client, so it is never
-- trusted by itself: it only makes the server ask Roblox about ownership
-- again. The payout itself does not yield, so it cannot pay twice.
--
-- The class card and the skin go through GachaRules.resolve, the crate's
-- own rule, so a class already owned steps to its next tier and a
-- duplicate pays Keys exactly as a crate would.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local ClassRosterData = require("@game/ServerScriptService/GameData/Classes/Roster")
local CosmeticCatalogueData = require("@game/ServerScriptService/GameData/Cosmetics/Catalogue")
local StarterPackData = require("@game/ServerScriptService/GameData/Store/StarterPack")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GachaRules = require("@game/ReplicatedStorage/Shared/GachaRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local StarterPackRules = require("@game/ReplicatedStorage/Shared/StarterPackRules")
local GachaManager = require(script.Parent.GachaManager)
local BadgeManager = require(script.Parent.Parent.Server.BadgeManager)
local DevTools = require(script.Parent.Parent.Server.DevTools)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local StarterPackManager = {}
StarterPackManager.__index = StarterPackManager

export type StarterPackManager = typeof(setmetatable(
	{} :: {
		-- the pass's live Robux price; nil until Roblox has answered
		priceRobux: number?,
		-- a player whose ownership is being asked about after a prompt
		isConfirmingByPlayer: { [Player]: boolean },
	},
	StarterPackManager
))

local EMPTY_SHAPE = {}

-- the contents paid without the pass, and the flag cleared (what was
-- paid is kept), for testing
StarterPackManager.GRANT_COMMAND = "grantStarterPack"
StarterPackManager.RESET_COMMAND = "resetStarterPack"

-- Roblox can be a moment behind its own purchase: ownership is asked
-- this many times, this far apart, before the player is told it will
-- arrive on their next visit (Ready pays it then)
local CONFIRM_ATTEMPTS = 5
local CONFIRM_RETRY_SEC = 3

local FEEDBACK_ALREADY_OWNED = "You already have the Starter Pack"
local FEEDBACK_CONFIRM_LATER = "Your Starter Pack is on its way. It will arrive the next time you join"

function StarterPackManager:getNetHandlers()
	return {
		[NetEventNames.TRY_BUY_STARTER_PACK] = {
			shape = EMPTY_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:buy(player)
			end,
		},
	}
end

function StarterPackManager:publishOffer()
	local config = GachaManager:getConfig()
	local offer = StarterPackRules.buildOffer(StarterPackData, config.maxSkillSlots, config.keysPerCompleteClass, self.priceRobux)
	SplendidReplicationManager:setGameMetadata(Attributes.STARTER_PACK, StarterPackRules.encodeOffer(offer))
end

-- asks Roblox for the pass's price (yields) and republishes with it
function StarterPackManager:fetchPrice()
	local isSuccess, info = pcall(
		function()
			return MarketplaceService:GetProductInfoAsync(StarterPackData.GAME_PASS_ID, Enum.InfoType.GamePass)
		end
	)
	local price = if isSuccess and typeof(info) == "table" then info.PriceInRobux else nil
	if typeof(price) ~= "number" then
		warn(`StarterPackManager: no price for game pass {StarterPackData.GAME_PASS_ID} ({if isSuccess then "no PriceInRobux" else tostring(info)})`)
		return
	end
	self.priceRobux = price
	self:publishOffer()
end

-- whether Roblox says the account owns the pass (yields); false when it
-- cannot say, so a failed call never pays anything
function StarterPackManager:fetchOwnsPass(player: Player): boolean
	local isSuccess, owns = pcall(
		function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, StarterPackData.GAME_PASS_ID)
		end
	)
	if not isSuccess then
		warn(`StarterPackManager: could not ask about the pass for {player.Name}: {tostring(owns)}`)
		return false
	end
	return owns == true
end

-- the payout: nothing here yields, and the flag is set first, so it runs
-- once per account however many callers reach it. True when it paid
function StarterPackManager:grantIfNeeded(player: Player): boolean
	local playerData = GameController:getPlayerData(player)
	if not playerData or playerData:getHasClaimedStarterPack() then
		return false
	end
	playerData:setHasClaimedStarterPack(true)
	playerData:addDiamonds(StarterPackData.DIAMONDS)

	local config = GachaManager:getConfig()
	local progress = playerData:getClassProgress()
	local ownedCosmetics = playerData:getOwnedCosmetics()
	-- the class card by the priority list; with every class maxed there
	-- is no class to give and the card pays a complete class's Keys
	local keys = 0
	local classKind = StarterPackRules.pickClassKind(StarterPackData.CLASS_PRIORITY, progress, config.maxSkillSlots)
	if classKind then
		local classDraw: GachaRules.Draw = { kind = Enums.GachaResultKind.CLASS, classKind = classKind }
		local classResult = GachaRules.resolve(classDraw, progress, ownedCosmetics, config)
		keys += GachaRules.applyResult(progress, ownedCosmetics, classResult)
	else
		keys += config.keysPerCompleteClass
	end
	local cosmeticDraw: GachaRules.Draw = { kind = Enums.GachaResultKind.COSMETIC, cosmeticId = StarterPackData.COSMETIC_ID }
	local cosmeticResult = GachaRules.resolve(cosmeticDraw, progress, ownedCosmetics, config)
	keys += GachaRules.applyResult(progress, ownedCosmetics, cosmeticResult)
	if keys > 0 then
		playerData:addKeys(keys)
	end

	SplendidReplicationManager:replicateDiamonds(player)
	SplendidReplicationManager:replicateGacha(player)
	SplendidReplicationManager:replicateClasses(player)
	SplendidReplicationManager:replicateStarterPack(player)
	playerData:saveNow()
	-- the class card may be the one Class Act or Collector needed (M69)
	BadgeManager:checkClassBadges(player)
	NetManager:notifyClient(
		player,
		NetEventNames.NOTIFY_STARTER_PACK_GRANTED,
		{
			diamonds = StarterPackData.DIAMONDS,
			keys = keys,
		}
	)
	print(`[StarterPackManager] {player.Name} was paid the Starter Pack ({keys} Keys from duplicates)`)
	return true
end

-- after the prompt closed with a purchase claimed: Roblox is asked until
-- it agrees or the tries run out
function StarterPackManager:confirmPurchase(player: Player)
	if self.isConfirmingByPlayer[player] then
		return
	end
	self.isConfirmingByPlayer[player] = true
	for attempt = 1, CONFIRM_ATTEMPTS do
		if self:fetchOwnsPass(player) then
			self:grantIfNeeded(player)
			break
		end
		if not self.isConfirmingByPlayer[player] then
			-- left meanwhile
			return
		end
		if attempt == CONFIRM_ATTEMPTS then
			PlayerFeedbackManager:give(player, FEEDBACK_CONFIRM_LATER)
			break
		end
		task.wait(CONFIRM_RETRY_SEC)
	end
	self.isConfirmingByPlayer[player] = nil
end

function StarterPackManager:buy(player: Player)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	if playerData:getHasClaimedStarterPack() then
		PlayerFeedbackManager:give(player, FEEDBACK_ALREADY_OWNED)
		return
	end
	local isSuccess, err = pcall(
		function()
			MarketplaceService:PromptGamePassPurchase(player, StarterPackData.GAME_PASS_ID)
		end
	)
	if not isSuccess then
		warn(`StarterPackManager: could not prompt the pass for {player.Name}: {err}`)
	end
end

-- ready-sequence entry: an account that owns the pass and was never paid
-- (bought on the website, or a crash between the purchase and the save)
-- is paid now
function StarterPackManager:onPlayerReady(player: Player)
	local playerData = GameController:getPlayerData(player)
	if not playerData or playerData:getHasClaimedStarterPack() then
		return
	end
	task.spawn(
		function()
			if self:fetchOwnsPass(player) then
				self:grantIfNeeded(player)
			end
		end
	)
end

function StarterPackManager:onPlayerRemoved(player: Player)
	self.isConfirmingByPlayer[player] = nil
end

function StarterPackManager:registerDevCommands()
	DevTools:registerPlaceCommand(
		StarterPackManager.GRANT_COMMAND,
		function(player: Player, _args: { [string]: any })
			if not self:grantIfNeeded(player) then
				PlayerFeedbackManager:give(player, FEEDBACK_ALREADY_OWNED)
			end
		end
	)
	DevTools:registerPlaceCommand(
		StarterPackManager.RESET_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:setHasClaimedStarterPack(false)
			SplendidReplicationManager:replicateStarterPack(player)
			playerData:saveNow()
			PlayerFeedbackManager:give(player, "Starter Pack reset (an account that owns the pass is paid again on its next join)")
		end
	)
end

function StarterPackManager:init()
	local poolClassKinds = GachaRules.poolClassKinds(Enums.getAllValues(Enums.ClassKind), ClassRosterData.POST_LAUNCH_KINDS)
	local problems = StarterPackRules.validate(
		StarterPackData,
		function(classKind: number): boolean
			return table.find(poolClassKinds, classKind) ~= nil
		end,
		function(cosmeticId: string): boolean
			return (CosmeticCatalogueData.BY_ID :: { [string]: any })[cosmeticId] ~= nil
		end
	)
	if #problems > 0 then
		error("StarterPackManager: GameData/Store/StarterPack is malformed: " .. table.concat(problems, "; "))
	end
	self:publishOffer()
	task.spawn(
		function()
			self:fetchPrice()
		end
	)
	-- a cheating client can fire this signal, so it only ever starts a
	-- question to Roblox (confirmPurchase), never a payout
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if gamePassId ~= StarterPackData.GAME_PASS_ID or not wasPurchased or player.Parent ~= Players then
				return
			end
			self:confirmPurchase(player)
		end
	)
	self:registerDevCommands()
	GameController:registerPlaceManager(self)
end

function StarterPackManager.new(): StarterPackManager
	local self = setmetatable({}, StarterPackManager) :: StarterPackManager
	self.isConfirmingByPlayer = {}
	return self
end

return StarterPackManager.new()
