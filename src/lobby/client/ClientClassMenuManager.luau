--!strict

-- The Class Menu (GDD "Classes", the Class Equip Menu of 2026-11-04,
-- which replaced the Character Select Menu and the Character Sheet of
-- M37): opened from the HUD's Classes button. On the left, one button per
-- class the catalogue lists (its icon and name; a locked one greyed with
-- a lock), any of which can be tapped to look at; on the right the info
-- panel for the selected class: its name, its three stars (one gold per
-- gacha tier earned), its icon, one sentence, the four kit slots (a tap
-- opens the item's tooltip), the three perk rows (locked ones name the
-- stars needed; open ones roll in place: the row's words scroll through
-- the catalogue like a slot reel and stop on the result, then KEEP or X,
-- the first roll into an empty slot free and final), ODDS, and EQUIP.
-- Everything drawn is
-- replicated already (the class catalogue, skill catalogue, and reroll
-- pricing as GameMetadata; the class records, class in play, and class
-- progress on CurrentPlayer); the menu sends TrySelectClass,
-- TryRerollSkill, and TryResolveSkillRoll.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local ClassCatalogueRules = require("@game/ReplicatedStorage/Shared/ClassCatalogueRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SkillRules = require("@game/ReplicatedStorage/Shared/SkillRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientGuiFade = require(script.Parent.Parent.Client.ClientGuiFade)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientTicker = require(script.Parent.Parent.Client.ClientTicker)
local ClientDiamondStoreManager = require(script.Parent.ClientDiamondStoreManager)
local ClientGachaMenuManager = require(script.Parent.ClientGachaMenuManager)

local ClientClassMenuManager = {}
ClientClassMenuManager.__index = ClientClassMenuManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	equippedIcon: ImageLabel,
	equippedTitle: TextLabel,
	classList: GuiObject,
	classButtonTemplate: GuiButton,
	nameLabel: TextLabel,
	stars: { TextLabel },
	icon: ImageLabel,
	descriptionLabel: TextLabel,
	kitRow: GuiObject,
	kitSlotTemplate: GuiButton,
	perkRows: GuiObject,
	perkRowTemplate: GuiObject,
	oddsButton: GuiButton,
	equipButton: GuiButton,
	supplyCrateButton: GuiButton,
	-- the restricted player's plates, both roads to the rotating store;
	-- nil on a gui without them
	rotatingStoreButton: GuiButton?,
	upgradeButton: GuiButton?,
	infoDialog: GuiObject,
	infoTitle: TextLabel,
	infoPicture: ImageLabel,
	infoRows: GuiObject,
	infoRowTemplate: GuiObject,
	infoNote: TextLabel,
	infoClose: GuiButton,
}

-- one entry of a perk row's words: a skill, or the empty slot
type ReelEntry = {
	name: string,
	nameColor: Color3,
	description: string,
}

-- the roll in flight on one perk row
type ActiveRoll = {
	classKind: number,
	slot: number,
	row: Instance,
	-- a free roll into an empty slot landed on the server already: the
	-- reel is show and no Keep or X follows
	isFinal: boolean,
	isLanded: boolean,
}

type InfoRow = {
	label: string,
	value: string,
	color: Color3?,
}

-- one of the four kit slots, in the order the panel shows them
type KitSlot = {
	key: string,
	label: string,
	icons: { [number]: string },
	enum: any,
	-- the kind that means the class has nothing in this slot (the
	-- Recruit's gadget); the row then shows neither icon nor name
	emptyKind: number?,
}

export type ClientClassMenuManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		-- the class the info panel shows; the class in play when the menu opens
		selectedClassKind: number,
		-- the list's order, fixed when the menu opens (the class in play,
		-- the owned, the locked) so an equip never reshuffles it
		listCatalogue: ClassCatalogueRules.Catalogue?,
		-- the roll in flight; a new roll or a close bumps the generation so
		-- a reel still turning stops, and its connections go with it
		activeRoll: ActiveRoll?,
		rollGeneration: number,
		rollConnections: { RBXScriptConnection },
		-- the connections of the cloned buttons, dropped on every redraw
		cloneConnections: { RBXScriptConnection },
		-- the labels counting down to a restricted player's next free
		-- roll, rebuilt with the perk rows and written once a second
		freeRollTimers: { { label: TextLabel, endTime: number, format: string } },
		listPaddingTopScale: number?,
		listGapScale: number?,
		-- the class the EQUIPPED CLASS box last showed, nil on opening so
		-- the first draw never flashes; a counter drops a fade a newer
		-- flash outran
		equippedShownKind: number?,
		equippedFlashGeneration: number,
		-- the class in play as last seen, so a change plays the equip sound
		knownActiveClassKind: number?,
	},
	ClientClassMenuManager
))

local KIT_SLOTS: { KitSlot } = {
	{ key = "post", label = "Post Weapon", icons = Icons.POST_WEAPON, enum = Enums.PostWeaponKind },
	{ key = "weapon", label = "Weapon", icons = Icons.WEAPON, enum = Enums.WeaponKind },
	{ key = "tower", label = "Tower", icons = Icons.TOWER_KIND, enum = Enums.TowerKind },
	{ key = "gadget", label = "Gadget", icons = Icons.GADGET, enum = Enums.GadgetKind, emptyKind = Enums.GadgetKind.NONE },
}

local EMPTY_PERK_TEXT = "Empty slot"
local EMPTY_PERK_DESCRIPTION = "Roll a perk"
-- a locked perk row reads only this line, "UNLOCKED AT 2 [star]"
-- (designer, 2026-11-05)
local UNLOCKED_AT_FORMAT = "Unlocked at %d " .. utf8.char(0x2605)
local ROLL_TEXT = "Roll"
local REROLL_TEXT = "Reroll"
local KEEP_TEXT = "Keep"
local FREE_ROLL_TIMER_INTERVAL_SEC = 1
-- an offered skill's description, the skill it would replace, and the
-- countdown to the offer's end (the last %s, filled every second)
local OFFER_DESCRIPTION_FORMAT = "%s\nReplaces %s. Offer ends in %%s"
local FREE_TEXT = "Free"
local EQUIP_TEXT = "Equip"
local EQUIPPED_TEXT = "Equipped"
local LOCKED_CLASS_TEXT = "Locked"
-- the designer's black word on the Equip plate
local EQUIP_WORD_COLOR = Color3.new(0, 0, 0)
-- the EQUIPPED CLASS box's name turns green when the class in play changes,
-- holds, then fades back to white (designer, 2026-11-05)
local EQUIPPED_FLASH_HOLD_SEC = 3
local EQUIPPED_FLASH_FADE_SEC = 0.5
local ODDS_TEXT = "Reroll odds"
-- the Odds plate on an owned class with no star yet: no slot is open to
-- roll, so the plate sends the player to the Supply Crates instead
-- (designer, 2026-11-05)
local STAR_UP_TEXT = "Draw a duplicate from Supply Crates to increase star rating"
local ODDS_TITLE = "Perk odds"
local ODDS_NOTE = "Every perk roll draws one skill from the catalogue; each rarity's share is its skills over the whole."
local ODDS_ROUNDING_NOTE = " Shares are rounded, so they may not add to exactly 100%."
local LOCKED_CLASS_FEEDBACK = "Open Supply Crates to unlock this class"
local LOCKED_CLASS_FEEDBACK_SEC = 3
-- the reel (designer, 2026-11-05, after Lucky Squares' strip but vertical
-- and words only): the rolled row's SkillText clips a column of entries,
-- the skill it had first and the result last, scrolled up fast and slowing
-- to a stop over REEL_SPIN_SEC
local REEL_CANDIDATE_COUNT = 10
local REEL_SPIN_SEC = 2.4
local REEL_TWEEN_INFO = TweenInfo.new(REEL_SPIN_SEC, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local REEL_FRAME_NAME = "Reel"
local PERK_ROW_NAME_FORMAT = "Perk%d"
-- the Reroll button fades out once the purchase has gone through
local REROLL_FADE_SEC = 0.3
-- the beat between the reel stopping and KEEP and X appearing
local SPIN_REVEAL_DELAY_SEC = 0.35
-- a locked class button's icon and name
local LOCKED_ICON_COLOR = Color3.fromRGB(90, 90, 90)
local LOCKED_NAME_COLOR = UiStyle.DISABLED_COLOR

local function rarityColor(rarity: number?): Color3
	return (if rarity then UiStyle.RARITY_COLORS[rarity] else nil) or UiStyle.TEXT_COLOR
end

local function skillTitle(entry: SkillRules.SkillCatalogueEntry?, skillId: string, rarity: number): string
	local name = if entry then entry.name else skillId
	return UiStyle.formatTitle(name .. " - " .. SkillRules.rarityName(rarity))
end

local function clearClones(parent: GuiObject, template: GuiObject)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child ~= template then
			child:Destroy()
		end
	end
end

local function setLabel(parent: Instance, name: string, text: string, color: Color3?)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
		if color then
			label.TextColor3 = color
		end
	end
end

local function setVisible(parent: Instance, name: string, isVisible: boolean)
	local child = parent:FindFirstChild(name)
	if child and child:IsA("GuiObject") then
		child.Visible = isVisible
	end
end

-- the frame a perk row's words live in (the row itself for an older copy)
local function skillTextOf(row: Instance): Instance
	return row:FindFirstChild(Constants.PERK_ROW_SKILL_TEXT) or row
end

local function fillSkillText(skillText: Instance, entry: ReelEntry)
	setLabel(skillText, Constants.PERK_ROW_NAME_LABEL, entry.name, entry.nameColor)
	setLabel(skillText, Constants.PERK_ROW_DESCRIPTION_LABEL, entry.description)
end

function ClientClassMenuManager:getCatalogue(): ClassCatalogueRules.Catalogue
	return ClassCatalogueRules.decode(ClientDataManager:getGameMetadata(Attributes.CLASS_CATALOGUE))
end

function ClientClassMenuManager:getSkillCatalogue(): SkillRules.SkillCatalogue
	return SkillRules.decodeSkillCatalogue(ClientDataManager:getGameMetadata(Attributes.SKILL_CATALOGUE))
end

function ClientClassMenuManager:getRerollPricing(): SkillRules.RerollPricing?
	return SkillRules.decodeRerollPricing(ClientDataManager:getGameMetadata(Attributes.SKILL_REROLL_PRICING))
end

-- the stars a class has earned (its gacha tiers: the skill slots open),
-- nil for a class not owned
function ClientClassMenuManager:starsOf(classKind: number): number?
	local className = Enums.getName(Enums.ClassKind, classKind)
	if not className then
		return nil
	end
	return ClientDataManager:getClassProgress()[className]
end

function ClientClassMenuManager:isOwned(classKind: number): boolean
	return self:starsOf(classKind) ~= nil
end

-- the info dialog: a title, an optional picture, rows, and a note. A kit
-- slot's tooltip is the title, the picture, and the note alone
function ClientClassMenuManager:showInfo(title: string, pictureId: string?, rows: { InfoRow }, note: string)
	local view = self.view
	if not view then
		return
	end
	clearClones(view.infoRows, view.infoRowTemplate)
	view.infoTitle.Text = UiStyle.formatTitle(title)
	local hasPicture = pictureId ~= nil and pictureId ~= ""
	view.infoPicture.Image = pictureId or ""
	view.infoPicture.Visible = hasPicture
	if view.infoRows:IsA("ScrollingFrame") then
		(view.infoRows :: ScrollingFrame).CanvasPosition = Vector2.zero
	end
	for index, infoRow in rows do
		local row = view.infoRowTemplate:Clone()
		row.Name = "Row" .. tostring(index)
		row.LayoutOrder = index
		row.Visible = true
		setLabel(row, Constants.INFO_ROW_LABEL, UiStyle.formatTitle(infoRow.label), infoRow.color or UiStyle.TEXT_COLOR)
		setLabel(row, Constants.INFO_ROW_VALUE, infoRow.value)
		row.Parent = view.infoRows
	end
	view.infoRows.Visible = #rows > 0
	view.infoNote.Text = note
	view.infoDialog.Visible = true
end

function ClientClassMenuManager:closeInfo()
	local view = self.view
	if view then
		view.infoDialog.Visible = false
	end
end

-- every perk roll's odds by rarity, on the panel before any roll is
-- bought, as Roblox's paid random items policy asks
function ClientClassMenuManager:showOdds()
	local odds = SkillRules.skillRarityOdds(self:getSkillCatalogue())
	local rows: { InfoRow } = {}
	for _, line in odds do
		table.insert(rows, { label = SkillRules.rarityName(line.rarity), value = SkillRules.percentText(line.percent), color = rarityColor(line.rarity) })
	end
	local note = ODDS_NOTE
	if not SkillRules.isOddsTotalExact(odds) then
		note ..= ODDS_ROUNDING_NOTE
	end
	self:showInfo(ODDS_TITLE, nil, rows, note)
end

function ClientClassMenuManager:addCloneConnection(connection: RBXScriptConnection)
	table.insert(self.cloneConnections, connection)
end

function ClientClassMenuManager:dropCloneConnections()
	for _, connection in self.cloneConnections do
		connection:Disconnect()
	end
	table.clear(self.cloneConnections)
end

-- the left column: one button per listed class (a locked one greyed under
-- its lock); the class in play is named in the EQUIPPED CLASS box under
-- the list, never marked on its button (designer, 2026-11-05)
function ClientClassMenuManager:renderClassList(view: View, catalogue: ClassCatalogueRules.Catalogue)
	clearClones(view.classList, view.classButtonTemplate)
	for order, entry in catalogue do
		local button = view.classButtonTemplate:Clone()
		button.Name = Enums.getName(Enums.ClassKind, entry.kind) or tostring(entry.kind)
		button.LayoutOrder = order
		button.Visible = true
		local isOwned = self:isOwned(entry.kind)
		local icon = button:FindFirstChild(Constants.CLASS_BUTTON_ICON)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = Icons.CLASS_KIND[entry.kind] or Icons.PLACEHOLDER
			icon.ImageColor3 = if isOwned then Color3.new(1, 1, 1) else LOCKED_ICON_COLOR
		end
		setLabel(button, Constants.CLASS_BUTTON_NAME_LABEL, UiStyle.formatTitle(Enums.getPublicName(Enums.ClassKind, entry.kind) or "?"), if isOwned then UiStyle.TEXT_COLOR else LOCKED_NAME_COLOR)
		setVisible(button, Constants.CLASS_BUTTON_LOCK_ICON, not isOwned)
		self:addCloneConnection(
			button.Activated:Connect(
				function()
					self:selectClass(entry.kind)
				end
			)
		)
		button.Parent = view.classList
	end
	self:fitListCanvas(view)
end

-- the list's canvas is sized here because AutomaticCanvasSize leaves out
-- children sized by scale (the same bug the gacha odds panel hit): the
-- layout's measured content height plus the padding, the padding turned
-- from the authored scale of the window into pixels so the canvas cannot
-- feed back into it
function ClientClassMenuManager:fitListCanvas(view: View)
	local list = view.classList
	if not list:IsA("ScrollingFrame") then
		return
	end
	local layout = list:FindFirstChildOfClass("UIListLayout")
	local padding = list:FindFirstChildOfClass("UIPadding")
	if not layout then
		return
	end
	local windowHeight = list.AbsoluteWindowSize.Y
	local paddingPx = 0
	if padding then
		local authoredTop: number = self.listPaddingTopScale or padding.PaddingTop.Scale
		self.listPaddingTopScale = authoredTop
		paddingPx = authoredTop * windowHeight
		padding.PaddingTop = UDim.new(0, paddingPx)
		padding.PaddingBottom = UDim.new(0, paddingPx)
	end
	-- the gap between rows is a scale of the canvas too, so it is pinned
	-- the same way (one button per row made the feedback plain, 2026-11-05)
	local authoredGap: number = self.listGapScale or layout.Padding.Scale
	self.listGapScale = authoredGap
	layout.Padding = UDim.new(0, authoredGap * windowHeight)
	list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + paddingPx * 2)
end

-- the four kit rows (the LOADOUT column): the item's icon, the slot
-- word, and the item's name, a tap opening the item's tooltip
function ClientClassMenuManager:renderKit(view: View, entry: ClassCatalogueRules.Entry)
	clearClones(view.kitRow, view.kitSlotTemplate)
	for order, slot in KIT_SLOTS do
		local kind = (entry.kit :: any)[slot.key] :: number
		local description = (entry.kitDescriptions :: any)[slot.key] :: string
		local itemName = Enums.getPublicName(slot.enum, kind) or "?"
		local iconId = slot.icons[kind] or ""
		local isEmpty = kind == slot.emptyKind
		local button = view.kitSlotTemplate:Clone()
		button.Name = slot.key
		button.LayoutOrder = order
		button.Visible = true
		local icon = button:FindFirstChild(Constants.KIT_SLOT_ICON)
		if icon and icon:IsA("ImageLabel") then
			-- an empty slot shows nothing; an item without art yet keeps
			-- its disc so the gap is visible
			icon.Image = iconId
			icon.Visible = not isEmpty
		end
		setLabel(button, Constants.KIT_SLOT_LABEL, UiStyle.formatTitle(slot.label))
		setLabel(button, Constants.KIT_SLOT_ITEM_LABEL, UiStyle.formatTitle(if isEmpty then "" else itemName))
		self:addCloneConnection(
			button.Activated:Connect(
				function()
					self:showInfo(itemName, iconId, {}, description)
				end
			)
		)
		button.Parent = view.kitRow
	end
end

-- a reroll button's word and price; a free roll says so with no icon
function ClientClassMenuManager:fillRerollButton(button: GuiObject, word: string, price: number)
	setLabel(button, Constants.REROLL_BUTTON_LABEL, UiStyle.formatTitle(word))
	setLabel(button, Constants.REROLL_BUTTON_PRICE_LABEL, if price > 0 then utils.formatWithCommas(price) else UiStyle.formatTitle(FREE_TEXT))
	setVisible(button, Constants.REROLL_BUTTON_PRICE_ICON, price > 0)
end

-- the three perk rows of the selected class: a slot past the class's
-- stars is locked and names the stars it needs (slot N opens with the
-- Nth tier), an open empty slot rolls free, a filled one rerolls for
-- Diamonds
function ClientClassMenuManager:renderPerkRows(view: View, classKind: number)
	-- a reel turning on this class's rows is left alone; the resolve
	-- redraws them
	local activeRoll = self.activeRoll
	if activeRoll and activeRoll.classKind == classKind then
		return
	end
	table.clear(self.freeRollTimers)
	local pricing = self:getRerollPricing()
	local record = ClientDataManager:getClassRecord(classKind)
	local stars = self:starsOf(classKind) or 0
	local slotCount = if pricing then pricing.maxSkillSlots else Constants.CLASS_INFO_STAR_COUNT
	for slot = 1, slotCount do
		-- a row made once and updated in place: recloning it after a reel
		-- landed drew the words once more from scratch, a visible flash
		-- (2026-11-06)
		local rowName = string.format(PERK_ROW_NAME_FORMAT, slot)
		local found = view.perkRows:FindFirstChild(rowName)
		local row: GuiObject
		if found and found:IsA("GuiObject") then
			row = found
		else
			row = view.perkRowTemplate:Clone()
			row.Name = rowName
			row.LayoutOrder = slot
			row.Parent = view.perkRows
		end
		row.Visible = true
		local isLocked = slot > stars
		local rerollButton = row:FindFirstChild(Constants.PERK_ROW_REROLL_BUTTON)
		setVisible(row, Constants.PERK_ROW_LOCK_ICON, isLocked)
		setVisible(row, Constants.PERK_ROW_REQUIREMENT_LABEL, isLocked)
		setVisible(row, Constants.PERK_ROW_KEEP_BUTTON, false)
		setVisible(row, Constants.PERK_ROW_CANCEL_BUTTON, false)
		if isLocked then
			fillSkillText(skillTextOf(row), { name = "", nameColor = UiStyle.TEXT_COLOR, description = "" })
			setLabel(row, Constants.PERK_ROW_REQUIREMENT_LABEL, UiStyle.formatTitle(string.format(UNLOCKED_AT_FORMAT, slot)))
			if rerollButton and rerollButton:IsA("GuiObject") then
				rerollButton.Visible = false
			end
			continue
		end
		local skill = record.skills[tostring(slot)]
		fillSkillText(skillTextOf(row), self:reelEntryFor(if skill then skill.skillId else nil, if skill then skill.rarity else nil))
		self:showRerollButton(row, classKind, slot, skill == nil)
	end
end

-- an open row's Reroll button, worded and priced for the slot's state; a
-- button a roll faded out comes back the same way. Called by the redraw
-- and by a kept roll, since a roll that lands on the skill the slot
-- already held changes no data and so brings no redraw (2026-11-06)
function ClientClassMenuManager:showRerollButton(row: Instance, classKind: number, slot: number, isEmpty: boolean)
	local rerollButton = row:FindFirstChild(Constants.PERK_ROW_REROLL_BUTTON)
	if not rerollButton or not rerollButton:IsA("GuiButton") then
		return
	end
	local pricing = self:getRerollPricing()
	local wasHidden = not rerollButton.Visible
	rerollButton.Visible = pricing ~= nil
	rerollButton.Interactable = true
	if wasHidden and rerollButton.Visible then
		ClientGuiFade.fadeIn(rerollButton, REROLL_FADE_SEC)
	end
	if not pricing then
		return
	end
	-- a player restricted from paid random items rerolls a filled slot
	-- free once a day and pays only to keep what came up
	if not isEmpty and ClientDataManager:isPaidRandomItemsRestricted() then
		self:showFreeRollButton(row, rerollButton, classKind, slot, pricing)
		return
	end
	local price = SkillRules.skillRollPrice(pricing, isEmpty)
	self:fillRerollButton(rerollButton, if isEmpty then ROLL_TEXT else REROLL_TEXT, price)
	self:addCloneConnection(
		rerollButton.Activated:Connect(
			function()
				self:requestRoll(classKind, slot, price)
			end
		)
	)
end

-- the restricted player's row (designer, 2026-11-10), in one of three
-- states read from the slot's saved free roll: the roll is ready (REROLL,
-- FREE); an offer stands (the row shows the offered skill, what it would
-- replace, and a countdown to the offer's end, and the button is KEEP
-- with the rarity's Diamond price); or the offer was kept or never came
-- and the next roll is still to come (the button dimmed, counting down)
function ClientClassMenuManager:showFreeRollButton(row: Instance, button: GuiButton, classKind: number, slot: number, pricing: SkillRules.RerollPricing)
	local record = ClientDataManager:getClassRecord(classKind)
	local freeRoll = if record.freeRolls then record.freeRolls[tostring(slot)] else nil
	local state = SkillRules.freeRollState(freeRoll, workspace:GetServerTimeNow(), pricing.freeRollIntervalSec)
	if state.canRoll then
		self:fillRerollButton(button, REROLL_TEXT, 0)
		self:addCloneConnection(
			button.Activated:Connect(
				function()
					self:requestRoll(classKind, slot, 0)
				end
			)
		)
		return
	end
	local offer = state.offer
	if not offer then
		self:fillRerollButton(button, REROLL_TEXT, 0)
		button.Interactable = false
		local priceLabel = button:FindFirstChild(Constants.REROLL_BUTTON_PRICE_LABEL)
		if priceLabel and priceLabel:IsA("TextLabel") then
			self:addFreeRollTimer(priceLabel, state.nextRollTime, "%s")
		end
		return
	end
	local held = record.skills[tostring(slot)]
	local heldEntry = self:reelEntryFor(if held then held.skillId else nil, if held then held.rarity else nil)
	local offerEntry = self:reelEntryFor(offer.skillId, offer.rarity)
	local skillText = skillTextOf(row)
	fillSkillText(skillText, offerEntry)
	local descriptionLabel = skillText:FindFirstChild(Constants.PERK_ROW_DESCRIPTION_LABEL)
	if descriptionLabel and descriptionLabel:IsA("TextLabel") then
		-- the words are data, so a % in them must not read as a format
		local description = string.gsub(offerEntry.description, "%%", "%%%%")
		local heldName = string.gsub(heldEntry.name, "%%", "%%%%")
		self:addFreeRollTimer(descriptionLabel, state.nextRollTime, string.format(OFFER_DESCRIPTION_FORMAT, description, heldName))
	end
	local price = SkillRules.keepPrice(pricing, offer.rarity) or 0
	self:fillRerollButton(button, KEEP_TEXT, price)
	self:addCloneConnection(
		button.Activated:Connect(
			function()
				self:requestKeep(classKind, slot, price)
			end
		)
	)
end

-- a label that counts down to a slot's next free roll: written now and
-- then once a second by the ticker (stepFreeRollTimers)
function ClientClassMenuManager:addFreeRollTimer(label: TextLabel, endTime: number, format: string)
	table.insert(self.freeRollTimers, { label = label, endTime = endTime, format = format })
	label.Text = string.format(format, SkillRules.formatCountdown(endTime - workspace:GetServerTimeNow()))
end

function ClientClassMenuManager:stepFreeRollTimers()
	if not self.isOpen or #self.freeRollTimers == 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	local hasExpired = false
	for _, timer in self.freeRollTimers do
		timer.label.Text = string.format(timer.format, SkillRules.formatCountdown(timer.endTime - now))
		if now >= timer.endTime then
			hasExpired = true
		end
	end
	if hasExpired then
		-- a wait ran out: the row is redrawn into its ready state (the
		-- list is cleared first so a skipped redraw cannot loop)
		table.clear(self.freeRollTimers)
		self:render()
	end
end

-- KEEP on a standing offer: judged here first so a short balance never
-- makes a round trip; the server checks the offer and the price again
function ClientClassMenuManager:requestKeep(classKind: number, slot: number, price: number)
	local diamonds = ClientDataManager:getDiamonds()
	if price > diamonds then
		ClientDiamondStoreManager:handleDiamondsShort(price, diamonds)
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.SALE_SUCCESS)
	ClientNetManager:fireServer(NetEventNames.TRY_KEEP_SKILL_OFFER, {
		classKind = classKind,
		slot = slot,
	})
end

-- a roll the menu already knows the price of: a short balance is handled
-- here, with no round trip
function ClientClassMenuManager:requestRoll(classKind: number, slot: number, price: number)
	local diamonds = ClientDataManager:getDiamonds()
	if price > diamonds then
		ClientDiamondStoreManager:handleDiamondsShort(price, diamonds)
		return
	end
	ClientSoundManager:playSfx(SoundNames.Sfx.REROLL)
	ClientNetManager:fireServer(NetEventNames.TRY_REROLL_SKILL, {
		classKind = classKind,
		slot = slot,
	})
end

-- a row's words for a skill, or for the empty slot
function ClientClassMenuManager:reelEntryFor(skillId: string?, rarity: number?): ReelEntry
	if not skillId then
		return {
			name = UiStyle.formatTitle(EMPTY_PERK_TEXT),
			nameColor = UiStyle.TEXT_MUTED_COLOR,
			description = EMPTY_PERK_DESCRIPTION,
		}
	end
	local entry = self:getSkillCatalogue()[skillId]
	return {
		name = skillTitle(entry, skillId, rarity or 0),
		nameColor = rarityColor(rarity),
		description = if entry then entry.description else "",
	}
end

-- the box's name goes green at once, holds, then eases back to white; a
-- newer flash during the hold wins through the generation
function ClientClassMenuManager:flashEquippedTitle(view: View)
	self.equippedFlashGeneration += 1
	local generation = self.equippedFlashGeneration
	view.equippedTitle.TextColor3 = UiStyle.POSITIVE_COLOR
	task.delay(
		EQUIPPED_FLASH_HOLD_SEC,
		function()
			if generation ~= self.equippedFlashGeneration or not self.isOpen then
				return
			end
			TweenService:Create(view.equippedTitle, TweenInfo.new(EQUIPPED_FLASH_FADE_SEC), { TextColor3 = UiStyle.TEXT_COLOR }):Play()
		end
	)
end

-- the EQUIPPED CLASS box under the list: the class in play, whatever the
-- panel is looking at. render runs on every class-data change, so an
-- equip moves it at once, flashing the name green
function ClientClassMenuManager:renderEquippedClass(view: View)
	local activeKind = ClientDataManager:getActiveClassKind()
	view.equippedIcon.Image = Icons.CLASS_KIND[activeKind] or Icons.PLACEHOLDER
	view.equippedTitle.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.ClassKind, activeKind) or "?")
	if self.equippedShownKind ~= nil and self.equippedShownKind ~= activeKind then
		self:flashEquippedTitle(view)
	end
	self.equippedShownKind = activeKind
end

-- the right column for the selected class
function ClientClassMenuManager:renderInfo(view: View, entry: ClassCatalogueRules.Entry)
	local classKind = entry.kind
	local stars = self:starsOf(classKind)
	local isOwned = stars ~= nil
	view.nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.ClassKind, classKind) or "?")
	for index, star in view.stars do
		star.TextColor3 = if index <= (stars or 0) then UiStyle.CLASS_CARD_STAR_GOLD_COLOR else UiStyle.CLASS_MENU_STAR_DARK_COLOR
	end
	view.icon.Image = Icons.CLASS_KIND[classKind] or Icons.PLACEHOLDER
	view.descriptionLabel.Text = entry.description
	self:renderKit(view, entry)
	self:renderPerkRows(view, classKind)

	local isActive = classKind == ClientDataManager:getActiveClassKind()
	local word = if isActive then EQUIPPED_TEXT elseif isOwned then EQUIP_TEXT else LOCKED_CLASS_TEXT
	-- the word lives on the button's TextLabel child; the colour is the
	-- plate's tint on the designer's ImageButton. On the class in play the
	-- plate goes clear and the word takes its green (designer, 2026-11-05)
	local wordColor = if isActive then UiStyle.POSITIVE_COLOR else EQUIP_WORD_COLOR
	setLabel(view.equipButton, Constants.EQUIP_BUTTON_LABEL, UiStyle.formatTitle(word), wordColor)
	local color = if isOwned and not isActive then UiStyle.POSITIVE_COLOR else UiStyle.DISABLED_COLOR
	if view.equipButton:IsA("ImageButton") then
		view.equipButton.ImageColor3 = color
		view.equipButton.ImageTransparency = if isActive then 1 else 0
	else
		view.equipButton.BackgroundColor3 = color
		view.equipButton.BackgroundTransparency = if isActive then 1 else 0
	end
	view.equipButton.AutoButtonColor = isOwned and not isActive

	-- a locked class shows the one Supply Crate plate where Odds and Equip
	-- stand; an owned class with no star has its Odds plate send the
	-- player there too (designer, 2026-11-05)
	-- a player restricted from paid random items has no crate and no
	-- random reroll odds to read (designer, 2026-11-10): a locked class
	-- shows the Rotating Store plate alone, an owned one the Upgrade
	-- plate where Odds stands, and both lead to the rotating store,
	-- where class cards are bought
	local isRestricted = ClientDataManager:isPaidRandomItemsRestricted()
	view.supplyCrateButton.Visible = not isOwned and not isRestricted
	view.oddsButton.Visible = isOwned and not isRestricted
	view.equipButton.Visible = isOwned
	local rotatingStoreButton = view.rotatingStoreButton
	if rotatingStoreButton then
		rotatingStoreButton.Visible = isRestricted and not isOwned
	end
	local upgradeButton = view.upgradeButton
	if upgradeButton then
		upgradeButton.Visible = isRestricted and isOwned
	end
	local isStarUp = self:isOddsStarUp(classKind)
	local oddsText = if isStarUp then STAR_UP_TEXT else ODDS_TEXT
	setLabel(view.oddsButton, Constants.EQUIP_BUTTON_LABEL, UiStyle.formatTitle(oddsText))
	local oddsColor = if isStarUp then UiStyle.SUPPLY_CRATE_BUTTON_COLOR else UiStyle.ODDS_BUTTON_COLOR
	if view.oddsButton:IsA("ImageButton") then
		view.oddsButton.ImageColor3 = oddsColor
	else
		view.oddsButton.BackgroundColor3 = oddsColor
	end
end

-- an owned class with no star has no slot open, so its Odds plate is a
-- road to the Supply Crates until the first star
function ClientClassMenuManager:isOddsStarUp(classKind: number): boolean
	local stars = self:starsOf(classKind)
	return stars ~= nil and stars <= 0
end

-- the Supply Crate plate, and the Odds plate in its star-up state: this
-- menu closes and the Supply Crate stall's menu opens in its place (one
-- overlay at a time, so the close must come first)
function ClientClassMenuManager:openSupplyCrates()
	self:closeMenu()
	ClientGachaMenuManager:openMenu()
end

function ClientClassMenuManager:onOddsActivated()
	if self:isOddsStarUp(self.selectedClassKind) then
		self:openSupplyCrates()
	else
		self:showOdds()
	end
end

function ClientClassMenuManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	local catalogue = self:getCatalogue()
	if #catalogue == 0 then
		warn("ClientClassMenuManager: no class catalogue in GameMetadata yet")
		return
	end
	local entry = ClassCatalogueRules.findEntry(catalogue, self.selectedClassKind) or catalogue[1]
	self.selectedClassKind = entry.kind
	self:dropCloneConnections()
	self:renderClassList(view, self.listCatalogue or catalogue)
	self:renderEquippedClass(view)
	self:renderInfo(view, entry)
end

-- the list order for this opening of the menu
function ClientClassMenuManager:buildListCatalogue(): ClassCatalogueRules.Catalogue
	local catalogue = self:getCatalogue()
	local isOwnedByKind: { [number]: boolean } = {}
	for _, entry in catalogue do
		isOwnedByKind[entry.kind] = self:isOwned(entry.kind)
	end
	return ClassCatalogueRules.sortForMenu(catalogue, ClientDataManager:getActiveClassKind(), isOwnedByKind)
end

-- a class button tapped: the info panel follows, owned or not
function ClientClassMenuManager:selectClass(classKind: number)
	if classKind == self.selectedClassKind then
		return
	end
	self.selectedClassKind = classKind
	self:closeInfo()
	self:render()
end

function ClientClassMenuManager:requestEquip()
	local classKind = self.selectedClassKind
	if classKind == ClientDataManager:getActiveClassKind() then
		return
	end
	if not self:isOwned(classKind) then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(LOCKED_CLASS_FEEDBACK, LOCKED_CLASS_FEEDBACK_SEC)
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_SELECT_CLASS, { classKind = classKind })
end

-- forgets the roll in flight: the reel stops where it is and its
-- connections go; the caller redraws the rows
function ClientClassMenuManager:clearRoll()
	self.rollGeneration += 1
	self.activeRoll = nil
	for _, connection in self.rollConnections do
		connection:Disconnect()
	end
	table.clear(self.rollConnections)
end

-- a roll left mid-way (Back, another overlay): a pending offer goes back
-- to the server as not taken, so the slot keeps what it had
function ClientClassMenuManager:abandonRoll()
	local roll = self.activeRoll
	self:clearRoll()
	if roll and not roll.isFinal then
		ClientNetManager:fireServer(NetEventNames.TRY_RESOLVE_SKILL_ROLL, { isTaken = false })
	end
end

-- the purchase went through: the Reroll button fades out of the row
function ClientClassMenuManager:fadeOutRerollButton(row: Instance)
	local button = row:FindFirstChild(Constants.PERK_ROW_REROLL_BUTTON)
	if not button or not button:IsA("GuiButton") then
		return
	end
	button.Interactable = false
	-- the helper puts the authored transparencies back under the hidden
	-- button, so the in-place redraw only has to show it again
	ClientGuiFade.fadeOut(
		button,
		REROLL_FADE_SEC,
		function()
			button.Visible = false
		end
	)
end

-- the reel: a column of entries built from clones of the row's own two
-- labels, the skill it had first, a shuffled handful of the catalogue,
-- and the result last, scrolled up through the clipping SkillText frame
-- with a tween that starts fast and eases to a stop on the last entry.
-- The row's own labels hide under it and come back showing the result
function ClientClassMenuManager:spinReel(row: Instance, start: ReelEntry, result: ReelEntry, generation: number, onLanded: () -> ())
	local skillText = skillTextOf(row)
	local nameLabel = skillText:FindFirstChild(Constants.PERK_ROW_NAME_LABEL)
	local descriptionLabel = skillText:FindFirstChild(Constants.PERK_ROW_DESCRIPTION_LABEL)
	if not skillText:IsA("GuiObject") or not nameLabel or not descriptionLabel or not nameLabel:IsA("GuiObject") or not descriptionLabel:IsA("GuiObject") then
		fillSkillText(skillText, result)
		onLanded()
		return
	end
	local catalogue = self:getSkillCatalogue()
	local ids: { string } = {}
	for id in catalogue do
		table.insert(ids, id)
	end
	table.sort(ids)
	Random.new():Shuffle(ids)
	local entries: { ReelEntry } = { start }
	for index = 1, math.min(REEL_CANDIDATE_COUNT, #ids) do
		local id = ids[index]
		table.insert(entries, self:reelEntryFor(id, catalogue[id].rarity))
	end
	table.insert(entries, result)
	local count = #entries

	skillText.ClipsDescendants = true
	local reel = Instance.new("Frame")
	reel.Name = REEL_FRAME_NAME
	reel.BackgroundTransparency = 1
	reel.BorderSizePixel = 0
	reel.Size = UDim2.fromScale(1, count)
	reel.Position = UDim2.fromScale(0, 0)
	for index, entry in entries do
		local cell = Instance.new("Frame")
		cell.Name = "Entry" .. tostring(index)
		cell.BackgroundTransparency = 1
		cell.BorderSizePixel = 0
		cell.Size = UDim2.fromScale(1, 1 / count)
		cell.Position = UDim2.fromScale(0, (index - 1) / count)
		local name = nameLabel:Clone()
		name.Visible = true
		name.Parent = cell
		local description = descriptionLabel:Clone()
		description.Visible = true
		description.Parent = cell
		fillSkillText(cell, entry)
		cell.Parent = reel
	end
	nameLabel.Visible = false
	descriptionLabel.Visible = false
	reel.Parent = skillText

	-- a tick as each entry passes the window
	local lastIndex = 1
	local ticking: RBXScriptConnection
	ticking = RunService.Heartbeat:Connect(
		function()
			local index = math.floor(-reel.Position.Y.Scale + 0.5) + 1
			if index ~= lastIndex then
				lastIndex = index
				ClientSoundManager:playSfx(SoundNames.Sfx.REROLL_SPIN)
			end
		end
	)
	table.insert(self.rollConnections, ticking)
	local tween = TweenService:Create(reel, REEL_TWEEN_INFO, { Position = UDim2.fromScale(0, -(count - 1)) })
	tween.Completed:Connect(
		function()
			ticking:Disconnect()
			if self.rollGeneration ~= generation then
				return
			end
			fillSkillText(skillText, result)
			nameLabel.Visible = true
			descriptionLabel.Visible = true
			reel:Destroy()
			ClientSoundManager:playSfx(SoundNames.Sfx.REROLL_REVEAL)
			onLanded()
		end
	)
	tween:Play()
end

-- KEEP takes the offer, X gives it back; either way the server's answer
-- (or its silence on a cancel) is what the rows are redrawn from
function ClientClassMenuManager:resolveRoll(isTaken: boolean)
	local roll = self.activeRoll
	if not roll or not roll.isLanded or roll.isFinal then
		return
	end
	self:clearRoll()
	setVisible(roll.row, Constants.PERK_ROW_KEEP_BUTTON, false)
	setVisible(roll.row, Constants.PERK_ROW_CANCEL_BUTTON, false)
	ClientNetManager:fireServer(NetEventNames.TRY_RESOLVE_SKILL_ROLL, { isTaken = isTaken })
	if isTaken then
		-- the row already shows the result; its button comes back now, since
		-- the data change (if the skill differs from the one held) redraws
		-- the row in place without disturbing it
		self:showRerollButton(roll.row, roll.classKind, roll.slot, false)
	else
		-- the server changes nothing on a cancel, so the row is put back here
		self:render()
	end
end

-- the server's offer for a slot, in place on its row: the Reroll button
-- fades, the words reel to the result, then KEEP and X appear (none for
-- the free first roll, which the server has already landed and replicated,
-- so its row reels from the empty slot to what the redraw already shows)
function ClientClassMenuManager:onSkillRollOffer(payload: any)
	if not self.isOpen or typeof(payload) ~= "table" or typeof(payload.offer) ~= "table" or typeof(payload.slot) ~= "number" then
		return
	end
	local view = self.view
	if not view then
		return
	end
	local classKind = if typeof(payload.classKind) == "number" then payload.classKind else self.selectedClassKind
	local slot: number = payload.slot
	-- a restricted player's free roll is saved on the slot as an offer
	-- already, so like the free first roll its reel is show: no KEEP or X
	-- follows, the redraw draws the offer with its own Keep
	local isFinal = payload.isFinal == true or payload.isFreeOffer == true
	local row = view.perkRows:FindFirstChild(string.format(PERK_ROW_NAME_FORMAT, slot))
	if classKind ~= self.selectedClassKind or not row then
		-- the panel moved on under the request: an open offer is handed back
		if not isFinal then
			ClientNetManager:fireServer(NetEventNames.TRY_RESOLVE_SKILL_ROLL, { isTaken = false })
		end
		return
	end
	self:clearRoll()
	self:closeInfo()
	local generation = self.rollGeneration
	local record = ClientDataManager:getClassRecord(classKind)
	-- the reel starts from the empty slot only for the first roll
	local current = if payload.isFinal == true then nil else record.skills[tostring(slot)]
	local start = self:reelEntryFor(if current then current.skillId else nil, if current then current.rarity else nil)
	local result = self:reelEntryFor(payload.offer.skillId, payload.offer.rarity)
	self.activeRoll = {
		classKind = classKind,
		slot = slot,
		row = row,
		isFinal = isFinal,
		isLanded = false,
	}
	self:fadeOutRerollButton(row)
	local keep = row:FindFirstChild(Constants.PERK_ROW_KEEP_BUTTON)
	local cancel = row:FindFirstChild(Constants.PERK_ROW_CANCEL_BUTTON)
	if keep and keep:IsA("GuiButton") then
		table.insert(
			self.rollConnections,
			keep.Activated:Connect(
				function()
					self:resolveRoll(true)
				end
			)
		)
	end
	if cancel and cancel:IsA("GuiButton") then
		table.insert(
			self.rollConnections,
			cancel.Activated:Connect(
				function()
					self:resolveRoll(false)
				end
			)
		)
	end
	self:spinReel(
		row,
		start,
		result,
		generation,
		function()
			local roll = self.activeRoll
			if not roll or self.rollGeneration ~= generation then
				return
			end
			roll.isLanded = true
			if isFinal then
				self:clearRoll()
				self:render()
				return
			end
			task.delay(
				SPIN_REVEAL_DELAY_SEC,
				function()
					if self.rollGeneration ~= generation then
						return
					end
					setVisible(row, Constants.PERK_ROW_KEEP_BUTTON, true)
					setVisible(row, Constants.PERK_ROW_CANCEL_BUTTON, true)
				end
			)
		end
	)
end

function ClientClassMenuManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	if ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isOpen = true
	-- the panel opens on the class in play, which also heads the list
	self.selectedClassKind = ClientDataManager:getActiveClassKind()
	self.listCatalogue = self:buildListCatalogue()
	self.equippedShownKind = nil
	self.equippedFlashGeneration += 1
	view.gui.Enabled = true
	self:closeInfo()
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientClassMenuManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self:abandonRoll()
	self:closeInfo()
	self.isOpen = false
	self.listCatalogue = nil
	self.equippedFlashGeneration += 1
	view.equippedTitle.TextColor3 = UiStyle.TEXT_COLOR
	view.gui.Enabled = false
	self:dropCloneConnections()
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientClassMenuManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.CLASS_MENU_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientClassMenuManager: no {Constants.CLASS_MENU_GUI_NAME} ScreenGui; run build_class_menu_gui`)
		return nil
	end
	local missing: { string } = {}
	local function find(parent: Instance?, name: string): Instance?
		local child = if parent then parent:FindFirstChild(name) else nil
		if not child then
			table.insert(missing, name)
		end
		return child
	end
	local dialog = find(gui, Constants.MENU_DIALOG_FRAME)
	local backButton = find(dialog, Constants.CLASS_MENU_BACK_BUTTON)
	local equippedClass = find(dialog, Constants.CLASS_MENU_EQUIPPED_CLASS)
	local equippedIcon = find(equippedClass, Constants.EQUIPPED_CLASS_ICON)
	local equippedTitle = find(equippedClass, Constants.EQUIPPED_CLASS_TITLE)
	local classListFrame = find(dialog, Constants.CLASS_MENU_CLASS_LIST_FRAME)
	local classList = find(classListFrame, Constants.CLASS_MENU_CLASS_LIST)
	local classButtonTemplate = find(classList, Constants.CLASS_MENU_CLASS_BUTTON_TEMPLATE)
	local infoPanel = find(dialog, Constants.CLASS_MENU_INFO_PANEL)
	local header = find(infoPanel, Constants.CLASS_INFO_HEADER)
	local nameLabel = find(header, Constants.CLASS_INFO_NAME_LABEL)
	local starsFrame = find(header, Constants.CLASS_INFO_STARS)
	local stars: { TextLabel } = {}
	for index = 1, Constants.CLASS_INFO_STAR_COUNT do
		local star = find(starsFrame, string.format(Constants.CLASS_INFO_STAR_NAME_FORMAT, index))
		if star and star:IsA("TextLabel") then
			table.insert(stars, star)
		end
	end
	local icon = find(header, Constants.CLASS_INFO_ICON)
	local descriptionFrame = find(infoPanel, Constants.CLASS_INFO_DESCRIPTION_FRAME)
	local descriptionLabel = find(descriptionFrame, Constants.CLASS_INFO_DESCRIPTION_LABEL)
	local kitRow = find(infoPanel, Constants.CLASS_INFO_KIT_ROW)
	local kitSlotTemplate = find(kitRow, Constants.CLASS_INFO_KIT_SLOT_TEMPLATE)
	local perkRows = find(infoPanel, Constants.CLASS_INFO_PERK_ROWS)
	local perkRowTemplate = find(perkRows, Constants.CLASS_INFO_PERK_ROW_TEMPLATE)
	local oddsButton = find(infoPanel, Constants.CLASS_INFO_ODDS_BUTTON)
	local equipButton = find(infoPanel, Constants.CLASS_INFO_EQUIP_BUTTON)
	local supplyCrateButton = find(infoPanel, Constants.CLASS_INFO_SUPPLY_CRATE_BUTTON)
	local rotatingStoreButton = find(infoPanel, Constants.CLASS_INFO_ROTATING_STORE_BUTTON)
	local upgradeButton = find(infoPanel, Constants.CLASS_INFO_UPGRADE_BUTTON)
	if not rotatingStoreButton or not upgradeButton then
		warn("ClientClassMenuManager: the ClassMenu has no RotatingStoreButton or UpgradeButton; a restricted player has no road to the store from here")
	end
	local infoDialog = find(dialog, Constants.CLASS_MENU_INFO_DIALOG)
	local infoTitle = find(infoDialog, Constants.INFO_DIALOG_TITLE)
	local infoPicture = find(infoDialog, Constants.INFO_DIALOG_PICTURE)
	local infoRows = find(infoDialog, Constants.INFO_DIALOG_ROWS)
	local infoRowTemplate = find(infoRows, Constants.INFO_DIALOG_ROW_TEMPLATE)
	local infoNote = find(infoDialog, Constants.INFO_DIALOG_NOTE)
	local infoClose = find(infoDialog, Constants.INFO_DIALOG_CLOSE_BUTTON)
	if #missing > 0 then
		warn(`ClientClassMenuManager: {Constants.CLASS_MENU_GUI_NAME} is missing {table.concat(missing, ", ")}; rerun build_class_menu_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton :: GuiButton,
		equippedIcon = equippedIcon :: ImageLabel,
		equippedTitle = equippedTitle :: TextLabel,
		classList = classList :: GuiObject,
		classButtonTemplate = classButtonTemplate :: GuiButton,
		nameLabel = nameLabel :: TextLabel,
		stars = stars,
		icon = icon :: ImageLabel,
		descriptionLabel = descriptionLabel :: TextLabel,
		kitRow = kitRow :: GuiObject,
		kitSlotTemplate = kitSlotTemplate :: GuiButton,
		perkRows = perkRows :: GuiObject,
		perkRowTemplate = perkRowTemplate :: GuiObject,
		oddsButton = oddsButton :: GuiButton,
		equipButton = equipButton :: GuiButton,
		supplyCrateButton = supplyCrateButton :: GuiButton,
		rotatingStoreButton = if rotatingStoreButton and rotatingStoreButton:IsA("GuiButton") then rotatingStoreButton else nil,
		upgradeButton = if upgradeButton and upgradeButton:IsA("GuiButton") then upgradeButton else nil,
		infoDialog = infoDialog :: GuiObject,
		infoTitle = infoTitle :: TextLabel,
		infoPicture = infoPicture :: ImageLabel,
		infoRows = infoRows :: GuiObject,
		infoRowTemplate = infoRowTemplate :: GuiObject,
		infoNote = infoNote :: TextLabel,
		infoClose = infoClose :: GuiButton,
	}
end

function ClientClassMenuManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.classButtonTemplate.Visible = false
	view.kitSlotTemplate.Visible = false
	view.perkRowTemplate.Visible = false
	view.infoRowTemplate.Visible = false
	view.infoDialog.Visible = false
	view.gui.Enabled = false

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)
	view.equipButton.Activated:Connect(
		function()
			self:requestEquip()
		end
	)
	view.oddsButton.Activated:Connect(
		function()
			self:onOddsActivated()
		end
	)
	view.supplyCrateButton.Activated:Connect(
		function()
			self:openSupplyCrates()
		end
	)
	-- both of the restricted player's plates do what the Supply Crate
	-- plate does: this menu closes and the stall's menu opens, which for
	-- them is the rotating store (ClientGachaMenuManager:openMenu)
	for _, plate in { view.rotatingStoreButton, view.upgradeButton } do
		plate.Visible = false
		plate.Activated:Connect(
			function()
				self:openSupplyCrates()
			end
		)
	end
	view.infoClose.Activated:Connect(
		function()
			self:closeInfo()
		end
	)
	-- the buttons take their height from an aspect constraint a frame after
	-- they are parented, and the window changes size with the screen, so
	-- the canvas is refitted on both
	local listLayout = view.classList:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(
			function()
				self:fitListCanvas(view)
			end
		)
	end
	view.classList:GetPropertyChangedSignal("AbsoluteSize"):Connect(
		function()
			self:fitListCanvas(view)
		end
	)
	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self:abandonRoll()
			self:closeInfo()
			self.isOpen = false
			view.gui.Enabled = false
			self:dropCloneConnections()
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
		-- the HUD's wallets stay on screen under the clear backdrop: the
		-- menu shows no balance of its own (designer, 2026-11-05)
		doesKeepHud = function(_overlay)
			return true
		end,
	}
	self.overlay = overlay

	-- a change of the class in play chimes, menu open or not (the dev
	-- dropdown too); the first value seen is only remembered
	self.knownActiveClassKind = ClientDataManager:getActiveClassKind()
	ClientDataManager:subscribeClasses(
		function()
			local activeKind = ClientDataManager:getActiveClassKind()
			if self.knownActiveClassKind ~= nil and activeKind ~= nil and activeKind ~= self.knownActiveClassKind then
				ClientSoundManager:playSfx(SoundNames.Sfx.CLASS_EQUIPPED)
			end
			self.knownActiveClassKind = activeKind
			self:render()
		end
	)
	-- the restricted flag swaps the crate and odds plates for the store's
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED,
		function()
			self:render()
		end
	)
	-- the Diamonds balance a roll spends is the HUD's wallet, left on
	-- screen under the clear backdrop (designer, 2026-11-05; the menu had
	-- its own wallet before), and a shortfall flashes it through the HUD
	-- the free roll countdowns; a tick with the menu closed or nothing
	-- counting returns at once
	ClientTicker.every(
		FREE_ROLL_TIMER_INTERVAL_SEC,
		function()
			self:stepFreeRollTimers()
		end
	)
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_SKILL_ROLL_OFFER,
		function(payload: any)
			self:onSkillRollOffer(payload)
		end
	)
end

function ClientClassMenuManager.new(): ClientClassMenuManager
	local self = setmetatable({}, ClientClassMenuManager) :: ClientClassMenuManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	self.selectedClassKind = 0
	self.activeRoll = nil
	self.freeRollTimers = {}
	self.rollGeneration = 0
	self.rollConnections = {}
	self.cloneConnections = {}
	self.listPaddingTopScale = nil
	self.listGapScale = nil
	self.listCatalogue = nil
	self.equippedShownKind = nil
	self.equippedFlashGeneration = 0
	self.knownActiveClassKind = nil
	return self
end

return ClientClassMenuManager.new()
