--!strict

-- Pure rules for dynamite (GDD "Mining Tools"): which grid cells a blast
-- centred on a cell reaches. A radius of 1 block clears the 3x3x3 cube
-- around the stick; cells outside the grid are skipped. Callers decide what
-- each cell contains.
local DynamiteRules = {}

export type Cell = {
	depth: number,
	height: number,
	width: number,
}

function DynamiteRules.cellsInBlast(centreDepth: number, centreHeight: number, centreWidth: number, radiusBlocks: number, gridDepth: number, gridHeight: number, gridWidth: number): { Cell }
	local cells: { Cell } = {}
	local radius = math.max(math.floor(radiusBlocks), 0)
	for depth = centreDepth - radius, centreDepth + radius do
		if depth < 0 or depth >= gridDepth then
			continue
		end
		for height = centreHeight - radius, centreHeight + radius do
			if height < 0 or height >= gridHeight then
				continue
			end
			for width = centreWidth - radius, centreWidth + radius do
				if width < 0 or width >= gridWidth then
					continue
				end
				table.insert(cells, { depth = depth, height = height, width = width })
			end
		end
	end
	return cells
end

return DynamiteRules
