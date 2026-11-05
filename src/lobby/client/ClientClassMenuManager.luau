--!strict

-- The Class Menu (GDD "Classes", the Class Equip Menu of 2026-11-04,
-- which replaced the Character Select Menu and the Character Sheet of
-- M37): opened from the HUD's Classes button. On the left, one button per
-- class the catalogue lists (its icon and name; a locked one greyed with
-- a lock), any of which can be tapped to look at; on the right the info
-- panel for the selected class: its name, its three stars (one gold per
-- gacha tier earned), its icon, one sentence, the four kit slots (a tap
-- opens the item's tooltip), the three perk rows (locked ones name the
-- stars needed; open ones roll the way the old skill rows did, the first
-- roll into an empty slot free), ODDS, and EQUIP. Everything drawn is
-- replicated already (the class catalogue, skill catalogue, and reroll
-- pricing as GameMetadata; the class records, class in play, and class
-- progress on CurrentPlayer); the menu sends TrySelectClass,
-- TryRerollSkill, and TryResolveSkillRoll.
local Players = game:GetService("Players")

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
local ClientLabelFlash = require(script.Parent.Parent.Client.ClientLabelFlash)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientDiamondStoreManager = require(script.Parent.ClientDiamondStoreManager)

local ClientClassMenuManager = {}
ClientClassMenuManager.__index = ClientClassMenuManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	diamondLabel: TextLabel,
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
	equipButton: TextButton,
	offerDialog: GuiObject,
	offerTitle: TextLabel,
	currentBox: GuiObject,
	newBox: GuiObject,
	offerKeep: GuiButton,
	offerUndo: GuiButton,
	infoDialog: GuiObject,
	infoTitle: TextLabel,
	infoPicture: ImageLabel,
	infoRows: GuiObject,
	infoRowTemplate: GuiObject,
	infoNote: TextLabel,
	infoClose: GuiButton,
}

-- what one side of the roll screen shows
type BoxContent = {
	icon: string,
	spinText: string,
	name: string,
	detail: string,
	rarity: number?,
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
		-- a roll screen's connections and the parts hidden under it; a new
		-- roll or a close bumps the generation so a flip in flight stops
		rollGeneration: number,
		offerConnections: { RBXScriptConnection },
		hiddenForRoll: { GuiObject },
		-- the connections of the cloned buttons, dropped on every redraw
		cloneConnections: { RBXScriptConnection },
		listPaddingTopScale: number?,
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
local LOCKED_PERK_TEXT = "Locked"
local ROLL_TEXT = "Roll"
local REROLL_TEXT = "Reroll"
local FREE_TEXT = "Free"
local EQUIP_TEXT = "Equip"
local EQUIPPED_TEXT = "Equipped"
local LOCKED_CLASS_TEXT = "Locked"
local ODDS_TITLE = "Perk odds"
local ODDS_NOTE = "Every perk roll draws one skill from the catalogue; each rarity's share is its skills over the whole."
local ODDS_ROUNDING_NOTE = " Shares are rounded, so they may not add to exactly 100%."
local PERK_OFFER_TITLE = "New roll: perk %d"
local LOCKED_CLASS_FEEDBACK = "Open Supply Crates to unlock this class"
local LOCKED_CLASS_FEEDBACK_SEC = 3
-- the NEW box flips through candidates quickly, then slows to a stop on the
-- result: each step waits longer than the last
local SPIN_FIRST_STEP_SEC = 0.05
local SPIN_STEP_GROWTH = 1.18
local SPIN_LAST_STEP_SEC = 0.45
-- the reveal of the name and buttons after the flip stops
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

local function fillBox(box: GuiObject, content: BoxContent)
	local icon = box:FindFirstChild(Constants.OFFER_BOX_ICON)
	local spin = box:FindFirstChild(Constants.OFFER_BOX_SPIN_LABEL)
	if icon and icon:IsA("ImageLabel") then
		icon.Image = content.icon
		icon.Visible = content.icon ~= ""
	end
	if spin and spin:IsA("TextLabel") then
		spin.Text = UiStyle.formatTitle(content.spinText)
		spin.Visible = content.icon == ""
	end
	setLabel(box, Constants.OFFER_BOX_NAME_LABEL, content.name, rarityColor(content.rarity))
	setLabel(box, Constants.OFFER_BOX_DETAIL_LABEL, content.detail)
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

-- the left column: one button per listed class, the selected one
-- outlined, a locked one greyed under its lock
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
		local stroke = button:FindFirstChild(Constants.CLASS_BUTTON_SELECTED_STROKE)
		if stroke and stroke:IsA("UIStroke") then
			stroke.Enabled = entry.kind == self.selectedClassKind
		end
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
	clearClones(view.perkRows, view.perkRowTemplate)
	local pricing = self:getRerollPricing()
	local catalogue = self:getSkillCatalogue()
	local record = ClientDataManager:getClassRecord(classKind)
	local stars = self:starsOf(classKind) or 0
	local slotCount = if pricing then pricing.maxSkillSlots else Constants.CLASS_INFO_STAR_COUNT
	for slot = 1, slotCount do
		local row = view.perkRowTemplate:Clone()
		row.Name = "Perk" .. tostring(slot)
		row.LayoutOrder = slot
		row.Visible = true
		local badge = row:FindFirstChild(Constants.PERK_ROW_BADGE)
		if badge then
			setLabel(badge, Constants.PERK_ROW_BADGE_LABEL, tostring(slot))
		end
		local isLocked = slot > stars
		local rerollButton = row:FindFirstChild(Constants.PERK_ROW_REROLL_BUTTON)
		setVisible(row, Constants.PERK_ROW_LOCK_ICON, isLocked)
		setVisible(row, Constants.PERK_ROW_REQUIREMENT_LABEL, isLocked)
		setVisible(row, Constants.PERK_ROW_REQUIREMENT_STAR, isLocked)
		if isLocked then
			setLabel(row, Constants.PERK_ROW_NAME_LABEL, UiStyle.formatTitle(LOCKED_PERK_TEXT), UiStyle.TEXT_MUTED_COLOR)
			setLabel(row, Constants.PERK_ROW_DESCRIPTION_LABEL, "")
			-- the star and the word REQUIRED are authored on the row, so it
			-- reads "2 [star] REQUIRED" with only the number set here
			setLabel(row, Constants.PERK_ROW_REQUIREMENT_LABEL, string.format("%d", slot))
			if rerollButton and rerollButton:IsA("GuiObject") then
				rerollButton.Visible = false
			end
			row.Parent = view.perkRows
			continue
		end
		local skill = record.skills[tostring(slot)]
		local isEmpty = skill == nil
		if skill then
			setLabel(row, Constants.PERK_ROW_NAME_LABEL, skillTitle(catalogue[skill.skillId], skill.skillId, skill.rarity), rarityColor(skill.rarity))
			local entry = catalogue[skill.skillId]
			setLabel(row, Constants.PERK_ROW_DESCRIPTION_LABEL, if entry then entry.description else "")
		else
			setLabel(row, Constants.PERK_ROW_NAME_LABEL, UiStyle.formatTitle(EMPTY_PERK_TEXT), UiStyle.TEXT_MUTED_COLOR)
			setLabel(row, Constants.PERK_ROW_DESCRIPTION_LABEL, EMPTY_PERK_DESCRIPTION)
		end
		if rerollButton and rerollButton:IsA("GuiButton") then
			rerollButton.Visible = pricing ~= nil
			if pricing then
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
		end
		row.Parent = view.perkRows
	end
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

-- the right column for the selected class
function ClientClassMenuManager:renderInfo(view: View, entry: ClassCatalogueRules.Entry)
	local classKind = entry.kind
	local stars = self:starsOf(classKind)
	local isOwned = stars ~= nil
	view.nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.ClassKind, classKind) or "?")
	for index, star in view.stars do
		star.TextColor3 = if index <= (stars or 0) then UiStyle.CLASS_CARD_STAR_GOLD_COLOR else UiStyle.CLASS_CARD_STAR_DARK_COLOR
	end
	view.icon.Image = Icons.CLASS_KIND[classKind] or Icons.PLACEHOLDER
	view.descriptionLabel.Text = entry.description
	self:renderKit(view, entry)
	self:renderPerkRows(view, classKind)

	local isActive = classKind == ClientDataManager:getActiveClassKind()
	local word = if isActive then EQUIPPED_TEXT elseif isOwned then EQUIP_TEXT else LOCKED_CLASS_TEXT
	view.equipButton.Text = UiStyle.formatTitle(word)
	view.equipButton.BackgroundColor3 = if isOwned and not isActive then UiStyle.POSITIVE_COLOR else UiStyle.DISABLED_COLOR
	view.equipButton.AutoButtonColor = isOwned and not isActive
end

function ClientClassMenuManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	view.diamondLabel.Text = utils.formatWithCommas(ClientDataManager:getDiamonds())
	local catalogue = self:getCatalogue()
	if #catalogue == 0 then
		warn("ClientClassMenuManager: no class catalogue in GameMetadata yet")
		return
	end
	local entry = ClassCatalogueRules.findEntry(catalogue, self.selectedClassKind) or catalogue[1]
	self.selectedClassKind = entry.kind
	self:dropCloneConnections()
	self:renderClassList(view, catalogue)
	self:renderInfo(view, entry)
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

function ClientClassMenuManager:clearOffer()
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
function ClientClassMenuManager:hideMenuForRoll(view: View)
	for _, child in view.dialog:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.offerDialog and child.Visible then
			child.Visible = false
			table.insert(self.hiddenForRoll, child)
		end
	end
end

-- the roll screen: CURRENT on the left, NEW on the right. The NEW box
-- flips through `candidates`, slowing to a stop on `result`; then Keep
-- and Undo appear. `onUndo` nil means the roll already landed (the free
-- first roll), so only Keep shows
function ClientClassMenuManager:showRoll(title: string, current: BoxContent, candidates: { BoxContent }, result: BoxContent, onKeep: () -> (), onUndo: (() -> ())?)
	local view = self.view
	if not view then
		return
	end
	self:clearOffer()
	self:closeInfo()
	local generation = self.rollGeneration
	view.offerTitle.Text = UiStyle.formatTitle(title)
	fillBox(view.currentBox, current)
	fillBox(view.newBox, result)
	view.offerKeep.Visible = false
	view.offerUndo.Visible = false
	self:hideMenuForRoll(view)
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
				fillBox(view.newBox, candidates[index])
				ClientSoundManager:playSfx(SoundNames.Sfx.REROLL_SPIN)
				task.wait(step)
				step *= SPIN_STEP_GROWTH
			end
			if self.rollGeneration ~= generation then
				return
			end
			fillBox(view.newBox, result)
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

function ClientClassMenuManager:onSkillRollOffer(payload: any)
	if not self.isOpen or typeof(payload) ~= "table" or typeof(payload.offer) ~= "table" or typeof(payload.slot) ~= "number" then
		return
	end
	local classKind = if typeof(payload.classKind) == "number" then payload.classKind else self.selectedClassKind
	local record = ClientDataManager:getClassRecord(classKind)
	local catalogue = self:getSkillCatalogue()
	-- skills have no icons yet: the name itself flips in the icon area
	local function boxFor(skillId: string?, rarity: number?): BoxContent
		local entry = if skillId then catalogue[skillId] else nil
		local name = if entry then entry.name else (skillId or EMPTY_PERK_TEXT)
		return {
			icon = "",
			spinText = name,
			name = if skillId then skillTitle(entry, skillId, rarity or 0) else UiStyle.formatTitle(EMPTY_PERK_TEXT),
			detail = if entry then entry.description else "",
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
	local current = record.skills[tostring(payload.slot)]
	local offer = payload.offer
	local isFinal = payload.isFinal == true
	self:showRoll(
		string.format(PERK_OFFER_TITLE, payload.slot),
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
	-- the panel opens on the class in play
	self.selectedClassKind = ClientDataManager:getActiveClassKind()
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
	self:clearOffer()
	self:closeInfo()
	self.isOpen = false
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
	local wallet = find(dialog, Constants.CLASS_MENU_WALLET)
	local diamondLabel = find(wallet, Constants.HUD_DIAMOND_AMOUNT_LABEL)
	local classList = find(dialog, Constants.CLASS_MENU_CLASS_LIST)
	local classButtonTemplate = find(classList, Constants.CLASS_MENU_CLASS_BUTTON_TEMPLATE)
	local infoPanel = find(dialog, Constants.CLASS_MENU_INFO_PANEL)
	local nameLabel = find(infoPanel, Constants.CLASS_INFO_NAME_LABEL)
	local starsFrame = find(infoPanel, Constants.CLASS_INFO_STARS)
	local stars: { TextLabel } = {}
	for index = 1, Constants.CLASS_INFO_STAR_COUNT do
		local star = find(starsFrame, string.format(Constants.CLASS_INFO_STAR_NAME_FORMAT, index))
		if star and star:IsA("TextLabel") then
			table.insert(stars, star)
		end
	end
	local icon = find(infoPanel, Constants.CLASS_INFO_ICON)
	local descriptionLabel = find(infoPanel, Constants.CLASS_INFO_DESCRIPTION_LABEL)
	local kitRow = find(infoPanel, Constants.CLASS_INFO_KIT_ROW)
	local kitSlotTemplate = find(kitRow, Constants.CLASS_INFO_KIT_SLOT_TEMPLATE)
	local perkRows = find(infoPanel, Constants.CLASS_INFO_PERK_ROWS)
	local perkRowTemplate = find(perkRows, Constants.CLASS_INFO_PERK_ROW_TEMPLATE)
	local oddsButton = find(infoPanel, Constants.CLASS_INFO_ODDS_BUTTON)
	local equipButton = find(infoPanel, Constants.CLASS_INFO_EQUIP_BUTTON)
	local offerDialog = find(dialog, Constants.CLASS_MENU_OFFER_DIALOG)
	local offerTitle = find(offerDialog, Constants.OFFER_DIALOG_TITLE)
	local currentBox = find(offerDialog, Constants.OFFER_CURRENT_BOX)
	local newBox = find(offerDialog, Constants.OFFER_NEW_BOX)
	local offerKeep = find(offerDialog, Constants.OFFER_KEEP_BUTTON)
	local offerUndo = find(offerDialog, Constants.OFFER_UNDO_BUTTON)
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
		diamondLabel = diamondLabel :: TextLabel,
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
		equipButton = equipButton :: TextButton,
		offerDialog = offerDialog :: GuiObject,
		offerTitle = offerTitle :: TextLabel,
		currentBox = currentBox :: GuiObject,
		newBox = newBox :: GuiObject,
		offerKeep = offerKeep :: GuiButton,
		offerUndo = offerUndo :: GuiButton,
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
	view.offerDialog.Visible = false
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
			self:showOdds()
		end
	)
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
			self:clearOffer()
			self:closeInfo()
			self.isOpen = false
			view.gui.Enabled = false
			self:dropCloneConnections()
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay

	ClientDataManager:subscribeClasses(
		function()
			self:render()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.DIAMONDS,
		function()
			local currentView = self.view
			if currentView and self.isOpen then
				currentView.diamondLabel.Text = utils.formatWithCommas(ClientDataManager:getDiamonds())
			end
		end
	)
	ClientDiamondStoreManager:subscribeDiamondsShort(
		function()
			local currentView = self.view
			if currentView and self.isOpen then
				ClientLabelFlash.flashRed(currentView.diamondLabel)
			end
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
	self.rollGeneration = 0
	self.offerConnections = {}
	self.hiddenForRoll = {}
	self.cloneConnections = {}
	self.listPaddingTopScale = nil
	return self
end

return ClientClassMenuManager.new()
