--!strict

-- The words of the first-run walkthrough (M76; the designer's first pass,
-- 2026-11-09), as data so the lines can be rewritten without touching
-- the manager. A sequence is a list of steps; ClientTutorialManager
-- plays one step at a time. A step's `text` is the guide's line. A step
-- with `waitFor` stays up until that condition holds (the names are
-- ClientTutorialManager's CONDITIONS); one without advances on its
-- own after a reading time (no NEXT, no SKIP: designer, 2026-11-09). A step with
-- `skipIf` is left out when that condition already holds as the step is
-- reached. `arrow` names a HUD element the arrow points at for the
-- step's length; `beam` names a world target the guide beam leads to.
-- `%d` in a text is filled from the step's `number` condition. A waiting
-- step's `task` is the goal the Tasks panel shows once the line has been
-- read (designer, 2026-11-09: the box in the way of play was annoying);
-- `progress` names the pair of numbers appended to it as " (done/total)".
local TutorialScript = {}

export type Step = {
	-- the guide's line; a step without one shows no dialogue and puts
	-- its task up at once
	text: string?,
	waitFor: string?,
	skipIf: string?,
	arrow: string?,
	beam: string?,
	-- a CONDITIONS number read into the text's %d
	number: string?,
	task: string?,
	progress: string?,
	-- seconds added to the line's reading time (the quota line, which
	-- the player reads while finding the arrow; designer 2026-11-09)
	extraSec: number?,
	-- the arrow leaves with the line instead of staying for the whole
	-- wait (the backpack arrow while filling it; designer 2026-11-09)
	isArrowWithLine: boolean?,
	-- a CONDITIONS name at which the beam fades away before the step is
	-- done (reaching the Refinery's ring; designer 2026-11-09)
	beamUntil: string?,
	-- when the step is done and this condition still fails, the
	-- sequence goes back this many steps (the mine-and-refine loop
	-- toward the pick axe price; designer 2026-11-09)
	repeatBackUnless: string?,
	repeatBackSteps: number?,
}

export type Sequence = { Step }

-- after the DAY 1 card, for a player who has not finished the tutorial
TutorialScript.DAY_ONE = {
	{ text = "Hello Miner! Since you're new, let's go over the basics." },
	{ text = "Your mission is to mine enough Uranium to meet your quota.", arrow = "uranium", extraSec = 1 },
	{ text = "The problem is this area is crawling with bloodthirsty zombies, mutants, bandits, etc." },
	{ text = "You'll need to mine in the day and defend the base at night." },
	{ text = "No time to waste. Head over to the mine to start digging.", skipIf = "inMine", waitFor = "inMine", beam = "mineEntrance", task = "Head to the mine" },
	{ text = "Equip your pick axe.", skipIf = "pickAxeEquipped", waitFor = "pickAxeEquipped", arrow = "pickAxe", task = "Equip your pick axe" },
	{ text = "Now start mining! Look for Gold.", waitFor = "minedGold", task = "Find and mine Gold Ore" },
	{ text = "You found some Gold Ore!" },
	{ text = "Any ore you mine goes into your Backpack.", arrow = "backpack" },
	{ text = "Keep mining until your backpack is full!", skipIf = "backpackFull", waitFor = "backpackFull", arrow = "backpack", isArrowWithLine = true, task = "Mine ore until your backpack is full", progress = "backpackFill" },
	{ text = "Your Backpack is full. Head to the Refinery to process your Ore.", waitFor = "refinedGold", beam = "refinery", beamUntil = "atRefinery", task = "Refine your ore at the Refinery" },
	{ text = "You got some Gold Bars! They can be used to upgrade your mining equipment.", arrow = "gold" },
	-- the ore the price still needs, a backpack at most, then the trip to
	-- refine it, around again while the bars fall short (designer, 2026-11-09)
	{ text = "You almost have enough for a new Pick Axe. Mine %d more Gold Ore.", skipIf = "hasPickAxeGold", waitFor = "goldOreMinedEnough", number = "goldOreNeeded", arrow = "gold", isArrowWithLine = true, task = "Mine %d Gold Ore", progress = "goldOreMined" },
	{ skipIf = "goldOreRefinedOrEnough", waitFor = "goldOreRefined", beam = "refinery", beamUntil = "atRefinery", task = "Take your Gold Ore to the Refinery", repeatBackUnless = "hasPickAxeGold", repeatBackSteps = 1 },
	{ text = "You have enough for a new Pick Axe! Go buy one in the Dig Store.", skipIf = "pickAxeBought", waitFor = "pickAxeBought", beam = "pickAxeStand", task = "Buy a new Pick Axe at the Dig Store" },
	{ text = "Oh, that's going to speed things up! Get back to mining, the day's almost over!" },
} :: Sequence

-- the first sunset; replaces whatever is playing
TutorialScript.SUNSET = {
	{ text = "Keep an eye on the clock.", arrow = "clock" },
	{ text = "It's sunset, which means it's time to prepare your defenses before nightfall." },
	{ text = "Head out to the wall and claim a defensive post.", skipIf = "postClaimed", waitFor = "postClaimed", beam = "nearestPost", task = "Claim a defensive post" },
	{ text = "Now get on your post weapon and get ready to mow down some zombie mutants!", skipIf = "postManned", waitFor = "postManned", beam = "ownPostWeapon", task = "Man your Post Weapon" },
} :: Sequence

-- the first night falls; replaces whatever is playing
TutorialScript.NIGHT = {
	{ text = "There they are! Start shooting!" },
} :: Sequence

-- after the DAY 2 card; the walkthrough's end
TutorialScript.MORNING = {
	{ text = "You survived your first night! Not bad." },
	{ text = "Now that they know you're here, they'll be sending more tonight." },
	{ text = "You can upgrade your weapons and walls in the Defend Store." },
	{ text = "Oh! I almost forgot. If you ever get stuck in the mine..." },
	{ text = "You can use your jetpack by double jumping. Give it a try." },
	{ waitFor = "jetPackUsed", task = "Double jump (and hold) to use your jetpack" },
	{ text = "You got it! I think that's everything!" },
	{ text = "Once you've mined your Uranium quota, give me a call over the radio..." },
	{ text = "and I'll send a rescue helicopter to pick you up." },
	{ text = "Good luck and godspeed!" },
} :: Sequence

-- the first Iron Ore in the backpack; plays after whatever is up
TutorialScript.IRON = {
	{ text = "You found some Iron Ore!" },
	{ text = "Once it's refined, you can use Iron Bars to upgrade your weapons and defenses in the Defend Store." },
} :: Sequence

-- the first Uranium Ore in the backpack; plays after whatever is up
TutorialScript.URANIUM = {
	{ text = "You found Uranium!" },
	{ text = "That's why we're all here." },
	{ text = "Take it to the refinery and when it's done, it will count toward your quota.", arrow = "uranium" },
	{ text = "Once your quota's full, you can radio for a rescue helicopter." },
} :: Sequence

return TutorialScript
