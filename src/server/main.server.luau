--!strict

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")

print("Dig Defend server started (" .. tostring(Enums.getName(Enums.PlaceKind, Constants.getPlaceKind())) .. ")")
