-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local ControlsRules = require(game:GetService("ReplicatedStorage").Shared.ControlsRules)
local Enums = require(game:GetService("ReplicatedStorage").Shared.Enums)

local function actions(rows)
	local names = {}
	for _, row in rows do
		table.insert(names, row.action)
	end
	return names
end

local function makeContext(overrides)
	local context = {
		place = Enums.PlaceKind.GAMEPLAY,
		tool = Enums.ToolKind.PICK_AXE,
		gadgetKind = nil,
		isMounted = false,
		isBuildMode = false,
	}
	for key, value in overrides or {} do
		context[key] = value
	end
	return context
end

describe("ControlsRules.schemeFor", function()
	it("follows the last input: a gamepad press, a touch, else the keyboard", function()
		expect(ControlsRules.schemeFor(Enum.UserInputType.Gamepad1, true, true)).toBe(ControlsRules.Scheme.GAMEPAD)
		expect(ControlsRules.schemeFor(Enum.UserInputType.Touch, false, false)).toBeNil()
		expect(ControlsRules.schemeFor(Enum.UserInputType.MouseMovement, true, false)).toBe(ControlsRules.Scheme.KEYBOARD)
		expect(ControlsRules.schemeFor(Enum.UserInputType.None, false, true)).toBe(ControlsRules.Scheme.GAMEPAD)
		expect(ControlsRules.schemeFor(Enum.UserInputType.None, false, false)).toBeNil()
	end)
end)

describe("ControlsRules.rowsFor", function()
	it("shows the pick axe swing with the body controls, keyed by scheme", function()
		local keyboard = ControlsRules.rowsFor(makeContext(), ControlsRules.Scheme.KEYBOARD)
		expect(actions(keyboard)).toEqual({ "Move", "Jump", "Jet pack", "Switch tool", "Backpack", "Swing pick axe" })
		expect(keyboard[#keyboard].key).toBe("LMB")
		local gamepad = ControlsRules.rowsFor(makeContext(), ControlsRules.Scheme.GAMEPAD)
		expect(actions(gamepad)).toEqual({ "Move", "Jump", "Jet pack", "Switch tool", "Swing pick axe" })
		expect(gamepad[#gamepad].key).toBe("RT")
	end)

	it("gives the weapon its fire, reload, and aim rows", function()
		local rows = ControlsRules.rowsFor(makeContext({ tool = Enums.ToolKind.WEAPON }), ControlsRules.Scheme.KEYBOARD)
		expect(actions(rows)).toEqual({ "Move", "Jump", "Jet pack", "Switch tool", "Backpack", "Fire", "Reload", "Aim or secondary" })
	end)

	it("names a gadget's own action and nothing for the Binoculars in hand", function()
		local flare = ControlsRules.rowsFor(makeContext({ tool = Enums.ToolKind.GADGET, gadgetKind = Enums.GadgetKind.FLARE }), ControlsRules.Scheme.KEYBOARD)
		expect(flare[#flare].action).toBe("Fire flare")
		local binoculars = ControlsRules.rowsFor(makeContext({ tool = Enums.ToolKind.GADGET, gadgetKind = Enums.GadgetKind.BINOCULARS }), ControlsRules.Scheme.KEYBOARD)
		expect(binoculars[#binoculars].action).toBe("Backpack")
	end)

	it("a manned post replaces everything, with the tag for the Binoculars", function()
		local rows = ControlsRules.rowsFor(makeContext({ isMounted = true, gadgetKind = Enums.GadgetKind.BINOCULARS }), ControlsRules.Scheme.GAMEPAD)
		expect(actions(rows)).toEqual({ "Aim", "Fire", "Tag a monster", "Leave post" })
		expect(rows[4].key).toBe("B")
	end)

	it("Build Mode has its own rows per scheme", function()
		local keyboard = ControlsRules.rowsFor(makeContext({ isBuildMode = true }), ControlsRules.Scheme.KEYBOARD)
		expect(actions(keyboard)).toEqual({ "Place", "Pan camera", "Zoom", "Rotate", "Cancel", "Pick a defense" })
		local gamepad = ControlsRules.rowsFor(makeContext({ isBuildMode = true }), ControlsRules.Scheme.GAMEPAD)
		expect(actions(gamepad)).toEqual({ "Move defense", "Place", "Cancel" })
	end)

	it("the lobby shows the body alone", function()
		local rows = ControlsRules.rowsFor(makeContext({ place = Enums.PlaceKind.LOBBY, tool = nil }), ControlsRules.Scheme.KEYBOARD)
		expect(actions(rows)).toEqual({ "Move", "Jump", "Jet pack" })
	end)
end)
