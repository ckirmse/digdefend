--!strict

-- Dev tool for the run report (M34): prints everything the report has so
-- far to the server Output, today included, without waiting for a dawn.
local DevTools = require(script.Parent.Parent.Server.DevTools)
local RunReportManager = require(script.Parent.RunReportManager)

local RunReportDevTools = {}
RunReportDevTools.__index = RunReportDevTools

export type RunReportDevTools = typeof(setmetatable({} :: {}, RunReportDevTools))

RunReportDevTools.PRINT_RUN_REPORT_COMMAND = "printRunReport"

function RunReportDevTools:init()
	DevTools:registerPlaceCommand(
		RunReportDevTools.PRINT_RUN_REPORT_COMMAND,
		function(_player: Player, _args: { [string]: any })
			RunReportManager:printNow()
		end
	)
end

function RunReportDevTools.new(): RunReportDevTools
	local self = setmetatable({}, RunReportDevTools) :: RunReportDevTools
	return self
end

return RunReportDevTools.new()
