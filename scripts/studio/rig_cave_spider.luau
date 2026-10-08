-- Rigs the designer's CaveSpider model in Workspace with Motor6Ds so the
-- Animation Editor can pose it and the game can play its clips (M62,
-- 2026-10-08: the model arrived as loose parts, and the editor refuses a
-- model with no joints). Adds an invisible HumanoidRootPart at the body's
-- centre facing the head and makes it the PrimaryPart, then joins:
-- root -> torso; torso -> Head, Abdomen, each leg's Upper; Upper -> Mid;
-- Mid -> Lower; Head -> every Eyes part and every fang part. A joint sits
-- at the end of the child nearest its parent, so a leg segment swings
-- from its hip or knee, not its middle. An AnimationController with an
-- Animator goes on too, which the Animation Editor needs to take the rig.
-- Runs once: a model that already has a Motor6D is left alone. Nothing else about the model is changed;
-- rerun build_cave_spider_template.luau afterwards to make the template.
-- Run in the gameplay place through the MCP execute_luau tool.
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local SOURCE_NAME = "CaveSpider"
-- the head is toward -X in the authored model
local FORWARD = Vector3.new(-1, 0, 0)

local ServerStorage = game:GetService("ServerStorage")
local sourcesFolder = ServerStorage:FindFirstChild("Sources")
local model = workspace:FindFirstChild(SOURCE_NAME, true) or (if sourcesFolder then sourcesFolder:FindFirstChild(SOURCE_NAME) else nil)
assert(model and model:IsA("Model"), "no Model named " .. SOURCE_NAME .. " in Workspace or ServerStorage.Sources")
for _, descendant in model:GetDescendants() do
	if descendant:IsA("Motor6D") then
		print("rig_cave_spider: " .. model:GetFullName() .. " already has Motor6Ds; nothing to do")
		return
	end
end

ChangeHistoryService:SetWaypoint("Before rigging the Cave Spider")

local torso = model:FindFirstChild("torso") or model:FindFirstChild("Torso")
local head = model:FindFirstChild("Head")
local abdomen = model:FindFirstChild("Abdomen")
assert(torso and head and abdomen, "the model needs torso, Head, and Abdomen parts")
torso.Name = "Torso"

-- animation keyframes are keyed by part name, so every part must be
-- unique (the editor refuses a rig with two "Upper"s): legs are named by
-- side and number, front to back, with their segment; fangs by side and
-- height; eyes by number. The head is toward -X and width runs along Z,
-- so a part's side is the sign of its Z against the torso's
local function side(part: BasePart): string
	return if part.Position.Z < torso.Position.Z then "Left" else "Right"
end
local legModels = {}
for _, child in model:GetChildren() do
	if child:IsA("Model") and (child.Name == "Leg" or child.Name:match("^%a+Leg%d$")) then
		local upper = child:FindFirstChild("Upper") or child:FindFirstChildWhichIsA("BasePart")
		table.insert(legModels, { model = child, upper = upper })
	end
end
table.sort(
	legModels,
	function(a, b)
		local sideA, sideB = side(a.upper), side(b.upper)
		if sideA ~= sideB then
			return sideA < sideB
		end
		return a.upper.Position.X < b.upper.Position.X
	end
)
local sideCounts = { Left = 0, Right = 0 }
for _, leg in legModels do
	local legSide = side(leg.upper)
	sideCounts[legSide] += 1
	local prefix = legSide .. "Leg" .. sideCounts[legSide]
	leg.model.Name = prefix
	for _, part in leg.model:GetChildren() do
		if part:IsA("BasePart") then
			local segment = if part.Name:match("Upper$") then "Upper" elseif part.Name:match("Mid$") then "Mid" elseif part.Name:match("Lower$") then "Lower" else part.Name
			part.Name = prefix .. segment
		end
	end
end
for _, child in model:GetChildren() do
	if child:IsA("Model") and (child.Name == "Fang" or child.Name:match("^%a+Fang$")) then
		local parts = {}
		for _, part in child:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(parts, part)
			end
		end
		table.sort(
			parts,
			function(a, b)
				return a.Position.Y > b.Position.Y
			end
		)
		local fangSide = side(parts[1])
		child.Name = fangSide .. "Fang"
		for index, part in parts do
			part.Name = fangSide .. "Fang" .. index
		end
	end
end
local eyes = {}
for _, child in model:GetChildren() do
	if child:IsA("BasePart") and (child.Name == "Eyes" or child.Name:match("^Eye%d+$")) then
		table.insert(eyes, child)
	end
end
table.sort(
	eyes,
	function(a, b)
		if math.abs(a.Position.Z - b.Position.Z) > 0.01 then
			return a.Position.Z < b.Position.Z
		end
		return a.Position.X < b.Position.X
	end
)
for index, eye in eyes do
	eye.Name = "Eye" .. index
end

local boxCFrame = model:GetBoundingBox()
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(1, 1, 1)
root.Transparency = 1
root.CanCollide = false
root.CanQuery = false
root.CanTouch = false
root.Anchored = true
root.CFrame = CFrame.lookAlong(boxCFrame.Position, FORWARD)
root.Parent = model
model.PrimaryPart = root

-- the world point a child hangs from: the end of its long axis nearest
-- the parent, or its centre for a part with no long axis
local function jointPoint(parent: BasePart, child: BasePart): CFrame
	local size = child.Size
	local longest = math.max(size.X, size.Y, size.Z)
	if longest < 1 or longest < 2 * math.min(size.X, size.Y, size.Z) then
		return child.CFrame
	end
	local axis = if size.X == longest then Vector3.new(size.X / 2, 0, 0) elseif size.Y == longest then Vector3.new(0, size.Y / 2, 0) else Vector3.new(0, 0, size.Z / 2)
	local a = child.CFrame * CFrame.new(axis)
	local b = child.CFrame * CFrame.new(-axis)
	local parentPosition = parent.Position
	return if (a.Position - parentPosition).Magnitude <= (b.Position - parentPosition).Magnitude then a else b
end

local joints = 0
local function join(parent: BasePart, child: BasePart, name: string)
	local pivot = jointPoint(parent, child)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = parent
	motor.Part1 = child
	motor.C0 = parent.CFrame:ToObjectSpace(pivot)
	motor.C1 = child.CFrame:ToObjectSpace(pivot)
	motor.Parent = parent
	child.Anchored = false
	joints += 1
end

join(root, torso, "RootJoint")
join(torso, head, "Neck")
join(torso, abdomen, "Waist")
local legs = 0
for _, child in model:GetChildren() do
	if child:IsA("Model") and child.Name:match("^%a+Leg%d$") then
		local upper = child:FindFirstChild(child.Name .. "Upper")
		local mid = child:FindFirstChild(child.Name .. "Mid")
		local lower = child:FindFirstChild(child.Name .. "Lower")
		if upper and mid and lower then
			legs += 1
			join(torso, upper, child.Name .. "Hip")
			join(upper, mid, child.Name .. "Knee")
			join(mid, lower, child.Name .. "Ankle")
		end
	elseif child:IsA("Model") and child.Name:match("^%a+Fang$") then
		for _, part in child:GetChildren() do
			if part:IsA("BasePart") then
				join(head, part, part.Name .. "Joint")
			end
		end
	elseif child:IsA("BasePart") and child.Name:match("^Eye%d+$") then
		join(head, child, child.Name .. "Joint")
	end
end

-- the Animation Editor takes a rig only with a Humanoid or an
-- AnimationController on it; the puppet has no Humanoid by design
local controller = Instance.new("AnimationController")
controller.Parent = model
local animator = Instance.new("Animator")
animator.Parent = controller

ChangeHistoryService:SetWaypoint("After rigging the Cave Spider")
print(string.format("rig_cave_spider: %d Motor6D(s) on %s, %d legs, root at %s", joints, model:GetFullName(), legs, tostring(root.Position)))
