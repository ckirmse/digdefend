--!strict

-- The held Tool on this client (ToolManager builds it on the server): plays
-- the swing. Roblox's default Animate script watches a held Tool for a
-- StringValue named "toolanim" and plays the matching tool animation
-- ("Slash" is the forward swing) once, then removes the marker. The
-- animation replicates with the character, so every player sees it.
local Players = game:GetService("Players")

local ClientHeldToolManager = {}
ClientHeldToolManager.__index = ClientHeldToolManager

export type ClientHeldToolManager = typeof(setmetatable({} :: {}, ClientHeldToolManager))

local TOOL_ANIMATION_MARKER = "toolanim"
local SWING_ANIMATION = "Slash"

function ClientHeldToolManager:getHeldTool(): Tool?
	local character = Players.LocalPlayer.Character
	return if character then character:FindFirstChildOfClass("Tool") else nil
end

-- one forward swing of whatever is held; a no-op with empty hands
function ClientHeldToolManager:playSwing()
	local tool = self:getHeldTool()
	if not tool then
		return
	end
	local marker = Instance.new("StringValue")
	marker.Name = TOOL_ANIMATION_MARKER
	marker.Value = SWING_ANIMATION
	marker.Parent = tool
end

function ClientHeldToolManager.new(): ClientHeldToolManager
	local self = setmetatable({}, ClientHeldToolManager) :: ClientHeldToolManager
	return self
end

return ClientHeldToolManager.new()
