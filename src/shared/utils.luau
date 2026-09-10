--!strict

local utils = {}

type Denomination = { suffix: string, exp: number }

-- ordered largest first so the first match wins
local DENOMINATIONS: { Denomination } = {
	{ suffix = "T", exp = 12 },
	{ suffix = "B", exp = 9 },
	{ suffix = "M", exp = 6 },
	{ suffix = "K", exp = 3 },
}

function utils.abbreviateNumber(n: number): string
	if n < 0 then
		return "-" .. utils.abbreviateNumber(-n)
	end
	if n < 1000 then
		return tostring(math.floor(n))
	end
	for _, denomination in DENOMINATIONS do
		if n >= 10 ^ denomination.exp then
			return string.format("%.2f%s", n / 10 ^ denomination.exp, denomination.suffix)
		end
	end
	return tostring(math.floor(n))
end

function utils.convertDurationSecToString(duration: number): string
	local days = duration // (3600 * 24)
	local hours = (duration - days * 3600 * 24) // 3600
	local minutes = (duration - days * 3600 * 24 - hours * 3600) // 60
	local sec = (duration - days * 3600 * 24 - hours * 3600 - minutes * 60) % 60
	if days > 0 then
		return string.format("%i:%02i:%02i:%02i", days, hours, minutes, sec)
	end
	if hours > 0 then
		return string.format("%2i:%02i:%02i", hours, minutes, sec)
	end
	return string.format("%2i:%02i", minutes, sec)
end

function utils.getColoredText(str: string, color: Color3): string
	return string.format("<font color=\"#%s\">%s</font>", color:ToHex(), str)
end

function utils.capitalize(str: string): string
	-- outer parentheses force only one return value, discarding the rest of gsub's results
	return (str:gsub("^%l", string.upper))
end

function utils.trimString(str: string): string
	-- this pattern matches every string, so the assert cannot fire
	return assert(string.match(str, "^%s*(.-)%s*$"))
end

function utils.deepCopy(obj: any, seen: { [any]: any }?): any
	if typeof(obj) ~= "table" then
		return obj
	end
	if seen and seen[obj] then
		return seen[obj]
	end
	local newTable: { [any]: any } = {}
	local seenMap: { [any]: any } = seen or {}
	seenMap[obj] = newTable
	local metatable = getmetatable(obj)
	if metatable then
		setmetatable(newTable, utils.deepCopy(metatable, seenMap))
	end
	for key, value in obj do
		newTable[utils.deepCopy(key, seenMap)] = utils.deepCopy(value, seenMap)
	end
	return newTable
end

function utils.shallowCopy(obj: any): any
	if typeof(obj) ~= "table" then
		return obj
	end
	local newTable: { [any]: any } = {}
	for key, value in obj do
		newTable[key] = value
	end
	return newTable
end

function utils.getTableSize(tbl: { [any]: any }): number
	local count = 0
	for _ in tbl do
		count += 1
	end
	return count
end

function utils.doesArrayContain<T>(array: { T }, value: T): boolean
	return table.find(array, value) ~= nil
end

function utils.arrayFindIndexOf<T>(array: { T }, value: T): number?
	return table.find(array, value)
end

function utils.arrayAppend<T>(array: { T }, extra: { T })
	for _, value in extra do
		table.insert(array, value)
	end
end

function utils.getArrayUnion<T>(arrayA: { T }, arrayB: { T }): { T }
	local union: { T } = {}
	local seen: { [any]: boolean } = {}
	for _, array in { arrayA, arrayB } do
		for _, value in array do
			if seen[value] then
				continue
			end
			table.insert(union, value)
			seen[value] = true
		end
	end
	return union
end

function utils.getMagnitudeXZ(vector: Vector3): number
	return math.sqrt(vector.X * vector.X + vector.Z * vector.Z)
end

function utils.getMagnitudeXZSquared(vector: Vector3): number
	return vector.X * vector.X + vector.Z * vector.Z
end

function utils.findFirstDescendantOfClass(parent: Instance, className: string): Instance?
	for _, descendant in parent:GetDescendants() do
		if descendant:IsA(className) then
			return descendant
		end
	end
	return nil
end

function utils.findFirstDescendant(parent: Instance, name: string): Instance?
	for _, descendant in parent:GetDescendants() do
		if descendant.Name == name then
			return descendant
		end
	end
	return nil
end

function utils.findFirstDescendantOfClassAndName(parent: Instance, className: string, name: string): Instance?
	for _, descendant in parent:GetDescendants() do
		if descendant:IsA(className) and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

function utils.getMainPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		local primaryPart = inst.PrimaryPart
		if primaryPart then
			return primaryPart
		end
		return inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function utils.setPropertyTreeClassName(root: Instance, className: string, propertyName: string, value: any)
	if root:IsA(className) then
		(root :: any)[propertyName] = value
	end
	for _, descendant in root:GetDescendants() do
		if not descendant:IsA(className) then
			continue
		end
		(descendant :: any)[propertyName] = value
	end
end

function utils.setPropertyTreeBaseParts(root: Instance, propertyName: string, value: any)
	utils.setPropertyTreeClassName(root, "BasePart", propertyName, value)
end

function utils.addTreeToCollisionGroup(root: Instance, collisionGroupName: string)
	utils.setPropertyTreeBaseParts(root, "CollisionGroup", collisionGroupName)
end

-- an instant change to and from a value is not replicated, so the reset is delayed
function utils.pulseAttribute(inst: Instance, attributeName: string, value: any)
	inst:SetAttribute(attributeName, value)
	task.delay(0.02,
		function()
			inst:SetAttribute(attributeName, nil)
		end
	)
end

-- dot-separated path below root; yields on each segment
function utils.getPathReference(root: Instance, path: string): Instance?
	local inst = root
	for _, segment in string.split(path, ".") do
		local parent = inst
		inst = parent:WaitForChild(segment)
		if (inst :: Instance?) == nil then
			warn("failed to load asset path", path, parent, segment)
			return nil
		end
	end
	return inst
end

-- deterministic order so server and clients agree on attachment indexing
function utils.getSortedAttachments(folder: Instance): { Attachment }
	local attachments = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Attachment") then
			table.insert(attachments, child)
		end
	end
	table.sort(attachments,
		function(a: Attachment, b: Attachment): boolean
			local positionA, positionB = a.CFrame.Position, b.CFrame.Position
			if positionA.X ~= positionB.X then
				return positionA.X < positionB.X
			end
			if positionA.Z ~= positionB.Z then
				return positionA.Z < positionB.Z
			end
			if positionA.Y ~= positionB.Y then
				return positionA.Y < positionB.Y
			end
			return a.Name < b.Name
		end
	)
	return attachments
end

function utils.getBoundingBoxBottomY(boundsCFrame: CFrame, boundsSize: Vector3): number
	local half = boundsSize / 2
	local bottomY = math.huge
	for _, x in { -half.X, half.X } do
		for _, y in { -half.Y, half.Y } do
			for _, z in { -half.Z, half.Z } do
				local corner = boundsCFrame:PointToWorldSpace(Vector3.new(x, y, z))
				bottomY = math.min(bottomY, corner.Y)
			end
		end
	end
	return bottomY
end

-- lift only, never lower: art whose geometry extends below its pivot must not
-- embed in the ground, but art authored floating stays where the anchor says
function utils.calcAnchorGroundLift(anchorCFrame: CFrame, boundsCFrame: CFrame, boundsSize: Vector3): number
	return math.max(0, anchorCFrame.Position.Y - utils.getBoundingBoxBottomY(boundsCFrame, boundsSize))
end

-- the anchor is the sole authority for caster pose; the anchor's Y plane is the ground
function utils.placeCasterAtAnchor(caster: PVInstance, anchorCFrame: CFrame)
	caster:PivotTo(anchorCFrame)
	local boundsCFrame: CFrame
	local boundsSize: Vector3
	if caster:IsA("Model") then
		boundsCFrame, boundsSize = caster:GetBoundingBox()
	elseif caster:IsA("BasePart") then
		boundsCFrame, boundsSize = caster.CFrame, caster.Size
	else
		return
	end
	local lift = utils.calcAnchorGroundLift(anchorCFrame, boundsCFrame, boundsSize)
	if lift > 0 then
		caster:PivotTo(anchorCFrame + Vector3.new(0, lift, 0))
	end
end

function utils.safelyDisposeOfParticle(effect: ParticleEmitter, delaySec: number?)
	task.delay(delaySec or 0,
		function()
			effect.Enabled = false
			task.wait(effect.Lifetime.Max)
			-- Debris in case the effect is destroyed another way in the meantime
			game:GetService("Debris"):AddItem(effect, 0)
		end
	)
end

return utils
