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
	},
	ClientMineDevTools
))

-- must match MineDevTools.REGENERATE_MINE_COMMAND on the server
local REGENERATE_MINE_COMMAND = "regenerateMine"

function ClientMineDevTools:renderSection()
	local stats = ClientMineManager:getStats()
	Iris.Text({ `Mine v{stats.version} seed {stats.seed}` })
	Iris.Text({ `Received {stats.bytesReceived} bytes in {stats.chunksReceived}/{stats.chunkCount} chunks` })
	Iris.Text({ `Rendered {stats.renderedCount} blocks ({stats.exposedInRadius} exposed in radius), {stats.pooledCount} pooled` })
	Iris.Text({ string.format("Last refresh %.1f ms", stats.lastRefreshMs) })

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
	return self
end

return ClientMineDevTools.new()
