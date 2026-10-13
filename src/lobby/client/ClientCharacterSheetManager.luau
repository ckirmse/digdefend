--!strict

-- The Character Sheet (GDD "Character Menu", M37, from
-- docs/mockups/character-sheet-2026-10-12.png): one character's name (with
-- the rename pencil), avatar, Rank, and Nights Survived on the left; on the
-- right the LOADOUT tab with four gear cards over three skill rows, each
-- with an info button and a REROLL, and the COSMETICS tab (M61). Opened
-- from a card on the Character Select Menu; Back returns there. Everything
-- drawn is replicated (the character, the Diamonds, the reroll pricing and
-- skill catalogue in GameMetadata); a roll's offer arrives as a notify and
-- is answered with keep or take.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CharacterRules = require("@game/ReplicatedStorage/Shared/CharacterRules")
local CharacterSchema = require("@game/ReplicatedStorage/Shared/CharacterSchema")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientAvatarViewport = require(script.Parent.Parent.Client.ClientAvatarViewport)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientCharacterSheetManager = {}
ClientCharacterSheetManager.__index = ClientCharacterSheetManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	diamondLabel: TextLabel,
	nameLabel: TextLabel,
	nameBox: TextBox,
	renameButton: GuiButton,
	avatar: ViewportFrame,
	rankLabel: TextLabel,
	rankInfoButton: GuiButton,
	nightsLabel: TextLabel,
	loadoutTab: GuiButton,
	cosmeticsTab: GuiButton,
	loadoutPage: GuiObject,
	cosmeticsPage: GuiObject,
	hatGrid: GuiObject,
	hatButtonTemplate: TextButton,
	gearRow: GuiObject,
	gearCardTemplate: GuiObject,
	skillRows: GuiObject,
	skillRowTemplate: GuiObject,
	offerDialog: GuiObject,
	offerTitle: TextLabel,
	currentBox: GuiObject,
	newBox: GuiObject,
	offerKeep: GuiButton,
	offerUndo: GuiButton,
	offerRank: TextLabel,
}

-- what one box of the roll screen shows
type BoxContent = {
	icon: string,
	-- shown over the icon (the star numeral, or the skill's name when the
	-- skill has no icon yet)
	spinText: string,
	name: string,
	detail: string,
	-- the character's Rank with this in the row
	rank: number,
	-- Enums.Rarity, colouring the name and detail; nil for an empty slot
	rarity: number?,
}

export type ClientCharacterSheetManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		characterId: string?,
		isCosmeticsTab: boolean,
		-- the hat buttons cloned into the grid, by hat id ("" is own hat)
		hatButtons: { [string]: TextButton },
		-- the select menu hands in how to get back to it, so neither
		-- manager requires the other both ways
		onBack: (() -> ())?,
		-- the roll screen on screen, so a stale notify cannot answer a new one
		offerConnections: { RBXScriptConnection },
		-- bumps per roll screen so an older flip animation stops touching it
		rollGeneration: number,
	},
	ClientCharacterSheetManager
))

local INFO_DISPLAY_SEC = 5
local EMPTY_SKILL_TEXT = "Empty slot"
local EMPTY_SKILL_DESCRIPTION = "Roll to pick a skill"
local FREE_TEXT = "Free"
local LOCKED_TEXT = "Survive %d nights to unlock"
local RANK_INFO_TEXT = "Rank adds up your gear and skills by rarity, one number for how built this character is. A Contract's recommended Rank is a guide, never a guarantee."
local NIGHTS_TEXT = "Nights survived: %d"
-- the hat grid's first button: the player's own avatar hat
local OWN_HAT_ID = CharacterSchema.OWN_HAT_ID
local OWN_HAT_TEXT = "Own hat"
-- the catalogue's own picture of a hat
local HAT_THUMBNAIL = "rbxthumb://type=Asset&id=%d&w=150&h=150"
local GEAR_OFFER_TITLE = "New roll: %s"
local SKILL_OFFER_TITLE = "New roll: skill %d"
-- the NEW box flips through candidates quickly, then slows to a stop on the
-- result: each step waits longer than the last
local SPIN_FIRST_STEP_SEC = 0.05
local SPIN_STEP_GROWTH = 1.18
local SPIN_LAST_STEP_SEC = 0.45
-- the reveal of the name and buttons after the flip stops
local SPIN_REVEAL_DELAY_SEC = 0.35
local RANK_CHANGE_TEXT = "Character rank:  %d  >>  %d"
local TAB_ACTIVE_COLOR = UiStyle.PANEL_COLOR
local TAB_INACTIVE_COLOR = UiStyle.BACKGROUND_COLOR

-- the row label on a gear card: the slot's public name, numbered for the
-- two tower rows
local function gearSlotTitle(gearSlot: number): string
	if gearSlot == Enums.GearSlot.TOWER_1 then
		return "Tower 1"
	elseif gearSlot == Enums.GearSlot.TOWER_2 then
		return "Tower 2"
	end
	return Enums.getPublicName(Enums.GearSlot, gearSlot)
end

-- the kind's public name ("Rifle"); its stars read as a rarity word beside it
local function gearName(gearSlot: number, kind: number): string
	local gearEnum = CharacterSchema.getGearEnum(gearSlot)
	local kindName = if gearEnum then Enums.getPublicName(gearEnum, kind) else nil
	return kindName or "?"
end

local function gearRarityName(stars: number): string
	return CharacterRules.rarityName(CharacterRules.rarityForStars(stars))
end

local function rarityColor(rarity: number): Color3
	return UiStyle.RARITY_COLORS[rarity] or UiStyle.TEXT_COLOR
end

-- the item's own picture (designer, 2026-10-12: never the type's), the
-- rendered gun for the weapon rather than the tool bar's flat art; a post
-- weapon without a captured icon shows its reticle
local function gearPicture(gearSlot: number, kind: number): string
	if gearSlot == Enums.GearSlot.WEAPON then
		local icon = Icons.WEAPON_KIND[kind]
		if Icons.isPlaceholder(icon) then
			return Icons.WEAPON[kind] or ""
		end
		return icon
	elseif gearSlot == Enums.GearSlot.POST then
		local icon = Icons.POST_WEAPON[kind]
		if Icons.isPlaceholder(icon) then
			return Icons.POST_WEAPON_RETICLE[kind] or ""
		end
		return icon
	end
	return Icons.TOWER_KIND[kind] or ""
end

local function skillTitle(entry: CharacterRules.SkillCatalogueEntry?, skillId: string, rarity: number): string
	local name = if entry then entry.name else skillId
	return name .. " - " .. (Enums.getPublicName(Enums.Rarity, rarity) or "")
end

function ClientCharacterSheetManager:setOnBack(onBack: () -> ())
	self.onBack = onBack
end

function ClientCharacterSheetManager:getCharacter(): ClientDataManager.CharacterData?
	for _, character in ClientDataManager:getCharacters() do
		if character.id == self.characterId then
			return character
		end
	end
	return nil
end

function ClientCharacterSheetManager:getRerollPricing(): CharacterRules.RerollPricing?
	return CharacterRules.decodeRerollPricing(ClientDataManager:getGameMetadata(Attributes.CHARACTER_REROLL_PRICING))
end

function ClientCharacterSheetManager:getSkillCatalogue(): CharacterRules.SkillCatalogue
	return CharacterRules.decodeSkillCatalogue(ClientDataManager:getGameMetadata(Attributes.CHARACTER_SKILL_CATALOGUE))
end

function ClientCharacterSheetManager:fillRerollButton(button: GuiObject, price: number)
	local priceLabel = button:FindFirstChild(Constants.REROLL_BUTTON_PRICE_LABEL) :: TextLabel
	local priceIcon = button:FindFirstChild(Constants.REROLL_BUTTON_PRICE_ICON) :: ImageLabel
	priceLabel.Text = if price > 0 then utils.abbreviateNumber(price) else UiStyle.formatTitle(FREE_TEXT)
	priceIcon.Visible = price > 0
end

function ClientCharacterSheetManager:renderGearCards(view: View, character: ClientDataManager.CharacterData, pricing: CharacterRules.RerollPricing?)
	for _, child in view.gearRow:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.gearCardTemplate then
			child:Destroy()
		end
	end
	-- the mock-up's order: post, weapon, then the towers
	local order = { Enums.GearSlot.POST, Enums.GearSlot.WEAPON, Enums.GearSlot.TOWER_1, Enums.GearSlot.TOWER_2 }
	for index, gearSlot in order do
		local gear = character.gear[gearSlot]
		if not gear then
			continue
		end
		local card = view.gearCardTemplate:Clone()
		card.Name = "GearCard" .. tostring(index)
		card.LayoutOrder = index
		card.Visible = true
		local slotLabel = card:FindFirstChild(Constants.GEAR_CARD_SLOT_LABEL) :: TextLabel
		slotLabel.Text = UiStyle.formatTitle(gearSlotTitle(gearSlot))
		local kindLabel = card:FindFirstChild(Constants.GEAR_CARD_KIND_LABEL) :: TextLabel
		kindLabel.Text = UiStyle.formatTitle(gearName(gearSlot, gear.kind))
		local rarityLabel = card:FindFirstChild(Constants.GEAR_CARD_RARITY_LABEL) :: TextLabel
		rarityLabel.Text = UiStyle.formatTitle(gearRarityName(gear.stars))
		local gearColor = rarityColor(CharacterRules.rarityForStars(gear.stars))
		kindLabel.TextColor3 = gearColor
		rarityLabel.TextColor3 = gearColor
		local picture = card:FindFirstChild(Constants.GEAR_CARD_PICTURE) :: ImageLabel
		picture.Image = gearPicture(gearSlot, gear.kind)
		local rerollButton = card:FindFirstChild(Constants.GEAR_CARD_REROLL_BUTTON) :: GuiButton
		self:fillRerollButton(rerollButton, if pricing then pricing.gearPriceDiamonds else 0)
		rerollButton.Activated:Connect(
			function()
				ClientNetManager:fireServer(NetEventNames.TRY_REROLL_GEAR, { characterId = character.id, gearSlot = gearSlot })
			end
		)
		local infoButton = card:FindFirstChild(Constants.GEAR_CARD_INFO_BUTTON) :: GuiButton
		infoButton.Activated:Connect(
			function()
				local bonusPercent = if pricing then math.floor(pricing.bonusPerStar * (gear.stars - 1) * 100 + 0.5) else 0
				local odds = if pricing then CharacterRules.describeStarOdds(pricing) else ""
				ClientPlayerFeedbackManager:giveLocal(string.format("%s (%s): +%d%% damage from its rarity. A roll draws the kind and the rarity: %s. %s", gearName(gearSlot, gear.kind), gearRarityName(gear.stars), bonusPercent, CharacterRules.describeKindOdds(gearSlot), odds), INFO_DISPLAY_SEC)
			end
		)
		card.Parent = view.gearRow
	end
end

function ClientCharacterSheetManager:renderSkillRows(view: View, character: ClientDataManager.CharacterData, pricing: CharacterRules.RerollPricing?)
	for _, child in view.skillRows:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.skillRowTemplate then
			child:Destroy()
		end
	end
	local catalogue = self:getSkillCatalogue()
	local unlockNights = if pricing then pricing.skillSlotUnlockNights else {}
	local slotCount = math.max(#unlockNights, character.skillSlotsOpen)
	for slot = 1, slotCount do
		local row = view.skillRowTemplate:Clone()
		row.Name = "SkillRow" .. tostring(slot)
		row.LayoutOrder = slot
		row.Visible = true
		local badge = row:FindFirstChild(Constants.SKILL_ROW_BADGE) :: GuiObject
		local number = badge:FindFirstChild(Constants.SKILL_ROW_BADGE_LABEL) :: TextLabel
		number.Text = tostring(slot)
		local nameLabel = row:FindFirstChild(Constants.SKILL_ROW_NAME_LABEL) :: TextLabel
		local descriptionLabel = row:FindFirstChild(Constants.SKILL_ROW_DESCRIPTION_LABEL) :: TextLabel
		local infoButton = row:FindFirstChild(Constants.SKILL_ROW_INFO_BUTTON) :: GuiButton
		local rerollButton = row:FindFirstChild(Constants.SKILL_ROW_REROLL_BUTTON) :: GuiButton
		local lockIcon = row:FindFirstChild(Constants.SKILL_ROW_LOCK_ICON) :: GuiObject
		local isOpen = slot <= character.skillSlotsOpen
		if isOpen then
			local skill = character.skills[tostring(slot)]
			local entry = if skill then catalogue[skill.skillId] else nil
			nameLabel.Text = UiStyle.formatTitle(if skill then skillTitle(entry, skill.skillId, skill.rarity) else EMPTY_SKILL_TEXT)
			nameLabel.TextColor3 = if skill then rarityColor(skill.rarity) else UiStyle.TEXT_MUTED_COLOR
			descriptionLabel.Text = if entry then entry.description else (if skill then "" else EMPTY_SKILL_DESCRIPTION)
			descriptionLabel.Visible = true
			infoButton.Visible = skill ~= nil
			rerollButton.Visible = true
			lockIcon.Visible = false
			self:fillRerollButton(rerollButton, if pricing then CharacterRules.skillRollPrice(pricing, skill == nil) else 0)
			rerollButton.Activated:Connect(
				function()
					ClientNetManager:fireServer(NetEventNames.TRY_REROLL_SKILL, { characterId = character.id, slot = slot })
				end
			)
			infoButton.Activated:Connect(
				function()
					if entry then
						local family = Enums.getPublicName(Enums.SkillFamily, entry.family) or ""
						ClientPlayerFeedbackManager:giveLocal(string.format("%s (%s): %s", entry.name, family, entry.description), INFO_DISPLAY_SEC)
					end
				end
			)
		else
			nameLabel.Text = UiStyle.formatTitle(string.format(LOCKED_TEXT, unlockNights[slot] or 0))
			nameLabel.TextColor3 = UiStyle.TEXT_COLOR
			descriptionLabel.Visible = false
			infoButton.Visible = false
			rerollButton.Visible = false
			lockIcon.Visible = true
		end
		row.Parent = view.skillRows
	end
end

local HELMET_SLOT_NAME = Enums.getName(Enums.CosmeticSlot, Enums.CosmeticSlot.HELMET) :: string

-- one button per catalogue hat plus "own hat", built once the catalogue
-- is known; the selected one wears the accent stroke
function ClientCharacterSheetManager:buildHatGrid(view: View)
	if next(self.hatButtons) ~= nil then
		return
	end
	local catalogue = CharacterRules.decodeHatCatalogue(ClientDataManager:getGameMetadata(Attributes.CHARACTER_HAT_CATALOGUE))
	local ids = { OWN_HAT_ID }
	for hatId in catalogue do
		table.insert(ids, hatId)
	end
	table.sort(
		ids,
		function(a, b)
			if a == OWN_HAT_ID or b == OWN_HAT_ID then
				return a == OWN_HAT_ID
			end
			return catalogue[a].name < catalogue[b].name
		end
	)
	for order, hatId in ids do
		local button = view.hatButtonTemplate:Clone()
		button.Name = if hatId == OWN_HAT_ID then "OwnHat" else hatId
		button.LayoutOrder = order
		button.Visible = true
		local picture = button:FindFirstChild(Constants.HAT_BUTTON_PICTURE) :: ImageLabel
		local nameLabel = button:FindFirstChild(Constants.HAT_BUTTON_NAME_LABEL) :: TextLabel
		if hatId == OWN_HAT_ID then
			picture.Image = ""
			nameLabel.Text = UiStyle.formatTitle(OWN_HAT_TEXT)
		else
			picture.Image = string.format(HAT_THUMBNAIL, catalogue[hatId].assetId)
			nameLabel.Text = UiStyle.formatTitle(catalogue[hatId].name)
		end
		button.Activated:Connect(
			function()
				if self.characterId then
					ClientNetManager:fireServer(NetEventNames.TRY_SET_COSMETIC, { characterId = self.characterId, slot = Enums.CosmeticSlot.HELMET, skinId = hatId })
				end
			end
		)
		button.Parent = view.hatGrid
		self.hatButtons[hatId] = button
	end
end

function ClientCharacterSheetManager:renderHats(view: View, cosmetics: { [string]: string })
	self:buildHatGrid(view)
	local equipped = cosmetics[HELMET_SLOT_NAME] or OWN_HAT_ID
	for hatId, button in self.hatButtons do
		local stroke = button:FindFirstChild(Constants.HAT_BUTTON_SELECTED_STROKE) :: UIStroke
		stroke.Enabled = hatId == equipped
	end
end

function ClientCharacterSheetManager:renderTabs(view: View)
	view.loadoutPage.Visible = not self.isCosmeticsTab
	view.cosmeticsPage.Visible = self.isCosmeticsTab
	view.loadoutTab.BackgroundColor3 = if self.isCosmeticsTab then TAB_INACTIVE_COLOR else TAB_ACTIVE_COLOR
	view.cosmeticsTab.BackgroundColor3 = if self.isCosmeticsTab then TAB_ACTIVE_COLOR else TAB_INACTIVE_COLOR
end

function ClientCharacterSheetManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	view.diamondLabel.Text = utils.abbreviateNumber(ClientDataManager:getDiamonds())
	local character = self:getCharacter()
	if not character then
		-- the character went away under the sheet (a dev reset): back out
		self:closeMenu()
		return
	end
	view.nameLabel.Text = UiStyle.formatTitle(character.name)
	-- redressed on every render so an equipped hat shows at once
	ClientAvatarViewport:fill(view.avatar, false, character.cosmetics)
	local pricing = self:getRerollPricing()
	local rank = self:rankWith(character, nil, nil, nil, nil)
	local bands = if pricing then pricing.rankBands else {}
	view.rankLabel.Text = UiStyle.formatTitle(CharacterRules.rankText(rank, bands))
	view.rankLabel.TextColor3 = rarityColor(CharacterRules.rankBand(rank, bands))
	view.nightsLabel.Text = UiStyle.formatTitle(string.format(NIGHTS_TEXT, character.nightsSurvived))
	self:renderGearCards(view, character, pricing)
	self:renderSkillRows(view, character, pricing)
	self:renderHats(view, character.cosmetics)
	self:renderTabs(view)
end

-- the character's Rank as it stands, or as it would stand with one gear
-- row's stars or one skill slot's rarity swapped (nil leaves a part alone;
-- a skill slot swapped to rarity 0 counts as emptied)
function ClientCharacterSheetManager:rankWith(character: ClientDataManager.CharacterData, gearSlot: number?, stars: number?, skillSlot: number?, skillRarity: number?): number
	local pricing = self:getRerollPricing()
	if not pricing then
		return 1
	end
	local starsBySlot: { [number]: number } = {}
	for slot, gear in character.gear do
		starsBySlot[slot] = if slot == gearSlot and stars then stars else gear.stars
	end
	local skillRarities: { number } = {}
	for slotName, skill in character.skills do
		if skillSlot and tostring(skillSlot) == slotName then
			continue
		end
		table.insert(skillRarities, skill.rarity)
	end
	if skillSlot and skillRarity and skillRarity > 0 then
		table.insert(skillRarities, skillRarity)
	end
	return CharacterRules.rankOfPricing(starsBySlot, skillRarities, pricing)
end

local function fillBox(box: GuiObject, content: BoxContent, isRevealed: boolean)
	local icon = box:FindFirstChild(Constants.OFFER_BOX_ICON) :: ImageLabel
	local spin = box:FindFirstChild(Constants.OFFER_BOX_SPIN_LABEL) :: TextLabel
	local nameLabel = box:FindFirstChild(Constants.OFFER_BOX_NAME_LABEL) :: TextLabel
	local detail = box:FindFirstChild(Constants.OFFER_BOX_DETAIL_LABEL) :: TextLabel
	icon.Image = content.icon
	spin.Text = content.spinText
	-- with an icon the flipping text is a badge in the icon's corner; with
	-- none (skills, until their icons exist) it fills the icon area
	if content.icon ~= "" then
		spin.AnchorPoint = Vector2.new(1, 1)
		spin.Position = UDim2.fromScale(0.92, 0.61)
		spin.Size = UDim2.fromScale(0.3, 0.16)
	else
		spin.AnchorPoint = Vector2.new(0.5, 0)
		spin.Position = UDim2.fromScale(0.5, 0.17)
		spin.Size = UDim2.fromScale(0.9, 0.44)
	end
	nameLabel.Text = UiStyle.formatTitle(content.name)
	detail.Text = content.detail
	local color = if content.rarity then rarityColor(content.rarity) else UiStyle.TEXT_MUTED_COLOR
	nameLabel.TextColor3 = color
	detail.TextColor3 = color
	nameLabel.Visible = isRevealed
	detail.Visible = isRevealed
end

-- the Rank line under the boxes: green when the candidate raises it, red
-- when it lowers it, muted when nothing changes
function ClientCharacterSheetManager:showRankChange(before: number, after: number)
	local view = self.view
	if not view then
		return
	end
	view.offerRank.Text = UiStyle.formatTitle(string.format(RANK_CHANGE_TEXT, before, after))
	if after > before then
		view.offerRank.TextColor3 = UiStyle.POSITIVE_COLOR
	elseif after < before then
		view.offerRank.TextColor3 = UiStyle.NEGATIVE_COLOR
	else
		view.offerRank.TextColor3 = UiStyle.TEXT_MUTED_COLOR
	end
end

function ClientCharacterSheetManager:clearOffer()
	local view = self.view
	if not view then
		return
	end
	self.rollGeneration += 1
	for _, connection in self.offerConnections do
		connection:Disconnect()
	end
	table.clear(self.offerConnections)
	view.offerDialog.Visible = false
end

-- the roll screen: CURRENT on the left, NEW on the right. The NEW box flips
-- through `candidates` (each one's icon, name, and rarity), slowing to a
-- stop on `result`; then Keep and Undo appear. `onUndo` nil means the roll already landed (the free first roll),
-- so only Keep shows
function ClientCharacterSheetManager:showRoll(title: string, current: BoxContent, candidates: { BoxContent }, result: BoxContent, onKeep: () -> (), onUndo: (() -> ())?)
	local view = self.view
	if not view then
		return
	end
	self:clearOffer()
	local generation = self.rollGeneration
	view.offerTitle.Text = UiStyle.formatTitle(title)
	fillBox(view.currentBox, current, true)
	fillBox(view.newBox, result, true)
	self:showRankChange(current.rank, result.rank)
	view.offerKeep.Visible = false
	view.offerUndo.Visible = false
	view.offerDialog.Visible = true

	table.insert(
		self.offerConnections,
		view.offerKeep.Activated:Connect(
			function()
				self:clearOffer()
				onKeep()
			end
		)
	)
	table.insert(
		self.offerConnections,
		view.offerUndo.Activated:Connect(
			function()
				self:clearOffer()
				if onUndo then
					onUndo()
				end
			end
		)
	)

	task.spawn(
		function()
			-- flip through the candidates, each step a little slower, and
			-- land on the result; a cleared screen (new roll, Back) stops it
			local step = SPIN_FIRST_STEP_SEC
			local index = 0
			while step < SPIN_LAST_STEP_SEC do
				if self.rollGeneration ~= generation then
					return
				end
				index = index % #candidates + 1
				fillBox(view.newBox, candidates[index], true)
				self:showRankChange(current.rank, candidates[index].rank)
				task.wait(step)
				step *= SPIN_STEP_GROWTH
			end
			if self.rollGeneration ~= generation then
				return
			end
			fillBox(view.newBox, result, true)
			self:showRankChange(current.rank, result.rank)
			ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
			task.wait(SPIN_REVEAL_DELAY_SEC)
			if self.rollGeneration ~= generation then
				return
			end
			view.offerKeep.Visible = true
			view.offerUndo.Visible = onUndo ~= nil
		end
	)
end

function ClientCharacterSheetManager:onGearRollOffer(payload: any)
	if not self.isOpen or typeof(payload) ~= "table" then
		return
	end
	local character = self:getCharacter()
	local gearSlot = payload.gearSlot
	local gear = if character then character.gear[gearSlot] else nil
	if not character or not gear then
		return
	end
	local pricing = self:getRerollPricing()
	local minStars = if pricing then pricing.minStars else 1
	local maxStars = if pricing then pricing.maxStars else 5
	local function boxFor(kind: number, stars: number): BoxContent
		return {
			icon = gearPicture(gearSlot, kind),
			spinText = CharacterRules.starNumeral(stars),
			name = gearName(gearSlot, kind),
			detail = gearRarityName(stars),
			rank = self:rankWith(character, gearSlot, stars, nil, nil),
			rarity = CharacterRules.rarityForStars(stars),
		}
	end
	-- the flip runs through every kind the slot can hold, with the star
	-- count climbing alongside so both are seen to change
	local gearEnum = CharacterSchema.getGearEnum(gearSlot)
	local kinds = if gearEnum then Enums.getAllValues(gearEnum) else { gear.kind }
	table.sort(kinds)
	local candidates = {}
	local starCount = maxStars - minStars + 1
	for index, kind in kinds do
		table.insert(candidates, boxFor(kind, minStars + (index - 1) % starCount))
	end
	if #kinds < starCount then
		for stars = minStars, maxStars do
			table.insert(candidates, boxFor(kinds[(stars - minStars) % #kinds + 1], stars))
		end
	end
	self:showRoll(
		string.format(GEAR_OFFER_TITLE, gearSlotTitle(gearSlot)),
		boxFor(gear.kind, gear.stars),
		candidates,
		boxFor(payload.kind, payload.stars),
		function()
			ClientNetManager:fireServer(NetEventNames.TRY_RESOLVE_GEAR_ROLL, { isTaken = true })
		end,
		function()
			ClientNetManager:fireServer(NetEventNames.TRY_RESOLVE_GEAR_ROLL, { isTaken = false })
		end
	)
end

function ClientCharacterSheetManager:onSkillRollOffer(payload: any)
	if not self.isOpen or typeof(payload) ~= "table" or typeof(payload.offer) ~= "table" then
		return
	end
	local character = self:getCharacter()
	if not character then
		return
	end
	local catalogue = self:getSkillCatalogue()
	-- skills have no icons yet: the name itself flips in the icon area
	local function boxFor(skillId: string?, rarity: number?): BoxContent
		local entry = if skillId then catalogue[skillId] else nil
		local name = if entry then entry.name else (skillId or EMPTY_SKILL_TEXT)
		return {
			icon = "",
			spinText = name,
			name = if skillId then skillTitle(entry, skillId, rarity or 0) else EMPTY_SKILL_TEXT,
			detail = if entry then entry.description else "",
			rank = self:rankWith(character, nil, nil, payload.slot, rarity or 0),
			rarity = if skillId then rarity else nil,
		}
	end
	local ids = {}
	for id in catalogue do
		table.insert(ids, id)
	end
	table.sort(ids)
	local candidates = {}
	for _, id in ids do
		table.insert(candidates, boxFor(id, catalogue[id].rarity))
	end
	local current = character.skills[tostring(payload.slot)]
	local offer = payload.offer
	local isFinal = payload.isFinal == true
	self:showRoll(
		string.format(SKILL_OFFER_TITLE, payload.slot),
		boxFor(if current then current.skillId else nil, if current then current.rarity else nil),
		candidates,
		boxFor(offer.skillId, offer.rarity),
		function()
			if not isFinal then
				ClientNetManager:fireServer(NetEventNames.TRY_RESOLVE_SKILL_ROLL, { isTaken = true })
			end
		end,
		if isFinal then nil else function()
			ClientNetManager:fireServer(NetEventNames.TRY_RESOLVE_SKILL_ROLL, { isTaken = false })
		end
	)
end

function ClientCharacterSheetManager:beginRename()
	local view = self.view
	local character = self:getCharacter()
	if not view or not character then
		return
	end
	view.nameBox.Text = character.name
	view.nameBox.Visible = true
	view.nameLabel.Visible = false
	view.nameBox:CaptureFocus()
end

function ClientCharacterSheetManager:endRename(isSubmitted: boolean)
	local view = self.view
	if not view or not view.nameBox.Visible then
		return
	end
	view.nameBox.Visible = false
	view.nameLabel.Visible = true
	local name = utils.trimString(view.nameBox.Text)
	if isSubmitted and name ~= "" and self.characterId then
		ClientNetManager:fireServer(NetEventNames.TRY_RENAME_CHARACTER, { characterId = self.characterId, name = name })
	end
end

function ClientCharacterSheetManager:openMenu(characterId: string)
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	self.characterId = characterId
	self.isOpen = true
	self.isCosmeticsTab = false
	view.gui.Enabled = true
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientCharacterSheetManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self:endRename(false)
	self:clearOffer()
	self.isOpen = false
	view.gui.Enabled = false
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

local function findChild(parent: Instance?, name: string): Instance?
	return if parent then parent:FindFirstChild(name) else nil
end

function ClientCharacterSheetManager:findView(playerGui: PlayerGui): View?
	local gui = playerGui:FindFirstChild(Constants.CHARACTER_SHEET_GUI_NAME)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientCharacterSheetManager: no {Constants.CHARACTER_SHEET_GUI_NAME} ScreenGui; run build_character_sheet_gui`)
		return nil
	end
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	local wallet = findChild(dialog, Constants.CHARACTER_SELECT_WALLET)
	local leftPanel = findChild(dialog, Constants.CHARACTER_SHEET_LEFT_PANEL)
	local rightPanel = findChild(dialog, Constants.CHARACTER_SHEET_RIGHT_PANEL)
	local loadoutPage = findChild(rightPanel, Constants.CHARACTER_SHEET_LOADOUT_PAGE)
	local gearRow = findChild(loadoutPage, Constants.CHARACTER_SHEET_GEAR_ROW)
	local skillRows = findChild(loadoutPage, Constants.CHARACTER_SHEET_SKILL_ROWS)
	local offerDialog = findChild(dialog, Constants.CHARACTER_SHEET_OFFER_DIALOG)
	local cosmeticsPage = findChild(rightPanel, Constants.CHARACTER_SHEET_COSMETICS_PAGE)
	local hatGrid = findChild(cosmeticsPage, Constants.CHARACTER_SHEET_HAT_GRID)
	local parts = {
		backButton = findChild(dialog, Constants.CHARACTER_SELECT_BACK_BUTTON),
		diamondLabel = findChild(wallet, Constants.HUD_DIAMOND_AMOUNT_LABEL),
		nameLabel = findChild(leftPanel, Constants.CHARACTER_SHEET_NAME_LABEL),
		nameBox = findChild(leftPanel, Constants.CHARACTER_SHEET_NAME_BOX),
		renameButton = findChild(leftPanel, Constants.CHARACTER_SHEET_RENAME_BUTTON),
		avatar = findChild(leftPanel, Constants.CHARACTER_CARD_AVATAR),
		rankLabel = findChild(leftPanel, Constants.CHARACTER_CARD_RANK_LABEL),
		rankInfoButton = findChild(leftPanel, Constants.CHARACTER_SHEET_RANK_INFO_BUTTON),
		nightsLabel = findChild(leftPanel, Constants.CHARACTER_CARD_NIGHTS_LABEL),
		loadoutTab = findChild(rightPanel, Constants.CHARACTER_SHEET_LOADOUT_TAB),
		cosmeticsTab = findChild(rightPanel, Constants.CHARACTER_SHEET_COSMETICS_TAB),
		loadoutPage = loadoutPage,
		cosmeticsPage = cosmeticsPage,
		hatGrid = hatGrid,
		hatButtonTemplate = findChild(hatGrid, Constants.CHARACTER_SHEET_HAT_BUTTON_TEMPLATE),
		gearRow = gearRow,
		gearCardTemplate = findChild(gearRow, Constants.CHARACTER_SHEET_GEAR_CARD_TEMPLATE),
		skillRows = skillRows,
		skillRowTemplate = findChild(skillRows, Constants.CHARACTER_SHEET_SKILL_ROW_TEMPLATE),
		offerDialog = offerDialog,
		offerTitle = findChild(offerDialog, Constants.OFFER_DIALOG_TITLE),
		currentBox = findChild(offerDialog, Constants.OFFER_CURRENT_BOX),
		newBox = findChild(offerDialog, Constants.OFFER_NEW_BOX),
		offerKeep = findChild(offerDialog, Constants.OFFER_KEEP_BUTTON),
		offerUndo = findChild(offerDialog, Constants.OFFER_UNDO_BUTTON),
		offerRank = findChild(offerDialog, Constants.OFFER_RANK_LABEL),
	}
	for name, part in parts do
		if part == nil then
			warn(`ClientCharacterSheetManager: {Constants.CHARACTER_SHEET_GUI_NAME} is missing {name}; rerun build_character_sheet_gui`)
			return nil
		end
	end
	local view = parts :: any
	view.gui = gui
	view.dialog = dialog
	return view :: View
end

function ClientCharacterSheetManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.gui.Enabled = false
	view.gearCardTemplate.Visible = false
	view.skillRowTemplate.Visible = false
	view.offerDialog.Visible = false
	view.nameBox.Visible = false
	view.hatButtonTemplate.Visible = false

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
			local onBack = self.onBack
			if onBack then
				onBack()
			end
		end
	)
	view.loadoutTab.Activated:Connect(
		function()
			self.isCosmeticsTab = false
			self:renderTabs(view)
		end
	)
	view.cosmeticsTab.Activated:Connect(
		function()
			self.isCosmeticsTab = true
			self:renderTabs(view)
		end
	)
	view.renameButton.Activated:Connect(
		function()
			self:beginRename()
		end
	)
	view.rankInfoButton.Activated:Connect(
		function()
			ClientPlayerFeedbackManager:giveLocal(RANK_INFO_TEXT, INFO_DISPLAY_SEC)
		end
	)
	view.nameBox.FocusLost:Connect(
		function(isEnterPressed: boolean)
			self:endRename(isEnterPressed)
		end
	)

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self:endRename(false)
			self:clearOffer()
			self.isOpen = false
			view.gui.Enabled = false
		end,
		notifyClickOutside = function(_overlay) end,
	}
	self.overlay = overlay

	ClientDataManager:subscribeCharacters(
		function()
			self:render()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.DIAMONDS,
		function()
			self:render()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_GEAR_ROLL_OFFER,
		function(payload: any)
			self:onGearRollOffer(payload)
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_SKILL_ROLL_OFFER,
		function(payload: any)
			self:onSkillRollOffer(payload)
		end
	)
end

function ClientCharacterSheetManager.new(): ClientCharacterSheetManager
	local self = setmetatable({}, ClientCharacterSheetManager) :: ClientCharacterSheetManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	self.characterId = nil
	self.isCosmeticsTab = false
	self.hatButtons = {}
	self.onBack = nil
	self.offerConnections = {}
	self.rollGeneration = 0
	return self
end

return ClientCharacterSheetManager.new()
