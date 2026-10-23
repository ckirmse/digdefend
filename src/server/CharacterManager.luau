--!strict

-- Business logic for a player's characters (GDD "Characters", M55). The
-- record of truth is PlayerData's `characters` list; this manager is the
-- one place that changes a record, so every change is followed by
-- SplendidReplicationManager:replicateCharacters and the client's copy is
-- never stale. Gameplay managers ask it which weapon, post, and towers a
-- player brings; the Character Select Menu (M37) picks the character,
-- buys slots, and renames through its net handlers; the dawn count (M56)
-- and the sheet (M57) land on the same setters.
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local RankData = require("@game/ServerScriptService/GameData/Characters/Rank")
local RerollsData = require("@game/ServerScriptService/GameData/Characters/Rerolls")
local SkillsData = require("@game/ServerScriptService/GameData/Characters/Skills")
local SlotsData = require("@game/ServerScriptService/GameData/Characters/Slots")
local StarsData = require("@game/ServerScriptService/GameData/Characters/Stars")
local ClassRosterData = require("@game/ServerScriptService/GameData/Classes/Roster")
local TowersData = require("@game/ServerScriptService/GameData/Defenses/Towers")
local PostWeaponsData = require("@game/ServerScriptService/GameData/Posts/PostWeapons")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CharacterRules = require("@game/ReplicatedStorage/Shared/CharacterRules")
local CharacterSchema = require("@game/ReplicatedStorage/Shared/CharacterSchema")
local ClassRules = require("@game/ReplicatedStorage/Shared/ClassRules")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GearStatsRules = require("@game/ReplicatedStorage/Shared/GearStatsRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PlayerData = require(script.Parent.PlayerData)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)

local CharacterManager = {}
CharacterManager.__index = CharacterManager

-- a roll the player has paid for and not yet kept or taken (M37); one at
-- a time per player, dropped when they leave
type PendingGearRoll = {
	characterId: string,
	gearSlot: number,
	offer: CharacterRules.GearOffer,
}

type PendingSkillRoll = {
	characterId: string,
	slot: number,
	offer: CharacterRules.SkillOffer,
}

export type CharacterManager = typeof(setmetatable(
	{} :: {
		pendingGearRollByPlayer: { [Player]: PendingGearRoll },
		pendingSkillRollByPlayer: { [Player]: PendingSkillRoll },
		classChangedCallbacks: { (player: Player, classKind: number) -> () },
		random: Random,
	},
	CharacterManager
))

local gameController: any -- prevent circular reference by not initializing here
local splendidReplicationManager: any
local purchaseManager: any
local netManager: any
local hatManager: any

local SELECT_CHARACTER_SHAPE = {
	characterId = "string",
}

local BUY_CHARACTER_SLOT_SHAPE = {}

local RENAME_CHARACTER_SHAPE = {
	characterId = { type = "string", optional = true },
	name = "string",
}

local SET_COSMETIC_SHAPE = {
	characterId = { type = "string", optional = true },
	slot = { type = "enum", name = "CosmeticSlot" },
	skinId = "string",
}

local REROLL_GEAR_SHAPE = {
	characterId = { type = "string", optional = true },
	gearSlot = { type = "enum", name = "GearSlot" },
}

local RESOLVE_GEAR_ROLL_SHAPE = {
	isTaken = "boolean",
}

local REROLL_SKILL_SHAPE = {
	characterId = { type = "string", optional = true },
	slot = "positiveInteger",
}

local RESOLVE_SKILL_ROLL_SHAPE = {
	isTaken = "boolean",
}

local FEEDBACK_NAME_FILTERED = "That name was not allowed"
local FEEDBACK_CHARACTER_CAP = "No more character slots"
local FEEDBACK_NOT_ENOUGH_DIAMONDS = "Not enough Diamonds for that slot"
local FEEDBACK_ROBUX_SLOT_COMING = "Robux character slots are coming soon"
local FEEDBACK_SELECTED = "%s will go on the next run"
local FEEDBACK_NOT_ENOUGH_DIAMONDS_ROLL = "Not enough Diamonds for that reroll"
local FEEDBACK_ROLL_PENDING = "Keep or take the roll on screen first"
local FEEDBACK_SLOT_LOCKED = "That skill slot is still locked"

function CharacterManager:getNetHandlers()
	return {
		[NetEventNames.TRY_SELECT_CHARACTER] = {
			shape = SELECT_CHARACTER_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleTrySelectCharacter(player, payload)
			end,
		},
		[NetEventNames.TRY_BUY_CHARACTER_SLOT] = {
			shape = BUY_CHARACTER_SLOT_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:buyCharacterSlot(player)
			end,
		},
		[NetEventNames.TRY_RENAME_CHARACTER] = {
			shape = RENAME_CHARACTER_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:renameCharacter(player, payload.characterId, payload.name)
			end,
		},
		[NetEventNames.TRY_SET_COSMETIC] = {
			shape = SET_COSMETIC_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:setCosmetic(player, payload.characterId, payload.slot, payload.skinId)
			end,
		},
		[NetEventNames.TRY_REROLL_GEAR] = {
			shape = REROLL_GEAR_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:rerollGear(player, payload.characterId, payload.gearSlot)
			end,
		},
		[NetEventNames.TRY_RESOLVE_GEAR_ROLL] = {
			shape = RESOLVE_GEAR_ROLL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:resolveGearRoll(player, payload.isTaken)
			end,
		},
		[NetEventNames.TRY_REROLL_SKILL] = {
			shape = REROLL_SKILL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:rerollSkill(player, payload.characterId, payload.slot)
			end,
		},
		[NetEventNames.TRY_RESOLVE_SKILL_ROLL] = {
			shape = RESOLVE_SKILL_ROLL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:resolveSkillRoll(player, payload.isTaken)
			end,
		},
	}
end

-- nil unless the player is Ready, like every PlayerData question
function CharacterManager:getPlayerData(player: Player): PlayerData.PlayerData?
	return gameController:getPlayerData(player)
end

function CharacterManager:getActiveCharacter(player: Player): CharacterSchema.CharacterSave?
	local playerData = self:getPlayerData(player)
	return if playerData then playerData:getActiveCharacter() else nil
end

-- the character the dev tools and menus act on: the active one unless an
-- id is given
function CharacterManager:getCharacter(player: Player, characterId: string?): CharacterSchema.CharacterSave?
	local playerData = self:getPlayerData(player)
	if not playerData then
		return nil
	end
	if characterId == nil or characterId == "" then
		return playerData:getActiveCharacter()
	end
	return playerData:getCharacter(characterId)
end

-- the class the player's active character is (M64); the default class for
-- a player without data (not Ready, or a dev stand-in)
function CharacterManager:getClassKind(player: Player): number
	local record = self:getActiveCharacter(player)
	if not record then
		return ClassRosterData.DEFAULT_CLASS
	end
	return CharacterSchema.getClassKind(record, PlayerData.getCharacterDefaults())
end

function CharacterManager:getClassData(player: Player): ClassRules.ClassData?
	return ClassRosterData.BY_KIND[self:getClassKind(player)]
end

-- the scale the player's class puts on one stat (Enums.ClassModifier);
-- 1.0 for everything the class leaves alone, so a caller multiplies and
-- never branches on the class
function CharacterManager:getModifier(player: Player, classModifier: number): number
	return ClassRules.modifier(self:getClassData(player), classModifier)
end

-- the kind a gear slot brings into a run: the class's fixed kit (M64),
-- never the record's gear rows, which stay in the save only until the
-- menus are redrawn for classes. The default covers a player without data
-- and a one-tower class's second row
function CharacterManager:getGearKind(player: Player, gearSlot: number, defaultKind: number): number
	local kind = ClassRules.kitKind(self:getClassData(player), gearSlot)
	return kind or defaultKind
end

-- the towers the player's class may build, each once (nil for no data)
function CharacterManager:getClassTowerKinds(player: Player): { number }
	return ClassRules.towerKinds(self:getClassData(player))
end

-- the gadget the player's class carries (M66); NONE without data
function CharacterManager:getGadgetKind(player: Player): number
	return ClassRules.gadgetKind(self:getClassData(player))
end

-- the gameplay managers hand out a class's kit at Ready; this is how they
-- hear that the active character's class changed mid-run (the dev tool),
-- so the weapon in hand and a claimed post can follow it
function CharacterManager:subscribeClassChanged(callback: (player: Player, classKind: number) -> ())
	table.insert(self.classChangedCallbacks, callback)
end

function CharacterManager:notifyClassChangedIfNeeded(player: Player, previousClassKind: number)
	local classKind = self:getClassKind(player)
	if classKind == previousClassKind then
		return
	end
	local callbacks: { (player: Player, classKind: number) -> () } = self.classChangedCallbacks
	for _, callback in callbacks do
		callback(player, classKind)
	end
end

function CharacterManager:setClassKind(player: Player, characterId: string?, classKind: number): boolean
	local record = self:getCharacter(player, characterId)
	local className = Enums.getName(Enums.ClassKind, classKind)
	if not record or not className or not ClassRosterData.BY_KIND[classKind] then
		return false
	end
	local previousClassKind = self:getClassKind(player)
	record.classKind = className
	self:replicate(player)
	self:notifyClassChangedIfNeeded(player, previousClassKind)
	return true
end

-- every roster row must point at built content, or a class would hand a
-- player a weapon with no data; checked once at startup so a roster typo
-- is a startup error naming the class, not a silent fallback mid-run
function CharacterManager:checkRoster()
	local function isKindKnown(gearSlot: number, kind: number): boolean
		if gearSlot == Enums.GearSlot.WEAPON then
			return HandheldData.BY_KIND[kind] ~= nil
		elseif gearSlot == Enums.GearSlot.POST then
			return PostWeaponsData.BY_KIND[kind] ~= nil
		end
		return TowersData.BY_KIND[kind] ~= nil
	end
	for _, classKind in Enums.getAllValues(Enums.ClassKind) do
		local className = Enums.getName(Enums.ClassKind, classKind)
		local problems = ClassRules.rosterRowProblems(ClassRosterData.BY_KIND[classKind], isKindKnown)
		if #problems > 0 then
			error(`CharacterManager: GameData/Classes/Roster {className}: {table.concat(problems, "; ")}`)
		end
	end
	if not ClassRosterData.BY_KIND[ClassRosterData.DEFAULT_CLASS] then
		error("CharacterManager: GameData/Classes/Roster DEFAULT_CLASS has no row")
	end
end

function CharacterManager:getGearStars(player: Player, gearSlot: number): number
	local record = self:getActiveCharacter(player)
	if not record then
		return PlayerData.getCharacterDefaults().minStars
	end
	local _, stars = CharacterSchema.getGear(record, gearSlot)
	return stars
end

function CharacterManager:getOpenSkillSlots(record: CharacterSchema.CharacterSave): number
	return CharacterSchema.openSkillSlots(record.nightsSurvived, PlayerData.getCharacterDefaults().skillSlotUnlockNights)
end

function CharacterManager:getSlotPricing(): CharacterRules.SlotPricing
	return {
		diamondPriceBySlot = SlotsData.DIAMOND_PRICE_BY_SLOT,
		robuxProductId = SlotsData.ROBUX_PRODUCT_ID,
		maxCharacters = PlayerData.getMaxCharacters(),
	}
end

function CharacterManager:getRerollPricing(): CharacterRules.RerollPricing
	return {
		gearPriceDiamonds = RerollsData.GEAR_REROLL_PRICE_DIAMONDS,
		skillPriceDiamonds = RerollsData.SKILL_REROLL_PRICE_DIAMONDS,
		isFirstSkillRollFree = RerollsData.IS_FIRST_SKILL_ROLL_FREE,
		minStars = StarsData.MIN_STARS,
		maxStars = StarsData.MAX_STARS,
		bonusPerStar = StarsData.BONUS_PER_STAR,
		skillSlotUnlockNights = PlayerData.getCharacterDefaults().skillSlotUnlockNights,
		rankPointsByRarity = RankData.POINTS_BY_RARITY,
		rankBaselinePoints = RankData.BASELINE_POINTS,
		rankBands = self:getRankBands(),
	}
end

-- the stats page behind every gear card (2026-10-13): each kind's base
-- numbers as rows, built once from GameData and published as GameMetadata
function CharacterManager:getGearStatsCatalogue(): GearStatsRules.GearStatsCatalogue
	local weapons: { [number]: { GearStatsRules.StatRow } } = {}
	for kind, data in HandheldData.BY_KIND do
		weapons[kind] = GearStatsRules.weaponRows(data)
	end
	local posts: { [number]: { GearStatsRules.StatRow } } = {}
	for kind, data in PostWeaponsData.BY_KIND do
		posts[kind] = GearStatsRules.postWeaponRows(data)
	end
	local towers: { [number]: { GearStatsRules.StatRow } } = {}
	for kind, data in TowersData.BY_KIND do
		towers[kind] = GearStatsRules.towerRows(data)
	end
	return {
		[Enums.GearSlot.WEAPON] = weapons,
		[Enums.GearSlot.POST] = posts,
		[Enums.GearSlot.TOWER_1] = towers,
		[Enums.GearSlot.TOWER_2] = towers,
	}
end

function CharacterManager:getRankBands(): { CharacterRules.RankBand }
	local bands: { CharacterRules.RankBand } = {}
	for _, band in RankData.BANDS do
		table.insert(bands, { minRank = band.MIN_RANK, rarity = band.RARITY })
	end
	return bands
end

function CharacterManager:getSkillCatalogue(): CharacterRules.SkillCatalogue
	local catalogue: CharacterRules.SkillCatalogue = {}
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

-- a gear roll: the price is spent, the new kind and star count are held
-- until the player keeps them or undoes the roll (the row goes back to
-- what it held)
function CharacterManager:rerollGear(player: Player, characterId: string?, gearSlot: number)
	local playerData = self:getPlayerData(player)
	local record = self:getCharacter(player, characterId)
	if not playerData or not record then
		return
	end
	if self.pendingGearRollByPlayer[player] or self.pendingSkillRollByPlayer[player] then
		PlayerFeedbackManager:give(player, FEEDBACK_ROLL_PENDING)
		return
	end
	local pricing = self:getRerollPricing()
	if not playerData:spendDiamonds(pricing.gearPriceDiamonds) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_DIAMONDS_ROLL)
		return
	end
	splendidReplicationManager:replicateDiamonds(player)
	local offer = CharacterRules.rollGear(self.random, gearSlot, pricing)
	if not offer then
		playerData:addDiamonds(pricing.gearPriceDiamonds)
		splendidReplicationManager:replicateDiamonds(player)
		return
	end
	self.pendingGearRollByPlayer[player] = {
		characterId = record.id,
		gearSlot = gearSlot,
		offer = offer,
	}
	netManager:notifyClient(
		player,
		NetEventNames.NOTIFY_GEAR_ROLL_OFFER,
		{
			characterId = record.id,
			gearSlot = gearSlot,
			kind = offer.kind,
			stars = offer.stars,
		}
	)
end

function CharacterManager:resolveGearRoll(player: Player, isTaken: boolean)
	local pending = self.pendingGearRollByPlayer[player]
	if not pending then
		return
	end
	self.pendingGearRollByPlayer[player] = nil
	if isTaken then
		self:setGear(player, pending.characterId, pending.gearSlot, pending.offer.kind, pending.offer.stars)
	end
	local playerData = self:getPlayerData(player)
	if playerData then
		playerData:saveNow()
	end
end

-- a skill roll: the price is spent, the one result is held until the
-- player keeps it or undoes it (the row goes back to what it held). The
-- roll that fills an empty slot is free and lands at once, with no undo
function CharacterManager:rerollSkill(player: Player, characterId: string?, slot: number)
	local playerData = self:getPlayerData(player)
	local record = self:getCharacter(player, characterId)
	if not playerData or not record then
		return
	end
	if self.pendingGearRollByPlayer[player] or self.pendingSkillRollByPlayer[player] then
		PlayerFeedbackManager:give(player, FEEDBACK_ROLL_PENDING)
		return
	end
	if slot > self:getOpenSkillSlots(record) then
		PlayerFeedbackManager:give(player, FEEDBACK_SLOT_LOCKED)
		return
	end
	local pricing = self:getRerollPricing()
	local isSlotEmpty = record.skills[tostring(slot)] == nil
	local price = CharacterRules.skillRollPrice(pricing, isSlotEmpty)
	if not playerData:spendDiamonds(price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_DIAMONDS_ROLL)
		return
	end
	splendidReplicationManager:replicateDiamonds(player)
	local offer = CharacterRules.rollSkill(self.random, self:getSkillCatalogue())
	if not offer then
		warn("CharacterManager: the skill catalogue is empty; nothing to roll")
		playerData:addDiamonds(price)
		splendidReplicationManager:replicateDiamonds(player)
		return
	end
	if price == 0 then
		self:setSkill(player, record.id, slot, offer.skillId, offer.rarity)
		playerData:saveNow()
		netManager:notifyClient(
			player,
			NetEventNames.NOTIFY_SKILL_ROLL_OFFER,
			{
				characterId = record.id,
				slot = slot,
				offer = offer,
				isFinal = true,
			}
		)
		return
	end
	self.pendingSkillRollByPlayer[player] = {
		characterId = record.id,
		slot = slot,
		offer = offer,
	}
	netManager:notifyClient(
		player,
		NetEventNames.NOTIFY_SKILL_ROLL_OFFER,
		{
			characterId = record.id,
			slot = slot,
			offer = offer,
		}
	)
end

function CharacterManager:resolveSkillRoll(player: Player, isTaken: boolean)
	local pending = self.pendingSkillRollByPlayer[player]
	if not pending then
		return
	end
	self.pendingSkillRollByPlayer[player] = nil
	if isTaken then
		self:setSkill(player, pending.characterId, pending.slot, pending.offer.skillId, pending.offer.rarity)
	end
	local playerData = self:getPlayerData(player)
	if playerData then
		playerData:saveNow()
	end
end

function CharacterManager:replicate(player: Player)
	splendidReplicationManager:replicateCharacters(player)
	splendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.CLASS_MODIFIERS, ClassRules.encodeModifiers(self:getClassData(player)))
end

function CharacterManager:setActiveCharacter(player: Player, characterId: string): boolean
	local playerData = self:getPlayerData(player)
	local previousClassKind = self:getClassKind(player)
	if not playerData or not playerData:setActiveCharacterId(characterId) then
		return false
	end
	self:replicate(player)
	-- the live character wears the picked character's cosmetics
	hatManager:refresh(player)
	self:notifyClassChangedIfNeeded(player, previousClassKind)
	return true
end

-- equips a skin on a cosmetic slot; "" clears the slot. A hat slot takes
-- a catalogue hat or the player's own; every other slot takes only its
-- default skin until M61's art lands (2026-10-13)
function CharacterManager:setCosmetic(player: Player, characterId: string?, slot: number, skinId: string): boolean
	local playerData = self:getPlayerData(player)
	local record = self:getCharacter(player, characterId)
	if not playerData or not record then
		return false
	end
	local slotName = Enums.getName(Enums.CosmeticSlot, slot)
	if not slotName then
		return false
	end
	if skinId ~= "" then
		local isKnown
		if slot == Enums.CosmeticSlot.HELMET then
			isKnown = skinId == CharacterSchema.OWN_HAT_ID or hatManager:isHat(skinId)
		else
			isKnown = skinId == CharacterSchema.DEFAULT_SKIN_ID
		end
		if not isKnown then
			warn(`CharacterManager: {player.Name} equipped unknown skin {skinId} on {slotName}`)
			return false
		end
	end
	record.cosmetics[slotName] = if skinId ~= "" then skinId else nil
	self:replicate(player)
	if record.id == playerData:getActiveCharacterId() then
		hatManager:refresh(player)
	end
	playerData:saveNow()
	return true
end

function CharacterManager:handleTrySelectCharacter(player: Player, payload: { [string]: any })
	local record = self:getCharacter(player, payload.characterId)
	if not record or not self:setActiveCharacter(player, payload.characterId) then
		warn(`CharacterManager: {player.Name} selected unknown character {tostring(payload.characterId)}`)
		return
	end
	PlayerFeedbackManager:give(player, string.format(FEEDBACK_SELECTED, record.name))
end

-- a new empty character in the next slot, granted outright (the dev tool
-- and the Robux receipt); nil at the cap
function CharacterManager:addCharacter(player: Player): CharacterSchema.CharacterSave?
	local playerData = self:getPlayerData(player)
	if not playerData then
		return nil
	end
	local record = playerData:addCharacter()
	if not record then
		PlayerFeedbackManager:give(player, FEEDBACK_CHARACTER_CAP)
		return nil
	end
	self:replicate(player)
	return record
end

-- the Character Select Menu's UNLOCK SLOT: Diamonds are spent here, a
-- Robux slot opens Roblox's prompt and the receipt grants it
function CharacterManager:buyCharacterSlot(player: Player)
	local playerData = self:getPlayerData(player)
	if not playerData then
		return
	end
	local offer = CharacterRules.nextSlotOffer(#playerData:getCharacters(), self:getSlotPricing())
	if not offer then
		PlayerFeedbackManager:give(player, FEEDBACK_CHARACTER_CAP)
		return
	end
	if offer.currency == Enums.SlotCurrency.ROBUX then
		if (offer.productId or 0) == 0 then
			PlayerFeedbackManager:give(player, FEEDBACK_ROBUX_SLOT_COMING)
			return
		end
		purchaseManager:prompt(player, offer.productId)
		return
	end
	local price = offer.diamonds or 0
	if not playerData:spendDiamonds(price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_DIAMONDS)
		return
	end
	splendidReplicationManager:replicateDiamonds(player)
	local record = playerData:addCharacter()
	if not record then
		-- the offer said a slot was free a moment ago; give the Diamonds back
		playerData:addDiamonds(price)
		splendidReplicationManager:replicateDiamonds(player)
		PlayerFeedbackManager:give(player, FEEDBACK_CHARACTER_CAP)
		return
	end
	self:replicate(player)
	playerData:saveNow()
	netManager:notifyClient(player, NetEventNames.NOTIFY_CHARACTER_SLOT_BOUGHT, { characterId = record.id })
	print(`[CharacterManager] {player.Name} bought character slot {offer.slot} for {price} Diamonds`)
end

-- a Robux slot receipt: never refused, so at the cap the character is
-- still added past it and the save's validation trims it next load with a
-- warning; the menu never offers a slot at the cap, so this is a race
function CharacterManager:onSlotProductBought(player: Player)
	local playerData = self:getPlayerData(player)
	if not playerData then
		error("buyer is not Ready")
	end
	local record = playerData:addCharacter()
	if not record then
		warn(`CharacterManager: {player.Name} bought a Robux slot at the character cap`)
		return
	end
	self:replicate(player)
	netManager:notifyClient(player, NetEventNames.NOTIFY_CHARACTER_SLOT_BOUGHT, { characterId = record.id })
end

-- a player-typed name goes through Roblox's text filter first; a name the
-- filter changes is refused rather than shown hashed
function CharacterManager:renameCharacter(player: Player, characterId: string?, rawName: string): boolean
	local playerData = self:getPlayerData(player)
	local record = self:getCharacter(player, characterId)
	if not playerData or not record then
		return false
	end
	local defaults = PlayerData.getCharacterDefaults()
	local trimmed = string.sub(rawName, 1, defaults.maxNameLength)
	if trimmed == "" then
		return false
	end
	local isSuccess, filtered = pcall(
		function()
			local result = TextService:FilterStringAsync(trimmed, player.UserId)
			return result:GetNonChatStringForBroadcastAsync()
		end
	)
	if not isSuccess or filtered ~= trimmed then
		PlayerFeedbackManager:give(player, FEEDBACK_NAME_FILTERED)
		return false
	end
	record.name = trimmed
	self:replicate(player)
	return true
end

function CharacterManager:setNightsSurvived(player: Player, characterId: string?, nightsSurvived: number): boolean
	local record = self:getCharacter(player, characterId)
	if not record then
		return false
	end
	record.nightsSurvived = math.max(0, math.floor(nightsSurvived))
	self:replicate(player)
	return true
end

-- sets a gear row's kind (nil keeps it) and stars (nil keeps them)
function CharacterManager:setGear(player: Player, characterId: string?, gearSlot: number, kind: number?, stars: number?): boolean
	local record = self:getCharacter(player, characterId)
	local gearEnum = CharacterSchema.getGearEnum(gearSlot)
	local slotName = Enums.getName(Enums.GearSlot, gearSlot)
	if not record or not gearEnum or not slotName then
		return false
	end
	local defaults = PlayerData.getCharacterDefaults()
	local kindName = if kind ~= nil then Enums.getName(gearEnum, kind) else nil
	if kind ~= nil and kindName == nil then
		return false
	end
	if stars ~= nil and (stars < defaults.minStars or stars > defaults.maxStars or stars ~= math.floor(stars)) then
		return false
	end
	local row = record.gear[slotName]
	row.kind = kindName or row.kind
	row.stars = stars or row.stars
	self:replicate(player)
	return true
end

-- puts a skill in an open slot; nil skillId empties the slot
function CharacterManager:setSkill(player: Player, characterId: string?, slot: number, skillId: string?, rarity: number?): boolean
	local record = self:getCharacter(player, characterId)
	if not record then
		return false
	end
	local defaults = PlayerData.getCharacterDefaults()
	if slot < 1 or slot > self:getOpenSkillSlots(record) or slot ~= math.floor(slot) then
		return false
	end
	if skillId == nil then
		record.skills[tostring(slot)] = nil
		self:replicate(player)
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
	return true
end

function CharacterManager:init(gameControllerIn: any, splendidReplicationManagerIn: any, purchaseManagerIn: any, netManagerIn: any, hatManagerIn: any)
	gameController = gameControllerIn
	splendidReplicationManager = splendidReplicationManagerIn
	purchaseManager = purchaseManagerIn
	netManager = netManagerIn
	hatManager = hatManagerIn
	self:checkRoster()

	-- the lobby draws the next slot's card, the reroll buttons, and the
	-- skill rows from these; none changes at runtime
	splendidReplicationManager:setGameMetadata(Attributes.CHARACTER_SLOT_PRICING, CharacterRules.encodePricing(self:getSlotPricing()))
	splendidReplicationManager:setGameMetadata(Attributes.CHARACTER_REROLL_PRICING, CharacterRules.encodeRerollPricing(self:getRerollPricing()))
	splendidReplicationManager:setGameMetadata(Attributes.CHARACTER_SKILL_CATALOGUE, CharacterRules.encodeSkillCatalogue(self:getSkillCatalogue()))
	splendidReplicationManager:setGameMetadata(Attributes.CHARACTER_GEAR_STATS, GearStatsRules.encodeCatalogue(self:getGearStatsCatalogue()))

	-- an unresolved roll is paid for and lost with the player who left; the
	-- menu never shows one across sessions
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.pendingGearRollByPlayer[player] = nil
			self.pendingSkillRollByPlayer[player] = nil
		end
	)

	if SlotsData.ROBUX_PRODUCT_ID ~= 0 then
		purchaseManager:registerProduct(
			SlotsData.ROBUX_PRODUCT_ID,
			function(player: Player, _productId: number)
				self:onSlotProductBought(player)
			end
		)
	end
end

function CharacterManager.new(): CharacterManager
	local self = setmetatable({}, CharacterManager) :: CharacterManager
	self.pendingGearRollByPlayer = {}
	self.pendingSkillRollByPlayer = {}
	self.classChangedCallbacks = {}
	self.random = Random.new()
	return self
end

return CharacterManager.new()
