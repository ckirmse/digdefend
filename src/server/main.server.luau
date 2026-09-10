--!strict

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local GameController = require(script.Parent.GameController)

print("Dig Defend server started (" .. tostring(Enums.getName(Enums.PlaceKind, Constants.getPlaceKind())) .. ")")

-- keep the orchestrator referenced so it is obvious this script owns startup
local _gameController = GameController
