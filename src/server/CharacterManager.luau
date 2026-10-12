--!strict

-- Business logic for a player's characters (GDD "Characters", M55). The
-- record of truth is PlayerData's `characters` list; this manager is the
-- one place that changes a record, so every change is followed by
-- SplendidReplicationManager:replicateCharacters and the client's copy is
-- never stale. Gameplay managers ask it which weapon, post, and tower a
-- player brings; the lobby menus (M37, M57) and the dawn count (M56) land
-- on top of the setters below, which the dev tools drive until then.
local TextService = game:GetService("TextService")

local CharacterSchema = require("@game/ReplicatedStorage/Shared/CharacterSchema")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerData = require(script.Parent.PlayerData)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)

local CharacterManager = {}
CharacterManager.__index = CharacterManager

export type CharacterManager = typeof(setmetatable({} :: {}, CharacterManager))

local gameController: any -- prevent circular reference by not initializing here
local splendidReplicationManager: any

local FEEDBACK_NAME_FILTERED = "That name was not allowed"
local FEEDBACK_CHARACTER_CAP = "No more character slots"

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

-- the kind a gear row brings into a run; a player without data (not Ready,
-- or a dev stand-in) gets the default so the run never stalls on it
function CharacterManager:getGearKind(player: Player, gearSlot: number, defaultKind: number): number
	local record = self:getActiveCharacter(player)
	if not record then
		return defaultKind
	end
	local kind = CharacterSchema.getGear(record, gearSlot)
	return kind or defaultKind
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

function CharacterManager:replicate(player: Player)
	splendidReplicationManager:replicateCharacters(player)
end

function CharacterManager:setActiveCharacter(player: Player, characterId: string): boolean
	local playerData = self:getPlayerData(player)
	if not playerData or not playerData:setActiveCharacterId(characterId) then
		return false
	end
	self:replicate(player)
	return true
end

-- a new empty character in the next slot; the Diamonds and Robux prices
-- are M37's, so this grants the slot outright
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
	if defaults.validSkillIds[skillId] ~= true or not Enums.isValidValue(Enums.SkillRarity, rarity) then
		return false
	end
	record.skills[tostring(slot)] = {
		skillId = skillId,
		rarity = rarity :: number,
	}
	self:replicate(player)
	return true
end

function CharacterManager:init(gameControllerIn: any, splendidReplicationManagerIn: any)
	gameController = gameControllerIn
	splendidReplicationManager = splendidReplicationManagerIn
end

function CharacterManager.new(): CharacterManager
	local self = setmetatable({}, CharacterManager) :: CharacterManager
	return self
end

return CharacterManager.new()
