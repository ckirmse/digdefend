--!strict

-- Where each player is looking, up or down (M24). A first-person camera is
-- client state, so other players would otherwise see a crewmate's weapon
-- stay level while they shoot at the sky. The client sends its pitch a few
-- times a second while it changes (TrySetAim); it is clamped and published
-- as the public AimPitchDegrees attribute, and every other client leans that
-- character by it (ClientAimManager). Cosmetic only: shots carry their own
-- ray and are never aimed from this. Mounted post weapons reuse it at M25.
local AimRules = require("@game/ReplicatedStorage/Shared/AimRules")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local NetEventNames = require("@game/ReplicatedStorage/Shared/NetEventNames")
local GameController = require(script.Parent.Parent.Server.GameController)
local SplendidReplicationManager = require(script.Parent.Parent.Server.SplendidReplicationManager)

local AimManager = {}
AimManager.__index = AimManager

export type AimManager = typeof(setmetatable({} :: {}, AimManager))

local TRY_SET_AIM_SHAPE = {
	pitchDegrees = "number",
}
-- a quarter of a default message: the stream must never starve firing
local TRY_SET_AIM_COST = 0.25

function AimManager:getNetHandlers()
	return {
		[NetEventNames.TRY_SET_AIM] = {
			shape = TRY_SET_AIM_SHAPE,
			cost = TRY_SET_AIM_COST,
			handler = function(player: Player, payload: { [string]: any })
				SplendidReplicationManager:setPublicAttribute(player, Attributes.AIM_PITCH_DEGREES, AimRules.clampPitch(payload.pitchDegrees))
			end,
		},
	}
end

function AimManager:onPlayerReady(player: Player)
	SplendidReplicationManager:setPublicAttribute(player, Attributes.AIM_PITCH_DEGREES, 0)
end

function AimManager:init()
	GameController:registerPlaceManager(self)
end

function AimManager.new(): AimManager
	local self = setmetatable({}, AimManager) :: AimManager
	return self
end

return AimManager.new()
