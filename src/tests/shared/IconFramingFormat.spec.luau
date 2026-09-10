-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local IconFramingFormat = require(game:GetService("ReplicatedStorage").Shared.IconFramingFormat)

local function makeFraming(): IconFramingFormat.Framing
	local relative = CFrame.new(0, 1, -5) * CFrame.Angles(0, math.rad(30), 0)
	return {
		cf = { relative:GetComponents() },
		fov = 30,
	}
end

describe(
	"IconFramingFormat line round-trip",
	function()
		it(
			"encodes and parses a framing line",
			function()
				local framing = makeFraming()
				local line = IconFramingFormat.encodeLine("Weapons.Pistol", framing)
				local entry = IconFramingFormat.parseLine(line)
				expect(entry).never.toBeNil()
				assert(entry)
				expect(entry.assetPath).toBe("Weapons.Pistol")
				expect(entry.framing.fov).toBe(30)
				expect(#entry.framing.cf).toBe(12)
				for index, component in framing.cf do
					expect(entry.framing.cf[index]).toBeCloseTo(component, 4)
				end
			end
		)

		it(
			"parses a line with leading whitespace",
			function()
				local line = "  " .. IconFramingFormat.encodeLine("Posts.Turret", makeFraming())
				expect(IconFramingFormat.parseLine(line)).never.toBeNil()
			end
		)

		it(
			"rejects malformed lines",
			function()
				expect(IconFramingFormat.parseLine("ICON_FRAMING not json")).toBeNil()
				expect(IconFramingFormat.parseLine('ICON_FRAMING {"assetPath":"Weapons.Pistol","cf":[1,2],"fov":30}')).toBeNil()
				expect(IconFramingFormat.parseLine('ICON_FRAMING {"assetPath":"","cf":[1,2,3,4,5,6,7,8,9,10,11,12],"fov":30}')).toBeNil()
				expect(IconFramingFormat.parseLine('ICON_FRAMING {"assetPath":"Weapons.Pistol","cf":[1,2,3,4,5,6,7,8,9,10,11,12],"fov":0}')).toBeNil()
				expect(IconFramingFormat.parseLine("unrelated console output")).toBeNil()
			end
		)
	end
)

describe(
	"IconFramingFormat.parseAll",
	function()
		it(
			"parses valid lines out of mixed console text and keeps the last save per asset",
			function()
				local firstFraming = makeFraming()
				local secondFraming = makeFraming()
				secondFraming.fov = 45
				local text = table.concat({
					"some unrelated output",
					IconFramingFormat.encodeLine("Weapons.Pistol", firstFraming),
					"ICON_FRAMING garbage",
					IconFramingFormat.encodeLine("Posts.Turret", firstFraming),
					IconFramingFormat.encodeLine("Weapons.Pistol", secondFraming),
				}, "\n")
				local entries, badLineCount = IconFramingFormat.parseAll(text)
				expect(#entries).toBe(2)
				expect(badLineCount).toBe(1)
				expect(entries[1].assetPath).toBe("Weapons.Pistol")
				expect(entries[1].framing.fov).toBe(45)
				expect(entries[2].assetPath).toBe("Posts.Turret")
			end
		)
	end
)

describe(
	"IconFramingFormat attribute round-trip",
	function()
		it(
			"encodes and decodes an attribute value",
			function()
				local framing = makeFraming()
				local decoded = IconFramingFormat.decodeAttribute(IconFramingFormat.encodeAttribute(framing))
				expect(decoded).never.toBeNil()
				assert(decoded)
				expect(decoded.fov).toBe(30)
				expect(#decoded.cf).toBe(12)
			end
		)

		it(
			"rejects malformed attribute values",
			function()
				expect(IconFramingFormat.decodeAttribute("not json")).toBeNil()
				expect(IconFramingFormat.decodeAttribute('{"cf":[1,2],"fov":30}')).toBeNil()
			end
		)
	end
)

describe(
	"IconFramingFormat.fromCameraAndTarget / toRelativeCFrame",
	function()
		it(
			"round-trips the camera pose through the pivot-relative framing",
			function()
				local targetPivot = CFrame.new(10, 5000, -3) * CFrame.Angles(0, math.rad(90), 0)
				local cameraCFrame = CFrame.lookAt(Vector3.new(14, 5002, -9), targetPivot.Position)
				local framing = IconFramingFormat.fromCameraAndTarget(cameraCFrame, targetPivot, 30)
				local rebuilt = targetPivot * IconFramingFormat.toRelativeCFrame(framing)
				local original = { cameraCFrame:GetComponents() }
				for index, component in { rebuilt:GetComponents() } do
					expect(component).toBeCloseTo(original[index], 3)
				end
			end
		)
	end
)
