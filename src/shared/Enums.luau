--!strict

-- An enum table maps SCREAMING_SNAKE_CASE key names to unique integer values, and may also carry a
-- PublicNames sub-table holding the player-facing string for some or all of those keys. Keys with
-- no player-facing name are simply absent from PublicNames, so lookups into it are optional.
--
-- EnumTable is the parameter type for the helpers below. It has to be `any` rather than a table
-- type like `{ [string]: number | PublicNames }`: table indexers are invariant in Luau, so the
-- precise inferred type of a literal like Difficulty (NORMAL: number, ..., PublicNames: {...}) is
-- not assignable to an indexer whose value type is that union. The helpers recover the real types
-- with typeof() guards instead.
export type PublicNames = { [string]: string? }
export type EnumTable = any

local module

module = {
	PlayerLifecycle = {
		LOADING = 1,
		READY = 2,
		LEAVING = 3,
		GONE = 4,
	},
	-- replicated on the Player instance so the loading screen can react before
	-- the CurrentPlayer folder exists
	LoadStatus = {
		LOADING_DATA = 1,
		RETRYING = 2,
		READY = 3,
	},
	PlaceKind = {
		LOBBY = 1,
		GAMEPLAY = 2,
		-- local place files and unpublished Studio sessions have PlaceId 0
		STUDIO = 3,
	},
	Map = {
		DEADMANS_CANYON = 1,
		FROSTBITE_PASS = 2,

		PublicNames = {
			DEADMANS_CANYON = "Deadman's Canyon",
			FROSTBITE_PASS = "Frostbite Pass",
		},
	},
	Difficulty = {
		NORMAL = 1,
		HARD = 2,
		NIGHTMARE = 3,

		PublicNames = {
			NORMAL = "Normal",
			HARD = "Hard",
			NIGHTMARE = "Nightmare",
		},
	},
	RawResource = {
		IRON_ORE = 1,
		GOLD_ORE = 2,
		CRYSTAL = 3,
		URANIUM_ORE = 4,

		PublicNames = {
			IRON_ORE = "Iron Ore",
			GOLD_ORE = "Gold Ore",
			CRYSTAL = "Crystal",
			URANIUM_ORE = "Uranium Ore",
		},
	},
	RefinedResource = {
		IRON_BAR = 1,
		GOLD_BAR = 2,
		DIAMOND = 3,
		URANIUM = 4,

		PublicNames = {
			IRON_BAR = "Iron Bar",
			GOLD_BAR = "Gold Bar",
			DIAMOND = "Diamond",
			URANIUM = "Uranium",
		},
	},
	-- one helicopter pad's party lifecycle (GDD "Helicopter Pads")
	PadState = {
		IDLE = 1,
		CONFIGURING = 2,
		BOARDING = 3,
		DEPARTING = 4,

		PublicNames = {
			IDLE = "Open",
			CONFIGURING = "Setting Up",
			BOARDING = "Now Boarding",
			DEPARTING = "Departing",
		},
	},
	PartyVisibility = {
		PUBLIC = 1,
		FRIENDS_ONLY = 2,

		PublicNames = {
			PUBLIC = "Public",
			FRIENDS_ONLY = "Friends Only",
		},
	},
	RockKind = {
		FILLER = 1,
		RESOURCE = 2,
		BEDROCK = 3,
		GATE = 4,
	},
	-- the five loadout slots carried into a run; keys double as save-data keys
	LoadoutSlot = {
		WEAPON = 1,
		POST = 2,
		DEFENSE_1 = 3,
		DEFENSE_2 = 4,
		DEFENSE_3 = 5,

		PublicNames = {
			WEAPON = "Weapon",
			POST = "Post",
			DEFENSE_1 = "Defense",
			DEFENSE_2 = "Defense",
			DEFENSE_3 = "Defense",
		},
	},

	getCount = function(tbl: EnumTable): number
		if typeof(tbl) ~= "table" then
			warn("first parameter to getCount() needs to be the enum table")
			return 0
		end
		local count = 0
		for _, value in tbl do
			if typeof(value) ~= "number" then
				continue
			end
			count += 1
		end
		return count
	end,
	getAllValues = function(tbl: EnumTable): { number }
		if typeof(tbl) ~= "table" then
			warn("first parameter to getAllValues() needs to be the enum table")
			return {}
		end
		local values = {}
		for _, value in tbl do
			if typeof(value) ~= "number" then
				continue
			end
			table.insert(values, value)
		end
		table.sort(values)
		return values
	end,
	isValidValue = function(tbl: EnumTable, value: any): boolean
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums isValidValue() needs to be the enum table")
			return false
		end
		for _, enumValue in tbl do
			if typeof(enumValue) ~= "number" then
				continue
			end
			if enumValue == value then
				return true
			end
		end
		return false
	end,
	getName = function(tbl: EnumTable, value: any): string?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getName() needs to be the enum table")
			return nil
		end
		for key, enumValue in tbl do
			if typeof(enumValue) ~= "number" then
				continue
			end
			if enumValue == value then
				return key
			end
		end
		warn("invalid enum to getName " .. tostring(value))
		return nil
	end,
	getValueByName = function(tbl: EnumTable, name: string): number?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getValueByName() needs to be the enum table")
			return nil
		end
		local value = tbl[name]
		if typeof(value) == "number" then
			return value
		end
		warn("invalid enum to getValueByName " .. tostring(name))
		return nil
	end,
	getPublicName = function(tbl: EnumTable, value: any): string?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getPublicName() needs to be the enum table")
			return nil
		end
		if value == nil then
			return nil
		end
		local key = nil
		for candidateKey, enumValue in tbl do
			if typeof(enumValue) == "number" and enumValue == value then
				key = candidateKey
				break
			end
		end
		if key == nil then
			warn("invalid enum to getPublicName " .. tostring(value))
			return nil
		end
		if not tbl.PublicNames then
			warn("enum table has no public names, including for key " .. key)
			return nil
		end
		return tbl.PublicNames[key]
	end,
}

return module
