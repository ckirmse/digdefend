--!strict

-- Handheld weapons (GDD "Weapon (Default Tool)", S12), M24. Every player
-- starts the run with the weapon their lobby loadout names, or the default
-- Rifle; equipping it is Weapon Mode on the client. Ammo, the reload, and
-- the fire cooldown are run state held here in Lua and published as private
-- attributes. Every shot is a TryFireWeapon request carrying only the ray
-- the client aimed: the server checks the weapon is equipped, loaded, off
-- cooldown, and that the ray starts near the shooter's head, then decides
-- the hit itself, a workspace raycast for what the world blocks and box
-- maths (WeaponRules) against DamageableManager's targets. The mine's rocks
-- exist only on clients, so a rock never blocks a shot here; nothing
-- damageable lives in the mine until M29, which is when that is revisited.
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local ToolManager = require(script.Parent.ToolManager)

local WeaponManager = {}
WeaponManager.__index = WeaponManager

type WeaponState = {
	weaponKind: number,
	ammo: number,
	-- server time the running reload ends; 0 when none
	reloadEndTime: number,
	lastFireTime: number?,
}

export type WeaponManager = typeof(setmetatable(
	{} :: {
		stateByPlayer: { [Player]: WeaponState },
	},
	WeaponManager
))

local TRY_FIRE_WEAPON_SHAPE = {
	origin = "vector3",
	direction = "vector3",
}
local TRY_RELOAD_WEAPON_SHAPE = {}

-- sent as the hit id when a shot hits nothing damageable
local NO_HIT_ID = ""
local MIN_DIRECTION_MAGNITUDE = 0.001

function WeaponManager:getWeaponData(weaponKind: number): WeaponRules.WeaponData?
	return HandheldData.BY_KIND[weaponKind]
end

function WeaponManager:replicate(player: Player)
	local state = self.stateByPlayer[player]
	local data = if state then self:getWeaponData(state.weaponKind) else nil
	if not state or not data then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_AMMO, state.ammo)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_RELOAD_END_TIME, state.reloadEndTime)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_MAGAZINE_SIZE, data.MAGAZINE_SIZE)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_FIRE_INTERVAL_SEC, data.FIRE_INTERVAL_SEC)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_RANGE_STUDS, data.RANGE_STUDS)
end

-- a reload runs whether or not the weapon stays in the hand, so swapping
-- tools never cancels or skips it
function WeaponManager:startReloadIfNeeded(player: Player)
	local state = self.stateByPlayer[player]
	local data = if state then self:getWeaponData(state.weaponKind) else nil
	if not state or not data then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not WeaponRules.canReload(state.ammo, data.MAGAZINE_SIZE, state.reloadEndTime, now) then
		return
	end
	local reloadEndTime = now + data.RELOAD_SEC
	state.reloadEndTime = reloadEndTime
	self:replicate(player)
	task.delay(
		data.RELOAD_SEC,
		function()
			local current = self.stateByPlayer[player]
			if current ~= state or state.reloadEndTime ~= reloadEndTime then
				return
			end
			state.ammo = data.MAGAZINE_SIZE
			state.reloadEndTime = 0
			self:replicate(player)
		end
	)
end

function WeaponManager:getHeadPosition(player: Player): Vector3?
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- how far the ray travels before the world stops it. Characters never
-- block: players cannot be shot, and a crewmate in the way must not eat
-- the bullet either
function WeaponManager:getWorldDistance(origin: Vector3, unitDirection: Vector3, rangeStuds: number): number
	local excluded: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(excluded, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	local result = workspace:Raycast(origin, unitDirection * rangeStuds, params)
	return if result then result.Distance else rangeStuds
end

function WeaponManager:fire(player: Player, origin: Vector3, direction: Vector3)
	local state = self.stateByPlayer[player]
	local data = if state then self:getWeaponData(state.weaponKind) else nil
	if not state or not data or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.WEAPON then
		return
	end
	if direction.Magnitude < MIN_DIRECTION_MAGNITUDE then
		return
	end
	local now = workspace:GetServerTimeNow()
	if WeaponRules.isReloading(state.reloadEndTime, now) or not WeaponRules.canFire(state.lastFireTime, now, data.FIRE_COOLDOWN_SEC) then
		return
	end
	if state.ammo <= 0 then
		self:startReloadIfNeeded(player)
		return
	end
	local headPosition = self:getHeadPosition(player)
	if not headPosition or not WeaponRules.isOriginPlausible(headPosition, origin, HandheldData.ORIGIN_TOLERANCE_STUDS) then
		return
	end
	local unitDirection = direction.Unit
	state.lastFireTime = now
	state.ammo -= 1

	local worldDistance = self:getWorldDistance(origin, unitDirection, data.RANGE_STUDS)
	local hitId, hitDistance = WeaponRules.findClosestHit(origin, unitDirection, worldDistance, DamageableManager:getHitBoxes())
	local endDistance = hitDistance or worldDistance
	if hitId then
		DamageableManager:damage(hitId, data.DAMAGE, player)
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_WEAPON_FIRED, {
		userId = player.UserId,
		weaponKind = state.weaponKind,
		origin = origin,
		endPosition = origin + unitDirection * endDistance,
		-- false when the shot ran out its range in open air: no dust puff
		isImpact = hitId ~= nil or worldDistance < data.RANGE_STUDS,
		hitId = hitId or NO_HIT_ID,
	})
	self:replicate(player)
	if state.ammo <= 0 then
		self:startReloadIfNeeded(player)
	end
end

function WeaponManager:getNetHandlers()
	return {
		[NetEventNames.TRY_FIRE_WEAPON] = {
			shape = TRY_FIRE_WEAPON_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:fire(player, payload.origin, payload.direction)
			end,
		},
		[NetEventNames.TRY_RELOAD_WEAPON] = {
			shape = TRY_RELOAD_WEAPON_SHAPE,
			handler = function(player: Player, _payload: { [string]: any })
				if ToolManager:getEquippedTool(player) == Enums.ToolKind.WEAPON then
					self:startReloadIfNeeded(player)
				end
			end,
		},
	}
end

-- ready-sequence entry: a fresh arrival is handed the loadout weapon with a
-- full magazine; a dev-tool reset does not replay this, like the tools
function WeaponManager:onPlayerReady(player: Player)
	if self.stateByPlayer[player] then
		self:replicate(player)
		return
	end
	local playerData = GameController:getPlayerData(player)
	local unlockName = if playerData then playerData:getLoadoutSlot(Enums.LoadoutSlot.WEAPON) else nil
	local weaponKind = WeaponRules.resolveLoadoutWeapon(unlockName, HandheldData.DEFAULT_WEAPON)
	local data = self:getWeaponData(weaponKind)
	if not data then
		warn(`WeaponManager: no GameData/Weapons/Handheld entry for weapon {weaponKind}; using the default`)
		weaponKind = HandheldData.DEFAULT_WEAPON
		data = self:getWeaponData(weaponKind)
	end
	if not data then
		warn("WeaponManager: the default weapon has no data; no weapon granted")
		return
	end
	self.stateByPlayer[player] = {
		weaponKind = weaponKind,
		ammo = data.MAGAZINE_SIZE,
		reloadEndTime = 0,
		lastFireTime = nil,
	}
	ToolManager:setWeaponKind(player, weaponKind)
	ToolManager:grantTool(player, Enums.ToolKind.WEAPON)
	self:replicate(player)
end

function WeaponManager:init()
	GameController:registerPlaceManager(self)
	-- not a teardown entry: a dev-tool reset must not strip the run's weapon
	Players.PlayerRemoving:Connect(
		function(player: Player)
			self.stateByPlayer[player] = nil
		end
	)
end

function WeaponManager.new(): WeaponManager
	local self = setmetatable({}, WeaponManager) :: WeaponManager
	self.stateByPlayer = {}
	return self
end

return WeaponManager.new()
