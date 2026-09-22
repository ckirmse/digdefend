--!strict

-- What a Trap going off looks like on this client (GDD "Trap Types"),
-- M27. The server's TrapBehaviorManager decides every trigger; this
-- manager only draws it. A NotifyTrapTriggered names the Trap and its
-- kind: a Land Mine blows as a growing orange sphere, a Bear Trap snaps
-- with a small grey one, a Spike Trap pops with a quick glint (its spikes
-- themselves follow the shadow's TrapState attribute, which
-- ClientPlacementManager draws). The shapes are plain neon parts tweened
-- out in a client-only folder; real effects are Phase 9.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientPlacementManager = require(script.Parent.ClientPlacementManager)

local ClientTrapBehaviorManager = {}
ClientTrapBehaviorManager.__index = ClientTrapBehaviorManager

export type ClientTrapBehaviorManager = typeof(setmetatable(
	{} :: {
		effectsFolder: Folder?,
	},
	ClientTrapBehaviorManager
))

local NOTIFY_TRAP_TRIGGERED_SHAPE = {
	id = "string",
	trapKind = { type = "enum", name = "TrapKind" },
}

local EFFECTS_FOLDER = "TrapEffects"
type Pop = {
	color: Color3,
	radiusStuds: number,
	lifeSec: number,
}
local POP_BY_KIND: { [number]: Pop } = {
	[Enums.TrapKind.LAND_MINE] = { color = Color3.fromRGB(255, 150, 40), radiusStuds = 10, lifeSec = 0.35 },
	[Enums.TrapKind.BEAR_TRAP] = { color = Color3.fromRGB(200, 200, 210), radiusStuds = 2.5, lifeSec = 0.2 },
	[Enums.TrapKind.SPIKE_TRAP] = { color = Color3.fromRGB(230, 230, 240), radiusStuds = 3, lifeSec = 0.15 },
}

function ClientTrapBehaviorManager:getEffectsFolder(): Folder
	local folder = self.effectsFolder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = EFFECTS_FOLDER
	created.Parent = workspace
	self.effectsFolder = created
	return created
end

function ClientTrapBehaviorManager:drawPop(position: Vector3, pop: Pop)
	local sphere = Instance.new("Part")
	sphere.Name = "Pop"
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.Neon
	sphere.Color = pop.color
	sphere.Transparency = 0.2
	sphere.Size = Vector3.one
	sphere.CFrame = CFrame.new(position)
	sphere.Parent = self:getEffectsFolder()
	TweenService:Create(sphere, TweenInfo.new(pop.lifeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * pop.radiusStuds * 2,
		Transparency = 1,
	}):Play()
	Debris:AddItem(sphere, pop.lifeSec)
end

function ClientTrapBehaviorManager:onTrapTriggered(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_TRAP_TRIGGERED_SHAPE) then
		warn("ClientTrapBehaviorManager: malformed NotifyTrapTriggered")
		return
	end
	local pop = POP_BY_KIND[payload.trapKind]
	-- a one-use Trap's shadow may already be gone when the message lands;
	-- the position was captured as it left
	local position = ClientPlacementManager:getLastKnownPosition(payload.id)
	if not pop or not position then
		return
	end
	self:drawPop(position, pop)
end

function ClientTrapBehaviorManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_TRAP_TRIGGERED,
		function(payload: any)
			self:onTrapTriggered(payload)
		end
	)
end

function ClientTrapBehaviorManager.new(): ClientTrapBehaviorManager
	local self = setmetatable({}, ClientTrapBehaviorManager) :: ClientTrapBehaviorManager
	self.effectsFolder = nil
	return self
end

return ClientTrapBehaviorManager.new()
