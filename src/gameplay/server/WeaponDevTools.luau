--!strict

-- Gameplay dev tools for weapons and defenses (M24, M27). Enemies arrive
-- at M29, so dummies are how shooting, Towers, and Traps are tested: each
-- registers with DamageableManager the way an enemy will and is gone at 0
-- HP. The target dummy stands in front of the admin; the walking dummy
-- spawns far out and walks a straight line back to where the admin stood,
-- on the ground or in the air, so slows, stuns, contact Traps, barriers,
-- and air-only Towers can all be seen working.
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local DamageableManager = require(script.Parent.DamageableManager)

local WeaponDevTools = {}
WeaponDevTools.__index = WeaponDevTools

export type WeaponDevTools = typeof(setmetatable({} :: {}, WeaponDevTools))

WeaponDevTools.SPAWN_TARGET_DUMMY_COMMAND = "spawnTargetDummy"
WeaponDevTools.SPAWN_WALKING_DUMMY_COMMAND = "spawnWalkingDummy"
WeaponDevTools.CLEAR_TARGET_DUMMIES_COMMAND = "clearTargetDummies"

local SPAWN_TARGET_DUMMY_ARGS_SHAPE = {}
local SPAWN_WALKING_DUMMY_ARGS_SHAPE = {
	isAirborne = "boolean",
}
local CLEAR_TARGET_DUMMIES_ARGS_SHAPE = {}
local DUMMY_NAME = "Target Dummy"
local WALKING_DUMMY_NAME = "Walking Dummy"
local FLYING_DUMMY_NAME = "Flying Dummy"

-- where the admin's feet are and which way they face, flattened
function WeaponDevTools:readAdminStance(player: Player): (Vector3?, Vector3?)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return nil, nil
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.zAxis
	end
	return root.Position - Vector3.new(0, 3, 0), flatLook.Unit
end

function WeaponDevTools:spawnTargetDummy(player: Player)
	local feet, flatLook = self:readAdminStance(player)
	if not feet or not flatLook then
		return
	end
	-- feet level with the admin's, facing back at them
	local size: Vector3 = HandheldData.TARGET_DUMMY_SIZE
	local center = feet + flatLook * HandheldData.TARGET_DUMMY_DISTANCE_STUDS + Vector3.new(0, size.Y / 2, 0)
	DamageableManager:register({
		name = DUMMY_NAME,
		cframe = CFrame.lookAt(center, center - flatLook),
		size = size,
		maxHp = HandheldData.TARGET_DUMMY_HP,
		onDestroyed = function(attacker: Player?)
			if attacker then
				PlayerFeedbackManager:give(attacker, `{DUMMY_NAME} destroyed`)
			end
		end,
	})
end

function WeaponDevTools:spawnWalkingDummy(player: Player, isAirborne: boolean)
	local feet, flatLook = self:readAdminStance(player)
	if not feet or not flatLook then
		return
	end
	local size: Vector3 = HandheldData.TARGET_DUMMY_SIZE
	local lift = Vector3.new(0, size.Y / 2 + (if isAirborne then HandheldData.WALKING_DUMMY_AIR_HEIGHT_STUDS else 0), 0)
	local start = feet + flatLook * HandheldData.WALKING_DUMMY_DISTANCE_STUDS + lift
	local destination = feet + lift
	local name = if isAirborne then FLYING_DUMMY_NAME else WALKING_DUMMY_NAME
	local id = DamageableManager:register({
		name = name,
		cframe = CFrame.lookAt(start, destination),
		size = size,
		maxHp = HandheldData.WALKING_DUMMY_HP,
		isAirborne = isAirborne,
		attackDamagePerSec = HandheldData.WALKING_DUMMY_ATTACK_DAMAGE_PER_SEC,
		onDestroyed = function(attacker: Player?)
			if attacker then
				PlayerFeedbackManager:give(attacker, `{name} destroyed`)
			end
		end,
	})
	DamageableManager:setWalk(id, {
		destination = destination,
		speedStudsPerSec = HandheldData.WALKING_DUMMY_SPEED_STUDS_PER_SEC,
	})
end

function WeaponDevTools:init()
	DevTools:registerPlaceCommand(
		WeaponDevTools.SPAWN_TARGET_DUMMY_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, SPAWN_TARGET_DUMMY_ARGS_SHAPE)
			if not isValid then
				warn("WeaponDevTools: spawnTargetDummy with invalid args:", err)
				return
			end
			self:spawnTargetDummy(player)
		end
	)
	DevTools:registerPlaceCommand(
		WeaponDevTools.SPAWN_WALKING_DUMMY_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, SPAWN_WALKING_DUMMY_ARGS_SHAPE)
			if not isValid then
				warn("WeaponDevTools: spawnWalkingDummy with invalid args:", err)
				return
			end
			self:spawnWalkingDummy(player, args.isAirborne)
		end
	)
	DevTools:registerPlaceCommand(
		WeaponDevTools.CLEAR_TARGET_DUMMIES_COMMAND,
		function(_player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, CLEAR_TARGET_DUMMIES_ARGS_SHAPE)
			if not isValid then
				warn("WeaponDevTools: clearTargetDummies with invalid args:", err)
				return
			end
			-- only dummies register until M29
			DamageableManager:unregisterAll()
		end
	)
end

function WeaponDevTools.new(): WeaponDevTools
	local self = setmetatable({}, WeaponDevTools) :: WeaponDevTools
	return self
end

return WeaponDevTools.new()
