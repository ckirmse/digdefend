-- Builds ReplicatedStorage/GameAssets/Tutorial/GuideHead (M76, 2026-11-09):
-- the head of the lobby's Class Selection salesperson
-- (Workspace.ClassSelection.ClassCharacter in the lobby place), who talks
-- the first-run player through day 1, as a three-part anchored model the
-- tutorial's dialogue box shows in its Portrait ViewportFrame. The mesh
-- and texture ids, sizes, colours, and the helmet's and mask's offsets
-- from the head were read off the lobby rig on 2026-11-09, so the two
-- places need no shared asset; the head's front is its -Z. Run from the
-- Studio command bar (or the MCP execute_luau tool) in the gameplay
-- place; it replaces any existing copy.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

ChangeHistoryService:SetWaypoint("Before GuideHead")

local SKIN_COLOR = Color3.new(0.917647, 0.721569, 0.572549)
local GEAR_COLOR = Color3.new(0.639216, 0.635294, 0.647059)

-- the lobby rig's Head and the two accessories on it, with each
-- accessory's CFrame relative to the head's
local PARTS = {
	{
		name = "Head",
		meshId = "rbxassetid://72827710653057",
		textureId = "rbxassetid://101576742139111",
		size = Vector3.new(1.19784, 1.2024, 1.20428),
		color = SKIN_COLOR,
		offset = CFrame.new(),
	},
	{
		name = "Helmet",
		meshId = "rbxassetid://97688148676984",
		textureId = "rbxassetid://119892830937794",
		size = Vector3.new(1.66790, 1.53087, 1.76864),
		color = GEAR_COLOR,
		-- head CFrame (52.391468, 5.968265, 21.694996), helmet (52.336144, 6.290761, 21.694996), same facing (-X)
		offset = CFrame.new(0, 0.322496, -0.055324),
	},
	{
		name = "Mask",
		meshId = "rbxassetid://5197119144",
		textureId = "rbxassetid://5197121493",
		size = Vector3.new(1.42427, 1.28882, 1.83896),
		color = GEAR_COLOR,
		-- mask (52.108082, 5.975954, 21.779995): 0.283 ahead of the face, 0.085 to its right
		offset = CFrame.new(0.084999, 0.007689, -0.283386),
	},
}

local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
if not gameAssets then
	error("build_tutorial_guide_head: no ReplicatedStorage.GameAssets")
end
local folder = gameAssets:FindFirstChild("Tutorial")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Tutorial"
	folder.Parent = gameAssets
end
local existing = folder:FindFirstChild("GuideHead")
if existing then
	existing:Destroy()
end

local model = Instance.new("Model")
model.Name = "GuideHead"
for _, spec in PARTS do
	local part = InsertService:CreateMeshPartAsync(spec.meshId, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Precise)
	part.Name = spec.name
	part.TextureID = spec.textureId
	part.Size = spec.size
	part.Color = spec.color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = spec.offset
	part.Parent = model
	if spec.name == "Head" then
		model.PrimaryPart = part
	end
end
model.Parent = folder

ChangeHistoryService:SetWaypoint("After GuideHead")
print("build_tutorial_guide_head: built ReplicatedStorage.GameAssets.Tutorial.GuideHead")

-- the guide beam's template beside the head (2026-11-09): the Beam the
-- client clones for the trail from the player to a step's world target
-- (ClientTutorialManager sets its two attachments). THE DESIGNER TUNES
-- IT IN THE EXPLORER: an existing one is left alone, so a rerun of this
-- script never resets it
if not folder:FindFirstChild("GuideBeam") then
	local beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Color = ColorSequence.new(Color3.fromRGB(245, 200, 80))
	beam.Width0 = 1
	beam.Width1 = 1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new(0.25)
	-- the tutorial arrow picture as a wrapping texture, moving toward the target
	beam.Texture = "rbxassetid://75040607043356"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 4
	beam.TextureSpeed = 1.5
	beam.Segments = 1
	beam.Parent = folder
	print("build_tutorial_guide_head: built ReplicatedStorage.GameAssets.Tutorial.GuideBeam")
end

-- the prompt sound (designer's asset, 2026-11-09): an AudioPlayer under
-- SoundService.Sfx wired to the output, played by ClientTutorialManager as
-- every line or task appears; an existing one is left alone
local sfx = game.SoundService:FindFirstChild("Sfx")
local output = game.SoundService:FindFirstChildWhichIsA("AudioDeviceOutput")
if sfx and output and not sfx:FindFirstChild("TutorialPrompt") then
	local player = Instance.new("AudioPlayer")
	player.Name = "TutorialPrompt"
	player.Volume = 1
	player.Asset = "rbxassetid://94069540570800"
	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = output
	wire.Parent = player
	player.Parent = sfx
	print("build_tutorial_guide_head: built SoundService.Sfx.TutorialPrompt")
end
