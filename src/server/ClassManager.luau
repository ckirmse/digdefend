--!strict

-- Business logic for a player's classes (GDD "Classes"; CharacterManager
-- until the Class Equip Menu of 2026-11-04, when the character records
-- went and a class became the loadout). The record of truth is
-- PlayerData's `classes` map and `activeClassKind`; this manager is the
-- one place that changes either, so every change is followed by
-- SplendidReplicationManager:replicateClasses and the client's copy is
-- never stale. Gameplay managers ask it which weapon, post, tower, and
-- gadget a player brings (the active class's kit from the roster) and
-- its modifiers; the Class Menu equips a class and rolls its perks (the
-- skill slots the gacha opened) through the net handlers. Cosmetics are
-- the account's one loadout (CosmeticManager), never a class's.
local Players = game:GetService("Players")

local RerollsData = require("@game/ServerScriptService/GameData/Characters/Rerolls")
local SkillEffectsData = require("@game/ServerScriptService/GameData/Characters/SkillEffects")
local SkillsData = require("@game/ServerScriptService/GameData/Characters/Skills")
local ClassDescriptionsData = require("@game/ServerScriptService/GameData/Classes/Descriptions")
local ClassRosterData = require("@game/ServerScriptService/GameData/Classes/Roster")
local TowersData = require("@game/ServerScriptService/GameData/Defenses/Towers")
local PostWeaponsData = require("@game/ServerScriptService/GameData/Posts/PostWeapons")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local ClassCatalogueRules = require("@game/ReplicatedStorage/Shared/ClassCatalogueRules")
local ClassRules = require("@game/ReplicatedStorage/Shared/ClassRules")
local ClassSchema = require("@game/ReplicatedStorage/Shared/ClassSchema")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GachaRules = require("@game/ReplicatedStorage/Shared/GachaRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SkillEffectRules = require("@game/ReplicatedStorage/Shared/SkillEffectRules")
local SkillRules = require("@game/ReplicatedStorage/Shared/SkillRules")
local PlayerData = require(script.Parent.PlayerData)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)

local ClassManager = {}
ClassManager.__index = ClassManager

-- a roll the player has paid for and not yet kept or undone; one at a
-- time per player, dropped when they leave
type PendingSkillRoll = {
	classKind: number,
	slot: number,
	offer: SkillRules.SkillOffer,
}

export type ClassManager = typeof(setmetatable(
	{} :: {
		pendingSkillRollByPlayer: { [Player]: PendingSkillRoll },
		classChangedCallbacks: { (player: Player, classKind: number) -> () },
		-- told when a skill lands in or leaves a slot of the class in play
		-- (a class change is told through classChangedCallbacks)
		skillsChangedCallbacks: { (player: Player) -> () },
		paidRandomRestrictedProvider: ((player: Player) -> boolean)?,
		random: Random,
	},
	ClassManager
))

local gameController: any -- prevent circular reference by not initializing here
local splendidReplicationManager: any
local netManager: any

local SELECT_CLASS_SHAPE = {
	classKind = { type = "enum", name = "ClassKind" },
}

local REROLL_SKILL_SHAPE = {
	classKind = { type = "enum", name = "ClassKind", optional = true },
	slot = "positiveInteger",
}

local RESOLVE_SKILL_ROLL_SHAPE = {
	isTaken = "boolean",
}

local FEEDBACK_ROLL_PENDING = "Keep or undo the roll on screen first"
local FEEDBACK_SLOT_LOCKED = "That perk slot is still locked"
local FEEDBACK_CLASS_LOCKED = "You do not own that class yet"
local FEEDBACK_FREE_ROLL_WAIT = "That slot's free reroll is not ready yet"
local FEEDBACK_OFFER_GONE = "That offer has expired"

function ClassManager:getNetHandlers()
	return {
		[NetEventNames.TRY_SELECT_CLASS] = {
			shape = SELECT_CLASS_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:selectClass(player, payload.classKind)
			end,
		},
		[NetEventNames.TRY_REROLL_SKILL] = {
			shape = REROLL_SKILL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:rerollSkill(player, payload.classKind, payload.slot)
			end,
		},
		[NetEventNames.TRY_RESOLVE_SKILL_ROLL] = {
			shape = RESOLVE_SKILL_ROLL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:resolveSkillRoll(player, payload.isTaken)
			end,
		},
		[NetEventNames.TRY_KEEP_SKILL_OFFER] = {
			shape = REROLL_SKILL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:keepSkillOffer(player, payload.classKind, payload.slot)
			end,
		},
	}
end

function ClassManager:getPlayerData(player: Player): PlayerData.PlayerData?
	return gameController:getPlayerData(player)
end

-- the record of a class (the active one when nil), made on first touch
function ClassManager:getRecord(player: Player, classKind: number?): ClassSchema.ClassSave?
	local playerData = self:getPlayerData(player)
	if not playerData then
		return nil
	end
	local kind = classKind or playerData:getActiveClassKind()
	local className = Enums.getName(Enums.ClassKind, kind)
	if not className then
		return nil
	end
	return playerData:getClassRecord(className)
end

-- the class the player brings; the roster's default before the save loads
function ClassManager:getClassKind(player: Player): number
	local playerData = self:getPlayerData(player)
	if not playerData then
		return ClassRosterData.DEFAULT_CLASS
	end
	return playerData:getActiveClassKind()
end

-- the roster row of the class the player brings; nil before Ready
function ClassManager:getClassData(player: Player): ClassRules.ClassData?
	if not self:getPlayerData(player) then
		return nil
	end
	return ClassRosterData.BY_KIND[self:getClassKind(player)]
end

-- the skill ids the class in play holds, slot order; none before Ready
function ClassManager:getSkillIds(player: Player): { string }
	return SkillEffectRules.skillIdsOf(self:getRecord(player))
end

-- the class's modifiers with the held skills' multiplied in (M56,
-- 2026-11-09): the one table every system and menu prices by
function ClassManager:getModifiers(player: Player): { [number]: number }
	local classData = self:getClassData(player)
	return SkillEffectRules.combineModifiers(if classData then classData.MODIFIERS else {}, self:getSkillIds(player), SkillEffectsData.BY_ID)
end

-- a class modifier with the skills on it (1.0 when nothing sets it or the
-- player is not Ready), so a system reads one number and never the
-- roster or the skills
function ClassManager:getModifier(player: Player, classModifier: number): number
	local scale = self:getModifiers(player)[classModifier]
	return if scale ~= nil then scale else ClassRules.DEFAULT_MODIFIER
end

function ClassManager:subscribeSkillsChanged(callback: (player: Player) -> ())
	table.insert(self.skillsChangedCallbacks, callback)
end

function ClassManager:notifySkillsChanged(player: Player)
	for _, callback in self.skillsChangedCallbacks do
		callback(player)
	end
end

-- the kind the class's kit puts in a gear slot; the system's own default
-- when the player is not Ready
function ClassManager:getGearKind(player: Player, gearSlot: number, defaultKind: number): number
	return ClassRules.kitKind(self:getClassData(player), gearSlot) or defaultKind
end

function ClassManager:getClassTowerKinds(player: Player): { number }
	return ClassRules.towerKinds(self:getClassData(player))
end

function ClassManager:getGadgetKind(player: Player): number
	return ClassRules.gadgetKind(self:getClassData(player))
end

-- fires after the class in play changes (an equip, the dev dropdown), so
-- the gameplay managers can swap the kit in hand mid-run
function ClassManager:subscribeClassChanged(callback: (player: Player, classKind: number) -> ())
	table.insert(self.classChangedCallbacks, callback)
end

function ClassManager:notifyClassChangedIfNeeded(player: Player, previousClassKind: number)
	local classKind = self:getClassKind(player)
	if classKind == previousClassKind then
		return
	end
	for _, callback in self.classChangedCallbacks do
		callback(player, classKind)
	end
end

function ClassManager:isClassOwned(player: Player, classKind: number): boolean
	local playerData = self:getPlayerData(player)
	if not playerData then
		return false
	end
	return GachaRules.isClassOwned(playerData:getClassProgress(), classKind)
end

-- the Class Menu's EQUIP: only an owned class (the gacha's progress, M70)
function ClassManager:selectClass(player: Player, classKind: number)
	if not self:isClassOwned(player, classKind) then
		PlayerFeedbackManager:give(player, FEEDBACK_CLASS_LOCKED)
		return
	end
	if not self:setClassKind(player, classKind) then
		warn(`ClassManager: {player.Name} selected unknown class {tostring(classKind)}`)
		return
	end
	local playerData = self:getPlayerData(player)
	if playerData then
		playerData:saveNow()
	end
	-- no feedback line: the menu's EQUIPPED CLASS box is the word
	-- (designer, 2026-11-05)
end

-- puts a class in play with no ownership check (the dev dropdown)
function ClassManager:setClassKind(player: Player, classKind: number): boolean
	local playerData = self:getPlayerData(player)
	if not playerData or not ClassRosterData.BY_KIND[classKind] then
		return false
	end
	local previousClassKind = self:getClassKind(player)
	if not playerData:setActiveClassKind(classKind) then
		return false
	end
	self:replicate(player)
	self:notifyClassChangedIfNeeded(player, previousClassKind)
	return true
end

-- every roster row must point at built content, or a class would hand a
-- player a weapon with no data; checked once at startup so a roster typo
-- is a startup error naming the class, not a silent fallback mid-run
function ClassManager:checkRoster()
	local function isKindKnown(gearSlot: number, kind: number): boolean
		if gearSlot == Enums.GearSlot.WEAPON then
			return HandheldData.BY_KIND[kind] ~= nil
		elseif gearSlot == Enums.GearSlot.POST then
			return PostWeaponsData.BY_KIND[kind] ~= nil
		end
		return TowersData.BY_KIND[kind] ~= nil
	end
	for classKind, classData in ClassRosterData.BY_KIND do
		local problems = ClassRules.rosterRowProblems(classData, isKindKnown)
		if #problems > 0 then
			error(`ClassManager: roster row {Enums.getName(Enums.ClassKind, classKind) or classKind} is broken: {table.concat(problems, "; ")}`)
		end
	end
	if not ClassRosterData.BY_KIND[ClassRosterData.DEFAULT_CLASS] then
		error("ClassManager: the roster has no row for its DEFAULT_CLASS")
	end
	-- every effect names a skill, and every modifier it rides is a real one
	for skillId, effect in SkillEffectsData.BY_ID do
		if not SkillsData.BY_ID[skillId] then
			error(`ClassManager: SkillEffects names {skillId}, which Skills does not list`)
		end
		for classModifier in effect.MODIFIERS or {} do
			if not Enums.isValidValue(Enums.ClassModifier, classModifier) then
				error(`ClassManager: SkillEffects.{skillId} rides an unknown ClassModifier {classModifier}`)
			end
		end
	end
end

-- how many skill slots the account's gacha progress has opened on a class
function ClassManager:getOpenSkillSlots(player: Player, classKind: number): number
	local playerData = self:getPlayerData(player)
	if not playerData then
		return 0
	end
	return GachaRules.openSkillSlots(playerData:getClassProgress(), classKind, PlayerData.getClassDefaults().maxSkillSlots)
end

function ClassManager:getRerollPricing(): SkillRules.RerollPricing
	return {
		skillPriceDiamonds = RerollsData.SKILL_REROLL_PRICE_DIAMONDS,
		isFirstSkillRollFree = RerollsData.IS_FIRST_SKILL_ROLL_FREE,
		maxSkillSlots = PlayerData.getClassDefaults().maxSkillSlots,
		freeRollIntervalSec = RerollsData.RESTRICTED_FREE_REROLL_INTERVAL_SEC,
		keepPriceDiamondsByRarity = RerollsData.RESTRICTED_KEEP_PRICE_DIAMONDS_BY_RARITY,
	}
end

function ClassManager:getSkillCatalogue(): SkillRules.SkillCatalogue
	local catalogue: SkillRules.SkillCatalogue = {}
	for id, entry in SkillsData.BY_ID do
		catalogue[id] = {
			family = entry.FAMILY,
			rarity = entry.RARITY,
			name = entry.NAME,
			description = entry.DESCRIPTION,
		}
	end
	return catalogue
end

-- every class the menu lists (the post-launch ones stay off it), with its
-- kit and words resolved
function ClassManager:getClassCatalogue(): ClassCatalogueRules.Catalogue
	local kinds = ClassCatalogueRules.listedKinds(ClassRosterData.POST_LAUNCH_KINDS)
	return ClassCatalogueRules.publish(ClassRosterData.BY_KIND, ClassDescriptionsData, kinds)
end

-- a perk roll: the price is spent, the one result is held until the
-- player keeps it or undoes it (the row goes back to what it held). The
-- roll that fills an empty slot is free and lands at once, with no undo
function ClassManager:rerollSkill(player: Player, classKind: number?, slot: number)
	local playerData = self:getPlayerData(player)
	if not playerData then
		return
	end
	local kind = classKind or playerData:getActiveClassKind()
	local record = self:getRecord(player, kind)
	if not record then
		return
	end
	if self.pendingSkillRollByPlayer[player] then
		PlayerFeedbackManager:give(player, FEEDBACK_ROLL_PENDING)
		return
	end
	if not self:isClassOwned(player, kind) then
		PlayerFeedbackManager:give(player, FEEDBACK_CLASS_LOCKED)
		return
	end
	if slot > self:getOpenSkillSlots(player, kind) then
		PlayerFeedbackManager:give(player, FEEDBACK_SLOT_LOCKED)
		return
	end
	local pricing = self:getRerollPricing()
	local isSlotEmpty = record.skills[tostring(slot)] == nil
	-- a player restricted from paid random items never pays for a roll:
	-- a filled slot takes its free daily roll instead (the roll into an
	-- empty slot is free and kept at once for everyone, below)
	if not isSlotEmpty and self:isPaidRandomRestricted(player) then
		self:rollFreeOffer(player, playerData, kind, record, slot)
		return
	end
	local price = SkillRules.skillRollPrice(pricing, isSlotEmpty)
	if not playerData:spendDiamonds(price) then
		PlayerFeedbackManager:giveDiamondsShort(player, price, playerData:getDiamonds())
		return
	end
	splendidReplicationManager:replicateDiamonds(player)
	local offer = SkillRules.rollSkill(self.random, self:getSkillCatalogue())
	if not offer then
		warn("ClassManager: the skill catalogue is empty; nothing to roll")
		playerData:addDiamonds(price)
		splendidReplicationManager:replicateDiamonds(player)
		return
	end
	if price == 0 then
		self:setSkill(player, kind, slot, offer.skillId, offer.rarity)
		playerData:saveNow()
		netManager:notifyClient(
			player,
			NetEventNames.NOTIFY_SKILL_ROLL_OFFER,
			{
				classKind = kind,
				slot = slot,
				offer = offer,
				isFinal = true,
			}
		)
		return
	end
	self.pendingSkillRollByPlayer[player] = {
		classKind = kind,
		slot = slot,
		offer = offer,
	}
	netManager:notifyClient(
		player,
		NetEventNames.NOTIFY_SKILL_ROLL_OFFER,
		{
			classKind = kind,
			slot = slot,
			offer = offer,
		}
	)
end

-- whether PolicyService restricts the player from paid random items; the
-- lobby's GachaManager holds the answer and hands this manager the
-- question (the gameplay place has no rolls, so no provider and false)
function ClassManager:setPaidRandomRestrictedProvider(provider: (player: Player) -> boolean)
	self.paidRandomRestrictedProvider = provider
end

function ClassManager:isPaidRandomRestricted(player: Player): boolean
	local provider = self.paidRandomRestrictedProvider
	return provider ~= nil and provider(player)
end

-- the restricted player's reroll (designer, 2026-11-10): one free roll
-- per filled slot every RESTRICTED_FREE_REROLL_INTERVAL_SEC. Nothing is
-- paid for the chance; the result is saved on the slot as an offer the
-- player sees in full and may keep for Diamonds (keepSkillOffer) until
-- the slot's next roll is due
function ClassManager:rollFreeOffer(player: Player, playerData: PlayerData.PlayerData, classKind: number, record: ClassSchema.ClassSave, slot: number)
	local now = workspace:GetServerTimeNow()
	local freeRolls = record.freeRolls or {}
	local state = SkillRules.freeRollState(freeRolls[tostring(slot)], now, RerollsData.RESTRICTED_FREE_REROLL_INTERVAL_SEC)
	if not state.canRoll then
		PlayerFeedbackManager:give(player, FEEDBACK_FREE_ROLL_WAIT)
		return
	end
	local offer = SkillRules.rollSkill(self.random, self:getSkillCatalogue())
	if not offer then
		warn("ClassManager: the skill catalogue is empty; nothing to roll")
		return
	end
	record.freeRolls = freeRolls
	freeRolls[tostring(slot)] = {
		rollTime = now,
		skillId = offer.skillId,
		rarity = offer.rarity,
	}
	playerData:saveNow()
	-- the offer first, so the menu's reel is turning before the redraw
	-- the data change brings
	netManager:notifyClient(
		player,
		NetEventNames.NOTIFY_SKILL_ROLL_OFFER,
		{
			classKind = classKind,
			slot = slot,
			offer = offer,
			isFreeOffer = true,
		}
	)
	splendidReplicationManager:replicateClasses(player)
end

-- the restricted player keeps the offer standing on a slot: the price is
-- the offered skill's rarity price, and the wait for the slot's next
-- free roll is untouched
function ClassManager:keepSkillOffer(player: Player, classKind: number?, slot: number)
	local playerData = self:getPlayerData(player)
	if not playerData then
		return
	end
	local kind = classKind or playerData:getActiveClassKind()
	local record = self:getRecord(player, kind)
	if not record or not self:isPaidRandomRestricted(player) then
		return
	end
	if not self:isClassOwned(player, kind) then
		PlayerFeedbackManager:give(player, FEEDBACK_CLASS_LOCKED)
		return
	end
	if slot > self:getOpenSkillSlots(player, kind) then
		PlayerFeedbackManager:give(player, FEEDBACK_SLOT_LOCKED)
		return
	end
	local freeRoll = if record.freeRolls then record.freeRolls[tostring(slot)] else nil
	local state = SkillRules.freeRollState(freeRoll, workspace:GetServerTimeNow(), RerollsData.RESTRICTED_FREE_REROLL_INTERVAL_SEC)
	local offer = state.offer
	if not freeRoll or not offer then
		PlayerFeedbackManager:give(player, FEEDBACK_OFFER_GONE)
		return
	end
	local price = SkillRules.keepPrice(self:getRerollPricing(), offer.rarity)
	if not price then
		warn(`ClassManager: no keep price for rarity {offer.rarity}`)
		return
	end
	if not playerData:spendDiamonds(price) then
		PlayerFeedbackManager:giveDiamondsShort(player, price, playerData:getDiamonds())
		return
	end
	splendidReplicationManager:replicateDiamonds(player)
	freeRoll.skillId = nil
	freeRoll.rarity = nil
	self:setSkill(player, kind, slot, offer.skillId, offer.rarity)
	playerData:saveNow()
end

-- the dev tool's reset: every slot of every class may take its free roll
-- again, and any standing offer is gone
function ClassManager:clearFreeRolls(player: Player)
	local playerData = self:getPlayerData(player)
	if not playerData then
		return
	end
	for _, record in playerData:getClassRecords() do
		record.freeRolls = nil
	end
	playerData:saveNow()
	splendidReplicationManager:replicateClasses(player)
end

function ClassManager:resolveSkillRoll(player: Player, isTaken: boolean)
	local pending = self.pendingSkillRollByPlayer[player]
	if not pending then
		return
	end
	self.pendingSkillRollByPlayer[player] = nil
	if isTaken then
		self:setSkill(player, pending.classKind, pending.slot, pending.offer.skillId, pending.offer.rarity)
	end
	local playerData = self:getPlayerData(player)
	if playerData then
		playerData:saveNow()
	end
end

function ClassManager:replicate(player: Player)
	splendidReplicationManager:replicateClasses(player)
	self:replicateModifiers(player)
end

-- the combined modifiers alone: published at Ready by the gameplay
-- SkillManager (before 2026-11-09 the table only reached a client after a
-- class change, so a menu priced by the roster's defaults until then)
function ClassManager:replicateModifiers(player: Player)
	splendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.CLASS_MODIFIERS, ClassRules.encodeModifierTable(self:getModifiers(player)))
end

-- puts a skill in an open slot of a class; nil skillId empties the slot
function ClassManager:setSkill(player: Player, classKind: number?, slot: number, skillId: string?, rarity: number?): boolean
	local playerData = self:getPlayerData(player)
	if not playerData then
		return false
	end
	local kind = classKind or playerData:getActiveClassKind()
	local record = self:getRecord(player, kind)
	if not record then
		return false
	end
	local defaults = PlayerData.getClassDefaults()
	if slot < 1 or slot > self:getOpenSkillSlots(player, kind) or slot ~= math.floor(slot) then
		return false
	end
	if skillId == nil then
		record.skills[tostring(slot)] = nil
		self:replicate(player)
		if kind == self:getClassKind(player) then
			self:notifySkillsChanged(player)
		end
		return true
	end
	if defaults.validSkillIds[skillId] ~= true or not Enums.isValidValue(Enums.Rarity, rarity) then
		return false
	end
	record.skills[tostring(slot)] = {
		skillId = skillId,
		rarity = rarity :: number,
	}
	self:replicate(player)
	if kind == self:getClassKind(player) then
		self:notifySkillsChanged(player)
	end
	return true
end

function ClassManager:init(gameControllerIn: any, splendidReplicationManagerIn: any, netManagerIn: any)
	gameController = gameControllerIn
	splendidReplicationManager = splendidReplicationManagerIn
	netManager = netManagerIn
	self:checkRoster()
	-- the Class Menu draws every class, the perk rows, and the reroll
	-- buttons from these; none changes at runtime
	splendidReplicationManager:setGameMetadata(Attributes.SKILL_REROLL_PRICING, SkillRules.encodeRerollPricing(self:getRerollPricing()))
	splendidReplicationManager:setGameMetadata(Attributes.SKILL_CATALOGUE, SkillRules.encodeSkillCatalogue(self:getSkillCatalogue()))
	splendidReplicationManager:setGameMetadata(Attributes.CLASS_CATALOGUE, ClassCatalogueRules.encode(self:getClassCatalogue()))
	local unbuiltNames = {}
	for _, classKind in ClassRosterData.UNBUILT_KINDS do
		table.insert(unbuiltNames, Enums.getName(Enums.ClassKind, classKind) or "?")
	end
	splendidReplicationManager:setGameMetadata(Attributes.CLASS_UNBUILT_KINDS, table.concat(unbuiltNames, ","))
	-- an unresolved roll is paid for and lost with the player who left; the
	-- menu never shows one across sessions
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.pendingSkillRollByPlayer[player] = nil
		end
	)
end

function ClassManager.new(): ClassManager
	local self = setmetatable({}, ClassManager) :: ClassManager
	self.pendingSkillRollByPlayer = {}
	self.classChangedCallbacks = {}
	self.skillsChangedCallbacks = {}
	self.random = Random.new()
	return self
end

return ClassManager.new()
