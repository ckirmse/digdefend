--!strict

-- every CollectionService tag name; never use raw strings at call sites
local module

module = {
	SHADOW = "Shadow",
	-- every helicopter model cloned by HelicopterManager
	HELICOPTER = "Helicopter",
	-- ore lying on the ground (OrePickupManager): a small invisible server
	-- part carrying PickupResource / PickupAmount; clients draw the visual
	ORE_PICKUP = "OrePickup",
	-- a placed torch (TorchManager): a small invisible server part; clients
	-- draw the torch, flame, and light
	TORCH = "Torch",
	-- a thrown stick of dynamite (DynamiteManager): the server-owned physics
	-- part; clients play the fuse and draw the blast
	DYNAMITE = "Dynamite",
}

return module
