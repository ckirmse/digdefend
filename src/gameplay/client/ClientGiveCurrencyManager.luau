--!strict

-- Give Currency on this client (M32). Every other player's character gets
-- a "Give Currency" ProximityPrompt made here, locally (so nobody sees
-- one on themselves and the server carries no extra instances); its words
-- and reach come from GameMetadata. Triggering it opens the GiveCurrency
-- menu (StarterGui.GiveCurrency, scripts/studio/build_give_currency_gui
-- .luau) for that player: their thumbnail and name, a Gold row and an
-- Iron row whose amounts move by the published step on plus and minus
-- (held, the button repeats faster and faster) or are typed into, and
-- Send, which leads to a confirmation page. Confirm
-- sends TryGiveCurrency; the server moves the bars and both players hear
-- the result as feedback text. Amounts are held inside the sender's
-- balances by pure GiveCurrencyRules, the same rules the server checks with.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GiveCurrencyRules = require("@game/ReplicatedStorage/Shared/GiveCurrencyRules")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.Parent.Client.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientIconFlightManager = require(script.Parent.ClientIconFlightManager)
local ClientRefineryManager = require(script.Parent.ClientRefineryManager)

local ClientGiveCurrencyManager = {}
ClientGiveCurrencyManager.__index = ClientGiveCurrencyManager

type AmountRow = {
	resource: number,
	balanceAttribute: string,
	amount: number,
	amountBox: TextBox?,
	ownedLabel: TextLabel?,
	confirmFrame: GuiObject?,
	confirmValueLabel: TextLabel?,
}

export type ClientGiveCurrencyManager = typeof(setmetatable(
	{} :: {
		menuGui: ScreenGui?,
		menuDialog: GuiObject?,
		sendPage: GuiObject?,
		confirmPage: GuiObject?,
		titleLabel: TextLabel?,
		confirmNameLabel: TextLabel?,
		thumbnails: { ImageLabel },
		rows: { AmountRow },
		overlay: ClientOverlayManager.Overlay?,
		isMenuOpen: boolean,
		-- counts presses and releases of the plus and minus buttons, so a
		-- held button's repeat stops the moment anything else happens
		holdGeneration: number,
		targetUserId: number?,
	},
	ClientGiveCurrencyManager
))

local NOTIFY_CURRENCY_GIVEN_SHAPE = {
	senderUserId = "integer",
	targetUserId = "integer",
	goldBars = "nonnegativeInteger",
	ironBars = "nonnegativeInteger",
}

local PROMPT_NAME = "GiveCurrencyPrompt"
-- the prompt hangs from a point this far from the middle of the other
-- player's body (a stud lower, so it does not sit over their face)
local PROMPT_ATTACHMENT_NAME = "GiveCurrencyPromptAttachment"
local PROMPT_OFFSET_STUDS = Vector3.new(0, -1, 0)
-- a gift in flight, as bars leave the Refinery: at most this many icons a
-- resource, one after another this far apart
local MAX_ICONS_PER_RESOURCE = 6
local ICON_STAGGER_SEC = 0.08
local GIFT_RESOURCES = { Enums.RefinedResource.GOLD_BAR, Enums.RefinedResource.IRON_BAR }
local GIFT_AMOUNT_KEY: { [number]: string } = {
	[Enums.RefinedResource.GOLD_BAR] = "goldBars",
	[Enums.RefinedResource.IRON_BAR] = "ironBars",
}
local GIFT_COLOR: { [number]: Color3 } = {
	[Enums.RefinedResource.GOLD_BAR] = Color3.fromRGB(245, 200, 80),
	[Enums.RefinedResource.IRON_BAR] = Color3.fromRGB(190, 195, 205),
}
local PROMPT_REFRESH_SEC = 1
local TITLE_FORMAT = "Send currency to %s"
local OWNED_FORMAT = "of %d"
local FEEDBACK_NOTHING = "Choose an amount to send"
local DEFAULT_STEP = 1
-- a held plus or minus button: the wait before its first repeat, what
-- each wait is multiplied by after that, and the shortest wait it reaches
local HOLD_REPEAT_START_SEC = 0.4
local HOLD_REPEAT_SPEED_UP = 0.82
local HOLD_REPEAT_MIN_SEC = 0.02
local DEFAULT_PROMPT_DISTANCE_STUDS = 8
local DEFAULT_PROMPT_ACTION_TEXT = "Give Currency"

local function readNumber(value: any, default: number): number
	return if typeof(value) == "number" then value else default
end

function ClientGiveCurrencyManager:getBalance(row: AmountRow): number
	return readNumber(ClientDataManager:getCurrentPlayerAttribute(row.balanceAttribute), 0)
end

function ClientGiveCurrencyManager:getStep(): number
	return readNumber(ClientDataManager:getGameMetadata(Attributes.GIVE_CURRENCY_STEP), DEFAULT_STEP)
end

function ClientGiveCurrencyManager:isLocalPlayerDead(): boolean
	local data = ClientDataManager:getPlayerPublicData(Players.LocalPlayer.UserId)
	return data ~= nil and data.isDead
end

function ClientGiveCurrencyManager:renderRows()
	for _, row in self.rows do
		local balance = self:getBalance(row)
		-- a balance that fell while the menu was open pulls the amount down
		row.amount = GiveCurrencyRules.stepAmount(row.amount, 0, balance)
		if row.amountBox and not row.amountBox:IsFocused() then
			row.amountBox.Text = tostring(row.amount)
		end
		if row.ownedLabel then
			row.ownedLabel.Text = string.format(OWNED_FORMAT, balance)
		end
		if row.confirmValueLabel then
			row.confirmValueLabel.Text = tostring(row.amount)
		end
		if row.confirmFrame then
			row.confirmFrame.Visible = row.amount > 0
		end
	end
end

function ClientGiveCurrencyManager:showPage(isConfirm: boolean)
	if self.sendPage then
		self.sendPage.Visible = not isConfirm
	end
	if self.confirmPage then
		self.confirmPage.Visible = isConfirm
	end
end

function ClientGiveCurrencyManager:closeMenu()
	if not self.isMenuOpen then
		return
	end
	self.isMenuOpen = false
	self.targetUserId = nil
	if self.menuGui then
		self.menuGui.Enabled = false
	end
	local overlay = self.overlay
	if overlay then
		ClientOverlayManager:notifyEndOverlay(overlay)
	end
end

function ClientGiveCurrencyManager:loadThumbnail(userId: number)
	for _, thumbnail in self.thumbnails do
		thumbnail.Image = ""
	end
	task.spawn(
		function()
			local isSuccess, image = pcall(
				function()
					return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
				end
			)
			-- the menu may have moved on to someone else while this loaded
			if not isSuccess or self.targetUserId ~= userId then
				return
			end
			for _, thumbnail in self.thumbnails do
				thumbnail.Image = image
			end
		end
	)
end

function ClientGiveCurrencyManager:openMenu(target: Player)
	local menuGui = self.menuGui
	local overlay = self.overlay
	if not menuGui or not overlay or self.isMenuOpen or self:isLocalPlayerDead() then
		return
	end
	self.isMenuOpen = true
	self.targetUserId = target.UserId
	for _, row in self.rows do
		row.amount = 0
	end
	if self.titleLabel then
		self.titleLabel.Text = UiStyle.formatTitle(string.format(TITLE_FORMAT, target.DisplayName))
	end
	if self.confirmNameLabel then
		self.confirmNameLabel.Text = target.DisplayName
	end
	self:loadThumbnail(target.UserId)
	self:showPage(false)
	self:renderRows()
	menuGui.Enabled = true
	ClientOverlayManager:notifyBeginOverlay(overlay)
end

function ClientGiveCurrencyManager:getAmount(resource: number): number
	for _, row in self.rows do
		if row.resource == resource then
			return row.amount
		end
	end
	return 0
end

-- Send: on to the confirmation page, unless there is nothing to send
function ClientGiveCurrencyManager:requestSend()
	local goldBars = self:getAmount(Enums.RefinedResource.GOLD_BAR)
	local ironBars = self:getAmount(Enums.RefinedResource.IRON_BAR)
	if goldBars <= 0 and ironBars <= 0 then
		ClientSoundManager:playSfx(SoundNames.Sfx.FAIL)
		ClientPlayerFeedbackManager:giveLocal(FEEDBACK_NOTHING)
		return
	end
	self:renderRows()
	self:showPage(true)
end

function ClientGiveCurrencyManager:confirm()
	local targetUserId = self.targetUserId
	if not targetUserId then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_GIVE_CURRENCY, {
		targetUserId = targetUserId,
		goldBars = self:getAmount(Enums.RefinedResource.GOLD_BAR),
		ironBars = self:getAmount(Enums.RefinedResource.IRON_BAR),
	})
	self:closeMenu()
end

function ClientGiveCurrencyManager:bindRow(sendPage: Instance, confirmPage: Instance?, rowName: string, confirmName: string, resource: number, balanceAttribute: string)
	local rowFrame = sendPage:FindFirstChild(rowName)
	if not rowFrame then
		warn(`ClientGiveCurrencyManager: the GiveCurrency menu has no SendPage.{rowName}`)
		return
	end
	local amountBox = rowFrame:FindFirstChild(Constants.GIVE_CURRENCY_ROW_AMOUNT_BOX)
	local ownedLabel = rowFrame:FindFirstChild(Constants.GIVE_CURRENCY_ROW_OWNED_LABEL)
	local confirmFrame = if confirmPage then confirmPage:FindFirstChild(confirmName) else nil
	local confirmValue = if confirmFrame then confirmFrame:FindFirstChild(Constants.GIVE_CURRENCY_AMOUNT_VALUE_LABEL) else nil
	local row: AmountRow = {
		resource = resource,
		balanceAttribute = balanceAttribute,
		amount = 0,
		amountBox = if amountBox and amountBox:IsA("TextBox") then amountBox else nil,
		ownedLabel = if ownedLabel and ownedLabel:IsA("TextLabel") then ownedLabel else nil,
		confirmFrame = if confirmFrame and confirmFrame:IsA("GuiObject") then confirmFrame else nil,
		confirmValueLabel = if confirmValue and confirmValue:IsA("TextLabel") then confirmValue else nil,
	}
	local imageId = Icons.REFINED_RESOURCE[resource]
	for _, parent in { rowFrame, confirmFrame } do
		local icon = parent:FindFirstChild(Constants.GIVE_CURRENCY_ROW_ICON)
		if icon and icon:IsA("ImageLabel") then
			icon.Image = if Icons.isPlaceholder(imageId) then "" else imageId
		end
	end
	-- a press steps the amount once; holding repeats the step, each
	-- repeat sooner than the last down to a floor, and letting go (or
	-- sliding off the button) puts the pace back to the start
	local function bindStep(buttonName: string, direction: number)
		local button = rowFrame:FindFirstChild(buttonName)
		if not button or not button:IsA("GuiButton") then
			return
		end
		local function step()
			row.amount = GiveCurrencyRules.stepAmount(row.amount, direction * self:getStep(), self:getBalance(row))
			self:renderRows()
		end
		local function release()
			self.holdGeneration += 1
		end
		button.MouseButton1Down:Connect(
			function()
				self.holdGeneration += 1
				local generation = self.holdGeneration
				step()
				task.spawn(
					function()
						local interval = HOLD_REPEAT_START_SEC
						while true do
							task.wait(interval)
							if generation ~= self.holdGeneration or not self.isMenuOpen then
								return
							end
							step()
							interval = math.max(HOLD_REPEAT_MIN_SEC, interval * HOLD_REPEAT_SPEED_UP)
						end
					end
				)
			end
		)
		button.MouseButton1Up:Connect(release)
		button.MouseLeave:Connect(release)
	end
	bindStep(Constants.GIVE_CURRENCY_ROW_MINUS_BUTTON, -1)
	bindStep(Constants.GIVE_CURRENCY_ROW_PLUS_BUTTON, 1)
	local box = row.amountBox
	if box then
		box.FocusLost:Connect(
			function()
				row.amount = GiveCurrencyRules.parseAmount(box.Text, self:getBalance(row))
				self:renderRows()
			end
		)
	end
	ClientDataManager:subscribeCurrentPlayerAttribute(
		balanceAttribute,
		function()
			if self.isMenuOpen then
				self:renderRows()
			end
		end
	)
	table.insert(self.rows, row)
end

function ClientGiveCurrencyManager:findMenu()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local menuGui = playerGui:WaitForChild(Constants.GIVE_CURRENCY_GUI_NAME, 10)
	if not menuGui or not menuGui:IsA("ScreenGui") then
		warn("ClientGiveCurrencyManager: no GiveCurrency ScreenGui; run scripts/studio/build_give_currency_gui.luau")
		return
	end
	menuGui.Enabled = false
	self.menuGui = menuGui
	local dialog = menuGui:FindFirstChild(Constants.GIVE_CURRENCY_DIALOG)
	local sendPage = if dialog then dialog:FindFirstChild(Constants.GIVE_CURRENCY_SEND_PAGE) else nil
	local confirmPage = if dialog then dialog:FindFirstChild(Constants.GIVE_CURRENCY_CONFIRM_PAGE) else nil
	if not dialog or not dialog:IsA("GuiObject") or not sendPage or not sendPage:IsA("GuiObject") then
		warn("ClientGiveCurrencyManager: the GiveCurrency menu has no Dialog.SendPage")
		return
	end
	self.menuDialog = dialog
	self.sendPage = sendPage
	self.confirmPage = if confirmPage and confirmPage:IsA("GuiObject") then confirmPage else nil
	local title = sendPage:FindFirstChild(Constants.GIVE_CURRENCY_TITLE_LABEL)
	self.titleLabel = if title and title:IsA("TextLabel") then title else nil
	local confirmName = if confirmPage then confirmPage:FindFirstChild(Constants.GIVE_CURRENCY_NAME_LABEL) else nil
	self.confirmNameLabel = if confirmName and confirmName:IsA("TextLabel") then confirmName else nil
	for _, page in { sendPage, confirmPage } do
		local thumbnail = page:FindFirstChild(Constants.GIVE_CURRENCY_THUMBNAIL)
		if thumbnail and thumbnail:IsA("ImageLabel") then
			table.insert(self.thumbnails, thumbnail)
		end
	end
	self:bindRow(sendPage, confirmPage, Constants.GIVE_CURRENCY_GOLD_ROW, Constants.GIVE_CURRENCY_GOLD_AMOUNT, Enums.RefinedResource.GOLD_BAR, Attributes.BALANCE_GOLD_BARS)
	self:bindRow(sendPage, confirmPage, Constants.GIVE_CURRENCY_IRON_ROW, Constants.GIVE_CURRENCY_IRON_AMOUNT, Enums.RefinedResource.IRON_BAR, Attributes.BALANCE_IRON_BARS)

	local function bindButton(parent: Instance?, name: string, onActivated: () -> ())
		local button = if parent then parent:FindFirstChild(name) else nil
		if button and button:IsA("GuiButton") then
			button.Activated:Connect(onActivated)
		else
			warn(`ClientGiveCurrencyManager: the GiveCurrency menu has no {name}`)
		end
	end
	bindButton(
		sendPage,
		Constants.GIVE_CURRENCY_SEND_BUTTON,
		function()
			self:requestSend()
		end
	)
	bindButton(
		sendPage,
		Constants.GIVE_CURRENCY_CLOSE_BUTTON,
		function()
			self:closeMenu()
		end
	)
	bindButton(
		confirmPage,
		Constants.GIVE_CURRENCY_CONFIRM_BUTTON,
		function()
			self:confirm()
		end
	)
	bindButton(
		confirmPage,
		Constants.GIVE_CURRENCY_BACK_BUTTON,
		function()
			self:showPage(false)
		end
	)

	local overlay: ClientOverlayManager.Overlay
	overlay = {
		getGuiRoot = function(_overlay)
			return self.menuDialog
		end,
		notifyForceEnd = function(_overlay)
			self:closeMenu()
		end,
		notifyClickOutside = function(_overlay)
			self:closeMenu()
		end,
	}
	self.overlay = overlay
end

-- one prompt on the character's root; a character that streams out and
-- back in arrives without it, so this is called again on a timer
function ClientGiveCurrencyManager:ensurePrompt(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root then
		return
	end
	local data = ClientDataManager:getPlayerPublicData(player.UserId)
	local isEnabled = data ~= nil and not data.isDead and not self:isLocalPlayerDead()
	local attachment = root:FindFirstChild(PROMPT_ATTACHMENT_NAME)
	local existing = if attachment then attachment:FindFirstChild(PROMPT_NAME) else nil
	if existing and existing:IsA("ProximityPrompt") then
		existing.Enabled = isEnabled
		return
	end
	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Name = PROMPT_ATTACHMENT_NAME
	promptAttachment.Position = PROMPT_OFFSET_STUDS
	promptAttachment.Parent = root
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person (2026-09-29)
	prompt.ClickablePrompt = false
	local actionText = ClientDataManager:getGameMetadata(Attributes.GIVE_CURRENCY_PROMPT_ACTION_TEXT)
	prompt.ActionText = if typeof(actionText) == "string" then actionText else DEFAULT_PROMPT_ACTION_TEXT
	prompt.ObjectText = player.DisplayName
	prompt.MaxActivationDistance = readNumber(ClientDataManager:getGameMetadata(Attributes.GIVE_CURRENCY_PROMPT_MAX_DISTANCE_STUDS), DEFAULT_PROMPT_DISTANCE_STUDS)
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Enabled = isEnabled
	prompt.Triggered:Connect(
		function()
			self:openMenu(player)
		end
	)
	prompt.Parent = promptAttachment
end

-- a gift, seen by everyone: the bars fly from the sender to the receiver
-- as they do out of the Refinery. The sender hears each one go, and the
-- receiver hears the Refinery's payout, a pop as each bar lands, and
-- sees its balance row bump
function ClientGiveCurrencyManager:onCurrencyGiven(payload: any)
	local isValid, errorMessage = Validate.isTableShape(payload, NOTIFY_CURRENCY_GIVEN_SHAPE)
	if not isValid then
		warn("ClientGiveCurrencyManager: malformed NotifyCurrencyGiven:", errorMessage)
		return
	end
	local localUserId = Players.LocalPlayer.UserId
	local isSender = payload.senderUserId == localUserId
	local isReceiver = payload.targetUserId == localUserId
	local function rootOf(userId: number): BasePart?
		local player = Players:GetPlayerByUserId(userId)
		local character = if player then player.Character else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		return if root and root:IsA("BasePart") then root else nil
	end
	local fromRoot = rootOf(payload.senderUserId)
	local toRoot = rootOf(payload.targetUserId)
	if isReceiver then
		ClientSoundManager:playSfx(SoundNames.Sfx.REFINERY_PAYOUT)
	end
	local delaySec = 0
	for _, resource in GIFT_RESOURCES do
		local amount = payload[GIFT_AMOUNT_KEY[resource]]
		if amount <= 0 then
			continue
		end
		local count = math.min(amount, MAX_ICONS_PER_RESOURCE)
		for _ = 1, count do
			local function onLanded()
				if isSender or isReceiver then
					ClientSoundManager:playSfx(SoundNames.Sfx.ORE_PICKUP)
				end
				if isReceiver then
					local landedOn = ClientRefineryManager:landingTarget(resource)
					if landedOn then
						ClientIconFlightManager:bump(landedOn)
					end
				end
			end
			-- either player may be streamed out for a watcher far away
			if fromRoot and toRoot then
				ClientIconFlightManager:flyWorld(Icons.REFINED_RESOURCE[resource], GIFT_COLOR[resource], fromRoot.Position, toRoot.Position, delaySec, onLanded)
			else
				task.delay(delaySec, onLanded)
			end
			delaySec += ICON_STAGGER_SEC
		end
	end
end

function ClientGiveCurrencyManager:refreshPrompts()
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer then
			self:ensurePrompt(player)
		end
	end
	-- the player the menu is for left or died: nothing to send to
	local targetUserId = self.targetUserId
	if self.isMenuOpen and targetUserId then
		local data = ClientDataManager:getPlayerPublicData(targetUserId)
		if not data or data.isDead or self:isLocalPlayerDead() then
			self:closeMenu()
		end
	end
end

function ClientGiveCurrencyManager:init()
	self:findMenu()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_CURRENCY_GIVEN,
		function(payload: any)
			self:onCurrencyGiven(payload)
		end
	)
	task.spawn(
		function()
			while true do
				self:refreshPrompts()
				task.wait(PROMPT_REFRESH_SEC)
			end
		end
	)
end

function ClientGiveCurrencyManager.new(): ClientGiveCurrencyManager
	local self = setmetatable({}, ClientGiveCurrencyManager) :: ClientGiveCurrencyManager
	self.menuGui = nil
	self.menuDialog = nil
	self.sendPage = nil
	self.confirmPage = nil
	self.titleLabel = nil
	self.confirmNameLabel = nil
	self.thumbnails = {}
	self.rows = {}
	self.overlay = nil
	self.isMenuOpen = false
	self.holdGeneration = 0
	self.targetUserId = nil
	return self
end

return ClientGiveCurrencyManager.new()
