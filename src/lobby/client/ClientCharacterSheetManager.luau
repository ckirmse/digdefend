--!strict

-- The Character Sheet (GDD "Character Menu", M37, from
-- docs/mockups/character-sheet-2026-10-12.png): one character's name (with
-- the rename pencil), avatar, Rank, and Nights Survived on the left; on the
-- right the LOADOUT tab with four gear cards over three skill rows, each
-- with a REROLL, a gear card's name and picture opening its stats page,
-- one REROLL ODDS button under the left panel (every roll's odds by
-- rarity in one dialog, Roblox's paid random items policy), and the
-- COSMETICS tab: a scrolling row per cosmetic slot, a type box beside a
-- strip of picture-only items, the equipped one outlined and first when
-- the sheet opens (designer's mock-up, 2026-10-13). Opened
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
local GearStatsRules = require("@game/ReplicatedStorage/Shared/GearStatsRules")
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
	oddsButton: GuiButton,
	nightsLabel: TextLabel,
	loadoutTab: GuiButton,
	cosmeticsTab: GuiButton,
	loadoutPage: GuiObject,
	cosmeticsPage: GuiObject,
	cosmeticRows: GuiObject,
	cosmeticRowTemplate: GuiObject,
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
	statsPanel: GuiObject,
	statRows: GuiObject,
	statRowTemplate: GuiObject,
	infoDialog: GuiObject,
	infoTitle: TextLabel,
	infoPicture: ImageLabel,
	infoRows: GuiObject,
	infoRowTemplate: GuiObject,
	infoNote: TextLabel,
	infoClose: GuiButton,
}

-- one line of the info dialog: a coloured label on the left, a value on the right
type InfoRow = {
	label: string,
	value: string,
	color: Color3?,
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
	-- the stats panel's rows for this item: a label, the value as shown,
	-- and the number behind it for the better-or-worse colour
	stats: { StatLine },
}

type StatLine = {
	label: string,
	value: string,
	number: number?,
}

export type ClientCharacterSheetManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		characterId: string?,
		isCosmeticsTab: boolean,
		-- the item buttons of every COSMETICS row, by slot then item id,
		-- rebuilt when the sheet opens so the equipped item leads each strip
		cosmeticButtons: { [number]: { [string]: ImageButton } },
		-- the select menu hands in how to get back to it, so neither
		-- manager requires the other both ways
		onBack: (() -> ())?,
		-- the roll screen on screen, so a stale notify cannot answer a new one
		offerConnections: { RBXScriptConnection },
		-- bumps per roll screen so an older flip animation stops touching it
		rollGeneration: number,
		-- the sheet's own parts hidden while the roll screen is up, so it
		-- stands alone (designer, 2026-10-13); put back when it clears
		hiddenForRoll: { GuiObject },
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
-- the hat row's last item, NONE: the player's own avatar hat, whatever it
-- is (designer, 2026-10-13)
local OWN_HAT_ID = CharacterSchema.OWN_HAT_ID
local OWN_HAT_NAME = "None"
-- the catalogue's own picture of a hat
local HAT_THUMBNAIL = "rbxthumb://type=Asset&id=%d&w=150&h=150"
-- every other slot's one skin so far: the game's existing asset
local DEFAULT_ITEM_ID = CharacterSchema.DEFAULT_SKIN_ID
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
-- a stat the panel colours the other way round: less is better
local LOWER_IS_BETTER_LABELS: { [string]: boolean } = {
	Reload = true,
	Cooldown = true,
}
local RARITY_BONUS_LABEL = "Rarity bonus"
local RARITY_LABEL = "Rarity"
local MISSING_STAT_TEXT = "-"
-- the selected tab is the accent yellow of every other button (designer, 2026-10-13)
local TAB_ACTIVE_COLOR = UiStyle.ACCENT_COLOR
local TAB_INACTIVE_COLOR = UiStyle.PANEL_COLOR
local ODDS_TITLE = "Reroll odds"
local GEAR_ODDS_HEADER = "Gear (every slot)"
local SKILL_ODDS_HEADER = "Skills"
-- Roblox's paid random items policy: every tier's share as a percentage,
-- totalling 100, with a rounding note where the printed shares cannot
local ODDS_ROUNDING_NOTE = "Shares are rounded, so they may not add up to exactly 100%."
local ODDS_NOTE = "A gear roll draws the kind and the rarity together, every kind of the slot equally likely. A skill roll draws one of %d skills, each equally likely. A result may match what you have."
local STATS_TITLE = "%s (%s)"
local STATS_NOTE = "Base numbers. The rarity adds +%d%% damage."
-- the rows sit under the picture, or where it was
local INFO_ROWS_POSITION_WITH_PICTURE = UDim2.fromScale(0.5, 0.38)
local INFO_ROWS_POSITION_NO_PICTURE = UDim2.fromScale(0.5, 0.16)
-- both end above the note line, which is anchored at 0.84 and 0.08 tall
local INFO_ROWS_SIZE_WITH_PICTURE = UDim2.fromScale(0.9, 0.36)
local INFO_ROWS_SIZE_NO_PICTURE = UDim2.fromScale(0.9, 0.58)

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

-- the item's name with its star numeral ("Rifle IV"; designer, 2026-10-13,
-- in place of a numeral badge on the roll screen's boxes)
local function gearNameWithStars(gearSlot: number, kind: number, stars: number): string
	return gearName(gearSlot, kind) .. " " .. CharacterRules.starNumeral(stars)
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

function ClientCharacterSheetManager:getGearStats(): GearStatsRules.GearStatsCatalogue
	return GearStatsRules.decodeCatalogue(ClientDataManager:getGameMetadata(Attributes.CHARACTER_GEAR_STATS))
end

-- the info dialog over the sheet: a title, a picture or none, rows, and
-- a note; one dialog serves the odds tables and the stats pages
function ClientCharacterSheetManager:showInfo(title: string, pictureId: string?, rows: { InfoRow }, note: string)
	local view = self.view
	if not view then
		return
	end
	for _, child in view.infoRows:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.infoRowTemplate then
			child:Destroy()
		end
	end
	view.infoTitle.Text = UiStyle.formatTitle(title)
	local hasPicture = pictureId ~= nil and pictureId ~= ""
	view.infoPicture.Image = pictureId or ""
	view.infoPicture.Visible = hasPicture
	view.infoRows.Position = if hasPicture then INFO_ROWS_POSITION_WITH_PICTURE else INFO_ROWS_POSITION_NO_PICTURE
	view.infoRows.Size = if hasPicture then INFO_ROWS_SIZE_WITH_PICTURE else INFO_ROWS_SIZE_NO_PICTURE
	-- the rows list scrolls (designer, 2026-10-13), so every row keeps the
	-- template's height and a long table scrolls back to the top
	if view.infoRows:IsA("ScrollingFrame") then
		view.infoRows.CanvasPosition = Vector2.zero
	end
	for index, infoRow in rows do
		local row = view.infoRowTemplate:Clone()
		row.Name = "Row" .. tostring(index)
		row.LayoutOrder = index
		row.Visible = true
		-- a header row is a label with no value and no background
		row.BackgroundTransparency = if infoRow.value == "" then 1 else view.infoRowTemplate.BackgroundTransparency
		local label = row:FindFirstChild(Constants.INFO_ROW_LABEL) :: TextLabel
		label.Text = UiStyle.formatTitle(infoRow.label)
		label.TextColor3 = infoRow.color or UiStyle.TEXT_COLOR
		local value = row:FindFirstChild(Constants.INFO_ROW_VALUE) :: TextLabel
		value.Text = infoRow.value
		row.Parent = view.infoRows
	end
	view.infoNote.Text = note
	view.infoDialog.Visible = true
end

function ClientCharacterSheetManager:closeInfo()
	local view = self.view
	if view then
		view.infoDialog.Visible = false
	end
end

local function rarityRows(odds: { CharacterRules.RarityOdds }, rows: { InfoRow }): { InfoRow }
	for _, line in odds do
		table.insert(rows, { label = CharacterRules.rarityName(line.rarity), value = CharacterRules.percentText(line.percent), color = rarityColor(line.rarity) })
	end
	return rows
end

-- the one REROLL ODDS button (designer, 2026-10-13): both tables in one
-- dialog, so every roll's odds are on the sheet before any REROLL is
-- pressed, as Roblox's paid random items policy asks
function ClientCharacterSheetManager:showAllOdds()
	local pricing = self:getRerollPricing()
	if not pricing then
		return
	end
	local catalogue = self:getSkillCatalogue()
	local count = 0
	for _ in catalogue do
		count += 1
	end
	local gearOdds = CharacterRules.gearRarityOdds(pricing)
	local skillOdds = CharacterRules.skillRarityOdds(catalogue)
	local rows: { InfoRow } = { { label = GEAR_ODDS_HEADER, value = "", color = UiStyle.TEXT_MUTED_COLOR } }
	rarityRows(gearOdds, rows)
	table.insert(rows, { label = SKILL_ODDS_HEADER, value = "", color = UiStyle.TEXT_MUTED_COLOR })
	rarityRows(skillOdds, rows)
	local note = string.format(ODDS_NOTE, count)
	if not CharacterRules.isOddsTotalExact(gearOdds) or not CharacterRules.isOddsTotalExact(skillOdds) then
		note ..= " " .. ODDS_ROUNDING_NOTE
	end
	self:showInfo(ODDS_TITLE, nil, rows, note)
end

-- the stats page behind a gear card's name or picture: the kind's base
-- numbers from the published catalogue
function ClientCharacterSheetManager:showGearStats(gearSlot: number, gear: ClientDataManager.GearData, pricing: CharacterRules.RerollPricing?)
	local byKind = self:getGearStats()[gearSlot]
	local statRows = if byKind then byKind[gear.kind] else nil
	local rows: { InfoRow } = {}
	for _, statRow in statRows or {} do
		table.insert(rows, { label = statRow.label, value = statRow.value })
	end
	local bonusPercent = if pricing then math.floor(pricing.bonusPerStar * (gear.stars - 1) * 100 + 0.5) else 0
	local title = string.format(STATS_TITLE, gearName(gearSlot, gear.kind), gearRarityName(gear.stars))
	self:showInfo(title, gearPicture(gearSlot, gear.kind), rows, string.format(STATS_NOTE, bonusPercent))
end

function ClientCharacterSheetManager:fillRerollButton(button: GuiObject, price: number)
	local priceLabel = button:FindFirstChild(Constants.REROLL_BUTTON_PRICE_LABEL) :: TextLabel
	local priceIcon = button:FindFirstChild(Constants.REROLL_BUTTON_PRICE_ICON) :: ImageLabel
	priceLabel.Text = if price > 0 then utils.formatWithCommas(price) else UiStyle.formatTitle(FREE_TEXT)
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
		local kindLabel = card:FindFirstChild(Constants.GEAR_CARD_KIND_LABEL) :: TextButton
		kindLabel.Text = UiStyle.formatTitle(gearNameWithStars(gearSlot, gear.kind, gear.stars))
		local rarityLabel = card:FindFirstChild(Constants.GEAR_CARD_RARITY_LABEL) :: TextLabel
		rarityLabel.Text = UiStyle.formatTitle(gearRarityName(gear.stars))
		local gearColor = rarityColor(CharacterRules.rarityForStars(gear.stars))
		kindLabel.TextColor3 = gearColor
		rarityLabel.TextColor3 = gearColor
		local picture = card:FindFirstChild(Constants.GEAR_CARD_PICTURE) :: ImageButton
		picture.Image = gearPicture(gearSlot, gear.kind)
		-- the name and the picture open the stats page (designer, 2026-10-13)
		local function openStats()
			self:showGearStats(gearSlot, gear, pricing)
		end
		kindLabel.Activated:Connect(openStats)
		picture.Activated:Connect(openStats)
		local rerollButton = card:FindFirstChild(Constants.GEAR_CARD_REROLL_BUTTON) :: GuiButton
		self:fillRerollButton(rerollButton, if pricing then pricing.gearPriceDiamonds else 0)
		rerollButton.Activated:Connect(
			function()
				ClientNetManager:fireServer(NetEventNames.TRY_REROLL_GEAR, { characterId = character.id, gearSlot = gearSlot })
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
			rerollButton.Visible = true
			lockIcon.Visible = false
			self:fillRerollButton(rerollButton, if pricing then CharacterRules.skillRollPrice(pricing, skill == nil) else 0)
			rerollButton.Activated:Connect(
				function()
					ClientNetManager:fireServer(NetEventNames.TRY_REROLL_SKILL, { characterId = character.id, slot = slot })
				end
			)
		else
			nameLabel.Text = UiStyle.formatTitle(string.format(LOCKED_TEXT, unlockNights[slot] or 0))
			nameLabel.TextColor3 = UiStyle.TEXT_COLOR
			descriptionLabel.Visible = false
			rerollButton.Visible = false
			lockIcon.Visible = true
		end
		row.Parent = view.skillRows
	end
end

-- the items a slot's strip offers and what each is called: the hat row
-- is the catalogue (every hat counts as unlocked until M61 brings
-- ownership) then NONE, the player's own avatar hat; every other slot
-- offers its one default skin, the game's existing asset, until M61.
function ClientCharacterSheetManager:getCosmeticItems(slot: number): ({ string }, { [string]: string }, { [string]: string })
	local ids: { string } = {}
	local names: { [string]: string } = {}
	local pictures: { [string]: string } = {}
	if slot == Enums.CosmeticSlot.HELMET then
		local catalogue = CharacterRules.decodeHatCatalogue(ClientDataManager:getGameMetadata(Attributes.CHARACTER_HAT_CATALOGUE))
		for hatId, entry in catalogue do
			table.insert(ids, hatId)
			names[hatId] = entry.name
			pictures[hatId] = string.format(HAT_THUMBNAIL, entry.assetId)
		end
		table.insert(ids, OWN_HAT_ID)
		names[OWN_HAT_ID] = OWN_HAT_NAME
		pictures[OWN_HAT_ID] = Icons.UI.NO_HAT
	else
		table.insert(ids, DEFAULT_ITEM_ID)
		names[DEFAULT_ITEM_ID] = "Default"
		pictures[DEFAULT_ITEM_ID] = Icons.COSMETIC_DEFAULT_SKIN[slot] or Icons.COSMETIC_SLOT[slot] or ""
	end
	return ids, names, pictures
end

local function equippedCosmetic(cosmetics: { [string]: string }, slot: number): string
	local slotName = Enums.getName(Enums.CosmeticSlot, slot) :: string
	if slot == Enums.CosmeticSlot.HELMET then
		return cosmetics[slotName] or OWN_HAT_ID
	end
	return cosmetics[slotName] or DEFAULT_ITEM_ID
end

-- one row per cosmetic slot, each strip in the order the sheet opened
-- with (equipped first); built once per open, so a tap equips without
-- moving anything, and the next open leads with the new pick (designer,
-- 2026-10-13)
function ClientCharacterSheetManager:buildCosmeticRows(view: View, cosmetics: { [string]: string })
	for _, child in view.cosmeticRows:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.cosmeticRowTemplate then
			child:Destroy()
		end
	end
	self.cosmeticButtons = {}
	for order, slot in Constants.CHARACTER_SHEET_COSMETIC_SLOTS do
		local row = view.cosmeticRowTemplate:Clone()
		row.Name = Enums.getName(Enums.CosmeticSlot, slot) :: string
		row.LayoutOrder = order
		row.Visible = true
		local typeBox = row:FindFirstChild(Constants.COSMETIC_ROW_TYPE_BOX) :: GuiObject
		local typeIcon = typeBox:FindFirstChild(Constants.COSMETIC_ROW_TYPE_ICON) :: ImageLabel
		typeIcon.Image = Icons.COSMETIC_SLOT[slot] or ""
		local typeLabel = typeBox:FindFirstChild(Constants.COSMETIC_ROW_TYPE_LABEL) :: TextLabel
		typeLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.CosmeticSlot, slot) or "")
		local items = row:FindFirstChild(Constants.COSMETIC_ROW_ITEMS) :: ScrollingFrame
		local itemTemplate = items:FindFirstChild(Constants.COSMETIC_ROW_ITEM_TEMPLATE) :: ImageButton
		local ids, names, pictures = self:getCosmeticItems(slot)
		local ordered = CharacterRules.cosmeticItemOrder(
			ids,
			equippedCosmetic(cosmetics, slot),
			function(id)
				return names[id] or id
			end,
			if slot == Enums.CosmeticSlot.HELMET then OWN_HAT_ID else nil
		)
		local buttons: { [string]: ImageButton } = {}
		for itemOrder, itemId in ordered do
			local button = itemTemplate:Clone()
			button.Name = itemId
			button.LayoutOrder = itemOrder
			button.Visible = true
			button.Image = pictures[itemId] or ""
			-- every item is a real pick, the default skin included
			button.Activated:Connect(
				function()
					if self.characterId then
						ClientNetManager:fireServer(NetEventNames.TRY_SET_COSMETIC, { characterId = self.characterId, slot = slot, skinId = itemId })
					end
				end
			)
			button.Parent = items
			buttons[itemId] = button
		end
		self.cosmeticButtons[slot] = buttons
		-- the strip starts just after the square type box, whose width is
		-- the row's height; a scale width cannot express that, so it is
		-- measured once the row is on screen
		local function fitStrip()
			local rowWidth = row.AbsoluteSize.X
			if rowWidth <= 0 then
				return
			end
			local boxRight = typeBox.AbsolutePosition.X + typeBox.AbsoluteSize.X - row.AbsolutePosition.X
			local gap = rowWidth * 0.01
			local right = rowWidth * 0.99
			items.Size = UDim2.fromScale(math.max((right - boxRight - gap) / rowWidth, 0.1), items.Size.Y.Scale)
		end
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitStrip)
		row.Parent = view.cosmeticRows
		fitStrip()
	end
end

-- the equipped item in every strip wears the accent stroke; the strips
-- themselves are built once per open
function ClientCharacterSheetManager:renderCosmetics(view: View, cosmetics: { [string]: string })
	if next(self.cosmeticButtons) == nil then
		self:buildCosmeticRows(view, cosmetics)
	end
	for slot, buttons in self.cosmeticButtons do
		local equipped = equippedCosmetic(cosmetics, slot)
		for itemId, button in buttons do
			local stroke = button:FindFirstChild(Constants.COSMETIC_ITEM_SELECTED_STROKE) :: UIStroke
			stroke.Enabled = itemId == equipped
		end
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
	view.diamondLabel.Text = utils.formatWithCommas(ClientDataManager:getDiamonds())
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
	self:renderCosmetics(view, character.cosmetics)
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
	-- with an icon nothing flips over it (the star numeral rides in the
	-- name since 2026-10-13); with none (skills, until their icons exist)
	-- the name itself flips in the icon area
	spin.Visible = content.icon == ""
	nameLabel.Text = UiStyle.formatTitle(content.name)
	detail.Text = content.detail
	local color = if content.rarity then rarityColor(content.rarity) else UiStyle.TEXT_MUTED_COLOR
	nameLabel.TextColor3 = color
	detail.TextColor3 = color
	nameLabel.Visible = isRevealed
	detail.Visible = isRevealed
end

-- green when the candidate is better, red when worse, muted when the same
local function directionColor(before: number?, after: number?, isLowerBetter: boolean): Color3
	if before == nil or after == nil or before == after then
		return UiStyle.TEXT_MUTED_COLOR
	end
	local isBetter = if isLowerBetter then after < before else after > before
	return if isBetter then UiStyle.POSITIVE_COLOR else UiStyle.NEGATIVE_COLOR
end

-- the number at the front of a stat as shown ("1.7/s", "300 studs", "+20%")
local function leadingNumber(value: string): number?
	return tonumber(value:match("^[-+]?%d+%.?%d*"))
end

-- the stats panel beside the boxes: every stat the current item or the
-- candidate has, as the current value then the candidate's, coloured by
-- direction, with the Rank line at its foot (designer, 2026-10-13)
function ClientCharacterSheetManager:showComparison(current: BoxContent, candidate: BoxContent)
	local view = self.view
	if not view then
		return
	end
	for _, child in view.statRows:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.statRowTemplate then
			child:Destroy()
		end
	end
	local currentByLabel: { [string]: StatLine } = {}
	local candidateByLabel: { [string]: StatLine } = {}
	local labels: { string } = {}
	for _, line in current.stats do
		currentByLabel[line.label] = line
		table.insert(labels, line.label)
	end
	for _, line in candidate.stats do
		candidateByLabel[line.label] = line
		if not currentByLabel[line.label] then
			table.insert(labels, line.label)
		end
	end
	-- two kinds that share few stats make a long union, so the rows share
	-- the frame out rather than running into the Rank line
	local layout = view.statRows:FindFirstChildOfClass("UIListLayout")
	local paddingScale: number = if layout then layout.Padding.Scale else 0
	local templateHeight: number = view.statRowTemplate.Size.Y.Scale
	local fitHeight: number = (1 - paddingScale * math.max(#labels - 1, 0)) / math.max(#labels, 1)
	local rowHeight: number = math.min(templateHeight, fitHeight)
	for order, label in labels do
		local before = currentByLabel[label]
		local after = candidateByLabel[label]
		local row = view.statRowTemplate:Clone()
		row.Name = "Row" .. tostring(order)
		row.LayoutOrder = order
		row.Visible = true
		row.Size = UDim2.fromScale(view.statRowTemplate.Size.X.Scale, rowHeight)
		local rowLabel = row:FindFirstChild(Constants.OFFER_STAT_ROW_LABEL) :: TextLabel
		rowLabel.Text = UiStyle.formatTitle(label)
		local currentValue = row:FindFirstChild(Constants.OFFER_STAT_ROW_CURRENT) :: TextLabel
		currentValue.Text = if before then before.value else MISSING_STAT_TEXT
		local newValue = row:FindFirstChild(Constants.OFFER_STAT_ROW_NEW) :: TextLabel
		newValue.Text = if after then after.value else MISSING_STAT_TEXT
		local beforeNumber = if before then (before.number or leadingNumber(before.value)) else nil
		local afterNumber = if after then (after.number or leadingNumber(after.value)) else nil
		newValue.TextColor3 = directionColor(beforeNumber, afterNumber, LOWER_IS_BETTER_LABELS[label] == true)
		row.Parent = view.statRows
	end
	view.offerRank.Text = UiStyle.formatTitle(string.format(RANK_CHANGE_TEXT, current.rank, candidate.rank))
	view.offerRank.TextColor3 = directionColor(current.rank, candidate.rank, false)
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
	for _, part in self.hiddenForRoll do
		part.Visible = true
	end
	table.clear(self.hiddenForRoll)
end

-- everything on the dialog but the roll screen goes away while it shows
function ClientCharacterSheetManager:hideSheetForRoll(view: View)
	for _, child in view.dialog:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.offerDialog and child.Visible then
			child.Visible = false
			table.insert(self.hiddenForRoll, child)
		end
	end
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
	self:showComparison(current, result)
	view.offerKeep.Visible = false
	view.offerUndo.Visible = false
	self:hideSheetForRoll(view)
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
				ClientSoundManager:playSfx(SoundNames.Sfx.REROLL_SPIN)
				self:showComparison(current, candidates[index])
				task.wait(step)
				step *= SPIN_STEP_GROWTH
			end
			if self.rollGeneration ~= generation then
				return
			end
			fillBox(view.newBox, result, true)
			self:showComparison(current, result)
			ClientSoundManager:playSfx(SoundNames.Sfx.REROLL_REVEAL)
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
	local statsByKind = self:getGearStats()[gearSlot] or {}
	local function boxFor(kind: number, stars: number): BoxContent
		local stats: { StatLine } = {}
		local kindRows: { GearStatsRules.StatRow } = statsByKind[kind] or {}
		for _, statRow in kindRows do
			table.insert(stats, { label = statRow.label, value = statRow.value })
		end
		local bonusPercent = if pricing then math.floor(pricing.bonusPerStar * (stars - 1) * 100 + 0.5) else 0
		table.insert(stats, { label = RARITY_BONUS_LABEL, value = string.format("+%d%%", bonusPercent), number = bonusPercent })
		return {
			icon = gearPicture(gearSlot, kind),
			spinText = "",
			name = gearNameWithStars(gearSlot, kind, stars),
			detail = gearRarityName(stars),
			rank = self:rankWith(character, gearSlot, stars, nil, nil),
			rarity = CharacterRules.rarityForStars(stars),
			stats = stats,
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
			stats = if skillId then { { label = RARITY_LABEL, value = CharacterRules.rarityName(rarity or 0), number = rarity } } else {},
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
	-- the strips are rebuilt so each opens with the equipped item first
	self.cosmeticButtons = {}
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
	self:closeInfo()
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
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in (2026-10-13)
	local gui = playerGui:WaitForChild(Constants.CHARACTER_SHEET_GUI_NAME, Constants.GUI_WAIT_SEC)
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
	local statsPanel = findChild(offerDialog, Constants.OFFER_STATS_PANEL)
	local statRows = findChild(statsPanel, Constants.OFFER_STAT_ROWS)
	local cosmeticsPage = findChild(rightPanel, Constants.CHARACTER_SHEET_COSMETICS_PAGE)
	local cosmeticRows = findChild(cosmeticsPage, Constants.CHARACTER_SHEET_COSMETIC_ROWS)
	local infoDialog = findChild(dialog, Constants.CHARACTER_SHEET_INFO_DIALOG)
	local infoRows = findChild(infoDialog, Constants.INFO_DIALOG_ROWS)
	local parts = {
		backButton = findChild(dialog, Constants.CHARACTER_SELECT_BACK_BUTTON),
		diamondLabel = findChild(wallet, Constants.HUD_DIAMOND_AMOUNT_LABEL),
		nameLabel = findChild(leftPanel, Constants.CHARACTER_SHEET_NAME_LABEL),
		nameBox = findChild(leftPanel, Constants.CHARACTER_SHEET_NAME_BOX),
		renameButton = findChild(leftPanel, Constants.CHARACTER_SHEET_RENAME_BUTTON),
		avatar = findChild(leftPanel, Constants.CHARACTER_CARD_AVATAR),
		rankLabel = findChild(leftPanel, Constants.CHARACTER_CARD_RANK_LABEL),
		rankInfoButton = findChild(leftPanel, Constants.CHARACTER_SHEET_RANK_INFO_BUTTON),
		oddsButton = findChild(dialog, Constants.CHARACTER_SHEET_ODDS_BUTTON),
		nightsLabel = findChild(leftPanel, Constants.CHARACTER_CARD_NIGHTS_LABEL),
		loadoutTab = findChild(rightPanel, Constants.CHARACTER_SHEET_LOADOUT_TAB),
		cosmeticsTab = findChild(rightPanel, Constants.CHARACTER_SHEET_COSMETICS_TAB),
		loadoutPage = loadoutPage,
		cosmeticsPage = cosmeticsPage,
		cosmeticRows = cosmeticRows,
		cosmeticRowTemplate = findChild(cosmeticRows, Constants.CHARACTER_SHEET_COSMETIC_ROW_TEMPLATE),
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
		offerRank = findChild(statsPanel, Constants.OFFER_RANK_LABEL),
		statsPanel = statsPanel,
		statRows = statRows,
		statRowTemplate = findChild(statRows, Constants.OFFER_STAT_ROW_TEMPLATE),
		infoDialog = infoDialog,
		infoTitle = findChild(infoDialog, Constants.INFO_DIALOG_TITLE),
		infoPicture = findChild(infoDialog, Constants.INFO_DIALOG_PICTURE),
		infoRows = infoRows,
		infoRowTemplate = findChild(infoRows, Constants.INFO_DIALOG_ROW_TEMPLATE),
		infoNote = findChild(infoDialog, Constants.INFO_DIALOG_NOTE),
		infoClose = findChild(infoDialog, Constants.INFO_DIALOG_CLOSE_BUTTON),
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
	view.statRowTemplate.Visible = false
	view.infoDialog.Visible = false
	view.infoRowTemplate.Visible = false
	view.nameBox.Visible = false
	view.cosmeticRowTemplate.Visible = false

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
	view.infoClose.Activated:Connect(
		function()
			self:closeInfo()
		end
	)
	view.oddsButton.Activated:Connect(
		function()
			self:showAllOdds()
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
			self:closeInfo()
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
	self.cosmeticButtons = {}
	self.onBack = nil
	self.offerConnections = {}
	self.rollGeneration = 0
	self.hiddenForRoll = {}
	return self
end

return ClientCharacterSheetManager.new()
