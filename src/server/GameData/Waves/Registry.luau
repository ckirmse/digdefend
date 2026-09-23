--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local DeadmansCanyonData = require("@game/ServerScriptService/GameData/Waves/DeadmansCanyon")
local FrostbitePassData = require("@game/ServerScriptService/GameData/Waves/FrostbitePass")

-- map -> wave definition; every Enums.Map value must have an entry
return {
	[Enums.Map.DEADMANS_CANYON] = DeadmansCanyonData,
	[Enums.Map.FROSTBITE_PASS] = FrostbitePassData,
}
