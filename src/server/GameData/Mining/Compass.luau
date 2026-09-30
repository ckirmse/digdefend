--!strict

-- The Compass (GDD "Compass"): a locator bar under the day clock, bought
-- once in the Mining Supplies Store (its price is in GameData/Store/
-- MiningSupplies). The Refinery is the home icon and every crewmate is a
-- coloured dot. Placeholders until tuned in play.
return {
	-- how often the server publishes each player's position for the dots;
	-- streaming hides far characters, so clients cannot read them directly
	POSITION_PUBLISH_INTERVAL_SEC = 0.25,
	-- the bar spans this much of the view, centred on straight ahead; a
	-- player outside it has no dot, the Refinery pins to the nearer end
	FIELD_OF_VIEW_DEGREES = 120,
	-- a dot is full size at or inside the first distance and shrinks to the
	-- smallest scale at the second
	DOT_FULL_SIZE_STUDS = 40,
	DOT_SMALLEST_STUDS = 300,
	DOT_SMALLEST_SCALE = 0.5,
	-- a marker this far above or below the viewer gets an up or down arrow
	-- (two mine blocks)
	VERTICAL_HINT_STUDS = 8,
	-- one dot colour per crew member; the colours themselves are UiStyle's
	PLAYER_COLOR_COUNT = 6,
}
