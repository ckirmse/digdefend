--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local DeadmansCanyonData = require("@game/ServerScriptService/GameData/Mines/DeadmansCanyon")
local FrostbitePassData = require("@game/ServerScriptService/GameData/Mines/FrostbitePass")

-- map -> mine definition; every Enums.Map value must have an entry
return {
	[Enums.Map.DEADMANS_CANYON] = DeadmansCanyonData,
	[Enums.Map.FROSTBITE_PASS] = FrostbitePassData,
}
