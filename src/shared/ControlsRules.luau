--!strict

-- The controls panel's words (2026-11-09): which input scheme a player is
-- on, and the rows of key and action that apply to what they are doing
-- right now, so the panel in the corner reads the same on every client
-- and the list lives in one place. Pure; unit tested. The keys named here
-- are the ones the client managers listen for (ClientJetPackManager,
-- ClientToolBarManager, ClientMiningManager, ClientWeaponManager,
-- ClientPostManager, ClientDefenseTableManager, the gadget managers);
-- change a binding there and here together.
local Enums = require(script.Parent.Enums)

local ControlsRules = {}

ControlsRules.Scheme = {
	KEYBOARD = 1,
	GAMEPAD = 2,
}

export type Row = {
	key: string,
	action: string,
}

export type Context = {
	place: number,
	-- Enums.ToolKind in hand; nil for none (the lobby, a dead player)
	tool: number?,
	-- Enums.GadgetKind the class carries; nil for none
	gadgetKind: number?,
	isMounted: boolean,
	isBuildMode: boolean,
}

local GAMEPAD_INPUT_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
	[Enum.UserInputType.Gamepad5] = true,
	[Enum.UserInputType.Gamepad6] = true,
	[Enum.UserInputType.Gamepad7] = true,
	[Enum.UserInputType.Gamepad8] = true,
}

-- the scheme the panel shows for, from the last input used and what the
-- device has; nil hides the panel (a touch device, whose buttons are on
-- screen already)
function ControlsRules.schemeFor(lastInputType: Enum.UserInputType?, isKeyboardEnabled: boolean, isGamepadEnabled: boolean): number?
	if lastInputType and GAMEPAD_INPUT_TYPES[lastInputType] then
		return ControlsRules.Scheme.GAMEPAD
	end
	if lastInputType == Enum.UserInputType.Touch then
		return nil
	end
	if isKeyboardEnabled then
		return ControlsRules.Scheme.KEYBOARD
	end
	if isGamepadEnabled then
		return ControlsRules.Scheme.GAMEPAD
	end
	return nil
end

-- one row, the key by scheme
local function row(keyboardKey: string, gamepadKey: string, action: string, scheme: number): Row
	return {
		key = if scheme == ControlsRules.Scheme.GAMEPAD then gamepadKey else keyboardKey,
		action = action,
	}
end

local GADGET_ACTIONS: { [number]: string } = {
	[Enums.GadgetKind.AUTO_TURRET] = "Place turret",
	[Enums.GadgetKind.REMOTE_CHARGE] = "Place or detonate",
	[Enums.GadgetKind.FLARE] = "Fire flare",
	[Enums.GadgetKind.STIM_SHOT] = "Use Stim Shot",
	[Enums.GadgetKind.ORE_SCANNER] = "Scan for ore",
	[Enums.GadgetKind.DYNAMITE] = "Throw dynamite",
}

-- what a held tool does on the trigger; nil for a tool with no trigger
local function toolTriggerAction(context: Context): string?
	local tool = context.tool
	if tool == Enums.ToolKind.PICK_AXE then
		return "Swing pick axe"
	elseif tool == Enums.ToolKind.HAMMER then
		return "Repair"
	elseif tool == Enums.ToolKind.TORCH then
		return "Place torch"
	elseif tool == Enums.ToolKind.DYNAMITE then
		return "Throw dynamite"
	elseif tool == Enums.ToolKind.GADGET then
		local gadgetKind = context.gadgetKind
		if gadgetKind == Enums.GadgetKind.BINOCULARS or gadgetKind == nil or gadgetKind == Enums.GadgetKind.NONE then
			return nil
		end
		return GADGET_ACTIONS[gadgetKind] or "Use gadget"
	end
	return nil
end

-- the rows for the moment, most specific state first: a manned post, then
-- Build Mode, then the tool in hand, then the body
function ControlsRules.rowsFor(context: Context, scheme: number): { Row }
	local rows: { Row } = {}
	if context.isMounted then
		table.insert(rows, row("MOUSE", "RIGHT STICK", "Aim", scheme))
		table.insert(rows, row("LMB", "RT", "Fire", scheme))
		if context.gadgetKind == Enums.GadgetKind.BINOCULARS then
			table.insert(rows, row("RMB", "LT", "Tag a monster", scheme))
		end
		table.insert(rows, row("BACKSPACE", "B", "Leave post", scheme))
		return rows
	end
	if context.isBuildMode then
		if scheme == ControlsRules.Scheme.GAMEPAD then
			table.insert(rows, row("", "LEFT STICK", "Move defense", scheme))
			table.insert(rows, row("", "A", "Place", scheme))
			table.insert(rows, row("", "B", "Cancel", scheme))
		else
			table.insert(rows, row("LMB", "", "Place", scheme))
			table.insert(rows, row("HOLD RMB", "", "Pan camera", scheme))
			table.insert(rows, row("WHEEL", "", "Zoom", scheme))
			table.insert(rows, row("R", "", "Rotate", scheme))
			table.insert(rows, row("Q", "", "Cancel", scheme))
			table.insert(rows, row("1-9", "", "Pick a defense", scheme))
		end
		return rows
	end
	table.insert(rows, row("W A S D", "LEFT STICK", "Move", scheme))
	table.insert(rows, row("SPACE", "A", "Jump", scheme))
	table.insert(rows, row("HOLD SPACE", "HOLD A", "Jet pack", scheme))
	if context.place == Enums.PlaceKind.GAMEPLAY then
		table.insert(rows, row("1-9", "LB / RB", "Switch tool", scheme))
		if scheme == ControlsRules.Scheme.KEYBOARD then
			table.insert(rows, row("B", "", "Backpack", scheme))
		end
		if context.tool == Enums.ToolKind.WEAPON then
			table.insert(rows, row("LMB", "RT", "Fire", scheme))
			table.insert(rows, row("R", "X", "Reload", scheme))
			table.insert(rows, row("RMB", "LT", "Aim or secondary", scheme))
		else
			local action = toolTriggerAction(context)
			if action then
				table.insert(rows, row("LMB", "RT", action, scheme))
			end
		end
	end
	return rows
end

return ControlsRules
