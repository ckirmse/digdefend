--!strict

-- Weapon Mode on this client (GDD "Weapon (Default Tool)"), M24. Equipping
-- the weapon shows the reticle and the ammo readout; a press fires once and
-- holding repeats on the weapon's interval (ClientHoldInput, the same input
-- on every device as the pick axe and the Hammer, the touch action button
-- included). A shot is a request: TryFireWeapon carries only the aim ray
-- (the camera's look in first person; in third person a ray from the head
-- toward whatever the mouse or the tapped finger is over, ClientCameraView,
-- 2026-10-07, when a quick tap also fires once), and the server decides what
-- it hit. The gun on screen is the viewmodel
-- (ClientViewModelManager), locked to the camera so it follows the reticle;
-- this manager shows it, kicks it on a shot, and lowers it for a reload.
-- What is drawn here at once (tracer, the 3D shot sound, a predicted round
-- off the counter) is cosmetic; the truth comes back as the WeaponAmmo /
-- WeaponReloadEndTime attributes and as NotifyWeaponFired, which also draws
-- every other player's shots and confirms this player's hits. R, gamepad X,
-- or a tap on the ammo readout reloads; an empty magazine reloads by itself.
-- The class weapons (2026-10-16) read their blocks from the catalogue the
-- server publishes: a CONE kind (the Flamethrower) draws no tracer and
-- pulses the flame emitter under its Muzzle every tick, a SCOPE kind (the
-- Sniper Rifle) zooms the camera while the aim button is held, and a
-- SECONDARY kind (the Assault Rifle's grenade) lobs on the aim button's
-- press, on its own cooldown, flown by ClientProjectileManager.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local PostRules = require("@game/ReplicatedStorage/Shared/PostRules")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Icons = require("@game/ReplicatedStorage/Shared/Icons")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local WeaponRules = require("@game/ReplicatedStorage/Shared/WeaponRules")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local ClientOverlayManager = require(script.Parent.Parent.Client.ClientOverlayManager)
local ClientSoundManager = require(script.Parent.Parent.Client.ClientSoundManager)
local ClientCameraView = require(script.Parent.ClientCameraView)
local ClientDamageableManager = require(script.Parent.ClientDamageableManager)
local ClientHeadshotManager = require(script.Parent.ClientHeadshotManager)
local ClientHoldInput = require(script.Parent.ClientHoldInput)
local ClientImpactManager = require(script.Parent.ClientImpactManager)
local ClientMiningManager = require(script.Parent.ClientMiningManager)
local ClientScopeGlassManager = require(script.Parent.ClientScopeGlassManager)
local ClientViewModelManager = require(script.Parent.ClientViewModelManager)

local ClientWeaponManager = {}
ClientWeaponManager.__index = ClientWeaponManager

export type ClientWeaponManager = typeof(setmetatable(
	{} :: {
		isWeaponMode: boolean,
		holdInput: ClientHoldInput.ClientHoldInput?,
		ammoButton: GuiButton?,
		ammoLabel: TextLabel?,
		-- the secondary's cooldown bar above the ammo (2026-10-19)
		secondaryBar: GuiObject?,
		secondaryFill: GuiObject?,
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
		-- a stream weapon's roar per nozzle (2026-10-20): the looping fire
		-- sound attached to the muzzle's part, and when its last tick ends
		streamRoarByPart: { [BasePart]: { player: AudioPlayer, endTime: number } },
		isOverlayActive: boolean,
		catalog: WeaponRules.Catalog?,
		isScoped: boolean,
		savedFieldOfView: number?,
		-- the scope's look (2026-10-19): Roblox's camera turns the same
		-- angle per mouse pixel at any zoom, so after it has moved each
		-- frame the turn is scaled down by the zoom and re-applied from the
		-- look the player last saw; the module reads its heading back from
		-- the camera, so it carries on from the scaled look
		scopeLastLook: Vector3?,
		scopeTurnScale: number,
		-- the picture on the glass while scoped
		scopeImageId: string?,
		secondaryReadyTime: number,
	},
	ClientWeaponManager
))

local RETICLE_BORROWER = "WeaponMode"
-- the first-person view model is shared with the flare gun (ClientFlareManager)
local VIEW_MODEL_OWNER = "Weapon"
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
-- one frame's grace on the streak's life for the frame it holds at the muzzle
local TRACER_HOLD_SEC = 0.05
local TRACER_COLOR = UiStyle.TRACER_COLOR
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
	userId = "integer",
	weaponKind = "positiveInteger",
	origin = "vector3",
	endPosition = "vector3",
	isImpact = "boolean",
	hitId = "string",
	-- a cone's tick: every body it reached
	hitIds = { type = "array", elementType = "string", optional = true },
	-- the shot landed in the head zone (the shooter's callout)
	isHeadshot = "boolean",
}
-- how long a tick keeps the stream weapon's flame emitter on: a little
-- past the interval, so a held trigger reads as one continuous flame
local MUZZLE_FLAME_SEC = 0.15
-- how long a tick keeps the stream's roar going: a held trigger ticks
-- every 0.1 s, so the loop never gaps, and a release stops it soon after
local STREAM_ROAR_SEC = 0.25
local DEFAULT_FIELD_OF_VIEW = 70
-- the scope look step (see stepScopeLook) and how far it may pitch
local SCOPE_LOOK_BINDING = "WeaponScopeLook"
local SCOPE_PITCH_LIMIT = math.rad(80)

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

-- the catalogue entry of a weapon kind, for its class blocks
function ClientWeaponManager:getKindData(weaponKind: any): WeaponRules.WeaponData?
	local catalog = self.catalog
	return if catalog and typeof(weaponKind) == "number" then catalog.kinds[weaponKind] else nil
end

function ClientWeaponManager:getOwnKindData(): WeaponRules.WeaponData?
	return self:getKindData(ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_KIND))
end

-- the flame authored (or built) under a Muzzle attachment, pulsed per tick
function ClientWeaponManager:playFlameEffects(muzzle: Attachment?)
	if not muzzle then
		return
	end
	local flame = muzzle:FindFirstChild(Constants.WEAPON_MUZZLE_FLAME_EMITTER)
	if flame and flame:IsA("ParticleEmitter") then
		self:pulse(flame, MUZZLE_FLAME_SEC)
	end
	local light = muzzle:FindFirstChild(Constants.WEAPON_MUZZLE_FLASH_LIGHT)
	if light and light:IsA("PointLight") then
		self:pulse(light, MUZZLE_FLAME_SEC)
	end
end

-- a stream weapon's roar: the kind's FIRE sound is a loop (the
-- Flamethrower, 2026-10-20), started at the nozzle on the first tick and
-- kept alive by every tick after; stepStreamRoars stops one whose ticks
-- stopped, and this player's own stops the moment the trigger is released
function ClientWeaponManager:playStreamRoar(muzzle: Attachment?, name: string)
	local part = if muzzle then muzzle.Parent else nil
	if not part or not part:IsA("BasePart") then
		return
	end
	local now = workspace:GetServerTimeNow()
	local roar = self.streamRoarByPart[part]
	if roar then
		roar.endTime = now + STREAM_ROAR_SEC
		return
	end
	local player = ClientSoundManager:attachLoop(part, name, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
	if not player then
		return
	end
	self.streamRoarByPart[part] = {
		player = player,
		endTime = now + STREAM_ROAR_SEC,
	}
end

function ClientWeaponManager:stopStreamRoar(part: BasePart)
	local roar = self.streamRoarByPart[part]
	if not roar then
		return
	end
	self.streamRoarByPart[part] = nil
	roar.player:Stop()
	roar.player:Destroy()
	for _, child in part:GetChildren() do
		if child:IsA("AudioEmitter") then
			child:Destroy()
		end
	end
end

function ClientWeaponManager:stepStreamRoars()
	local now = workspace:GetServerTimeNow()
	for part, roar in self.streamRoarByPart do
		if now >= roar.endTime or part.Parent == nil then
			self:stopStreamRoar(part)
		end
	end
end

-- the scope (the Sniper Rifle): the camera zooms to the kind's field of
-- view while the aim button is held and the gun leaves the screen
function ClientWeaponManager:setScoped(isScoped: boolean)
	local kindData = self:getOwnKindData()
	local scope = if kindData then kindData.SCOPE else nil
	if isScoped == self.isScoped then
		return
	end
	if isScoped and (not self.isWeaponMode or not scope or self:isManningPost()) then
		return
	end
	if isScoped and scope then
		local weaponKind = ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_KIND)
		local imageId = if typeof(weaponKind) == "number" then Icons.WEAPON_SCOPE[weaponKind] else nil
		self:enterScope(scope.FIELD_OF_VIEW, if typeof(imageId) == "string" then imageId else nil)
	else
		self:exitScope()
	end
end

function ClientWeaponManager:enterScope(fieldOfView: number, imageId: string?)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	self.isScoped = true
	self.scopeImageId = imageId
	self.savedFieldOfView = camera.FieldOfView
	camera.FieldOfView = fieldOfView
	-- a hand movement covers the same screen distance scoped as
	-- unscoped: the turn is scaled by the zoom (see stepScopeLook)
	self.scopeTurnScale = fieldOfView / math.max(self.savedFieldOfView, 1)
	self.scopeLastLook = camera.CFrame.LookVector
	RunService:BindToRenderStep(SCOPE_LOOK_BINDING, Enum.RenderPriority.Camera.Value + 1,
		function()
			self:stepScopeLook()
		end
	)
	ClientViewModelManager:hide()
	self:renderScopeGlass()
end

function ClientWeaponManager:exitScope()
	if not self.isScoped then
		return
	end
	self.isScoped = false
	self.scopeImageId = nil
	RunService:UnbindFromRenderStep(SCOPE_LOOK_BINDING)
	self.scopeLastLook = nil
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = self.savedFieldOfView or DEFAULT_FIELD_OF_VIEW
	end
	self.savedFieldOfView = nil
	self:renderViewModel()
	self:renderScopeGlass()
end

-- right after Roblox's camera has turned for the frame: the yaw and pitch
-- it added since the look the player last saw are scaled down by the zoom
-- and applied from that look instead, so a mouse pixel moves the reticle
-- the same distance across the glass as it moves the crosshair unscoped
function ClientWeaponManager:stepScopeLook()
	local camera = workspace.CurrentCamera
	local lastLook = self.scopeLastLook
	if not camera or not lastLook then
		return
	end
	local look = camera.CFrame.LookVector
	local lastYaw = math.atan2(-lastLook.X, -lastLook.Z)
	local lastPitch = math.asin(math.clamp(lastLook.Y, -1, 1))
	local yaw = math.atan2(-look.X, -look.Z)
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	local yawDelta = (yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi
	local pitchDelta = pitch - lastPitch
	local newYaw = lastYaw + yawDelta * self.scopeTurnScale
	local newPitch = math.clamp(lastPitch + pitchDelta * self.scopeTurnScale, -SCOPE_PITCH_LIMIT, SCOPE_PITCH_LIMIT)
	local newLook = Vector3.new(-math.sin(newYaw) * math.cos(newPitch), math.sin(newPitch), -math.cos(newYaw) * math.cos(newPitch))
	local position = camera.CFrame.Position
	camera.CFrame = CFrame.lookAt(position, position + newLook)
	self.scopeLastLook = newLook
end

-- the scope glass: the kind's reticle picture with black all round it,
-- shown only while scoped (decided 2026-10-19)
function ClientWeaponManager:renderScopeGlass()
	if not self.isScoped then
		ClientScopeGlassManager:hide()
		return
	end
	ClientScopeGlassManager:show(self.scopeImageId)
end

-- the second trigger (the Assault Rifle's grenade): a request on the aim
-- button, refused here while the cooldown runs so the hand never asks
function ClientWeaponManager:fireSecondary()
	local kindData = self:getOwnKindData()
	local secondary = if kindData then kindData.SECONDARY else nil
	local camera = workspace.CurrentCamera
	if not secondary or not camera or not self.isWeaponMode or self:isManningPost() or self:getIsReloading() then
		return
	end
	local now = workspace:GetServerTimeNow()
	if self.secondaryReadyTime > now then
		local weaponSfx = self:getOwnWeaponSfx()
		if weaponSfx then
			ClientSoundManager:playSfx(weaponSfx.EMPTY)
		end
		return
	end
	-- the grenade leaves the launcher under the barrel (the template's
	-- Grenade attachment, 2026-10-19), toward where the camera looks; the
	-- server allows the launcher's distance from the head
	local secondaryMuzzle = ClientViewModelManager:getSecondaryMuzzle() or self:findHeldAttachment(Players.LocalPlayer.Character, Constants.WEAPON_SECONDARY_ATTACHMENT)
	local origin = if secondaryMuzzle then secondaryMuzzle.WorldPosition else camera.CFrame.Position
	local unitDirection = camera.CFrame.LookVector
	ClientNetManager:fireServer(
		NetEventNames.TRY_FIRE_WEAPON_SECONDARY,
		{
			origin = origin,
			direction = unitDirection,
		}
	)
	-- the cooldown is expected until the server's own lands
	self.secondaryReadyTime = now + secondary.COOLDOWN_SEC
	local muzzleAttachment = ClientViewModelManager:getMuzzle() or self:findHeldMuzzle(Players.LocalPlayer.Character)
	self:playMuzzleEffects(secondaryMuzzle or muzzleAttachment)
	ClientViewModelManager:kick()
	local weaponSfx = self:getOwnWeaponSfx()
	local launchSound = if weaponSfx then weaponSfx.SECONDARY_FIRE else nil
	if launchSound then
		ClientSoundManager:playSfxAt(origin, launchSound, FIRE_SOUND_FULL_VOLUME_STUDS, EFFECT_RANGE_STUDS)
	end
end

-- the aim button: the scope while held on a scope kind, the grenade on
-- its press on a secondary kind
function ClientWeaponManager:onAimButton(isDown: boolean)
	local kindData = self:getOwnKindData()
	if not kindData then
		return
	end
	if kindData.SCOPE then
		self:setScoped(isDown)
	elseif kindData.SECONDARY and isDown then
		self:fireSecondary()
	end
end

-- the weapon's Muzzle attachment on a character's held Tool
function ClientWeaponManager:findHeldMuzzle(character: Model?): Attachment?
	return self:findHeldAttachment(character, Constants.WEAPON_MUZZLE_ATTACHMENT)
end

-- a named attachment on the Tool in a character's hand (another player's
-- shot, or this player's in third person)
function ClientWeaponManager:findHeldAttachment(character: Model?, attachmentName: string): Attachment?
	local tool = if character then character:FindFirstChildOfClass("Tool") else nil
	local muzzle = if tool then tool:FindFirstChild(attachmentName, true) else nil
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

-- returns how long the streak takes to arrive, so the impact can wait for
-- it; a caller with a kind of its own passes that kind's colour and speed
function ClientWeaponManager:drawTracer(from: Vector3, to: Vector3, color: Color3?, speedStudsPerSec: number?): number
	local length = (to - from).Magnitude
	if length < 0.5 then
		return 0
	end
	local streakLength = math.min(TRACER_LENGTH_STUDS, length)
	local travelStuds = length - streakLength
	local travelSec = travelStuds / (speedStudsPerSec or TRACER_SPEED_STUDS_PER_SEC)
	local aim = CFrame.lookAt(from, to)
	local tracer = Instance.new("Part")
	tracer.Name = "Tracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = color or TRACER_COLOR
	tracer.Size = Vector3.new(TRACER_THICKNESS_STUDS, TRACER_THICKNESS_STUDS, streakLength)
	tracer.CFrame = aim * CFrame.new(0, 0, -streakLength / 2)
	tracer.Parent = workspace
	-- a point-blank shot has nowhere to fly: the streak just shows for a frame or two
	local lifeSec = math.max(travelSec, 0.03)
	local tween = TweenService:Create(tracer, TweenInfo.new(lifeSec, Enum.EasingStyle.Linear), { CFrame = aim * CFrame.new(0, 0, -(travelStuds + streakLength / 2)) })
	-- the streak is drawn once at the muzzle before it flies (2026-10-19):
	-- at 900 studs a second one frame is 15 studs, so a tween started this
	-- frame put the first frame anyone saw well down range, and the shot
	-- read as leaving a point ahead of the barrel
	task.spawn(
		function()
			RunService.RenderStepped:Wait()
			if tracer.Parent then
				tween:Play()
			end
		end
	)
	Debris:AddItem(tracer, lifeSec + TRACER_HOLD_SEC)
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
-- which the server does not, so the tracer ends where the player sees it
-- end. Like the server, a bullet flies through the fortifications and the
-- mounted guns (Constants.BULLET_PASS_THROUGH_CAMP_CHILDREN)
function ClientWeaponManager:findLocalEnd(origin: Vector3, unitDirection: Vector3, rangeStuds: number): (Vector3, Vector3?, Instance?)
	local excluded: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(excluded, other.Character)
		end
	end
	local camp = workspace:FindFirstChild(Constants.CAMP_FOLDER)
	if camp then
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
	if result then
		return result.Position, result.Normal, result.Instance
	end
	return origin + unitDirection * rangeStuds, nil, nil
end

-- the post gun has the hands while a post is manned; the server refuses
-- the rifle then too, this only spares the client its own effects
function ClientWeaponManager:isManningPost(): boolean
	local mannedIndex = ClientDataManager:getCurrentPlayerAttribute(Attributes.MANNED_POST_INDEX)
	return typeof(mannedIndex) == "number" and mannedIndex ~= PostRules.NO_POST
end

function ClientWeaponManager:requestReload()
	if not self.isWeaponMode or self:getIsReloading() or self.predictedAmmo >= self.magazineSize or self:isManningPost() then
		return
	end
	ClientNetManager:fireServer(NetEventNames.TRY_RELOAD_WEAPON, {})
end

-- one shot: a request, never a result. False (reloading, empty) leaves the
-- hold free to try again the moment the magazine is back
function ClientWeaponManager:fire(isFreshPress: boolean): boolean
	local camera = workspace.CurrentCamera
	if not camera or self:getIsReloading() or self:isManningPost() then
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
	if ClientCameraView:isThirdPerson() then
		-- the shot leaves the head (the server checks the origin sits near
		-- it) toward the point the pointer's ray reaches, so the bullet goes
		-- where the player clicked or tapped, not where the camera looks
		local character = Players.LocalPlayer.Character
		local head = if character then character:FindFirstChild("Head") else nil
		if head and head:IsA("BasePart") then
			local rayOrigin, rayDirection = ClientCameraView:getPointerRay(if self.holdInput then self.holdInput:getTouchPosition() else nil)
			local aimPoint = self:findLocalEnd(rayOrigin, rayDirection, self.rangeStuds + (head.Position - rayOrigin).Magnitude)
			origin = head.Position
			local toAimPoint = aimPoint - origin
			if toAimPoint.Magnitude > 0 then
				unitDirection = toAimPoint.Unit
			end
		end
	end
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
	local kindData = self:getKindData(weaponKind)
	if kindData and kindData.CONE then
		-- a stream: the flame at the nozzle and its roar, no tracer and no
		-- impact; what it burns flashes when the server says so
		self:playFlameEffects(muzzleAttachment)
		local weaponSfx = self:getWeaponSfx(weaponKind)
		if weaponSfx then
			self:playStreamRoar(muzzleAttachment, weaponSfx.FIRE)
		end
		return true
	end
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
	-- this player's own stream stops with the trigger, not after the linger
	local ownMuzzle = ClientViewModelManager:getMuzzle() or self:findHeldMuzzle(Players.LocalPlayer.Character)
	local ownPart = if ownMuzzle then ownMuzzle.Parent else nil
	if ownPart and ownPart:IsA("BasePart") then
		self:stopStreamRoar(ownPart)
	end
end

function ClientWeaponManager:onWeaponFired(payload: any)
	local isValid = Validate.isTableShape(payload, NOTIFY_WEAPON_FIRED_SHAPE)
	if not isValid then
		warn("ClientWeaponManager: malformed NotifyWeaponFired")
		return
	end
	local hitIds: { string } = payload.hitIds or {}
	if #hitIds == 0 and payload.hitId ~= "" then
		hitIds = { payload.hitId }
	end
	for _, hitId in hitIds do
		ClientDamageableManager:flashHit(hitId)
	end
	if payload.userId == Players.LocalPlayer.UserId then
		-- this client drew its own shot when it fired; the news is the hit
		local weaponSfx = self:getWeaponSfx(payload.weaponKind)
		if #hitIds > 0 and weaponSfx then
			ClientSoundManager:playSfx(weaponSfx.HIT)
		end
		if payload.isHeadshot and payload.hitId ~= "" then
			ClientHeadshotManager:showBonus(payload.hitId)
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
	local kindData = self:getKindData(payload.weaponKind)
	if kindData and kindData.CONE then
		self:playFlameEffects(muzzleAttachment)
		local weaponSfx = self:getWeaponSfx(payload.weaponKind)
		if weaponSfx then
			self:playStreamRoar(muzzleAttachment, weaponSfx.FIRE)
		end
		return
	end
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

-- the secondary's bar: shown with the ammo for a weapon that has one,
-- its Fill the share of the cooldown that has run (full when ready)
function ClientWeaponManager:renderSecondaryBar()
	local bar = self.secondaryBar
	if not bar then
		return
	end
	local kindData = self:getOwnKindData()
	local secondary = if kindData then kindData.SECONDARY else nil
	local isShown = self.isWeaponMode and secondary ~= nil and not self.isOverlayActive
	bar.Visible = isShown
	local fill = self.secondaryFill
	if not isShown or not fill or not secondary then
		return
	end
	local remaining = math.max(0, self.secondaryReadyTime - workspace:GetServerTimeNow())
	local share = if secondary.COOLDOWN_SEC > 0 then 1 - math.clamp(remaining / secondary.COOLDOWN_SEC, 0, 1) else 1
	fill.Size = UDim2.fromScale(share, 1)
	fill.BackgroundColor3 = if share >= 1 then UiStyle.POSITIVE_COLOR else UiStyle.NEGATIVE_COLOR
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
		ClientViewModelManager:show(WeaponRules.templateNameFor(weaponKind), VIEW_MODEL_OWNER)
	else
		ClientViewModelManager:hide(VIEW_MODEL_OWNER)
	end
end

function ClientWeaponManager:setWeaponMode(isWeaponMode: boolean)
	if self.isWeaponMode == isWeaponMode then
		return
	end
	if not isWeaponMode then
		self:setScoped(false)
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
	local secondaryBar = if gui then gui:FindFirstChild(Constants.WEAPON_HUD_SECONDARY_BAR, true) else nil
	if secondaryBar and secondaryBar:IsA("GuiObject") then
		self.secondaryBar = secondaryBar
		local fill = secondaryBar:FindFirstChild(Constants.WEAPON_HUD_SECONDARY_FILL, true)
		self.secondaryFill = if fill and fill:IsA("GuiObject") then fill else nil
		secondaryBar.Visible = false
	else
		warn("ClientWeaponManager: WeaponHud has no SecondaryBar; run scripts/studio/build_weapon_hud_gui.luau")
	end
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

	self.catalog = WeaponRules.decodeCatalog(ClientDataManager:getGameMetadata(Attributes.WEAPON_CATALOG))
	ClientDataManager:subscribeGameMetadataAttribute(
		Attributes.WEAPON_CATALOG,
		function(value: any)
			self.catalog = WeaponRules.decodeCatalog(value)
		end
	)
	local function applySecondaryReady(value: any)
		self.secondaryReadyTime = if typeof(value) == "number" then value else 0
	end
	applySecondaryReady(ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_SECONDARY_READY_TIME))
	ClientDataManager:subscribeCurrentPlayerAttribute(Attributes.WEAPON_SECONDARY_READY_TIME, applySecondaryReady)

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
		isTapEnabled = function(): boolean
			return ClientCameraView:isThirdPerson()
		end,
	})
	holdInput:connect()
	self.holdInput = holdInput

	-- the secondary's bar fills with the clock, so it is drawn every frame
	RunService.RenderStepped:Connect(
		function()
			self:renderSecondaryBar()
			self:stepStreamRoars()
		end
	)
	UserInputService.InputBegan:Connect(
		function(input: InputObject, isGameProcessed: boolean)
			if isGameProcessed or ClientOverlayManager:isOverlayActive() then
				return
			end
			if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonX then
				self:requestReload()
			end
			-- the aim button: the right mouse button, or the left trigger
			if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
				self:onAimButton(true)
			end
		end
	)
	UserInputService.InputEnded:Connect(
		function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
				self:onAimButton(false)
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
	self.secondaryBar = nil
	self.secondaryFill = nil
	self.predictedAmmo = 0
	self.magazineSize = 0
	self.fireIntervalSec = DEFAULT_FIRE_INTERVAL_SEC
	self.rangeStuds = DEFAULT_RANGE_STUDS
	self.reloadEndTime = 0
	self.reloadRenderToken = 0
	self.pulseTokenByInstance = {}
	self.streamRoarByPart = {}
	self.isOverlayActive = false
	self.catalog = nil
	self.isScoped = false
	self.scopeLastLook = nil
	self.scopeTurnScale = 1
	self.scopeImageId = nil
	self.savedFieldOfView = nil
	self.secondaryReadyTime = 0
	return self
end

return ClientWeaponManager.new()
