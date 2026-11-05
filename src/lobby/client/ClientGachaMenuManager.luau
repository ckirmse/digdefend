--!strict

-- The class gacha as a 3D crate opening (GDD "Class Unlock System", M70;
-- redesigned by the designer 2026-11-03 from the roulette strip). Opening
-- the menu glides the camera to the stall's CameraMenuOpen shot, the
-- crate on the left two thirds of the screen and the panel on the right
-- third: an X close in the corner, the odds list (or, for a player
-- restricted from paid random items, the classes to buy outright), and
-- OPEN CRATE with its Diamonds price; the balances are the HUD's. OPEN CRATE sends TryRollGacha and at once pans the camera to
-- CameraOpenSequence while every other character and the stall's ring
-- fade away; TAP CRATE TO OPEN then fades in along the bottom. A tap on
-- the crate (a ray from the camera through the input) swings the lid up
-- to LidOpen, lights the attachment's light and emitter, tilts the
-- camera to CameraOpen, and flies the prize card out of the crate: for a
-- class, the designer's 3D ClassCard (GameAssets/Store) rising from the
-- crate's CardStart pose to CardEnd with the class's stars already gold
-- and the newly earned one turning gold under its sparks; for Keys or a
-- cosmetic, the 2D card to the screen's centre. CLAIM sits under either. CLAIM shuts the lid, puts the
-- world back, glides the camera back to the menu shot, and the panel
-- fades back in. The X puts the player's own camera back at once, no
-- glide (designer, 2026-11-03). The prize is
-- already granted before NotifyGachaResult arrives, so the whole sequence
-- is show: everything drawn is replicated state and the menu sends only
-- TryRollGacha and TryBuyClass. Every shot is an authored part under the
-- stall (scripts/studio/build_supply_crate_parts.luau), so the designer
-- tunes the camera in the Explorer. The lid, the effects, and the fades
-- are this client's alone: nothing here touches the server.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GachaRules = require("@game/ReplicatedStorage/Shared/GachaRules")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local SkillRules = require("@game/ReplicatedStorage/Shared/SkillRules")
local CosmeticRules = require("@game/ReplicatedStorage/Shared/CosmeticRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientGuiFade = require(script.Parent.Parent.Client.ClientGuiFade)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientDiamondStoreManager = require(script.Parent.ClientDiamondStoreManager)

local ClientGachaMenuManager = {}
ClientGachaMenuManager.__index = ClientGachaMenuManager

type View = {
	gui: ScreenGui,
	dialog: GuiObject,
	closeButton: GuiButton,
	oddsPanel: GuiObject,
	oddsRowTemplate: GuiObject,
	classRowTemplate: GuiObject,
	rollButton: TextButton,
	rollPriceLabel: TextLabel,
	tapHint: TextLabel,
	-- the headline's picture backing and the words inside it
	revealTitle: ImageLabel,
	revealText: TextLabel,
	card: GuiObject,
	cardScale: UIScale,
	cardStroke: UIStroke?,
	cardKindLabel: TextLabel,
	cardNameLabel: TextLabel,
	cardDetailLabel: TextLabel,
	claimButton: GuiButton,
}

-- the designer's crate and the stall's shots, read once
type Crate = {
	model: Model,
	attachment: Attachment,
	lid: BasePart,
	lidClosedCFrame: CFrame,
	lidOpenCFrame: CFrame,
	emitters: { ParticleEmitter },
	lights: { Light },
	ring: BasePart?,
	cameraMenu: CFrame,
	cameraSequence: CFrame,
	cameraOpen: CFrame,
	-- the 3D class card's poses; without both the 2D card stands in
	cardStart: BasePart?,
	cardEnd: BasePart?,
	-- the Key's poses the same way
	keyStart: BasePart?,
	keyEnd: BasePart?,
	-- any cosmetic skin's poses: the skin is fitted to PrizeEnd's size
	prizeStart: BasePart?,
	prizeEnd: BasePart?,
}

-- one transparency taken away by the world fade, to be put back
type Faded = {
	instance: Instance,
	value: number,
}

export type ClientGachaMenuManager = typeof(setmetatable(
	{} :: {
		view: View?,
		crate: Crate?,
		-- the designer's ClassCard under GameAssets/Store, and this reveal's clone
		classCardTemplate: Model?,
		classCard: Model?,
		-- the designer's Key mesh under GameAssets/Store, this reveal's
		-- clone, and the spin that turns it while the claim waits
		keyTemplate: BasePart?,
		keyClone: BasePart?,
		keySpinConnection: RBXScriptConnection?,
		-- the landed class card's bob and tilt, until the claim or the sink
		cardFloatConnection: RBXScriptConnection?,
		-- a cosmetic skin's clone flying out of the crate, and its spin
		prizeClone: Model?,
		prizeSpinConnection: RBXScriptConnection?,
		-- places the standing prize a share of the way back into the crate,
		-- for the exchange's sink
		prizeSinkStep: ((share: number) -> ())?,
		overlay: ClientOverlayManager.Overlay?,
		isOpen: boolean,
		stage: number,
		-- a roll sent and not yet claimed: the button waits
		isRolling: boolean,
		-- the odds list's authored gap and top padding, as scales of the
		-- window's height
		oddsGapScale: number?,
		oddsPaddingTopScale: number?,
		-- the result that arrived, held until the crate is tapped
		pendingResult: { [string]: any }?,
		-- a step of the sequence started after this one cancels it
		sequenceSerial: number,
		faded: { Faded },
		-- the player's own body, faded for as long as the menu is up: the
		-- menu shot is fixed and the body can stand right in it
		fadedSelf: { Faded },
		cameraTween: Tween?,
		-- where the camera was before the menu took it
		savedCameraCFrame: CFrame?,
		pulseTween: Tween?,
		-- told when the HUD wallets should fade for the reveal and come
		-- back after the claim (the HUD listens; it requires this module)
		walletsFadedSubscribers: { (isFaded: boolean, fadeSec: number) -> () },
		dialogAuthoredTransparency: number,
		tapHintAuthoredTextTransparency: number,
		tapHintAuthoredStrokeTransparency: number,
		headlineAuthoredImageTransparency: number,
		headlineAuthoredTextTransparency: number,
		headlineAuthoredStrokeTransparency: number,
	},
	ClientGachaMenuManager
))

-- where the sequence stands
local Stage = {
	MENU = 1,
	-- the camera on its way to the crate
	PANNING = 2,
	-- the crate waits for the tap
	TAP = 3,
	-- the lid swinging up and the card on its way out
	OPENING = 4,
	-- the card up with CLAIM
	CLAIM = 5,
	-- a maxed class's card up with EXCHANGE FOR KEYS (designer, 2026-11-03;
	-- renamed and the crate reopened for the Keys, 2026-11-04)
	SELL = 6,
}

local ROLL_TEXT = "Open Crate"
local ROLLING_TEXT = "Opening"
local LOCKED_TEXT = "Locked"
local COMPLETE_TEXT = "Complete"
local SLOTS_TEXT = "%d / %d skill slots"
local KEYS_NAME = "Keys"
local REVEAL_CLASS_DETAIL = "Equip it from the Classes menu"
local REVEAL_SLOT_DETAIL = "Skill slot %d is open on the %s"
local REVEAL_KEYS_DETAIL = "+%d"
local REVEAL_KEYS_FROM_CLASS = "The %s is complete, so the crate paid Keys"
local REVEAL_KEYS_FROM_COSMETIC = "You already own %s, so the crate paid Keys"
local REVEAL_COSMETIC_DETAIL = "Wear it from the Character Sheet"
-- the headline over a landed class card (designer, 2026-11-03)
local HEADLINE_NEW_CLASS = "New class unlocked!"
local HEADLINE_TIER_UP = "Class tier increased!"
local HEADLINE_KEYS = "+%d keys"
local HEADLINE_MAXED = "Class already maxed out"
local HEADLINE_COSMETIC = "%s unlocked!"
local HEADLINE_COSMETIC_OWNED = "You already own %s"
-- the button under the card: CLAIM, or EXCHANGE FOR KEYS under a maxed class
local CLAIM_TEXT = "Claim"
local SELL_TEXT = "Exchange for keys"

-- a roll whose result never comes (the server refused it) is let go of
-- after this long waiting at the crate, and the menu comes back
local RESULT_TIMEOUT_SEC = 8
-- the card starts this small at the crate's mouth
local CARD_START_SCALE = 0.15
local CAMERA_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_CAMERA_TWEEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local LID_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_LID_OPEN_SEC, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LID_CLOSE_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_LID_OPEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_WORLD_FADE_SEC, Enum.EasingStyle.Linear)
local TAP_HINT_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_TAP_HINT_FADE_SEC, Enum.EasingStyle.Linear)
local CARD_FLY_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_CARD_FLY_SEC, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CARD_RISE_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_CARD_RISE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local KEY_RISE_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_KEY_RISE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- the sold card sinking back into the crate
local CARD_SINK_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_CARD_SINK_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local STAR_FILL_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_STAR_FILL_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PANEL_FADE_TWEEN_INFO = TweenInfo.new(UiStyle.GACHA_PANEL_FADE_SEC, Enum.EasingStyle.Linear)

function ClientGachaMenuManager:getConfig(): GachaRules.Config_Published?
	return GachaRules.decodeConfig(ClientDataManager:getGameMetadata(Attributes.GACHA_CONFIG))
end

-- the name a cosmetic id shows: the cosmetics catalogue's skins, else
-- the hat catalogue's hats
function ClientGachaMenuManager:cosmeticName(cosmeticId: string): string
	local skin = self:findCosmeticEntry(cosmeticId)
	if skin then
		return skin.name
	end
	local catalogue = SkillRules.decodeHatCatalogue(ClientDataManager:getGameMetadata(Attributes.HAT_CATALOGUE))
	local entry = catalogue[cosmeticId]
	return if entry then entry.name else cosmeticId
end

function ClientGachaMenuManager:findCosmeticEntry(cosmeticId: string): CosmeticRules.PublishedEntry?
	local published = CosmeticRules.decodeCatalogue(ClientDataManager:getGameMetadata(Attributes.COSMETIC_CATALOGUE))
	if not published then
		return nil
	end
	return CosmeticRules.findEntry(published, cosmeticId)
end

-- the skin's model under GameAssets/Cosmetics/<SLOT>/<template>; nil
-- (and the 2D card) when the template is not built
function ClientGachaMenuManager:findCosmeticTemplate(entry: CosmeticRules.PublishedEntry): Model?
	local slotName = Enums.getName(Enums.CosmeticSlot, entry.slot)
	local assets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local cosmetics = assets and assets:FindFirstChild(Constants.COSMETIC_TEMPLATES_FOLDER)
	local folder = cosmetics and slotName and cosmetics:FindFirstChild(slotName)
	local template = folder and folder:FindFirstChild(entry.templateName)
	if not template or not template:IsA("Model") then
		warn(`ClientGachaMenuManager: no {Constants.GAME_ASSETS_FOLDER}.{Constants.COSMETIC_TEMPLATES_FOLDER}.{tostring(slotName)}.{entry.templateName} model (run build_cosmetic_templates); the 2D card stands in`)
		return nil
	end
	return template
end

function ClientGachaMenuManager:prizeName(prize: GachaRules.Prize): string
	if prize.kind == Enums.GachaResultKind.CLASS then
		return Enums.getPublicName(Enums.ClassKind, prize.classKind) or "?"
	elseif prize.kind == Enums.GachaResultKind.COSMETIC then
		return self:cosmeticName(prize.cosmeticId or "")
	end
	return KEYS_NAME
end

-- the designer's buttons draw their word on a TextLabel child over a
-- picture backing, so the button's own Text is never what shows; a button
-- without the child still takes its Text
local function setButtonText(button: GuiButton, text: string)
	local label = button:FindFirstChild(Constants.GACHA_BUTTON_TEXT_LABEL)
	if label and label:IsA("TextLabel") then
		label.Text = text
	elseif button:IsA("TextButton") then
		button.Text = text
	end
end

local function kindColor(kind: number): Color3
	return UiStyle.GACHA_KIND_COLORS[kind] or UiStyle.TEXT_COLOR
end

local function clearRows(panel: GuiObject, templates: { GuiObject })
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") and not table.find(templates, child) then
			child:Destroy()
		end
	end
end

-- the odds panel is a ScrollingFrame whose canvas grows to its rows, but a
-- row sized by scale is measured against the window, so the canvas never
-- grew and the list was cut off (designer, 2026-11-04). Each row and the
-- list's gap take their authored scale of the window's height as pixels,
-- redone whenever the window changes size, so the designer's scale values
-- stay the source
function ClientGachaMenuManager:fitRowsToWindow(view: View)
	local panel = view.oddsPanel
	if not panel:IsA("ScrollingFrame") then
		return
	end
	local windowHeight = panel.AbsoluteWindowSize.Y
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") and child ~= view.oddsRowTemplate and child ~= view.classRowTemplate then
			local template = if child.Name:sub(1, 7) == "OddsRow" then view.oddsRowTemplate else view.classRowTemplate
			child.Size = UDim2.new(template.Size.X.Scale, 0, 0, template.Size.Y.Scale * windowHeight)
		elseif child:IsA("UIListLayout") then
			local authoredGap: number = self.oddsGapScale or child.Padding.Scale
			self.oddsGapScale = authoredGap
			child.Padding = UDim.new(0, authoredGap * windowHeight)
		elseif child:IsA("UIPadding") then
			-- the canvas does not count a scale padding either, and the
			-- bottom takes the top's room so the last row clears the edge
			local authoredTop: number = self.oddsPaddingTopScale or child.PaddingTop.Scale
			self.oddsPaddingTopScale = authoredTop
			child.PaddingTop = UDim.new(0, authoredTop * windowHeight)
			child.PaddingBottom = UDim.new(0, authoredTop * windowHeight)
		end
	end
end

function ClientGachaMenuManager:renderOdds(view: View, config: GachaRules.Config_Published)
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

-- the restricted player's list in the odds panel's place: every class in
-- the pool with the player's progress and BUY on the ones not owned
function ClientGachaMenuManager:renderClasses(view: View, config: GachaRules.Config_Published)
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
		local priceLabel = buyButton:FindFirstChild(Constants.GACHA_ROLL_PRICE_LABEL, true) :: TextLabel
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
		buyButton.Visible = not isOwned
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
		row.Parent = view.oddsPanel
	end
end

function ClientGachaMenuManager:renderRollButton(view: View, config: GachaRules.Config_Published, isRestricted: boolean)
	view.rollButton.Visible = not isRestricted
	local canAfford = ClientDataManager:getDiamonds() >= config.rollPriceDiamonds
	local isReady = canAfford and not self.isRolling
	view.rollButton.BackgroundColor3 = if isReady then UiStyle.POSITIVE_COLOR else UiStyle.DISABLED_COLOR
	setButtonText(view.rollButton, UiStyle.formatTitle(if self.isRolling then ROLLING_TEXT else ROLL_TEXT))
	view.rollPriceLabel.Text = utils.abbreviateNumber(config.rollPriceDiamonds)
end

function ClientGachaMenuManager:render()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	local config = self:getConfig()
	if not config then
		warn("ClientGachaMenuManager: no GachaConfig in GameMetadata")
		return
	end
	local isRestricted = ClientDataManager:isPaidRandomItemsRestricted()
	clearRows(view.oddsPanel, { view.oddsRowTemplate, view.classRowTemplate })
	if isRestricted then
		self:renderClasses(view, config)
	else
		self:renderOdds(view, config)
	end
	self:fitRowsToWindow(view)
	self:renderRollButton(view, config, isRestricted)
end

-- the camera: Scriptable for as long as the menu is up, eased between the
-- stall's shots; onDone runs only when the glide ran to its end
function ClientGachaMenuManager:tweenCamera(target: CFrame, tweenInfo: TweenInfo, onDone: (() -> ())?)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local previous = self.cameraTween
	if previous then
		previous:Cancel()
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local tween = TweenService:Create(camera, tweenInfo, { CFrame = target })
	self.cameraTween = tween
	tween.Completed:Connect(
		function(playbackState)
			if self.cameraTween == tween then
				self.cameraTween = nil
			end
			if playbackState == Enum.PlaybackState.Completed and onDone then
				onDone()
			end
		end
	)
	tween:Play()
end

-- back to the player at once: Roblox's own camera takes over from where
-- it stood before the menu, no glide (designer, 2026-11-03)
function ClientGachaMenuManager:restoreCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local previous = self.cameraTween
	if previous then
		previous:Cancel()
		self.cameraTween = nil
	end
	local saved = self.savedCameraCFrame
	self.savedCameraCFrame = nil
	if saved then
		camera.CFrame = saved
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = Players.LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- the panel back after a claim: everything in it eases up from clear
function ClientGachaMenuManager:fadePanelIn(view: View)
	view.dialog.BackgroundTransparency = 1
	view.dialog.Visible = true
	TweenService:Create(view.dialog, PANEL_FADE_TWEEN_INFO, { BackgroundTransparency = self.dialogAuthoredTransparency }):Play()
	ClientGuiFade.fadeIn(view.dialog, UiStyle.GACHA_PANEL_FADE_SEC)
end

local function collectVisualParts(root: Instance, targets: { Instance })
	if root:IsA("BasePart") or root:IsA("Decal") then
		table.insert(targets, root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			table.insert(targets, descendant)
		end
	end
end

-- fades targets to clear and remembers what they were in faded; an
-- already clear part is left alone
local function fadeOut(targets: { Instance }, faded: { Faded })
	for _, target in targets do
		local value = (target :: any).Transparency
		if typeof(value) ~= "number" or value >= 1 then
			continue
		end
		table.insert(faded, { instance = target, value = value })
		TweenService:Create(target, FADE_TWEEN_INFO, { Transparency = 1 }):Play()
	end
end

-- puts the remembered transparencies back, eased after a claim or at once
-- on a close (designer, 2026-11-03: no fade in when the menu shuts)
local function fadeBack(faded: { Faded }, isInstant: boolean?)
	for _, entry in faded do
		if not entry.instance.Parent then
			continue
		end
		if isInstant then
			(entry.instance :: any).Transparency = entry.value
		else
			TweenService:Create(entry.instance, FADE_TWEEN_INFO, { Transparency = entry.value }):Play()
		end
	end
	table.clear(faded)
end

-- what fades round the crate: every other player's character, the
-- stall salespeople (the LOBBY_NPC rigs), and the ring the stall stands
-- on; the authored transparencies are kept so the fade back is exact
function ClientGachaMenuManager:collectFadeTargets(crate: Crate): { Instance }
	local roots: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and player.Character then
			table.insert(roots, player.Character)
		end
	end
	for _, rig in CollectionService:GetTagged(Tags.LOBBY_NPC) do
		table.insert(roots, rig)
	end
	if crate.ring then
		table.insert(roots, crate.ring)
	end
	local targets: { Instance } = {}
	for _, root in roots do
		collectVisualParts(root, targets)
	end
	return targets
end

function ClientGachaMenuManager:fadeWorld(crate: Crate, isFaded: boolean, isInstant: boolean?)
	if isFaded then
		if #self.faded == 0 then
			fadeOut(self:collectFadeTargets(crate), self.faded)
		end
		return
	end
	fadeBack(self.faded, isInstant)
end

function ClientGachaMenuManager:fadeSelf(isFaded: boolean, isInstant: boolean?)
	if isFaded then
		local character = Players.LocalPlayer.Character
		if #self.fadedSelf == 0 and character then
			local targets = {}
			collectVisualParts(character, targets)
			fadeOut(targets, self.fadedSelf)
		end
		return
	end
	fadeBack(self.fadedSelf, isInstant)
end

-- a line of text fading in to its authored look, or out and off
local function setLineShown(label: TextLabel, isShown: boolean, authoredText: number, authoredStroke: number)
	if isShown then
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
		label.Visible = true
		TweenService:Create(label, TAP_HINT_TWEEN_INFO, {
			TextTransparency = authoredText,
			TextStrokeTransparency = authoredStroke,
		}):Play()
		return
	end
	local tween = TweenService:Create(label, TAP_HINT_TWEEN_INFO, { TextTransparency = 1, TextStrokeTransparency = 1 })
	tween.Completed:Connect(
		function()
			if label.TextTransparency >= 1 then
				label.Visible = false
			end
		end
	)
	tween:Play()
end

function ClientGachaMenuManager:setTapHintShown(view: View, isShown: boolean)
	setLineShown(view.tapHint, isShown, self.tapHintAuthoredTextTransparency, self.tapHintAuthoredStrokeTransparency)
end

-- the headline's backing and words fade together to their authored looks
function ClientGachaMenuManager:setHeadlineShown(view: View, isShown: boolean, text: string?)
	local backing = view.revealTitle
	if text then
		view.revealText.Text = UiStyle.formatTitle(text)
	end
	setLineShown(view.revealText, isShown, self.headlineAuthoredTextTransparency, self.headlineAuthoredStrokeTransparency)
	if isShown then
		backing.ImageTransparency = 1
		backing.Visible = true
		TweenService:Create(backing, TAP_HINT_TWEEN_INFO, { ImageTransparency = self.headlineAuthoredImageTransparency }):Play()
		return
	end
	local tween = TweenService:Create(backing, TAP_HINT_TWEEN_INFO, { ImageTransparency = 1 })
	tween.Completed:Connect(
		function()
			if backing.ImageTransparency >= 1 then
				backing.Visible = false
			end
		end
	)
	tween:Play()
end

function ClientGachaMenuManager:setCrateEffects(crate: Crate, isOn: boolean)
	for _, emitter in crate.emitters do
		emitter.Enabled = isOn
	end
	for _, light in crate.lights do
		light.Enabled = isOn
	end
end

-- a closing lid keeps the crate's light and sparks until it is down
-- (designer, 2026-11-04); a lid opened again before then cancels the
-- close, so its tween never completes and the light stays
function ClientGachaMenuManager:tweenLid(crate: Crate, isOpen: boolean)
	local target = if isOpen then crate.lidOpenCFrame else crate.lidClosedCFrame
	local info = if isOpen then LID_TWEEN_INFO else LID_CLOSE_TWEEN_INFO
	local tween = TweenService:Create(crate.lid, info, { CFrame = target })
	if not isOpen then
		tween.Completed:Connect(
			function(playbackState)
				if playbackState == Enum.PlaybackState.Completed then
					self:setCrateEffects(crate, false)
				end
			end
		)
	end
	tween:Play()
end

function ClientGachaMenuManager:stopPulse()
	local pulse = self.pulseTween
	if pulse then
		pulse:Cancel()
		self.pulseTween = nil
	end
end

-- what the result means, in the player's words, on the card
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

-- OPEN CRATE pressed, or a result arriving while the panel is up (the
-- dev panel's free roll): the camera pans in and the world fades
function ClientGachaMenuManager:subscribeWalletsFaded(callback: (isFaded: boolean, fadeSec: number) -> ())
	table.insert(self.walletsFadedSubscribers, callback)
end

function ClientGachaMenuManager:notifyWalletsFaded(isFaded: boolean, fadeSec: number)
	for _, callback in self.walletsFadedSubscribers do
		callback(isFaded, fadeSec)
	end
end

function ClientGachaMenuManager:startSequence()
	local view = self.view
	local crate = self.crate
	if not view or not crate or self.stage ~= Stage.MENU then
		return
	end
	self.sequenceSerial += 1
	local serial = self.sequenceSerial
	self.stage = Stage.PANNING
	view.dialog.Visible = false
	self:fadeWorld(crate, true)
	-- the balances leave with the world and come back after the claim
	self:notifyWalletsFaded(true, UiStyle.GACHA_WORLD_FADE_SEC)
	self:tweenCamera(
		crate.cameraSequence,
		CAMERA_TWEEN_INFO,
		function()
			if serial ~= self.sequenceSerial then
				return
			end
			self.stage = Stage.TAP
			self:setTapHintShown(view, true)
			task.delay(
				RESULT_TIMEOUT_SEC,
				function()
					if serial == self.sequenceSerial and self.stage == Stage.TAP and self.pendingResult == nil then
						warn("ClientGachaMenuManager: no result came for the roll; back to the menu")
						self:returnToMenu()
					end
				end
			)
		end
	)
end

-- the tap: the lid swings up, the effects come on, the camera tilts to
-- the open shot, and the card flies out
function ClientGachaMenuManager:openCrate()
	local view = self.view
	local crate = self.crate
	local payload = self.pendingResult
	if not view or not crate or not payload or self.stage ~= Stage.TAP then
		return
	end
	local serial = self.sequenceSerial
	self.stage = Stage.OPENING
	self:setTapHintShown(view, false)
	self:setCrateEffects(crate, true)
	self:tweenLid(crate, true)
	ClientSoundManager:playSfx(SoundNames.Sfx.CRATE_OPEN)
	self:tweenCamera(
		crate.cameraOpen,
		LID_TWEEN_INFO,
		function()
			if serial == self.sequenceSerial then
				self:flyCard(view, crate, payload)
			end
		end
	)
end

-- the card is up: CLAIM may be pressed
function ClientGachaMenuManager:finishReveal(view: View)
	self.stage = Stage.CLAIM
	self.isRolling = false
	view.claimButton.Visible = true
	ClientSoundManager:playSfx(SoundNames.Sfx.REROLL_REVEAL)
end

local function isClassDraw(payload: { [string]: any }): boolean
	return payload.kind == Enums.GachaResultKind.CLASS or payload.kind == Enums.GachaResultKind.SKILL_SLOT
end

-- a class drawn with every slot open: the server paid Keys for it, and
-- the card is shown anyway so the player sees what they drew
local function isMaxedClassDraw(payload: { [string]: any }): boolean
	return payload.kind == Enums.GachaResultKind.KEYS and payload.convertedFromKind == Enums.GachaResultKind.CLASS
end

-- a cosmetic drawn that the player owns: the same show as a maxed class,
-- the prize revealed and then exchanged for the Keys (designer, 2026-11-04)
local function isOwnedCosmeticDraw(payload: { [string]: any }): boolean
	return payload.kind == Enums.GachaResultKind.KEYS and payload.convertedFromKind == Enums.GachaResultKind.COSMETIC
end

local function setStarEffects(star: BasePart, isOn: boolean)
	local effect = star:FindFirstChild(Constants.CLASS_CARD_EFFECT_ATTACHMENT)
	if not effect then
		return
	end
	for _, child in effect:GetChildren() do
		if child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("Beam") then
			child.Enabled = isOn
		end
	end
end

-- the 3D card for a class: cloned from the designer's template, named
-- and starred for the class as it stood before this draw, laid flat in
-- the crate at CardStart, risen to CardEnd, and then the newly earned
-- star (a skill slot result's slot) turns gold under its sparks
function ClientGachaMenuManager:flyClassCard(view: View, crate: Crate, payload: { [string]: any }, cardStart: BasePart, cardEnd: BasePart, template: Model, isMaxed: boolean)
	local serial = self.sequenceSerial
	local card = template:Clone()
	card.Name = Constants.CLASS_CARD_TEMPLATE
	self.classCard = card

	local classKind = if isMaxed then payload.convertedClassKind else payload.classKind
	local className = Enums.getPublicName(Enums.ClassKind, classKind) or "?"
	local nameLabel = card:FindFirstChild(Constants.CLASS_CARD_NAME_LABEL, true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = UiStyle.formatTitle(className)
	end
	-- the class picture, where the designer has made one
	local iconLabel = card:FindFirstChild(Constants.CLASS_CARD_ICON_LABEL, true)
	local iconId = Icons.CLASS_KIND[classKind]
	if iconLabel and iconLabel:IsA("ImageLabel") and iconId then
		iconLabel.Image = iconId
	end

	-- stars are the class's open skill slots: the ones held before this
	-- draw are gold already, and a slot result adds its own
	local newStar = if payload.kind == Enums.GachaResultKind.SKILL_SLOT then tonumber(payload.skillSlot) else nil
	local starsBefore = if isMaxed then Constants.CLASS_CARD_STAR_COUNT elseif newStar then newStar - 1 else 0
	local stars: { BasePart } = {}
	for starIndex = 1, Constants.CLASS_CARD_STAR_COUNT do
		local star = card:FindFirstChild(string.format(Constants.CLASS_CARD_STAR_NAME_FORMAT, starIndex))
		if star and star:IsA("BasePart") then
			stars[starIndex] = star
			star.Color = if starIndex <= starsBefore then UiStyle.CLASS_CARD_STAR_GOLD_COLOR else UiStyle.CLASS_CARD_STAR_DARK_COLOR
			setStarEffects(star, false)
		end
	end

	-- the card's own size is CardEnd's; CardStart is the same card smaller
	local cardPart = card.PrimaryPart
	local ownHeight = if cardPart then cardPart.Size.Y else cardEnd.Size.Y
	local startScale = cardStart.Size.Y / ownHeight
	local endScale = cardEnd.Size.Y / ownHeight
	card:ScaleTo(startScale)
	card:PivotTo(cardStart.CFrame)
	card.Parent = workspace

	local progress = Instance.new("NumberValue")
	progress.Value = 0
	progress.Changed:Connect(
		function(value)
			if card.Parent == nil then
				return
			end
			card:ScaleTo(startScale + (endScale - startScale) * value)
			card:PivotTo(cardStart.CFrame:Lerp(cardEnd.CFrame, value))
		end
	)
	local headline = if isMaxed then HEADLINE_MAXED elseif newStar then HEADLINE_TIER_UP else HEADLINE_NEW_CLASS
	local isNewClass = payload.kind == Enums.GachaResultKind.CLASS and not isMaxed
	local function finishClassReveal()
		if isNewClass then
			-- a class the player did not own: the card's own emitters burst
			-- and the unlock sting plays as it lands (designer, 2026-11-04)
			local burst = cardPart and cardPart:FindFirstChild(Constants.CLASS_CARD_BURST_ATTACHMENT)
			if burst then
				for _, emitter in burst:GetChildren() do
					if emitter:IsA("ParticleEmitter") then
						emitter.Enabled = true
					end
				end
			end
			ClientSoundManager:playSfx(SoundNames.Sfx.CLASS_UNLOCKED)
		end
		self:setHeadlineShown(view, true, headline)
		self:finishReveal(view)
		if isMaxed then
			-- the same button, now the offer to sell
			self.stage = Stage.SELL
			setButtonText(view.claimButton, UiStyle.formatTitle(SELL_TEXT))
		end
	end
	local rise = TweenService:Create(progress, CARD_RISE_TWEEN_INFO, { Value = 1 })
	rise.Completed:Connect(
		function(playbackState)
			progress:Destroy()
			if playbackState ~= Enum.PlaybackState.Completed or serial ~= self.sequenceSerial then
				return
			end
			self:startCardFloat(card, cardEnd)
			local star = if newStar then stars[newStar] else nil
			if not star then
				finishClassReveal()
				return
			end
			-- a beat on the landed card before the new star lights
			task.delay(
				UiStyle.GACHA_STAR_DELAY_SEC,
				function()
					if serial ~= self.sequenceSerial then
						return
					end
					setStarEffects(star, true)
					ClientSoundManager:playSfx(SoundNames.Sfx.CLASS_TIER_UP)
					local fill = TweenService:Create(star, STAR_FILL_TWEEN_INFO, { Color = UiStyle.CLASS_CARD_STAR_GOLD_COLOR })
					fill.Completed:Connect(
						function()
							setStarEffects(star, false)
							if serial == self.sequenceSerial then
								finishClassReveal()
							end
						end
					)
					fill:Play()
				end
			)
		end
	)
	rise:Play()
end

-- the landed card drifts: a slow bob up and down about CardEnd with a
-- slight pitch and roll, so it never sits dead still while the claim
-- waits (designer, 2026-11-04); three sines at different rates so the
-- tilt never repeats in step with the bob, every one starting from zero
-- and the whole swing eased in, so the first frame is the landed pose
function ClientGachaMenuManager:startCardFloat(card: Model, cardEnd: BasePart)
	self:stopCardFloat()
	local restFrame = cardEnd.CFrame
	local height = cardEnd.Size.Y * UiStyle.GACHA_CARD_FLOAT_HEIGHT_SHARE
	local tilt = math.rad(UiStyle.GACHA_CARD_FLOAT_TILT_DEGREES)
	local period = UiStyle.GACHA_CARD_FLOAT_PERIOD_SEC
	local startTime = workspace:GetServerTimeNow()
	self.cardFloatConnection = RunService.RenderStepped:Connect(
		function()
			if card.Parent == nil then
				return
			end
			local elapsed = workspace:GetServerTimeNow() - startTime
			local phase = elapsed / period * math.pi * 2
			-- a smooth step from 0 to 1 over the ease-in
			local grown = math.clamp(elapsed / UiStyle.GACHA_CARD_FLOAT_EASE_IN_SEC, 0, 1)
			grown = grown * grown * (3 - 2 * grown)
			local lift = math.sin(phase) * height * grown
			local pitch = math.sin(phase * 0.7) * tilt * grown
			local roll = math.sin(phase * 0.5) * tilt * grown
			card:PivotTo(restFrame * CFrame.new(0, lift, 0) * CFrame.Angles(pitch, 0, roll))
		end
	)
end

function ClientGachaMenuManager:stopCardFloat()
	local connection = self.cardFloatConnection
	if connection then
		connection:Disconnect()
		self.cardFloatConnection = nil
	end
end

function ClientGachaMenuManager:destroyClassCard()
	self:stopCardFloat()
	local card = self.classCard
	if card then
		card:Destroy()
		self.classCard = nil
	end
end

-- the Key for a Keys draw: the designer's mesh cloned, risen from
-- KeyStart to KeyEnd, then turned about the world's up at KeyEnd until
-- the claim, under a headline with the count
function ClientGachaMenuManager:flyKey(view: View, payload: { [string]: any }, keyStart: BasePart, keyEnd: BasePart, template: BasePart)
	local serial = self.sequenceSerial
	local key = template:Clone()
	key.Name = Constants.KEY_TEMPLATE
	key.Anchored = true
	key.CanCollide = false
	key.CanQuery = false
	key.CFrame = keyStart.CFrame
	key.Parent = workspace
	self.keyClone = key

	local keys = tonumber(payload.keys) or 0
	local rise = TweenService:Create(key, KEY_RISE_TWEEN_INFO, { CFrame = keyEnd.CFrame })
	rise.Completed:Connect(
		function(playbackState)
			if playbackState ~= Enum.PlaybackState.Completed or serial ~= self.sequenceSerial then
				return
			end
			-- the turn is about the world's up through the key's own
			-- position, so a leaning mesh keeps its lean
			local restCFrame = keyEnd.CFrame
			local position = restCFrame.Position
			local rotation = restCFrame - position
			local startTime = workspace:GetServerTimeNow()
			self.keySpinConnection = RunService.RenderStepped:Connect(
				function()
					local elapsed = workspace:GetServerTimeNow() - startTime
					local angle = (elapsed / UiStyle.GACHA_KEY_SPIN_SEC) * math.pi * 2
					key.CFrame = CFrame.new(position) * CFrame.Angles(0, angle, 0) * rotation
				end
			)
			self:setHeadlineShown(view, true, string.format(HEADLINE_KEYS, keys))
			self:finishReveal(view)
		end
	)
	rise:Play()
end

-- a cosmetic skin out of the crate (designer, 2026-11-04): whatever its
-- art's size, the clone is scaled so its longest side matches PrizeEnd's
-- longest side (times the catalogue's REVEAL_SCALE) and placed by its
-- bounding box's centre, not its own pivot, so a pick axe pivoted at the
-- handle and a jet pack pivoted at the plate both rise centred; it grows
-- from PrizeStart's size on the way up and turns about the world's up
-- while the claim waits, as the Key does
function ClientGachaMenuManager:flyPrize(view: View, payload: { [string]: any }, entry: CosmeticRules.PublishedEntry, prizeStart: BasePart, prizeEnd: BasePart, template: Model, isOwned: boolean)
	local serial = self.sequenceSerial
	local prize = template:Clone()
	prize.Name = Constants.GACHA_PRIZE_CLONE
	for _, descendant in prize:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	local function longestSide(size: Vector3): number
		return math.max(size.X, size.Y, size.Z)
	end
	local _, extents = prize:GetBoundingBox()
	local endScale = longestSide(prizeEnd.Size) * entry.revealScale / math.max(longestSide(extents), 0.001)
	local startScale = endScale * UiStyle.GACHA_PRIZE_START_SCALE_SHARE
	prize:ScaleTo(endScale)
	-- where the pivot sits inside the box, so a box frame places the model
	local boxCFrame = prize:GetBoundingBox()
	local pivotInBox = boxCFrame:Inverse() * prize:GetPivot()
	local function boxFrameAt(pose: BasePart): CFrame
		return pose.CFrame
	end
	local function place(boxFrame: CFrame, scale: number)
		prize:ScaleTo(scale)
		prize:PivotTo(boxFrame * pivotInBox)
	end
	place(boxFrameAt(prizeStart), startScale)
	prize.Parent = workspace
	self.prizeClone = prize
	self.prizeSinkStep = function(share: number)
		if prize.Parent == nil then
			return
		end
		place(boxFrameAt(prizeEnd):Lerp(boxFrameAt(prizeStart), share), endScale + (startScale - endScale) * share)
	end

	local progress = Instance.new("NumberValue")
	progress.Value = 0
	progress.Changed:Connect(
		function(value)
			if prize.Parent == nil then
				return
			end
			place(boxFrameAt(prizeStart):Lerp(boxFrameAt(prizeEnd), value), startScale + (endScale - startScale) * value)
		end
	)
	local rise = TweenService:Create(progress, KEY_RISE_TWEEN_INFO, { Value = 1 })
	rise.Completed:Connect(
		function(playbackState)
			progress:Destroy()
			if playbackState ~= Enum.PlaybackState.Completed or serial ~= self.sequenceSerial then
				return
			end
			local restFrame = boxFrameAt(prizeEnd)
			local position = restFrame.Position
			local rotation = restFrame - position
			local startTime = workspace:GetServerTimeNow()
			self.prizeSpinConnection = RunService.RenderStepped:Connect(
				function()
					local elapsed = workspace:GetServerTimeNow() - startTime
					local angle = (elapsed / UiStyle.GACHA_KEY_SPIN_SEC) * math.pi * 2
					place(CFrame.new(position) * CFrame.Angles(0, angle, 0) * rotation, endScale)
				end
			)
			local headline = if isOwned then HEADLINE_COSMETIC_OWNED else HEADLINE_COSMETIC
			self:setHeadlineShown(view, true, string.format(headline, entry.name))
			self:finishReveal(view)
			if isOwned then
				-- the same button, now the offer to exchange
				self.stage = Stage.SELL
				setButtonText(view.claimButton, UiStyle.formatTitle(SELL_TEXT))
			end
		end
	)
	rise:Play()
end

function ClientGachaMenuManager:destroyPrize()
	local connection = self.prizeSpinConnection
	if connection then
		connection:Disconnect()
		self.prizeSpinConnection = nil
	end
	local prize = self.prizeClone
	if prize then
		prize:Destroy()
		self.prizeClone = nil
	end
	self.prizeSinkStep = nil
end

function ClientGachaMenuManager:destroyKey()
	local connection = self.keySpinConnection
	if connection then
		connection:Disconnect()
		self.keySpinConnection = nil
	end
	local key = self.keyClone
	if key then
		key:Destroy()
		self.keyClone = nil
	end
end

-- EXCHANGE FOR KEYS under a maxed class's card (designer, 2026-11-04): the
-- card sinks back into the crate while the Keys the server paid rise out
-- of it at the same time, the lid open, the light on, and the camera
-- held on the open shot throughout (a lid close and reopen between the
-- two was tried and dropped the same day)
function ClientGachaMenuManager:sellCard()
	local view = self.view
	local crate = self.crate
	local payload = self.pendingResult
	local card = self.classCard
	local cardStart = crate and crate.cardStart
	local cardEnd = crate and crate.cardEnd
	if not view or not crate or not payload or self.stage ~= Stage.SELL then
		return
	end
	self.stage = Stage.OPENING
	local serial = self.sequenceSerial
	view.claimButton.Visible = false
	setButtonText(view.claimButton, UiStyle.formatTitle(CLAIM_TEXT))
	self:setHeadlineShown(view, false)
	-- the Keys rise as the card sinks, the lid open and the light on
	self:stopCardFloat()
	self:revealKeys(view, crate, payload)
	if not card or not cardStart or not cardEnd then
		self:destroyClassCard()
		self:sinkPrize()
		return
	end
	local endScale = card:GetScale()
	local startScale = endScale * cardStart.Size.Y / cardEnd.Size.Y
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	progress.Changed:Connect(
		function(value)
			if card.Parent == nil then
				return
			end
			card:ScaleTo(endScale + (startScale - endScale) * value)
			card:PivotTo(cardEnd.CFrame:Lerp(cardStart.CFrame, value))
		end
	)
	local sink = TweenService:Create(progress, CARD_SINK_TWEEN_INFO, { Value = 1 })
	sink.Completed:Connect(
		function(playbackState)
			progress:Destroy()
			if playbackState ~= Enum.PlaybackState.Completed or serial ~= self.sequenceSerial then
				return
			end
			self:destroyClassCard()
		end
	)
	sink:Play()
end

-- an owned cosmetic's exchange: the prize stops spinning and goes back
-- down into the crate the way it came, shrinking to its start pose
function ClientGachaMenuManager:sinkPrize()
	local step = self.prizeSinkStep
	local connection = self.prizeSpinConnection
	if connection then
		connection:Disconnect()
		self.prizeSpinConnection = nil
	end
	if not step then
		self:destroyPrize()
		return
	end
	local serial = self.sequenceSerial
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	progress.Changed:Connect(
		function(value)
			step(value)
		end
	)
	local sink = TweenService:Create(progress, CARD_SINK_TWEEN_INFO, { Value = 1 })
	sink.Completed:Connect(
		function(playbackState)
			progress:Destroy()
			if playbackState ~= Enum.PlaybackState.Completed or serial ~= self.sequenceSerial then
				return
			end
			self:destroyPrize()
		end
	)
	sink:Play()
end

-- Keys out of the crate: the designer's Key where the crate has its
-- poses, the 2D card otherwise
function ClientGachaMenuManager:revealKeys(view: View, crate: Crate, payload: { [string]: any })
	local keyTemplate = self.keyTemplate
	local keyStart = crate.keyStart
	local keyEnd = crate.keyEnd
	if keyTemplate and keyStart and keyEnd then
		self:flyKey(view, payload, keyStart, keyEnd, keyTemplate)
		return
	end
	self:flyFlatCard(view, crate, payload)
end

function ClientGachaMenuManager:flyCard(view: View, crate: Crate, payload: { [string]: any })
	view.claimButton.Visible = false
	local template = self.classCardTemplate
	local cardStart = crate.cardStart
	local cardEnd = crate.cardEnd
	if template and cardStart and cardEnd then
		if isClassDraw(payload) then
			self:flyClassCard(view, crate, payload, cardStart, cardEnd, template, false)
			return
		elseif isMaxedClassDraw(payload) then
			self:flyClassCard(view, crate, payload, cardStart, cardEnd, template, true)
			return
		end
	end
	local isOwnedCosmetic = isOwnedCosmeticDraw(payload)
	if payload.kind == Enums.GachaResultKind.COSMETIC or isOwnedCosmetic then
		local cosmeticId = if isOwnedCosmetic then payload.convertedCosmeticId else payload.cosmeticId
		local entry = self:findCosmeticEntry(tostring(cosmeticId))
		local prizeTemplate = if entry then self:findCosmeticTemplate(entry) else nil
		if entry and prizeTemplate and crate.prizeStart and crate.prizeEnd then
			self:flyPrize(view, payload, entry, crate.prizeStart, crate.prizeEnd, prizeTemplate, isOwnedCosmetic)
			return
		end
	end
	if payload.kind == Enums.GachaResultKind.KEYS then
		self:revealKeys(view, crate, payload)
		return
	end
	self:flyFlatCard(view, crate, payload)
end

-- the 2D card for a cosmetic, and the stand-in for anything whose 3D
-- pieces are missing
function ClientGachaMenuManager:flyFlatCard(view: View, crate: Crate, payload: { [string]: any })
	local camera = workspace.CurrentCamera
	local serial = self.sequenceSerial
	local kindName, name, detail = self:describeResult(payload)
	view.cardKindLabel.Text = UiStyle.formatTitle(kindName)
	view.cardNameLabel.Text = UiStyle.formatTitle(name)
	view.cardNameLabel.TextColor3 = kindColor(payload.kind)
	view.cardDetailLabel.Text = detail
	local stroke = view.cardStroke
	if stroke then
		stroke.Color = kindColor(payload.kind)
		stroke.Transparency = 0
	end

	-- from the crate's mouth on screen to the centre, growing on the way
	local start = UDim2.fromScale(0.5, 0.5)
	if camera then
		local point = camera:WorldToScreenPoint(crate.attachment.WorldPosition)
		start = UDim2.fromOffset(point.X, point.Y)
	end
	view.card.Position = start
	view.cardScale.Scale = CARD_START_SCALE
	view.card.Visible = true
	TweenService:Create(view.cardScale, CARD_FLY_TWEEN_INFO, { Scale = 1 }):Play()
	local fly = TweenService:Create(view.card, CARD_FLY_TWEEN_INFO, { Position = UDim2.fromScale(0.5, 0.5) })
	fly.Completed:Connect(
		function(playbackState)
			if playbackState ~= Enum.PlaybackState.Completed or serial ~= self.sequenceSerial then
				return
			end
			if stroke then
				local pulseInfo = TweenInfo.new(UiStyle.GACHA_STROKE_PULSE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true)
				local pulse = TweenService:Create(stroke, pulseInfo, { Transparency = 0.7 })
				self.pulseTween = pulse
				pulse:Play()
			end
			self:finishReveal(view)
		end
	)
	fly:Play()
end

-- CLAIM (or a roll that never answered): the crate shuts, the world
-- comes back, and the camera glides back to the menu shot
function ClientGachaMenuManager:returnToMenu()
	local view = self.view
	local crate = self.crate
	if not view or not crate then
		return
	end
	self.sequenceSerial += 1
	local serial = self.sequenceSerial
	self.pendingResult = nil
	self.isRolling = false
	self:stopPulse()
	self:destroyClassCard()
	self:destroyKey()
	self:destroyPrize()
	view.card.Visible = false
	view.claimButton.Visible = false
	setButtonText(view.claimButton, UiStyle.formatTitle(CLAIM_TEXT))
	self:setTapHintShown(view, false)
	self:setHeadlineShown(view, false)
	self:notifyWalletsFaded(false, UiStyle.GACHA_WORLD_FADE_SEC)
	self:tweenLid(crate, false)
	self:fadeWorld(crate, false)
	self.stage = Stage.PANNING
	self:tweenCamera(
		crate.cameraMenu,
		CAMERA_TWEEN_INFO,
		function()
			if serial ~= self.sequenceSerial then
				return
			end
			self.stage = Stage.MENU
			self:render()
			self:fadePanelIn(view)
		end
	)
end

function ClientGachaMenuManager:requestRoll()
	local view = self.view
	local config = self:getConfig()
	if not view or not config or self.isRolling or self.stage ~= Stage.MENU then
		return
	end
	local diamonds = ClientDataManager:getDiamonds()
	if diamonds < config.rollPriceDiamonds then
		ClientDiamondStoreManager:handleDiamondsShort(config.rollPriceDiamonds, diamonds)
		return
	end
	self:beginRoll(
		function()
			ClientNetManager:fireServer(NetEventNames.TRY_ROLL_GACHA, {})
		end
	)
end

-- the dev panel's forced roll (2026-11-04): with the menu open the whole
-- crate sequence plays for the named prize, free; closed, the server
-- still grants it and only the balances move. Returns whether the
-- sequence took it
function ClientGachaMenuManager:requestForcedRoll(send: () -> ()): boolean
	if not self.isOpen or self.isRolling or self.stage ~= Stage.MENU then
		return false
	end
	self:beginRoll(send)
	return true
end

function ClientGachaMenuManager:beginRoll(send: () -> ())
	self.isRolling = true
	send()
	self:render()
	-- the pan covers the round trip; the result is waited for at the crate
	self:startSequence()
end

function ClientGachaMenuManager:showResult(payload: { [string]: any })
	if not self.isOpen then
		-- a roll from the dev panel with the menu closed: the balances
		-- already moved, there is nothing to show
		self.isRolling = false
		return
	end
	self.pendingResult = payload
	if self.stage == Stage.MENU then
		self.isRolling = true
		self:render()
		self:startSequence()
	end
end

-- a click or a touch while the crate waits: a ray from the camera through
-- the input, and only the crate's own parts count
function ClientGachaMenuManager:onInputBegan(input: InputObject, isGameProcessed: boolean)
	if isGameProcessed or self.stage ~= Stage.TAP or self.pendingResult == nil then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local crate = self.crate
	local camera = workspace.CurrentCamera
	if not crate or not camera then
		return
	end
	local ray = camera:ViewportPointToRay(input.Position.X, input.Position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { crate.model }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 100, params)
	if hit then
		self:openCrate()
	end
end

-- everything the sequence changed, put back at once (a close or a force
-- end mid-way)
function ClientGachaMenuManager:resetSequence()
	local view = self.view
	local crate = self.crate
	self.sequenceSerial += 1
	self.pendingResult = nil
	self.isRolling = false
	self.stage = Stage.MENU
	self:stopPulse()
	self:destroyClassCard()
	self:destroyKey()
	self:destroyPrize()
	self:notifyWalletsFaded(false, 0)
	if view then
		view.card.Visible = false
		view.claimButton.Visible = false
		setButtonText(view.claimButton, UiStyle.formatTitle(CLAIM_TEXT))
		view.tapHint.Visible = false
		view.revealTitle.Visible = false
		view.dialog.BackgroundTransparency = self.dialogAuthoredTransparency
		view.dialog.Visible = true
	end
	if crate then
		self:setCrateEffects(crate, false)
		crate.lid.CFrame = crate.lidClosedCFrame
		self:fadeWorld(crate, false, true)
	end
end

function ClientGachaMenuManager:openMenu()
	local view = self.view
	local overlay = self.overlay
	if not view or not overlay or self.isOpen then
		return
	end
	if ClientOverlayManager:isOverlayActive() then
		return
	end
	self.isOpen = true
	self:resetSequence()
	view.gui.Enabled = true
	self:render()
	ClientOverlayManager:notifyBeginOverlay(overlay)
	local crate = self.crate
	local camera = workspace.CurrentCamera
	if crate and camera then
		self.savedCameraCFrame = camera.CFrame
		self:tweenCamera(crate.cameraMenu, CAMERA_TWEEN_INFO)
		self:fadeSelf(true)
	end
end

function ClientGachaMenuManager:closeMenu()
	local view = self.view
	if not view or not self.isOpen then
		return
	end
	self.isOpen = false
	self:resetSequence()
	self:fadeSelf(false, true)
	view.gui.Enabled = false
	self:restoreCamera()
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientGachaMenuManager:findCrate(): Crate?
	-- waited for, not found: on a live server the client can start before
	-- the lobby has streamed in
	local folder = workspace:WaitForChild(Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER, Constants.GUI_WAIT_SEC)
	local model = folder and folder:WaitForChild(Constants.SUPPLY_CRATE_MODEL, Constants.GUI_WAIT_SEC)
	if not folder or not model or not model:IsA("Model") then
		warn(`ClientGachaMenuManager: no {Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER}.{Constants.SUPPLY_CRATE_MODEL} model; the crate opening is skipped`)
		return nil
	end
	local cratePart = model:FindFirstChild(Constants.SUPPLY_CRATE_PART)
	local attachment = cratePart and cratePart:FindFirstChild(Constants.SUPPLY_CRATE_ATTACHMENT)
	local lid = model:FindFirstChild(Constants.SUPPLY_CRATE_LID)
	local lidClosed = model:FindFirstChild(Constants.SUPPLY_CRATE_LID_CLOSED)
	local lidOpen = model:FindFirstChild(Constants.SUPPLY_CRATE_LID_OPEN)
	local cameraMenu = folder:FindFirstChild(Constants.SUPPLY_CRATE_CAMERA_MENU)
	local cameraSequence = folder:FindFirstChild(Constants.SUPPLY_CRATE_CAMERA_SEQUENCE)
	local cameraOpen = folder:FindFirstChild(Constants.SUPPLY_CRATE_CAMERA_OPEN)
	if
		not attachment
		or not attachment:IsA("Attachment")
		or not lid
		or not lid:IsA("BasePart")
		or not lidClosed
		or not lidClosed:IsA("BasePart")
		or not lidOpen
		or not lidOpen:IsA("BasePart")
		or not cameraMenu
		or not cameraMenu:IsA("BasePart")
		or not cameraSequence
		or not cameraSequence:IsA("BasePart")
		or not cameraOpen
		or not cameraOpen:IsA("BasePart")
	then
		warn(`ClientGachaMenuManager: {model:GetFullName()} is missing parts (run build_supply_crate_parts); the crate opening is skipped`)
		return nil
	end
	local emitters = {}
	local lights = {}
	for _, child in attachment:GetChildren() do
		if child:IsA("ParticleEmitter") then
			table.insert(emitters, child)
		elseif child:IsA("Light") then
			table.insert(lights, child)
		end
	end
	local ring = folder:FindFirstChild(Constants.SUPPLY_CRATE_RING)
	local cardStart = model:FindFirstChild(Constants.SUPPLY_CRATE_CARD_START)
	local cardEnd = model:FindFirstChild(Constants.SUPPLY_CRATE_CARD_END)
	if not cardStart or not cardStart:IsA("BasePart") or not cardEnd or not cardEnd:IsA("BasePart") then
		warn(`ClientGachaMenuManager: {model:GetFullName()} has no {Constants.SUPPLY_CRATE_CARD_START} and {Constants.SUPPLY_CRATE_CARD_END}; the 2D card stands in for a class`)
	end
	local keyStart = model:FindFirstChild(Constants.SUPPLY_CRATE_KEY_START)
	local keyEnd = model:FindFirstChild(Constants.SUPPLY_CRATE_KEY_END)
	if not keyStart or not keyStart:IsA("BasePart") or not keyEnd or not keyEnd:IsA("BasePart") then
		warn(`ClientGachaMenuManager: {model:GetFullName()} has no {Constants.SUPPLY_CRATE_KEY_START} and {Constants.SUPPLY_CRATE_KEY_END}; the 2D card stands in for Keys`)
	end
	local prizeStart = model:FindFirstChild(Constants.SUPPLY_CRATE_PRIZE_START)
	local prizeEnd = model:FindFirstChild(Constants.SUPPLY_CRATE_PRIZE_END)
	if not prizeStart or not prizeStart:IsA("BasePart") or not prizeEnd or not prizeEnd:IsA("BasePart") then
		warn(`ClientGachaMenuManager: {model:GetFullName()} has no {Constants.SUPPLY_CRATE_PRIZE_START} and {Constants.SUPPLY_CRATE_PRIZE_END}; the 2D card stands in for a cosmetic`)
	end
	return {
		model = model,
		attachment = attachment,
		lid = lid,
		lidClosedCFrame = lidClosed.CFrame,
		lidOpenCFrame = lidOpen.CFrame,
		emitters = emitters,
		lights = lights,
		ring = if ring and ring:IsA("BasePart") then ring else nil,
		cameraMenu = cameraMenu.CFrame,
		cameraSequence = cameraSequence.CFrame,
		cameraOpen = cameraOpen.CFrame,
		cardStart = if cardStart and cardStart:IsA("BasePart") then cardStart else nil,
		cardEnd = if cardEnd and cardEnd:IsA("BasePart") then cardEnd else nil,
		keyStart = if keyStart and keyStart:IsA("BasePart") then keyStart else nil,
		keyEnd = if keyEnd and keyEnd:IsA("BasePart") then keyEnd else nil,
		prizeStart = if prizeStart and prizeStart:IsA("BasePart") then prizeStart else nil,
		prizeEnd = if prizeEnd and prizeEnd:IsA("BasePart") then prizeEnd else nil,
	}
end

function ClientGachaMenuManager:findClassCardTemplate(): Model?
	local assets = ReplicatedStorage:WaitForChild(Constants.GAME_ASSETS_FOLDER, Constants.GUI_WAIT_SEC)
	local store = assets and assets:WaitForChild(Constants.STORE_ASSETS_FOLDER, Constants.GUI_WAIT_SEC)
	local template = store and store:WaitForChild(Constants.CLASS_CARD_TEMPLATE, Constants.GUI_WAIT_SEC)
	if not template or not template:IsA("Model") or not template.PrimaryPart then
		warn(`ClientGachaMenuManager: no {Constants.GAME_ASSETS_FOLDER}.{Constants.STORE_ASSETS_FOLDER}.{Constants.CLASS_CARD_TEMPLATE} model with a PrimaryPart; the 2D card stands in for a class`)
		return nil
	end
	return template
end

function ClientGachaMenuManager:findKeyTemplate(): BasePart?
	local assets = ReplicatedStorage:WaitForChild(Constants.GAME_ASSETS_FOLDER, Constants.GUI_WAIT_SEC)
	local store = assets and assets:WaitForChild(Constants.STORE_ASSETS_FOLDER, Constants.GUI_WAIT_SEC)
	local template = store and store:WaitForChild(Constants.KEY_TEMPLATE, Constants.GUI_WAIT_SEC)
	if not template or not template:IsA("BasePart") then
		warn(`ClientGachaMenuManager: no {Constants.GAME_ASSETS_FOLDER}.{Constants.STORE_ASSETS_FOLDER}.{Constants.KEY_TEMPLATE} part; the 2D card stands in for Keys`)
		return nil
	end
	return template
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
	local closeButton = dialog and dialog:FindFirstChild(Constants.GACHA_CLOSE_BUTTON)
	local oddsPanel = dialog and dialog:FindFirstChild(Constants.GACHA_ODDS_PANEL)
	local oddsRowTemplate = oddsPanel and oddsPanel:FindFirstChild(Constants.GACHA_ODDS_ROW_TEMPLATE)
	local classRowTemplate = oddsPanel and oddsPanel:FindFirstChild(Constants.GACHA_CLASS_ROW_TEMPLATE)
	local rollButton = dialog and dialog:FindFirstChild(Constants.GACHA_ROLL_BUTTON)
	-- the price sits on a tab inside the button, so the search descends
	local rollPriceLabel = rollButton and rollButton:FindFirstChild(Constants.GACHA_ROLL_PRICE_LABEL, true)
	local tapHint = gui:FindFirstChild(Constants.GACHA_TAP_HINT)
	local revealTitle = gui:FindFirstChild(Constants.GACHA_REVEAL_TITLE)
	local revealText = revealTitle and revealTitle:FindFirstChild(Constants.GACHA_REVEAL_TEXT)
	local card = gui:FindFirstChild(Constants.GACHA_CARD)
	local cardScale = card and card:FindFirstChildOfClass("UIScale")
	local cardStroke = card and card:FindFirstChildOfClass("UIStroke")
	local cardKindLabel = card and card:FindFirstChild(Constants.GACHA_CARD_KIND_LABEL)
	local cardNameLabel = card and card:FindFirstChild(Constants.GACHA_CARD_NAME_LABEL)
	local cardDetailLabel = card and card:FindFirstChild(Constants.GACHA_CARD_DETAIL_LABEL)
	local claimButton = gui:FindFirstChild(Constants.GACHA_CARD_CLAIM_BUTTON)
	if
		not dialog
		or not closeButton
		or not oddsPanel
		or not oddsRowTemplate
		or not classRowTemplate
		or not rollButton
		or not rollPriceLabel
		or not tapHint
		or not revealTitle
		or not revealText
		or not card
		or not cardScale
		or not cardKindLabel
		or not cardNameLabel
		or not cardDetailLabel
		or not claimButton
	then
		warn(`ClientGachaMenuManager: {Constants.GACHA_GUI_NAME} is missing parts; rerun build_gacha_gui`)
		return nil
	end
	return {
		gui = gui,
		dialog = dialog :: GuiObject,
		closeButton = closeButton :: GuiButton,
		oddsPanel = oddsPanel :: GuiObject,
		oddsRowTemplate = oddsRowTemplate :: GuiObject,
		classRowTemplate = classRowTemplate :: GuiObject,
		rollButton = rollButton :: TextButton,
		rollPriceLabel = rollPriceLabel :: TextLabel,
		tapHint = tapHint :: TextLabel,
		revealTitle = revealTitle :: ImageLabel,
		revealText = revealText :: TextLabel,
		card = card :: GuiObject,
		cardScale = cardScale :: UIScale,
		cardStroke = if cardStroke then cardStroke :: UIStroke else nil,
		cardKindLabel = cardKindLabel :: TextLabel,
		cardNameLabel = cardNameLabel :: TextLabel,
		cardDetailLabel = cardDetailLabel :: TextLabel,
		claimButton = claimButton :: GuiButton,
	}
end

function ClientGachaMenuManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local view = self:findView(playerGui)
	if not view then
		return
	end
	self.view = view
	view.oddsPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(
		function()
			self:fitRowsToWindow(view)
		end
	)
	self.dialogAuthoredTransparency = view.dialog.BackgroundTransparency
	view.oddsRowTemplate.Visible = false
	view.classRowTemplate.Visible = false
	view.card.Visible = false
	view.claimButton.Visible = false
	self.tapHintAuthoredTextTransparency = view.tapHint.TextTransparency
	self.tapHintAuthoredStrokeTransparency = view.tapHint.TextStrokeTransparency
	self.headlineAuthoredImageTransparency = view.revealTitle.ImageTransparency
	self.headlineAuthoredTextTransparency = view.revealText.TextTransparency
	self.headlineAuthoredStrokeTransparency = view.revealText.TextStrokeTransparency
	view.tapHint.Visible = false
	view.revealTitle.Visible = false
	view.gui.Enabled = false

	view.closeButton.Activated:Connect(
		function()
			self:closeMenu()
		end
	)
	view.rollButton.Activated:Connect(
		function()
			self:requestRoll()
		end
	)
	view.claimButton.Activated:Connect(
		function()
			if self.stage == Stage.CLAIM then
				self:returnToMenu()
			elseif self.stage == Stage.SELL then
				self:sellCard()
			end
		end
	)
	UserInputService.InputBegan:Connect(
		function(input, isGameProcessed)
			self:onInputBegan(input, isGameProcessed)
		end
	)

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return view.dialog
		end,
		notifyForceEnd = function(_overlay)
			self.isOpen = false
			self:resetSequence()
			self:fadeSelf(false, true)
			view.gui.Enabled = false
			self:restoreCamera()
		end,
		-- Back is the way out: a click on the crate must never close it
		notifyClickOutside = function(_overlay) end,
		-- the crate is the picture: no blur, no FOV nudge, and no backdrop
		-- in the way of the tap
		doesWantBlur = function(_overlay)
			return false
		end,
		doZoomCamera = function(_overlay)
			return false
		end,
		doesWantBackdrop = function(_overlay)
			return false
		end,
		-- the balances stay up on the purchase screen (designer, 2026-11-03)
		doesKeepHud = function(_overlay)
			return true
		end,
	}
	self.overlay = overlay

	-- the crate can arrive after the gui on a live server, so it is found
	-- off the main thread and the menu simply has no camera until then
	task.spawn(
		function()
			self.crate = self:findCrate()
			self.classCardTemplate = self:findClassCardTemplate()
			self.keyTemplate = self:findKeyTemplate()
		end
	)

	for _, attribute in { Attributes.DIAMONDS, Attributes.CLASS_PROGRESS, Attributes.IS_PAID_RANDOM_ITEMS_RESTRICTED } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			attribute,
			function()
				if self.stage == Stage.MENU then
					self:render()
				end
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
	self.oddsGapScale = nil
	self.oddsPaddingTopScale = nil
	self.crate = nil
	self.classCardTemplate = nil
	self.classCard = nil
	self.keyTemplate = nil
	self.keyClone = nil
	self.keySpinConnection = nil
	self.cardFloatConnection = nil
	self.prizeClone = nil
	self.prizeSpinConnection = nil
	self.prizeSinkStep = nil
	self.overlay = nil
	self.isOpen = false
	self.stage = Stage.MENU
	self.isRolling = false
	self.pendingResult = nil
	self.sequenceSerial = 0
	self.faded = {}
	self.fadedSelf = {}
	self.cameraTween = nil
	self.savedCameraCFrame = nil
	self.pulseTween = nil
	self.walletsFadedSubscribers = {}
	self.dialogAuthoredTransparency = 0
	self.tapHintAuthoredTextTransparency = 0
	self.tapHintAuthoredStrokeTransparency = 0
	self.headlineAuthoredImageTransparency = 0
	self.headlineAuthoredTextTransparency = 0
	self.headlineAuthoredStrokeTransparency = 0
	return self
end

return ClientGachaMenuManager.new()
