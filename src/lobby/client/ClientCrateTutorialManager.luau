--!strict

-- The lobby's one tutorial lesson (designer, 2026-11-10): the first time
-- a player's Diamonds cover a Supply Crate, the guide from the run's
-- walkthrough says so in the same Tutorial ScreenGui (the dialogue box
-- with the talking head, then the goal on the Tasks panel), a guide beam
-- leads from the player to the Supply Crate stall, and once the crate
-- menu is open the arrow points at its OPEN CRATE button. Nothing here
-- is scripted by the server: the price is the published gacha config,
-- the balance and the flags are CurrentPlayer attributes. The lesson is
-- over when the server says so (HasFinishedSupplyCrateTutorial, set by
-- GachaManager at the first crate paid for); a player who closes the
-- menu without buying is left alone until their next visit to the lobby.
-- A player PolicyService restricts from paid random items never sees it,
-- since the crate is not theirs to open.
-- The gui, the head, and the beam are the gameplay place's, ported
-- (build_tutorial_gui.luau, build_tutorial_guide_head.luau); the
-- presentation below repeats ClientTutorialManager's on purpose rather
-- than sharing it, since that manager is built round the run's steps.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientGuiFade = require(script.Parent.Parent.Client.ClientGuiFade)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientGachaMenuManager = require(script.Parent.ClientGachaMenuManager)

local ClientCrateTutorialManager = {}
ClientCrateTutorialManager.__index = ClientCrateTutorialManager

-- one of the two fading panels: the dialogue box or the Tasks panel
type Panel = {
	frame: GuiObject?,
	authored: ClientGuiFade.Hidden,
	isShown: boolean,
	-- outdates a hide a later show cut short
	generation: number,
}

export type ClientCrateTutorialManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		authoredDisplayOrder: number,
		dialog: Panel,
		tasks: Panel,
		messageLabel: TextLabel?,
		taskLabel: TextLabel?,
		readBar: GuiObject?,
		readBarFullScale: number,
		arrow: GuiObject?,
		portraitHead: Model?,
		state: number,
		-- the line's start and end, for the read bar; nil once it has left
		lineStartTime: number,
		lineEndTime: number?,
		-- the typewriter's end and the head's talking motion (0 to 1)
		typeEndTime: number,
		talkShare: number,
		lastStepTime: number,
		lastIdleCheckTime: number,
		-- outdates the gui's switch-off when the lesson starts again
		guiGeneration: number,
		beam: Beam?,
		beamFolder: Folder?,
		targetPart: BasePart?,
		rootAttachment: Attachment?,
		stepConnection: RBXScriptConnection?,
	},
	ClientCrateTutorialManager
))

local State = {
	-- waiting for the Diamonds to cover a crate
	IDLE = 1,
	-- the line, then the task, with the beam to the stall
	GUIDING = 2,
	-- the crate menu is open: the arrow at its button
	POINTING = 3,
	-- the menu was closed without a crate: quiet for this visit
	DISMISSED = 4,
}

local LINE_TEXT = "You have enough Diamonds for a Supply Crate! Head over to the Supply Crate Store."
local TASK_TEXT = "Open a Supply Crate at the Supply Crate Store"

-- the same pacing as the run's walkthrough (ClientTutorialManager)
local READ_BASE_SEC = 1.8
local READ_SEC_PER_CHARACTER = 0.055
local READ_MIN_SEC = 3
local READ_MAX_SEC = 8
local TYPE_MAX_SEC = 1.2
local TYPE_SEC_PER_CHARACTER = 0.02
local PANEL_FADE_SEC = 0.35
local ARROW_BOB_SHARE = 0.25
local ARROW_BOB_HZ = 1.2
local ARROW_GAP_SHARE = 0.35
local BEAM_ROOT_OFFSET = Vector3.new(0, -1, 0)
local FOLDER_NAME = "TutorialGuide"
local TALK_NOD_HZ = 2.25
local TALK_NOD_DEGREES = 5
local TALK_SWAY_HZ = 1.7
local TALK_SWAY_DEGREES = 2.5
local TALK_BOB_STUDS = 0.03
local TALK_EASE_PER_SEC = 8
local TALK_NECK_OFFSET = Vector3.new(0, -0.6, 0)
-- how often the idle lesson asks whether it may start
local IDLE_CHECK_INTERVAL_SEC = 0.5
-- the arrow must draw over the crate menu, which the gui sits under
local POINTING_DISPLAY_ORDER = ClientOverlayManager.MENU_DISPLAY_ORDER + 1

local function getRootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- the lesson may run: not learnt yet, the crate is this player's to
-- open, and the Diamonds cover one
function ClientCrateTutorialManager:canGuide(): boolean
	if ClientDataManager:getCurrentPlayerAttribute(Attributes.HAS_FINISHED_SUPPLY_CRATE_TUTORIAL) == true then
		return false
	end
	if ClientDataManager:isPaidRandomItemsRestricted() then
		return false
	end
	local price = ClientGachaMenuManager:getRollPrice()
	return price ~= nil and ClientDataManager:getDiamonds() >= price
end

function ClientCrateTutorialManager:setPanelShown(panel: Panel, isShown: boolean)
	local frame = panel.frame
	if not frame or panel.isShown == isShown then
		return
	end
	panel.isShown = isShown
	panel.generation += 1
	local generation = panel.generation
	if isShown then
		frame.Visible = true
	end
	ClientGuiFade.tweenShown(panel.authored, isShown, PANEL_FADE_SEC)
	if not isShown then
		task.delay(
			PANEL_FADE_SEC,
			function()
				if generation == panel.generation then
					frame.Visible = false
				end
			end
		)
	end
end

-- the gui is on for as long as the lesson shows anything, and goes off
-- once the last panel has faded
function ClientCrateTutorialManager:setGuiEnabled(isEnabled: boolean)
	local gui = self.gui
	if not gui then
		return
	end
	self.guiGeneration += 1
	local generation = self.guiGeneration
	if isEnabled then
		gui.Enabled = true
		return
	end
	task.delay(
		PANEL_FADE_SEC,
		function()
			if generation == self.guiGeneration then
				gui.Enabled = false
			end
		end
	)
end

-- an asset under GameAssets/Tutorial (the head, the beam)
function ClientCrateTutorialManager:findTutorialAsset(name: string): Instance?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.TUTORIAL_ASSETS_FOLDER) else nil
	return if folder then folder:FindFirstChild(name) else nil
end

-- where the beam leads: the stall's touch volume, the part whose box
-- opens the crate menu
function ClientCrateTutorialManager:findStorePosition(): Vector3?
	local folder = workspace:FindFirstChild(Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER)
	local part = if folder then folder:FindFirstChild(Constants.STORE_MENU_TOUCH_PART) else nil
	return if part and part:IsA("BasePart") then part.Position else nil
end

-- the designer's GuideBeam hung between an attachment on the character's
-- root (made again after a respawn) and an invisible anchored part
function ClientCrateTutorialManager:ensureBeam(): Beam?
	local root = getRootPart()
	if not root then
		return nil
	end
	local folder = self.beamFolder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = workspace
		self.beamFolder = folder
	end
	local targetPart = self.targetPart
	if not targetPart then
		targetPart = Instance.new("Part")
		targetPart.Name = "Target"
		targetPart.Anchored = true
		targetPart.CanCollide = false
		targetPart.CanQuery = false
		targetPart.CanTouch = false
		targetPart.Transparency = 1
		targetPart.Size = Vector3.one
		local targetAttachment = Instance.new("Attachment")
		targetAttachment.Name = "BeamEnd"
		targetAttachment.Parent = targetPart
		targetPart.Parent = folder
		self.targetPart = targetPart
	end
	local rootAttachment = self.rootAttachment
	if not rootAttachment or rootAttachment.Parent ~= root then
		if rootAttachment then
			rootAttachment:Destroy()
		end
		rootAttachment = Instance.new("Attachment")
		rootAttachment.Name = "TutorialBeamStart"
		rootAttachment.Position = BEAM_ROOT_OFFSET
		rootAttachment.Parent = root
		self.rootAttachment = rootAttachment
		local existingBeam = self.beam
		if existingBeam then
			existingBeam.Attachment0 = rootAttachment
		end
	end
	local beam = self.beam
	if not beam then
		local template = self:findTutorialAsset(Constants.TUTORIAL_GUIDE_BEAM_TEMPLATE)
		if not template or not template:IsA("Beam") then
			warn("ClientCrateTutorialManager: no GameAssets.Tutorial.GuideBeam; run scripts/studio/build_tutorial_guide_head.luau in the lobby place")
			return nil
		end
		beam = template:Clone()
		beam.Attachment0 = rootAttachment :: Attachment
		beam.Attachment1 = (targetPart :: BasePart):FindFirstChild("BeamEnd") :: Attachment
		beam.Enabled = false
		beam.Parent = folder
		self.beam = beam
	end
	return beam
end

function ClientCrateTutorialManager:placeBeam(isShown: boolean)
	local beam = if isShown then self:ensureBeam() else self.beam
	if not beam then
		return
	end
	local target = if isShown then self:findStorePosition() else nil
	local targetPart = self.targetPart
	if not target or not targetPart then
		beam.Enabled = false
		return
	end
	targetPart.Position = target
	beam.Enabled = true
end

-- the arrow sits left of the button, points right at it, and bobs
-- toward it; hidden while the button cannot be pressed
function ClientCrateTutorialManager:placeArrow(target: GuiObject?)
	local arrow = self.arrow
	local gui = self.gui
	if not arrow or not gui then
		return
	end
	if not target then
		arrow.Visible = false
		return
	end
	local targetPosition = target.AbsolutePosition
	local targetSize = target.AbsoluteSize
	local arrowSize = arrow.AbsoluteSize.X
	local bob = math.sin(workspace:GetServerTimeNow() * ARROW_BOB_HZ * math.pi * 2) * arrowSize * ARROW_BOB_SHARE
	local centreX = targetPosition.X - arrowSize * (ARROW_GAP_SHARE + 0.5) + bob
	local centreY = targetPosition.Y + targetSize.Y * 0.5
	local guiOrigin = gui.AbsolutePosition
	arrow.Position = UDim2.fromOffset(centreX - guiOrigin.X, centreY - guiOrigin.Y)
	-- the picture points down at Rotation 0
	arrow.Rotation = -90
	arrow.Visible = true
end

-- the head nods while the line types out and eases back to rest after
function ClientCrateTutorialManager:stepTalk(now: number)
	local head = self.portraitHead
	local deltaSec = math.clamp(now - self.lastStepTime, 0, 0.1)
	self.lastStepTime = now
	if not head then
		return
	end
	local goal = if now < self.typeEndTime then 1 else 0
	local share = self.talkShare
	if share == goal and goal == 0 then
		return
	end
	local change = TALK_EASE_PER_SEC * deltaSec
	share = if goal > share then math.min(share + change, goal) else math.max(share - change, goal)
	self.talkShare = share
	local nod = math.sin(now * TALK_NOD_HZ * math.pi * 2)
	local sway = math.sin(now * TALK_SWAY_HZ * math.pi * 2)
	local turn = CFrame.Angles(math.rad(nod * TALK_NOD_DEGREES * share), math.rad(sway * TALK_SWAY_DEGREES * share), 0)
	local bob = Vector3.new(0, math.abs(nod) * TALK_BOB_STUDS * share, 0)
	head:PivotTo(CFrame.new(TALK_NECK_OFFSET + bob) * turn * CFrame.new(-TALK_NECK_OFFSET))
end

function ClientCrateTutorialManager:startGuiding(now: number)
	self.state = State.GUIDING
	local gui = self.gui
	if gui then
		gui.DisplayOrder = self.authoredDisplayOrder
	end
	self:setGuiEnabled(true)
	local label = self.messageLabel
	if label then
		label.Text = LINE_TEXT
		label.MaxVisibleGraphemes = 0
		local graphemeCount = utf8.len(LINE_TEXT) or #LINE_TEXT
		local typeSec = math.min(TYPE_MAX_SEC, graphemeCount * TYPE_SEC_PER_CHARACTER)
		TweenService:Create(label, TweenInfo.new(typeSec, Enum.EasingStyle.Linear), { MaxVisibleGraphemes = graphemeCount }):Play()
		self.typeEndTime = now + typeSec
	end
	local taskLabel = self.taskLabel
	if taskLabel then
		taskLabel.Text = TASK_TEXT
	end
	self.lineStartTime = now
	self.lineEndTime = now + math.clamp(READ_BASE_SEC + #LINE_TEXT * READ_SEC_PER_CHARACTER, READ_MIN_SEC, READ_MAX_SEC)
	self:setPanelShown(self.tasks, false)
	self:setPanelShown(self.dialog, true)
	self:placeBeam(true)
	ClientSoundManager:playSfx(SoundNames.Sfx.TUTORIAL_PROMPT)
end

-- the crate menu is up: the line, the task, and the beam make way for
-- the arrow, and the gui is lifted over the menu for as long as it points
function ClientCrateTutorialManager:startPointing()
	self.state = State.POINTING
	self.lineEndTime = nil
	self:setPanelShown(self.dialog, false)
	self:setPanelShown(self.tasks, false)
	self:placeBeam(false)
	local gui = self.gui
	if gui then
		gui.DisplayOrder = POINTING_DISPLAY_ORDER
	end
	self:setGuiEnabled(true)
end

-- everything off; the gui goes back under the menus once it has faded
function ClientCrateTutorialManager:stop(state: number)
	self.state = state
	self.lineEndTime = nil
	self:setPanelShown(self.dialog, false)
	self:setPanelShown(self.tasks, false)
	self:placeBeam(false)
	self:placeArrow(nil)
	self:setGuiEnabled(false)
end

function ClientCrateTutorialManager:stepGuiding(now: number)
	if not self:canGuide() then
		-- the Diamonds were spent elsewhere, or the lesson was learnt
		self:stop(State.IDLE)
		return
	end
	if ClientGachaMenuManager:getIsOpen() then
		self:startPointing()
		return
	end
	self:placeBeam(true)
	local lineEndTime = self.lineEndTime
	if not lineEndTime then
		return
	end
	local readBar = self.readBar
	if readBar then
		local share = math.clamp((lineEndTime - now) / math.max(lineEndTime - self.lineStartTime, 0.01), 0, 1)
		readBar.Size = UDim2.fromScale(self.readBarFullScale * share, readBar.Size.Y.Scale)
	end
	if now >= lineEndTime then
		-- the line has been read: the goal takes its place
		self.lineEndTime = nil
		self:setPanelShown(self.dialog, false)
		self:setPanelShown(self.tasks, true)
	end
end

function ClientCrateTutorialManager:stepPointing()
	if ClientDataManager:getCurrentPlayerAttribute(Attributes.HAS_FINISHED_SUPPLY_CRATE_TUTORIAL) == true then
		-- a crate was paid for: the lesson is over for good
		self:stop(State.IDLE)
		return
	end
	if not ClientGachaMenuManager:getIsOpen() then
		self:stop(State.DISMISSED)
		return
	end
	self:placeArrow(ClientGachaMenuManager:getReadyRollButton())
end

function ClientCrateTutorialManager:step()
	local now = workspace:GetServerTimeNow()
	self:stepTalk(now)
	local state = self.state
	if state == State.GUIDING then
		self:stepGuiding(now)
	elseif state == State.POINTING then
		self:stepPointing()
	elseif state == State.IDLE then
		if now - self.lastIdleCheckTime < IDLE_CHECK_INTERVAL_SEC then
			return
		end
		self.lastIdleCheckTime = now
		if not self:canGuide() then
			return
		end
		if ClientGachaMenuManager:getIsOpen() then
			self:startPointing()
		elseif not ClientOverlayManager:isOverlayActive() then
			self:startGuiding(now)
		end
	end
end

-- the guide's head in the portrait: the GameAssets model cloned in, the
-- camera on its face (the same shot as the run's walkthrough)
function ClientCrateTutorialManager:fillPortrait(portrait: ViewportFrame)
	local template = self:findTutorialAsset(Constants.TUTORIAL_GUIDE_HEAD_MODEL)
	if not template or not template:IsA("Model") then
		warn("ClientCrateTutorialManager: no GameAssets.Tutorial.GuideHead; run scripts/studio/build_tutorial_guide_head.luau in the lobby place")
		return
	end
	local head = template:Clone()
	head:PivotTo(CFrame.new())
	head.Parent = portrait
	self.portraitHead = head
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0.15, 0.25, -3.2), Vector3.new(0, 0.2, 0))
	camera.Parent = portrait
	portrait.CurrentCamera = camera
end

function ClientCrateTutorialManager:bindPanel(panel: Panel, frame: Instance?)
	if not frame or not frame:IsA("GuiObject") then
		return
	end
	panel.frame = frame
	frame.Visible = false
	panel.authored = ClientGuiFade.capture(frame)
	ClientGuiFade.setHidden(panel.authored)
end

function ClientCrateTutorialManager:findGui(): boolean
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.TUTORIAL_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientCrateTutorialManager: no Tutorial ScreenGui; run scripts/studio/build_tutorial_gui.luau in the lobby place")
		return false
	end
	gui.Enabled = false
	self.gui = gui
	self.authoredDisplayOrder = gui.DisplayOrder
	self:bindPanel(self.dialog, gui:FindFirstChild(Constants.TUTORIAL_DIALOG_FRAME))
	self:bindPanel(self.tasks, gui:FindFirstChild(Constants.TUTORIAL_TASKS_FRAME))
	local message = gui:FindFirstChild(Constants.TUTORIAL_MESSAGE_LABEL, true)
	self.messageLabel = if message and message:IsA("TextLabel") then message else nil
	local taskLabel = gui:FindFirstChild(Constants.TUTORIAL_TASK_LABEL, true)
	self.taskLabel = if taskLabel and taskLabel:IsA("TextLabel") then taskLabel else nil
	local readBar = gui:FindFirstChild(Constants.TUTORIAL_READ_BAR, true)
	self.readBar = if readBar and readBar:IsA("GuiObject") then readBar else nil
	self.readBarFullScale = if self.readBar then self.readBar.Size.X.Scale else 0
	local arrow = gui:FindFirstChild(Constants.TUTORIAL_ARROW)
	self.arrow = if arrow and arrow:IsA("GuiObject") then arrow else nil
	if self.arrow then
		self.arrow.Visible = false
	end
	local portrait = gui:FindFirstChild(Constants.TUTORIAL_PORTRAIT_VIEWPORT, true)
	if portrait and portrait:IsA("ViewportFrame") then
		self:fillPortrait(portrait)
	end
	return true
end

function ClientCrateTutorialManager:init()
	if not self:findGui() then
		return
	end
	self.stepConnection = RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function ClientCrateTutorialManager.new(): ClientCrateTutorialManager
	local self = setmetatable({}, ClientCrateTutorialManager) :: ClientCrateTutorialManager
	self.authoredDisplayOrder = 0
	self.dialog = { frame = nil, authored = {}, isShown = false, generation = 0 }
	self.tasks = { frame = nil, authored = {}, isShown = false, generation = 0 }
	self.readBarFullScale = 0
	self.state = State.IDLE
	self.lineStartTime = 0
	self.lineEndTime = nil
	self.typeEndTime = 0
	self.talkShare = 0
	self.lastStepTime = 0
	self.lastIdleCheckTime = 0
	self.guiGeneration = 0
	return self
end

return ClientCrateTutorialManager.new()
