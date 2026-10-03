--!strict

-- The Defense Table (GDD "Defense Table"): the map table in the camp's
-- Defense Store, the one way into Build Mode (decided 2026-09-30,
-- replacing the Defenses tool). Its ProximityPrompt is heard here; a
-- trigger puts the player in Build Mode, which is state held in this
-- manager and published privately (IsInBuildMode) for the client to lift
-- its camera over the Defensive Zone. PlacementManager asks
-- isInBuildMode before it accepts a build.
--
-- While in Build Mode the player's tools are locked (hands empty, as at a
-- post) and their streaming is focused on the zone instead of on their
-- character: the zone is far from the store, and without that the
-- placements there would not be loaded for them. Build Mode ends when the
-- client asks (the Exit button), when the player is hurt or dies (so a
-- night attack never finds them stuck in a menu), or when they leave.
-- Ending it first streams the camp back in around the character, then
-- tells the client, so the camera never returns to an unloaded store.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local TableData = require("@game/ServerScriptService/GameData/Defenses/Table")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local MapManager = require(script.Parent.MapManager)
local ToolManager = require(script.Parent.ToolManager)

local DefenseTableManager = {}
DefenseTableManager.__index = DefenseTableManager

type Session = {
	connections: { RBXScriptConnection },
	lastHealth: number,
}

export type DefenseTableManager = typeof(setmetatable(
	{} :: {
		sessionByPlayer: { [Player]: Session },
		promptConnection: RBXScriptConnection?,
		-- what a player's streaming follows while they are at the table
		focusPart: BasePart?,
	},
	DefenseTableManager
))

local TRY_EXIT_BUILD_MODE_SHAPE = {}

function DefenseTableManager:isInBuildMode(player: Player): boolean
	return self.sessionByPlayer[player] ~= nil
end

function DefenseTableManager:replicate(player: Player)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.IS_IN_BUILD_MODE, self:isInBuildMode(player))
end

function DefenseTableManager:exit(player: Player)
	local session = self.sessionByPlayer[player]
	if not session then
		return
	end
	self.sessionByPlayer[player] = nil
	for _, connection in session.connections do
		connection:Disconnect()
	end
	if player.Parent ~= Players then
		return
	end
	ToolManager:setToolsLocked(player, false)
	player.ReplicationFocus = nil
	-- the camp streams back in around the character before the client is
	-- told, so its camera never returns to a store that is not there yet
	task.spawn(
		function()
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				pcall(
					function()
						player:RequestStreamAroundAsync(root.Position, TableData.EXIT_STREAM_TIMEOUT_SEC)
					end
				)
			end
			-- unless they walked back in during the wait
			if player.Parent == Players and not self.sessionByPlayer[player] then
				self:replicate(player)
			end
		end
	)
end

function DefenseTableManager:enter(player: Player)
	if not GameController:isPlayerReady(player) or self.sessionByPlayer[player] then
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	local session: Session = {
		connections = {},
		lastHealth = humanoid.Health,
	}
	self.sessionByPlayer[player] = session
	-- a hit drops the player out so they can react; healing does not
	table.insert(
		session.connections,
		humanoid.HealthChanged:Connect(
			function(health: number)
				if health < session.lastHealth then
					self:exit(player)
					return
				end
				session.lastHealth = health
			end
		)
	)
	table.insert(
		session.connections,
		player.CharacterRemoving:Connect(
			function()
				self:exit(player)
			end
		)
	)
	ToolManager:setToolsLocked(player, true)
	if self.focusPart then
		player.ReplicationFocus = self.focusPart
	end
	self:replicate(player)
end

function DefenseTableManager:getNetHandlers()
	return {
		[NetEventNames.TRY_EXIT_BUILD_MODE] = {
			shape = TRY_EXIT_BUILD_MODE_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:exit(player)
			end,
		},
	}
end

-- the first Defensive Zone by name: where a player at the table looks
function DefenseTableManager:findFocusPart(camp: Instance): BasePart?
	local folder = camp:FindFirstChild(Constants.CAMP_DEFENSIVE_ZONES_FOLDER)
	local first: BasePart? = nil
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("BasePart") and (not first or child.Name < first.Name) then
				first = child
			end
		end
	end
	return first
end

-- binds the loaded camp's table; the previous camp's connection dies with
-- its instances but is dropped here so a restart never hears two prompts
function DefenseTableManager:bindTable()
	if self.promptConnection then
		self.promptConnection:Disconnect()
		self.promptConnection = nil
	end
	local camp = MapManager:getCamp()
	self.focusPart = if camp then self:findFocusPart(camp) else nil
	local promptPart = MapManager:findDefenseTablePart(Constants.TOWER_TABLE_MODEL, Constants.DEFENSE_TABLE_PROMPT_PART)
	if not promptPart then
		warn(`DefenseTableManager: the loaded camp has no {Constants.TOWER_TABLE_MODEL}.{Constants.DEFENSE_TABLE_PROMPT_PART} in its {Constants.CAMP_DEFENSE_STORE_MODEL}; nothing can be built`)
		return
	end
	-- the prompt is created here so a table authored in Studio needs only its Prompt part
	local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person (2026-09-29)
		prompt.ClickablePrompt = false
		prompt.Parent = promptPart
	end
	local livePrompt = prompt :: ProximityPrompt
	livePrompt.ActionText = TableData.PROMPT_ACTION_TEXT
	livePrompt.ObjectText = TableData.PROMPT_OBJECT_TEXT
	livePrompt.HoldDuration = TableData.PROMPT_HOLD_SEC
	livePrompt.MaxActivationDistance = TableData.PROMPT_MAX_DISTANCE_STUDS
	livePrompt.RequiresLineOfSight = false
	livePrompt.Enabled = true
	self.promptConnection = livePrompt.Triggered:Connect(
		function(player: Player)
			self:enter(player)
		end
	)
end

-- a run (or a dev-tool restart) starts with nobody at the fresh camp's table
function DefenseTableManager:onRunStarted()
	for player in self.sessionByPlayer do
		self:exit(player)
	end
	self:bindTable()
end

-- ready-sequence entry
function DefenseTableManager:onPlayerReady(player: Player)
	self:replicate(player)
end

function DefenseTableManager:init()
	GameController:registerPlaceManager(self)
	SplendidReplicationManager:setGameMetadata(Attributes.BUILD_CAMERA_DISTANCE_STUDS, TableData.CAMERA_DISTANCE_STUDS)
	SplendidReplicationManager:setGameMetadata(Attributes.BUILD_CAMERA_MIN_DISTANCE_STUDS, TableData.CAMERA_MIN_DISTANCE_STUDS)
	SplendidReplicationManager:setGameMetadata(Attributes.BUILD_CAMERA_MAX_DISTANCE_STUDS, TableData.CAMERA_MAX_DISTANCE_STUDS)
	SplendidReplicationManager:setGameMetadata(Attributes.BUILD_CAMERA_PITCH_DEGREES, TableData.CAMERA_PITCH_DEGREES)
	SplendidReplicationManager:setGameMetadata(Attributes.BUILD_CAMERA_PAN_SCREENS_PER_SEC, TableData.CAMERA_PAN_SCREENS_PER_SEC)
	SplendidReplicationManager:setGameMetadata(Attributes.BUILD_CAMERA_TRANSITION_SEC, TableData.CAMERA_TRANSITION_SEC)
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self:exit(player)
		end
	)
end

function DefenseTableManager.new(): DefenseTableManager
	local self = setmetatable({}, DefenseTableManager) :: DefenseTableManager
	self.sessionByPlayer = {}
	self.promptConnection = nil
	self.focusPart = nil
	return self
end

return DefenseTableManager.new()
