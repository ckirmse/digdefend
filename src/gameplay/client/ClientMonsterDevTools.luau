--!strict

-- The monsters' dev tool panel section (M29): spawn any kind at a numbered
-- spawn, kill every monster, run the stress test, show the path grid, and
-- the live numbers the stress test is judged by: how many monsters live,
-- the server's step time, what this client receives per second, and what
-- drawing them costs here.
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local ClientDataManager = require(script.Parent.Parent.Client.ClientDataManager)
local ClientDevTools = require(script.Parent.Parent.Client.ClientDevTools)
local ClientNetManager = require(script.Parent.Parent.Client.ClientNetManager)
local Iris = require(script.Parent.Parent.Client.Iris)
local ClientMonsterManager = require(script.Parent.ClientMonsterManager)

local ClientMonsterDevTools = {}
ClientMonsterDevTools.__index = ClientMonsterDevTools

export type ClientMonsterDevTools = typeof(setmetatable(
	{} :: {
		kindOptions: { string },
		kindOption: any,
		countInput: any,
		spawnInput: any,
		stressCountInput: any,
		isPathVisible: boolean,
	},
	ClientMonsterDevTools
))

-- must match MonsterDevTools.*_COMMAND on the server
local SPAWN_MONSTERS_COMMAND = "spawnMonsters"
local KILL_ALL_MONSTERS_COMMAND = "killAllMonsters"
local STRESS_TEST_MONSTERS_COMMAND = "stressTestMonsters"
local SET_MONSTER_PATHS_VISIBLE_COMMAND = "setMonsterPathsVisible"

function ClientMonsterDevTools:send(command: string, args: { [string]: any })
	ClientNetManager:fireServer(
		NetEventNames.TRY_DEV_TOOL,
		{
			command = command,
			args = args,
		}
	)
end

function ClientMonsterDevTools:renderSection()
	Iris.Text({ "Monsters" })
	Iris.ComboArray({ "Monster" }, { index = self.kindOption }, self.kindOptions)
	Iris.InputNum({ "Count", 1, 1, 500 }, { number = self.countInput })
	Iris.InputNum({ "Spawn", 1, 1, 9 }, { number = self.spawnInput })
	if Iris.Button({ "Spawn monsters" }).clicked() then
		self:send(SPAWN_MONSTERS_COMMAND, {
			kind = Enums.getValueByName(Enums.MonsterKind, self.kindOption:get()),
			count = math.max(1, math.floor(self.countInput:get())),
			spawnNumber = math.max(1, math.floor(self.spawnInput:get())),
		})
	end
	if Iris.Button({ "Kill all monsters" }).clicked() then
		self:send(KILL_ALL_MONSTERS_COMMAND, {} :: { [string]: any })
	end
	Iris.InputNum({ "Stress count", 50, 1, 500 }, { number = self.stressCountInput })
	if Iris.Button({ "Stress test (zombies at every spawn)" }).clicked() then
		self:send(STRESS_TEST_MONSTERS_COMMAND, {
			count = math.max(1, math.floor(self.stressCountInput:get())),
		})
	end
	if Iris.Button({ if self.isPathVisible then "Hide monster paths" else "Show monster paths" }).clicked() then
		self.isPathVisible = not self.isPathVisible
		self:send(SET_MONSTER_PATHS_VISIBLE_COMMAND, {
			isVisible = self.isPathVisible,
		})
	end
	local stats = ClientMonsterManager:getStats()
	Iris.Text({ `Server: {tostring(ClientDataManager:getGameMetadata(Attributes.MONSTER_ALIVE_COUNT))} alive, step {tostring(ClientDataManager:getGameMetadata(Attributes.MONSTER_STEP_MS))} ms` })
	Iris.Text({ string.format("Received: %.1f KB/s in %.0f packets/s", stats.bytesPerSec / 1024, stats.packetsPerSec) })
	Iris.Text({ string.format("Drawn: %d (%d animated, %d held, %d proxy), %.2f ms a frame", stats.aliveCount, stats.animatedCount, stats.heldCount, stats.proxyCount, stats.renderMs) })
end

function ClientMonsterDevTools:init()
	local kinds = Enums.getAllValues(Enums.MonsterKind)
	table.sort(kinds)
	for _, kind in kinds do
		table.insert(self.kindOptions, Enums.getName(Enums.MonsterKind, kind) :: string)
	end
	self.kindOption = Iris.State(self.kindOptions[1])
	self.countInput = Iris.State(5)
	self.spawnInput = Iris.State(2)
	self.stressCountInput = Iris.State(300)
	ClientDevTools:addMenuSection(
		function()
			self:renderSection()
		end
	)
end

function ClientMonsterDevTools.new(): ClientMonsterDevTools
	local self = setmetatable({}, ClientMonsterDevTools) :: ClientMonsterDevTools
	self.kindOptions = {}
	self.kindOption = nil
	self.countInput = nil
	self.spawnInput = nil
	self.stressCountInput = nil
	self.isPathVisible = false
	return self
end

return ClientMonsterDevTools.new()
