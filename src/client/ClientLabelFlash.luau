--!strict

-- Flashes a label's text colour a few times and puts the authored colour
-- back (a balance the player cannot cover, designer 2026-11-04). The
-- rest colour is remembered per label on the first flash, so a flash
-- started over a running one does not learn red as the rest; a newer
-- flash cancels the older through a generation per label.
local UiStyle = require("@game/ReplicatedStorage/Shared/UiStyle")

local ClientLabelFlash = {}

local generationByLabel: { [TextLabel]: number } = setmetatable({}, { __mode = "k" }) :: any
local restColorByLabel: { [TextLabel]: Color3 } = setmetatable({}, { __mode = "k" }) :: any

function ClientLabelFlash.flash(label: TextLabel, color: Color3, count: number, onSec: number)
	local restColor = restColorByLabel[label]
	if not restColor then
		restColor = label.TextColor3
		restColorByLabel[label] = restColor
	end
	local generation = (generationByLabel[label] or 0) + 1
	generationByLabel[label] = generation
	task.spawn(
		function()
			for _ = 1, count do
				if generationByLabel[label] ~= generation then
					return
				end
				label.TextColor3 = color
				task.wait(onSec)
				if generationByLabel[label] ~= generation then
					return
				end
				label.TextColor3 = restColor
				task.wait(onSec)
			end
		end
	)
end

function ClientLabelFlash.flashRed(label: TextLabel)
	ClientLabelFlash.flash(label, UiStyle.NEGATIVE_COLOR, UiStyle.BALANCE_SHORT_FLASH_COUNT, UiStyle.BALANCE_SHORT_FLASH_SEC)
end

return ClientLabelFlash
