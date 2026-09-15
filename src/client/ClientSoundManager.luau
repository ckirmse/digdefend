--!strict

-- Plays the designer-authored 2D audio under SoundService: AudioPlayers in
-- the Sfx and Music folders, each wired to the AudioDeviceOutput. Names come
-- from shared SoundNames; a missing player or an empty asset is reported once
-- and otherwise silent, so unfinished audio never breaks a feature. Also
-- keeps an AudioListener on the camera wired to the same output, so the 3D
-- emitters the server attaches to objects (SpatialSoundManager) are heard
-- from where they are.
local SoundService = game:GetService("SoundService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local SoundNames = require("@game/ReplicatedStorage/Shared/SoundNames")

local ClientSoundManager = {}
ClientSoundManager.__index = ClientSoundManager

export type ClientSoundManager = typeof(setmetatable(
	{} :: {
		sfxFolder: Instance?,
		musicFolder: Instance?,
		warnedNames: { [string]: boolean },
	},
	ClientSoundManager
))

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
	self.sfxFolder = nil
	self.musicFolder = nil
	self.warnedNames = {}
	return self
end

return ClientSoundManager.new()
