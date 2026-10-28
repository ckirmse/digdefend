-- Authors what the rescue escape cinematic (M75) needs in a place, and is
-- safe to rerun: it only adds what is missing and leaves anything the
-- designer has tuned.
-- * On the Helicopter template under ReplicatedStorage/GameAssets (both
--   places): the Searchlight SpotLight (disabled; lit by the clients on
--   the way in). A BoardPrompt from the first build is removed: boarding
--   is by touch since 2026-10-27.
-- * On every map's Camp.HelicopterPad under ServerStorage/Maps (gameplay
--   place): Dust (a part on the pad with the touchdown emitter; a stale
--   ApproachSpawn or DepartureHeading from the earlier builds is removed,
--   every flight running along the pad's facing since 2026-10-27) and the
--   rider's three camera shots, RideCameraStart (the camera once
--   seated), RideCameraEnd (where it is once risen with the lift-off),
--   and RideCameraFinal (where it drifts to over the rest of the ride),
--   placed from the designer's Deadman's Canyon shots relative to the
--   pad. The parts are invisible and inert; move the shots in the
--   Explorer to change the ride's view.
-- * Under SoundService.Sfx: the AudioPlayers the escape plays, wired to
--   the device output, with the designer's asset where one was given and
--   empty otherwise: Helicopter_Touchdown, Helicopter_Liftoff,
--   Rescue_Board, Rescue_Incoming, Rescue_Win, Rescue_Landed (the lobby
--   gets the lift-off only); under SoundService.Music the looping
--   FinalNightSong. The radio's dispatch message is the designer's own
--   Rescue Sound on the radio model, not made here.
-- Run from the Studio command bar (or the MCP execute_luau tool).
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local HELICOPTER_BODY = "SM_Veh_Helicopter_01"
-- the rider's shots in the pad's spawn frame (the designer's Deadman's
-- Canyon placements, 2026-10-27)
local RIDE_CAMERA_START = CFrame.new(19.832, 6.934, -26.874, -0.7544, 0.0506, 0.6544, 0, 0.997, -0.0771, -0.6564, -0.0582, -0.7522)
local RIDE_CAMERA_END = CFrame.new(34.972, 35.48, 32.931, 0.9968, -0.0162, 0.0782, 0, 0.9792, 0.2029, -0.0799, -0.2022, 0.9761)
local RIDE_CAMERA_FINAL = CFrame.new(39.941, 159.111, 7.827, 0.9989, 0.0367, 0.0308, 0, 0.6423, -0.7665, -0.0479, 0.7656, 0.6416)

local isGameplay = ServerStorage:FindFirstChild("Maps") ~= nil
local report = {}

local function log(message: string)
	table.insert(report, message)
end

local function makeMarker(parent: Instance, name: string, cframe: CFrame, size: Vector3): BasePart
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		log(`kept {existing:GetFullName()}`)
		return existing
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = parent
	log(`added {part:GetFullName()}`)
	return part
end

local function buildPad(pad: Instance)
	local spawn = pad:FindFirstChild("HelicopterSpawn")
	if not spawn or not spawn:IsA("BasePart") then
		log(`{pad:GetFullName()} has no HelicopterSpawn part; skipped`)
		return
	end
	for _, staleName in { "ApproachSpawn", "DepartureHeading" } do
		local stale = pad:FindFirstChild(staleName)
		if stale then
			stale:Destroy()
			log(`removed {pad:GetFullName()}.{staleName} (every flight runs along the pad's facing)`)
		end
	end
	makeMarker(pad, "RideCameraStart", spawn.CFrame * RIDE_CAMERA_START, Vector3.new(2, 2, 2))
	makeMarker(pad, "RideCameraEnd", spawn.CFrame * RIDE_CAMERA_END, Vector3.new(2, 2, 2))
	makeMarker(pad, "RideCameraFinal", spawn.CFrame * RIDE_CAMERA_FINAL, Vector3.new(2, 2, 2))
	local dust = makeMarker(pad, "Dust", spawn.CFrame + Vector3.new(0, 0.5, 0), Vector3.new(8, 1, 8))
	if not dust:FindFirstChildWhichIsA("ParticleEmitter") then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "DustEmitter"
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(1.5, 2.5)
		emitter.Speed = NumberRange.new(20, 35)
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		emitter.Color = ColorSequence.new(Color3.fromRGB(196, 170, 128))
		emitter.Drag = 2
		emitter.Acceleration = Vector3.new(0, -6, 0)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-40, 40)
		emitter.Parent = dust
		log(`added {emitter:GetFullName()}`)
	end
end

local function buildTemplate()
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local template = if gameAssets then gameAssets:FindFirstChild("Helicopter") else nil
	if not template then
		log("no GameAssets.Helicopter template; skipped")
		return
	end
	local body = template:FindFirstChild(HELICOPTER_BODY) or template:FindFirstChildWhichIsA("BasePart")
	if not body then
		log("the Helicopter template has no body part; skipped")
		return
	end
	local stalePrompt = template:FindFirstChild("BoardPrompt", true)
	if stalePrompt then
		stalePrompt:Destroy()
		log("removed the template's BoardPrompt (boarding is by touch)")
	end
	if not template:FindFirstChild("Searchlight", true) then
		local light = Instance.new("SpotLight")
		light.Name = "Searchlight"
		light.Face = Enum.NormalId.Bottom
		light.Angle = 55
		light.Range = 160
		light.Brightness = 4
		light.Color = Color3.fromRGB(255, 244, 214)
		light.Shadows = true
		light.Enabled = false
		light.Parent = body
		log(`added {light:GetFullName()}`)
	else
		log("kept the template's Searchlight")
	end
end

-- a name alone makes an empty player; a name with an asset id fills it
-- in (an existing player is left as the designer has it)
local function buildSounds(folderName: string, names: { string | { name: string, assetId: number, isLooping: boolean? } })
	local sfx = SoundService:FindFirstChild(folderName)
	if not sfx then
		log(`no SoundService.{folderName} folder; sounds skipped`)
		return
	end
	local output = SoundService:FindFirstChildWhichIsA("AudioDeviceOutput", true)
	for _, entry in names do
		local name = if typeof(entry) == "string" then entry else entry.name
		local assetId = if typeof(entry) == "table" then entry.assetId else nil
		local isLooping = typeof(entry) == "table" and entry.isLooping == true
		if sfx:FindFirstChild(name) then
			log(`kept {folderName}.{name}`)
			continue
		end
		local player = Instance.new("AudioPlayer")
		player.Name = name
		player.Looping = isLooping
		player.Volume = 1
		if assetId then
			player.Asset = `rbxassetid://{assetId}`
		end
		local wire = Instance.new("Wire")
		wire.SourceInstance = player
		wire.TargetInstance = output
		wire.Parent = player
		player.Parent = sfx
		log(`added {folderName}.{name}` .. if assetId then "" else " (no asset yet)")
	end
end

ChangeHistoryService:SetWaypoint("Before rescue flight parts")
buildTemplate()
if isGameplay then
	for _, map in ServerStorage.Maps:GetChildren() do
		local pad = map:FindFirstChild("HelicopterPad")
		if pad then
			buildPad(pad)
		end
	end
	local campInWorkspace = workspace:FindFirstChild("Camp")
	local loadedPad = if campInWorkspace then campInWorkspace:FindFirstChild("HelicopterPad") else nil
	if loadedPad then
		buildPad(loadedPad)
	end
	buildSounds("Sfx", { "Helicopter_Touchdown", "Helicopter_Liftoff", "Rescue_Board", "Rescue_Incoming", "Rescue_Win", { name = "Rescue_Landed", assetId = 93702417682824 } })
	buildSounds("Music", { { name = "FinalNightSong", assetId = 74659750894541, isLooping = true }, { name = "RescueExitSong", assetId = 70524779529135, isLooping = true } })
else
	buildSounds("Sfx", { "Helicopter_Liftoff" })
end
ChangeHistoryService:SetWaypoint("After rescue flight parts")
print("build_rescue_flight_parts:\n" .. table.concat(report, "\n"))
return table.concat(report, "\n")
