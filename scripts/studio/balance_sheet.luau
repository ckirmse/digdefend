-- Prints the balance sheet without starting Play (docs/balance-plan.md):
-- loads BalanceAudit and everything it requires through a substitute
-- require, since the Studio MCP thread cannot require() a ModuleScript,
-- then prints every missed target and the sheet for the SHEETS below.
-- Run through the Studio MCP execute_luau in the Edit datamodel after a
-- GameData edit has synced; the Output is the result.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- { map, difficulty, crew } sheets to print in full
local SHEETS = {
	{ 1, 1, 1 },
	{ 1, 1, 4 },
	{ 1, 2, 1 },
	{ 1, 3, 1 },
}

local ROOTS = {
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
}

local cache = {}

local function resolvePath(path)
	local rootName, rest = string.match(path, "^@game/([^/]+)/(.+)$")
	if rootName == nil then
		error("balance_sheet: cannot resolve require path " .. tostring(path))
	end
	local instance = ROOTS[rootName]
	for name in string.gmatch(rest, "[^/]+") do
		instance = instance:FindFirstChild(name)
		if instance == nil then
			error("balance_sheet: missing " .. path .. " at " .. name)
		end
	end
	return instance
end

local function substituteRequire(target)
	local module = if typeof(target) == "string" then resolvePath(target) else target
	if cache[module] ~= nil then
		return cache[module]
	end
	local environment = setmetatable({ script = module, require = substituteRequire }, { __index = getfenv(0) })
	local chunk, compileError = loadstring(module.Source, "=" .. module:GetFullName())
	if chunk == nil then
		error("balance_sheet: " .. tostring(compileError))
	end
	setfenv(chunk, environment)
	local result = chunk()
	cache[module] = result
	return result
end

local BalanceAudit = substituteRequire("@game/ServerScriptService/Gameplay/BalanceAudit")

local failures = BalanceAudit:auditAll()
print(string.format("[balance_sheet] %d target(s) missed%s", #failures, if #failures > 0 then ":\n  " .. table.concat(failures, "\n  ") else ""))
for _, sheet in SHEETS do
	print("[balance_sheet]\n" .. table.concat(BalanceAudit:describe(sheet[1], sheet[2], sheet[3]), "\n"))
end
return string.format("%d missed", #failures)
