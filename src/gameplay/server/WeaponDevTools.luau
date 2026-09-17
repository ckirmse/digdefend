--!strict

-- Gameplay dev tools for weapons (M24). Enemies arrive at M29, so a target
-- dummy is how shooting is tested: it registers with DamageableManager the
-- way an enemy will, stands in front of the admin, and is gone at 0 HP.
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local DamageableManager = require(script.Parent.DamageableManager)

local WeaponDevTools = {}
WeaponDevTools.__index = WeaponDevTools

export type WeaponDevTools = typeof(setmetatable({} :: {}, WeaponDevTools))

WeaponDevTools.SPAWN_TARGET_DUMMY_COMMAND = "spawnTargetDummy"
WeaponDevTools.CLEAR_TARGET_DUMMIES_COMMAND = "clearTargetDummies"

local SPAWN_TARGET_DUMMY_ARGS_SHAPE = {}
local CLEAR_TARGET_DUMMIES_ARGS_SHAPE = {}
local DUMMY_NAME = "Target Dummy"

function WeaponDevTools:spawnTargetDummy(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.zAxis
	end
	-- feet level with the admin's, facing back at them
	local size: Vector3 = HandheldData.TARGET_DUMMY_SIZE
	local feet = root.Position - Vector3.new(0, 3, 0)
	local center = feet + flatLook.Unit * HandheldData.TARGET_DUMMY_DISTANCE_STUDS + Vector3.new(0, size.Y / 2, 0)
	DamageableManager:register({
		name = DUMMY_NAME,
		cframe = CFrame.lookAt(center, center - flatLook.Unit),
		size = size,
		maxHp = HandheldData.TARGET_DUMMY_HP,
		onDestroyed = function(attacker: Player?)
			if attacker then
				PlayerFeedbackManager:give(attacker, `{DUMMY_NAME} destroyed`)
			end
		end,
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
