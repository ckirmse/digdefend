--!strict

local Enums = require("@game/ReplicatedStorage/Shared/Enums")

-- Health and Revives (GDD "Health and Revives", "Spectate Mode"), M32. A
-- player has a fixed health that only monsters lower and nothing restores.
-- At zero the character is moved to the DeathRoom, a tombstone stands in
-- the camp's Cemetery, and the three Robux revives become available.
return {
	PLAYER_MAX_HEALTH = 100,
	-- a dead character is never killed (that would respawn it): its
	-- Humanoid is held at this while the player is dead
	DEAD_CHARACTER_HEALTH = 1,

	-- the Robux developer products, created on Roblox for the game; the
	-- prices are read from Roblox at startup, never written here
	PRODUCT_ID_BY_KIND = {
		[Enums.ReviveKind.SELF] = 3716709853,
		[Enums.ReviveKind.FRIEND] = 3716709889,
		[Enums.ReviveKind.TEAM] = 3716709964,
	},

	-- the Game Over screen a player sees when they die or the Refinery
	-- falls: the red screen holds, fades to black, and fades back in on the
	-- Results Menu. A dead character stays where it fell, held still, until
	-- the screen is black (hold + fade in), and the revive windows below
	-- start counting only then
	GAME_OVER_HOLD_SEC = 6,
	GAME_OVER_FADE_IN_SEC = 2,
	-- the screen stays black this long before the fade back in
	GAME_OVER_BLACK_HOLD_SEC = 3,
	GAME_OVER_FADE_OUT_SEC = 3,

	-- how long a dead player's own Revive stays on offer; after it the
	-- button is gone for that death (a Friend Revive never runs out)
	SELF_REVIVE_WINDOW_SEC = 60,
	-- how long the run holds still once every player is dead
	WIPE_WINDOW_SEC = 60,
	-- a revived player cannot be hurt for this long
	REVIVE_INVULNERABLE_SEC = 5,
	-- a revived player appears on their own grave, lifted this far clear of it
	REVIVE_LIFT_STUDS = 4,
	-- a dead character stands this far above the DeathRoom's Spawn part
	DEATH_ROOM_LIFT_STUDS = 3,

	-- the tombstone's Friend Revive prompt
	TOMBSTONE_PROMPT_ACTION_FORMAT = "Bring %s back from the dead",
	TOMBSTONE_PROMPT_MAX_DISTANCE_STUDS = 10,
	TOMBSTONE_PROMPT_HOLD_SEC = 0.5,

	DIED_ANNOUNCEMENT_FORMAT = "%s has died",
	REVIVED_BY_FRIEND_FORMAT = "%s revived you.",
	REVIVED_FRIEND_FEEDBACK_FORMAT = "You revived %s",
	TEAM_REVIVED_MESSAGE = "The crew is back. The day starts over",
	CREDIT_KEPT_FORMAT = "That %s could not be used. It is saved, and your next one is free",
	CREDIT_USED_FEEDBACK = "Used a saved revive",
	NOT_AVAILABLE_FEEDBACK = "That revive is not available right now",
	FEEDBACK_DISPLAY_SEC = 5,
}
