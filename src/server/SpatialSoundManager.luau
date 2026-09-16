--!strict

-- 3D sounds every player hears from where they happen (a lit stick of
-- dynamite, a burning jet pack). The designer authors each sound once as an
-- AudioPlayer under SoundService.Sfx, exactly as for 2D audio; this manager
-- clones that player onto a world part with an AudioEmitter, so the asset
-- lives in one place and the emitter's position does the rest. Each client
-- hears it through the AudioListener ClientSoundManager keeps on its camera.
-- A missing player or empty asset is reported once and stays silent, like
-- the 2D path.
local SoundService = game:GetService("SoundService")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")

local SpatialSoundManager = {}
SpatialSoundManager.__index = SpatialSoundManager

export type SpatialSoundManager = typeof(setmetatable(
	{} :: {
		warnedNames: { [string]: boolean },
	},
	SpatialSoundManager
))

-- a one-shot whose Ended never fires (asset failed to load) is cleaned up after this
local ONE_SHOT_MAX_LIFETIME_SEC = 10
local EMITTER_NAME = "SpatialEmitter"

function SpatialSoundManager:warnOnce(name: string, message: string)
	if self.warnedNames[name] then
		return
	end
	self.warnedNames[name] = true
	warn("SpatialSoundManager: " .. message)
end

function SpatialSoundManager:findTemplate(name: string): AudioPlayer?
	local sfx = SoundService:FindFirstChild(Constants.SFX_FOLDER)
	local player = if sfx then sfx:FindFirstChild(name) else nil
	if not player or not player:IsA("AudioPlayer") then
		self:warnOnce(name, `no AudioPlayer {Constants.SFX_FOLDER}.{name}`)
		return nil
	end
	if player.Asset == "" then
		self:warnOnce(name, `{Constants.SFX_FOLDER}.{name} has no asset yet`)
		return nil
	end
	return player
end

-- clones the authored player onto the part with an emitter and starts it
-- unless isAutoPlay is false (then a client decides when it plays, as with
-- the helicopter rotor loop); the caller keeps the returned player to stop
-- or destroy it. The template's own Wire (to the device output) is dropped
-- so the clone is only spatial.
function SpatialSoundManager:attach(part: BasePart, name: string, isLooping: boolean?, isAutoPlay: boolean?): AudioPlayer?
	local template = self:findTemplate(name)
	if not template then
		return nil
	end
	local player = template:Clone()
	for _, child in player:GetChildren() do
		if child:IsA("Wire") then
			child:Destroy()
		end
	end
	if isLooping ~= nil then
		player.Looping = isLooping
	end
	local emitter = Instance.new("AudioEmitter")
	emitter.Name = EMITTER_NAME
	emitter.Parent = part
	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = emitter
	wire.Parent = player
	player.Parent = part
	if isAutoPlay ~= false then
		player:Play()
	end
	return player
end

-- a one-shot at a world position on a throwaway part that goes when the sound does
function SpatialSoundManager:playAt(position: Vector3, name: string)
	if not self:findTemplate(name) then
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
	anchor.Parent = workspace
	local player = self:attach(anchor, name, false)
	if not player then
		anchor:Destroy()
		return
	end
	player.Ended:Connect(
		function()
			anchor:Destroy()
		end
	)
	task.delay(
		ONE_SHOT_MAX_LIFETIME_SEC,
		function()
			if anchor.Parent then
				anchor:Destroy()
			end
		end
	)
end

function SpatialSoundManager.new(): SpatialSoundManager
	local self = setmetatable({}, SpatialSoundManager) :: SpatialSoundManager
	self.warnedNames = {}
	return self
end

return SpatialSoundManager.new()
