--!strict

-- Badges (GDD "Earning Diamonds", M69): the one award path. A badge is a
-- Roblox badge with a Diamond reward (GameData/Run/Badges). Earning and
-- being paid are two steps: award marks the badge earned wherever it
-- happens, and claim pays its Diamonds once when the player presses the
-- button in the lobby's Badges menu (TryClaimBadgeReward). The record of
-- truth is the save: PlayerData's badges set (earned), badgesClaimed set
-- (paid), and badgeCounters, the lifetime numbers (blocks, kills, and
-- the rest) that span runs. This manager is the one writer of all three,
-- replicated as two CurrentPlayer attributes; every badge's stars,
-- description, picture, and reward are the BadgeCatalogue GameMetadata.
-- Roblox's own badge is awarded beside it when the badge has an id, so a
-- badge with no id yet (BADGE_ID = 0) is still earned and paid.
--
-- Common code, started by each place's main (it has per-player work at
-- Ready). It judges nothing about a run itself: the owning managers say
-- what happened (award, addProgress, checkClassBadges), which in the
-- gameplay place is the BadgeTrackerManager's job.
local BadgeService = game:GetService("BadgeService")

local BadgesData = require("@game/ServerScriptService/GameData/Run/Badges")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BadgeRules = require("@game/ReplicatedStorage/Shared/BadgeRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.DevTools)
local GameController = require(script.Parent.GameController)
local NetManager = require(script.Parent.NetManager)
local PlayerData = require(script.Parent.PlayerData)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.SplendidReplicationManager)

local BadgeManager = {}
BadgeManager.__index = BadgeManager

export type BadgeManager = typeof(setmetatable(
	{} :: {
		-- the Roblox badge's own picture, for a badge with no ICON
		iconByKind: { [number]: string },
	},
	BadgeManager
))

local GRANT_ARGS_SHAPE = {
	badgeKind = { type = "enum", name = "BadgeKind" },
}

local CLAIM_SHAPE = {
	badgeKind = { type = "enum", name = "BadgeKind" },
}

-- one badge awarded on demand, and every badge and counter forgotten in
-- the save (a Roblox badge once awarded stays on the account)
BadgeManager.GRANT_COMMAND = "grantBadge"
BadgeManager.CLEAR_COMMAND = "clearBadges"

local ARRIVAL_AWARD_DELAY_SEC = 8

local DEFINITIONS = BadgesData.BY_KIND :: BadgeRules.Definitions
local RULES = BadgesData.RULES :: BadgeRules.Rules

function BadgeManager:getRules(): BadgeRules.Rules
	return RULES
end

function BadgeManager:getDefinitions(): BadgeRules.Definitions
	return DEFINITIONS
end

-- Roblox's own badge, off the thread; a failure only loses the profile
-- badge, never the Diamonds, and Roblox ignores a badge already held
function BadgeManager:awardRobloxBadge(player: Player, badgeId: number)
	task.spawn(
		function()
			local isSuccess, err = pcall(
				function()
					BadgeService:AwardBadgeAsync(player.UserId, badgeId)
				end
			)
			if not isSuccess then
				warn(`BadgeManager: Roblox would not award badge {badgeId} to {player.Name}: {err}`)
			end
		end
	)
end

-- earns the badge for the player if they do not have it: the save's
-- set, the save, and the toast. Its Diamonds wait to be claimed in the
-- lobby's Badges menu (claim). True when it was new
function BadgeManager:award(player: Player, badgeKind: number): boolean
	local playerData = GameController:getPlayerData(player)
	local definition = DEFINITIONS[badgeKind]
	if not playerData or not definition or playerData:hasBadge(badgeKind) then
		return false
	end
	playerData:addBadge(badgeKind)
	SplendidReplicationManager:replicateBadges(player)
	playerData:saveNow()
	NetManager:notifyClient(player, NetEventNames.NOTIFY_BADGE_EARNED, { badgeKind = badgeKind })
	if definition.BADGE_ID > 0 then
		self:awardRobloxBadge(player, definition.BADGE_ID)
	end
	print(`[BadgeManager] {player.Name} earned {Enums.getName(Enums.BadgeKind, badgeKind)}`)
	return true
end

-- pays an earned badge's Diamonds, once. Nothing here yields, so two
-- presses cannot both find the reward unclaimed: the claimed set is
-- written before the Diamonds are added
function BadgeManager:claim(player: Player, badgeKind: number)
	local playerData = GameController:getPlayerData(player)
	local definition = DEFINITIONS[badgeKind]
	if not playerData or not definition then
		return
	end
	if not BadgeRules.canClaim(playerData:hasBadge(badgeKind), playerData:hasClaimedBadge(badgeKind)) then
		return
	end
	playerData:addClaimedBadge(badgeKind)
	playerData:addDiamonds(definition.DIAMONDS)
	SplendidReplicationManager:replicateBadges(player)
	SplendidReplicationManager:replicateDiamonds(player)
	playerData:saveNow()
	NetManager:notifyClient(
		player,
		NetEventNames.NOTIFY_BADGE_REWARD_CLAIMED,
		{
			badgeKind = badgeKind,
			diamonds = definition.DIAMONDS,
		}
	)
	print(`[BadgeManager] {player.Name} claimed {Enums.getName(Enums.BadgeKind, badgeKind)} (+{definition.DIAMONDS} Diamonds)`)
end

function BadgeManager:getNetHandlers()
	return {
		[NetEventNames.TRY_CLAIM_BADGE_REWARD] = {
			shape = CLAIM_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:claim(player, payload.badgeKind)
			end,
		},
	}
end

-- every badge as the Badges menu draws it, as GameMetadata
function BadgeManager:publishCatalogue()
	local published = BadgeRules.publish(DEFINITIONS, self.iconByKind, BadgesData.DEFAULT_ICON)
	SplendidReplicationManager:setGameMetadata(Attributes.BADGE_CATALOGUE, BadgeRules.encodeCatalogue(published))
end

-- a badge that exists on Roblox and has no ICON of its own takes the
-- Roblox badge's picture; asked once, off the thread, and the catalogue
-- is published again when the answers are in
function BadgeManager:fetchRobloxIcons()
	task.spawn(
		function()
			local hasFoundAny = false
			for badgeKind, definition in DEFINITIONS do
				if definition.BADGE_ID <= 0 or (definition.ICON and definition.ICON ~= "") then
					continue
				end
				local isSuccess, info = pcall(
					function()
						return BadgeService:GetBadgeInfoAsync(definition.BADGE_ID)
					end
				)
				if isSuccess and typeof(info) == "table" and typeof(info.IconImageId) == "number" and info.IconImageId > 0 then
					self.iconByKind[badgeKind] = `rbxassetid://{info.IconImageId}`
					hasFoundAny = true
				else
					warn(`BadgeManager: no Roblox icon for badge {definition.BADGE_ID}`)
				end
			end
			if hasFoundAny then
				self:publishCatalogue()
			end
		end
	)
end

function BadgeManager:awardAll(player: Player, badgeKinds: { number })
	for _, badgeKind in badgeKinds do
		self:award(player, badgeKind)
	end
end

-- adds to a lifetime counter and earns whatever it has now reached. The
-- counter rides the profile's own saves; only an earned badge saves at once
function BadgeManager:addProgress(player: Player, counter: number, amount: number)
	local playerData = GameController:getPlayerData(player)
	if not playerData or amount <= 0 then
		return
	end
	local value = playerData:addBadgeCounter(counter, amount)
	self:awardAll(player, BadgeRules.kindsForCounter(DEFINITIONS, counter, value))
end

-- Class Act and Collector, from the account's class progress; called at
-- Ready and by whatever just changed the progress (a crate, the store,
-- the Starter Pack)
function BadgeManager:checkClassBadges(player: Player)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	local maxSkillSlots = PlayerData.getClassDefaults().maxSkillSlots
	self:awardAll(player, BadgeRules.kindsForClassProgress(playerData:getClassProgress(), maxSkillSlots, RULES))
end

-- ready-sequence entry, in both places: joining is the first badge, and
-- an account whose classes already qualify is caught up
function BadgeManager:onPlayerReady(player: Player)
	-- a pause, so the toast lands once the client has started and the
	-- arrival loading screen has gone, not under it
	task.delay(
		ARRIVAL_AWARD_DELAY_SEC,
		function()
			self:award(player, Enums.BadgeKind.WELCOME)
			self:checkClassBadges(player)
		end
	)
end

function BadgeManager:registerDevCommands()
	DevTools:registerPlaceCommand(
		BadgeManager.GRANT_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, GRANT_ARGS_SHAPE)
			if not isValid then
				warn("BadgeManager: grantBadge with invalid args:", err)
				return
			end
			if not self:award(player, args.badgeKind) then
				PlayerFeedbackManager:give(player, "You already have that badge")
			end
		end
	)
	DevTools:registerPlaceCommand(
		BadgeManager.CLEAR_COMMAND,
		function(player: Player, _args: { [string]: any })
			local playerData = GameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:resetBadges()
			SplendidReplicationManager:replicateBadges(player)
			playerData:saveNow()
			PlayerFeedbackManager:give(player, "Badges and badge counters cleared")
		end
	)
end

function BadgeManager:init()
	local problems = BadgeRules.validate(DEFINITIONS, RULES)
	if #problems > 0 then
		error("BadgeManager: GameData/Run/Badges is malformed: " .. table.concat(problems, "; "))
	end
	self:publishCatalogue()
	self:fetchRobloxIcons()
	self:registerDevCommands()
	GameController:registerPlaceManager(self)
end

function BadgeManager.new(): BadgeManager
	local self = setmetatable({}, BadgeManager) :: BadgeManager
	self.iconByKind = {}
	return self
end

return BadgeManager.new()
