--!strict

-- Weapon Mode on this client (GDD "Weapon (Default Tool)"), M24. Equipping
-- the weapon shows the reticle and the ammo readout; a press fires once and
-- holding repeats on the weapon's interval (ClientHoldInput, the same input
-- on every device as the pick axe and the Hammer, the touch action button
-- included). A shot is a request: TryFireWeapon carries only the camera ray,
-- and the server decides what it hit. The gun on screen is the viewmodel
-- (ClientViewModelManager), locked to the camera so it follows the reticle;
-- this manager shows it, kicks it on a shot, and lowers it for a reload.
-- What is drawn here at once (tracer, the 3D shot sound, a predicted round
-- off the counter) is cosmetic; the truth comes back as the WeaponAmmo /
-- WeaponReloadEndTime attributes and as NotifyWeaponFired, which also draws
-- every other player's shots and confirms this player's hits. R, gamepad X,
-- or a tap on the ammo readout reloads; an empty magazine reloads by itself.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientHoldInput = require(script.Parent.ClientHoldInput)
local ClientImpactManager = require(script.Parent.ClientImpactManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientViewModelManager = require(script.Parent.ClientViewModelManager)

local ClientWeaponManager = {}
ClientWeaponManager.__index = ClientWeaponManager

export type ClientWeaponManager = typeof(setmetatable(
	{} :: {
		isWeaponMode: boolean,
		holdInput: ClientHoldInput.ClientHoldInput?,
		ammoButton: GuiButton?,
		ammoLabel: TextLabel?,
		-- rounds left as this client expects them: the server's count, less
		-- shots sent since it last arrived, so a hold never outruns the magazine
		predictedAmmo: number,
		magazineSize: number,
		fireIntervalSec: number,
		rangeStuds: number,
		reloadEndTime: number,
		reloadRenderToken: number,
		-- the latest pulse of each muzzle light and emitter, so an earlier
		-- shot's timer never switches off a later shot's flash
		pulseTokenByInstance: { [Instance]: number },
		isOverlayActive: boolean,
	},
	ClientWeaponManager
))

local RETICLE_BORROWER = "WeaponMode"
local DEFAULT_FIRE_INTERVAL_SEC = 0.2
local DEFAULT_RANGE_STUDS = 300
local AMMO_FORMAT = "%d / %d"
local RELOADING_TEXT = "Reloading"
-- the tracer is a short streak that flies to the hit point, not a beam left
-- hanging in the world: a beam stayed put while the shooter strafed away
-- from it (2026-09-17)
local TRACER_THICKNESS_STUDS = 0.08
local TRACER_LENGTH_STUDS = 10
local TRACER_SPEED_STUDS_PER_SEC = 900
local TRACER_COLOR = Color3.fromRGB(255, 230, 140)
-- a tracer starts this far ahead of the camera when no held weapon is found
local FALLBACK_MUZZLE_OFFSET_STUDS = 2
-- other players' shots are drawn and heard only this close
local EFFECT_RANGE_STUDS = 400
-- a shot is at full volume within this distance, the shooter's own and a
-- crewmate's alongside; past it, it fades out to nothing at
-- EFFECT_RANGE_STUDS, still clearly heard across the camp
local FIRE_SOUND_FULL_VOLUME_STUDS = 30
-- another player's shot is cast again locally this far past where the
-- server said it ended, so a surface exactly at the end point is still found
local REPLAYED_SHOT_OVERSHOOT_STUDS = 1
-- how long a shot keeps the template's muzzle light and smoke switched on
local MUZZLE_FLASH_SEC = 0.125
local MUZZLE_SMOKE_SEC = 0.1

local NOTIFY_WEAPON_FIRED_SHAPE = {
	userId = "positiveInteger",
	weaponKind = "positiveInteger",
	origin = "vector3",
	endPosition = "vector3",
	isImpact = "boolean",
	hitId = "string",
}

function ClientWeaponManager:getIsWeaponMode(): boolean
	return self.isWeaponMode
end

-- a weapon's own four sounds; nil (and silence) for a kind with no set
function ClientWeaponManager:getWeaponSfx(weaponKind: any): SoundNames.WeaponSfx?
	local kindName = if typeof(weaponKind) == "number" and Enums.isValidValue(Enums.WeaponKind, weaponKind) then Enums.getName(Enums.WeaponKind, weaponKind) else nil
	return if kindName then SoundNames.WeaponSfxByKindName[kindName] else nil
end

-- the sounds of the weapon this player carries
function ClientWeaponManager:getOwnWeaponSfx(): SoundNames.WeaponSfx?
	return self:getWeaponSfx(ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_KIND))
end

function ClientWeaponManager:getIsReloading(): boolean
	return WeaponRules.isReloading(self.reloadEndTime, workspace:GetServerTimeNow())
end

-- the weapon's Muzzle attachment on a character's held Tool
function ClientWeaponManager:findHeldMuzzle(character: Model?): Attachment?
	local tool = if character then character:FindFirstChildOfClass("Tool") else nil
	local muzzle = if tool then tool:FindFirstChild(Constants.WEAPON_MUZZLE_ATTACHMENT, true) else nil
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

-- switches a light or an emitter on for a moment
function ClientWeaponManager:pulse(instance: PointLight | ParticleEmitter, seconds: number)
	local token = (self.pulseTokenByInstance[instance] or 0) + 1
	self.pulseTokenByInstance[instance] = token
	instance.Enabled = true
	task.delay(
		seconds,
		function()
			if self.pulseTokenByInstance[instance] ~= token then
				return
			end
			self.pulseTokenByInstance[instance] = nil
			instance.Enabled = false
		end
	)
end

-- the flash and the wisp of smoke authored under a Muzzle attachment; a
-- template without them simply shows neither
function ClientWeaponManager:playMuzzleEffects(muzzle: Attachment?)
	if not muzzle then
		return
	end
	local flash = muzzle:FindFirstChild(Constants.WEAPON_MUZZLE_FLASH_LIGHT)
	if flash and flash:IsA("PointLight") then
		self:pulse(flash, MUZZLE_FLASH_SEC)
	end
	local smoke = muzzle:FindFirstChild(Constants.WEAPON_MUZZLE_SMOKE_EMITTER)
	if smoke and smoke:IsA("ParticleEmitter") then
		self:pulse(smoke, MUZZLE_SMOKE_SEC)
	end
end

-- returns how long the streak takes to arrive, so the impact can wait for it
function ClientWeaponManager:drawTracer(from: Vector3, to: Vector3): number
	local length = (to - from).Magnitude
	if length < 0.5 then
		return 0
	end
	local streakLength = math.min(TRACER_LENGTH_STUDS, length)
	local travelStuds = length - streakLength
	local travelSec = travelStuds / TRACER_SPEED_STUDS_PER_SEC
	local aim = CFrame.lookAt(from, to)
	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = TRACER_COLOR
	tracer.Size = Vector3.new(TRACER_THICKNESS_STUDS, TRACER_THICKNESS_STUDS, streakLength)
	tracer.CFrame = aim * CFrame.new(0, 0, -streakLength / 2)
	tracer.Parent = workspace
	-- a point-blank shot has nowhere to fly: the streak just shows for a frame or two
	local lifeSec = math.max(travelSec, 0.03)
	TweenService:Create(tracer, TweenInfo.new(lifeSec, Enum.EasingStyle.Linear), { CFrame = aim * CFrame.new(0, 0, -(travelStuds + streakLength / 2)) }):Play()
	Debris:AddItem(tracer, lifeSec)
	return travelSec
end

-- impactNormal is nil when the shot hit nothing (open air at full range);
-- impactSurface is what it hit, when this client's own raycast found it
function ClientWeaponManager:playFireEffects(weaponKind: number, from: Vector3, to: Vector3, impactNormal: Vector3?, impactSurface: Instance?)
	local travelSec = self:drawTracer(from, to)
	local weaponSfx = self:getWeaponSfx(weaponKind)
	if weaponSfx then
		ClientSoundManager:playSfxAt(from, weaponSfx.FIRE, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
	end
	if impactNormal then
		task.delay(
			travelSec,
			function()
				ClientImpactManager:play(to, impactNormal, impactSurface)
			end
		)
	end
end

-- where this client's own world stops the ray: it has the mine's rocks,
-- which the server does not, so the tracer ends where the player sees it end
function ClientWeaponManager:findLocalEnd(origin: Vector3, unitDirection: Vector3, rangeStuds: number): (Vector3, Vector3?, Instance?)
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
	if result then
		return result.Position, result.Normal, result.Instance
	end
	return origin + unitDirection * rangeStuds, nil, nil
end

function ClientWeaponManager:requestReload()
	if not self.isWeaponMode or self:getIsReloading() or self.predictedAmmo >= self.magazineSize then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_RELOAD_WEAPON, {})
end

-- one shot: a request, never a result. False (reloading, empty) leaves the
-- hold free to try again the moment the magazine is back
function ClientWeaponManager:fire(isFreshPress: boolean): boolean
	local camera = workspace.CurrentCamera
	if not camera or self:getIsReloading() then
		return false
	end
	if self.predictedAmmo <= 0 then
		-- said once per press, not once per interval of a hold
		if isFreshPress then
			local weaponSfx = self:getOwnWeaponSfx()
			if weaponSfx then
				ClientSoundManager:playSfx(weaponSfx.EMPTY)
			end
			ClientNetManager:fireServer(NetEventNames.TRY_RELOAD_WEAPON, {})
		end
		return false
	end
	local origin = camera.CFrame.Position
	local unitDirection = camera.CFrame.LookVector
	self.predictedAmmo -= 1
	self:renderAmmo()
	ClientNetManager:fireServer(
		NetEventNames.TRY_FIRE_WEAPON,
		{
			origin = origin,
			direction = unitDirection,
		}
	)
	local weaponKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_KIND)
	-- in first person the gun on screen is the viewmodel, so its muzzle;
	-- the held Tool is hidden on this client
	local muzzleAttachment = ClientViewModelManager:getMuzzle() or self:findHeldMuzzle(Players.LocalPlayer.Character)
	local muzzle = if muzzleAttachment then muzzleAttachment.WorldPosition else origin + unitDirection * FALLBACK_MUZZLE_OFFSET_STUDS
	self:playMuzzleEffects(muzzleAttachment)
	ClientViewModelManager:kick()
	local endPosition, impactNormal, impactSurface = self:findLocalEnd(origin, unitDirection, self.rangeStuds)
	self:playFireEffects(if typeof(weaponKind) == "number" then weaponKind else Enums.WeaponKind.RIFLE, muzzle, endPosition, impactNormal, impactSurface)
	return true
end

function ClientWeaponManager:beginHold()
	if self.holdInput then
		self.holdInput:beginHold()
	end
end

function ClientWeaponManager:endHold()
	if self.holdInput then
		self.holdInput:endHold()
	end
end

function ClientWeaponManager:onWeaponFired(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_WEAPON_FIRED_SHAPE)
	if not isValid then
		warn("ClientWeaponManager: malformed NotifyWeaponFired")
		return
	end
	if payload.hitId ~= "" then
		ClientDamageableManager:flashHit(payload.hitId)
	end
	if payload.userId == Players.LocalPlayer.UserId then
		-- this client drew its own shot when it fired; the news is the hit
		local weaponSfx = self:getWeaponSfx(payload.weaponKind)
		if payload.hitId ~= "" and weaponSfx then
			ClientSoundManager:playSfx(weaponSfx.HIT)
		end
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - payload.origin).Magnitude > EFFECT_RANGE_STUDS then
		return
	end
	local shooter = Players:GetPlayerByUserId(payload.userId)
	local muzzleAttachment = self:findHeldMuzzle(if shooter then shooter.Character else nil)
	local muzzle = if muzzleAttachment then muzzleAttachment.WorldPosition else payload.origin
	self:playMuzzleEffects(muzzleAttachment)
	-- the server sends no surface, so the same line is cast again here to
	-- find what the shot landed on and which way it faces. When this
	-- client's world has nothing there, the puff faces back along the shot
	-- and there is no hole
	local shotVector = payload.endPosition - payload.origin
	local endPosition: Vector3 = payload.endPosition
	local impactNormal: Vector3? = nil
	local impactSurface: Instance? = nil
	if payload.isImpact and shotVector.Magnitude > 0.01 then
		local localPosition, localNormal, localSurface = self:findLocalEnd(payload.origin, shotVector.Unit, shotVector.Magnitude + REPLAYED_SHOT_OVERSHOOT_STUDS)
		if localNormal then
			endPosition = localPosition
		end
		impactNormal = localNormal or -shotVector.Unit
		impactSurface = localSurface
	end
	self:playFireEffects(payload.weaponKind, muzzle, endPosition, impactNormal, impactSurface)
end

function ClientWeaponManager:renderAmmo()
	local button = self.ammoButton
	local label = self.ammoLabel
	if not button or not label then
		return
	end
	button.Visible = self.isWeaponMode and not self.isOverlayActive
	ClientViewModelManager:setLowered(self:getIsReloading())
	if self:getIsReloading() then
		label.Text = UiStyle.formatTitle(RELOADING_TEXT)
	else
		label.Text = string.format(AMMO_FORMAT, math.max(0, self.predictedAmmo), self.magazineSize)
	end
end

function ClientWeaponManager:notifyBeginOverlay()
	self.isOverlayActive = true
	self:renderAmmo()
end

function ClientWeaponManager:notifyEndOverlay()
	self.isOverlayActive = false
	self:renderAmmo()
end

function ClientWeaponManager:onReloadEndTimeChanged(value: any)
	local reloadEndTime = if typeof(value) == "number" then value else 0
	local wasReloading = self:getIsReloading()
	self.reloadEndTime = reloadEndTime
	self.reloadRenderToken += 1
	if self:getIsReloading() then
		local weaponSfx = self:getOwnWeaponSfx()
		if not wasReloading and self.isWeaponMode and weaponSfx then
			ClientSoundManager:playSfx(weaponSfx.RELOAD)
		end
		-- the label reads Reloading until the clock passes the end time, even
		-- if the ammo attribute lands a moment late
		local token = self.reloadRenderToken
		task.delay(
			math.max(0, reloadEndTime - workspace:GetServerTimeNow()),
			function()
				if token == self.reloadRenderToken then
					self:renderAmmo()
				end
			end
		)
	end
	self:renderAmmo()
end

function ClientWeaponManager:readTuning()
	local function read(key: string, default: number): number
		local value = ClientDataManager:getCurrentPlayerAttribute(key)
		return if typeof(value) == "number" then value else default
	end
	self.magazineSize = read(Attributes.WEAPON_MAGAZINE_SIZE, 0)
	self.fireIntervalSec = read(Attributes.WEAPON_FIRE_INTERVAL_SEC, DEFAULT_FIRE_INTERVAL_SEC)
	self.rangeStuds = read(Attributes.WEAPON_RANGE_STUDS, DEFAULT_RANGE_STUDS)
	self:renderAmmo()
end

function ClientWeaponManager:renderViewModel()
	local weaponKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_KIND)
	if self.isWeaponMode and typeof(weaponKind) == "number" and Enums.isValidValue(Enums.WeaponKind, weaponKind) then
		ClientViewModelManager:show(WeaponRules.templateNameFor(weaponKind))
	else
		ClientViewModelManager:hide()
	end
end

function ClientWeaponManager:setWeaponMode(isWeaponMode: boolean)
	if self.isWeaponMode == isWeaponMode then
		return
	end
	self.isWeaponMode = isWeaponMode
	ClientMiningManager:setReticleBorrowed(RETICLE_BORROWER, isWeaponMode)
	if not isWeaponMode and self.holdInput then
		self.holdInput:cancel()
	end
	self:renderViewModel()
	self:renderAmmo()
end

function ClientWeaponManager:init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(Constants.WEAPON_HUD_GUI_NAME, 10)
	local button = if gui then gui:FindFirstChild(Constants.WEAPON_HUD_AMMO_BUTTON) else nil
	if button and button:IsA("GuiButton") then
		self.ammoButton = button
		local label = button:FindFirstChild(Constants.WEAPON_HUD_AMMO_LABEL)
		self.ammoLabel = if label and label:IsA("TextLabel") then label else nil
		button.Visible = false
		button.Activated:Connect(
			function()
				self:requestReload()
			end
		)
	else
		warn("ClientWeaponManager: no WeaponHud ScreenGui with an AmmoButton; run scripts/studio/build_weapon_hud_gui.luau")
	end

	self:readTuning()
	for _, key in { Attributes.WEAPON_MAGAZINE_SIZE, Attributes.WEAPON_FIRE_INTERVAL_SEC, Attributes.WEAPON_RANGE_STUDS } do
		ClientDataManager:subscribeCurrentPlayerAttribute(
			key,
			function()
				self:readTuning()
			end
		)
	end
	local function applyAmmo(value: any)
		self.predictedAmmo = if typeof(value) == "number" then value else 0
		self:renderAmmo()
	end
	applyAmmo(ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_AMMO))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.WEAPON_AMMO, applyAmmo)
	self:onReloadEndTimeChanged(ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_RELOAD_END_TIME))
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.WEAPON_RELOAD_END_TIME,
		function(value: any)
			self:onReloadEndTimeChanged(value)
		end
	)

	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.WEAPON_KIND,
		function()
			self:renderViewModel()
		end
	)

	local holdInput = ClientHoldInput.new({
		isEnabled = function(): boolean
			return self.isWeaponMode
		end,
		getIntervalSec = function(): number
			return self.fireIntervalSec
		end,
		swing = function(isFreshPress: boolean): boolean
			return self:fire(isFreshPress)
		end,
	})
	holdInput:connect()
	self.holdInput = holdInput

	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			if isGameProcessed or ClientOverlayManager:isOverlayActive() then
				return
			end
			if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonX then
				self:requestReload()
			end
		end
	)

	ClientNetManager:registerHandler(
		NetEventNames.NOTIFY_WEAPON_FIRED,
		function(payload: any)
			self:onWeaponFired(payload)
		end
	)
	ClientOverlayManager:addOverlayNotifier(self)

	local function applyEquipped(value: any)
		self:setWeaponMode(value == Enums.ToolKind.WEAPON)
	end
	applyEquipped(ClientDataManager:getCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.EQUIPPED_TOOL, applyEquipped)
end

function ClientWeaponManager.new(): ClientWeaponManager
	local self = setmetatable({}, ClientWeaponManager) :: ClientWeaponManager
	self.isWeaponMode = false
	self.holdInput = nil
	self.ammoButton = nil
	self.ammoLabel = nil
	self.predictedAmmo = 0
	self.magazineSize = 0
	self.fireIntervalSec = DEFAULT_FIRE_INTERVAL_SEC
	self.rangeStuds = DEFAULT_RANGE_STUDS
	self.reloadEndTime = 0
	self.reloadRenderToken = 0
	self.pulseTokenByInstance = {}
	self.isOverlayActive = false
	return self
end

return ClientWeaponManager.new()
