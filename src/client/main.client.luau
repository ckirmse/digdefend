--!strict

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local ClientDataManager = require(script.Parent.ClientDataManager)
local ClientDevTools = require(script.Parent.ClientDevTools)
local ClientNetManager = require(script.Parent.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.ClientPlayerFeedbackManager)

-- CurrentPlayer appearing is the server's "you are fully set up" signal; no
-- client system starts before it
ClientDataManager:awaitReady()

ClientNetManager:init()
ClientPlayerFeedbackManager:init()

if ClientDataManager:getIsAdmin() then
	ClientDevTools:init()
end

print("Dig Defend client started (" .. tostring(Enums.getName(Enums.PlaceKind, Constants.getPlaceKind())) .. ")")
