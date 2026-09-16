--!strict

-- Gameplay dev tool section for the mine: regenerate with an optional seed,
-- and live streaming numbers (bytes received, rendered parts, pool size) so
-- the 2 GB phone budget can be checked in-game.
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)
local ClientMineManager = require(script.Parent.ClientMineManager)

local ClientMineDevTools = {}
ClientMineDevTools.__index = ClientMineDevTools

export type ClientMineDevTools = typeof(setmetatable(
	{} :: {
		seedInput: any,
		useSeed: any,
		goldInput: any,
		diamondsInput: any,
		campLevelInput: any,
	},
	ClientMineDevTools
))

-- must match MineDevTools.*_COMMAND on the server
local REGENERATE_MINE_COMMAND = "regenerateMine"
local FILL_BACKPACK_COMMAND = "fillBackpack"
local EMPTY_BACKPACK_COMMAND = "emptyBackpack"
local RESET_REFINERY_COMMAND = "resetRefinery"
local ADD_GOLD_COMMAND = "addGold"
local ADD_DIAMONDS_COMMAND = "addDiamonds"
local SET_CAMP_LEVEL_COMMAND = "setCampLevel"
local GIVE_CONSUMABLES_COMMAND = "giveConsumables"

function ClientMineDevTools:renderSection()
	local stats = ClientMineManager:getStats()
	Iris.Text({ `Mine v{stats.version} seed {stats.seed}` })
	Iris.Text({ `Received {stats.bytesReceived} bytes in {stats.chunksReceived}/{stats.chunkCount} chunks` })
	Iris.Text({ `Rendered {stats.renderedCount} blocks ({stats.exposedInRadius} exposed in radius), {stats.pooledCount} pooled` })
	Iris.Text({ string.format("Last refresh %.1f ms", stats.lastRefreshMs) })

	if Iris.Button({ "Fill backpack" }).clicked() then
		ClientNetManager:fireServer(NetEventNames.TRY_DEV_TOOL, { command = FILL_BACKPACK_COMMAND })
	end
	if Iris.Button({ "Empty backpack" }).clicked() then
		ClientNetManager:fireServer(NetEventNames.TRY_DEV_TOOL, { command = EMPTY_BACKPACK_COMMAND })
	end
	if Iris.Button({ "Reset refinery" }).clicked() then
		ClientNetManager:fireServer(NetEventNames.TRY_DEV_TOOL, { command = RESET_REFINERY_COMMAND })
	end

	Iris.Separator()
	Iris.InputNum({ "Gold", 10, 0 }, { number = self.goldInput })
	if Iris.Button({ "Add gold" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = ADD_GOLD_COMMAND,
				args = { amount = math.floor(self.goldInput:get()) },
			}
		)
	end
	Iris.InputNum({ "Diamonds", 10, 1 }, { number = self.diamondsInput })
	if Iris.Button({ "Add diamonds" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = ADD_DIAMONDS_COMMAND,
				args = { amount = math.max(1, math.floor(self.diamondsInput:get())) },
			}
		)
	end
	Iris.InputNum({ "Camp level", 1, 1 }, { number = self.campLevelInput })
	if Iris.Button({ "Set camp level" }).clicked() then
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = SET_CAMP_LEVEL_COMMAND,
				args = { level = math.max(1, math.floor(self.campLevelInput:get())) },
			}
		)
	end
	if Iris.Button({ "Give torches and dynamite" }).clicked() then
		ClientNetManager:fireServer(NetEventNames.TRY_DEV_TOOL, { command = GIVE_CONSUMABLES_COMMAND })
	end

	Iris.Checkbox({ "Use seed" }, { isChecked = self.useSeed })
	Iris.InputNum({ "Seed", 1, 1 }, { number = self.seedInput })
	if Iris.Button({ "Regenerate mine" }).clicked() then
		local args: { [string]: any } = {}
		if self.useSeed:get() then
			args.seed = math.max(1, math.floor(self.seedInput:get()))
		end
		ClientNetManager:fireServer(
			NetEventNames.TRY_DEV_TOOL,
			{
				command = REGENERATE_MINE_COMMAND,
				args = args,
			}
		)
	end
end

function ClientMineDevTools:init()
	self.seedInput = Iris.State(42)
	self.useSeed = Iris.State(false)
	self.goldInput = Iris.State(100)
	self.diamondsInput = Iris.State(20)
	self.campLevelInput = Iris.State(2)
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientMineDevTools.new(): ClientMineDevTools
	local self = setmetatable({}, ClientMineDevTools) :: ClientMineDevTools
	self.seedInput = nil
	self.useSeed = nil
	self.goldInput = nil
	self.diamondsInput = nil
	self.campLevelInput = nil
	return self
end

return ClientMineDevTools.new()
