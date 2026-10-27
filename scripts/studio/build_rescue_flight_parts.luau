-- Authors what the rescue escape cinematic (M75) needs in a place, and is
-- safe to rerun: it only adds what is missing and leaves anything the
-- designer has tuned.
-- * On the Helicopter template under ReplicatedStorage/GameAssets (both
--   places): the BoardPrompt ProximityPrompt (disabled; RescueManager
--   enables it once landed) on the body, and the Searchlight SpotLight
--   (disabled; lit by the clients on the way in).
-- * On every map's Camp.HelicopterPad under ServerStorage/Maps (gameplay
--   place): ApproachSpawn (where the rescue helicopter appears, high and
--   far, facing the pad), DepartureHeading (its facing is the way out),
--   and Dust (a part on the pad with the touchdown emitter). The parts are
--   invisible and inert; move them in the Explorer to change the flight.
-- * Under SoundService.Sfx: the AudioPlayers the escape plays, wired to
--   the device output with no asset yet (the designer fills them in):
--   Helicopter_Touchdown, Helicopter_Liftoff, Rescue_Board,
--   Rescue_Incoming, Rescue_Win (the lobby gets the lift-off only). The
--   radio's dispatch message is the designer's own Rescue Sound on the
--   radio model, not made here.
-- Run from the Studio command bar (or the MCP execute_luau tool).
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local HELICOPTER_BODY = "SM_Veh_Helicopter_01"
-- the approach start relative to the pad's spawn, in the pad's own frame:
-- x to its right, y up, z behind it (the pad faces the gate, so the
-- helicopter comes in over the monsters' side, off to one flank)
local APPROACH_OFFSET = Vector3.new(-260, 160, -380)
-- the way out, in the pad's frame: ahead and off to the other flank
local DEPARTURE_HEADING = Vector3.new(0.8, 0, -0.6)

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
	local approachPosition = spawn.CFrame:PointToWorldSpace(APPROACH_OFFSET)
	makeMarker(pad, "ApproachSpawn", CFrame.lookAt(approachPosition, spawn.Position), Vector3.new(4, 1, 4))
	local heading = spawn.CFrame:VectorToWorldSpace(DEPARTURE_HEADING)
	makeMarker(pad, "DepartureHeading", CFrame.lookAt(spawn.Position + Vector3.new(0, 6, 0), spawn.Position + Vector3.new(0, 6, 0) + heading), Vector3.new(4, 1, 4))
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
	if not template:FindFirstChild("BoardPrompt", true) then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BoardPrompt"
		prompt.ActionText = "Board"
		prompt.ObjectText = "Rescue helicopter"
		prompt.MaxActivationDistance = 14
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.ClickablePrompt = false
		prompt.Enabled = false
		prompt.Parent = body
		log(`added {prompt:GetFullName()}`)
	else
		log("kept the template's BoardPrompt")
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

local function buildSounds(folderName: string, names: { string })
	local sfx = SoundService:FindFirstChild(folderName)
	if not sfx then
		log(`no SoundService.{folderName} folder; sounds skipped`)
		return
	end
	local output = SoundService:FindFirstChildWhichIsA("AudioDeviceOutput", true)
	for _, name in names do
		if sfx:FindFirstChild(name) then
			log(`kept {folderName}.{name}`)
			continue
		end
		local player = Instance.new("AudioPlayer")
		player.Name = name
		player.Looping = false
		player.Volume = 1
		local wire = Instance.new("Wire")
		wire.SourceInstance = player
		wire.TargetInstance = output
		wire.Parent = player
		player.Parent = sfx
		log(`added {folderName}.{name} (no asset yet)`)
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
	buildSounds("Sfx", { "Helicopter_Touchdown", "Helicopter_Liftoff", "Rescue_Board", "Rescue_Incoming", "Rescue_Win" })
else
	buildSounds("Sfx", { "Helicopter_Liftoff" })
end
ChangeHistoryService:SetWaypoint("After rescue flight parts")
print("build_rescue_flight_parts:\n" .. table.concat(report, "\n"))
return table.concat(report, "\n")
