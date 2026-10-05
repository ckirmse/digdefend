-- Adds a stand-in Cemetery to every map that does not have one yet (GDD
-- "Health and Revives", M32): a Folder named Cemetery holding a Plots
-- folder of six invisible anchored parts named 1 to 6, in a row. A dead
-- player's grave (GameAssets.Grave) is laid with its Ground on the lowest
-- free plot and a revived player appears on it. Deadman's Canyon has the
-- designer's own Cemetery (fenced, with plots the size of the grave's
-- Ground); this only keeps a map without one playable.
-- A first position is taken beside the map's HelicopterPad; a map that
-- already has a Cemetery is left exactly as the designer placed it.
-- Works on a map wherever it is (ServerStorage/Maps or loaded into
-- Workspace by map_tools.luau). Run from the Studio command bar (or the
-- MCP execute_luau tool) in the gameplay place. Names must match
-- Constants.CAMP_CEMETERY_FOLDER / CEMETERY_PLOTS_FOLDER.
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local Enums = require(game.ReplicatedStorage.Shared.Enums)

-- where the row starts, in the helicopter pad's own space (studs to its
-- right, up, and back), and how far apart the plots stand
local FIRST_PLOT_OFFSET = Vector3.new(30, 0, -15)
local PLOT_SPACING_STUDS = 6
local PLOT_SIZE = Vector3.new(4, 0.2, 4)

ChangeHistoryService:SetWaypoint("Before cemetery")

local function findMap(mapName)
	local maps = ServerStorage:FindFirstChild(Constants.MAPS_FOLDER)
	return (maps and maps:FindFirstChild(mapName)) or workspace:FindFirstChild(mapName)
end

local built = {}
for _, map in Enums.getAllValues(Enums.Map) do
	local mapName = Enums.getName(Enums.Map, map)
	local folder = findMap(mapName)
	if not folder then
		warn("build_cemetery: no map folder named " .. mapName)
		continue
	end
	if folder:FindFirstChild(Constants.CAMP_CEMETERY_FOLDER) then
		print("build_cemetery: " .. mapName .. " already has a Cemetery; left as it is")
		continue
	end
	local pad = folder:FindFirstChild(Constants.CAMP_HELICOPTER_PAD_MODEL)
	if not pad or not pad:IsA("Model") then
		warn("build_cemetery: " .. mapName .. " has no HelicopterPad to place the Cemetery beside")
		continue
	end
	-- the ground is the bottom of the pad (its spawn parts stand up on the deck)
	local padPivot = pad:GetPivot()
	local boundsCFrame, boundsSize = pad:GetBoundingBox()
	local groundY = boundsCFrame.Position.Y - boundsSize.Y / 2
	local flatPivot = CFrame.new(padPivot.Position.X, groundY, padPivot.Position.Z) * CFrame.Angles(0, select(2, padPivot:ToOrientation()), 0)

	local cemetery = Instance.new("Folder")
	cemetery.Name = Constants.CAMP_CEMETERY_FOLDER
	local plots = Instance.new("Folder")
	plots.Name = Constants.CEMETERY_PLOTS_FOLDER
	plots.Parent = cemetery
	for index = 1, Constants.CEMETERY_PLOT_COUNT do
		local plot = Instance.new("Part")
		plot.Name = tostring(index)
		plot.Size = PLOT_SIZE
		plot.Anchored = true
		plot.CanCollide = false
		plot.CanQuery = false
		plot.CanTouch = false
		plot.Transparency = 1
		plot.CFrame = flatPivot * CFrame.new(FIRST_PLOT_OFFSET + Vector3.new((index - 1) * PLOT_SPACING_STUDS, PLOT_SIZE.Y / 2, 0))
		plot.Parent = plots
	end
	cemetery.Parent = folder
	table.insert(built, mapName)
end

ChangeHistoryService:SetWaypoint("After cemetery")
print("build_cemetery: added a Cemetery to " .. (if #built > 0 then table.concat(built, ", ") else "no map"))
