--!strict

-- The explicit allowlist of client-callable dev tool commands. Kept free of
-- requires so jest-runtime can load it (it cannot resolve the @game alias).
local DevToolCommands = {}

DevToolCommands.NAMES = {
	"resetPlayerState",
	"sendTestFeedback",
}

local isCommandByName: { [string]: boolean } = {}
for _, name in DevToolCommands.NAMES do
	isCommandByName[name] = true
end

function DevToolCommands.isCommand(name: any): boolean
	return typeof(name) == "string" and isCommandByName[name] == true
end

return DevToolCommands
