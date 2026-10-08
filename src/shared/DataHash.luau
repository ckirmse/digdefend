--!strict

-- A deterministic fingerprint of a data table (M34, 2026-10-08): the run
-- record carries the hash of every GameData table it was played on, so two
-- runs are only averaged together when they were played on the same
-- numbers. The table is walked with its keys sorted, every value written
-- as its type and text, and the text folded through FNV-1a (32-bit), which
-- is cheap in Luau and plenty for telling tuning passes apart. Not a
-- security hash.
local DataHash = {}

local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

-- keys may be numbers or strings; numbers sort first, then strings
local function compareKeys(a: any, b: any): boolean
	local aIsNumber = typeof(a) == "number"
	local bIsNumber = typeof(b) == "number"
	if aIsNumber ~= bIsNumber then
		return aIsNumber
	end
	if aIsNumber then
		return a < b
	end
	return tostring(a) < tostring(b)
end

local function serialiseInto(value: any, parts: { string }, seen: { [any]: boolean })
	local valueType = typeof(value)
	if valueType == "table" then
		if seen[value] then
			table.insert(parts, "<cycle>")
			return
		end
		seen[value] = true
		local keys = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys, compareKeys)
		table.insert(parts, "{")
		for _, key in keys do
			table.insert(parts, typeof(key) .. ":" .. tostring(key) .. "=")
			serialiseInto(value[key], parts, seen)
			table.insert(parts, ";")
		end
		table.insert(parts, "}")
		seen[value] = nil
		return
	end
	if valueType == "function" then
		-- GameData is data only; a function is a mistake, but it must not
		-- make the hash depend on the address
		table.insert(parts, "function")
		return
	end
	table.insert(parts, valueType .. ":" .. tostring(value))
end

-- the canonical text of a value: the same table always gives the same text
function DataHash.serialise(value: any): string
	local parts = {}
	serialiseInto(value, parts, {})
	return table.concat(parts)
end

-- a times b modulo 2^32. The plain product of two 32-bit numbers can
-- reach 2^56, past the 53 bits a double keeps exactly, so the low bits
-- would be wrong; splitting into 16-bit halves keeps every partial
-- product exact
local function multiply32(a: number, b: number): number
	local aLow = a % 65536
	local aHigh = a // 65536
	local bLow = b % 65536
	local bHigh = b // 65536
	local cross = (aLow * bHigh + aHigh * bLow) % 65536
	return (aLow * bLow + cross * 65536) % 4294967296
end

-- FNV-1a over the bytes of a string, as eight hex digits
function DataHash.hashString(text: string): string
	local hash = FNV_OFFSET
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = multiply32(hash, FNV_PRIME)
	end
	return string.format("%08x", hash)
end

function DataHash.hashValue(value: any): string
	return DataHash.hashString(DataHash.serialise(value))
end

-- one fingerprint for a set of named tables (the GameData modules), in
-- name order so the folder's iteration order cannot change it
function DataHash.hashNamed(tablesByName: { [string]: any }): string
	local names = {}
	for name in tablesByName do
		table.insert(names, name)
	end
	table.sort(names)
	local parts = {}
	for _, name in names do
		table.insert(parts, name .. "=" .. DataHash.serialise(tablesByName[name]))
	end
	return DataHash.hashString(table.concat(parts, "\n"))
end

return DataHash
