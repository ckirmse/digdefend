-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local DataHash = require(game:GetService("ReplicatedStorage").Shared.DataHash)

describe(
	"DataHash",
	function()
		it(
			"serialises a table the same way whatever the insertion order",
			function()
				local a = { gold = 2, iron = 1, zones = { { depth = 8 }, { depth = 12 } } }
				local b = { zones = { { depth = 8 }, { depth = 12 } }, iron = 1, gold = 2 }
				expect(DataHash.serialise(a)).toBe(DataHash.serialise(b))
				expect(DataHash.hashValue(a)).toBe(DataHash.hashValue(b))
			end
		)
		it(
			"changes when a number, a key, or a type changes",
			function()
				local base = DataHash.hashValue({ gold = 90, hardness = 1.0 })
				expect(DataHash.hashValue({ gold = 120, hardness = 1.0 })).never.toBe(base)
				expect(DataHash.hashValue({ gold = 90, hardness = 1.0, iron = 0 })).never.toBe(base)
				expect(DataHash.hashValue({ gold = "90", hardness = 1.0 })).never.toBe(base)
			end
		)
		it(
			"is eight hex digits and matches the FNV-1a test vectors",
			function()
				expect(DataHash.hashString("")).toBe("811c9dc5")
				expect(DataHash.hashString("a")).toBe("e40c292c")
				expect(DataHash.hashString("foobar")).toBe("bf9cf968")
			end
		)
		it(
			"survives cycles and ignores function addresses",
			function()
				local a: any = { name = "x" }
				a.self = a
				local first = DataHash.hashValue(a)
				expect(DataHash.hashValue(a)).toBe(first)
				local withFunction = { f = function() end }
				local other = { f = function() end }
				expect(DataHash.hashValue(withFunction)).toBe(DataHash.hashValue(other))
			end
		)
		it(
			"fingerprints a set of named tables in name order",
			function()
				local first = DataHash.hashNamed({ ["Mines/A"] = { gold = 1 }, ["Control/B"] = { x = 2 } })
				local second = DataHash.hashNamed({ ["Control/B"] = { x = 2 }, ["Mines/A"] = { gold = 1 } })
				expect(first).toBe(second)
				expect(DataHash.hashNamed({ ["Mines/A"] = { gold = 2 }, ["Control/B"] = { x = 2 } })).never.toBe(first)
			end
		)
	end
)
