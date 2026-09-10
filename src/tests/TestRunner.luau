--!strict

-- Run from the Studio Command Bar in Edit mode with:
--   task.spawn(function() loadstring(game.ServerScriptService.Tests.TestRunner.Source)():run() end) return "running"
-- loadstring bypasses the module cache so edits to this file take effect without restarting Studio.

local ServerScriptService = game:GetService("ServerScriptService")

local TestRunner = {}

function TestRunner:run()
	task.spawn(
		function()
			local devPackages = ServerScriptService.Tests.DevPackages

			-- Emittery:emit() waits on Promise.delay(1/60), which never resolves under
			-- the Edit-mode scheduler, so the event-emitter path must be switched off
			local Runner = require(devPackages._Index["jsdotlua_jest-runner@3.10.0"]["jest-runner"]).default
			local originalNew = Runner.new
			Runner.new = function(self, ...)
				local instance = originalNew(self, ...)
				instance.__PRIVATE_UNSTABLE_API_supportsEventEmitters__ = false
				return instance
			end

			local Jest = require(devPackages.Jest)
			local isSuccess, err = pcall(
				function()
					Jest.runCLI(ServerScriptService, {}, { ServerScriptService.Tests.Shared }):expect()
				end
			)
			if not isSuccess then
				warn("TestRunner error: " .. tostring(err))
			end
		end
	)
end

return TestRunner
