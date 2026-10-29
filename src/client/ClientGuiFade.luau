--!strict

-- Fades a whole gui tree out (2026-10-27): every element's transparency
-- properties ease to 1 together, then the caller is told so it can
-- disable the gui, and the authored values are put back underneath so the
-- gui shows whole the next time it is enabled. Used for the radio's
-- billboard when the rescue is called and for the HUD when the crew is
-- all aboard. Code only ever sets values on the designer's instances.
local TweenService = game:GetService("TweenService")

local ClientGuiFade = {}

-- what hide() took away: each element's authored transparencies, to be
-- given back by reveal() a branch at a time or restore() all at once
export type Hidden = { [Instance]: { [string]: number } }

-- the transparency properties an element fades by
local TRANSPARENCY_PROPERTIES_BY_CLASS: { [string]: { string } } = {
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextBox = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	Frame = { "BackgroundTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	CanvasGroup = { "GroupTransparency" },
	UIStroke = { "Transparency" },
}

-- fades root's elements out over fadeSec; onDone runs at the end, before
-- the authored values go back (disable the gui there, or it shows whole
-- again). An element already fully transparent is left alone
function ClientGuiFade.fadeOut(root: Instance, fadeSec: number, onDone: (() -> ())?)
	local authoredByInstance: { [Instance]: { [string]: number } } = {}
	for _, descendant in root:GetDescendants() do
		local properties = TRANSPARENCY_PROPERTIES_BY_CLASS[descendant.ClassName]
		if not properties then
			continue
		end
		local authored = {}
		local goal = {}
		for _, property in properties do
			local value = (descendant :: any)[property]
			if typeof(value) == "number" and value < 1 then
				authored[property] = value
				goal[property] = 1
			end
		end
		if next(goal) == nil then
			continue
		end
		authoredByInstance[descendant] = authored
		TweenService:Create(descendant, TweenInfo.new(fadeSec, Enum.EasingStyle.Linear), goal):Play()
	end
	task.delay(
		fadeSec,
		function()
			if onDone then
				onDone()
			end
			for instance, authored in authoredByInstance do
				for property, value in authored do
					(instance :: any)[property] = value
				end
			end
		end
	)
end

-- the reverse: root's elements start fully transparent and ease back to
-- their authored values over fadeSec (the Results Menu arriving at the
-- end of the ride out, 2026-10-27); root should be enabled already
function ClientGuiFade.fadeIn(root: Instance, fadeSec: number)
	for _, descendant in root:GetDescendants() do
		local properties = TRANSPARENCY_PROPERTIES_BY_CLASS[descendant.ClassName]
		if not properties then
			continue
		end
		local goal = {}
		for _, property in properties do
			local value = (descendant :: any)[property]
			if typeof(value) == "number" and value < 1 then
				goal[property] = value;
				(descendant :: any)[property] = 1
			end
		end
		if next(goal) ~= nil then
			TweenService:Create(descendant, TweenInfo.new(fadeSec, Enum.EasingStyle.Linear), goal):Play()
		end
	end
end

-- the staged reveal (the death menu, 2026-10-28): hide() makes root and
-- everything under it fully transparent and remembers what it was, so the
-- caller can reveal() one branch after another in its own order
function ClientGuiFade.hide(root: Instance): Hidden
	local hidden: Hidden = {}
	local instances = root:GetDescendants()
	table.insert(instances, root)
	for _, instance in instances do
		local properties = TRANSPARENCY_PROPERTIES_BY_CLASS[instance.ClassName]
		if not properties then
			continue
		end
		local authored = {}
		for _, property in properties do
			local value = (instance :: any)[property]
			if typeof(value) == "number" and value < 1 then
				authored[property] = value;
				(instance :: any)[property] = 1
			end
		end
		if next(authored) ~= nil then
			hidden[instance] = authored
		end
	end
	return hidden
end

-- eases root and everything under it back to the authored values hide()
-- remembered, over fadeSec (at once when 0), and forgets them; isRootOnly
-- brings back root alone, leaving its children hidden for a later stage
function ClientGuiFade.reveal(hidden: Hidden, root: Instance, fadeSec: number, isRootOnly: boolean?)
	for instance, authored in hidden do
		if instance ~= root and (isRootOnly or not instance:IsDescendantOf(root)) then
			continue
		end
		hidden[instance] = nil
		if fadeSec <= 0 then
			for property, value in authored do
				(instance :: any)[property] = value
			end
			continue
		end
		TweenService:Create(instance, TweenInfo.new(fadeSec, Enum.EasingStyle.Linear), authored):Play()
	end
end

-- everything still hidden goes back at once (the menu closing mid-reveal)
function ClientGuiFade.restore(hidden: Hidden)
	for instance, authored in hidden do
		hidden[instance] = nil
		for property, value in authored do
			(instance :: any)[property] = value
		end
	end
end

return ClientGuiFade
