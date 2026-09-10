-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local DevToolCommands = require(game:GetService("ServerScriptService").Server.DevToolCommands)

describe(
	"DevToolCommands allowlist",
	function()
		it(
			"accepts every listed command name",
			function()
				expect(#DevToolCommands.NAMES).toBeGreaterThan(0)
				for _, name in DevToolCommands.NAMES do
					expect(DevToolCommands.isCommand(name)).toBe(true)
				end
			end
		)

		it(
			"rejects lifecycle methods, unknown names, and non-strings",
			function()
				expect(DevToolCommands.isCommand("init")).toBe(false)
				expect(DevToolCommands.isCommand("handleTryDevTool")).toBe(false)
				expect(DevToolCommands.isCommand("getNetHandlers")).toBe(false)
				expect(DevToolCommands.isCommand("")).toBe(false)
				expect(DevToolCommands.isCommand(nil)).toBe(false)
				expect(DevToolCommands.isCommand(42)).toBe(false)
			end
		)

		it(
			"lists each command once in camelCase",
			function()
				local seen = {}
				for _, name in DevToolCommands.NAMES do
					expect(name).toMatch("^[a-z][A-Za-z0-9]*$")
					expect(seen[name]).toBeNil()
					seen[name] = true
				end
			end
		)
	end
)
