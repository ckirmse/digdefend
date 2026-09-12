-- explicit import required because debug.loadmodule is unavailable in Edit mode,
-- so jest-runtime cannot auto-inject globals into loadstring-loaded modules
local JestGlobals = require(game:GetService("ServerScriptService").Tests.DevPackages.JestGlobals)
local describe = JestGlobals.describe
local it = JestGlobals.it
local expect = JestGlobals.expect

local MineGridCodec = require(game:GetService("ReplicatedStorage").Shared.MineGridCodec)

local function makeCells(): { number }
	-- a shape like a real grid: long solid runs with scattered single cells
	local cells = {}
	local random = Random.new(7)
	for index = 1, 50000 do
		local rock = 18
		if index % 997 == 0 then
			rock = random:NextInteger(1, 17)
		elseif index > 20000 and index < 30000 then
			rock = if index % 2 == 0 then 0 else 1
		end
		cells[index] = rock
	end
	return cells
end

describe(
	"MineGridCodec encode and decode",
	function()
		it(
			"round-trips a grid-shaped cell array",
			function()
				local cells = makeCells()
				local encoded = MineGridCodec.encode(cells)
				local decoded, err = MineGridCodec.decode(encoded)
				expect(err).toBeNil()
				expect(decoded).toEqual(cells)
			end
		)

		it(
			"compresses long runs far below one byte per cell",
			function()
				local cells = table.create(47268, 18)
				local encoded = MineGridCodec.encode(cells)
				expect(buffer.len(encoded)).toBeLessThan(20)
			end
		)

		it(
			"splits runs longer than a u16 can hold",
			function()
				local cells = table.create(70000, 3)
				local decoded, err = MineGridCodec.decode(MineGridCodec.encode(cells))
				expect(err).toBeNil()
				expect(#decoded).toBe(70000)
				expect(decoded[70000]).toBe(3)
			end
		)

		it(
			"handles an empty grid and a single cell",
			function()
				expect(MineGridCodec.decode(MineGridCodec.encode({}))).toEqual({})
				expect(MineGridCodec.decode(MineGridCodec.encode({ 5 }))).toEqual({ 5 })
			end
		)

		it(
			"rejects malformed buffers with a reason",
			function()
				local short = buffer.create(2)
				local cells, err = MineGridCodec.decode(short)
				expect(cells).toBeNil()
				expect(err).toContain("too short")

				local truncated = MineGridCodec.encode({ 1, 1, 2 })
				local cut = buffer.create(buffer.len(truncated) - 1)
				buffer.copy(cut, 0, truncated, 0, buffer.len(cut))
				cells, err = MineGridCodec.decode(cut)
				expect(cells).toBeNil()
				expect(err).toContain("trailing")

				local lying = MineGridCodec.encode({ 1, 1, 2 })
				buffer.writeu32(lying, 0, 5)
				cells, err = MineGridCodec.decode(lying)
				expect(cells).toBeNil()
				expect(err).toContain("declared")
			end
		)
	end
)

describe(
	"MineGridCodec split and join",
	function()
		it(
			"slices into chunks of at most the given size and joins back exactly",
			function()
				local encoded = MineGridCodec.encode(makeCells())
				local chunks = MineGridCodec.split(encoded, 1000)
				expect(#chunks).toBe(math.ceil(buffer.len(encoded) / 1000))
				for index, chunk in chunks do
					if index < #chunks then
						expect(buffer.len(chunk)).toBe(1000)
					else
						expect(buffer.len(chunk)).toBeLessThanOrEqual(1000)
					end
				end
				local joined = MineGridCodec.join(chunks)
				expect(buffer.tostring(joined)).toBe(buffer.tostring(encoded))
			end
		)

		it(
			"produces one chunk when the data fits",
			function()
				local encoded = MineGridCodec.encode({ 1, 2, 3 })
				expect(#MineGridCodec.split(encoded, 4096)).toBe(1)
			end
		)
	end
)
