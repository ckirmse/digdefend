-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)
local LightingPresets = require(game:GetService("ReplicatedStorage").Shared.LightingPresets)

local function keysOf(properties)
	local keys = {}
	for name in properties do
		table.insert(keys, name)
	end
	table.sort(keys)
	return keys
end

describe(
	"LightingPresets",
	function()
		it(
			"gives every map four looks that set exactly the same properties",
			function()
				for _, map in Enums.getAllValues(Enums.Map) do
					local presets = LightingPresets.BY_MAP[map]
					expect(presets).toBeDefined()
					for _, presetName in LightingPresets.PRESET_NAMES do
						local preset = presets[presetName]
						expect(preset).toBeDefined()
						expect(keysOf(preset.LIGHTING)).toEqual(keysOf(presets.DAY_START.LIGHTING))
						expect(keysOf(preset.CHILDREN)).toEqual(keysOf(presets.DAY_START.CHILDREN))
						for _, childName in LightingPresets.CHILD_NAMES do
							expect(presets.DAY_START.CHILDREN[childName]).toBeDefined()
							expect(keysOf(preset.CHILDREN[childName])).toEqual(keysOf(presets.DAY_START.CHILDREN[childName]))
						end
						expect(typeof(preset.LIGHTING.ClockTime)).toBe("number")
					end
				end
			end
		)
		it(
			"pairs each stage with the looks it blends between",
			function()
				local presets = LightingPresets.BY_MAP[LightingPresets.DEFAULT_MAP]
				local from, to = LightingPresets.stageEnds(presets, Enums.SkyStage.DAY)
				expect(from).toBe(presets.DAY_START)
				expect(to).toBe(presets.DAY_END)
				from, to = LightingPresets.stageEnds(presets, Enums.SkyStage.DUSK)
				expect(from).toBe(presets.DAY_END)
				expect(to).toBe(presets.NIGHT_START)
				from, to = LightingPresets.stageEnds(presets, Enums.SkyStage.NIGHT)
				expect(from).toBe(presets.NIGHT_START)
				expect(to).toBe(presets.NIGHT_END)
				from, to = LightingPresets.stageEnds(presets, Enums.SkyStage.DAWN)
				expect(from).toBe(presets.NIGHT_END)
				expect(to).toBe(presets.DAY_START)
			end
		)
		it(
			"falls back to the default map for an unknown one",
			function()
				expect(LightingPresets.forMap(999)).toBe(LightingPresets.BY_MAP[LightingPresets.DEFAULT_MAP])
				expect(LightingPresets.forMap(nil)).toBe(LightingPresets.BY_MAP[LightingPresets.DEFAULT_MAP])
			end
		)
		it(
			"blends numbers and colours by share and picks the nearer side for the rest",
			function()
				local mixed = LightingPresets.blend({ ClockTime = 8, Brightness = 2, Ambient = Color3.new(0, 0, 0), GlobalShadows = true, Extra = 1 }, { ClockTime = 20, Brightness = 4, Ambient = Color3.new(1, 1, 1), GlobalShadows = false }, 0.25)
				expect(mixed.Brightness).toBeCloseTo(2.5, 5)
				expect(mixed.Ambient.R).toBeCloseTo(0.25, 5)
				expect(mixed.GlobalShadows).toBe(true)
				expect(mixed.ClockTime).toBeNil()
				expect(mixed.Extra).toBeNil()
				expect(LightingPresets.blend({ GlobalShadows = true }, { GlobalShadows = false }, 0.75).GlobalShadows).toBe(false)
			end
		)
		it(
			"splits numbers and colours from what must be set outright, leaving the clock alone",
			function()
				local tweenable, instant = LightingPresets.splitTweenable({ ClockTime = 8, Brightness = 7, Ambient = Color3.new(1, 1, 1), GlobalShadows = true, SkyboxUp = "rbxassetid://1" })
				expect(tweenable.Brightness).toBe(7)
				expect(tweenable.Ambient).toBeDefined()
				expect(tweenable.ClockTime).toBeNil()
				expect(instant.GlobalShadows).toBe(true)
				expect(instant.SkyboxUp).toBe("rbxassetid://1")
				expect(instant.ClockTime).toBeNil()
			end
		)
	end
)
