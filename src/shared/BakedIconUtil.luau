--!strict

-- Baked 2D icon lookup for any template under the central GameAssets folder,
-- keyed by a dot-separated assetPath ("Weapons.Pistol", "Posts.Tier1.Turret").
-- See docs/icon-capture.md for the capture pipeline that stamps the
-- attributes this module reads.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(script.Parent.Attributes)
local Constants = require(script.Parent.Constants)

local BakedIconUtil = {}

-- utils.getPathReference yields on missing children; icon lookups must never
-- block, so this resolver walks with FindFirstChild instead
function BakedIconUtil.findTemplate(assetPath: string): Instance?
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	if not gameAssets or assetPath == "" then
		return nil
	end
	local instance: Instance = gameAssets
	for _, name in string.split(assetPath, ".") do
		local child = instance:FindFirstChild(name)
		if not child then
			return nil
		end
		instance = child
	end
	return instance
end

function BakedIconUtil.getImageUrlForImageId(imageId: number): string
	return `rbxassetid://{imageId}`
end

-- nil until the asset has been captured, which callers treat as an asset bug
function BakedIconUtil.getBakedImage(assetPath: string): string?
	local template = BakedIconUtil.findTemplate(assetPath)
	if not template then
		return nil
	end
	local imageId = template:GetAttribute(Attributes.ICON_IMAGE_ID)
	if typeof(imageId) ~= "number" then
		return nil
	end
	return BakedIconUtil.getImageUrlForImageId(imageId)
end

local function collectAssetPaths(folder: Instance, prefix: string, paths: { string })
	local names = {}
	for _, child in folder:GetChildren() do
		table.insert(names, child.Name)
	end
	table.sort(names)
	for _, name in names do
		local child = folder:FindFirstChild(name) :: Instance
		local path = `{prefix}{name}`
		if child:IsA("Folder") then
			collectAssetPaths(child, `{path}.`, paths)
		else
			table.insert(paths, path)
		end
	end
end

-- every capturable asset (any Model or BasePart under any GameAssets folder),
-- in folder-then-name order; the framing dev tool's picker iterates this list
function BakedIconUtil.getAllBakeableAssetPaths(): { string }
	local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
	local paths: { string } = {}
	if not gameAssets then
		return paths
	end
	collectAssetPaths(gameAssets, "", paths)
	return paths
end

return BakedIconUtil
