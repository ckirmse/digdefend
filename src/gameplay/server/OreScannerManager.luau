--!strict

-- The Ore Scanner, the Prospector's gadget (GDD "Classes", 2026-10-22).
-- The GADGET slot is the scanner while the class says so (granted here;
-- the Auto Turret manager, which runs first, takes the slot from any
-- class without a turret, so this only ever gives). With it in hand the
-- use input asks TryUseOreScanner; the server checks the player is
-- alive, holds the scanner, has it equipped, stands inside the mine's
-- grid (MineSpace.containsPosition, the run report's test), and is off
-- cooldown, then tells every client the sweep (NotifyOreScan: the origin,
-- the radius, and the timings from GameData/Gadgets/OreScanner), which
-- each draws from its own copy of the grid, so no ore positions travel.
-- A use starts the cooldown (COOLDOWN_SEC; designer, 2026-10-22, once a
-- day for an hour before that) through the shared gadget ready time
-- (GadgetReadyTime on CurrentPlayer, the length published as
-- GameMetadata so the slot drains its sheet), and the scanner leaves the
-- hand until then.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local MineSpace = require("@game/ReplicatedStorage/Shared/MineSpace")
local MiningRules = require("@game/ReplicatedStorage/Shared/MiningRules")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local OreScannerData = require("@game/ServerScriptService/GameData/Gadgets/OreScanner")
local CharacterManager = require(script.Parent.Parent.Server.CharacterManager)
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local MineManager = require(script.Parent.MineManager)
local ReviveManager = require(script.Parent.ReviveManager)
local RunCycleManager = require(script.Parent.RunCycleManager)
local ToolManager = require(script.Parent.ToolManager)

local OreScannerManager = {}
OreScannerManager.__index = OreScannerManager

export type OreScannerManager = typeof(setmetatable(
	{} :: {
		-- when a player's scanner is ready again; nil when it is
		readyTimeByPlayer: { [Player]: number },
	},
	OreScannerManager
))

local TRY_USE_ORE_SCANNER_SHAPE = {}
local FEEDBACK_COOLING = "Scanner ready in %d s"
local FEEDBACK_NOT_IN_MINE = "The scanner only works inside the mine."
local FEEDBACK_NOT_YET = "Not until the day starts."

function OreScannerManager:hasScanner(player: Player): boolean
	return CharacterManager:getGadgetKind(player) == Enums.GadgetKind.ORE_SCANNER
end

-- seconds until the scanner is ready; 0 when it is
function OreScannerManager:getCooldownLeft(player: Player): number
	local readyTime = self.readyTimeByPlayer[player]
	if not readyTime then
		return 0
	end
	return math.max(0, readyTime - workspace:GetServerTimeNow())
end

function OreScannerManager:replicate(player: Player)
	if not player.Parent then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.GADGET_READY_TIME, self.readyTimeByPlayer[player] or 0)
end

function OreScannerManager:setReadyTime(player: Player, readyTime: number?)
	self.readyTimeByPlayer[player] = readyTime
	self:replicate(player)
end

function OreScannerManager:use(player: Player)
	if not GameController:isPlayerReady(player) or ReviveManager:isDead(player) then
		return
	end
	if not self:hasScanner(player) or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.GADGET then
		return
	end
	local cooldownLeft = self:getCooldownLeft(player)
	if cooldownLeft > 0 then
		PlayerFeedbackManager:give(player, string.format(FEEDBACK_COOLING, math.ceil(cooldownLeft)))
		return
	end
	if not RunCycleManager:isRunOn() then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_YET)
		return
	end
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	local grid = MineManager:getGrid()
	local space = MineManager:getSpace()
	if not head or not head:IsA("BasePart") or not grid or not space then
		return
	end
	local origin = head.Position
	if not MineSpace.containsPosition(space, grid.depth, grid.height, grid.width, origin) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_IN_MINE)
		return
	end
	-- the use is the spend: out of the hand, the slot draining until ready
	self:setReadyTime(player, workspace:GetServerTimeNow() + OreScannerData.COOLDOWN_SEC)
	ToolManager:setEquippedTool(player, MiningRules.NO_TOOL)
	NetManager:notifyAllClients(NetEventNames.NOTIFY_ORE_SCAN, {
		userId = player.UserId,
		origin = origin,
		radiusStuds = OreScannerData.RADIUS_STUDS,
		sweepSec = OreScannerData.SWEEP_SEC,
		revealDelaySec = OreScannerData.REVEAL_DELAY_SEC,
		holdSec = OreScannerData.HOLD_SEC,
		fadeSec = OreScannerData.FADE_SEC,
		pulseCount = OreScannerData.PULSE_COUNT,
	})
end

-- the slot is the scanner's while the class says so (see the header)
function OreScannerManager:applyGadget(player: Player)
	if self:hasScanner(player) then
		ToolManager:grantTool(player, Enums.ToolKind.GADGET)
	end
end

function OreScannerManager:getNetHandlers()
	return {
		[NetEventNames.TRY_USE_ORE_SCANNER] = {
			shape = TRY_USE_ORE_SCANNER_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				self:use(player)
			end,
		},
	}
end

-- a new run: every cooldown over
function OreScannerManager:onRunStarted()
	for player in self.readyTimeByPlayer do
		if player.Parent then
			self:setReadyTime(player, nil)
		end
	end
	for _, player in GameController:getReadyPlayers() do
		self:applyGadget(player)
	end
end

function OreScannerManager:onPlayerReady(player: Player)
	self:replicate(player)
	self:applyGadget(player)
end

function OreScannerManager:onPlayerRemoved(player: Player)
	self.readyTimeByPlayer[player] = nil
end

function OreScannerManager:init()
	-- the slot drains its sheet over the same wait the server keeps
	SplendidReplicationManager:setGameMetadata(Attributes.ORE_SCANNER_COOLDOWN_SEC, OreScannerData.COOLDOWN_SEC)
	GameController:registerPlaceManager(self)
	CharacterManager:subscribeClassChanged(
		function(player: Player, _classKind: number)
			if GameController:isPlayerReady(player) then
				self:applyGadget(player)
			end
		end
	)
end

function OreScannerManager.new(): OreScannerManager
	local self = setmetatable({}, OreScannerManager) :: OreScannerManager
	self.readyTimeByPlayer = {}
	return self
end

return OreScannerManager.new()
