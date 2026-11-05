-- Authors the Supply Crate stall's camera parts under Workspace.SupplyCrateStore
-- (GDD "Class Unlock System", the 3D crate opening, designer 2026-11-03):
-- three invisible anchored parts whose CFrames are the camera's shots,
-- CameraMenuOpen (the crate on the left two thirds, the menu panel on the
-- right), CameraOpenSequence (the crate centred, waiting for the tap), and
-- CameraOpen (the lid up, the card flying out). Run in the lobby place;
-- reruns safely and keeps a part the designer has already moved. The
-- numbers are the designer's Studio Position and Orientation (degrees,
-- Studio's YXZ order). Names must match Constants.SUPPLY_CRATE_CAMERA_*.
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)

local SHOTS = {
	{
		name = Constants.SUPPLY_CRATE_CAMERA_MENU,
		position = Vector3.new(-30.458, 3.961, 46.634),
		orientationDegrees = Vector3.new(-14.867, -178.647, 0),
	},
	{
		name = Constants.SUPPLY_CRATE_CAMERA_SEQUENCE,
		position = Vector3.new(-28.884, 4.217, 47.236),
		orientationDegrees = Vector3.new(-16.884, -178.992, 0),
	},
	{
		name = Constants.SUPPLY_CRATE_CAMERA_OPEN,
		position = Vector3.new(-28.748, 4.125, 45.974),
		orientationDegrees = Vector3.new(9.576, 179.328, 0),
	},
}

ChangeHistoryService:SetWaypoint("Before supply crate parts")

local folder = workspace:FindFirstChild(Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER)
if not folder then
	error(`no Workspace.{Constants.LOBBY_SUPPLY_CRATE_STORE_FOLDER} folder`)
end

local made = {}
for _, shot in SHOTS do
	if folder:FindFirstChild(shot.name) then
		continue
	end
	local part = Instance.new("Part")
	part.Name = shot.name
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	-- Studio's Orientation is Euler YXZ in degrees
	local radians = shot.orientationDegrees * (math.pi / 180)
	part.CFrame = CFrame.new(shot.position) * CFrame.fromEulerAnglesYXZ(radians.X, radians.Y, radians.Z)
	part.Parent = folder
	table.insert(made, shot.name)
end

-- the crate's sounds under SoundService.Sfx, wired to the device output
-- (the designer's CrateOpen is kept; ClassUnlocked added 2026-11-04)
local SoundNames = require(game.ReplicatedStorage.Shared.SoundNames)
local SOUNDS = {
	{ name = SoundNames.Sfx.CLASS_UNLOCKED, assetId = 86883509504250 },
	{ name = SoundNames.Sfx.CLASS_TIER_UP, assetId = 17759873264 },
}
local sfx = game.SoundService:FindFirstChild("Sfx")
local output = game.SoundService:FindFirstChildWhichIsA("AudioDeviceOutput")
if sfx and output then
	for _, sound in SOUNDS do
		if sfx:FindFirstChild(sound.name) then
			continue
		end
		local player = Instance.new("AudioPlayer")
		player.Name = sound.name
		player.Volume = 1
		player.Asset = `rbxassetid://{sound.assetId}`
		local wire = Instance.new("Wire")
		wire.SourceInstance = player
		wire.TargetInstance = output
		wire.Parent = player
		player.Parent = sfx
		table.insert(made, sound.name)
	end
end

ChangeHistoryService:SetWaypoint("Supply crate parts")
return if #made == 0 then "supply crate camera parts already present" else "made " .. table.concat(made, ", ")
