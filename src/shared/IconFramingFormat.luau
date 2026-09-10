--!strict

-- Serialization for per-asset capture framings: the play-mode dev tool prints
-- one machine-readable line per saved framing, and the edit-mode
-- ApplyIconFramings utility parses those lines back to persist them as
-- template attributes. See docs/icon-capture.md.
local HttpService = game:GetService("HttpService")

local IconFramingFormat = {}

IconFramingFormat.LINE_PREFIX = "ICON_FRAMING"

local CFRAME_COMPONENT_COUNT = 12
local MAX_FOV = 120

-- cf is the 12 components of the camera CFrame relative to the target's pivot,
-- so capture can stage the asset anywhere and reconstruct the same shot
export type Framing = {
	cf: { number },
	fov: number,
}

export type FramingEntry = {
	assetPath: string,
	framing: Framing,
}

local function isValidFraming(framing: any): boolean
	if typeof(framing) ~= "table" then
		return false
	end
	if typeof(framing.fov) ~= "number" or framing.fov <= 0 or framing.fov > MAX_FOV then
		return false
	end
	if typeof(framing.cf) ~= "table" or #framing.cf ~= CFRAME_COMPONENT_COUNT then
		return false
	end
	for _, component in framing.cf do
		if typeof(component) ~= "number" then
			return false
		end
	end
	return true
end

function IconFramingFormat.fromCameraAndTarget(cameraCFrame: CFrame, targetPivot: CFrame, fov: number): Framing
	local relative = targetPivot:ToObjectSpace(cameraCFrame)
	return {
		cf = { relative:GetComponents() },
		fov = fov,
	}
end

function IconFramingFormat.toRelativeCFrame(framing: Framing): CFrame
	local cf = framing.cf
	return CFrame.new(cf[1], cf[2], cf[3], cf[4], cf[5], cf[6], cf[7], cf[8], cf[9], cf[10], cf[11], cf[12])
end

function IconFramingFormat.encodeAttribute(framing: Framing): string
	return HttpService:JSONEncode(framing)
end

function IconFramingFormat.decodeAttribute(encoded: string): Framing?
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or not isValidFraming(decoded) then
		return nil
	end
	return decoded
end

function IconFramingFormat.encodeLine(assetPath: string, framing: Framing): string
	local payload = HttpService:JSONEncode({
		assetPath = assetPath,
		cf = framing.cf,
		fov = framing.fov,
	})
	return `{IconFramingFormat.LINE_PREFIX} {payload}`
end

function IconFramingFormat.parseLine(line: string): FramingEntry?
	local payload = string.match(line, `^%s*{IconFramingFormat.LINE_PREFIX} (.+)$`)
	if not payload then
		return nil
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(payload :: string)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" or typeof(decoded.assetPath) ~= "string" or decoded.assetPath == "" then
		return nil
	end
	local framing = { cf = decoded.cf, fov = decoded.fov }
	if not isValidFraming(framing) then
		return nil
	end
	return {
		assetPath = decoded.assetPath,
		framing = framing,
	}
end

-- parses every ICON_FRAMING line in pasted multi-line console text; a later
-- line for the same asset wins so the artist can re-save freely in one session
function IconFramingFormat.parseAll(text: string): ({ FramingEntry }, number)
	local entriesByAssetPath: { [string]: FramingEntry } = {}
	local orderedAssetPaths: { string } = {}
	local badLineCount = 0
	for line in string.gmatch(text, "[^\r\n]+") do
		if not string.find(line, IconFramingFormat.LINE_PREFIX, 1, true) then
			continue
		end
		local entry = IconFramingFormat.parseLine(line)
		if not entry then
			badLineCount += 1
			continue
		end
		if not entriesByAssetPath[entry.assetPath] then
			table.insert(orderedAssetPaths, entry.assetPath)
		end
		entriesByAssetPath[entry.assetPath] = entry
	end
	local entries: { FramingEntry } = {}
	for _, assetPath in orderedAssetPaths do
		table.insert(entries, entriesByAssetPath[assetPath])
	end
	return entries, badLineCount
end

return IconFramingFormat
