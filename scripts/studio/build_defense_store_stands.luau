-- Fills out the Defense Store in the map that is loaded in Workspace (GDD
-- "Buying Traps"): the Mining Store's PickAxeStand is the template; this
-- script creates the DefenseStore model if the map has none (a row of
-- stands beside the Mining Store, for the designer to move) and clones the
-- template into one "<Kind>Stand" per Enums.TrapKind that is missing,
-- spaced along the store's back wall. Existing stands are left where they
-- are. Run in the gameplay place with the map loaded (map_tools.luau
-- "load"), then save the map.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums = require(ReplicatedStorage.Shared.Enums)
local StoreRules = require(ReplicatedStorage.Shared.StoreRules)

local MAP_NAME = "DEADMANS_CANYON"
local TEMPLATE_ITEM = Enums.StoreItem.PICK_AXE
-- studs between stand centres along the wall, and how far along the
-- Mining Store's right axis the new store starts
local STAND_SPACING_STUDS = 4.5
local STORE_OFFSET_STUDS = 32

ChangeHistoryService:SetWaypoint("Before defense store stands")

local map = workspace:FindFirstChild(MAP_NAME)
assert(map, MAP_NAME .. " is not loaded in Workspace; run map_tools.luau with ACTION = \"load\" first")
local miningStore = map:FindFirstChild(Constants.CAMP_MINING_STORE_MODEL)
assert(miningStore, MAP_NAME .. " has no " .. Constants.CAMP_MINING_STORE_MODEL .. " model")
local template = miningStore:FindFirstChild(StoreRules.standNameForItem(TEMPLATE_ITEM))
assert(template, "the mining store has no " .. StoreRules.standNameForItem(TEMPLATE_ITEM) .. " to clone")

local store = map:FindFirstChild(Constants.CAMP_DEFENSE_STORE_MODEL)
local created = false
if not store then
	store = Instance.new("Model")
	store.Name = Constants.CAMP_DEFENSE_STORE_MODEL
	store.Parent = map
	created = true
end

local templateCFrame = template:GetPivot()
local right = templateCFrame.RightVector
local origin = if created then templateCFrame + right * STORE_OFFSET_STUDS else templateCFrame
local built = 0
local index = 0
for _, kind in Enums.getAllValues(Enums.TrapKind) do
	local standName = StoreRules.standNameFromKey(Enums.getName(Enums.TrapKind, kind))
	local stand = store:FindFirstChild(standName)
	if not stand then
		stand = template:Clone()
		stand.Name = standName
		-- the template's own ProximityPrompt belongs to the mining store's server binding
		local base = stand:FindFirstChild(Constants.STAND_BASE_PART)
		local prompt = base and base:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end
		stand:PivotTo(origin + right * (STAND_SPACING_STUDS * index))
		stand.Parent = store
		built += 1
	end
	local itemSpawn = stand:FindFirstChild(Constants.STAND_ITEM_SPAWN_PART)
	if itemSpawn then
		itemSpawn.Anchored = true
		itemSpawn.Transparency = 1
		itemSpawn.CanCollide = false
	end
	index += 1
end

ChangeHistoryService:SetWaypoint("After defense store stands")
print("build_defense_store_stands: built " .. built .. " new stand(s); " .. index .. " stands under " .. store:GetFullName() .. (if created then " (new store, move it where it belongs)" else ""))
