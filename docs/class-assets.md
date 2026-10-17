# Class assets to author (2026-10-16)

Everything the twelve launch classes (GDD "Classes") need that does not exist yet, and where each model goes in the **gameplay** place's `ReplicatedStorage/GameAssets`. Each row names the enum key the model must be named after, since code finds every template by that key. Nothing here is built in code; the behaviour milestones that follow read these models.

## Handheld weapons (4)

Source art goes under `GameAssets/Weapons` as a Model, the way `SM_Wep_Rifle_01` does today. `scripts/studio/build_tool_templates.luau` copies it, scales it to hand size, adds the invisible `Handle` at the grip and the `Muzzle` attachment at the barrel tip, and writes the held template `GameAssets/Tools/WEAPON_<KEY>`. Front of the art is -Z (the barrel). Tell me the grip part's name per model so the script can put the hand there.

| Enum key (`Enums.WeaponKind`) | Item | Classes | Notes |
|---|---|---|---|
| `PISTOL` | Pistol | Recruit, Prospector, Hauler, Medic | one-handed; the weak-night classes' weapon |
| `SNIPER_RIFLE` | Sniper Rifle | Sniper | bolt action, a scope on top (the scope is the first-person view) |
| `FLAMETHROWER` | Flamethrower | Pyro | a tank on the back or under the barrel; the nozzle is the muzzle |
| `ASSAULT_RIFLE` | Assault Rifle | Ranger | a grenade launcher under the barrel (it will get its own attachment, `GrenadeMuzzle`, from the build script) |

## Post weapons (10)

A Model under `GameAssets/PostWeapons/<KEY>` with the same parts as the Machine Gun and Rocket Launcher today: `Spawn` as the PrimaryPart (the cylinder matched to the post's), `CharacterSpawn` (the gunner's feet), `Prompt` (the invisible part carrying the Use ProximityPrompt), `HandleLeft` and `HandleRight` (the hands), `CameraLocation` (welded to the gun), and one MeshPart gun carrying `MuzzleAttachment`. The gun part is the one that tilts.

| Enum key (`Enums.PostWeaponKind`) | Item | Class | Look |
|---|---|---|---|
| `MINIGUN` | Minigun | Gunner | rotating barrel cluster; spins up before firing |
| `RAILGUN` | Railgun | Sniper | long thin rail; a charge glow along it while held |
| `NAPALM_MORTAR` | Napalm Mortar | Pyro | a short stubby tube angled up; lobs a shell |
| `AA_LAUNCHER` | AA Launcher | Air Defense | a box of three missile tubes; a lock-on dish or sight |
| `AUTO_MACHINE_GUN` | Auto Machine Gun | Ranger | an unmanned machine gun on the post mount (decided 2026-10-16, replacing the Grenade Launcher): no `CharacterSpawn`, `HandleLeft`, `HandleRight`, or `CameraLocation`, since nobody mans it; a sensor or dish so it reads as automatic; fires by itself at 60% of the Machine Gun's damage so the Ranger stays on foot |
| `MINE_LAYER` | Mine Layer | Engineer | a stubby lobber with a mine drum; drops proximity mines on the path (2026-10-16, replacing the Salvage Gun) |
| `TESLA_ARC` | Tesla Arc | Electrician | a coil emitter, no barrel; the arc comes from the coil tip |
| `SALVAGE_GUN` | Salvage Gun | Prospector | a light fast gun with a scrap hopper or magnet; kills drop Iron (moved from the Engineer on 2026-10-16) |
| `SAW_GUN` | Saw Gun | Hauler | a wide flat launcher with a blade magazine; fires a spinning saw blade in a line (2026-10-16, replacing the Catapult) |
| `MAGNET_GUN` | Magnet Gun | Medic | a horseshoe magnet or dish on a mount; no damage, a pull |

Projectile models (`GameAssets/Projectiles/<NAME>`, one part with a `TailAttachment`, nose at the far end from it, trail emitters authored under the attachment, like the `Rocket`), named as `GameData/Posts/PostWeapons` and `GameData/Weapons/Handheld` expect them; a missing one flies as a yellow placeholder: `NapalmShell` (Napalm Mortar), `AAMissile` (AA Launcher), `ProximityMine` (Mine Layer; it also sits armed on the ground, so give it an armed look), `SawBlade` (Saw Gun; flies flat and spins about its heading), `Grenade` (the Assault Rifle's under-barrel grenade). Every burst uses `GameAssets/Effects/RocketBlast` until a kind gets its own `BLAST_TEMPLATE`.

## Gadgets (11)

No gadget exists in code yet, so there is no folder for them. Proposal: a Model under `GameAssets/Gadgets/<KEY>`. A **held** gadget is authored like a weapon source (a Model with a grip part I can name, front -Z) and gets a `GADGET_<KEY>` held template under `Tools` from the build script. A **placed** gadget is authored like a tower (a Model whose pivot is the centre of its base's underside).

| Enum key (`Enums.GadgetKind`) | Item | Class | Kind | Notes |
|---|---|---|---|---|
| `AUTO_TURRET` | Auto Turret | Gunner | placed | a compact sentry, smaller than the Sentry Gun tower; a turning top |
| `BINOCULARS` | Binoculars | Sniper | held | raised to the eyes; the view is a marker reticle |
| `REMOTE_CHARGE` | Remote Charge | Pyro | placed and held | two looks: the planted charge (a canister with a blinking light) and the detonator held in the hand after placing; blast and fire pool are effects by code (2026-10-16, replacing the Tar Pit) |
| `GROUNDING_NET` | Grounding Net | Air Defense | placed | an emitter post or dish; a net pulse effect |
| `STIM_SHOT` | Stim Shot | Ranger | held | an injector or syringe gun; used on the Ranger: 50% health back and 20 s of speed (2026-10-16, replacing the Grapple) |
| `BUILD_TABLET` | Build Tablet | Engineer | held | a tablet; opens the Defense Table menu anywhere |
| `STORM_ROD` | Storm Rod | Electrician | placed | a tall rod on a base; the storm is lighting and effects by code |
| `ORE_SCANNER` | Ore Scanner | Prospector | held | a handheld scanner with a screen; the highlight is drawn by code |
| `DYNAMITE` | Dynamite | Demolitionist | held | exists today as `Tools/DYNAMITE`; nothing new |
| `ORE_CART` | Ore Cart | Hauler | placed, follows | a mine cart on wheels; moved by code behind the Hauler |
| `MEDKIT` | Medkit | Medic | held | a medical bag or box |

## Towers (4)

Not in the list you asked for, but part of the same kits. A Model under `GameAssets/Towers/<KEY>`, pivot at the centre of the base's underside, footprint on the defensive grid as the existing towers.

| Enum key (`Enums.TowerKind`) | Item | Class | Notes |
|---|---|---|---|
| `MORTAR` | Mortar Tower | Engineer | a tube angled up; lobs over the wall |
| `DRILL_RIG` | Drill Rig | Prospector | a derrick with a drill; mines each dawn, defends nothing |
| `ROCK_SLIDE` | Rock Slide | Hauler | a stacked pile of boulders; releases one down its lane |
| `REPAIR_TOWER` | Repair Tower | Medic | no gun; a crane, a toolbox, or an antenna; repairs in a radius |

## Icons

Each new weapon, post, tower, and gadget needs an icon for the tool bar, the Build Mode menu, and the class sheet, captured through the icon pipeline in `docs/icon-capture.md` once its model exists; no hand-drawn icons needed.

## Order

The models can land in any order. The behaviour milestones that use them go one class at a time, so the first class's items are the ones to author first.
