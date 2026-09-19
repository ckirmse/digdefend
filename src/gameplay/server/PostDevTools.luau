--!strict

-- Gameplay dev tools for posts (M25). The lobby store that fills the Post
-- loadout slot is a later milestone, so an admin picks the post weapon
-- their next claim spawns here, can claim and mount a post by number
-- without walking to it, and can hand a claimed post back to test
-- claiming again.
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Validate = require("@game/ReplicatedStorage/Shared/Validate")
local DevTools = require(script.Parent.Parent.Server.DevTools)
local PlayerFeedbackManager = require(script.Parent.Parent.Server.PlayerFeedbackManager)
local PostManager = require(script.Parent.PostManager)

local PostDevTools = {}
PostDevTools.__index = PostDevTools

export type PostDevTools = typeof(setmetatable({} :: {}, PostDevTools))

PostDevTools.SET_LOADOUT_POST_COMMAND = "setLoadoutPost"
PostDevTools.RELEASE_POST_COMMAND = "releasePost"
PostDevTools.CLAIM_POST_COMMAND = "claimPost"
PostDevTools.MOUNT_POST_COMMAND = "mountPost"

local SET_LOADOUT_POST_ARGS_SHAPE = {
	kind = { type = "enum", name = "PostWeaponKind" },
}
local RELEASE_POST_ARGS_SHAPE = {}
local POST_INDEX_ARGS_SHAPE = {
	index = "positiveInteger",
}

function PostDevTools:init()
	DevTools:registerPlaceCommand(
		PostDevTools.SET_LOADOUT_POST_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, SET_LOADOUT_POST_ARGS_SHAPE)
			if not isValid then
				warn("PostDevTools: setLoadoutPost with invalid args:", err)
				return
			end
			PostManager:setLoadoutOverride(player, args.kind)
			PlayerFeedbackManager:give(player, `Next claim spawns a {Enums.getPublicName(Enums.PostWeaponKind, args.kind)}`)
		end
	)
	DevTools:registerPlaceCommand(
		PostDevTools.RELEASE_POST_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, RELEASE_POST_ARGS_SHAPE)
			if not isValid then
				warn("PostDevTools: releasePost with invalid args:", err)
				return
			end
			PostManager:release(player)
			PlayerFeedbackManager:give(player, "Post released")
		end
	)
	-- the same paths the prompts take, so the checks and the Gold spend apply
	DevTools:registerPlaceCommand(
		PostDevTools.CLAIM_POST_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, POST_INDEX_ARGS_SHAPE)
			if not isValid then
				warn("PostDevTools: claimPost with invalid args:", err)
				return
			end
			local post = PostManager:getPost(args.index)
			if post then
				PostManager:claim(player, post)
			end
		end
	)
	DevTools:registerPlaceCommand(
		PostDevTools.MOUNT_POST_COMMAND,
		function(player: Player, args: { [string]: any })
			local isValid, err = Validate.isTableShape(args, POST_INDEX_ARGS_SHAPE)
			if not isValid then
				warn("PostDevTools: mountPost with invalid args:", err)
				return
			end
			local post = PostManager:getPost(args.index)
			if post then
				PostManager:mount(player, post)
			end
		end
	)
end

function PostDevTools.new(): PostDevTools
	local self = setmetatable({}, PostDevTools) :: PostDevTools
	return self
end

return PostDevTools.new()
