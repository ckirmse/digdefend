--!strict

-- Packs a mine grid's cells for the wire. Cells are run-length encoded into a
-- buffer (rock byte, run length u16), which turns the mostly-solid grid into a
-- few kilobytes, then sliced into chunks so a low-bandwidth phone receives
-- the mine over several frames instead of one burst. Pure and unit tested;
-- the server encodes, the client decodes.
local MineGridCodec = {}

local CELL_COUNT_BYTES = 4
local RUN_BYTES = 3
local MAX_RUN_LENGTH = 65535

-- cells -> buffer of [u32 cellCount][u8 rock, u16 runLength]...
function MineGridCodec.encode(cells: { number }): buffer
	local cellCount = #cells
	-- worst case is one run per cell; trimmed to the used size at the end
	local scratch = buffer.create(CELL_COUNT_BYTES + cellCount * RUN_BYTES)
	buffer.writeu32(scratch, 0, cellCount)
	local offset = CELL_COUNT_BYTES
	local index = 1
	while index <= cellCount do
		local rock = cells[index]
		local runLength = 1
		while index + runLength <= cellCount and cells[index + runLength] == rock and runLength < MAX_RUN_LENGTH do
			runLength += 1
		end
		buffer.writeu8(scratch, offset, rock)
		buffer.writeu16(scratch, offset + 1, runLength)
		offset += RUN_BYTES
		index += runLength
	end
	local encoded = buffer.create(offset)
	buffer.copy(encoded, 0, scratch, 0, offset)
	return encoded
end

-- buffer -> cells; returns nil and a reason when the data is malformed
function MineGridCodec.decode(encoded: buffer): ({ number }?, string?)
	local length = buffer.len(encoded)
	if length < CELL_COUNT_BYTES then
		return nil, "buffer too short for a cell count"
	end
	local cellCount = buffer.readu32(encoded, 0)
	local cells = table.create(cellCount, 0)
	local offset = CELL_COUNT_BYTES
	local index = 1
	while offset + RUN_BYTES <= length do
		local rock = buffer.readu8(encoded, offset)
		local runLength = buffer.readu16(encoded, offset + 1)
		if index + runLength - 1 > cellCount then
			return nil, "runs exceed the declared cell count"
		end
		for cell = index, index + runLength - 1 do
			cells[cell] = rock
		end
		index += runLength
		offset += RUN_BYTES
	end
	if offset ~= length then
		return nil, "trailing bytes after the last run"
	end
	if index - 1 ~= cellCount then
		return nil, "runs cover " .. (index - 1) .. " cells but " .. cellCount .. " were declared"
	end
	return cells, nil
end

function MineGridCodec.split(encoded: buffer, chunkBytes: number): { buffer }
	local chunks: { buffer } = {}
	local length = buffer.len(encoded)
	local offset = 0
	repeat
		local size = math.min(chunkBytes, length - offset)
		local chunk = buffer.create(size)
		buffer.copy(chunk, 0, encoded, offset, size)
		table.insert(chunks, chunk)
		offset += size
	until offset >= length
	return chunks
end

function MineGridCodec.join(chunks: { buffer }): buffer
	local total = 0
	for _, chunk in chunks do
		total += buffer.len(chunk)
	end
	local joined = buffer.create(total)
	local offset = 0
	for _, chunk in chunks do
		buffer.copy(joined, offset, chunk, 0, buffer.len(chunk))
		offset += buffer.len(chunk)
	end
	return joined
end

return MineGridCodec
