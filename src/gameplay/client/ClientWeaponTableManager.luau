--!strict

-- The weapon lying on the Weapon Upgrade table (designer, 2026-11-13): the
-- designer authors one Model per handheld weapon on the table, every part
-- of each fully transparent, and each player sees only the one their own
-- class carries. A model belongs to a weapon when its name is the weapon's
-- Enums.WeaponKind key with the underscores and the case set aside
-- ("AssaultRifle" for ASSAULT_RIFLE). Showing and hiding is a transparency
-- written on this client alone, so every player has their own table; a
-- weapon with no model on the table shows nothing. Sister of
-- ClientTowerTableManager and the post on the Post Upgrade table.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)

local ClientWeaponTableManager = {}
ClientWeaponTableManager.__index = ClientWeaponTableManager

export type ClientWeaponTableManager = typeof(setmetatable(
	{} :: {
		-- the table's weapon models by their normalised name
		modelByKey: { [string]: Model },
	},
	ClientWeaponTableManager
))

local WAIT_FOR_CAMP_SEC = 30
local SHOWN_TRANSPARENCY = 0
local HIDDEN_TRANSPARENCY = 1

-- "ASSAULT_RIFLE" and "AssaultRifle" meet as "assaultrifle"
local function normaliseName(name: string): string
	return string.lower((string.gsub(name, "_", "")))
end

local function setModelShown(model: Model, isShown: boolean)
	local transparency = if isShown then SHOWN_TRANSPARENCY else HIDDEN_TRANSPARENCY
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.Transparency = transparency
		end
	end
end

function ClientWeaponTableManager:renderWeapons()
	local kind = ClientDataManager:getCurrentPlayerAttribute(Attributes.WEAPON_KIND)
	-- 0 before the weapon is handed out, and getName warns on a value it does not know
	local kindName = if typeof(kind) == "number" and Enums.isValidValue(Enums.WeaponKind, kind) then Enums.getName(Enums.WeaponKind, kind) else nil
	local ownKey = if kindName then normaliseName(kindName) else nil
	for key, model in self.modelByKey do
		setModelShown(model, key == ownKey)
	end
end

function ClientWeaponTableManager:attachTable()
	local camp = workspace:WaitForChild(Constants.CAMP_FOLDER, WAIT_FOR_CAMP_SEC)
	local store = if camp then camp:WaitForChild(Constants.CAMP_DEFENSE_STORE_MODEL, WAIT_FOR_CAMP_SEC) else nil
	local tables = if store then store:WaitForChild(Constants.DEFENSE_TABLES_FOLDER, WAIT_FOR_CAMP_SEC) else nil
	local tableModel = if tables then tables:WaitForChild(Constants.WEAPON_UPGRADE_TABLE_MODEL, WAIT_FOR_CAMP_SEC) else nil
	if not tableModel or not tableModel:IsA("Model") then
		warn(`ClientWeaponTableManager: no {Constants.WEAPON_UPGRADE_TABLE_MODEL} model in the camp's {Constants.CAMP_DEFENSE_STORE_MODEL}; no weapon on the table`)
		return
	end
	table.clear(self.modelByKey)
	-- only a model named for a weapon is ours; anything else on the table is left alone
	local weaponKeys: { [string]: boolean } = {}
	for _, kind in Enums.getAllValues(Enums.WeaponKind) do
		local kindName = Enums.getName(Enums.WeaponKind, kind)
		if kindName then
			weaponKeys[normaliseName(kindName)] = true
		end
	end
	for _, child in tableModel:GetChildren() do
		local key = normaliseName(child.Name)
		if child:IsA("Model") and weaponKeys[key] then
			self.modelByKey[key] = child
		end
	end
	self:renderWeapons()
	-- a new run brings a new camp and a new table; follow it
	tableModel.AncestryChanged:Connect(
		function()
			if not tableModel:IsDescendantOf(workspace) then
				table.clear(self.modelByKey)
				task.spawn(
					function()
						self:attachTable()
					end
				)
			end
		end
	)
end

function ClientWeaponTableManager:init()
	-- the camp can take a while to stream in; nothing else waits on the display
	task.spawn(
		function()
			self:attachTable()
		end
	)
	ClientDataManager:subscribeCurrentPlayerAttribute(
		Attributes.WEAPON_KIND,
		function()
			self:renderWeapons()
		end
	)
end

function ClientWeaponTableManager.new(): ClientWeaponTableManager
	local self = setmetatable({}, ClientWeaponTableManager) :: ClientWeaponTableManager
	self.modelByKey = {}
	return self
end

return ClientWeaponTableManager.new()
