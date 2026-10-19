--!strict

-- Server half of the admin-only dev tools. Every command arrives as
-- TryDevTool { command, args }; the sender must be an admin and the command
-- must be on the explicit allowlist below. Each command validates its own args.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevToolCommands = require(script.Parent.DevToolCommands)
local PlayerFeedbackManager = require(script.Parent.PlayerFeedbackManager)

local DevTools = {}
DevTools.__index = DevTools

export type PlaceCommandHandler = (player: Player, args: { [string]: any }) -> ()

export type DevTools = typeof(setmetatable(
	{} :: {
		-- commands a place manager registered (registerPlaceCommand); the
		-- common allowlist stays in DevToolCommands
		placeCommands: { [string]: PlaceCommandHandler },
		-- told of every command that ran, by name (the run record counts
		-- them so a run with forced nights is not averaged as a clean one)
		commandExecutedHandlers: { (command: string) -> () },
	},
	DevTools
))

local gameController: any -- prevent circular reference by not initializing here
local splendidReplicationManager: any
local characterManager: any

local TRY_DEV_TOOL_SHAPE = {
	command = "string",
	args = { type = "table", optional = true },
}

local SEND_TEST_FEEDBACK_ARGS_SHAPE = {
	message = "string",
	displaySec = "positiveNumber",
}

local SET_DIAMONDS_ARGS_SHAPE = {
	diamonds = "nonnegativeInteger",
}

-- the character commands (M55) act on the active character; the lobby's
-- Character Menu (M37, M57) replaces them for players
local SET_CHARACTER_NIGHTS_ARGS_SHAPE = {
	nightsSurvived = "nonnegativeInteger",
}

local SET_CHARACTER_CLASS_ARGS_SHAPE = {
	classKind = { type = "enum", name = "ClassKind" },
}

local SET_CHARACTER_GEAR_ARGS_SHAPE = {
	gearSlot = { type = "enum", name = "GearSlot" },
	kind = { type = "positiveInteger", optional = true },
	stars = { type = "positiveInteger", optional = true },
}

local SET_CHARACTER_SKILL_ARGS_SHAPE = {
	slot = "positiveInteger",
	skillId = { type = "string", optional = true },
	rarity = { type = "enum", name = "Rarity", optional = true },
}

local RENAME_CHARACTER_ARGS_SHAPE = {
	name = "string",
}

local SET_ACTIVE_CHARACTER_ARGS_SHAPE = {
	characterId = "string",
}

-- a method is client-callable only if named in DevToolCommands.NAMES; init()
-- verifies every listed name has a method below
function DevTools:getNetHandlers()
	return {
		[NetEventNames.TRY_DEV_TOOL] = {
			shape = TRY_DEV_TOOL_SHAPE,
			handler = function(player: Player, payload: { [string]: any })
				self:handleTryDevTool(player, payload)
			end,
		},
	}
end

function DevTools:handleTryDevTool(player: Player, payload: { [string]: any })
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end
	if not playerData:getIsAdmin() then
		warn("DevTools: command from non-admin", player.Name, payload.command)
		return
	end

	local command = payload.command
	local placeHandler: PlaceCommandHandler? = self.placeCommands[command]
	if placeHandler then
		print("DevTools: executing", command, "for", player.Name)
		self:fireCommandExecuted(command)
		placeHandler(player, payload.args or {})
		return
	end
	if not DevToolCommands.isCommand(command) then
		warn("DevTools: unknown command", command, "from", player.Name)
		return
	end

	print("DevTools: executing", command, "for", player.Name)
	self:fireCommandExecuted(command)
	local method = (DevTools :: any)[command]
	method(self, player, payload.args or {})
end

function DevTools:subscribeCommandExecuted(handler: (command: string) -> ())
	table.insert(self.commandExecutedHandlers, handler)
end

function DevTools:fireCommandExecuted(command: string)
	for _, handler in self.commandExecutedHandlers do
		handler(command)
	end
end

-- lobby- and gameplay-only commands plug in here so common code never
-- names a place; the same admin check applies
function DevTools:registerPlaceCommand(name: string, handler: PlaceCommandHandler)
	if self.placeCommands[name] or DevToolCommands.isCommand(name) then
		error("DevTools: duplicate command " .. name)
	end
	self.placeCommands[name] = handler
end

-- full reset to a brand-new player; see DEV TOOL CONTRACT in GameController
function DevTools:resetPlayerState(player: Player, args: { [string]: any })
	gameController:resetPlayerState(player)
end

function DevTools:sendTestFeedback(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SEND_TEST_FEEDBACK_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: sendTestFeedback with invalid args:", err)
		return
	end
	PlayerFeedbackManager:give(player, args.message, args.displaySec)
end

function DevTools:setDiamonds(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SET_DIAMONDS_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: setDiamonds with invalid args:", err)
		return
	end
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end
	playerData:setDiamonds(args.diamonds)
	splendidReplicationManager:replicateDiamonds(player)
	PlayerFeedbackManager:give(player, "Diamonds set to " .. tostring(playerData:getDiamonds()))
end

function DevTools:setCharacterNights(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SET_CHARACTER_NIGHTS_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: setCharacterNights with invalid args:", err)
		return
	end
	if characterManager:setNightsSurvived(player, nil, args.nightsSurvived) then
		PlayerFeedbackManager:give(player, "Nights survived set to " .. tostring(args.nightsSurvived))
	end
end

-- the class the active character is (M64); takes effect at once, since
-- the gameplay managers listen for the change and swap the kit in hand
function DevTools:setCharacterClass(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SET_CHARACTER_CLASS_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: setCharacterClass with invalid args:", err)
		return
	end
	if characterManager:setClassKind(player, nil, args.classKind) then
		PlayerFeedbackManager:give(player, "Class set to " .. Enums.getPublicName(Enums.ClassKind, args.classKind))
	else
		PlayerFeedbackManager:give(player, "That class is not in the roster")
	end
end

function DevTools:setCharacterGear(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SET_CHARACTER_GEAR_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: setCharacterGear with invalid args:", err)
		return
	end
	if characterManager:setGear(player, nil, args.gearSlot, args.kind, args.stars) then
		PlayerFeedbackManager:give(player, Enums.getPublicName(Enums.GearSlot, args.gearSlot) .. " row updated")
	else
		PlayerFeedbackManager:give(player, "That gear kind or star count is not allowed")
	end
end

function DevTools:setCharacterSkill(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SET_CHARACTER_SKILL_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: setCharacterSkill with invalid args:", err)
		return
	end
	if characterManager:setSkill(player, nil, args.slot, args.skillId, args.rarity) then
		PlayerFeedbackManager:give(player, "Skill slot " .. tostring(args.slot) .. " updated")
	else
		PlayerFeedbackManager:give(player, "That skill slot is closed or the skill is unknown")
	end
end

function DevTools:renameCharacter(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, RENAME_CHARACTER_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: renameCharacter with invalid args:", err)
		return
	end
	if characterManager:renameCharacter(player, nil, args.name) then
		PlayerFeedbackManager:give(player, "Character renamed")
	end
end

function DevTools:addCharacter(player: Player, args: { [string]: any })
	local record = characterManager:addCharacter(player)
	if record then
		PlayerFeedbackManager:give(player, "Added " .. record.name)
	end
end

function DevTools:setActiveCharacter(player: Player, args: { [string]: any })
	local isValid, err = Validate.isTableShape(args, SET_ACTIVE_CHARACTER_ARGS_SHAPE)
	if not isValid then
		warn("DevTools: setActiveCharacter with invalid args:", err)
		return
	end
	if characterManager:setActiveCharacter(player, args.characterId) then
		PlayerFeedbackManager:give(player, "Active character changed")
	else
		PlayerFeedbackManager:give(player, "No character with that id")
	end
end

function DevTools:init(gameControllerIn: any, splendidReplicationManagerIn: any, characterManagerIn: any)
	characterManager = characterManagerIn
	gameController = gameControllerIn
	splendidReplicationManager = splendidReplicationManagerIn
	for _, name in DevToolCommands.NAMES do
		if typeof((DevTools :: any)[name]) ~= "function" then
			error("DevTools: allowlisted command has no method: " .. name)
		end
	end
end

function DevTools.new(): DevTools
	local self = setmetatable({}, DevTools) :: DevTools
	self.placeCommands = {}
	self.commandExecutedHandlers = {}
	return self
end

return DevTools.new()
