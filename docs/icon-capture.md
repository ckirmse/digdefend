# Icon image capture runbook

Instructions for Claude: turn artist-saved framings into baked image assets
(`IconImageId` attribute on the template) for any Model or BasePart under
`ReplicatedStorage.GameAssets`, keyed by dot-separated assetPath
("Weapons.Pistol", "Posts.Tier1.Turret"). Ported from Lucky Squares
(`~/Documents/square/docs/pet-image-capture.md`) with the screenshot and
image steps rewritten for Windows. Requires ImageMagick 7 (`magick`) on the
path (installed via winget on the dev machine).

## Inputs

The artist frames assets in a play session (RightShift → Dev Tools → Icon
Framing, stage asset, adjust sliders, "Save framing"). Each save prints one
line to the Output window:

```
ICON_FRAMING {"assetPath":"<Folder.Path.Name>","cf":[...12 numbers...],"fov":<n>}
```

Read the console (`get_console_output`) and collect every `ICON_FRAMING` line
since the last capture run (a later line for the same asset supersedes earlier
ones). Framings are stored relative to the template's pivot (`GetPivot()`), so
they transfer across similarly-authored assets.

## Step 1 — apply framings (Edit mode)

Studio must be in Edit mode (`get_studio_state`; stop play if the artist is
done framing). Via `execute_luau` (Edit):

```lua
require(game.ServerScriptService.Server.ApplyIconFramings)([[<paste all ICON_FRAMING lines>]])
```

This stamps `IconFraming` attributes onto the templates and prints a summary.
Attribute writes only persist in Edit mode.

## Step 2 — stage one asset for capture (Edit mode)

Via `execute_luau` (Edit), one asset at a time. `YAW` is 0 normally; use
`math.pi` for meshes authored facing away from the camera (you will see the
back of the model in the shot).

```lua
local Lighting = game:GetService("Lighting")
local BakedIconUtil = require(game.ReplicatedStorage.Shared.BakedIconUtil)
local IconFramingFormat = require(game.ReplicatedStorage.Shared.IconFramingFormat)
local assetPath = "<assetPath>"
local YAW = 0
for _, name in { "IconCaptureStage", "IconFramingBackdrop" } do
    local old = workspace:FindFirstChild(name)
    if old then old:Destroy() end
end
local template = BakedIconUtil.findTemplate(assetPath)
local framing = IconFramingFormat.decodeAttribute(template:GetAttribute("IconFraming"))
local staged = template:Clone()
staged.Name = "IconCaptureStage"
-- anchor everything (rigs settle otherwise) and strip effects so auras,
-- highlights and lights don't bake into the icon; never shortcut this loop
for _, descendant in staged:GetDescendants() do
    if descendant:IsA("BasePart") then
        descendant.Anchored = true
    elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Highlight")
        or descendant:IsA("Trail") or descendant:IsA("Beam") or descendant:IsA("Sound")
        or descendant:IsA("Light") or descendant:IsA("Sparkles")
        or descendant:IsA("Fire") or descendant:IsA("Smoke") then
        descendant:Destroy()
    elseif descendant:IsA("Humanoid") then
        -- tall rigs otherwise render the nameplate inside the frame
        descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end
end
if staged:IsA("BasePart") then staged.Anchored = true end
staged:PivotTo(CFrame.new(0, 5000, 0))
staged.Parent = workspace
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
local rel = IconFramingFormat.toRelativeCFrame(framing)
camera.CFrame = staged:GetPivot() * CFrame.Angles(0, YAW, 0) * rel
camera.FieldOfView = framing.fov
local backdrop = Instance.new("Part")
backdrop.Name = "IconFramingBackdrop"
backdrop.Size = Vector3.new(400, 400, 1)
backdrop.Color = Color3.new(0, 1, 0)
backdrop.Material = Enum.Material.Neon
backdrop.Anchored = true
backdrop.CanCollide = false
backdrop.CastShadow = false
local focus = staged:GetPivot().Position
local viewDirection = (focus - camera.CFrame.Position).Unit
backdrop.CFrame = CFrame.lookAt(focus + viewDirection * 60, focus)
backdrop.Parent = workspace
local disabledEffects = {}
for _, effect in Lighting:GetChildren() do          -- DepthOfField/Bloom/SunRays blur or tint the shot
    if effect:IsA("PostEffect") and effect.Enabled then
        effect.Enabled = false
        table.insert(disabledEffects, effect.Name)
    end
end
game:GetService("StarterGui").ShowDevelopmentGui = false  -- Studio renders StarterGui previews otherwise
game:GetService("Selection"):Set({})                       -- selection/handle widgets draw over the viewport
return "disabled post effects: " .. table.concat(disabledEffects, ", ")
```

Remember which post effects were disabled so Step 5 can restore them.

Facing check: after the screenshot, confirm the front of the asset is visible.
If not, re-stage with `YAW = math.pi`.

## Step 3 — screenshot the Studio window (PowerShell)

`screen_capture` (MCP) does not write a file to disk, and it returns only the
viewport at low resolution. Use the window-capture script, which grabs only the
Studio window, never the full screen:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/capture_studio_window.ps1 "<scratchpad>/<asset>_studio.png"
```

(`-ExecutionPolicy Bypass` applies to this one invocation only; the machine's
default policy blocks script files.) `magick` lives in
`C:\Program Files\ImageMagick-7.1.2-Q16`; add it to `PATH` in the shell if
`command -v magick` fails.

Wait about a second between staging and the screenshot so the viewport has
re-rendered. The window PNG is roughly 1936x1048 at 100% scaling. For the
eyeball check, crop the viewport region and read the smaller image rather than
the full capture:

```bash
magick "<asset>_studio.png" -crop 1280x690+10+170 +repage -resize 50% "<asset>_peek.png"
```

(offsets are for the current layout: Explorer and Properties docked right,
Output docked bottom; re-derive from the green bounding box if the layout
changed). Confirm: subject centered on pure green, facing the camera, no glow,
no UI over the green except the view-selector cube (top-right; handled below).

## Step 4 — trim to a transparent square (ImageMagick)

```bash
scripts/process_icon.sh "<asset>_studio.png" "<asset>_final.png"
```

This finds the viewport by the green bounding box, paints out the view-selector
cube corner, chroma-keys the green, drops small stray components (gizmo lines),
trims, and centers the subject on a 512x512 transparent canvas with a green
despill. For a batch, build one side-by-side preview instead of reading each
final:

```bash
magick a_final.png b_final.png -resize 256x256 +append -background '#888888' -alpha remove montage.png
```

Read it to verify: full-color subject, transparent background, no green
fringe, no stray lines. If the trim box is much larger than the subject, a
widget survived keying; raise the area threshold in `process_icon.sh`.
Multi-part rigs can key apart into several components; lower the threshold
if a limb vanishes.

## Step 5 — upload and stamp (Edit mode)

`upload_image` (MCP) takes HTTP URLs only, so serve the scratchpad locally:

```bash
cd "<scratchpad>" && python -m http.server 8971 --bind 127.0.0.1   # run_in_background
```

Then `upload_image` with `http://127.0.0.1:8971/<asset>_final.png`, which
returns `rbxassetid://<id>`. Stop the server after. Then via `execute_luau`
(Edit):

```lua
local Lighting = game:GetService("Lighting")
local BakedIconUtil = require(game.ReplicatedStorage.Shared.BakedIconUtil)
BakedIconUtil.findTemplate("<assetPath>"):SetAttribute("IconImageId", <id>)
for _, name in { "IconCaptureStage", "IconFramingBackdrop" } do
    local inst = workspace:FindFirstChild(name)
    if inst then inst:Destroy() end
end
for _, effectName in { <names returned by Step 2> } do
    local effect = Lighting:FindFirstChild(effectName)
    if effect then effect.Enabled = true end
end
game:GetService("StarterGui").ShowDevelopmentGui = true
workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed
```

For multiple assets, loop Steps 2 to 4 per asset, then batch-upload all finals
in one `upload_image` call and stamp all ids; clean up once at the end.

## Step 6 — verify

`BakedIconUtil.getBakedImage("<assetPath>")` (Edit mode) must return
`rbxassetid://<id>`. Freshly uploaded assets can take a minute to load and
pass moderation.

## Known gotchas

- Play-mode attribute writes don't persist; everything above runs in Edit.
- Synthetic RightShift from the MCP doesn't reach UserInputService; the artist
  opens the dev tools themselves.
- The view-selector cube can't be disabled by API; that's why Step 4 paints
  its corner green before keying.
- Framings copied from one asset to a differently sized one put the camera
  inside the mesh; scale the relative translation by the size ratio
  (`template.Size.Magnitude / sourceSize`) before applying.
