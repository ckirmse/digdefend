# Helicopter Pad Party System — Spec

**Status:** implemented through M14 (2026-09-11). This document mirrors the GDD "Helicopter Pads – Party Creation/Teleports", "Create Party Menu", and "Queue Menu" sections and records how they are realised in code.

**Reference:** Dead Rails' Create Party flow (difficulty carousel, player-count stepper, Friends Only toggle, creation countdown). No join-by-code.

---

## 1. Summary

| Old GDD | Current |
|---|---|
| 6 pads, each hardcoded to one map + difficulty | 6 identical pads, configured by the host at runtime |
| Walk on → join queue | Walk onto an idle pad → become host → configure → others join |
| Pad-level unlock requirements | Requirements evaluated against the host's completions at Create |
| Departure on timer only | Host presses Launch, or boarding timeout, or party full |
| No host | Host role with promotion on leave |
| No visibility control | Public or Friends Only |
| No configuration timeout | Creation timeout ejects an idle host |

---

## 2. Pad states

`Enums.PadState`, held in server Lua (`PartyManager`) and replicated as the `PadState` attribute on the pad model.

| State | Meaning | Touching JoinCollision |
|---|---|---|
| `IDLE` | Empty. No host. | Becomes host, enters `CONFIGURING` |
| `CONFIGURING` | Host is on the Create Party menu | "Pad is being set up" |
| `BOARDING` | Configured. Accepting players. | Runs the join checks (§6.2) |
| `DEPARTING` | Teleport in progress | "Pad is departing" |

```
IDLE ──touch──▶ CONFIGURING ──Create──▶ BOARDING ──launch──▶ DEPARTING ──reset──▶ IDLE
                    │                        │
                    └─timeout/Cancel/leave───┘──(nobody left)──▶ IDLE
```

---

## 3. Flow

### 3.1 Becoming host

1. Player touches `JoinCollision` on an `IDLE` pad (one decision per player per `TOUCH_DEBOUNCE_SEC`).
2. If the player is already in a party on any pad: "You're already in a party".
3. Pad becomes `CONFIGURING` with this host; the creation timer starts at `CREATION_TIMEOUT_SEC`.
4. The character is seated in the helicopter's `Seat1`; the client moves its camera to `CameraPositionPart`, hides every pad billboard, and disables jumping.
5. The client opens the Create Party menu.

Two players touching in the same frame: the first processed becomes host, the second gets "Pad is being set up".

### 3.2 Configuring

The countdown is a hard limit; changing a setting does not reset it.

Leaving party creation: the countdown reaching zero (feedback "Party creation timed out"), the **Cancel** button, or disconnecting. In every case the host goes to `ExitSpawn`, the camera and jumping are restored, the menu closes, billboards reappear, and the pad returns to `IDLE`. Jumping out of the seat is disabled, so the seat only empties through the menu or an outside event (death); an emptied seat is still treated as a leave.

**Create:** the server validates the selection (§6.1). If invalid, feedback and the pad stays `CONFIGURING`. If valid, the pad records map, difficulty, max players, and visibility, becomes `BOARDING`, and the boarding timer starts at `BOARDING_TIMEOUT_SEC` (shortened at once to `CAPACITY_TIME_SEC` if the party is already full, e.g. a party of one). The host's client swaps to the Queue menu in host mode; the rotor starts spinning.

### 3.3 Boarding

Joiners touch `JoinCollision`; the join checks (§6.2) run. On pass: seated at the next free seat, camera moved, added to the party, count replicated, Queue menu in member mode.

When the party reaches max players the boarding timer drops to `CAPACITY_TIME_SEC`. The timer never goes back up.

Leaving: the **Exit** button or disconnecting (or the seat emptying for any other reason). The character goes to `ExitSpawn`. If the host leaves and others remain, the earliest joiner is promoted ("You are now the party host") and their menu switches to host mode. If nobody remains the pad returns to `IDLE`.

### 3.4 Launching

Triggers: host presses **Launch**, the boarding timer reaches zero, or the capacity countdown reaches zero. A party of one launches.

Server (`PartyManager:runLaunch`):
1. `DEPARTING`. Seats emptying no longer count as leaving.
2. After `TAKEOFF_SEC` the present members are unseated and moved to random `HoldingArea.Spawns`.
3. `TeleportService:ReserveServer` + one `TeleportAsync` with the member list and join data (§7), retried `TELEPORT_RETRY_COUNT` times `TELEPORT_RETRY_DELAY_SEC` apart. A member who left during takeoff is excluded.
4. On final failure every present member gets `NotifyPartyMenu NONE`, "Teleport failed", and `LoadCharacter` (respawn in `SpawnZone`).
5. On success, anyone still here after `TELEPORT_SETTLE_SEC` gets the same failure treatment.
6. Reset: the launched helicopter is renamed `DepartedHelicopter` and destroyed after `DEPARTED_HELICOPTER_LIFETIME_SEC`; a fresh one is cloned to `HelicopterSpawn`; the pad returns to `IDLE`. Only the launch flow that set `DEPARTING` may reset.

Client:
- Every client flies the departed helicopter (`ClientHelicopterManager`, phase `FLYING`): rotor at full speed, climb 100 studs, cruise 1000 studs along the model's facing, then the local copy is removed.
- Party members: the Queue menu fades out, the camera stays on `CameraPositionPart`, and 2 s later the departure screen (the `Loading` ScreenGui in departure mode, "Flying to <map>...", bar empty) slides in and a copy is handed to `TeleportService:SetTeleportGui`, which the gameplay place's ReplicatedFirst script keeps on screen on arrival. Menu NONE (failure) restores everything and hides the screen.

---

## 4. Data model

### 4.1 Pad model (`Workspace.HelicopterPads.Pad<n>`)

Studio-authored: `PadIndex` attribute (1–6), `JoinCollision`, `ExitSpawn`, `HelicopterSpawn`, `CameraPositionPart` (facing the helicopter), `GuiPart.PadGui`. All marker parts are anchored (`LobbyMapManager` warns otherwise). The `Helicopter` model is cloned in by `PartyManager` at startup.

Runtime state, attributes written only by `PartyManager` (names in `Attributes.luau`):

| Attribute | Value |
|---|---|
| `PadState` | `Enums.PadState` |
| `PadHostUserId` | 0 when idle |
| `PadMap`, `PadDifficulty` | `Enums.Map` / `Enums.Difficulty`; nil when idle |
| `PadMaxPlayers` | `MAX_PARTY_SIZE` while idle or configuring, the host's choice once boarding |
| `PadVisibility` | `Enums.PartyVisibility` |
| `PadPlayerCount` | member count |
| `PadTimerEndTime` | server time the active timer expires; 0 when none. Clients count down locally. |

The member list stays on the server.

### 4.2 Helicopter template (`ReplicatedStorage.GameAssets.Helicopter`)

- `PlayerSpawns`: `Seat1`–`Seat6`, real `Seat` instances, anchored, invisible, `Disabled`. The server enables a seat only for its own `Sit` call and disables it again when it empties, so the engine never auto-seats a passer-by.
- `Rotar.Rotar`: the rotor hub; blades are welded to it.
- Every helicopter is cloned by the common server `HelicopterManager`, tagged `Tags.HELICOPTER`, and carries a `HelicopterPhase` attribute (`IDLE`, `SPINNING`, `FLYING`) that the server sets; the common `ClientHelicopterManager` animates every tagged model from it on every client (rotor about world up with ramps; `FLYING` climbs 100 studs then cruises 1000 studs and removes the local copy). The lobby maps pad states to phases (`BOARDING` → `SPINNING`, `DEPARTING` → `FLYING`); the gameplay place's `ArrivalManager` spawns the camp helicopter `SPINNING` and retires it to `FLYING` once the party is in.

### 4.3 Config — `GameData/Pads/Party`

```lua
return {
	CREATION_TIMEOUT_SEC = 30,
	BOARDING_TIMEOUT_SEC = 20,
	CAPACITY_TIME_SEC = 3,
	MAX_PARTY_SIZE = 6,
	DEFAULT_MAX_PLAYERS = 4,
	DEFAULT_VISIBILITY = Enums.PartyVisibility.PUBLIC,
	TOUCH_DEBOUNCE_SEC = 2,
	TIMER_POLL_SEC = 0.25,
	TAKEOFF_SEC = 4,
	TELEPORT_RETRY_COUNT = 3,
	TELEPORT_RETRY_DELAY_SEC = 2,
	TELEPORT_SETTLE_SEC = 10,
	DEPARTED_HELICOPTER_LIFETIME_SEC = 35,
	MAPS = { { map = Enums.Map.DEADMANS_CANYON, thumbnail = "rbxassetid://0" }, ... },
	DIFFICULTIES = { { difficulty = Enums.Difficulty.NORMAL }, { difficulty = Enums.Difficulty.HARD, requires = { difficulty = Enums.Difficulty.NORMAL } }, ... },
}
```

`PartyRules.validateConfig` runs at lobby startup and fails loudly naming the offending key. The client never requires GameData: the config is replicated as one JSON string attribute (`PartyConfig`) on `SplendidGames.GameMetadata` and decoded with `PartyRules.decodeConfig`, which re-validates it.

### 4.4 Player progression

`PlayerData:hasCompletion(key)` with keys from `CompletionKeys` (`"DEADMANS_CANYON/NORMAL"`). Only the host's completions are checked, only at Create.

---

## 5. Menus

Both are overlays registered with `ClientOverlayManager` (no blur, no freeze, no zoom; the seat holds the character and the camera is on the pad). Built by `scripts/studio/build_create_party_gui.luau` and `build_queue_gui.luau`; driven by `ClientPartyMenuManager`. The server chooses which menu a client shows (`NotifyPartyMenu { menu, padIndex, isHost }`).

### 5.1 Create Party menu

Top to bottom: title; map carousel (thumbnail, name, lock icon and requirement text when locked; placeholder colours until art exists); difficulty carousel (re-evaluated per map, falls back to the first unlocked difficulty); players stepper (1–`MAX_PARTY_SIZE`, starts at `DEFAULT_MAX_PLAYERS`); Friends Only toggle; "Cancelling in N seconds" in red; **Create** (disabled while locked); **Cancel** directly beneath.

Selection is client-side until Create sends `TryCreateParty { map, difficulty, maxPlayers, visibility }`.

### 5.2 Queue menu

Map, difficulty, "Players: X / Y", visibility, "Host: name", "Departing in N seconds", **Exit** (`TryLeaveParty`). The host also sees **Launch** (`TryLaunchParty`).

### 5.3 Pad billboard (`GuiPart.PadGui`)

Three labels rendered by `ClientPadBillboardManager` from the pad attributes; hidden on that client while it is in a party menu.

| State | Status | Private | Players |
|---|---|---|---|
| `IDLE` | "Waiting for players..." | hidden | "0/MaxPartySize" |
| `CONFIGURING` | "Player configuring" | hidden | "1/MaxPartySize" |
| `BOARDING` | "Starts in: N" | "Public" or "Private" | "X/Y" |
| `DEPARTING` | "Departing" | "Public" or "Private" | "X/Y" |

---

## 6. Rules (`PartyRules`, unit tested)

### 6.1 Create validation (`validateSelection`)

Reject if: map or difficulty not in config; map requirement not completed; difficulty requirement not completed on the selected map; max players outside 1..`MAX_PARTY_SIZE`; visibility invalid; pad not `CONFIGURING` or sender not its host. The server is authoritative; the client only greys out.

### 6.2 Join checks (`getJoinRejection`, in order)

| Check | Feedback |
|---|---|
| Pad is `BOARDING` | "Pad is being set up" / "Pad is departing" |
| Party has room | "Party is full" |
| Not already in a party | "You're already in a party" |
| Friends Only: joiner is a friend of the host (`IsFriendsWithAsync`) | "This party is friends only" |

Joiners are not checked against unlocks; access follows the host.

### 6.3 Timer on full (`getTimerEndTimeOnFull`)

`min(currentEndTime, now + CAPACITY_TIME_SEC)`. Never rises.

### 6.4 Progression on completion (gameplay server, later)

A run's completion is recorded for a player only if that player had already completed the prerequisite themselves.

---

## 7. Join data

`PartyRules.buildJoinData`, sent as the teleport data and validated by `PartyRules.JOIN_DATA_SHAPE`:

```lua
{ map = Enums.Map.X, difficulty = Enums.Difficulty.Y, playerCount = 4, hostUserId = 12345, padIndex = 2, memberUserIds = { 12345, ... } }
```

`playerCount` is the number actually teleported. The gameplay place's `ArrivalManager` runs `PartyRules.getArrivalRejection` on every arrival and kicks anyone without valid join data or not listed in `memberUserIds` (Studio play sessions are let through with a warning); `RunManager` records the first valid join data as the run and replicates map, difficulty, player count, and host as `GameMetadata` attributes.

---

## 8. Wiring

- `PartyManager` (lobby server) registers with `GameController:registerPlaceManager`: its `Try*` handlers join the single-RemoteEvent protocol and it takes part in the player teardown and dev-tool reset sequences (a reset player is removed from any party).
- Feedback strings live on `PartyRules.FEEDBACK_*` and go through `PlayerFeedbackManager`.

---

## 9. Edge cases

| Case | Behaviour |
|---|---|
| Host disconnects during `CONFIGURING` | Pad → `IDLE` |
| Host disconnects during `BOARDING`, others present | Earliest joiner promoted. Timer unaffected. |
| Host disconnects during `BOARDING`, alone | Pad → `IDLE` |
| Player disconnects during `DEPARTING` | Excluded from teleport |
| Party full, then someone leaves before the capacity countdown expires | Timer keeps counting; launches with the remaining players |
| Host presses Launch with 1 player | Launches solo |
| Player touches a pad while already in another pad's party | Rejected; must Exit first |
| Map changed to one where the chosen difficulty is locked | Difficulty resets to the first unlocked one |
| Two players touch an `IDLE` pad simultaneously | First processed becomes host; second rejected |
| Player leaves and is still standing in `JoinCollision` | A touch grace window (`TOUCH_DEBOUNCE_SEC`) stops a stale touch from re-hosting them |
