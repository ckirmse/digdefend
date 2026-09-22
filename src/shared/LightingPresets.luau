--!strict

-- The looks of the sky per map (GDD "Wave Cycle"), M28, read from Studio
-- on 2026-09-22: every map has four. A day blends DAY_START into DAY_END
-- over its length; the night's first seconds blend DAY_END into
-- NIGHT_START (dusk), then NIGHT_START into NIGHT_END over the spawn
-- window, and night end holds until the wave is done; dawn blends
-- NIGHT_END back to DAY_START (ClientRunCycleManager; lengths in
-- GameData/Control/RunCycle).
-- LIGHTING is the Lighting service itself; CHILDREN is keyed by the name
-- of the child under Lighting. Each look's ClockTime is the hour that
-- stage ends at. Data only; the designer sets a look up in Studio and the
-- numbers are ported here. A map without an entry falls back to
-- DEFAULT_MAP's.
local Enums = require(script.Parent.Enums)

local LightingPresets = {}

export type Properties = { [string]: any }

export type Preset = {
	LIGHTING: Properties,
	CHILDREN: { [string]: Properties },
}

export type MapPresets = {
	DAY_START: Preset,
	DAY_END: Preset,
	NIGHT_START: Preset,
	NIGHT_END: Preset,
}

LightingPresets.PRESET_NAMES = { "DAY_START", "DAY_END", "NIGHT_START", "NIGHT_END" }

LightingPresets.CHILD_NAMES = { "Atmosphere", "Bloom", "ColorCorrection", "DepthOfField", "Sky", "SunRays" }
LightingPresets.DEFAULT_MAP = Enums.Map.DEADMANS_CANYON

-- the parts of a look that do not change between morning and night on
-- the canyon; each map's presets spell everything out regardless
local CANYON_COMMON_CHILDREN = {
	Bloom = {
		Enabled = true,
		Intensity = 1,
		Size = 24,
		Threshold = 2,
	},
	ColorCorrection = {
		Enabled = true,
		Brightness = 0,
		Contrast = 0,
		Saturation = 0.2,
		TintColor = Color3.fromRGB(255, 255, 255),
	},
	DepthOfField = {
		Enabled = false,
		FarIntensity = 0.1,
		FocusDistance = 0.05,
		InFocusRadius = 30,
		NearIntensity = 0.75,
	},
	Sky = {
		CelestialBodiesShown = true,
		StarCount = 3000,
		SunAngularSize = 10,
		MoonAngularSize = 11,
		SunTextureId = "rbxassetid://6196665106",
		MoonTextureId = "rbxassetid://6444320592",
		SkyboxBk = "rbxassetid://6444884337",
		SkyboxFt = "rbxassetid://6444884337",
		SkyboxLf = "rbxassetid://6444884337",
		SkyboxRt = "rbxassetid://6444884337",
		SkyboxUp = "rbxassetid://6412503613",
		SkyboxDn = "rbxassetid://6444884785",
	},
	SunRays = {
		Enabled = true,
		Intensity = 0.15,
		Spread = 0,
	},
}

local function withChildren(atmosphere: Properties): { [string]: Properties }
	local children = table.clone(CANYON_COMMON_CHILDREN)
	children.Atmosphere = atmosphere
	return children
end

-- the day's looks share their colours; the day is the sun's arc from
-- 8:00 to 17:30
local CANYON_DAY_START: Preset = {
	LIGHTING = {
		ClockTime = 8,
		Brightness = 7,
		Ambient = Color3.fromRGB(70, 70, 70),
		OutdoorAmbient = Color3.fromRGB(0, 0, 0),
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
		ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
		ShadowSoftness = 0.2,
		GlobalShadows = true,
		ExposureCompensation = 0,
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		GeographicLatitude = 27,
		FogColor = Color3.fromRGB(192, 192, 192),
		FogStart = 0,
		FogEnd = 100000,
	},
	CHILDREN = withChildren({
		Density = 0.3,
		Offset = 0.25,
		Color = Color3.fromRGB(199, 199, 199),
		Decay = Color3.fromRGB(106, 112, 125),
		Glare = 0,
		Haze = 0,
	}),
}

local CANYON_DAY_END: Preset = {
	LIGHTING = {
		ClockTime = 17.5,
		Brightness = 7,
		Ambient = Color3.fromRGB(70, 70, 70),
		OutdoorAmbient = Color3.fromRGB(0, 0, 0),
		ColorShift_Top = Color3.fromRGB(0, 0, 0),
		ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
		ShadowSoftness = 0.2,
		GlobalShadows = true,
		ExposureCompensation = 0,
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		GeographicLatitude = 27,
		FogColor = Color3.fromRGB(192, 192, 192),
		FogStart = 0,
		FogEnd = 100000,
	},
	CHILDREN = withChildren({
		Density = 0.3,
		Offset = 0.25,
		Color = Color3.fromRGB(199, 199, 199),
		Decay = Color3.fromRGB(106, 112, 125),
		Glare = 0,
		Haze = 0,
	}),
}

-- night start and night end share their colours (read 2026-09-22). The
-- engine hands its one directional light from the sun to the moon at
-- about 19:12 (seen in play), a switch nothing can blend, so dusk dims
-- the light to nothing and lands just past that hour; the night stage is
-- then the moon rising, the light coming back up to full by 20:00
local CANYON_NIGHT_START: Preset = {
	LIGHTING = {
		ClockTime = 19.2,
		Brightness = 0,
		Ambient = Color3.fromRGB(82, 87, 88),
		OutdoorAmbient = Color3.fromRGB(5, 134, 255),
		ColorShift_Top = Color3.fromRGB(34, 99, 221),
		ColorShift_Bottom = Color3.fromRGB(0, 179, 255),
		ShadowSoftness = 0.2,
		GlobalShadows = true,
		ExposureCompensation = 0,
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		GeographicLatitude = 27,
		FogColor = Color3.fromRGB(192, 192, 192),
		FogStart = 0,
		FogEnd = 100000,
	},
	CHILDREN = withChildren({
		Density = 0.3,
		Offset = 0.25,
		Color = Color3.fromRGB(5, 93, 199),
		Decay = Color3.fromRGB(106, 112, 125),
		Glare = 0,
		Haze = 0,
	}),
}

local CANYON_NIGHT_END: Preset = {
	LIGHTING = {
		ClockTime = 20,
		Brightness = 7,
		Ambient = Color3.fromRGB(82, 87, 88),
		OutdoorAmbient = Color3.fromRGB(5, 134, 255),
		ColorShift_Top = Color3.fromRGB(34, 99, 221),
		ColorShift_Bottom = Color3.fromRGB(0, 179, 255),
		ShadowSoftness = 0.2,
		GlobalShadows = true,
		ExposureCompensation = 0,
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		GeographicLatitude = 27,
		FogColor = Color3.fromRGB(192, 192, 192),
		FogStart = 0,
		FogEnd = 100000,
	},
	CHILDREN = withChildren({
		Density = 0.3,
		Offset = 0.25,
		Color = Color3.fromRGB(5, 93, 199),
		Decay = Color3.fromRGB(106, 112, 125),
		Glare = 0,
		Haze = 0,
	}),
}

LightingPresets.BY_MAP = {
	[Enums.Map.DEADMANS_CANYON] = {
		DAY_START = CANYON_DAY_START,
		DAY_END = CANYON_DAY_END,
		NIGHT_START = CANYON_NIGHT_START,
		NIGHT_END = CANYON_NIGHT_END,
	},
	-- Frostbite Pass has no look of its own yet (M42); the canyon's stands in
	[Enums.Map.FROSTBITE_PASS] = {
		DAY_START = CANYON_DAY_START,
		DAY_END = CANYON_DAY_END,
		NIGHT_START = CANYON_NIGHT_START,
		NIGHT_END = CANYON_NIGHT_END,
	},
} :: { [number]: MapPresets }

-- the two looks a sky stage blends between (Enums.SkyStage)
function LightingPresets.stageEnds(presets: MapPresets, stage: number): (Preset, Preset)
	if stage == Enums.SkyStage.DUSK then
		return presets.DAY_END, presets.NIGHT_START
	elseif stage == Enums.SkyStage.NIGHT then
		return presets.NIGHT_START, presets.NIGHT_END
	elseif stage == Enums.SkyStage.DAWN then
		return presets.NIGHT_END, presets.DAY_START
	end
	return presets.DAY_START, presets.DAY_END
end

function LightingPresets.forMap(map: number?): MapPresets
	return LightingPresets.BY_MAP[map or LightingPresets.DEFAULT_MAP] or LightingPresets.BY_MAP[LightingPresets.DEFAULT_MAP]
end

-- the properties a blend can carry (numbers and colours) and the ones set
-- outright (everything else, and ClockTime, which the day clock turns
-- itself the forward way round)
function LightingPresets.splitTweenable(properties: Properties): (Properties, Properties)
	local tweenable = {}
	local instant = {}
	for name, value in properties do
		if name == "ClockTime" then
			continue
		end
		if typeof(value) == "number" or typeof(value) == "Color3" then
			tweenable[name] = value
		else
			instant[name] = value
		end
	end
	return tweenable, instant
end

-- the look part way from one preset to another: numbers and colours
-- mixed by share (0 is all `from`, 1 all `to`); the rest come from `to`
-- once the share passes half, `from` before
function LightingPresets.blend(from: Properties, to: Properties, share: number): Properties
	local mixed = {}
	local clamped = math.clamp(share, 0, 1)
	for name, fromValue in from do
		local toValue = to[name]
		if name == "ClockTime" or toValue == nil then
			continue
		end
		if typeof(fromValue) == "number" and typeof(toValue) == "number" then
			mixed[name] = fromValue + (toValue - fromValue) * clamped
		elseif typeof(fromValue) == "Color3" and typeof(toValue) == "Color3" then
			mixed[name] = fromValue:Lerp(toValue, clamped)
		else
			mixed[name] = if clamped >= 0.5 then toValue else fromValue
		end
	end
	return mixed
end

return LightingPresets
