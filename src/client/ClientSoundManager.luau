--!strict

-- Plays the designer-authored 2D audio under SoundService: AudioPlayers in
-- the Sfx and Music folders, each wired to the AudioDeviceOutput. Names come
-- from shared SoundNames; a missing player or an empty asset is reported once
-- and otherwise silent, so unfinished audio never breaks a feature. Also
-- keeps an AudioListener on the camera wired to the same output, so the 3D
-- emitters the server attaches to objects (SpatialSoundManager) are heard
-- from where they are.
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")

local ClientSoundManager = {}
ClientSoundManager.__index = ClientSoundManager

export type ClientSoundManager = typeof(setmetatable(
	{} :: {
		-- the designer's volume of each looping player faded by setSfxLoopLevel
		authoredVolumeByName: { [string]: number },
		sfxFolder: Instance?,
		musicFolder: Instance?,
		warnedNames: { [string]: boolean },
	},
	ClientSoundManager
))

-- long enough for any one-shot; the throwaway part goes with it
local SPATIAL_ONE_SHOT_LIFETIME_SEC = 5

function ClientSoundManager:warnOnce(name: string, message: string)
	if self.warnedNames[name] then
		return
	end
	self.warnedNames[name] = true
	warn("ClientSoundManager: " .. message)
end

function ClientSoundManager:findPlayer(folder: Instance?, name: string): AudioPlayer?
	if not folder then
		return nil
	end
	local player = folder:FindFirstChild(name)
	if player and player:IsA("AudioPlayer") then
		return player
	end
	return nil
end

function ClientSoundManager:playSfx(name: string)
	local player = self:findPlayer(self.sfxFolder, name)
	if not player then
		self:warnOnce(name, `no AudioPlayer {Constants.SFX_FOLDER}.{name}`)
		return
	end
	if player.Asset == "" then
		self:warnOnce(name, `{Constants.SFX_FOLDER}.{name} has no asset yet`)
		return
	end
	-- restart so rapid repeats (cash ticking up) each make a sound
	player.TimePosition = 0
	player:Play()
end

-- a 3D one-shot heard from a world position by this client only (gunfire:
-- too frequent for the server to build a part per shot). The authored
-- player is cloned onto a local throwaway part with an emitter, as
-- SpatialSoundManager does on the server. fullVolumeStuds and silentStuds
-- shape the falloff: an emitter's default is the real inverse-square law,
-- fine within a few studs but nearly gone by 60 (measured 2026-09-17: a
-- shot 60 studs off came through at 6% of its level up close), so a
-- crewmate firing across the camp could not be heard
function ClientSoundManager:playSfxAt(position: Vector3, name: string, fullVolumeStuds: number, silentStuds: number)
	local template = self:findPlayer(self.sfxFolder, name)
	if not template then
		self:warnOnce(name, `no AudioPlayer {Constants.SFX_FOLDER}.{name}`)
		return
	end
	if template.Asset == "" then
		self:warnOnce(name, `{Constants.SFX_FOLDER}.{name} has no asset yet`)
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(position)
	local player = template:Clone()
	for _, child in player:GetChildren() do
		if child:IsA("Wire") then
			child:Destroy()
		end
	end
	player.Looping = false
	local emitter = Instance.new("AudioEmitter")
	-- full volume up close, then a curve that drops quickly at first and
	-- trails off, which is how distance is heard
	local fadeStuds = math.max(1, silentStuds - fullVolumeStuds)
	emitter:SetDistanceAttenuation({
		[0] = 1,
		[fullVolumeStuds] = 1,
		[fullVolumeStuds + fadeStuds * 0.25] = 0.45,
		[fullVolumeStuds + fadeStuds * 0.6] = 0.15,
		[fullVolumeStuds + fadeStuds] = 0,
	})
	emitter.Parent = anchor
	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = emitter
	wire.Parent = player
	player.Parent = anchor
	anchor.Parent = workspace
	player:Play()
	Debris:AddItem(anchor, SPATIAL_ONE_SHOT_LIFETIME_SEC)
end

-- a 3D loop that rides a part (a rocket in flight, a turning gun): the same
-- wiring as a one-shot, but the emitter lives on the part and the loop dies
-- with it. Returns the player so the owner can stop and restart it; nil
-- when the sound is not authored yet. isStarted false leaves it silent
function ClientSoundManager:attachLoop(part: BasePart, name: string, fullVolumeStuds: number, silentStuds: number, isStarted: boolean?): AudioPlayer?
	local template = self:findPlayer(self.sfxFolder, name)
	if not template then
		self:warnOnce(name, `no AudioPlayer {Constants.SFX_FOLDER}.{name}`)
		return nil
	end
	if template.Asset == "" then
		self:warnOnce(name, `{Constants.SFX_FOLDER}.{name} has no asset yet`)
		return nil
	end
	local player = template:Clone()
	for _, child in player:GetChildren() do
		if child:IsA("Wire") then
			child:Destroy()
		end
	end
	player.Looping = true
	local emitter = Instance.new("AudioEmitter")
	local fadeStuds = math.max(1, silentStuds - fullVolumeStuds)
	emitter:SetDistanceAttenuation({
		[0] = 1,
		[fullVolumeStuds] = 1,
		[fullVolumeStuds + fadeStuds * 0.25] = 0.45,
		[fullVolumeStuds + fadeStuds * 0.6] = 0.15,
		[fullVolumeStuds + fadeStuds] = 0,
	})
	emitter.Parent = part
	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = emitter
	wire.Parent = player
	player.Parent = part
	if isStarted ~= false then
		player:Play()
	end
	return player
end

-- a 2D loop for this player only (the turret whirring under the gunner):
-- the authored looping player itself, kept running and faded by level so
-- it can swell and die away as often as the owner likes. Level 1 is the
-- designer's authored volume; 0 is silent but still running, so a fade
-- never restarts the sound. stopSfxLoop halts it and restores the volume
function ClientSoundManager:setSfxLoopLevel(name: string, level: number)
	local player = self:findPlayer(self.sfxFolder, name)
	if not player then
		self:warnOnce(name, `no AudioPlayer {Constants.SFX_FOLDER}.{name}`)
		return
	end
	if player.Asset == "" then
		self:warnOnce(name, `{Constants.SFX_FOLDER}.{name} has no asset yet`)
		return
	end
	local authoredVolume = self.authoredVolumeByName[name]
	if authoredVolume == nil then
		authoredVolume = player.Volume
		self.authoredVolumeByName[name] = authoredVolume
	end
	player.Volume = authoredVolume * math.clamp(level, 0, 1)
	if not player.IsPlaying then
		player.Looping = true
		player:Play()
	end
end

function ClientSoundManager:stopSfxLoop(name: string)
	local player = self:findPlayer(self.sfxFolder, name)
	if not player then
		return
	end
	if player.IsPlaying then
		player:Stop()
	end
	local authoredVolume = self.authoredVolumeByName[name]
	if authoredVolume then
		player.Volume = authoredVolume
	end
end

function ClientSoundManager:checkAuthoredSounds()
	local output = SoundService:FindFirstChildOfClass("AudioDeviceOutput")
	if not output then
		warn("ClientSoundManager: SoundService has no AudioDeviceOutput; 2D audio will be silent")
	end
	for _, name in SoundNames.Sfx do
		if not self:findPlayer(self.sfxFolder, name) then
			warn(`ClientSoundManager: SoundNames.Sfx names {name} but {Constants.SFX_FOLDER} has no such AudioPlayer`)
		end
	end
	for _, name in SoundNames.Music do
		if not self:findPlayer(self.musicFolder, name) then
			warn(`ClientSoundManager: SoundNames.Music names {name} but {Constants.MUSIC_FOLDER} has no such AudioPlayer`)
		end
	end
end

-- the ear: one listener that follows the camera, feeding the device output
function ClientSoundManager:setupListener()
	local output = SoundService:FindFirstChildOfClass("AudioDeviceOutput")
	local camera = workspace.CurrentCamera
	if not output or not camera then
		return
	end
	local listener = Instance.new("AudioListener")
	listener.Name = "CameraListener"
	listener.Parent = camera
	local wire = Instance.new("Wire")
	wire.SourceInstance = listener
	wire.TargetInstance = output
	wire.Parent = listener
	-- a new camera (a respawn) needs the listener moved onto it
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(
		function()
			local current = workspace.CurrentCamera
			if current and listener.Parent ~= current then
				listener.Parent = current
			end
		end
	)
end

function ClientSoundManager:init()
	self:setupListener()
	self.sfxFolder = SoundService:FindFirstChild(Constants.SFX_FOLDER)
	self.musicFolder = SoundService:FindFirstChild(Constants.MUSIC_FOLDER)
	if not self.sfxFolder then
		warn(`ClientSoundManager: SoundService has no {Constants.SFX_FOLDER} folder`)
	end
	if not self.musicFolder then
		warn(`ClientSoundManager: SoundService has no {Constants.MUSIC_FOLDER} folder`)
	end
	self:checkAuthoredSounds()
end

function ClientSoundManager.new(): ClientSoundManager
	local self = setmetatable({}, ClientSoundManager) :: ClientSoundManager
	self.authoredVolumeByName = {}
	self.sfxFolder = nil
	self.musicFolder = nil
	self.warnedNames = {}
	return self
end

return ClientSoundManager.new()
