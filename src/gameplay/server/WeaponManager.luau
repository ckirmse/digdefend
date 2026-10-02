--!strict

-- Handheld weapons (GDD "Weapon (Default Tool)", S12), M24. Every player
-- starts the run with the weapon their lobby loadout names, or the default
-- Rifle; equipping it is Weapon Mode on the client. Ammo, the reload, the
-- fire cooldown, and the run's upgrades are run state held here in Lua and
-- published as private attributes. Every shot is a TryFireWeapon request
-- carrying only the ray the client aimed: the server checks the weapon is
-- equipped, loaded, off cooldown, and that the ray starts near the
-- shooter's head, then decides the hit itself, a workspace raycast for
-- what the world blocks and box maths (WeaponRules) against
-- DamageableManager's targets. The mine's rocks exist only on clients, so
-- a rock never blocks a shot here.
-- Upgrades (2026-10-01): Damage, Ammo, and Range, four each, bought with
-- Gold at the Weapons Table in the defense building. The table's prompt
-- is created here; the triggering player's own client opens the menu, and
-- a buy is a TryUpgradeWeapon request checked against the catalogue
-- (WeaponRules) and the Gold balance.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local HandheldData = require("@game/ServerScriptService/GameData/Weapons/Handheld")
local UpgradesData = require("@game/ServerScriptService/GameData/Weapons/Upgrades")
local GameController = require(script.Parent.Parent.Server.GameController)
local NetManager = require(script.Parent.Parent.Server.NetManager)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)
local DamageableManager = require(script.Parent.DamageableManager)
local MapManager = require(script.Parent.MapManager)
local RefineryManager = require(script.Parent.RefineryManager)
local ToolManager = require(script.Parent.ToolManager)

local WeaponManager = {}
WeaponManager.__index = WeaponManager

type WeaponState = {
	weaponKind: number,
	ammo: number,
	-- server time the running reload ends; 0 when none
	reloadEndTime: number,
	lastFireTime: number?,
	upgrades: WeaponRules.Upgrades,
}

export type WeaponManager = typeof(setmetatable(
	{} :: {
		catalog: WeaponRules.Catalog,
		stateByPlayer: { [Player]: WeaponState },
	},
	WeaponManager
))

local TRY_FIRE_WEAPON_SHAPE = {
	origin = "vector3",
	direction = "vector3",
}
local TRY_RELOAD_WEAPON_SHAPE = {}
local TRY_UPGRADE_WEAPON_SHAPE = {
	attribute = { type = "enum", name = "WeaponAttribute" },
}

-- sent as the hit id when a shot hits nothing damageable
local NO_HIT_ID = ""
local MIN_DIRECTION_MAGNITUDE = 0.001

local FEEDBACK_NOT_ENOUGH_GOLD = "Not enough Gold"
local FEEDBACK_MAXED = "Already maxed out"

function WeaponManager:getWeaponData(weaponKind: number): WeaponRules.WeaponData?
	return HandheldData.BY_KIND[weaponKind]
end

-- the weapon's numbers after this player's upgrades
function WeaponManager:getStats(player: Player): WeaponRules.Stats?
	local state = self.stateByPlayer[player]
	return if state then WeaponRules.statsFor(self.catalog, state.weaponKind, state.upgrades) else nil
end

function WeaponManager:replicate(player: Player)
	local state = self.stateByPlayer[player]
	local data = if state then self:getWeaponData(state.weaponKind) else nil
	local stats = self:getStats(player)
	if not state or not data or not stats then
		return
	end
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_AMMO, state.ammo)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_RELOAD_END_TIME, state.reloadEndTime)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_MAGAZINE_SIZE, stats.magazineSize)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_FIRE_INTERVAL_SEC, data.FIRE_INTERVAL_SEC)
	SplendidReplicationManager:setCurrentPlayerAttribute(player, Attributes.WEAPON_RANGE_STUDS, stats.rangeStuds)
	for attribute, attributeName in WeaponRules.UPGRADE_ATTRIBUTE_BY_WEAPON_ATTRIBUTE do
		SplendidReplicationManager:setCurrentPlayerAttribute(player, attributeName, WeaponRules.upgradeLevel(state.upgrades, attribute))
	end
end

-- a reload runs whether or not the weapon stays in the hand, so swapping
-- tools never cancels or skips it
function WeaponManager:startReloadIfNeeded(player: Player)
	local state = self.stateByPlayer[player]
	local data = if state then self:getWeaponData(state.weaponKind) else nil
	local stats = self:getStats(player)
	if not state or not data or not stats then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not WeaponRules.canReload(state.ammo, stats.magazineSize, state.reloadEndTime, now) then
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
			-- the magazine as it is when the reload lands, so an Ammo
			-- upgrade bought mid-reload fills the bigger one
			local latest = self:getStats(player)
			state.ammo = if latest then latest.magazineSize else data.MAGAZINE_SIZE
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
-- the bullet either. A bullet (isBullet) also flies through the walls,
-- the posts, the gate, and the mounted guns, so a post covers every wall
-- of a curved line; a rocket does not
function WeaponManager:getWorldDistance(origin: Vector3, unitDirection: Vector3, rangeStuds: number, isBullet: boolean): number
	local excluded: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(excluded, other.Character)
		end
	end
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if isBullet and camp then
		for _, childName in Constants.BULLET_PASS_THROUGH_CAMP_CHILDREN do
			local child = camp:FindFirstChild(childName)
			if child then
				table.insert(excluded, child)
			end
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
	local stats = self:getStats(player)
	if not state or not data or not stats or ToolManager:getEquippedTool(player) ~= Enums.ToolKind.WEAPON then
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

	local worldDistance = self:getWorldDistance(origin, unitDirection, stats.rangeStuds, true)
	local hitId, hitDistance = WeaponRules.findClosestHit(origin, unitDirection, worldDistance, DamageableManager:getHitBoxes())
	local endDistance = hitDistance or worldDistance
	if hitId then
		DamageableManager:damage(hitId, stats.damage, player)
	end
	NetManager:notifyAllClients(NetEventNames.NOTIFY_WEAPON_FIRED, {
		userId = player.UserId,
		weaponKind = state.weaponKind,
		origin = origin,
		endPosition = origin + unitDirection * endDistance,
		-- false when the shot ran out its range in open air: no dust puff
		isImpact = hitId ~= nil or worldDistance < stats.rangeStuds,
		hitId = hitId or NO_HIT_ID,
	})
	self:replicate(player)
	if state.ammo <= 0 then
		self:startReloadIfNeeded(player)
	end
end

-- one upgrade of one attribute, paid in Gold; the client refused what it
-- could see was refused, and this checks again
function WeaponManager:upgrade(player: Player, attribute: number)
	local state = self.stateByPlayer[player]
	if not state or not GameController:isPlayerReady(player) then
		return
	end
	local offer = WeaponRules.getUpgradeOffer(self.catalog, state.upgrades, attribute)
	if offer.status == Enums.StoreOffer.MAXED or not offer.level or not offer.price then
		PlayerFeedbackManager:give(player, FEEDBACK_MAXED)
		return
	end
	local price = offer.price
	if not WeaponRules.canAfford(RefineryManager:getGoldBars(player), price) then
		PlayerFeedbackManager:give(player, FEEDBACK_NOT_ENOUGH_GOLD)
		return
	end
	if not RefineryManager:spendGoldBars(player, price) then
		return
	end
	state.upgrades[attribute] = offer.level
	self:replicate(player)
	NetManager:notifyClient(player, NetEventNames.NOTIFY_WEAPON_UPGRADED, {
		attribute = attribute,
		level = offer.level,
		price = price,
	})
	print(`[WeaponManager] {player.Name} upgraded weapon {Enums.getPublicName(Enums.WeaponAttribute, attribute)} to {offer.level} for {price} Gold`)
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
		[NetEventNames.TRY_UPGRADE_WEAPON] = {
			shape = TRY_UPGRADE_WEAPON_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:upgrade(player, payload.attribute)
			end,
		},
	}
end

-- the Weapons Table in the defense building: its prompt is created and
-- tagged here, and acted on only by the triggering player's own client,
-- which opens the menu
function WeaponManager:bindUpgradeTable()
	local promptPart = MapManager:findDefenseTablePart(Constants.WEAPON_UPGRADE_TABLE_MODEL, Constants.DEFENSE_TABLE_PROMPT_PART)
	if not promptPart then
		warn(`WeaponManager: the loaded camp has no {Constants.WEAPON_UPGRADE_TABLE_MODEL}.{Constants.DEFENSE_TABLE_PROMPT_PART} in its {Constants.CAMP_DEFENSE_STORE_MODEL}; weapons cannot be upgraded`)
		return
	end
	local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = promptPart
	end
	local livePrompt = prompt :: ProximityPrompt
	livePrompt.ActionText = UpgradesData.TABLE_PROMPT_ACTION_TEXT
	livePrompt.ObjectText = UpgradesData.TABLE_PROMPT_OBJECT_TEXT
	livePrompt.HoldDuration = 0
	livePrompt.MaxActivationDistance = UpgradesData.TABLE_PROMPT_MAX_DISTANCE_STUDS
	livePrompt.RequiresLineOfSight = false
	-- a clickable prompt frees the mouse when hovered, which sticks the cursor in first person (2026-09-29)
	livePrompt.ClickablePrompt = false
	livePrompt.Enabled = true
	CollectionService:AddTag(livePrompt, Tags.WEAPON_UPGRADE_PROMPT)
end

-- a run (or a dev-tool restart) has a fresh camp with a fresh table; the
-- run's upgrades start over with it
function WeaponManager:onRunStarted()
	for player, state in self.stateByPlayer do
		state.upgrades = {}
		if player.Parent then
			self:replicate(player)
		end
	end
	self:bindUpgradeTable()
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
		upgrades = {},
	}
	ToolManager:setWeaponKind(player, weaponKind)
	ToolManager:grantTool(player, Enums.ToolKind.WEAPON)
	self:replicate(player)
end

function WeaponManager:init()
	local kinds: { [number]: WeaponRules.WeaponData } = {}
	for kind, data in HandheldData.BY_KIND do
		kinds[kind] = data
	end
	self.catalog = {
		upgradePriceByLevel = UpgradesData.UPGRADE_PRICE_BY_LEVEL,
		bonusPerLevelByAttribute = UpgradesData.BONUS_PER_LEVEL_BY_ATTRIBUTE,
		kinds = kinds,
	}
	SplendidReplicationManager:setGameMetadata(Attributes.WEAPON_CATALOG, WeaponRules.encodeCatalog(self.catalog))
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
	self.catalog = {
		upgradePriceByLevel = {},
		bonusPerLevelByAttribute = {},
		kinds = {},
	}
	self.stateByPlayer = {}
	return self
end

return WeaponManager.new()
