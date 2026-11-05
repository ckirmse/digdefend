--!strict

-- The shape of a player's one cosmetic loadout (designer, 2026-11-04:
-- cosmetics belong to the account, not to a class, so every class is
-- played in the same hat, pick axe, and jet pack). A map of
-- Enums.CosmeticSlot key name to skin id, on the save as `cosmetics`.
-- Pure, like PlayerSaveSchema: defaults in, a repaired loadout out, so
-- every rule is unit tested and PlayerData stays thin.
local HttpService = game:GetService("HttpService")

local Enums = require(script.Parent.Enums)

local CosmeticLoadoutSchema = {}

-- Enums.CosmeticSlot key name -> skin id
export type Loadout = { [string]: string }

export type Repair = string

-- the skin id that means "no skin here, the player's own look": stored on
-- purpose so a cleared slot is told apart from one that was never set
CosmeticLoadoutSchema.OWN_HAT_ID = "OWN_HAT"
-- the stock art of a slot (the pick axe, the jet pack); saved explicitly
-- so a pick is a pick (designer, 2026-10-13)
CosmeticLoadoutSchema.DEFAULT_SKIN_ID = "DEFAULT"

-- a fresh copy of the skins a new account wears
function CosmeticLoadoutSchema.getDefault(defaultCosmetics: Loadout): Loadout
	return table.clone(defaultCosmetics)
end

-- repairs a loadout in place and returns it: a non-table becomes the
-- default, an unknown slot or a blank id is dropped, a missing default
-- slot is filled. `prefix` names the field in repair messages
function CosmeticLoadoutSchema.validate(loadout: any, defaultCosmetics: Loadout, prefix: string, repairs: { Repair }): Loadout
	if typeof(loadout) ~= "table" then
		table.insert(repairs, prefix .. "reset")
		return CosmeticLoadoutSchema.getDefault(defaultCosmetics)
	end
	for key, value in loadout do
		if typeof(key) == "string" and Enums.getValueByName(Enums.CosmeticSlot, key) ~= nil and typeof(value) == "string" and value ~= "" then
			continue
		end
		loadout[key] = nil
		table.insert(repairs, prefix .. "dropped slot " .. tostring(key))
	end
	for key, skinId in defaultCosmetics do
		if loadout[key] == nil then
			loadout[key] = skinId
			table.insert(repairs, prefix .. key .. " set to default")
		end
	end
	return loadout
end

-- the loadout travels to the client as one JSON attribute
function CosmeticLoadoutSchema.encode(loadout: Loadout): string
	return HttpService:JSONEncode(loadout)
end

function CosmeticLoadoutSchema.decode(encoded: any): Loadout
	local loadout: Loadout = {}
	if typeof(encoded) ~= "string" or encoded == "" then
		return loadout
	end
	local isSuccess, decoded = pcall(
		function()
			return HttpService:JSONDecode(encoded)
		end
	)
	if not isSuccess or typeof(decoded) ~= "table" then
		return loadout
	end
	for key, value in decoded do
		if typeof(key) == "string" and typeof(value) == "string" then
			loadout[key] = value
		end
	end
	return loadout
end

return CosmeticLoadoutSchema
