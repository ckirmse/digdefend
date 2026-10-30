-- Solo mining simulation (designer request, 2026-10-28): a scripted solo
-- Recruit on Deadman's Canyon, Normal, digging straight 2-tall lines off a
-- cross-cut behind the entrance for DAYS days, over many real generated
-- mines. It answers what a fixed, simple way of mining earns per day and
-- when it can afford each pick axe and backpack level. It is not shipped
-- (scripts/ is outside every Rojo project) and changes nothing in the place.
--
-- Run through the Studio MCP execute_luau in the Gameplay Edit datamodel
-- (the source pasted as the code), or paste it into the Studio Command Bar
-- in Edit mode. A plain require of the shared modules and GameData works
-- there. Never require MineManager or GameController: they leave a
-- RemoteEvent behind. Running it defines _G.SoloMiningSim and prints the
-- report to the Output. Globals set before pasting change what it does:
-- _G.SoloMiningSimConfig overrides CONFIG keys, _G.SoloMiningSimBackground
-- runs in the background with the report left in _G.SoloMiningSimReport,
-- and _G.SoloMiningSimDefineOnly only defines the functions. The
-- `solo-sim` project skill (.claude/skills/solo-sim) walks Claude through it;
-- the rules and the latest results are in docs/solo-mining-sim.md.
--
-- The rules (agreed with the designer, 2026-10-28):
-- * lines are 1 wide on the entrance floor rows (floor and floor + 1), dug
--   from the cross-cut at the entrance's back row toward the far bedrock;
--   columns are the centreline +-SPACING*k inside the zone width, taken
--   centre first, then alternating outward
-- * a line or the cross-cut stops when a stone block of its next
--   cross-section needs STALL_HITS or more hits with the current pick (7: stone
--   two tiers above the pick; hits run 1-3 / 6 / 18 / 54 by tier). Ore never stops one
-- * exposed iron, gold, and uranium within reach (3 blocks) of the tunnel is
--   mined whatever it costs, cascading as mining exposes more; a pocket the
--   tunnel opens is entered (stairs carved past a one-block step) and every
--   exposed ore in it mined before the line goes on
-- * a full backpack walks to the Refinery, refines, buys the cheaper of the
--   next pick axe and backpack level while affordable, and walks back; ore
--   that did not fit is picked up on return within its lifetime
-- * after an upgrade the deepest line whose blocking stone is now under
--   STALL_HITS is dug next; with every line stalled and nothing affordable the
--   cheapest blocking cross-section is broken through (the stuck state)
-- * mining happens only inside the day; the last load is walked home,
--   refined, and spent after dark and counts for that day
-- * the Geiger Counter (designer, 2026-10-28): once a line first reaches zone 5
--   (zones counted 0-5 from the mouth) it joins the store list and is bought
--   whenever it is the cheapest next rung (a tie goes to the pick axe or the
--   backpack). From zone 4 down, a lit dial at the digging face starts a hunt,
--   method B (the T-branch): sweep along the line, then sideways, then up or
--   down, one axis at a time, each time going one way until the rings fall
--   (turning back only if the first step drops them) and settling in the
--   middle of the strongest stretch, with a second pass of the three sweeps
--   when the first raised the rings; then, only once every ring is lit,
--   clear the stone around until the rock shows (refined by the designer the
--   same day). Hunt tunnels keep the stall rule; a rock that cannot be reached is
--   given up and no longer chased. A hunt repeats while the dial stays lit,
--   then the player walks back to the line
-- * boots (designer, 2026-10-29): once the pick axe and the backpack are both
--   BOOTS_LEVEL_GAP levels above the boots, the next boots level is bought
--   before anything else, saving for it if it is not yet affordable; boots
--   set the walk speed. Without the rule boots are never bought
-- * once every line has reached the far bedrock, stairs at the entrance lead
--   to a second band of the same lines BAND_ROWS higher (the only other
--   band whose cross-cut fits inside the first zone); added during the run
--   and kept by the designer the same day
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enums = require(ReplicatedStorage.Shared.Enums)
local MineGenerator = require(ReplicatedStorage.Shared.MineGenerator)
local BackpackRules = require(ReplicatedStorage.Shared.BackpackRules)
local GeigerRules = require(ReplicatedStorage.Shared.GeigerRules)
local RockRules = require(ReplicatedStorage.Shared.RockRules)
local GameData = ServerScriptService.GameData
local RockDefinitionsData = require(GameData.Rocks.RockDefinitions)
local WeightsData = require(GameData.Rocks.Weights)
local DifficultyData = require(GameData.Control.Difficulty)
local GenerationData = require(GameData.Mines.Generation)
local PartyScalingData = require(GameData.Control.PartyScaling)
local DeadmansCanyonData = require(GameData.Mines.DeadmansCanyon)
local PickAxeData = require(GameData.Mining.PickAxe)
local BackpackData = require(GameData.Mining.Backpack)
local BootsData = require(GameData.Mining.Boots)
local GeigerCounterData = require(GameData.Mining.GeigerCounter)
local MiningSuppliesData = require(GameData.Store.MiningSupplies)
local RefineryData = require(GameData.Refinery.Refinery)
local RunCycleData = require(GameData.Control.RunCycle)
local RosterData = require(GameData.Classes.Roster)

local CONFIG = {
	SEEDS = 200,
	-- seed i is i * SEED_STRIDE, the same seeds for every variant (paired)
	SEED_STRIDE = 7919,
	DAYS = 15,
	-- spacing 3 only since 2026-10-28 (designer): it beat spacing 2 in every
	-- round, so spacing 2 is no longer run
	SPACINGS = { 3 },
	STALL_HITS = 7,
	DIFFICULTY = Enums.Difficulty.NORMAL,
	-- the uranium target a solo Normal crew must refine (reference only)
	URANIUM_TARGET = DeadmansCanyonData.uraniumTarget,
	-- the Geiger Counter rule; false is the plain line digger
	IS_GEIGER_ENABLED = true,
	-- zones counted from 0 at the mouth: the first line to reach this zone
	-- puts the counter on the store list, and hunts start from this one down
	GEIGER_BUY_ZONE = 5,
	HUNT_FROM_ZONE = 4,
	-- the most steps one sweep takes in one direction (the top range, 40
	-- studs, is ten blocks)
	HUNT_MAX_STEPS = 10,
	-- the most stone blocks cleared around the settled point before the rock
	-- is given up
	HUNT_CLEAR_CELLS = 25,
	-- the boots rule (designer, 2026-10-29): once the pick axe and the
	-- backpack are both this many levels above the boots, the next boots level
	-- comes first, saved for if need be; false never buys boots
	IS_BOOTS_RULE_ENABLED = true,
	BOOTS_LEVEL_GAP = 2,
}
-- settings for one run without editing the file: set, for example,
-- _G.SoloMiningSimConfig = { SEEDS = 50, STALL_HITS = 5 } before pasting;
-- a key CONFIG does not have is refused so a typo cannot pass silently
local overrides = _G.SoloMiningSimConfig
if typeof(overrides) == "table" then
	for key, value in overrides do
		assert(CONFIG[key] ~= nil, "solo_mining_sim: unknown CONFIG key " .. tostring(key))
		CONFIG[key] = value
	end
end

-- camp walks in studs, measured with PathfindingService on the Deadman's
-- Canyon map (2026-10-28): the mine mouth to the edge of the refine ring,
-- the ring to each stand, stand to stand (round the counter), and each
-- stand back to the mouth (the boots stand's walks measured 2026-10-29). A
-- visit takes the stands in STAND_ORDER
local CAMP = {
	MOUTH_TO_RING = 48,
	RING_TO_STAND = { pick = 34, pack = 73, boots = 64, geiger = 61 },
	BETWEEN_STANDS = { pick = { pack = 39, boots = 47, geiger = 44 }, pack = { boots = 13, geiger = 27 }, boots = { geiger = 23 } },
	STAND_TO_MOUTH = { ring = 48, pick = 83, pack = 105, boots = 113, geiger = 110 },
}
local STAND_ORDER = { "pick", "pack", "boots", "geiger" }

local BLOCK_STUDS = 4
-- a walk around the inside of a pocket while clearing it, in blocks
local POCKET_LOOP_BLOCKS = 4
-- rows between one band of lines and the next above it: a one-block floor
-- between them, so the upper band's floor is the lower band's ceiling wall
local BAND_ROWS = 3
-- the dial reads from the character's root, about a stud above the centre
-- of the lower cell it stands in
local ROOT_LIFT_STUDS = 1
-- the most passes of the three sweeps a hunt makes
local HUNT_PASSES = 2
local AIR = MineGenerator.AIR
local ROCKS = RockDefinitionsData.ROCKS
local RESOURCE = Enums.RockKind.RESOURCE
local FILLER = Enums.RockKind.FILLER
local GOLD = Enums.RawResource.GOLD_ORE
local IRON = Enums.RawResource.IRON_ORE

local recruitModifiers = RosterData.BY_KIND[RosterData.DEFAULT_CLASS].MODIFIERS
local function classModifier(modifier: number): number
	return recruitModifiers[modifier] or 1
end
local SWING_SEC = PickAxeData.HIT_INTERVAL_SEC / classModifier(Enums.ClassModifier.MINING_SPEED)
local MOVE_SPEED = classModifier(Enums.ClassModifier.MOVE_SPEED)
local DAY_SEC = RunCycleData.DAY_SEC
local PICK_PRICES = MiningSuppliesData.UPGRADES[Enums.StoreItem.PICK_AXE].priceByLevel
local PACK_PRICES = MiningSuppliesData.UPGRADES[Enums.StoreItem.BACKPACK].priceByLevel
local GEIGER_PRICES = MiningSuppliesData.UPGRADES[Enums.StoreItem.GEIGER_COUNTER].priceByLevel
local BOOTS_PRICES = MiningSuppliesData.UPGRADES[Enums.StoreItem.BOOTS].priceByLevel

local function stoneName(rock: number): string
	return Enums.getName(Enums.RockName, rock) or tostring(rock)
end

local function buildConfig(difficulty: number)
	local largestDifficulty = 0
	for _, multiplier in DifficultyData.URANIUM_TARGET_MULTIPLIER do
		largestDifficulty = math.max(largestDifficulty, multiplier)
	end
	local largestParty = 0
	for _, multiplier in PartyScalingData.URANIUM_TARGET_MULTIPLIER_BY_PLAYER_COUNT do
		largestParty = math.max(largestParty, multiplier)
	end
	-- the same config MineManager:buildConfig assembles
	return {
		rockTable = RockDefinitionsData,
		spread = WeightsData.SPREAD,
		minCenter = WeightsData.MIN_CENTER,
		maxCenter = WeightsData.MAX_CENTER,
		hardnessShift = DifficultyData.HARDNESS_SHIFT,
		difficultyValue = DifficultyData.DIFFICULTY_VALUE[difficulty],
		veinDivisor = DifficultyData.VEIN_DIVISOR[difficulty],
		uraniumVeinDivisor = DifficultyData.URANIUM_VEIN_DIVISOR[difficulty],
		tierMinDepthBlocks = WeightsData.TIER_MIN_DEPTH_BLOCKS,
		pickaxeReachBlocks = GenerationData.PICKAXE_REACH_BLOCKS,
		isClimbingEnabled = GenerationData.IS_CLIMBING_ENABLED,
		maxPartyUraniumTargetMultiplier = largestDifficulty * largestParty,
	}
end

local BUCKETS = { "swingStone", "swingOre", "hunt", "walk", "refineShop", "stuck", "idle" }

-- one run: one mine, DAYS days. Returns the per-day rows and run facts;
-- `trace` (a list) receives the event log of day `traceDay` (default 1) when given
local function simulateRun(seed: number, spacing: number, stallHits: number, trace: { string }?, traceDay: number?)
	local result = assert(MineGenerator.generate(DeadmansCanyonData, buildConfig(CONFIG.DIFFICULTY), seed), "generation failed for seed " .. seed)
	local grid = result.grid
	local cells = grid.cells
	local H, W = grid.height, grid.width
	local plane = H * W
	local floorRow = grid.floorHeight
	local centre = grid.centrelineWidth
	local crossDepth = DeadmansCanyonData.bedrockThickness + DeadmansCanyonData.entranceDepth - 1
	local firstZone = result.zones[1]
	local widthMin, widthMax = firstZone.widthStart, firstZone.widthStart + firstZone.width - 1
	local entranceStart = centre - math.floor((DeadmansCanyonData.entranceWidth - 1) / 2)
	local entranceEnd = entranceStart + DeadmansCanyonData.entranceWidth - 1

	local function index(d: number, h: number, w: number): number
		return (d * H + h) * W + w + 1
	end
	local function decode(i: number): (number, number, number)
		local n = i - 1
		return n // plane, (n // W) % H, n % W
	end
	local function zoneAt(d: number)
		for _, zone in result.zones do
			if d >= zone.depthStart and d < zone.depthStart + zone.depth then
				return zone
			end
		end
		return result.zones[#result.zones]
	end
	-- pocket membership of each carved pocket cell
	local pocketOf: { [number]: number } = {}
	for pocketIndex, pocket in result.pockets do
		local bounds = MineGenerator.pocketBounds(pocket)
		for d = bounds.depthStart, bounds.depthEnd do
			for h = bounds.heightStart, bounds.heightEnd do
				for w = bounds.widthStart, bounds.widthEnd do
					if MineGenerator.isCellInPocket(pocket, d, h, w) and cells[index(d, h, w)] == AIR then
						pocketOf[index(d, h, w)] = pocketIndex
					end
				end
			end
		end
	end

	local hpLeft: { [number]: number } = {}
	-- cells the player can stand in or beside to swing from: the entrance,
	-- the dug tunnels, the inside of a visited pocket
	local anchor: { [number]: boolean } = {}
	local pocketVisited: { [number]: boolean } = {}

	local pick, pack = 1, 1
	-- boots set the walk speed (GameData/Mining/Boots); level 1 is the default
	local bootsLevel = 1
	-- level 1 is not owning a Geiger Counter
	local geigerLevel = 1
	local isGeigerOnSale = false
	local geigerBuyDepth = result.zones[CONFIG.GEIGER_BUY_ZONE + 1].depthStart
	local huntFromDepth = result.zones[CONFIG.HUNT_FROM_ZONE + 1].depthStart
	local uraniumCells: { number } = {}
	for i, rock in cells do
		if RockRules.isUraniumRock(rock) then
			table.insert(uraniumCells, i)
		end
	end
	-- rocks a hunt gave up on; the player stops chasing them
	local abandoned: { [number]: boolean } = {}
	local carried: { [number]: number } = {}
	local carriedTotal = 0
	local goldBalance, ironTotal, uraniumTotal = 0, 0, 0
	local brokenYield, refinedTotal, lostTotal = 0, 0, 0
	local drops = {}
	local oreQueue: { number } = {}
	local queued: { [number]: boolean } = {}
	local pendingPockets: { number } = {}
	local isPocketPending: { [number]: boolean } = {}
	-- where the player left the mine for a trip, to come back to unfinished work
	local workSpot = { d = 0, w = 0, extra = 0, band = 1 }

	local t, day = 0, 1
	local buckets: { [string]: number } = {}
	local dayRow
	local rows = {}
	local buyDays = { pick = {}, pack = {}, boots = {}, geiger = {} }
	local firstStallByPick = {}
	local stuckEvents = 0
	local uraniumDay: number? = nil
	-- the night the rescue could be won: the call is day-only, so a target
	-- refined after dark is called the next day and won that night
	local winNight: number? = nil

	-- the player: in camp at a spot ("ring", "pick", "pack"), or in the mine
	-- at a tunnel cell (depth, width) plus `extra` blocks into a pocket
	local player = { inCamp = true, campSpot = "ring", d = 0, w = centre, extra = 0, band = 1 }

	local function log(message: string)
		if trace and day == (traceDay or 1) then
			table.insert(trace, string.format("%7.2f  %s  [pack %d/%d, gold %d, pick %d, geiger %d, U %d]", t, message, carriedTotal, BackpackData.CAPACITY_BY_LEVEL[pack], goldBalance, pick, geigerLevel, uraniumTotal))
		end
	end

	-- time only counts inside the day; what is spent after dark is night
	local function spend(bucket: string, seconds: number)
		local counted = math.max(0, math.min(t + seconds, DAY_SEC) - t)
		buckets[bucket] = (buckets[bucket] or 0) + counted
		t += seconds
	end
	local function walk(studs: number, bucket: string?)
		spend(bucket or "walk", studs / (BootsData.WALK_SPEED_BY_LEVEL[bootsLevel] * MOVE_SPEED))
	end
	local function capacity(): number
		return BackpackData.CAPACITY_BY_LEVEL[pack]
	end
	local function hitsToBreak(i: number): number
		local definition = ROCKS[cells[i]]
		return math.ceil((hpLeft[i] or definition.hp) / PickAxeData.DAMAGE_BY_LEVEL[pick])
	end

	-- a band is a layer of lines BAND_ROWS above the last, reached by stairs
	-- at the entrance; the next opens once every line of the last is done
	local function bandRow(band: number): number
		return floorRow + BAND_ROWS * (band - 1)
	end
	local function climbBlocks(band: number): number
		return BAND_ROWS * (band - 1)
	end
	-- blocks along the dug tree from the mouth: down the entrance and the
	-- centre line, or along the cross-cut and up a line
	local function tunnelBlocks(d: number, w: number, band: number): number
		return d + math.abs(w - centre) + climbBlocks(band)
	end
	local function treeBlocks(d1: number, w1: number, band1: number, d2: number, w2: number, band2: number): number
		if band1 ~= band2 then
			return tunnelBlocks(d1, w1, band1) + tunnelBlocks(d2, w2, band2)
		end
		if w1 == w2 then
			return math.abs(d1 - d2)
		end
		return (d1 - crossDepth) + math.abs(w1 - w2) + (d2 - crossDepth)
	end
	local function campToMouthStuds(): number
		return CAMP.STAND_TO_MOUTH[player.campSpot]
	end
	local function moveTo(d: number, w: number, extra: number, band: number)
		if player.inCamp then
			walk(campToMouthStuds() + (tunnelBlocks(d, w, band) + extra) * BLOCK_STUDS)
		elseif player.d ~= d or player.w ~= w or player.extra ~= extra or player.band ~= band then
			local isSameCell = player.d == d and player.w == w and player.band == band
			local blocks = if isSameCell then math.abs(player.extra - extra) else player.extra + treeBlocks(player.d, player.w, player.band, d, w, band) + extra
			walk(blocks * BLOCK_STUDS)
		end
		player.inCamp, player.d, player.w, player.extra, player.band = false, d, w, extra, band
	end

	local lines = {}
	local cross = {}
	local bandCount = 0
	-- the highest band whose two rows stay inside the first zone, where its
	-- cross-cut runs
	local maxBand = 1
	while bandRow(maxBand + 1) + 1 <= firstZone.heightStart + firstZone.height - 1 do
		maxBand += 1
	end
	local function addBand()
		bandCount += 1
		local band = bandCount
		local columns = { centre }
		for k = 1, W do
			for _, sign in { 1, -1 } do
				local column = centre + sign * spacing * k
				if column >= widthMin and column <= widthMax then
					table.insert(columns, column)
				end
			end
		end
		for order, column in columns do
			table.insert(lines, {
				order = order,
				band = band,
				row = bandRow(band),
				w = column,
				front = crossDepth,
				-- the first band's centre line starts straight from the entrance
				isReached = band == 1 and column >= entranceStart and column <= entranceEnd,
				isStalled = false,
				isReopened = false,
				isDone = false,
			})
		end
		-- a higher band's cross-cut runs over the entrance from its centreline
		local isFirst = band == 1
		cross[band] = {
			[1] = { sign = 1, next = if isFirst then entranceEnd + 1 else centre, isStalled = false, isReopened = false, isDone = false },
			[-1] = { sign = -1, next = if isFirst then entranceStart - 1 else centre - 1, isStalled = false, isReopened = false, isDone = false },
		}
	end
	addBand()
	local function lineAt(column: number, band: number)
		for _, line in lines do
			if line.w == column and line.band == band then
				return line
			end
		end
		return nil
	end

	-- the next cross-section a line or cross-cut side would dig
	local function nextSection(target)
		if target.kind == "line" then
			local d = target.line.front + 1
			return d, target.line.w, { index(d, target.line.row, target.line.w), index(d, target.line.row + 1, target.line.w) }
		end
		local side = cross[target.band][target.side]
		local row = bandRow(target.band)
		return crossDepth, side.next, { index(crossDepth, row, side.next), index(crossDepth, row + 1, side.next) }
	end
	local function stateOf(target)
		return if target.kind == "line" then target.line else cross[target.band][target.side]
	end
	local function bandOf(target): number
		return if target.kind == "line" then target.line.band else target.band
	end
	-- "bedrock", "stall" (and the hardest blocking stone), or "open"
	local function judge(sectionCells: { number }): (string, number?, number)
		local worst, worstHits, total = nil, 0, 0
		for _, i in sectionCells do
			local rock = cells[i]
			if rock ~= AIR then
				local definition = ROCKS[rock]
				if not definition.hp then
					return "bedrock", nil, 0
				end
				local hits = hitsToBreak(i)
				total += hits
				if definition.kind == FILLER and hits >= stallHits and hits > worstHits then
					worst, worstHits = rock, hits
				end
			end
		end
		return if worst then "stall" else "open", worst, total
	end

	local function credit()
		local refined = 0
		for resource, amount in carried do
			local bars = amount * (RefineryData.RATE_BY_RAW[resource] or 1)
			refined += amount
			if resource == GOLD then
				goldBalance += bars
				dayRow.gold += bars
			elseif resource == IRON then
				ironTotal += bars
				dayRow.iron += bars
			else
				uraniumTotal += bars
				dayRow.uranium += bars
			end
		end
		refinedTotal += refined
		table.clear(carried)
		carriedTotal = 0
		if uraniumDay == nil and uraniumTotal >= CONFIG.URANIUM_TARGET then
			uraniumDay = day
			winNight = if t < DAY_SEC then day else day + 1
		end
	end

	local function isPassable(target): boolean
		local _, _, sectionCells = nextSection(target)
		local verdict = judge(sectionCells)
		return verdict == "open"
	end
	-- after an upgrade every stalled line and cross-cut side is judged again
	local function reopenStalled()
		for _, line in lines do
			if line.isStalled and isPassable({ kind = "line", line = line }) then
				line.isStalled, line.isReopened = false, true
			end
		end
		for band, sides in cross do
			for sign, side in sides do
				if side.isStalled and isPassable({ kind = "cross", side = sign, band = band }) then
					side.isStalled, side.isReopened = false, true
				end
			end
		end
	end

	-- the cheapest next rung while affordable (a tie goes to the pick axe,
	-- then the backpack, then the Geiger Counter), except that boots come
	-- first once the pick axe and the backpack both lead them by
	-- BOOTS_LEVEL_GAP: then nothing else is bought until the boots are.
	-- Returns the stands visited
	local function shop(): { [string]: boolean }
		local visited = {}
		while true do
			local options = {
				{ item = "pick", price = PICK_PRICES[pick + 1] },
				{ item = "pack", price = PACK_PRICES[pack + 1] },
				{ item = "geiger", price = if isGeigerOnSale then GEIGER_PRICES[geigerLevel + 1] else nil },
			}
			local bootsPrice = BOOTS_PRICES[bootsLevel + 1]
			local isBootsDue = CONFIG.IS_BOOTS_RULE_ENABLED
				and bootsPrice ~= nil
				and pick - bootsLevel >= CONFIG.BOOTS_LEVEL_GAP
				and pack - bootsLevel >= CONFIG.BOOTS_LEVEL_GAP
			if isBootsDue then
				options = { { item = "boots", price = bootsPrice } }
			end
			local best = nil
			for _, option in options do
				if option.price ~= nil and (best == nil or option.price < best.price) then
					best = option
				end
			end
			if best == nil or goldBalance < best.price then
				break
			end
			goldBalance -= best.price
			dayRow.spent += best.price
			spend("refineShop", MiningSuppliesData.PROMPT_HOLD_SEC)
			visited[best.item] = true
			local level
			if best.item == "pick" then
				pick += 1
				level = pick
			elseif best.item == "pack" then
				pack += 1
				level = pack
			elseif best.item == "boots" then
				bootsLevel += 1
				level = bootsLevel
			else
				geigerLevel += 1
				level = geigerLevel
			end
			buyDays[best.item][level] = day
			log(string.format("bought %s %d for %d", best.item, level, best.price))
		end
		return visited
	end

	-- walk out, refine, shop, and stay in camp (the walk back in is the next
	-- move's); the time is the day's only while the day lasts
	local function trip()
		if player.inCamp then
			return
		end
		log(string.format("trip out from depth %d width %d (+%d in a pocket)", player.d, player.w, player.extra))
		workSpot.d, workSpot.w, workSpot.extra, workSpot.band = player.d, player.w, player.extra, player.band
		walk((tunnelBlocks(player.d, player.w, player.band) + player.extra) * BLOCK_STUDS + CAMP.MOUTH_TO_RING)
		player.inCamp, player.campSpot = true, "ring"
		if carriedTotal > 0 then
			spend("refineShop", RefineryData.REFINE_DURATION_SEC)
			credit()
		end
		local visited = shop()
		for _, stand in STAND_ORDER do
			if visited[stand] then
				local studs = if player.campSpot == "ring" then CAMP.RING_TO_STAND[stand] else CAMP.BETWEEN_STANDS[player.campSpot][stand]
				walk(studs, "refineShop")
				player.campSpot = stand
			end
		end
		if visited.pick then
			reopenStalled()
		end
	end

	local function award(rock: number, i: number)
		local definition = ROCKS[rock]
		local amount = BackpackRules.yieldForBreak(definition.yield, definition.resource, 1, PartyScalingData.ORE_YIELD_MULTIPLIER_BY_PLAYER_COUNT)
		amount = math.floor(amount * classModifier(Enums.ClassModifier.ORE_YIELD) + 0.5)
		brokenYield += amount
		local added, overflow = BackpackRules.add(carried, capacity(), definition.resource, amount)
		carriedTotal += added
		if overflow > 0 then
			table.insert(drops, { resource = definition.resource, amount = overflow, time = t, d = player.d, w = player.w, extra = player.extra, band = player.band })
		end
		log(string.format("broke %s: +%d (%d dropped)", stoneName(rock), added, overflow))
	end

	-- swings at a block until it breaks or the day ends
	local function swingBlock(i: number, bucket: string): boolean
		local rock = cells[i]
		local definition = ROCKS[rock]
		assert(definition and definition.hp, "the sim tried to mine bedrock or air")
		local hp = hpLeft[i] or definition.hp
		local damage = PickAxeData.DAMAGE_BY_LEVEL[pick]
		while hp > 0 do
			if t >= DAY_SEC then
				hpLeft[i] = hp
				return false
			end
			spend(bucket, SWING_SEC)
			hp -= damage
		end
		hpLeft[i] = nil
		cells[i] = AIR
		if definition.kind == RESOURCE then
			award(rock, i)
		end
		return true
	end

	local NEIGHBOURS = { 1, -1, W, -W, plane, -plane }
	local function isReachable(i: number): boolean
		local d, h, w = decode(i)
		for dd = -3, 3 do
			for dh = -3, 3 do
				for dw = -3, 3 do
					if dd * dd + dh * dh + dw * dw <= 9 then
						local a, b, c = d + dd, h + dh, w + dw
						if a >= 0 and a < grid.depth and b >= 0 and b < H and c >= 0 and c < W and anchor[index(a, b, c)] then
							return true
						end
					end
				end
			end
		end
		return false
	end
	-- a cell just opened: exposed ore beside it joins the queue when in reach,
	-- and an unvisited pocket beside it is remembered
	local function exposeAround(i: number)
		for _, offset in NEIGHBOURS do
			local n = i + offset
			local rock = cells[n]
			if rock ~= nil then
				if rock == AIR then
					local pocketIndex = pocketOf[n]
					if pocketIndex and not pocketVisited[pocketIndex] and not isPocketPending[pocketIndex] then
						isPocketPending[pocketIndex] = true
						table.insert(pendingPockets, pocketIndex)
					end
				elseif not queued[n] and ROCKS[rock].kind == RESOURCE and isReachable(n) then
					queued[n] = true
					table.insert(oreQueue, n)
				end
			end
		end
	end

	-- picks up what lies where the player stands, while it lasts and fits
	local function pickUpDrops()
		local kept = {}
		for _, drop in drops do
			if t - drop.time >= BackpackData.PICKUP_LIFETIME_SEC then
				lostTotal += drop.amount
			-- the pickup radius (5 studs) covers the block beside the player
			elseif not player.inCamp and drop.band == player.band and drop.extra == player.extra and math.abs(drop.d - player.d) + math.abs(drop.w - player.w) <= 1 then
				local added, overflow = BackpackRules.add(carried, capacity(), drop.resource, drop.amount)
				carriedTotal += added
				if overflow > 0 then
					drop.amount = overflow
					table.insert(kept, drop)
				end
			else
				table.insert(kept, drop)
			end
		end
		drops = kept
	end

	local function isFull(): boolean
		return carriedTotal >= capacity()
	end

	-- mines the queued ore; returns false when the day ran out first
	local function clearOreQueue(): boolean
		while #oreQueue > 0 do
			if t >= DAY_SEC then
				return false
			end
			if isFull() then
				trip()
				return true
			end
			local i = oreQueue[#oreQueue]
			if cells[i] == AIR then
				table.remove(oreQueue)
				queued[i] = nil
			elseif swingBlock(i, "swingOre") then
				table.remove(oreQueue)
				queued[i] = nil
				exposeAround(i)
			else
				return false
			end
		end
		return true
	end

	-- a stair step is two cells of the zone's commonest stone, carved where
	-- the climb needs it (the cells themselves are not tracked)
	local function carveStairs(steps: number, zone)
		if steps <= 0 then
			return
		end
		local best, bestWeight = 1, -1
		for k, weight in zone.fillerWeights do
			if weight > bestWeight then
				best, bestWeight = k, weight
			end
		end
		local stone = ROCKS[RockDefinitionsData.FILLER_ORDER[best]]
		local hits = math.ceil(stone.hp / PickAxeData.DAMAGE_BY_LEVEL[pick])
		spend("swingStone", steps * 2 * hits * SWING_SEC)
	end

	-- enters the pending pocket from the tunnel cell beside it: stairs past a
	-- one-block step (the jump clears 7.2 studs), then its whole room is in reach
	local function enterPocket(pocketIndex: number)
		local pocket = result.pockets[pocketIndex]
		local bounds = MineGenerator.pocketBounds(pocket)
		pocketVisited[pocketIndex] = true
		local steps = math.max(0, math.abs(bounds.heightStart - bandRow(player.band)) - 1)
		carveStairs(steps, result.zones[pocket.zoneIndex])
		local extra = math.abs(pocket.depth - player.d) + math.abs(pocket.width - player.w)
		moveTo(player.d, player.w, extra, player.band)
		walk(POCKET_LOOP_BLOCKS * BLOCK_STUDS)
		dayRow.pockets += 1
		log(string.format("entered pocket %d (%d stair steps)", pocketIndex, steps))
		for i in pocketOf do
			if pocketOf[i] == pocketIndex then
				anchor[i] = true
			end
		end
		for i in pocketOf do
			if pocketOf[i] == pocketIndex then
				exposeAround(i)
			end
		end
	end

	-- digs one cross-section of a line or cross-cut side; `isBreakthrough`
	-- ignores the stall rule for this one section (the stuck state)
	local function digSection(target, isBreakthrough: boolean)
		local state = stateOf(target)
		local d, w, sectionCells = nextSection(target)
		local verdict, worst, _ = judge(sectionCells)
		if verdict == "bedrock" then
			state.isDone = true
			return
		end
		if verdict == "stall" and not isBreakthrough then
			state.isStalled = true
			state.stallStone, state.stallDepth = worst, d
			if not firstStallByPick[pick] then
				firstStallByPick[pick] = { depth = d, w = w, stone = worst, day = day, kind = target.kind }
			end
			log(string.format("%s stalls at depth %d width %d on %s", target.kind, d, w, stoneName(worst :: number)))
			return
		end
		-- stand behind the section
		local band = bandOf(target)
		if target.kind == "line" then
			moveTo(d - 1, w, 0, band)
		else
			moveTo(crossDepth, w - state.sign, 0, band)
		end
		for _, i in sectionCells do
			if cells[i] ~= AIR then
				local bucket = if isBreakthrough then "stuck" elseif ROCKS[cells[i]].kind == RESOURCE then "swingOre" else "swingStone"
				if not swingBlock(i, bucket) then
					return
				end
			end
		end
		for _, i in sectionCells do
			anchor[i] = true
		end
		for _, i in sectionCells do
			exposeAround(i)
		end
		if target.kind == "line" then
			state.front = d
			if CONFIG.IS_GEIGER_ENABLED and d >= geigerBuyDepth and not isGeigerOnSale then
				isGeigerOnSale = true
				log("first line into the Geiger zone: the counter goes on the store list")
			end
		else
			state.next += state.sign
			local line = lineAt(w, band)
			if line then
				line.isReached = true
			end
		end
		state.isReopened = false
		walk(BLOCK_STUDS)
		player.d, player.w = d, w
	end

	-- the Geiger Counter's rings at a standing cell, and the rock behind them
	-- (the sim's own bookkeeping; the player sees only the rings)
	local function readDial(d: number, h: number, w: number): (number, number?)
		if geigerLevel <= 1 then
			return 0, nil
		end
		local range = GeigerRules.rangeForLevel(GeigerCounterData.RANGE_STUDS_BY_LEVEL, geigerLevel)
		local position = Vector3.new(w * BLOCK_STUDS, h * BLOCK_STUDS + ROOT_LIFT_STUDS, d * BLOCK_STUDS)
		local nearest, nearestDistance = nil, math.huge
		for _, i in uraniumCells do
			if cells[i] ~= AIR and not abandoned[i] then
				local cd, ch, cw = decode(i)
				local distance = GeigerRules.distanceToBlock(position, Vector3.new(cw * BLOCK_STUDS, ch * BLOCK_STUDS, cd * BLOCK_STUDS), BLOCK_STUDS)
				if distance <= range and distance < nearestDistance then
					nearest, nearestDistance = i, distance
				end
			end
		end
		if nearest == nil then
			return 0, nil
		end
		return GeigerRules.litRingCount(nearestDistance, GeigerRules.ringStudsForLevel(GeigerCounterData.RING_STUDS_BY_LEVEL, geigerLevel)), nearest
	end

	-- a hunt starts at a line cell (its origin) and moves through its own
	-- tunnels; the player's tunnel spot stays the origin and `extra` is the
	-- walk from it, so trips and drops work as they do for pockets
	local hunt = nil
	local function huntExtra(): number
		return math.abs(hunt.d - hunt.originD) + math.abs(hunt.w - hunt.originW) + math.abs(hunt.h - bandRow(hunt.band))
	end
	local function returnToHunt()
		if player.inCamp then
			moveTo(hunt.originD, hunt.originW, huntExtra(), hunt.band)
		end
	end
	local function walkHuntTo(d: number, h: number, w: number)
		walk((math.abs(d - hunt.d) + math.abs(h - hunt.h) + math.abs(w - hunt.w)) * BLOCK_STUDS)
		hunt.d, hunt.h, hunt.w = d, h, w
		player.extra = huntExtra()
	end
	-- mines whatever the last carve exposed, coming back after any trip
	local function settleOre(): boolean
		while #oreQueue > 0 and t < DAY_SEC do
			returnToHunt()
			clearOreQueue()
		end
		if t < DAY_SEC then
			returnToHunt()
		end
		return t < DAY_SEC
	end
	-- air, or stone under the stall rule; never bedrock or outside the grid
	local function isCarvable(i: number?): boolean
		if i == nil or cells[i] == nil then
			return false
		end
		local rock = cells[i]
		if rock == AIR then
			return true
		end
		local definition = ROCKS[rock]
		if not definition.hp then
			return false
		end
		return definition.kind ~= FILLER or hitsToBreak(i) < stallHits
	end
	local function cellAt(d: number, h: number, w: number): number?
		if d < 0 or d >= grid.depth or h < 0 or h >= H or w < 0 or w >= W then
			return nil
		end
		return index(d, h, w)
	end
	-- the cells at these positions, or an empty list if any is outside the grid
	local function cellsAt(positions: { { number } }): { number }
		local found = {}
		for _, position in positions do
			local i = cellAt(position[1], position[2], position[3])
			if i == nil then
				return {}
			end
			table.insert(found, i)
		end
		return found
	end
	-- opens the cells, or nothing if any is too hard; false also when the day ends
	local function carveHunt(huntCells: { number }): boolean
		if #huntCells == 0 then
			return false
		end
		for _, i in huntCells do
			if not isCarvable(i) then
				return false
			end
		end
		for _, i in huntCells do
			if cells[i] ~= AIR then
				if isFull() then
					trip()
					returnToHunt()
				end
				local bucket = if ROCKS[cells[i]].kind == RESOURCE then "swingOre" else "hunt"
				if not swingBlock(i, bucket) then
					return false
				end
			end
		end
		for _, i in huntCells do
			anchor[i] = true
		end
		for _, i in huntCells do
			exposeAround(i)
		end
		return settleOre()
	end
	-- the cells one step along an axis opens: two rows for a step along the
	-- depth or the width, one cell for a step up or down (plus a stair block)
	local function stepCells(axis: string, sign: number): (number, number, number, { number })
		local d, h, w = hunt.d, hunt.h, hunt.w
		if axis == "depth" then
			return d + sign, h, w, cellsAt({ { d + sign, h, w }, { d + sign, h + 1, w } })
		elseif axis == "width" then
			return d, h, w + sign, cellsAt({ { d, h, w + sign }, { d, h + 1, w + sign } })
		elseif sign == 1 then
			return d, h + 1, w, cellsAt({ { d, h + 2, w } })
		end
		return d, h - 1, w, cellsAt({ { d, h - 1, w } })
	end
	-- one axis of the T-branch: go one way while the rings hold or rise,
	-- turning back only if the very first step drops them, then settle in the
	-- middle of the strongest stretch. False when the day ran out
	local function sweep(axis: string, line): boolean
		local best = readDial(hunt.d, hunt.h, hunt.w)
		local startD, startH, startW = hunt.d, hunt.h, hunt.w
		for _, sign in { 1, -1 } do
			local stretch = { { hunt.d, hunt.h, hunt.w } }
			local isWrongWay = false
			for step = 1, CONFIG.HUNT_MAX_STEPS do
				local d, h, w, huntCells = stepCells(axis, sign)
				if not carveHunt(huntCells) then
					break
				end
				if axis == "height" and sign == 1 then
					-- the step to stand on while climbing
					carveStairs(1, zoneAt(d))
				end
				walkHuntTo(d, h, w)
				if line and axis == "depth" and w == line.w and h == line.row and d > line.front then
					line.front = d
				end
				local rings = readDial(d, h, w)
				if rings > best then
					best = rings
					stretch = { { d, h, w } }
				elseif rings == best then
					table.insert(stretch, { d, h, w })
				else
					isWrongWay = step == 1
					break
				end
			end
			if t >= DAY_SEC then
				return false
			end
			if not isWrongWay then
				local middle = stretch[math.ceil(#stretch / 2)]
				walkHuntTo(middle[1], middle[2], middle[3])
				return true
			end
			walkHuntTo(startD, startH, startW)
		end
		return true
	end
	-- stone around the settled point, nearest first, until the rock shows
	local function clearAround(target: number): boolean
		for _ = 1, CONFIG.HUNT_CLEAR_CELLS do
			if cells[target] == AIR or t >= DAY_SEC then
				break
			end
			local bestCell, bestDistance = nil, math.huge
			for dd = -2, 2 do
				for dh = -2, 3 do
					for dw = -2, 2 do
						local i = cellAt(hunt.d + dd, hunt.h + dh, hunt.w + dw)
						if i and cells[i] ~= AIR and isCarvable(i) and ROCKS[cells[i]].kind == FILLER then
							local hasOpenFace = false
							for _, offset in NEIGHBOURS do
								if cells[i + offset] == AIR and anchor[i + offset] then
									hasOpenFace = true
								end
							end
							local distance = dd * dd + (dh - 0.5) * (dh - 0.5) + dw * dw
							if hasOpenFace and distance < bestDistance then
								bestCell, bestDistance = i, distance
							end
						end
					end
				end
			end
			if bestCell == nil or not carveHunt({ bestCell }) then
				break
			end
		end
		return cells[target] == AIR
	end
	-- a lit dial at a line's face: hunt rock after rock while it stays lit,
	-- then walk back to the line
	local function huntUranium(line)
		hunt = { originD = line.front, originW = line.w, band = line.band, d = line.front, h = line.row, w = line.w }
		dayRow.hunts += 1
		local startTime = t
		local isFirst = true
		while t < DAY_SEC do
			local rings, target = readDial(hunt.d, hunt.h, hunt.w)
			if rings == 0 or target == nil then
				break
			end
			log(string.format("dial %d rings at depth %d row %d width %d: hunting", rings, hunt.d, hunt.h, hunt.w))
			-- a second pass of the three sweeps when the first one raised the
			-- rings (designer, 2026-10-28): one axis at a time overshoots
			-- when the rock sits off two axes at once
			for pass = 1, HUNT_PASSES do
				local before = readDial(hunt.d, hunt.h, hunt.w)
				for _, axis in { "depth", "width", "height" } do
					if cells[target] == AIR or not sweep(axis, if isFirst then line else nil) then
						break
					end
				end
				isFirst = false
				if cells[target] == AIR or t >= DAY_SEC or readDial(hunt.d, hunt.h, hunt.w) <= before then
					break
				end
			end
			if t >= DAY_SEC then
				break
			end
			local settledRings, nearest = readDial(hunt.d, hunt.h, hunt.w)
			if cells[target] ~= AIR then
				target = nearest or target
			end
			-- clearing pays only once every ring is lit: the rock is then within
			-- the inner ring's two blocks; short of that, the rock is given up
			local ringCount = #GeigerRules.ringStudsForLevel(GeigerCounterData.RING_STUDS_BY_LEVEL, geigerLevel)
			if cells[target] ~= AIR and settledRings < ringCount then
				abandoned[target] = true
				dayRow.huntsAbandoned += 1
				log(string.format("only %d rings after the sweeps: gave up on that rock", settledRings))
			elseif cells[target] ~= AIR and not clearAround(target) then
				if t >= DAY_SEC then
					break
				end
				abandoned[target] = true
				dayRow.huntsAbandoned += 1
				log("gave up on that rock")
			elseif cells[target] == AIR then
				dayRow.huntRocks += 1
				log("found it")
			end
		end
		dayRow.huntSec += math.max(0, math.min(t, DAY_SEC) - startTime)
		if not player.inCamp then
			moveTo(hunt.originD, hunt.originW, 0, hunt.band)
		end
		hunt = nil
	end

	-- what to do next: a reopened line, the line in hand, the next new line
	-- (cutting the cross-cut toward it), or the stuck state
	local current = nil
	local function isOpen(state): boolean
		return not state.isStalled and not state.isDone
	end
	-- which cross-cut side leads to a line: the first band's sides start
	-- beside the entrance, a higher band's from its centreline outward
	local function crossSignFor(line): number
		if line.band == 1 then
			return if line.w > centre then 1 else -1
		end
		return if line.w >= centre then 1 else -1
	end
	-- a cross-cut side is worth digging only while a new line waits beyond it
	local function isCrossNeeded(sign: number, band: number): boolean
		for _, line in lines do
			if line.band == band and not line.isReached and not line.isDone and crossSignFor(line) == sign then
				return true
			end
		end
		return false
	end
	local function choose()
		local deepest = nil
		for _, line in lines do
			if line.isReopened and isOpen(line) and line.isReached and (deepest == nil or line.front > deepest.front) then
				deepest = line
			end
		end
		if deepest then
			return { kind = "line", line = deepest }, false
		end
		for band, sides in cross do
			for sign, side in sides do
				if side.isReopened and isOpen(side) and isCrossNeeded(sign, band) then
					return { kind = "cross", side = sign, band = band }, false
				end
			end
		end
		if current and current.kind == "line" and isOpen(current.line) then
			return current, false
		end
		for _, line in lines do
			if isOpen(line) and line.front == crossDepth then
				if line.isReached then
					return { kind = "line", line = line }, false
				end
				local sign = crossSignFor(line)
				if isOpen(cross[line.band][sign]) then
					return { kind = "cross", side = sign, band = line.band }, false
				end
			end
		end
		for _, line in lines do
			if isOpen(line) and line.isReached and line.front > crossDepth then
				return { kind = "line", line = line }, false
			end
		end
		-- every line finished at the far bedrock: stairs up to the next band
		local isEveryLineDone = true
		for _, line in lines do
			if not line.isDone then
				isEveryLineDone = false
			end
		end
		if isEveryLineDone and bandCount < maxBand then
			moveTo(crossDepth, centre, 0, bandCount)
			carveStairs(BAND_ROWS - 1, firstZone)
			addBand()
			log(string.format("every line done: stairs up to band %d", bandCount))
			return choose()
		end
		-- stuck: refine first if the load would buy a rung
		local cheapest = math.min(PICK_PRICES[pick + 1] or math.huge, PACK_PRICES[pack + 1] or math.huge)
		if carriedTotal > 0 and goldBalance + (carried[GOLD] or 0) >= cheapest then
			return { kind = "trip" }, false
		end
		local best, bestCost = nil, math.huge
		local function consider(target)
			local state = stateOf(target)
			if not state.isStalled or state.isDone then
				return
			end
			local d, w, sectionCells = nextSection(target)
			local _, _, cost = judge(sectionCells)
			cost += treeBlocks(player.d, player.w, player.band, d, w, bandOf(target)) * 0.01
			if cost < bestCost then
				best, bestCost = target, cost
			end
		end
		for _, line in lines do
			if line.isReached then
				consider({ kind = "line", line = line })
			end
		end
		for band, sides in cross do
			for sign in sides do
				if isCrossNeeded(sign, band) then
					consider({ kind = "cross", side = sign, band = band })
				end
			end
		end
		if best then
			return best, true
		end
		return nil, false
	end

	local function newDayRow()
		return { gold = 0, iron = 0, uranium = 0, spent = 0, pockets = 0, stuckEvents = 0, hunts = 0, huntRocks = 0, huntsAbandoned = 0, huntSec = 0 }
	end

	-- the entrance is standing room from the start
	for d = 0, crossDepth do
		for h = floorRow, floorRow + DeadmansCanyonData.entranceHeight - 1 do
			for w = entranceStart, entranceEnd do
				if cells[index(d, h, w)] == AIR then
					anchor[index(d, h, w)] = true
				end
			end
		end
	end

	for runDay = 1, CONFIG.DAYS do
		day, t = runDay, 0
		buckets = {}
		dayRow = newDayRow()
		while t < DAY_SEC do
			pickUpDrops()
			local hasDropsWaiting = false
			for _, drop in drops do
				if t - drop.time < BackpackData.PICKUP_LIFETIME_SEC then
					hasDropsWaiting = true
				end
			end
			if isFull() then
				trip()
			elseif player.inCamp and (#oreQueue > 0 or #pendingPockets > 0 or hasDropsWaiting) then
				-- back to the unfinished work first
				moveTo(workSpot.d, workSpot.w, workSpot.extra, workSpot.band)
			elseif #oreQueue > 0 then
				clearOreQueue()
			elseif #pendingPockets > 0 then
				local pocketIndex = table.remove(pendingPockets, 1) :: number
				isPocketPending[pocketIndex] = nil
				enterPocket(pocketIndex)
			else
				local target, isBreakthrough = choose()
				if target == nil then
					spend("idle", DAY_SEC - t)
				elseif target.kind == "trip" then
					trip()
				else
					if isBreakthrough then
						stuckEvents += 1
						dayRow.stuckEvents += 1
						local d, w = nextSection(target)
						log(string.format("stuck: breaking through %s at depth %d width %d", target.kind, d, w))
					end
					current = target
					digSection(target, isBreakthrough)
					-- the dial is read at the face: a lit one in the hunt zones starts a hunt
					if target.kind == "line" and geigerLevel > 1 and t < DAY_SEC and not player.inCamp then
						local line = target.line
						if line.front >= huntFromDepth and player.d == line.front and player.w == line.w and player.extra == 0 and readDial(line.front, line.row, line.w) > 0 then
							huntUranium(line)
						end
					end
				end
			end
		end
		-- night: home, refine, shop; drops left in the mine are gone by morning
		trip()
		for _, drop in drops do
			lostTotal += drop.amount
		end
		table.clear(drops)
		local deepest, started = 0, 0
		for _, line in lines do
			if line.front > crossDepth then
				started += 1
				deepest = math.max(deepest, line.front)
			end
		end
		dayRow.bands = bandCount
		local counted = 0
		for _, name in BUCKETS do
			counted += buckets[name] or 0
		end
		assert(math.abs(counted - DAY_SEC) < 1e-6, string.format("day %d time adds to %.3f, not %d", day, counted, DAY_SEC))
		dayRow.pick, dayRow.pack, dayRow.boots, dayRow.geiger = pick, pack, bootsLevel, geigerLevel
		dayRow.balance = goldBalance
		dayRow.ironTotal, dayRow.uraniumTotal = ironTotal, uraniumTotal
		dayRow.deepest, dayRow.lines = deepest, started
		dayRow.buckets = buckets
		rows[day] = dayRow
	end
	assert(brokenYield == refinedTotal + lostTotal + carriedTotal, string.format("ore not conserved: broken %d, refined %d, lost %d, carried %d", brokenYield, refinedTotal, lostTotal, carriedTotal))

	local stalls = {}
	for _, line in lines do
		table.insert(stalls, { w = line.w, front = line.front, stone = line.stallStone, isStalled = line.isStalled, isDone = line.isDone })
	end
	return {
		rows = rows,
		buyDays = buyDays,
		firstStallByPick = firstStallByPick,
		uraniumDay = uraniumDay,
		winNight = winNight,
		stuckEvents = stuckEvents,
		lost = lostTotal,
		stalls = stalls,
		grid = grid,
	}
end

local function percentile(sorted: { number }, q: number): number
	if #sorted == 0 then
		return 0
	end
	return sorted[math.clamp(math.ceil(q * #sorted), 1, #sorted)]
end
local function stats(values: { number })
	local sorted = table.clone(values)
	table.sort(sorted)
	local sum = 0
	for _, v in sorted do
		sum += v
	end
	return { mean = sum / math.max(#sorted, 1), p10 = percentile(sorted, 0.1), p50 = percentile(sorted, 0.5), p90 = percentile(sorted, 0.9) }
end
local function fmt(s): string
	return string.format("%.0f (%.0f/%.0f/%.0f)", s.mean, s.p10, s.p50, s.p90)
end

-- every seed for one variant
local function runVariant(spacing: number, stallHits: number, seedCount: number)
	local runs = {}
	for k = 1, seedCount do
		table.insert(runs, simulateRun(k * CONFIG.SEED_STRIDE, spacing, stallHits))
		task.wait()
	end
	return runs
end

local function describe(runs, label: string): string
	local out = { "== " .. label .. string.format(" (%d seeds; mean (p10/p50/p90))", #runs) }
	table.insert(out, "day | gold | iron | uranium | cum gold | cum iron | cum uranium")
	local cum = {}
	for k in runs do
		cum[k] = { g = 0, i = 0, u = 0 }
	end
	for day = 1, CONFIG.DAYS do
		local g, i, u, cg, ci, cu = {}, {}, {}, {}, {}, {}
		for k, run in runs do
			local row = run.rows[day]
			cum[k].g += row.gold
			cum[k].i += row.iron
			cum[k].u += row.uranium
			table.insert(g, row.gold)
			table.insert(i, row.iron)
			table.insert(u, row.uranium)
			table.insert(cg, cum[k].g)
			table.insert(ci, cum[k].i)
			table.insert(cu, cum[k].u)
		end
		table.insert(out, string.format("%2d | %s | %s | %s | %s | %s | %s", day, fmt(stats(g)), fmt(stats(i)), fmt(stats(u)), fmt(stats(cg)), fmt(stats(ci)), fmt(stats(cu))))
	end
	table.insert(out, "day | pick p10/p50/p90 | backpack p10/p50/p90 | boots p10/p50/p90 | gold spent | gold left | deepest | lines | pockets | % in band 2")
	for day = 1, CONFIG.DAYS do
		local p, b, bt, s, l, dp, ln, pk = {}, {}, {}, {}, {}, {}, {}, {}
		local upperBand = 0
		for _, run in runs do
			local row = run.rows[day]
			table.insert(p, row.pick)
			table.insert(b, row.pack)
			table.insert(bt, row.boots)
			table.insert(s, row.spent)
			table.insert(l, row.balance)
			table.insert(dp, row.deepest)
			table.insert(ln, row.lines)
			table.insert(pk, row.pockets)
			if row.bands > 1 then
				upperBand += 1
			end
		end
		local ps, bs, bts = stats(p), stats(b), stats(bt)
		table.insert(out, string.format("%2d | %d/%d/%d | %d/%d/%d | %d/%d/%d | %s | %s | %s | %.1f | %.1f | %d%%", day, ps.p10, ps.p50, ps.p90, bs.p10, bs.p50, bs.p90, bts.p10, bts.p50, bts.p90, fmt(stats(s)), fmt(stats(l)), fmt(stats(dp)), stats(ln).mean, stats(pk).mean, math.floor(upperBand / #runs * 100 + 0.5)))
	end
	table.insert(out, "day | mean seconds: swing stone | swing ore | hunt stone | walk | refine+shop | stuck | idle | stuck events (mean, % of seeds)")
	for day = 1, CONFIG.DAYS do
		local sums = {}
		local events, firing = 0, 0
		for _, run in runs do
			for _, name in BUCKETS do
				sums[name] = (sums[name] or 0) + (run.rows[day].buckets[name] or 0)
			end
			events += run.rows[day].stuckEvents
			if run.rows[day].stuckEvents > 0 then
				firing += 1
			end
		end
		local n = #runs
		table.insert(out, string.format("%2d | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.2f, %d%%", day, sums.swingStone / n, sums.swingOre / n, sums.hunt / n, sums.walk / n, sums.refineShop / n, sums.stuck / n, sums.idle / n, events / n, math.floor(firing / n * 100 + 0.5)))
	end
	table.insert(out, "day | geiger level p10/p50/p90 | hunts | rocks found | rocks given up | seconds hunting (all of it: digging, walking, ore, trips)")
	for day = 1, CONFIG.DAYS do
		local levels, hunts, found, givenUp, seconds = {}, {}, {}, {}, {}
		for _, run in runs do
			local row = run.rows[day]
			table.insert(levels, row.geiger)
			table.insert(hunts, row.hunts)
			table.insert(found, row.huntRocks)
			table.insert(givenUp, row.huntsAbandoned)
			table.insert(seconds, row.huntSec)
		end
		local ls = stats(levels)
		table.insert(out, string.format("%2d | %d/%d/%d | %.1f | %.1f | %.1f | %.0f", day, ls.p10, ls.p50, ls.p90, stats(hunts).mean, stats(found).mean, stats(givenUp).mean, stats(seconds).mean))
	end
	table.insert(out, "upgrade | bought by day 15 | buy day p10/p50/p90 (geiger 2 is the counter itself)")
	for _, entry in { { "pick", 2, 6 }, { "pack", 2, 5 }, { "boots", 2, #BOOTS_PRICES }, { "geiger", 2, #GEIGER_PRICES } } do
		for level = entry[2], entry[3] do
			local daysBought = {}
			for _, run in runs do
				local boughtDay = run.buyDays[entry[1]][level]
				if boughtDay then
					table.insert(daysBought, boughtDay)
				end
			end
			local s = stats(daysBought)
			local itemName = ({ pick = "pick", pack = "backpack", boots = "boots", geiger = "geiger" })[entry[1]]
			table.insert(out, string.format("%s %d | %d%% | %s", itemName, level, math.floor(#daysBought / #runs * 100 + 0.5), if #daysBought > 0 then string.format("%d/%d/%d", s.p10, s.p50, s.p90) else "-"))
		end
	end
	table.insert(out, "pick level | first stall: depth p10/p50/p90 | stone (share) | day p50")
	for level = 1, #PickAxeData.DAMAGE_BY_LEVEL do
		local depths, daysOf, stones, n = {}, {}, {}, 0
		for _, run in runs do
			local stall = run.firstStallByPick[level]
			if stall then
				n += 1
				table.insert(depths, stall.depth)
				table.insert(daysOf, stall.day)
				local name = stoneName(stall.stone) .. (if stall.kind == "cross" then " (cross-cut)" else "")
				stones[name] = (stones[name] or 0) + 1
			end
		end
		local names = {}
		for name, count in stones do
			table.insert(names, string.format("%s %d%%", name, math.floor(count / #runs * 100 + 0.5)))
		end
		table.sort(names)
		local s = stats(depths)
		table.insert(out, string.format("L%d | %s | %s | %s", level, if n > 0 then string.format("%d/%d/%d", s.p10, s.p50, s.p90) else "-", if n > 0 then table.concat(names, ", ") else "never stalled", if n > 0 then tostring(stats(daysOf).p50) else "-"))
	end
	local uraniumDays, winNights, events, lost = {}, {}, {}, {}
	for _, run in runs do
		if run.uraniumDay then
			table.insert(uraniumDays, run.uraniumDay)
			table.insert(winNights, run.winNight)
		end
		table.insert(events, run.stuckEvents)
		table.insert(lost, run.lost)
	end
	local ud = stats(uraniumDays)
	table.insert(out, string.format("uranium %d reached by day %d in %d%% of seeds; day mean %.1f, p10/p50/p90 %s", CONFIG.URANIUM_TARGET, CONFIG.DAYS, math.floor(#uraniumDays / #runs * 100 + 0.5), ud.mean, if #uraniumDays > 0 then string.format("%d/%d/%d", ud.p10, ud.p50, ud.p90) else "-"))
	local wn = stats(winNights)
	table.insert(out, string.format("rescue won (the night of the first day call allows) mean night %.1f, p10/p50/p90 %s", wn.mean, if #winNights > 0 then string.format("%d/%d/%d", wn.p10, wn.p50, wn.p90) else "-"))
	table.insert(out, "stuck events per run: " .. fmt(stats(events)) .. "; ore lost to expired drops per run: " .. fmt(stats(lost)))
	return table.concat(out, "\n")
end

-- the day-1 event log and the floor rows before and after, for checking by hand
local function traceSeed(seed: number, spacing: number, stallHits: number, sliceDepth: number): string
	local before = assert(MineGenerator.generate(DeadmansCanyonData, buildConfig(CONFIG.DIFFICULTY), seed))
	local events = {}
	local run = simulateRun(seed, spacing, stallHits, events)
	local function slice(grid, row: number): string
		local lines = { string.format("row %d (depth down, width 1-24 across; 1-5 stone tier, G/I/U ore (lower case above tier 1), . air, # bedrock)", row) }
		for d = 0, sliceDepth do
			local chars = {}
			for w = 1, 24 do
				local rock = grid.cells[MineGenerator.cellIndex(grid, d, row, w)]
				local definition = ROCKS[rock]
				local char = "."
				if rock ~= AIR then
					if not definition.hp then
						char = "#"
					elseif definition.kind == FILLER then
						char = tostring(table.find(RockDefinitionsData.FILLER_ORDER, rock))
					else
						-- upper case is tier 1, lower case a higher tier
						local letter = if definition.resource == GOLD then "G" elseif definition.resource == IRON then "I" else "U"
						char = if definition.tier > 1 then string.lower(letter) else letter
					end
				end
				table.insert(chars, char)
			end
			table.insert(lines, string.format("%3d %s", d, table.concat(chars)))
		end
		return table.concat(lines, "\n")
	end
	local floor = before.grid.floorHeight
	local parts = { string.format("TRACE seed %d spacing %d stall %d hits: day-1 events", seed, spacing, stallHits) }
	table.insert(parts, table.concat(events, "\n"))
	for _, row in { floor - 1, floor, floor + 1, floor + 2 } do
		table.insert(parts, "BEFORE " .. slice(before.grid, row))
	end
	for _, row in { floor, floor + 1, floor + BAND_ROWS, floor + BAND_ROWS + 1 } do
		table.insert(parts, string.format("AFTER %d DAYS ", CONFIG.DAYS) .. slice(run.grid, row))
	end
	return table.concat(parts, "\n")
end

local SoloMiningSim = {
	CONFIG = CONFIG,
	CAMP = CAMP,
	simulateRun = simulateRun,
	runVariant = runVariant,
	describe = describe,
	traceSeed = traceSeed,
	stats = stats,
}
_G.SoloMiningSim = SoloMiningSim

if _G.SoloMiningSimDefineOnly then
	return "defined _G.SoloMiningSim"
end
local function runAll(): string
	local reports = {}
	for _, spacing in CONFIG.SPACINGS do
		local runs = runVariant(spacing, CONFIG.STALL_HITS, CONFIG.SEEDS)
		local label = string.format("spacing %d, stall %d hits, Geiger rule %s", spacing, CONFIG.STALL_HITS, if CONFIG.IS_GEIGER_ENABLED then "on" else "off")
		local report = describe(runs, label)
		print(report)
		table.insert(reports, report)
	end
	return table.concat(reports, "\n\n")
end
-- a full run with the Geiger rule takes minutes, past the MCP call's time
-- limit: background mode returns at once and leaves the report (or the
-- error) in _G.SoloMiningSimReport, nil until it is done
if _G.SoloMiningSimBackground then
	_G.SoloMiningSimReport = nil
	task.spawn(
		function()
			local isSuccess, report = pcall(runAll)
			_G.SoloMiningSimReport = if isSuccess then report else "ERROR: " .. tostring(report)
		end
	)
	return "started; poll _G.SoloMiningSimReport"
end
return runAll()
