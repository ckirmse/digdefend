--!strict

-- The first-run walkthrough on this client (M76, 2026-11-09): the lobby's
-- Class Selection salesperson talks a new player through day 1, the first
-- sunset, the first night, and the dawn after, in the Tutorial ScreenGui's
-- dialogue box (the head in a ViewportFrame and the line). The
-- words are TutorialScript; every condition a step waits on is judged
-- here from state the client already has (the backpack and balance
-- attributes, the equipped tool, the mine's grid, the run's day and
-- phase, the post models), so the server scripts nothing and only owns
-- the HasFinishedTutorial flag (TutorialManager: set at the dawn after
-- the first night). There is no NEXT and no SKIP (designer, 2026-11-09):
-- a line is read in its own time or waited out. The HUD arrow is
-- one ImageLabel parked beside the element a step names and bobbing
-- toward it; the guide beam is one Beam from the player's root to an
-- invisible anchored part this client moves to the step's world target
-- (the mine entrance from the grid's origin, the Refinery from the
-- compass's home, the pick axe stand, the nearest unclaimed post sign,
-- re-picked while the step is up). Sequences: the day 1 one starts when
-- the DAY 1 card closes, the sunset and night ones replace whatever is
-- playing, the morning one ends the walkthrough, and the first Iron and
-- the first Uranium wait their turn behind what is up.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BackpackRules = require("@game/ReplicatedStorage/Shared/BackpackRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local StoreRules = require("@game/ReplicatedStorage/Shared/StoreRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientGuiFade = require(script.Parent.Parent.Client.ClientGuiFade)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientMineManager = require(script.Parent.ClientMineManager)
local ClientRunCycleManager = require(script.Parent.ClientRunCycleManager)
local ClientToolBarManager = require(script.Parent.ClientToolBarManager)
local TutorialScript = require(script.Parent.TutorialScript)

local ClientTutorialManager = {}
ClientTutorialManager.__index = ClientTutorialManager

-- where the arrow sits relative to its target and which way it points:
-- the picture points down at Rotation 0, Rotation turns clockwise
type ArrowSide = {
	-- the target's edge the arrow hangs off, as a share of its size from
	-- its top-left corner
	anchor: Vector2,
	-- the arrow's own anchor against that edge, and the push away from it
	-- in arrow sizes
	offset: Vector2,
	rotation: number,
	-- the bob direction in screen space (toward the target)
	bob: Vector2,
}

export type ClientTutorialManager = typeof(setmetatable(
	{} :: {
		gui: ScreenGui?,
		dialog: GuiObject?,
		portrait: ViewportFrame?,
		messageLabel: TextLabel?,
		readBar: GuiObject?,
		-- the Tasks panel (designer, 2026-11-09): the goal of a waiting step
		tasksFrame: GuiObject?,
		taskLabel: TextLabel?,
		isTasksShown: boolean,
		isDialogShown: boolean,
		-- each panel's authored transparencies, captured once; the fades
		-- run between them and 1
		dialogAuthored: ClientGuiFade.Hidden,
		tasksAuthored: ClientGuiFade.Hidden,
		-- outdates a fade-out a show cut short, per panel
		dialogFadeGeneration: number,
		tasksFadeGeneration: number,
		-- a waiting step's line leaves the dialogue at this server time and
		-- its goal stays on the Tasks panel
		lineEndTime: number?,
		arrow: GuiObject?,
		-- true while the walkthrough may start its sequences: the save's
		-- flag was false at Ready (or was reset by the dev tool); false
		-- again after SKIP or the morning lines
		isArmed: boolean,
		-- the sequences that have played, so each fires once
		playedKeys: { [string]: boolean },
		-- the running sequence and the ones queued behind it
		sequence: TutorialScript.Sequence?,
		stepIndex: number,
		pending: { TutorialScript.Sequence },
		-- the step on screen, nil between steps
		currentStep: TutorialScript.Step?,
		-- the read bar's authored width, drained by the reading time
		readBarFullScale: number,
		-- a step without a wait leaves at this server time
		stepEndTime: number?,
		stepStartTime: number,
		-- the first Iron, Gold, and Uranium seen in the backpack, and the
		-- first Gold Bars credited, each latched for good
		hasMinedByResource: { [number]: boolean },
		hasRefinedGold: boolean,
		-- the pick axe level at Ready, so a bought rung is a rise from it
		pickAxeLevelAtStart: number,
		-- the mine-and-refine loop toward the pick axe price: the ore the
		-- current trip is for, fixed as its step is shown, and the Gold
		-- Bars held as the step began (a rise is a refine)
		goldOreTarget: number,
		goldBarsAtStepStart: number,
		-- the jet pack seen burning since the current step began (the
		-- jet pack task; the flag is the player's own public IsJetPackBurning)
		hasBurnedJetPackThisStep: boolean,
		-- the world beam and its moving far end
		beam: Beam?,
		beamFolder: Folder?,
		targetPart: BasePart?,
		rootAttachment: Attachment?,
		beamTargetName: string?,
		-- the template's transparency, faded to 1 when a step's beamUntil
		-- holds; nil while no fade runs
		beamAuthoredTransparency: NumberSequence?,
		beamFadeStartTime: number?,
		lastPostPickTime: number,
		stepConnection: RBXScriptConnection?,
		disconnects: { () -> () },
	},
	ClientTutorialManager
))

-- a line without a wait stays this long: a base plus a share per character
local READ_BASE_SEC = 1.8
local READ_SEC_PER_CHARACTER = 0.055
local READ_MIN_SEC = 3
local READ_MAX_SEC = 8
-- the typewriter: the whole line in at most this long
local TYPE_MAX_SEC = 1.2
local TYPE_SEC_PER_CHARACTER = 0.02
-- the arrow's bob toward its target, in arrow sizes and per second
local ARROW_BOB_SHARE = 0.25
local ARROW_BOB_HZ = 1.2
-- how far the arrow sits from the target's edge, in arrow sizes
local ARROW_GAP_SHARE = 0.35
-- the beam's far end floats this high over its target, and the near end
-- hangs under the player's chest
local BEAM_TARGET_RISE_STUDS = 3
local BEAM_ROOT_OFFSET = Vector3.new(0, -1, 0)
-- the nearest unclaimed post is re-picked this often while the beam leads to it
local POST_PICK_INTERVAL_SEC = 0.5
-- the beam's fade once its step's beamUntil holds
local BEAM_FADE_SEC = 0.6
-- standing this close to the entrance mouth counts as in the mine
local ENTRANCE_REACH_STUDS = 10
local FIRST_DAY = 1
local FOLDER_NAME = "TutorialGuide"
-- the dialogue and the Tasks panel fade in and out
local PANEL_FADE_SEC = 0.35
local PROGRESS_FORMAT = "%s (%d/%d)"

-- the arrow beside each HUD element: right of the Balances (pointing
-- left), left of the backpack button (pointing right), above the pick
-- axe slot (pointing down), left of the clock's badge (pointing right)
local ARROW_SIDES: { [string]: ArrowSide } = {
	uranium = { anchor = Vector2.new(1, 0.5), offset = Vector2.new(0, 0.5), rotation = 90, bob = Vector2.new(-1, 0) },
	gold = { anchor = Vector2.new(1, 0.5), offset = Vector2.new(0, 0.5), rotation = 90, bob = Vector2.new(-1, 0) },
	backpack = { anchor = Vector2.new(0, 0.5), offset = Vector2.new(1, 0.5), rotation = -90, bob = Vector2.new(1, 0) },
	pickAxe = { anchor = Vector2.new(0.5, 0), offset = Vector2.new(0.5, 1), rotation = 0, bob = Vector2.new(0, 1) },
	-- left of the clock's phase badge (the compass sits under the clock)
	clock = { anchor = Vector2.new(0, 0.5), offset = Vector2.new(1, 0.5), rotation = -90, bob = Vector2.new(1, 0) },
}

local function readNumberAttribute(key: string): number
	local value = ClientDataManager:getCurrentPlayerAttribute(key)
	return if typeof(value) == "number" then value else 0
end

local function getRootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function findStarterGuiChild(guiName: string, childName: string): GuiObject?
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local gui = if playerGui then playerGui:FindFirstChild(guiName) else nil
	local child = if gui then gui:FindFirstChild(childName, true) else nil
	return if child and child:IsA("GuiObject") then child else nil
end

-- the HUD element each arrow name means; looked up per frame because the
-- tool bar rebuilds its slots
function ClientTutorialManager:findArrowTarget(name: string): GuiObject?
	if name == "uranium" then
		return findStarterGuiChild(Constants.GAMEPLAY_HUD_GUI_NAME, Constants.HUD_BALANCE_URANIUM_ROW)
	elseif name == "gold" then
		return findStarterGuiChild(Constants.GAMEPLAY_HUD_GUI_NAME, Constants.HUD_BALANCE_GOLD_ROW)
	elseif name == "backpack" then
		return findStarterGuiChild(Constants.GAMEPLAY_HUD_GUI_NAME, Constants.HUD_BACKPACK_BUTTON)
	elseif name == "pickAxe" then
		return ClientToolBarManager:getSlotFrame(Enums.ToolKind.PICK_AXE)
	elseif name == "clock" then
		return findStarterGuiChild(Constants.DAY_CLOCK_GUI_NAME, Constants.DAY_CLOCK_PHASE_ICON)
	end
	warn(`ClientTutorialManager: no arrow target named {name}`)
	return nil
end

function ClientTutorialManager:isInMine(): boolean
	local root = getRootPart()
	local space = ClientMineManager:getSpace()
	local grid = ClientMineManager:getGrid()
	if not root or not space then
		return false
	end
	if (root.Position - space.origin).Magnitude <= ENTRANCE_REACH_STUDS then
		return true
	end
	return grid ~= nil and MineSpace.containsPosition(space, grid.depth, grid.height, grid.width, root.Position)
end

-- inside the Refinery's ring, judged the server's way: the flat distance
-- to the Refinery against the published refine radius
function ClientTutorialManager:isAtRefinery(): boolean
	local root = getRootPart()
	local home = ClientDataManager:getGameMetadata(Attributes.COMPASS_HOME_POSITION)
	local radius = ClientDataManager:getGameMetadata(Attributes.REFINE_RADIUS_STUDS)
	if not root or typeof(home) ~= "Vector3" or typeof(radius) ~= "number" then
		return false
	end
	local offset = root.Position - home
	return Vector2.new(offset.X, offset.Z).Magnitude <= radius
end

function ClientTutorialManager:isBackpackFull(): boolean
	local capacity = readNumberAttribute(Attributes.BACKPACK_CAPACITY)
	local total = 0
	for _, resource in Enums.getAllValues(Enums.RawResource) do
		total += readNumberAttribute(BackpackRules.attributeForResource(resource) :: string)
	end
	return capacity > 0 and total >= capacity
end

-- the next pick axe rung's Gold price, from the store catalogue the
-- server publishes; the designer's 25 when the catalogue is not up yet
function ClientTutorialManager:getPickAxePrice(): number
	local catalog = StoreRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.STORE_CATALOG))
	local offer = if catalog then StoreRules.getOffer(catalog, Enums.StoreItem.PICK_AXE, self.pickAxeLevelAtStart) else nil
	return if offer and offer.price then offer.price else 25
end

-- every condition a step can wait on or skip by, and every number a
-- line can show, by the names TutorialScript uses
function ClientTutorialManager:judge(name: string): boolean
	if name == "inMine" then
		return self:isInMine()
	elseif name == "pickAxeEquipped" then
		return ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL) == Enums.ToolKind.PICK_AXE
	elseif name == "minedGold" then
		return self.hasMinedByResource[Enums.RawResource.GOLD_ORE] == true
	elseif name == "backpackFull" then
		return self:isBackpackFull()
	elseif name == "refinedGold" then
		return self.hasRefinedGold
	elseif name == "hasPickAxeGold" then
		return readNumberAttribute(Attributes.BALANCE_GOLD_BARS) >= self:getPickAxePrice()
	elseif name == "pickAxeBought" then
		return readNumberAttribute(Attributes.PICK_AXE_LEVEL) > self.pickAxeLevelAtStart
	elseif name == "postClaimed" then
		return readNumberAttribute(Attributes.POST_INDEX) ~= PostRules.NO_POST
	elseif name == "postManned" then
		return readNumberAttribute(Attributes.MANNED_POST_INDEX) ~= PostRules.NO_POST
	elseif name == "atRefinery" then
		return self:isAtRefinery()
	elseif name == "goldOreMinedEnough" then
		-- a refine seen mid-step counts too: the fill and the trip can land
		-- in one replication batch, and the bars are what the price needs
		return readNumberAttribute(Attributes.BACKPACK_GOLD_ORE) >= self.goldOreTarget
			or self:isBackpackFull()
			or readNumberAttribute(Attributes.BALANCE_GOLD_BARS) > self.goldBarsAtStepStart
	elseif name == "goldOreRefined" then
		return readNumberAttribute(Attributes.BALANCE_GOLD_BARS) > self.goldBarsAtStepStart
	elseif name == "goldOreRefinedOrEnough" then
		return self:judge("goldOreRefined") or self:judge("hasPickAxeGold")
	elseif name == "jetPackUsed" then
		if ClientDataManager:getPublicAttribute(Players.LocalPlayer.UserId, Attributes.IS_JET_PACK_BURNING) == true then
			self.hasBurnedJetPackThisStep = true
		end
		return self.hasBurnedJetPackThisStep
	end
	warn(`ClientTutorialManager: no condition named {name}`)
	return true
end

-- the Gold Ore the pick axe price still needs after the bars in hand and
-- the ore already carried, at the published refine rate, capped at what
-- the backpack holds, since a trip refines a backpack at most
function ClientTutorialManager:computeGoldOreTarget(): number
	local rate = ClientDataManager:getGameMetadata(Attributes.REFINE_GOLD_RATE)
	local barsPerOre = if typeof(rate) == "number" and rate > 0 then rate else 1
	local barsShort = math.max(self:getPickAxePrice() - readNumberAttribute(Attributes.BALANCE_GOLD_BARS), 0)
	local oreNeeded = math.ceil(barsShort / barsPerOre)
	local capacity = readNumberAttribute(Attributes.BACKPACK_CAPACITY)
	if capacity > 0 then
		oreNeeded = math.min(oreNeeded, capacity)
	end
	return math.max(oreNeeded, 1)
end

function ClientTutorialManager:readNumberFor(name: string): number
	if name == "pickAxePrice" then
		return self:getPickAxePrice()
	elseif name == "goldOreNeeded" then
		return self.goldOreTarget
	end
	warn(`ClientTutorialManager: no number named {name}`)
	return 0
end

-- the world point each beam name leads to, and whether it is a prompt
-- (the beam ends on it, with no rise); nil while it cannot be known yet
-- (the camp still streaming in, no unclaimed post left)
function ClientTutorialManager:findBeamTarget(name: string): (Vector3?, boolean)
	if name == "mineEntrance" then
		local space = ClientMineManager:getSpace()
		return if space then space.origin else nil, false
	elseif name == "refinery" then
		local home = ClientDataManager:getGameMetadata(Attributes.COMPASS_HOME_POSITION)
		if typeof(home) == "Vector3" then
			return home, false
		end
		local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
		local refinery = if camp then camp:FindFirstChild(Constants.CAMP_REFINERY_MODEL) else nil
		return if refinery and refinery:IsA("PVInstance") then refinery:GetPivot().Position else nil, false
	elseif name == "ownPostWeapon" then
		return self:findOwnPostWeaponPrompt(), true
	elseif name == "pickAxeStand" then
		local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
		local store = if camp then camp:FindFirstChild(Constants.CAMP_MINING_STORE_MODEL) else nil
		local stands = if store then store:FindFirstChild(Constants.MINING_STORE_STANDS_FOLDER) else nil
		local stand = if stands then stands:FindFirstChild(StoreRules.standNameForItem(Enums.StoreItem.PICK_AXE) :: string) else nil
		local base = if stand then stand:FindFirstChild(Constants.STAND_BASE_PART) else nil
		return if base and base:IsA("BasePart") then base.Position else nil, false
	elseif name == "nearestPost" then
		return self:findNearestUnclaimedSign(), true
	end
	warn(`ClientTutorialManager: no beam target named {name}`)
	return nil, false
end

-- a prompt's own point: the server parents a sign's Claim prompt to an
-- attachment under the sign part and a weapon's Use prompt to its Prompt
-- part, so the beam ends where the prompt shows
local function promptPoint(holder: Instance): Vector3?
	local prompt = holder:FindFirstChildWhichIsA("ProximityPrompt", true)
	local parent = if prompt then prompt.Parent else nil
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	elseif holder:IsA("BasePart") then
		return holder.Position
	end
	return nil
end

-- the Use prompt of the weapon on the player's own post
function ClientTutorialManager:findOwnPostWeaponPrompt(): Vector3?
	local ownIndex = readNumberAttribute(Attributes.POST_INDEX)
	if ownIndex == PostRules.NO_POST then
		return nil
	end
	for _, model in CollectionService:GetTagged(Tags.POST_WEAPON) do
		if model:GetAttribute(Attributes.POST_WEAPON_POST_INDEX) ~= ownIndex then
			continue
		end
		local promptPart = model:FindFirstChild(Constants.POST_WEAPON_PROMPT_PART)
		return promptPoint(promptPart or model)
	end
	return nil
end

function ClientTutorialManager:findNearestUnclaimedSign(): Vector3?
	local root = getRootPart()
	local nearest: Vector3? = nil
	local nearestDistance = math.huge
	for _, model in CollectionService:GetTagged(Tags.POST) do
		local owner = model:GetAttribute(Attributes.POST_OWNER_USER_ID)
		if typeof(owner) == "number" and owner ~= PostRules.NOBODY then
			continue
		end
		local signModel = model:FindFirstChild(Constants.POST_SIGN_MODEL)
		local signPart = if signModel then signModel:FindFirstChild(Constants.POST_SIGN_PART) else nil
		if not signPart or not signPart:IsA("BasePart") then
			continue
		end
		local distance = if root then (signPart.Position - root.Position).Magnitude else 0
		if distance < nearestDistance then
			nearestDistance = distance
			nearest = promptPoint(signPart)
		end
	end
	return nearest
end

-- the beam lives in its own Workspace folder with the far-end part; the
-- near end is an attachment on whatever root the character has now
function ClientTutorialManager:ensureBeam(): Beam?
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
		local beam = self.beam
		if beam then
			beam.Attachment0 = rootAttachment
		end
	end
	local beam = self.beam
	if not beam then
		-- the designer's Beam under GameAssets/Tutorial (its look, width,
		-- texture, and speed are tuned there, 2026-11-09); the code only
		-- hangs it between the two attachments
		local template = self:findTutorialAsset(Constants.TUTORIAL_GUIDE_BEAM_TEMPLATE)
		if not template or not template:IsA("Beam") then
			warn("ClientTutorialManager: no GameAssets.Tutorial.GuideBeam; run scripts/studio/build_tutorial_guide_head.luau")
			return nil
		end
		beam = template:Clone()
		self.beamAuthoredTransparency = beam.Transparency
		beam.Attachment0 = rootAttachment :: Attachment
		beam.Attachment1 = (targetPart :: BasePart):FindFirstChild("BeamEnd") :: Attachment
		beam.Enabled = false
		beam.Parent = folder
		self.beam = beam
	end
	return beam
end

function ClientTutorialManager:setBeamTarget(name: string?)
	self.beamTargetName = name
	self.beamFadeStartTime = nil
	local beam = self:ensureBeam()
	if not beam then
		return
	end
	beam.Enabled = false
	local authored = self.beamAuthoredTransparency
	if authored then
		beam.Transparency = authored
	end
	if name then
		self:placeBeam(true)
	end
end

-- the beam eases to clear over BEAM_FADE_SEC, then goes, when a step's
-- beamUntil holds before the step is done (the Refinery reached, the
-- refine still to run); a NumberSequence cannot be tweened, so each
-- keypoint is lerped toward 1 by hand
function ClientTutorialManager:stepBeamFade(now: number)
	local step = self.currentStep
	local beam = self.beam
	local authored = self.beamAuthoredTransparency
	if not step or not beam or not authored or not self.beamTargetName then
		return
	end
	local startTime = self.beamFadeStartTime
	if not startTime then
		if step.beamUntil and self:judge(step.beamUntil) then
			self.beamFadeStartTime = now
		end
		return
	end
	local share = math.clamp((now - startTime) / BEAM_FADE_SEC, 0, 1)
	local keypoints = {}
	for _, keypoint in authored.Keypoints do
		table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value + (1 - keypoint.Value) * share, keypoint.Envelope))
	end
	beam.Transparency = NumberSequence.new(keypoints)
	if share >= 1 then
		self:setBeamTarget(nil)
	end
end

-- the far end follows a target that can move (the nearest post sign
-- changes as posts are claimed) or arrive late (the camp streaming in)
function ClientTutorialManager:placeBeam(isForced: boolean)
	local name = self.beamTargetName
	local beam = self:ensureBeam()
	local targetPart = self.targetPart
	if not name or not beam or not targetPart then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not isForced and now - self.lastPostPickTime < POST_PICK_INTERVAL_SEC then
		return
	end
	self.lastPostPickTime = now
	local target, isPrompt = self:findBeamTarget(name)
	if not target then
		beam.Enabled = false
		return
	end
	targetPart.Position = if isPrompt then target else target + Vector3.new(0, BEAM_TARGET_RISE_STUDS, 0)
	beam.Enabled = true
end

-- the arrow hangs off the target's edge and bobs toward it; hidden when
-- the target is not on screen (the tool bar slid away, the clock off)
function ClientTutorialManager:placeArrow()
	local arrow = self.arrow
	local step = self.currentStep
	local name = if step then step.arrow else nil
	if not arrow then
		return
	end
	local side = if name then ARROW_SIDES[name] else nil
	local target = if name then self:findArrowTarget(name) else nil
	local isLineGone = step ~= nil and step.isArrowWithLine == true and not self.isDialogShown
	if not side or not target or not target.Visible or isLineGone then
		arrow.Visible = false
		return
	end
	local targetPosition = target.AbsolutePosition
	local targetSize = target.AbsoluteSize
	-- a HUD element slid off the screen (the clock at dusk) gets no arrow
	local gui = self.gui :: ScreenGui
	local guiOrigin = gui.AbsolutePosition
	local guiSize = gui.AbsoluteSize
	local isOnScreen = targetPosition.X + targetSize.X > guiOrigin.X
		and targetPosition.Y + targetSize.Y > guiOrigin.Y
		and targetPosition.X < guiOrigin.X + guiSize.X
		and targetPosition.Y < guiOrigin.Y + guiSize.Y
	if not isOnScreen then
		arrow.Visible = false
		return
	end
	local arrowSize: number = arrow.AbsoluteSize.X
	local edge = targetPosition + targetSize * side.anchor
	local push = side.bob * -1 * arrowSize * (ARROW_GAP_SHARE + 0.5)
	local bob = side.bob * math.sin(workspace:GetServerTimeNow() * ARROW_BOB_HZ * math.pi * 2) * arrowSize * ARROW_BOB_SHARE
	local centre = edge + push + bob
	-- AbsolutePosition is in the gui's own space with the inset already
	-- applied, and so is a scale-free Position on a gui of the same inset
	arrow.Position = UDim2.fromOffset(centre.X - guiOrigin.X, centre.Y - guiOrigin.Y)
	arrow.Rotation = side.rotation
	arrow.Visible = true
end

function ClientTutorialManager:isPlaying(): boolean
	return self.sequence ~= nil
end

-- a panel fades in when it has something to show and out when it has
-- not; the gui stays enabled for as long as either is up. A menu draws
-- over both (MENU_DISPLAY_ORDER is above the gui's), and a manned post
-- counts as an overlay too, where the night's line must still be read
function ClientTutorialManager:fadePanel(panel: GuiObject?, authored: ClientGuiFade.Hidden, isShown: boolean, wasShown: boolean, generation: number)
	if not panel or isShown == wasShown then
		return
	end
	if isShown then
		panel.Visible = true
	end
	ClientGuiFade.tweenShown(authored, isShown, PANEL_FADE_SEC)
	if not isShown then
		task.delay(
			PANEL_FADE_SEC,
			function()
				local liveGeneration = if panel == self.dialog then self.dialogFadeGeneration else self.tasksFadeGeneration
				if generation == liveGeneration then
					panel.Visible = false
				end
			end
		)
	end
end

function ClientTutorialManager:setDialogShown(isShown: boolean)
	local wasShown = self.isDialogShown
	self.isDialogShown = isShown
	self.dialogFadeGeneration += 1
	self:fadePanel(self.dialog, self.dialogAuthored, isShown, wasShown, self.dialogFadeGeneration)
	self:renderGuiEnabled()
end

function ClientTutorialManager:setTasksShown(isShown: boolean)
	local wasShown = self.isTasksShown
	self.isTasksShown = isShown
	self.tasksFadeGeneration += 1
	self:fadePanel(self.tasksFrame, self.tasksAuthored, isShown, wasShown, self.tasksFadeGeneration)
	self:renderGuiEnabled()
end

function ClientTutorialManager:renderGuiEnabled()
	local gui = self.gui
	if gui then
		gui.Enabled = self.currentStep ~= nil or self.isDialogShown or self.isTasksShown
	end
end

-- the goal line, with its progress pair where the step names one; only
-- written when it changes so the label is not churned every frame
function ClientTutorialManager:renderTask()
	local step = self.currentStep
	local label = self.taskLabel
	if not label or not step or not step.task then
		return
	end
	local text = step.task
	if step.number then
		text = string.format(text, self:readNumberFor(step.number))
	end
	if step.progress then
		local done, total = self:readProgress(step.progress)
		text = string.format(PROGRESS_FORMAT, text, math.min(done, total), total)
	end
	if label.Text ~= text then
		label.Text = text
	end
end

-- the pairs a task can count: the backpack's fill and the Gold Bars
-- toward the pick axe
function ClientTutorialManager:readProgress(name: string): (number, number)
	if name == "backpackFill" then
		local total = 0
		for _, resource in Enums.getAllValues(Enums.RawResource) do
			total += readNumberAttribute(BackpackRules.attributeForResource(resource) :: string)
		end
		return total, readNumberAttribute(Attributes.BACKPACK_CAPACITY)
	elseif name == "goldBars" then
		return readNumberAttribute(Attributes.BALANCE_GOLD_BARS), self:getPickAxePrice()
	elseif name == "goldOreMined" then
		return readNumberAttribute(Attributes.BACKPACK_GOLD_ORE), self.goldOreTarget
	end
	warn(`ClientTutorialManager: no progress named {name}`)
	return 0, 0
end

function ClientTutorialManager:showStep(step: TutorialScript.Step)
	self.currentStep = step
	local now = workspace:GetServerTimeNow()
	self.stepStartTime = now
	self.goldOreTarget = self:computeGoldOreTarget()
	self.goldBarsAtStepStart = readNumberAttribute(Attributes.BALANCE_GOLD_BARS)
	self.hasBurnedJetPackThisStep = false
	if not step.text then
		-- a task-only step: no line, the goal up at once
		self.stepEndTime = nil
		self.lineEndTime = nil
		self:setBeamTarget(step.beam)
		self:setDialogShown(false)
		self:renderTask()
		self:setTasksShown(step.task ~= nil)
		ClientSoundManager:playSfx(SoundNames.Sfx.TUTORIAL_PROMPT)
		return
	end
	local text = step.text
	if step.number then
		text = string.format(text, self:readNumberFor(step.number))
	end
	local label = self.messageLabel :: TextLabel?
	if label then
		label.Text = text
		label.MaxVisibleGraphemes = 0
		local graphemeCount = utf8.len(text) or #text
		TweenService:Create(label, TweenInfo.new(math.min(TYPE_MAX_SEC, graphemeCount * TYPE_SEC_PER_CHARACTER), Enum.EasingStyle.Linear), { MaxVisibleGraphemes = graphemeCount }):Play()
	end
	-- every line is up for its reading time; a line that waits on
	-- nothing advances at its end, one that waits leaves the dialogue
	-- and keeps its goal on the Tasks panel (designer, 2026-11-09: the
	-- box in the way of play was annoying)
	local isWaiting = step.waitFor ~= nil
	local readEndTime = now + math.clamp(READ_BASE_SEC + #text * READ_SEC_PER_CHARACTER, READ_MIN_SEC, READ_MAX_SEC) + (step.extraSec or 0)
	self.stepEndTime = if isWaiting then nil else readEndTime
	self.lineEndTime = if isWaiting then readEndTime else nil
	self:setBeamTarget(step.beam)
	self:setDialogShown(true)
	-- the goal takes the line's place once the line has been read
	-- (designer, 2026-11-09); a step with no line time left (none have)
	-- would show it at once
	self:setTasksShown(false)
	ClientSoundManager:playSfx(SoundNames.Sfx.TUTORIAL_PROMPT)
end

-- the next step the running sequence has, skipping any whose skipIf
-- already holds; the sequence ends when none is left, and the next
-- queued one starts
function ClientTutorialManager:advance()
	local sequence = self.sequence
	if not sequence then
		return
	end
	while true do
		self.stepIndex += 1
		local step = sequence[self.stepIndex]
		if not step then
			self:endSequence()
			return
		end
		if step.skipIf and self:judge(step.skipIf) then
			-- a skipped loop step still turns the loop
			if step.repeatBackUnless and not self:judge(step.repeatBackUnless) then
				self.stepIndex -= (step.repeatBackSteps or 1) + 1
			end
			continue
		end
		self:showStep(step)
		return
	end
end

function ClientTutorialManager:endSequence()
	local wasMorning = self.sequence == TutorialScript.MORNING
	self.sequence = nil
	self.currentStep = nil
	self.stepEndTime = nil
	self.lineEndTime = nil
	self:setBeamTarget(nil)
	self:setDialogShown(false)
	self:setTasksShown(false)
	local arrow = self.arrow
	if arrow then
		arrow.Visible = false
	end
	if wasMorning then
		-- the walkthrough is over; the server has saved the flag at the dawn
		self.isArmed = false
		self.pending = {}
		return
	end
	local nextSequence = table.remove(self.pending, 1)
	if nextSequence then
		self:startSequence(nextSequence)
	end
end

function ClientTutorialManager:startSequence(sequence: TutorialScript.Sequence)
	self.sequence = sequence
	self.stepIndex = 0
	self:advance()
end

-- a sequence plays once; an override drops what is up and what waits,
-- anything else waits its turn
function ClientTutorialManager:play(key: string, isOverride: boolean)
	if not self.isArmed or self.playedKeys[key] then
		return
	end
	local sequence = (TutorialScript :: any)[key] :: TutorialScript.Sequence?
	if not sequence then
		warn(`ClientTutorialManager: no sequence named {key}`)
		return
	end
	self.playedKeys[key] = true
	if self.sequence and not isOverride then
		table.insert(self.pending, sequence)
		return
	end
	if isOverride then
		self.pending = {}
	end
	self:startSequence(sequence)
end

-- the dev panel's "start now": the walkthrough from the top, whatever
-- the day, as if the DAY 1 card had just closed; every sequence may play
-- again (this client only; the save's flag is the server's reset)
function ClientTutorialManager:startNow()
	self:stopNow()
	self.isArmed = true
	self.playedKeys = {}
	self.pickAxeLevelAtStart = readNumberAttribute(Attributes.PICK_AXE_LEVEL)
	self.hasMinedByResource = {}
	self.hasRefinedGold = false
	self:play("DAY_ONE", true)
end

-- the dev panel's "stop": drops what is up and what waits, without
-- touching the save
function ClientTutorialManager:stopNow()
	self.pending = {}
	self.sequence = nil
	self:endSequence()
end

function ClientTutorialManager:step()
	local step = self.currentStep
	if not step then
		return
	end
	self:placeArrow()
	self:placeBeam(false)
	local now = workspace:GetServerTimeNow()
	self:stepBeamFade(now)
	local endTime = self.stepEndTime or self.lineEndTime
	local readBar = self.readBar
	if readBar and endTime then
		local share = math.clamp((endTime - now) / math.max(endTime - self.stepStartTime, 0.01), 0, 1)
		readBar.Size = UDim2.fromScale(self.readBarFullScale * share, readBar.Size.Y.Scale)
	end
	if step.waitFor then
		if self.isTasksShown then
			self:renderTask()
		end
		local lineEndTime = self.lineEndTime
		if lineEndTime and now >= lineEndTime then
			self.lineEndTime = nil
			self:setDialogShown(false)
			self:renderTask()
			self:setTasksShown(step.task ~= nil)
		end
		if self:judge(step.waitFor) then
			if step.repeatBackUnless and not self:judge(step.repeatBackUnless) then
				-- around again: advance() moves one on, so land on the
				-- step this many back from here
				self.stepIndex -= (step.repeatBackSteps or 1) + 1
			end
			self:advance()
		end
		return
	end
	if endTime and now >= endTime then
		self:advance()
	end
end

-- the DAY N card closing: day 1's opens the walkthrough, day 2's (the
-- first dawn survived) closes it
function ClientTutorialManager:onCardClosed()
	local day = ClientDataManager:getGameMetadata(Attributes.RUN_DAY)
	local runState = ClientDataManager:getGameMetadata(Attributes.RUN_STATE)
	if typeof(day) ~= "number" or runState ~= Enums.RunState.DAY then
		return
	end
	if day == FIRST_DAY then
		self:play("DAY_ONE", false)
	elseif self.playedKeys.DAY_ONE or self.playedKeys.SUNSET or self.playedKeys.NIGHT then
		self:play("MORNING", true)
	end
end

-- the first of each ore seen in the backpack; a rise is a find, a fall is
-- a refine (the backpack empties), and the first Gold Bars are the refine
-- the day 1 line waits for
function ClientTutorialManager:watchBackpack()
	for _, resource in Enums.getAllValues(Enums.RawResource) do
		local attribute = BackpackRules.attributeForResource(resource) :: string
		local last = readNumberAttribute(attribute)
		if last > 0 then
			self.hasMinedByResource[resource] = true
		end
		table.insert(
			self.disconnects,
			ClientDataManager:subscribeCurrentPlayerAttribute(
				attribute,
				function(value: any)
					local amount = if typeof(value) == "number" then value else 0
					if amount > last and not self.hasMinedByResource[resource] then
						self.hasMinedByResource[resource] = true
						if resource == Enums.RawResource.IRON_ORE then
							self:play("IRON", false)
						elseif resource == Enums.RawResource.URANIUM_ORE then
							self:play("URANIUM", false)
						end
					end
					last = amount
				end
			)
		)
	end
	local lastGold = readNumberAttribute(Attributes.BALANCE_GOLD_BARS)
	table.insert(
		self.disconnects,
		ClientDataManager:subscribeCurrentPlayerAttribute(
			Attributes.BALANCE_GOLD_BARS,
			function(value: any)
				local amount = if typeof(value) == "number" then value else 0
				if amount > lastGold then
					self.hasRefinedGold = true
				end
				lastGold = amount
			end
		)
	)
end

-- an asset under GameAssets/Tutorial (the head, the beam)
function ClientTutorialManager:findTutorialAsset(name: string): Instance?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local folder = if gameAssets then gameAssets:FindFirstChild(Constants.TUTORIAL_ASSETS_FOLDER) else nil
	return if folder then folder:FindFirstChild(name) else nil
end

-- the guide's head in the portrait: the GameAssets model cloned in, the
-- camera on its face
function ClientTutorialManager:fillPortrait()
	local portrait = self.portrait
	if not portrait then
		return
	end
	local template = self:findTutorialAsset(Constants.TUTORIAL_GUIDE_HEAD_MODEL)
	if not template or not template:IsA("Model") then
		warn("ClientTutorialManager: no GameAssets.Tutorial.GuideHead; run scripts/studio/build_tutorial_guide_head.luau")
		return
	end
	local head = template:Clone()
	head:PivotTo(CFrame.new())
	head.Parent = portrait
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	-- the face is the model's -Z; a little above centre so the helmet fits
	camera.CFrame = CFrame.lookAt(Vector3.new(0.15, 0.25, -3.2), Vector3.new(0, 0.2, 0))
	camera.Parent = portrait
	portrait.CurrentCamera = camera
end

function ClientTutorialManager:findGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.TUTORIAL_GUI_NAME, Constants.GUI_WAIT_SEC)
	if not gui or not gui:IsA("ScreenGui") then
		warn("ClientTutorialManager: no Tutorial ScreenGui; run scripts/studio/build_tutorial_gui.luau")
		return
	end
	gui.Enabled = false
	self.gui = gui
	local dialog = gui:FindFirstChild(Constants.TUTORIAL_DIALOG_FRAME)
	self.dialog = if dialog and dialog:IsA("GuiObject") then dialog else nil
	local portrait = gui:FindFirstChild(Constants.TUTORIAL_PORTRAIT_VIEWPORT, true)
	self.portrait = if portrait and portrait:IsA("ViewportFrame") then portrait else nil
	local message = gui:FindFirstChild(Constants.TUTORIAL_MESSAGE_LABEL, true)
	self.messageLabel = if message and message:IsA("TextLabel") then message else nil
	local readBar = gui:FindFirstChild(Constants.TUTORIAL_READ_BAR, true)
	self.readBar = if readBar and readBar:IsA("GuiObject") then readBar else nil
	self.readBarFullScale = if self.readBar then self.readBar.Size.X.Scale else 0
	local arrow = gui:FindFirstChild(Constants.TUTORIAL_ARROW)
	self.arrow = if arrow and arrow:IsA("GuiObject") then arrow else nil
	local tasks = gui:FindFirstChild(Constants.TUTORIAL_TASKS_FRAME)
	if tasks and tasks:IsA("GuiObject") then
		self.tasksFrame = tasks
		tasks.Visible = false
		self.tasksAuthored = ClientGuiFade.capture(tasks)
		ClientGuiFade.setHidden(self.tasksAuthored)
		local taskLabel = tasks:FindFirstChild(Constants.TUTORIAL_TASK_LABEL)
		self.taskLabel = if taskLabel and taskLabel:IsA("TextLabel") then taskLabel else nil
	else
		warn("ClientTutorialManager: the Tutorial gui has no Tasks frame; goals will not show")
	end
	local dialogFrame = self.dialog :: GuiObject?
	if dialogFrame then
		dialogFrame.Visible = false
		self.dialogAuthored = ClientGuiFade.capture(dialogFrame)
		ClientGuiFade.setHidden(self.dialogAuthored)
	end
	self:fillPortrait()
end

function ClientTutorialManager:init()
	self:findGui()
	self.isArmed = ClientDataManager:getCurrentPlayerAttribute(Attributes.HAS_FINISHED_TUTORIAL) ~= true
	self.pickAxeLevelAtStart = readNumberAttribute(Attributes.PICK_AXE_LEVEL)
	self:watchBackpack()
	-- the dev tool's reset arms the walkthrough again; the server's own
	-- flip to true at the dawn is left alone, since the morning lines are
	-- still to play
	table.insert(
		self.disconnects,
		ClientDataManager:subscribeCurrentPlayerAttribute(
			Attributes.HAS_FINISHED_TUTORIAL,
			function(value: any)
				if value == false then
					self.isArmed = true
					self.playedKeys = {}
					self.pickAxeLevelAtStart = readNumberAttribute(Attributes.PICK_AXE_LEVEL)
				end
			end
		)
	)
	ClientRunCycleManager:subscribeCardClosed(
		function()
			self:onCardClosed()
		end
	)
	ClientRunCycleManager:subscribePhaseChanged(
		function(phase: number)
			if phase == Enums.ClockPhase.DUSK and self.playedKeys.DAY_ONE then
				self:play("SUNSET", true)
			end
		end
	)
	table.insert(
		self.disconnects,
		ClientDataManager:subscribeGameMetadataAttribute(
			Attributes.IS_NIGHT,
			function(value: any)
				if value == true and self.playedKeys.SUNSET then
					self:play("NIGHT", true)
				end
			end
		)
	)
	self.stepConnection = RunService.Heartbeat:Connect(
		function()
			self:step()
		end
	)
end

function ClientTutorialManager.new(): ClientTutorialManager
	local self = setmetatable({}, ClientTutorialManager) :: ClientTutorialManager
	self.isArmed = false
	self.playedKeys = {}
	self.sequence = nil
	self.stepIndex = 0
	self.pending = {}
	self.currentStep = nil
	self.stepEndTime = nil
	self.lineEndTime = nil
	self.stepStartTime = 0
	self.readBarFullScale = 0
	self.isTasksShown = false
	self.isDialogShown = false
	self.dialogAuthored = {}
	self.tasksAuthored = {}
	self.dialogFadeGeneration = 0
	self.tasksFadeGeneration = 0
	self.hasMinedByResource = {}
	self.hasRefinedGold = false
	self.pickAxeLevelAtStart = 0
	self.goldOreTarget = 1
	self.goldBarsAtStepStart = 0
	self.hasBurnedJetPackThisStep = false
	self.lastPostPickTime = 0
	self.beamAuthoredTransparency = nil
	self.beamFadeStartTime = nil
	self.disconnects = {}
	return self
end

return ClientTutorialManager.new()
