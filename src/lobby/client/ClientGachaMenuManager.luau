--!strict

-- The class gacha menu (GDD "Class Unlock System", M70): the lobby HUD's
-- Store button opens it. The left side lists every prize the pool can
-- land on with its own chance and the ROLL button with its Diamonds
-- price; the right side lists every class in the pool with the player's
-- progress on it (locked, the skill slots open, or complete). A player
-- PolicyService reports as restricted from paid random items sees no
-- ROLL button and a BUY button on each unowned class instead, at the
-- direct price. Everything drawn is already replicated (the config in
-- GameMetadata, the progress and balances on CurrentPlayer); the menu
-- sends only TryRollGacha and TryBuyClass.
--
-- NotifyGachaResult opens the reveal: a roulette strip of prize tiles
-- sampled from the real odds, the winner planted near the end, eased
-- under the centre pointer over GACHA_SPIN_SEC with a little jitter, then
-- a pop and a pulsing stroke (the reference game's Lucky Box reveal). The
-- prize is already granted before the notify, so the strip is pure show
-- and cannot be skipped; DONE puts the dialog back.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GachaRules = require("@game/ReplicatedStorage/Shared/GachaRules")
local CharacterRules = require("@game/ReplicatedStorage/Shared/CharacterRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)

local ClientGachaMenuManager = {}
ClientGachaMenuManager.__index = ClientGachaMenuManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	backButton: GuiButton,
	diamondLabel: TextLabel,
	keysLabel: TextLabel,
	oddsPanel: GuiObject,
	oddsRowTemplate: GuiObject,
	classesPanel: GuiObject,
	classRowTemplate: GuiObject,
	rollButton: TextButton,
	rollPriceLabel: TextLabel,
	revealPanel: GuiObject,
	stripWindow: GuiObject,
	strip: GuiObject,
	-- held out of the strip so clearing the strip can never destroy it
	tileTemplate: GuiObject,
	revealKindLabel: TextLabel,
	revealNameLabel: TextLabel,
	revealDetailLabel: TextLabel,
	revealDoneButton: GuiButton,
}

export type ClientGachaMenuManager = typeof(setmetatable(
	{} :: {
		view: View?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		-- a roll sent and not yet landed: the button waits
		isRolling: boolean,
		-- the strip's filler tiles are the client's own draw
		random: Random,
		-- a reveal started after this one cancels it through the serial
		revealSerial: number,
		spinTween: Tween?,
		celebrationStroke: UIStroke?,
	},
	ClientGachaMenuManager
))

local ROLL_TEXT = "Roll"
local ROLLING_TEXT = "Rolling"
local LOCKED_TEXT = "Locked"
local COMPLETE_TEXT = "Complete"
local SLOTS_TEXT = "%d / %d skill slots"
local KEYS_NAME = "Keys"
local KIND_NAMES = {
	[Enums.GachaResultKind.CLASS] = "Class",
	[Enums.GachaResultKind.COSMETIC] = "Cosmetic",
	[Enums.GachaResultKind.KEYS] = "Keys",
}
local REVEAL_ROLLING_TEXT = "Rolling"
local REVEAL_CLASS_DETAIL = "Equip it from the Classes menu"
local REVEAL_SLOT_DETAIL = "Skill slot %d is open on the %s"
local REVEAL_KEYS_DETAIL = "+%d"
local REVEAL_KEYS_FROM_CLASS = "The %s is complete, so the roll paid Keys"
local REVEAL_KEYS_FROM_COSMETIC = "You already own %s, so the roll paid Keys"
local REVEAL_COSMETIC_DETAIL = "Wear it from the Character Sheet"

-- the strip: how many tiles, which one the winner is planted at (near
-- the end, so the strip has somewhere to decelerate from), and how far
-- off centre the stop may land so it is never robotically exact
local TILE_COUNT = 40
local LAND_TILE_INDEX = 35
local TILES_PER_WINDOW = 5
local STOP_JITTER_SHARE = 0.6
local TILE_PADDING_PX = 8

function ClientGachaMenuManager:getConfig(): GachaRules.Config_Published?
	return GachaRules.decodeConfig(ClientDataManager:getGameMetadata(Attributes.GACHA_CONFIG))
end

-- the name a cosmetic id shows, from the hat catalogue until M61 adds
-- the other slots
function ClientGachaMenuManager:cosmeticName(cosmeticId: string): string
	local catalogue = CharacterRules.decodeHatCatalogue(ClientDataManager:getGameMetadata(Attributes.CHARACTER_HAT_CATALOGUE))
	local entry = catalogue[cosmeticId]
	return if entry then entry.name else cosmeticId
end

function ClientGachaMenuManager:prizeName(prize: GachaRules.Prize): string
	if prize.kind == Enums.GachaResultKind.CLASS then
		return Enums.getPublicName(Enums.ClassKind, prize.classKind) or "?"
	elseif prize.kind == Enums.GachaResultKind.COSMETIC then
		return self:cosmeticName(prize.cosmeticId or "")
	end
	return KEYS_NAME
end

local function kindColor(kind: number): Color3
	return UiStyle.GACHA_KIND_COLORS[kind] or UiStyle.TEXT_COLOR
end

local function clearRows(panel: GuiObject, template: GuiObject)
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") and child ~= template then
			child:Destroy()
		end
	end
end

function ClientGachaMenuManager:renderOdds(view: View, config: GachaRules.Config_Published)
	clearRows(view.oddsPanel, view.oddsRowTemplate)
	for order, prize in config.prizes do
		local row = view.oddsRowTemplate:Clone()
		row.Name = "OddsRow" .. prize.key
		row.LayoutOrder = order
		row.Visible = true
		local nameLabel = row:FindFirstChild(Constants.GACHA_ODDS_ROW_NAME_LABEL) :: TextLabel
		local shareLabel = row:FindFirstChild(Constants.GACHA_ODDS_ROW_SHARE_LABEL) :: TextLabel
		local kindBar = row:FindFirstChild("KindBar")
		nameLabel.Text = UiStyle.formatTitle(self:prizeName(prize))
		shareLabel.Text = GachaRules.formatOddsPercent(prize.odds)
		shareLabel.TextColor3 = kindColor(prize.kind)
		if kindBar and kindBar:IsA("GuiObject") then
			kindBar.BackgroundColor3 = kindColor(prize.kind)
		end
		row.Parent = view.oddsPanel
	end
end

function ClientGachaMenuManager:renderClasses(view: View, config: GachaRules.Config_Published, isRestricted: boolean)
	clearRows(view.classesPanel, view.classRowTemplate)
	local progress = ClientDataManager:getClassProgress()
	local diamonds = ClientDataManager:getDiamonds()
	for order, classKind in config.poolClassKinds do
		local row = view.classRowTemplate:Clone()
		row.Name = "ClassRow" .. tostring(classKind)
		row.LayoutOrder = order
		row.Visible = true
		local nameLabel = row:FindFirstChild(Constants.GACHA_CLASS_ROW_NAME_LABEL) :: TextLabel
		local progressLabel = row:FindFirstChild(Constants.GACHA_CLASS_ROW_PROGRESS_LABEL) :: TextLabel
		local buyButton = row:FindFirstChild(Constants.GACHA_CLASS_ROW_BUY_BUTTON) :: GuiButton
		local priceLabel = buyButton:FindFirstChild(Constants.GACHA_ROLL_PRICE_LABEL) :: TextLabel
		nameLabel.Text = UiStyle.formatTitle(Enums.getPublicName(Enums.ClassKind, classKind) or "?")
		local isOwned = GachaRules.isClassOwned(progress, classKind)
		local open = GachaRules.openSkillSlots(progress, classKind, config.maxSkillSlots)
		if not isOwned then
			progressLabel.Text = LOCKED_TEXT
			progressLabel.TextColor3 = UiStyle.TEXT_MUTED_COLOR
		elseif open >= config.maxSkillSlots then
			progressLabel.Text = COMPLETE_TEXT
			progressLabel.TextColor3 = UiStyle.POSITIVE_COLOR
		else
			progressLabel.Text = string.format(SLOTS_TEXT, open, config.maxSkillSlots)
			progressLabel.TextColor3 = UiStyle.TEXT_COLOR
		end
		buyButton.Visible = isRestricted and not isOwned
		if buyButton.Visible then
			local canAfford = diamonds >= config.directClassPriceDiamonds
			priceLabel.Text = utils.abbreviateNumber(config.directClassPriceDiamonds)
			buyButton.BackgroundColor3 = if canAfford then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
			buyButton.Activated:Connect(
				function()
					ClientNetManager:fireServer(NetEventNames.TRY_BUY_CLASS, { classKind = classKind })
				end
			)
		end
		row.Parent = view.classesPanel
	end
end

function ClientGachaMenuManager:renderRollButton(view: View, config: GachaRules.Config_Published, isRestricted: boolean)
	view.rollButton.Visible = not isRestricted
	local canAfford = ClientDataManager:getDiamonds() >= config.rollPriceDiamonds
	local isReady = canAfford and not self.isRolling
	view.rollButton.BackgroundColor3 = if isReady then UiStyle.ACCENT_COLOR else UiStyle.DISABLED_COLOR
	view.rollButton.Text = UiStyle.formatTitle(if self.isRolling then ROLLING_TEXT else ROLL_TEXT)
	view.rollPriceLabel.Text = utils.abbreviateNumber(config.rollPriceDiamonds)
end

function ClientGachaMenuManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	view.diamondLabel.Text = utils.abbreviateNumber(ClientDataManager:getDiamonds())
	view.keysLabel.Text = utils.abbreviateNumber(ClientDataManager:getKeys())
	local config = self:getConfig()
	if not config then
		warn("ClientGachaMenuManager: no GachaConfig in GameMetadata")
		return
	end
	local isRestricted = ClientDataManager:isPaidRandomItemsRestricted()
	self:renderOdds(view, config)
	self:renderClasses(view, config, isRestricted)
	self:renderRollButton(view, config, isRestricted)
end

function ClientGachaMenuManager:requestRoll()
	local view = self.view
	local config = self:getConfig()
	if not view or not config or self.isRolling then
		return
	end
	if ClientDataManager:getDiamonds() < config.rollPriceDiamonds then
		return
	end
	self.isRolling = true
	ClientNetManager:fireServer(NetEventNames.TRY_ROLL_GACHA, {})
	self:render()
end

-- the tile the strip lands on: what was rolled, which for a Keys result
-- converted from a class or a cosmetic is that class or cosmetic
local function winnerKey(payload: { [string]: any }): string
	local kind = payload.kind
	if kind == Enums.GachaResultKind.CLASS or kind == Enums.GachaResultKind.SKILL_SLOT then
		return GachaRules.prizeKey(Enums.GachaResultKind.CLASS, payload.classKind, nil)
	elseif kind == Enums.GachaResultKind.COSMETIC then
		return GachaRules.prizeKey(Enums.GachaResultKind.COSMETIC, nil, payload.cosmeticId)
	elseif payload.convertedFromKind == Enums.GachaResultKind.CLASS then
		return GachaRules.prizeKey(Enums.GachaResultKind.CLASS, payload.convertedClassKind, nil)
	elseif payload.convertedFromKind == Enums.GachaResultKind.COSMETIC then
		return GachaRules.prizeKey(Enums.GachaResultKind.COSMETIC, nil, payload.convertedCosmeticId)
	end
	return GachaRules.prizeKey(Enums.GachaResultKind.KEYS, nil, nil)
end

-- one weighted pick from the prize list; filler tiles use this so the
-- strip roughly reflects the real odds
function ClientGachaMenuManager:samplePrize(prizes: { GachaRules.Prize }): GachaRules.Prize
	local total = 0
	for _, prize in prizes do
		total += prize.odds
	end
	local roll = self.random:NextNumber() * total
	for _, prize in prizes do
		roll -= prize.odds
		if roll <= 0 then
			return prize
		end
	end
	return prizes[#prizes]
end

function ClientGachaMenuManager:tileWidthPx(view: View): number
	local windowWidth = view.stripWindow.AbsoluteSize.X
	if windowWidth <= 0 then
		return 160
	end
	return (windowWidth - TILE_PADDING_PX * (TILES_PER_WINDOW - 1)) / TILES_PER_WINDOW
end

function ClientGachaMenuManager:buildTile(view: View, prize: GachaRules.Prize, layoutOrder: number, widthPx: number): GuiObject
	local tile = view.tileTemplate:Clone()
	tile.Name = "Tile" .. tostring(layoutOrder)
	tile.LayoutOrder = layoutOrder
	tile.Size = UDim2.new(0, widthPx, tile.Size.Y.Scale, 0)
	tile.Visible = true
	local kindLabel = tile:FindFirstChild(Constants.GACHA_REVEAL_TILE_KIND_LABEL) :: TextLabel
	local nameLabel = tile:FindFirstChild(Constants.GACHA_REVEAL_TILE_NAME_LABEL) :: TextLabel
	local oddsLabel = tile:FindFirstChild(Constants.GACHA_REVEAL_TILE_ODDS_LABEL) :: TextLabel
	local stroke = tile:FindFirstChildOfClass("UIStroke")
	kindLabel.Text = UiStyle.formatTitle(KIND_NAMES[prize.kind] or "")
	nameLabel.Text = UiStyle.formatTitle(self:prizeName(prize))
	nameLabel.TextColor3 = kindColor(prize.kind)
	oddsLabel.Text = GachaRules.formatOddsPercent(prize.odds)
	if stroke then
		stroke.Color = kindColor(prize.kind)
	end
	tile.Parent = view.strip
	return tile
end

function ClientGachaMenuManager:stopSpin()
	local spinTween = self.spinTween
	if spinTween then
		spinTween:Cancel()
		self.spinTween = nil
	end
	local stroke = self.celebrationStroke
	if stroke then
		stroke:Destroy()
		self.celebrationStroke = nil
	end
end

function ClientGachaMenuManager:clearStrip(view: View)
	self:stopSpin()
	for _, child in view.strip:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- the strip X offset that puts the winner's centre under the pointer,
-- read from the live layout every time: fresh clones report zero size
-- for a frame or more on a slow client, so a target measured once could
-- strand the strip at its start. nil while nothing is laid out yet
function ClientGachaMenuManager:winnerTarget(view: View, winnerTile: GuiObject, jitterShare: number): number?
	local windowWidth = view.stripWindow.AbsoluteSize.X
	local tileWidth = winnerTile.AbsoluteSize.X
	local winnerLeft = winnerTile.AbsolutePosition.X - view.strip.AbsolutePosition.X
	if windowWidth <= 0 or tileWidth <= 0 or winnerLeft <= 0 then
		return nil
	end
	local winnerCentre = winnerLeft + tileWidth / 2
	return windowWidth / 2 - winnerCentre + jitterShare * tileWidth
end

-- what the result means, in the player's words, under the landed strip
function ClientGachaMenuManager:describeResult(payload: { [string]: any }): (string, string, string)
	local kind = payload.kind
	local kindName = Enums.getPublicName(Enums.GachaResultKind, kind) or ""
	if kind == Enums.GachaResultKind.CLASS then
		return kindName, Enums.getPublicName(Enums.ClassKind, payload.classKind) or "?", REVEAL_CLASS_DETAIL
	elseif kind == Enums.GachaResultKind.SKILL_SLOT then
		local className = Enums.getPublicName(Enums.ClassKind, payload.classKind) or "?"
		return kindName, className, string.format(REVEAL_SLOT_DETAIL, tonumber(payload.skillSlot) or 0, className)
	elseif kind == Enums.GachaResultKind.COSMETIC then
		return kindName, self:cosmeticName(tostring(payload.cosmeticId)), REVEAL_COSMETIC_DETAIL
	end
	local name = string.format(REVEAL_KEYS_DETAIL, tonumber(payload.keys) or 0)
	local detail = ""
	if payload.convertedFromKind == Enums.GachaResultKind.CLASS then
		detail = string.format(REVEAL_KEYS_FROM_CLASS, Enums.getPublicName(Enums.ClassKind, payload.convertedClassKind) or "?")
	elseif payload.convertedFromKind == Enums.GachaResultKind.COSMETIC then
		detail = string.format(REVEAL_KEYS_FROM_COSMETIC, self:cosmeticName(tostring(payload.convertedCosmeticId)))
	end
	return kindName, name, detail
end

function ClientGachaMenuManager:celebrateWinner(view: View, winnerTile: GuiObject, payload: { [string]: any })
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = winnerTile
	local popInfo = TweenInfo.new(UiStyle.GACHA_WINNER_POP_SEC, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(scale, popInfo, { Scale = UiStyle.GACHA_WINNER_POP_SCALE }):Play()

	local existingStroke = winnerTile:FindFirstChildOfClass("UIStroke")
	if existingStroke then
		existingStroke.Enabled = false
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UiStyle.STROKE_PX * 2
	stroke.Color = kindColor(payload.kind)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = winnerTile
	self.celebrationStroke = stroke
	local pulseInfo = TweenInfo.new(UiStyle.GACHA_STROKE_PULSE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(stroke, pulseInfo, { Transparency = 0.7 }):Play()

	local kindName, name, detail = self:describeResult(payload)
	view.revealKindLabel.Text = UiStyle.formatTitle(kindName)
	view.revealNameLabel.Text = UiStyle.formatTitle(name)
	view.revealNameLabel.TextColor3 = kindColor(payload.kind)
	view.revealDetailLabel.Text = detail
	view.revealNameLabel.Visible = true
	view.revealDetailLabel.Visible = true
	view.revealDoneButton.Visible = true
	ClientSoundManager:playSfx(SoundNames.Sfx.REROLL_REVEAL)
end

-- the reveal: the strip is built from the published prize list with the
-- winner planted, then eased under the pointer; the result reads only
-- once it lands
function ClientGachaMenuManager:showResult(payload: { [string]: any })
	local view = self.view
	local config = self:getConfig()
	if not view or not config or #config.prizes == 0 then
		self.isRolling = false
		self:render()
		return
	end
	if not self.isOpen then
		-- a roll from the dev panel with the menu closed: the balances
		-- already moved, there is nothing to show
		self.isRolling = false
		return
	end
	self.revealSerial += 1
	local serial = self.revealSerial
	self:clearStrip(view)

	local prizes = config.prizes
	local wantedKey = winnerKey(payload)
	local winner: GachaRules.Prize? = nil
	for _, prize in prizes do
		if prize.key == wantedKey then
			winner = prize
		end
	end
	if not winner then
		warn(`ClientGachaMenuManager: won prize {wantedKey} is not in the published list; the strip will not match`)
	end
	local widthPx = self:tileWidthPx(view)
	local winnerTile: GuiObject? = nil
	for tileIndex = 1, TILE_COUNT do
		local prize = if tileIndex == LAND_TILE_INDEX and winner then winner else self:samplePrize(prizes)
		local tile = self:buildTile(view, prize, tileIndex, widthPx)
		if tileIndex == LAND_TILE_INDEX then
			winnerTile = tile
		end
	end

	view.revealKindLabel.Text = UiStyle.formatTitle(REVEAL_ROLLING_TEXT)
	view.revealNameLabel.Visible = false
	view.revealDetailLabel.Visible = false
	view.revealDoneButton.Visible = false
	view.revealPanel.Visible = true
	view.strip.Position = UDim2.fromOffset(0, 0)
	ClientSoundManager:playSfx(SoundNames.Sfx.REROLL_SPIN)

	-- the progress value is tweened and the strip placed from it every
	-- change, so the target can be re-read from the live layout each frame
	local jitterShare = (self.random:NextNumber() - 0.5) * STOP_JITTER_SHARE
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	local function applyProgress()
		if not winnerTile then
			return
		end
		local target = self:winnerTarget(view, winnerTile, jitterShare)
		if target then
			view.strip.Position = UDim2.fromOffset(target * progress.Value, 0)
		end
	end
	progress.Changed:Connect(applyProgress)
	local spinInfo = TweenInfo.new(UiStyle.GACHA_SPIN_SEC, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local tween = TweenService:Create(progress, spinInfo, { Value = 1 })
	self.spinTween = tween
	tween.Completed:Connect(
		function(playbackState)
			local isCurrent = playbackState == Enum.PlaybackState.Completed and serial == self.revealSerial and self.isOpen
			if isCurrent then
				progress.Value = 1
				applyProgress()
			end
			progress:Destroy()
			if not isCurrent then
				return
			end
			self.spinTween = nil
			self.isRolling = false
			if winnerTile then
				self:celebrateWinner(view, winnerTile, payload)
			else
				view.revealDoneButton.Visible = true
			end
			self:render()
		end
	)
	tween:Play()
end

function ClientGachaMenuManager:hideReveal()
	local view = self.view
	if not view then
		return
	end
	-- the strip cannot be skipped: DONE only shows once it has landed
	if self.spinTween then
		return
	end
	self:clearStrip(view)
	view.revealPanel.Visible = false
end

function ClientGachaMenuManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	self.isOpen = true
	view.gui.Enabled = true
	view.revealPanel.Visible = false
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientGachaMenuManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self.isOpen = false
	self:clearStrip(view)
	view.revealPanel.Visible = false
	view.gui.Enabled = false
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientGachaMenuManager:findView(playerGui: PlayerGui): View?
	-- waited for, not found: on a live server the client starts before
	-- StarterGui is copied in
	local gui = playerGui:WaitForChild(Constants.GACHA_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`ClientGachaMenuManager: no {Constants.GACHA_GUI_NAME} ScreenGui; run build_gacha_gui`)
		return nil
	end
	local dialog = gui:FindFirstChild(Constants.MENU_DIALOG_FRAME)
	local backButton = dialog and dialog:FindFirstChild(Constants.GACHA_BACK_BUTTON)
	local wallet = dialog and dialog:FindFirstChild(Constants.GACHA_WALLET)
	local diamondLabel = wallet and wallet:FindFirstChild(Constants.HUD_DIAMOND_AMOUNT_LABEL)
	local keysWallet = dialog and dialog:FindFirstChild(Constants.GACHA_KEYS_WALLET)
	local keysLabel = keysWallet and keysWallet:FindFirstChild(Constants.GACHA_KEYS_AMOUNT_LABEL)
	local oddsPanel = dialog and dialog:FindFirstChild(Constants.GACHA_ODDS_PANEL)
	local oddsRowTemplate = oddsPanel and oddsPanel:FindFirstChild(Constants.GACHA_ODDS_ROW_TEMPLATE)
	local classesPanel = dialog and dialog:FindFirstChild(Constants.GACHA_CLASSES_PANEL)
	local classRowTemplate = classesPanel and classesPanel:FindFirstChild(Constants.GACHA_CLASS_ROW_TEMPLATE)
	local rollButton = dialog and dialog:FindFirstChild(Constants.GACHA_ROLL_BUTTON)
	-- the price sits on a tab inside the button, so the search descends
	local rollPriceLabel = rollButton and rollButton:FindFirstChild(Constants.GACHA_ROLL_PRICE_LABEL, true)
	local revealPanel = dialog and dialog:FindFirstChild(Constants.GACHA_REVEAL_PANEL)
	local stripWindow = revealPanel and revealPanel:FindFirstChild(Constants.GACHA_REVEAL_STRIP_WINDOW)
	local strip = stripWindow and stripWindow:FindFirstChild(Constants.GACHA_REVEAL_STRIP)
	local tileTemplate = strip and strip:FindFirstChild(Constants.GACHA_REVEAL_TILE_TEMPLATE)
	local revealKindLabel = revealPanel and revealPanel:FindFirstChild(Constants.GACHA_REVEAL_KIND_LABEL)
	local revealNameLabel = revealPanel and revealPanel:FindFirstChild(Constants.GACHA_REVEAL_NAME_LABEL)
	local revealDetailLabel = revealPanel and revealPanel:FindFirstChild(Constants.GACHA_REVEAL_DETAIL_LABEL)
	local revealDoneButton = revealPanel and revealPanel:FindFirstChild(Constants.GACHA_REVEAL_DONE_BUTTON)
	if
		not dialog
		or not backButton
		or not diamondLabel
		or not keysLabel
		or not oddsPanel
		or not oddsRowTemplate
		or not classesPanel
		or not classRowTemplate
		or not rollButton
		or not rollPriceLabel
		or not revealPanel
		or not stripWindow
		or not strip
		or not tileTemplate
		or not revealKindLabel
		or not revealNameLabel
		or not revealDetailLabel
		or not revealDoneButton
	then
		warn(`ClientGachaMenuManager: {Constants.GACHA_GUI_NAME} is missing parts; rerun build_gacha_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		backButton = backButton :: GuiButton,
		diamondLabel = diamondLabel :: TextLabel,
		keysLabel = keysLabel :: TextLabel,
		oddsPanel = oddsPanel :: GuiObject,
		oddsRowTemplate = oddsRowTemplate :: GuiObject,
		classesPanel = classesPanel :: GuiObject,
		classRowTemplate = classRowTemplate :: GuiObject,
		rollButton = rollButton :: TextButton,
		rollPriceLabel = rollPriceLabel :: TextLabel,
		revealPanel = revealPanel :: GuiObject,
		stripWindow = stripWindow :: GuiObject,
		strip = strip :: GuiObject,
		tileTemplate = tileTemplate :: GuiObject,
		revealKindLabel = revealKindLabel :: TextLabel,
		revealNameLabel = revealNameLabel :: TextLabel,
		revealDetailLabel = revealDetailLabel :: TextLabel,
		revealDoneButton = revealDoneButton :: GuiButton,
	}
end

function ClientGachaMenuManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.oddsRowTemplate.Visible = false
	view.classRowTemplate.Visible = false
	-- pulled out of the strip so clearing the strip can never destroy it
	view.tileTemplate.Visible = false
	view.tileTemplate.Parent = nil
	view.revealPanel.Visible = false
	view.gui.Enabled = false

	view.backButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)
	view.rollButton.Activated:Connect(
		function()
			self:requestRoll()
		end
	)
	view.revealDoneButton.Activated:Connect(
		function()
			self:hideReveal()
		end
	)

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self.isOpen = false
			self:clearStrip(view)
			view.revealPanel.Visible = false
			view.gui.Enabled = false
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay

	for _, attribute in { Attributes.DIAMONDS, Attributes.KEYS, Attributes.CLASS_PROGRESS, Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attribute,
			function()
				self:render()
			end
		)
	end
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_GACHA_RESULT,
		function(payload: any)
			if typeof(payload) == "table" then
				self:showResult(payload)
			end
		end
	)
end

function ClientGachaMenuManager.new(): ClientGachaMenuManager
	local self = setmetatable({}, ClientGachaMenuManager) :: ClientGachaMenuManager
	self.view = nil
	self.overlay = nil
	self.isOpen = false
	self.isRolling = false
	self.random = Random.new()
	self.revealSerial = 0
	self.spinTween = nil
	self.celebrationStroke = nil
	return self
end

return ClientGachaMenuManager.new()
