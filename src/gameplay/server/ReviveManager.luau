--!strict

-- Death and the three revives (GDD "Health and Revives", "Spectate Mode"),
-- M32. This manager owns who is dead. A player has a fixed health that
-- only monsters lower (MonsterManager hands every hit to damagePlayer) and
-- nothing restores: Roblox's own regeneration script is removed from every
-- character here, the one place. At zero the character is never killed or
-- respawned: it is moved to Workspace.DeathRoom, the player lets go of
-- their post, Build Mode, and tools, and a grave (a shadow part,
-- Tags.TOMBSTONE, on the lowest free plot of the camp's Cemetery; clients
-- clone GameAssets.Grave onto it) stands for them. A player who leaves a
-- run under way leaves a grave too, which stays until the run is over.
--
-- Every way back goes through revive(): the dead player's own Revive and
-- the crew's Team Revive (TryRevive from the Results Menu), a Friend
-- Revive (the tombstone's prompt), a saved credit, and the dev tool. The
-- three are Robux developer products; PurchaseManager hears the receipt
-- and calls the handler registered here, and pure ReviveRules decides
-- whether the revive happens or is kept as a credit (it is never refused).
--
-- When every player is dead the run is held still (RunPauseManager, the
-- dev tool's pause) for WIPE_WINDOW_SEC. The first wipe of a crew of two
-- or more offers the Team Revive, which brings everyone back and starts
-- the current day over; a later wipe, and every death of a solo player,
-- offers each player their own Revive, which brings them back where the
-- run stands. If the window ends with nobody revived, the run is lost.
--
-- What clients need: IsDead is public on AllPlayers; the offer, its end
-- time, and the saved credits are private CurrentPlayer attributes; the
-- prices and the wipe flag are GameMetadata.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local PartyRules = require("@game/ReplicatedStorage/Shared/PartyRules")
local ReviveRules = require("@game/ReplicatedStorage/Shared/ReviveRules")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local RevivesData = require("@game/ServerScriptService/GameData/Run/Revives")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local PurchaseManager = require(script.Parent.Parent.Server.PurchaseManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DefenseTableManager = require(script.Parent.DefenseTableManager)
local JetPackManager = require(script.Parent.JetPackManager)
local MapManager = require(script.Parent.MapManager)
local PostManager = require(script.Parent.PostManager)
local Ragdoll = require(script.Parent.Ragdoll)
local RunCycleManager = require(script.Parent.RunCycleManager)
local RunPauseManager = require(script.Parent.RunPauseManager)
local ToolManager = require(script.Parent.ToolManager)

local ReviveManager = {}
ReviveManager.__index = ReviveManager

type DeadEntry = {
	deathTime: number,
	-- the server time the player's own Revive stops being offered
	selfDeadline: number,
	plotIndex: number?,
	tombstone: BasePart?,
	-- who a spectator is watching; the world streams round them
	spectateTarget: Player?,
	-- the Game Over screen has gone black: the character is in the
	-- DeathRoom and the world streams round the grave
	isSceneOver: boolean,
	replicatedOffer: number?,
	replicatedOfferEndTime: number?,
}

type LeaverGrave = {
	tombstone: BasePart,
	plotIndex: number,
}

export type DiedHandler = (player: Player) -> ()
export type TeamRevivedHandler = () -> ()

export type ReviveManager = typeof(setmetatable(
	{} :: {
		deadByPlayer: { [Player]: DeadEntry },
		invulnerableUntilByPlayer: { [Player]: number },
		isSetUpByPlayer: { [Player]: boolean },
		isTeamReviveUsed: boolean,
		-- 0 unless the whole crew is dead and the run is being held
		wipeDeadline: number,
		-- a Friend Revive's receipt names only the buyer, so the tombstone
		-- they triggered is remembered until the purchase resolves
		pendingFriendTargetByBuyer: { [Player]: Player },
		-- the graves of players who left the run; they stay until it is over
		leaverGraves: { LeaverGrave },
		diedHandlers: { DiedHandler },
		teamRevivedHandlers: { TeamRevivedHandler },
		shadowFolder: Folder?,
		hasWarnedNoDeathRoom: boolean,
		stepAccumulatorSec: number,
	},
	ReviveManager
))

local TRY_RETURN_TO_LOBBY_SHAPE = {}

local TRY_REVIVE_SHAPE = {
	reviveKind = "positiveInteger",
}

-- 0 for nobody; any other whole number is a user id (Studio's local
-- test players have negative ones)
local TRY_SPECTATE_SHAPE = {
	userId = "integer",
}

-- the name this manager holds the run still under (RunPauseManager)
local WIPE_HOLDER = "crewWipe"
local STEP_INTERVAL_SEC = 0.25
local SHADOW_SIZE = Vector3.one
-- Roblox's regeneration Script inside every character
local REGENERATION_SCRIPT = "Health"
local CHARACTER_WAIT_SEC = 5
-- how long a death's Game Over screen takes to go black
local GAME_OVER_SCENE_SEC = RevivesData.GAME_OVER_HOLD_SEC + RevivesData.GAME_OVER_FADE_IN_SEC
-- and how long before the Results Menu is on screen: the revive windows
-- count from then, so the Game Over screen costs the player none of them
local GAME_OVER_REVIVE_DELAY_SEC = GAME_OVER_SCENE_SEC + RevivesData.GAME_OVER_BLACK_HOLD_SEC + RevivesData.GAME_OVER_FADE_OUT_SEC

local CREDIT_ATTRIBUTE_BY_KIND: { [number]: string } = {
	[Enums.ReviveKind.SELF] = Attributes.REVIVE_CREDITS_SELF,
	[Enums.ReviveKind.FRIEND] = Attributes.REVIVE_CREDITS_FRIEND,
	[Enums.ReviveKind.TEAM] = Attributes.REVIVE_CREDITS_TEAM,
}

local PRICE_ATTRIBUTE_BY_KIND: { [number]: string } = {
	[Enums.ReviveKind.SELF] = Attributes.REVIVE_PRICE_SELF,
	[Enums.ReviveKind.FRIEND] = Attributes.REVIVE_PRICE_FRIEND,
	[Enums.ReviveKind.TEAM] = Attributes.REVIVE_PRICE_TEAM,
}

local PRODUCT_ID_BY_KIND: { [number]: number } = RevivesData.PRODUCT_ID_BY_KIND

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

function ReviveManager:isDead(player: Player): boolean
	return self.deadByPlayer[player] ~= nil
end

-- Ready players who are not dead: who monsters hunt, who the rescue waits
-- for, and who a spectator may watch
function ReviveManager:getLivingPlayers(): { Player }
	local living = {}
	for _, player in GameController:getReadyPlayers() do
		if not self.deadByPlayer[player] then
			table.insert(living, player)
		end
	end
	return living
end

function ReviveManager:isCrewWiped(): boolean
	return self.wipeDeadline > 0
end

-- one player in the run right now: they are offered their own Revive,
-- never the Team Revive
function ReviveManager:isSolo(): boolean
	return #GameController:getReadyPlayers() <= 1
end

-- where the world a player is looking at is centred: a spectator's is the
-- player they watch, a dead player's who is not spectating is their own
-- grave (the Results Menu's camera stands there), everyone else's is their
-- own character (the monster snapshots are sent by distance from here)
function ReviveManager:getViewPosition(player: Player): Vector3?
	local entry = self.deadByPlayer[player]
	local target = if entry then entry.spectateTarget else nil
	if entry and entry.isSceneOver and entry.tombstone and not (target and target.Parent == Players) then
		return entry.tombstone.Position
	end
	local root = getRoot(if target and target.Parent == Players then target else player)
	return if root then root.Position else nil
end

function ReviveManager:subscribeDied(handler: DiedHandler)
	table.insert(self.diedHandlers, handler)
end

-- the Team Revive was used: whoever owns monsters, waves, and the rescue
-- clears them before the day starts over (wired in main.server)
function ReviveManager:subscribeTeamRevived(handler: TeamRevivedHandler)
	table.insert(self.teamRevivedHandlers, handler)
end

function ReviveManager:getShadowFolder(): Folder
	local folder = self.shadowFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = Constants.TOMBSTONE_SHADOWS_FOLDER
	created.Parent = workspace
	self.shadowFolder = created
	return created
end

-- the loaded camp's Cemetery plots by their numeric name
function ReviveManager:getPlots(): { [number]: BasePart }
	local plots: { [number]: BasePart } = {}
	local camp = MapManager:getCamp()
	local cemetery = if camp then camp:FindFirstChild(Constants.CAMP_CEMETERY_FOLDER) else nil
	local folder = if cemetery then cemetery:FindFirstChild(Constants.CEMETERY_PLOTS_FOLDER) else nil
	if not folder then
		return plots
	end
	for _, child in folder:GetChildren() do
		local index = tonumber(child.Name)
		if index and child:IsA("BasePart") then
			plots[index] = child
		end
	end
	return plots
end

function ReviveManager:replicateCredits(player: Player)
	local playerData = GameController:getPlayerData(player)
	if not playerData then
		return
	end
	for reviveKind, attributeName in CREDIT_ATTRIBUTE_BY_KIND do
		SplendidReplicationManager:setCurrentPlayerAttribute(player, attributeName, playerData:getReviveCredits(reviveKind))
	end
end

-- what each dead player's Results Menu shows right now; written on change only
function ReviveManager:replicateOffers()
	local now = workspace:GetServerTimeNow()
	local isRunOn = RunCycleManager:isRunOn()
	local isWiped = self:isCrewWiped()
	local isSolo = self:isSolo()
	for player, entry in self.deadByPlayer do
		local offer = ReviveRules.offerFor(true, isRunOn, isWiped, self.isTeamReviveUsed, isSolo, entry.selfDeadline, now)
		local endTime = ReviveRules.offerEndTime(offer, entry.selfDeadline, self.wipeDeadline)
		if offer ~= entry.replicatedOffer or endTime ~= entry.replicatedOfferEndTime then
			entry.replicatedOffer = offer
			entry.replicatedOfferEndTime = endTime
			SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.REVIVE_OFFER, offer)
			SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.REVIVE_OFFER_END_TIME, endTime)
		end
	end
end

function ReviveManager:replicateAlive(player: Player)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.IS_DEAD, false)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.REVIVE_OFFER, Enums.ReviveOffer.NONE)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.REVIVE_OFFER_END_TIME, 0)
end

-- a line for the announcement box of every living player; the dead are
-- looking at the Game Over screen or the Results Menu, which say it already
function ReviveManager:announce(message: string, isAlert: boolean)
	for _, player in self:getLivingPlayers() do
		NetManager:notifyClient(player, NetEventNames.NOTIFY_REVIVE_ANNOUNCEMENT, {
			message = message,
			displaySec = RevivesData.FEEDBACK_DISPLAY_SEC,
			-- a death shows red, like a wall falling
			isAlert = isAlert,
		})
	end
end

-- full health, and no regeneration: there is no healing in a run
function ReviveManager:setUpCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", CHARACTER_WAIT_SEC)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.MaxHealth = RevivesData.PLAYER_MAX_HEALTH
	humanoid.Health = RevivesData.PLAYER_MAX_HEALTH
	task.spawn(
		function()
			local regeneration = character:WaitForChild(REGENERATION_SCRIPT, CHARACTER_WAIT_SEC)
			if regeneration then
				regeneration:Destroy()
			end
		end
	)
	-- a character the engine killed anyway (fallen out of the world) counts
	-- as a death; its replacement is sent to the DeathRoom below
	humanoid.Died:Connect(
		function()
			if player.Character == character and GameController:isPlayerReady(player) then
				self:kill(player)
			end
		end
	)
	if self.deadByPlayer[player] then
		humanoid.Health = RevivesData.DEAD_CHARACTER_HEALTH
		-- after ArrivalManager has put the new character on the pad
		character:WaitForChild("HumanoidRootPart", CHARACTER_WAIT_SEC)
		task.wait()
		if self.deadByPlayer[player] and player.Character == character then
			self:moveToDeathRoom(player)
		end
	end
end

function ReviveManager:moveToDeathRoom(player: Player)
	local character = player.Character
	local room = workspace:FindFirstChild(Constants.DEATH_ROOM_MODEL)
	local spawnPart = if room then room:FindFirstChild(Constants.DEATH_ROOM_SPAWN_PART) else nil
	if not spawnPart or not spawnPart:IsA("BasePart") then
		if not self.hasWarnedNoDeathRoom then
			self.hasWarnedNoDeathRoom = true
			warn(`ReviveManager: Workspace has no {Constants.DEATH_ROOM_MODEL}.{Constants.DEATH_ROOM_SPAWN_PART}; a dead character stays where it fell`)
		end
		return
	end
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end
	character:PivotTo(spawnPart.CFrame + Vector3.new(0, RevivesData.DEATH_ROOM_LIFT_STUDS, 0))
end

-- stands a grave shadow on the lowest free plot of the Cemetery: for a
-- dead player (with the Friend Revive prompt) or for one who left the
-- run (no prompt, and it stays until the run is over). Clients clone the
-- Grave template onto it and write the name, the face, and the day
function ReviveManager:createGrave(player: Player, hasPrompt: boolean): (BasePart?, number?)
	local plots = self:getPlots()
	local isTaken: { [number]: boolean } = {}
	for _, other in self.deadByPlayer do
		if other.plotIndex then
			isTaken[other.plotIndex] = true
		end
	end
	for _, grave in self.leaverGraves do
		isTaken[grave.plotIndex] = true
	end
	local plotIndex = ReviveRules.firstFreePlot(Constants.CEMETERY_PLOT_COUNT, isTaken)
	local plot = if plotIndex then plots[plotIndex] else nil
	if not plotIndex or not plot then
		-- GameplayMapManager already reported a camp without its Cemetery
		return nil, nil
	end
	local shadow = Instance.new("Part")
	shadow.Name = tostring(player.UserId)
	shadow.Size = SHADOW_SIZE
	shadow.Transparency = 1
	shadow.Anchored = true
	shadow.CanCollide = false
	shadow.CanQuery = false
	shadow.CanTouch = false
	shadow.CFrame = plot.CFrame
	shadow:SetAttribute(Attributes.TOMBSTONE_USER_ID, player.UserId)
	shadow:SetAttribute(Attributes.TOMBSTONE_DISPLAY_NAME, player.DisplayName)
	shadow:SetAttribute(Attributes.TOMBSTONE_DAY, RunCycleManager:getDay())
	CollectionService:AddTag(shadow, Tags.TOMBSTONE)
	if hasPrompt then
		local prompt = Instance.new("ProximityPrompt")
		-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person (2026-09-29)
		prompt.ClickablePrompt = false
		prompt.ActionText = string.format(RevivesData.TOMBSTONE_PROMPT_ACTION_FORMAT, player.DisplayName)
		prompt.ObjectText = ""
		prompt.MaxActivationDistance = RevivesData.TOMBSTONE_PROMPT_MAX_DISTANCE_STUDS
		prompt.HoldDuration = RevivesData.TOMBSTONE_PROMPT_HOLD_SEC
		prompt.RequiresLineOfSight = false
		prompt.Parent = shadow
		prompt.Triggered:Connect(
			function(buyer: Player)
				self:requestFriendRevive(buyer, player)
			end
		)
	end
	shadow.Parent = self:getShadowFolder()
	return shadow, plotIndex
end

-- a dead player's hands come off everything; the order matters because
-- stepping down from a post or out of Build Mode unlocks the tools
function ReviveManager:releaseEverything(player: Player)
	DefenseTableManager:exit(player)
	PostManager:dismount(player)
	JetPackManager:setBurning(player, false)
	ToolManager:setToolsLocked(player, true)
end

-- what death does to a player, whoever or whatever killed them: a grave,
-- hands off everything, the body limp where it fell (Ragdoll, unless
-- isRagdoll is false) for the Game Over screen and moved to the DeathRoom
-- once that screen is black
-- (when the Cemetery, where the camera goes next, is streamed in), and
-- the public IsDead flag. hasPrompt is the Friend Revive prompt
function ReviveManager:bury(player: Player, hasPrompt: boolean, isRagdoll: boolean): DeadEntry
	local now = workspace:GetServerTimeNow()
	local entry: DeadEntry = {
		deathTime = now,
		selfDeadline = now + GAME_OVER_REVIVE_DELAY_SEC + RevivesData.SELF_REVIVE_WINDOW_SEC,
		plotIndex = nil,
		tombstone = nil,
		spectateTarget = nil,
		isSceneOver = false,
		replicatedOffer = nil,
		replicatedOfferEndTime = nil,
	}
	entry.tombstone, entry.plotIndex = self:createGrave(player, hasPrompt)
	self.deadByPlayer[player] = entry
	self.invulnerableUntilByPlayer[player] = nil
	local humanoid = getHumanoid(player)
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = RevivesData.DEAD_CHARACTER_HEALTH
	end
	self:releaseEverything(player)
	-- the body drops limp where it fell for the Game Over screen; when
	-- it was the Refinery that fell, the camera is on the Refinery and
	-- the character is simply held still
	local character = player.Character
	local root = getRoot(player)
	if isRagdoll and character then
		Ragdoll.apply(character)
	elseif root then
		root.Anchored = true
	end
	task.delay(
		GAME_OVER_SCENE_SEC,
		function()
			if self.deadByPlayer[player] ~= entry then
				return
			end
			entry.isSceneOver = true
			-- off screen now: back on its joints and held still in the DeathRoom
			local sceneCharacter = player.Character
			local sceneRoot = getRoot(player)
			if sceneCharacter then
				Ragdoll.remove(sceneCharacter)
			end
			if sceneRoot then
				sceneRoot.Anchored = true
			end
			self:moveToDeathRoom(player)
			player.ReplicationFocus = entry.tombstone
		end
	)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.IS_DEAD, true)
	return entry
end

function ReviveManager:kill(player: Player)
	if self.deadByPlayer[player] or not GameController:isPlayerReady(player) or not RunCycleManager:isRunOn() then
		return
	end
	self:bury(player, true, true)
	print(`[ReviveManager] {player.Name} died`)
	-- anyone watching this player needs someone else to watch
	for _, other in self.deadByPlayer do
		if other.spectateTarget == player then
			other.spectateTarget = nil
		end
	end
	for _, handler in self.diedHandlers do
		handler(player)
	end
	self:announce(string.format(RevivesData.DIED_ANNOUNCEMENT_FORMAT, player.DisplayName), true)
	self:startWipeIfNeeded(GAME_OVER_REVIVE_DELAY_SEC)
	self:replicateOffers()
end

-- the Refinery fell: the run is lost for everyone, so everyone still
-- standing gets a grave too and sees the run's results beside it, exactly
-- as the dead do (decided 2026-10-05). Nothing can revive them: the run
-- is over
function ReviveManager:buryTheLiving()
	for _, player in self:getLivingPlayers() do
		self:bury(player, false, false)
	end
	self:replicateOffers()
end

-- every hit a monster lands on a player comes through here
function ReviveManager:damagePlayer(player: Player, amount: number)
	if self.deadByPlayer[player] or not RunCycleManager:isRunOn() then
		return
	end
	local humanoid = getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	local isInvulnerable = now < (self.invulnerableUntilByPlayer[player] or 0)
	local health, isKilled = ReviveRules.applyDamage(humanoid.Health, amount, isInvulnerable)
	if isKilled then
		self:kill(player)
		return
	end
	humanoid.Health = health
end

function ReviveManager:endWipe()
	if self.wipeDeadline == 0 then
		return
	end
	self.wipeDeadline = 0
	SplendidReplicationManager:setGameMetadata(Attributes.IS_CREW_WIPED, false)
	RunPauseManager:setPaused(false, WIPE_HOLDER)
end

-- every player dead: the run holds still and the last offer goes out.
-- sceneSec is the Game Over screen the last to die is watching, if a
-- death is what wiped the crew; a crewmate leaving wipes it with no screen
function ReviveManager:startWipeIfNeeded(sceneSec: number)
	if self.wipeDeadline > 0 or not RunCycleManager:isRunOn() then
		return
	end
	local deadCount = 0
	for _ in self.deadByPlayer do
		deadCount += 1
	end
	if not ReviveRules.isCrewWiped(#GameController:getReadyPlayers(), deadCount) then
		return
	end
	-- the last to die watches the Game Over screen first
	self.wipeDeadline = workspace:GetServerTimeNow() + sceneSec + RevivesData.WIPE_WINDOW_SEC
	-- once the Team Revive is spent, a wipe gives every player their own
	-- Revive back for as long as the run is held
	for _, entry in self.deadByPlayer do
		entry.selfDeadline = self.wipeDeadline
	end
	SplendidReplicationManager:setGameMetadata(Attributes.IS_CREW_WIPED, true)
	RunPauseManager:setPaused(true, WIPE_HOLDER)
	print(`[ReviveManager] the whole crew is dead; the run is held for {RevivesData.WIPE_WINDOW_SEC} s`)
end

-- a dead character is limp or held still; this lets it walk again
function ReviveManager:releaseRoot(player: Player)
	local character = player.Character
	if character then
		Ragdoll.remove(character)
	end
	local root = getRoot(player)
	if root then
		root.Anchored = false
	end
end

function ReviveManager:removeEntry(player: Player)
	local entry = self.deadByPlayer[player]
	if not entry then
		return
	end
	self.deadByPlayer[player] = nil
	if entry.tombstone then
		entry.tombstone:Destroy()
	end
end

-- where a revived player appears: on their own grave, else on the pad
function ReviveManager:placeRevived(player: Player, plotIndex: number?)
	local character = player.Character
	if not character then
		return
	end
	local plot = if plotIndex then self:getPlots()[plotIndex] else nil
	if plot then
		character:PivotTo(plot.CFrame + Vector3.new(0, RevivesData.REVIVE_LIFT_STUDS, 0))
		return
	end
	local camp = MapManager:getCamp()
	local pad = if camp then camp:FindFirstChild(Constants.CAMP_HELICOPTER_PAD_MODEL) else nil
	if pad and pad:IsA("Model") then
		character:PivotTo(pad:GetPivot() + Vector3.new(0, RevivesData.REVIVE_LIFT_STUDS, 0))
	end
end

-- the one way back to life; reviver is the friend who paid, when one did
function ReviveManager:revive(player: Player, reviveKind: number, reviver: Player?)
	local entry = self.deadByPlayer[player]
	if not entry then
		return
	end
	self:removeEntry(player)
	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	self.invulnerableUntilByPlayer[player] = workspace:GetServerTimeNow() + RevivesData.REVIVE_INVULNERABLE_SEC
	player.ReplicationFocus = nil
	self:releaseRoot(player)
	self:placeRevived(player, entry.plotIndex)
	ToolManager:setToolsLocked(player, false)
	self:replicateAlive(player)
	print(`[ReviveManager] {player.Name} revived ({Enums.getPublicName(Enums.ReviveKind, reviveKind)})`)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_PLAYER_REVIVED, {
		userId = player.UserId,
		reviveKind = reviveKind,
	})
	if reviver and reviver ~= player then
		PlayerFeedbackManager:give(player, string.format(RevivesData.REVIVED_BY_FRIEND_FORMAT, reviver.DisplayName), RevivesData.FEEDBACK_DISPLAY_SEC)
		PlayerFeedbackManager:give(reviver, string.format(RevivesData.REVIVED_FRIEND_FEEDBACK_FORMAT, player.DisplayName), RevivesData.FEEDBACK_DISPLAY_SEC)
	end
	-- someone stands again, so a held run moves on
	self:endWipe()
	self:replicateOffers()
end

-- the whole crew back at once, and the current day from dawn again
function ReviveManager:teamRevive()
	self.isTeamReviveUsed = true
	self:endWipe()
	local dead = {}
	for player in self.deadByPlayer do
		table.insert(dead, player)
	end
	for _, player in dead do
		self:revive(player, Enums.ReviveKind.TEAM, nil)
	end
	for _, handler in self.teamRevivedHandlers do
		handler()
	end
	RunCycleManager:restartDay()
	self:announce(RevivesData.TEAM_REVIVED_MESSAGE, false)
end

function ReviveManager:buildContext(buyer: Player, target: Player?): ReviveRules.PurchaseContext
	return {
		isRunOn = RunCycleManager:isRunOn(),
		isBuyerDead = self.deadByPlayer[buyer] ~= nil,
		isTargetDead = target ~= nil and target.Parent == Players and self.deadByPlayer[target] ~= nil,
		isCrewWiped = self:isCrewWiped(),
		isTeamReviveUsed = self.isTeamReviveUsed,
		isSolo = self:isSolo(),
	}
end

-- a paid revive (a receipt or a saved credit): it happens, or it becomes
-- a credit. Returns whether it happened
function ReviveManager:applyPurchase(buyer: Player, reviveKind: number, target: Player?): boolean
	local outcome = ReviveRules.resolvePurchase(reviveKind, self:buildContext(buyer, target))
	if outcome ~= ReviveRules.OUTCOME_APPLY then
		return false
	end
	if reviveKind == Enums.ReviveKind.SELF then
		self:revive(buyer, reviveKind, nil)
	elseif reviveKind == Enums.ReviveKind.FRIEND and target then
		self:revive(target, reviveKind, buyer)
	elseif reviveKind == Enums.ReviveKind.TEAM then
		self:teamRevive()
	end
	return true
end

-- PurchaseManager's handler for the three products: the Robux is spent, so
-- this never refuses
function ReviveManager:onProductPurchased(buyer: Player, reviveKind: number)
	local playerData = GameController:getPlayerData(buyer)
	if not playerData then
		error("buyer is not Ready")
	end
	local target = self.pendingFriendTargetByBuyer[buyer]
	if reviveKind == Enums.ReviveKind.FRIEND then
		self.pendingFriendTargetByBuyer[buyer] = nil
	end
	if self:applyPurchase(buyer, reviveKind, target) then
		return
	end
	playerData:addReviveCredit(reviveKind)
	self:replicateCredits(buyer)
	local kindName = Enums.getPublicName(Enums.ReviveKind, reviveKind) or "revive"
	print(`[ReviveManager] {buyer.Name}'s {kindName} could not apply; kept as a credit`)
	PlayerFeedbackManager:give(buyer, string.format(RevivesData.CREDIT_KEPT_FORMAT, kindName), RevivesData.FEEDBACK_DISPLAY_SEC)
end

-- spends a saved credit when the revive can happen right now; false
-- leaves the credit alone
function ReviveManager:useCreditIfNeeded(buyer: Player, reviveKind: number, target: Player?): boolean
	local playerData = GameController:getPlayerData(buyer)
	if not playerData or playerData:getReviveCredits(reviveKind) <= 0 then
		return false
	end
	if ReviveRules.resolvePurchase(reviveKind, self:buildContext(buyer, target)) ~= ReviveRules.OUTCOME_APPLY then
		return false
	end
	playerData:spendReviveCredit(reviveKind)
	playerData:saveNow()
	self:replicateCredits(buyer)
	PlayerFeedbackManager:give(buyer, RevivesData.CREDIT_USED_FEEDBACK, RevivesData.FEEDBACK_DISPLAY_SEC)
	self:applyPurchase(buyer, reviveKind, target)
	return true
end

-- the Results Menu's button: the dead player's own Revive or the crew's
-- Team Revive, whichever is on offer
function ReviveManager:handleTryRevive(player: Player, payload: { [string]: any })
	local entry = self.deadByPlayer[player]
	local reviveKind = payload.reviveKind
	local offer = if entry then entry.replicatedOffer else nil
	local isOffered = (reviveKind == Enums.ReviveKind.SELF and offer == Enums.ReviveOffer.SELF)
		or (reviveKind == Enums.ReviveKind.TEAM and offer == Enums.ReviveOffer.TEAM)
	if not isOffered then
		PlayerFeedbackManager:give(player, RevivesData.NOT_AVAILABLE_FEEDBACK)
		return
	end
	if self:useCreditIfNeeded(player, reviveKind, nil) then
		return
	end
	PurchaseManager:prompt(player, PRODUCT_ID_BY_KIND[reviveKind])
end

-- the tombstone's prompt: a living player pays for someone else
function ReviveManager:requestFriendRevive(buyer: Player, target: Player)
	if not GameController:isPlayerReady(buyer) or self.deadByPlayer[buyer] or not self.deadByPlayer[target] then
		return
	end
	if self:useCreditIfNeeded(buyer, Enums.ReviveKind.FRIEND, target) then
		return
	end
	self.pendingFriendTargetByBuyer[buyer] = target
	PurchaseManager:prompt(buyer, PRODUCT_ID_BY_KIND[Enums.ReviveKind.FRIEND])
end

-- a dead player names who they watch (0 for nobody): the world streams
-- round that player, as Build Mode does for the Defensive Zone
function ReviveManager:handleTrySpectate(player: Player, payload: { [string]: any })
	local entry = self.deadByPlayer[player]
	if not entry then
		return
	end
	local target = if payload.userId ~= 0 then Players:GetPlayerByUserId(payload.userId) else nil
	if target and (target == player or self.deadByPlayer[target] or not GameController:isPlayerReady(target)) then
		target = nil
	end
	entry.spectateTarget = target
	player.ReplicationFocus = if target then getRoot(target) else entry.tombstone
end

-- the Return to Lobby button: a dead player may give the run up, and
-- anyone may leave once it is over. A player who leaves a run under way
-- leaves their grave behind (onPlayerLeft). The end-of-run summary and
-- its rewards are M33; this is only the trip
function ReviveManager:handleTryReturnToLobby(player: Player)
	if not self.deadByPlayer[player] and RunCycleManager:isRunOn() then
		return
	end
	print(`[ReviveManager] {player.Name} returns to the lobby`)
	local isSuccess, err = pcall(
		function()
			TeleportService:TeleportAsync(Constants.LOBBY_PLACE_ID, { player })
		end
	)
	if not isSuccess then
		warn(`ReviveManager: return to lobby failed for {player.Name}:`, err)
		PlayerFeedbackManager:give(player, PartyRules.FEEDBACK_TELEPORT_FAILED)
	end
end

function ReviveManager:getNetHandlers()
	return {
		[NetEventNames.TRY_RETURN_TO_LOBBY] = {
			shape = TRY_RETURN_TO_LOBBY_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:handleTryReturnToLobby(player)
			end,
		},
		[NetEventNames.TRY_REVIVE] = {
			shape = TRY_REVIVE_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleTryRevive(player, payload)
			end,
		},
		[NetEventNames.TRY_SPECTATE] = {
			shape = TRY_SPECTATE_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleTrySpectate(player, payload)
			end,
		},
	}
end

function ReviveManager:step(deltaSec: number)
	self.stepAccumulatorSec += deltaSec
	if self.stepAccumulatorSec < STEP_INTERVAL_SEC then
		return
	end
	self.stepAccumulatorSec = 0
	if next(self.deadByPlayer) == nil then
		return
	end
	if ReviveRules.isWipeLost(self.wipeDeadline, workspace:GetServerTimeNow()) then
		print("[ReviveManager] nobody was revived in time")
		self:endWipe()
		RunCycleManager:loseAllDead()
	end
	self:replicateOffers()
end

-- dev tool: this player dies now, as if a monster had done it
function ReviveManager:killForDevTool(player: Player)
	self:kill(player)
end

-- dev tool: a revive without paying, through the same door as the paid ones
function ReviveManager:reviveForDevTool(player: Player, reviveKind: number)
	if reviveKind == Enums.ReviveKind.TEAM then
		if self:isCrewWiped() then
			self:teamRevive()
		end
		return
	end
	self:revive(player, reviveKind, nil)
end

-- dev tool: the once-per-run Team Revive is available again
function ReviveManager:resetTeamReviveForDevTool()
	self.isTeamReviveUsed = false
	self:replicateOffers()
end

-- a run (or a dev-tool restart) starts with everyone alive
function ReviveManager:onRunStarted()
	self:endWipe()
	self.isTeamReviveUsed = false
	self.pendingFriendTargetByBuyer = {}
	self.invulnerableUntilByPlayer = {}
	for _, grave in self.leaverGraves do
		grave.tombstone:Destroy()
	end
	self.leaverGraves = {}
	local dead = {}
	for player in self.deadByPlayer do
		table.insert(dead, player)
	end
	for _, player in dead do
		self:removeEntry(player)
		local humanoid = getHumanoid(player)
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
		player.ReplicationFocus = nil
		self:releaseRoot(player)
		self:placeRevived(player, nil)
		ToolManager:setToolsLocked(player, false)
		self:replicateAlive(player)
	end
end

-- ready-sequence entry; not replayed on a dev-tool reset, so run state survives
function ReviveManager:onPlayerReady(player: Player)
	if not self.isSetUpByPlayer[player] then
		self.isSetUpByPlayer[player] = true
		player.CharacterAdded:Connect(
			function(character: Model)
				self:setUpCharacter(player, character)
			end
		)
		local character = player.Character
		if character then
			task.spawn(
				function()
					self:setUpCharacter(player, character)
				end
			)
		end
	end
	if not self.deadByPlayer[player] then
		self:replicateAlive(player)
	end
	self:replicateCredits(player)
end

-- a player who leaves a run under way leaves a grave behind (their own,
-- if they were dead, now without its prompt)
function ReviveManager:leaveGrave(player: Player)
	local entry = self.deadByPlayer[player]
	local tombstone = if entry then entry.tombstone else nil
	local plotIndex = if entry then entry.plotIndex else nil
	if entry then
		entry.tombstone = nil
	elseif RunCycleManager:isRunOn() then
		tombstone, plotIndex = self:createGrave(player, false)
	end
	if not tombstone or not plotIndex then
		return
	end
	local prompt = tombstone:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt:Destroy()
	end
	table.insert(self.leaverGraves, {
		tombstone = tombstone,
		plotIndex = plotIndex,
	})
end

-- the crew left behind may now all be dead
function ReviveManager:onPlayerLeft(player: Player)
	self:leaveGrave(player)
	self:removeEntry(player)
	self.invulnerableUntilByPlayer[player] = nil
	self.isSetUpByPlayer[player] = nil
	self.pendingFriendTargetByBuyer[player] = nil
	for buyer, target in self.pendingFriendTargetByBuyer do
		if target == player then
			self.pendingFriendTargetByBuyer[buyer] = nil
		end
	end
	for _, entry in self.deadByPlayer do
		if entry.spectateTarget == player then
			entry.spectateTarget = nil
		end
	end
	-- the leaver is still in the Ready list during PlayerRemoving
	task.defer(
		function()
			self:startWipeIfNeeded(0)
			self:replicateOffers()
		end
	)
end

function ReviveManager:fetchPrices()
	for reviveKind, productId in PRODUCT_ID_BY_KIND do
		local price = PurchaseManager:fetchPriceRobux(productId)
		SplendidReplicationManager:setGameMetadata(PRICE_ATTRIBUTE_BY_KIND[reviveKind], price or 0)
	end
end

function ReviveManager:init()
	SplendidReplicationManager:setGameMetadata(Attributes.PLAYER_MAX_HEALTH, RevivesData.PLAYER_MAX_HEALTH)
	SplendidReplicationManager:setGameMetadata(Attributes.IS_CREW_WIPED, false)
	SplendidReplicationManager:setGameMetadata(Attributes.GAME_OVER_HOLD_SEC, RevivesData.GAME_OVER_HOLD_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.GAME_OVER_FADE_IN_SEC, RevivesData.GAME_OVER_FADE_IN_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.GAME_OVER_BLACK_HOLD_SEC, RevivesData.GAME_OVER_BLACK_HOLD_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.GAME_OVER_FADE_OUT_SEC, RevivesData.GAME_OVER_FADE_OUT_SEC)
	for _, attributeName in PRICE_ATTRIBUTE_BY_KIND do
		SplendidReplicationManager:setGameMetadata(attributeName, 0)
	end
	task.spawn(
		function()
			self:fetchPrices()
		end
	)
	for reviveKind, productId in PRODUCT_ID_BY_KIND do
		PurchaseManager:registerProduct(
			productId,
			function(buyer: Player, _productId: number)
				self:onProductPurchased(buyer, reviveKind)
			end
		)
	end
	-- a prompt closed without buying: forget which tombstone it was for
	PurchaseManager:subscribePromptFinished(
		function(player: Player, productId: number, isPurchased: boolean)
			if not isPurchased and productId == PRODUCT_ID_BY_KIND[Enums.ReviveKind.FRIEND] then
				self.pendingFriendTargetByBuyer[player] = nil
			end
		end
	)
	RunCycleManager:subscribeRunEnded(
		function(_isWon: boolean, reason: number)
			self:endWipe()
			if reason == Enums.RunEndReason.REFINERY_DESTROYED then
				self:buryTheLiving()
			end
			self:replicateOffers()
		end
	)
	GameController:registerPlaceManager(self)
	-- not a teardown entry: a dev-tool reset must not bring the dead back
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self:onPlayerLeft(player)
		end
	)
	RunService.Heartbeat:Connect(
		function(deltaSec: number)
			self:step(deltaSec)
		end
	)
end

function ReviveManager.new(): ReviveManager
	local self = setmetatable({}, ReviveManager) :: ReviveManager
	self.deadByPlayer = {}
	self.invulnerableUntilByPlayer = {}
	self.isSetUpByPlayer = {}
	self.isTeamReviveUsed = false
	self.wipeDeadline = 0
	self.pendingFriendTargetByBuyer = {}
	self.leaverGraves = {}
	self.diedHandlers = {}
	self.teamRevivedHandlers = {}
	self.shadowFolder = nil
	self.hasWarnedNoDeathRoom = false
	self.stepAccumulatorSec = 0
	return self
end

return ReviveManager.new()
