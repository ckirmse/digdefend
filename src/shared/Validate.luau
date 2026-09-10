--!strict

-- instance-path require (not @game string) so jest-runtime can load this module
local Enums = require(script.Parent.Enums)

local Validate = {}

-- beyond 2^53 a double can't represent consecutive integers, and every integer
-- field is an index or a count; huge values are always garbage or an attack
local MAX_SAFE_INTEGER = 9007199254740991
-- every string field is an id or a short name; the cap keeps a hostile client
-- from spending our bandwidth and log space for free
local MAX_STRING_LENGTH = 4096

function Validate.isBoolean(value: any): boolean
	return typeof(value) == "boolean"
end

function Validate.isNumber(value: any): boolean
	return typeof(value) == "number"
end

-- NaN passes both `< 0` and `<= 0` as false, so the ordered comparisons in the
-- number validators can't be trusted on their own
function Validate.isFiniteNumber(value: any): boolean
	return Validate.isNumber(value) and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isInteger(value: any): boolean
	return Validate.isFiniteNumber(value) and (value % 1) == 0 and math.abs(value) <= MAX_SAFE_INTEGER
end

function Validate.isString(value: any): boolean
	return typeof(value) == "string"
end

function Validate.isTable(value: any): boolean
	return typeof(value) == "table"
end

function Validate.isTableBelowSize(value: any, size: number): boolean
	if not Validate.isTable(value) then
		return false
	end
	local count = 0
	for _ in value do
		count += 1
		if count > size then
			return false
		end
	end
	return true
end

function Validate.isArray(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end
	local count = 0
	for _ in value do
		count += 1
	end
	return count == #value
end

function Validate.isTableShape(value: any, shape: any): (boolean, string?)
	if typeof(shape) ~= "table" then
		warn("validation data invalid: shape is not a table:", shape)
		return false, string.format("validation data invalid: non-table shape %s", tostring(shape))
	end

	if not Validate.isTable(value) then
		return false, string.format("%s not a table", tostring(value))
	end

	for key, shapeValue in shape do
		local isValid, err = Validate.isValueType(value[key], shapeValue)
		if not isValid then
			return false, string.format("table key %s invalid; %s", tostring(key), tostring(err))
		end
	end

	for key in value do
		if shape[key] == nil then
			return false, string.format("table extra key %s", tostring(key))
		end
	end

	return true, nil
end

-- testType is either a type name string ("boolean", "number", "nonnegativeNumber",
-- "positiveNumber", "integer", "nonnegativeInteger", "positiveInteger", "string",
-- "table") or a spec table: { type = <name>, optional = true },
-- { type = "table", shape = <shape>, nonempty = true },
-- { type = "array", elementType = <testType>, nonempty = true, length = <n> },
-- { type = "enum", name = "<Enums key>" }, or a bare shape table with no type field.
function Validate.isValueType(value: any, testType: any): (boolean, string?)
	if typeof(testType) == "table" then
		if testType.type then
			if testType.optional and value == nil then
				return true, nil
			end
			if testType.type == "table" then
				if not Validate.isTable(value) then
					return false, string.format("%s not a table", tostring(value))
				end
				local shape = testType.shape
				if shape then
					local isValid, err = Validate.isTableShape(value, shape)
					if not isValid then
						return false, string.format("%s not table shape; %s", tostring(value), tostring(err))
					end
				end
				if testType.nonempty and not next(value) then
					return false, string.format("%s not non-empty table", tostring(value))
				end
			elseif testType.type == "array" then
				if not Validate.isArray(value) then
					return false, string.format("%s not array", tostring(value))
				end
				if testType.nonempty and #value == 0 then
					return false, string.format("%s not non-empty array", tostring(value))
				end
				if testType.length and #value ~= testType.length then
					return false, string.format("%s not fixed length %i array", tostring(value), testType.length :: number)
				end
				local elementType = testType.elementType
				for index = 1, #value do
					local isValid, err = Validate.isValueType(value[index], elementType)
					if not isValid then
						return false, string.format("%s entry %i invalid; %s", tostring(value), index, tostring(err))
					end
				end
			elseif testType.type == "enum" then
				local enumName = testType.name
				local enumTable = (Enums :: any)[enumName]
				if not enumTable then
					return false, string.format("validation data invalid: unknown enum name %s", tostring(enumName))
				end
				if not Enums.isValidValue(enumTable, value) then
					return false, string.format("%s not valid value of enum type %s", tostring(value), tostring(enumName))
				end
			else
				return Validate.isValueType(value, testType.type)
			end
		else
			local isValid, err = Validate.isTableShape(value, testType)
			if not isValid then
				return false, string.format("%s not table shape; %s", tostring(value), tostring(err))
			end
		end
	elseif testType == "boolean" then
		if not Validate.isBoolean(value) then
			return false, string.format("%s not a boolean", tostring(value))
		end
	elseif testType == "number" then
		if not Validate.isFiniteNumber(value) then
			return false, string.format("%s not a number", tostring(value))
		end
	elseif testType == "nonnegativeNumber" then
		if not Validate.isFiniteNumber(value) then
			return false, string.format("%s not a number, no less nonnegativeNumber", tostring(value))
		end
		if value < 0 then
			return false, string.format("%s not a nonnegativeNumber", tostring(value))
		end
	elseif testType == "positiveNumber" then
		if not Validate.isFiniteNumber(value) then
			return false, string.format("%s not a number, no less positiveNumber", tostring(value))
		end
		if value <= 0 then
			return false, string.format("%s not a positiveNumber", tostring(value))
		end
	elseif testType == "integer" then
		if not Validate.isInteger(value) then
			return false, string.format("%s not an integer", tostring(value))
		end
	elseif testType == "nonnegativeInteger" then
		if not Validate.isInteger(value) then
			return false, string.format("%s not an integer, no less nonnegativeInteger", tostring(value))
		end
		if value < 0 then
			return false, string.format("%s not a nonnegativeInteger", tostring(value))
		end
	elseif testType == "positiveInteger" then
		if not Validate.isInteger(value) then
			return false, string.format("%s not an integer, no less positiveInteger", tostring(value))
		end
		if value <= 0 then
			return false, string.format("%s not a positiveInteger", tostring(value))
		end
	elseif testType == "string" then
		if not Validate.isString(value) then
			return false, string.format("%s not a string", tostring(value))
		end
		if #value > MAX_STRING_LENGTH then
			return false, string.format("string of length %i over the %i cap", #value, MAX_STRING_LENGTH)
		end
	elseif testType == "table" then
		if not Validate.isTable(value) then
			return false, string.format("%s not a table", tostring(value))
		end
	else
		warn("isValueType given unknown test type", testType)
		return false, string.format("validation data invalid: unknown test type %s", tostring(testType))
	end

	return true, nil
end

return Validate
