--!strict

-- What a Tower's attack looks like on this client (GDD "Tower Types"),
-- M27. The server's TowerBehaviorManager decides every hit; this manager
-- only draws it. A NotifyTowerFired names the Tower and the targets it
-- hit: a single hit is a tracer from the muzzle to the body, a chain is a
-- bolt from the muzzle to the first body and on to each next one, and
-- every hit body flashes. Cone Towers send no message: their flame is the
-- shadow's IsAttacking attribute, which ClientPlacementManager draws. The
-- streaks are plain neon parts in a client-only folder, gone after a
-- moment; real effects are Phase 9.
local Debris = game:GetService("Debris")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientPlacementManager = require(script.Parent.ClientPlacementManager)

local ClientTowerBehaviorManager = {}
ClientTowerBehaviorManager.__index = ClientTowerBehaviorManager

export type ClientTowerBehaviorManager = typeof(setmetatable(
	{} :: {
		effectsFolder: Folder?,
	},
	ClientTowerBehaviorManager
))

local NOTIFY_TOWER_FIRED_SHAPE = {
	id = "string",
	hitIds = { type = "array", elementType = "string" },
}

local EFFECTS_FOLDER = "TowerEffects"
local TRACER_COLOR = Color3.fromRGB(255, 220, 140)
local TRACER_THICKNESS_STUDS = 0.15
local TRACER_LIFE_SEC = 0.08
local BOLT_COLOR = Color3.fromRGB(150, 200, 255)
local BOLT_THICKNESS_STUDS = 0.3
local BOLT_LIFE_SEC = 0.15

function ClientTowerBehaviorManager:getEffectsFolder(): Folder
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

function ClientTowerBehaviorManager:drawStreak(from: Vector3, to: Vector3, color: Color3, thickness: number, lifeSec: number)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local streak = Instance.new("Part")
	streak.Name = "Streak"
	streak.Anchored = true
	streak.CanCollide = false
	streak.CanQuery = false
	streak.CanTouch = false
	streak.CastShadow = false
	streak.Material = Enum.Material.Neon
	streak.Color = color
	streak.Size = Vector3.new(thickness, thickness, length)
	streak.CFrame = CFrame.lookAt((from + to) / 2, to)
	streak.Parent = self:getEffectsFolder()
	Debris:AddItem(streak, lifeSec)
end

function ClientTowerBehaviorManager:onTowerFired(payload: any)
	if not Validate.isTableShape(payload, NOTIFY_TOWER_FIRED_SHAPE) then
		warn("ClientTowerBehaviorManager: malformed NotifyTowerFired")
		return
	end
	local shadow = ClientPlacementManager:findShadowById(payload.id)
	if not shadow then
		return
	end
	local isChain = ClientPlacementManager:getTowerAttack(shadow) == Enums.TowerAttack.CHAIN
	local from = ClientPlacementManager:getMuzzlePosition(shadow)
	for _, hitId in payload.hitIds do
		local to = ClientDamageableManager:getBodyPosition(hitId)
		if not to then
			continue
		end
		if isChain then
			self:drawStreak(from, to, BOLT_COLOR, BOLT_THICKNESS_STUDS, BOLT_LIFE_SEC)
		else
			self:drawStreak(from, to, TRACER_COLOR, TRACER_THICKNESS_STUDS, TRACER_LIFE_SEC)
		end
		ClientDamageableManager:flashHit(hitId)
		from = to
	end
end

function ClientTowerBehaviorManager:init()
	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_TOWER_FIRED,
		function(payload: any)
			self:onTowerFired(payload)
		end
	)
end

function ClientTowerBehaviorManager.new(): ClientTowerBehaviorManager
	local self = setmetatable({}, ClientTowerBehaviorManager) :: ClientTowerBehaviorManager
	self.effectsFolder = nil
	return self
end

return ClientTowerBehaviorManager.new()
