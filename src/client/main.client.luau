--!strict

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local ClientDevTools = require(script.Parent.ClientDevTools)
local ClientNetManager = require(script.Parent.ClientNetManager)
local ClientPlayerFeedbackManager = require(script.Parent.ClientPlayerFeedbackManager)

ClientNetManager:init()
ClientPlayerFeedbackManager:init()
ClientDevTools:initWhenAdmin()

print("Dig Defend client started (" .. tostring(Enums.getName(Enums.PlaceKind, Constants.getPlaceKind())) .. ")")
