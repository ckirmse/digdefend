# Helicopter Pad Party System — Spec

**Replaces:** the Helicopter Pads section of the GDD. Pads are no longer pre-assigned to a map and difficulty. Every pad is identical; the first player onto it becomes the host and configures the run.

**Reference:** Dead Rails' Create Party flow (difficulty carousel, player-count stepper, Private toggle, creation countdown). We are not implementing join-by-code.

---

## 1. Summary of changes

| Current GDD | New |
|---|---|
| 6 pads, each hardcoded to one map + difficulty | 6 identical pads, configured by the host at runtime |
| Walk on → join queue | Walk onto an idle pad → become host → configure → others join |
| Pad-level unlock requirements | Requirements evaluated against the host's data at configure time |
| Departure on timer only | Host presses Launch, or boarding timeout, or party full |
| No host | Host role with promotion on leave |
| No visibility control | Public or Friends Only |
| No configuration timeout | Creation timeout ejects an idle host |

Everything else about pads — the HelicopterModel, PlayerSpawns, CameraPositionPart, ExitSpawn, JoinCollision, HoldingArea, teleport retry handling, fresh helicopter clone after departure — is unchanged.

---

## 2. Pad states

Each pad is in exactly one state. Stored as a `State` StringValue on the pad model, replicated so the billboard can render it.

| State | Meaning | Who can touch JoinCollision |
|---|---|---|
| `Idle` | Empty. No host. | Anyone → becomes host, enters `Configuring` |
| `Configuring` | Host is on the Create Party menu | Nobody. Touching gives feedback "Pad is being set up" |
| `Boarding` | Configured. Accepting players. | Anyone who passes the join checks (§6) |
| `Departing` | Teleport in progress | Nobody |

Transitions:

```
Idle ──touch──▶ Configuring ──Create──▶ Boarding ──launch──▶ Departing ──reset──▶ Idle
                    │                        │
                    └──timeout / host leaves─┘──(no players left)──▶ Idle
```

---

## 3. Flow

### 3.1 Becoming host

1. Player touches `JoinCollision` on an `Idle` pad.
2. Server checks the player is not already in a party on any pad. If they are, feedback: "You're already in a party."
3. Server sets `State = "Configuring"`, `HostUserId = player.UserId`, starts the `CreationTimer` at `CreationTimeout`.
4. Player's character is seated in the helicopter at the first PlayerSpawn, camera moved to `CameraPositionPart`.
5. Client opens the **Create Party Menu** (§5.1).

If two players touch an `Idle` pad in the same frame, the server processes the first, and the second receives "Pad is being set up." Never two hosts.

### 3.2 Configuring

The host sees the Create Party Menu with a visible countdown. Every second the countdown decrements. Changing a setting does **not** reset the countdown — it is a hard limit on how long a pad can be held without committing.

**If the countdown reaches zero:** host is removed from the pad, character moved to `ExitSpawn`, camera returned, menu closed, feedback: "Party creation timed out." Pad returns to `Idle`.

**If the host leaves the game or walks off:** same as timeout, no feedback needed.

**When the host presses Create:**

1. Server validates the selection (§6.1). If invalid, reject with feedback and stay in `Configuring`.
2. Server writes `MapId`, `DifficultyId`, `MaxPlayers`, `Visibility` to the pad model.
3. `State = "Boarding"`. `CreationTimer` stops. `BoardingTimer` starts at `BoardingTimeout`.
4. Host's client closes Create Party Menu and opens the **Queue Menu** (§5.2) in host mode.
5. Billboard updates to show the configuration.

### 3.3 Boarding

Other players touch `JoinCollision`. Server runs the join checks (§6.2). On pass:

1. Character seated at the next free PlayerSpawn, camera moved.
2. Player added to the pad's party list. `CurrentPlayers` incremented.
3. Client opens Queue Menu in member mode.
4. If `CurrentPlayers == MaxPlayers`, the `BoardingTimer` is set to `CapacityTime` (short auto-launch countdown).

**Leaving:** the Exit button in the Queue Menu, or walking off, or disconnecting. Character to `ExitSpawn`, party list updated, billboard updated. If the party was full and drops below full, the `BoardingTimer` does **not** reset upward — it continues from wherever it is. (A full party that loses someone in the last two seconds still launches.)

**Host leaves during Boarding:**
- If other players remain, the earliest-joined remaining player becomes host. Their Queue Menu switches to host mode. Feedback to them: "You are now the party host."
- If nobody remains, pad resets to `Idle`.

### 3.4 Launching

Three triggers, any of which launches:

1. Host presses **Launch** in the Queue Menu.
2. `BoardingTimer` reaches zero.
3. `CapacityTime` countdown reaches zero after the party filled.

Launch requires `CurrentPlayers >= MinPlayersToLaunch` (default 1). This is always true in practice since the host counts.

On launch:

1. `State = "Departing"`. Billboard shows "Departing".
2. Helicopter takes off (existing animation). Departure Loading Screen shown to party members.
3. Party members' characters moved to random `HoldingArea.Spawns`.
4. Teleport all party members together with `TeleportPartyAsync` (never per-player). Join data per §7.
5. Existing failure handling: failed players respawn at SpawnZone with "Teleport failed."
6. Pad reset: fresh HelicopterModel cloned to `HelicopterSpawn`, `State = "Idle"`, all values cleared.

---

## 4. Data model

### 4.1 Pad model (`Workspace.HelicopterPads.HelicopterPad_N`)

Remove `MapNumber`, `DifficultyNumber`, `MaxPlayers` as authored values. They become runtime state.

| Child | Type | Set when |
|---|---|---|
| `State` | StringValue | Every transition. `Idle` / `Configuring` / `Boarding` / `Departing` |
| `HostUserId` | IntValue | Host assigned or promoted. 0 when Idle |
| `MapId` | StringValue | Create pressed. Empty when Idle |
| `DifficultyId` | StringValue | Create pressed. Empty when Idle |
| `MaxPlayers` | IntValue | Create pressed. 0 when Idle |
| `Visibility` | StringValue | Create pressed. `Public` / `FriendsOnly` |
| `CurrentPlayers` | IntValue | Every join/leave |
| `TimerSeconds` | IntValue | Every second while a timer is active. 0 when none |

Existing children retained unchanged: `HelicopterModel`, `HelicopterSpawn`, `CameraPositionPart`, `GuiPart.PadGui`, `JoinCollision`, `ExitSpawn`.

The party member list itself lives in server Lua state keyed by pad, not in the workspace. Only the count replicates.

### 4.2 Config — `ServerScripts/GameData/PartyConfig`

All numbers live here. Nothing is hardcoded in the pad scripts.

```lua
return {
    padCount           = 6,

    creationTimeout    = 30,   -- seconds host has to press Create
    boardingTimeout    = 120,  -- seconds after Create before auto-launch
    capacityTime       = 3,    -- countdown once the party is full
    minPlayersToLaunch = 1,
    maxPartySize       = 6,    -- upper bound on the stepper

    defaultMaxPlayers  = 4,    -- stepper starting value
    defaultVisibility  = "Public",

    maps = {
        -- ordered. Carousel shows them in this order.
        {
            id          = "Canyon",
            displayName = "Deadman's Canyon",
            thumbnail   = "rbxassetid://0",
            requires    = nil,   -- always available
        },
        {
            id          = "Frostbite",
            displayName = "Frostbite Pass",
            thumbnail   = "rbxassetid://0",
            requires    = { map = "Canyon", difficulty = "Normal" },
        },
    },

    difficulties = {
        -- ordered. Carousel shows them in this order.
        -- requires is evaluated against the currently selected map.
        { id = "Normal",    displayName = "Normal",    requires = nil },
        { id = "Hard",      displayName = "Hard",      requires = { difficulty = "Normal" } },
        { id = "Nightmare", displayName = "Nightmare", requires = { difficulty = "Hard" } },
    },
}
```

**Note on naming:** the GDD's main text uses Normal / Hard / Nightmare. The mine generation section uses "Brutal" for the third tier. Use **Nightmare** everywhere.

### 4.3 Player progression data

The system needs one query: has this player completed `(mapId, difficultyId)`? This reads from the existing profile system. Expected shape:

```lua
profile.Data.Completions = {
    Canyon    = { Normal = true, Hard = false, Nightmare = false },
    Frostbite = { Normal = false, ... },
}
```

Only the **host's** completions are checked, and only at Create time.

---

## 5. Menus

### 5.1 Create Party Menu (new)

Shown to the host during `Configuring`. Modelled on Dead Rails' Create Party screen.

**Layout, top to bottom:**

1. **Title:** "Create Party"
2. **Map carousel.** Left/right arrows around a large thumbnail. Map display name overlaid on the thumbnail. Locked maps show the thumbnail desaturated with a lock icon and the unlock requirement as text beneath ("Complete Deadman's Canyon on Normal"). Arrows skip nothing — locked maps are visible but not selectable.
3. **Difficulty carousel.** Same pattern, smaller. Locked difficulties greyed with lock icon and requirement text. Re-evaluated whenever the map selection changes.
4. **Players stepper.** "Players" label, `−` and `+` buttons, current value. Range 1 to `maxPartySize`. Starts at `defaultMaxPlayers`.
5. **Visibility toggle.** A single toggle labelled "Friends Only". Off = Public. Starts at `defaultVisibility`.
6. **Countdown text.** "Cancelling in N seconds", red, updates every second.
7. **Create button.** Disabled (greyed) while the selected map or difficulty is locked. Enabled otherwise.

**Behaviour:**
- Opening the menu hides the HUD (consistent with other menus).
- No Cancel button is needed — walking off the pad or letting the timer expire cancels. If a Cancel button is added for clarity, it behaves identically to timeout.
- All selection state is client-side until Create is pressed. The server receives one message with the full selection and validates it.

### 5.2 Queue Menu (existing, extended)

Shown to everyone on a `Boarding` pad.

**All members see:**
- Map name, difficulty name
- "Players: X / Y"
- Visibility ("Public" or "Friends Only")
- Host's display name
- Countdown: "Departing in N seconds"
- **Exit** button (existing behaviour)

**Host additionally sees:**
- **Launch** button. Pressing it launches immediately (§3.4).

When host is promoted, the new host's client receives a message and shows the Launch button.

### 5.3 Pad billboard (`GuiPart.PadGui`, existing, extended)

Rendered from replicated pad values. Shows:

| State | Billboard content |
|---|---|
| `Idle` | "Open" |
| `Configuring` | "Setting up…" |
| `Boarding` | Map name / Difficulty / "X / Y players" / visibility icon / "Departing in N" |
| `Departing` | "Departing" |

A `FriendsOnly` pad shows a lock or friends icon so players can tell before walking over.

---

## 6. Rules

### 6.1 Create validation (server, on Create)

Reject with feedback if any fail:

- Selected map exists in config
- Selected difficulty exists in config
- Host has completed the map's `requires` (if any)
- Host has completed the difficulty's `requires` on the selected map (if any)
- `1 <= MaxPlayers <= maxPartySize`
- Visibility is `Public` or `FriendsOnly`
- Pad is still `Configuring` and this player is still its host

The client greys out invalid options, but the server is authoritative. Never trust the client's claim that something is unlocked.

### 6.2 Join checks (server, on JoinCollision touch during Boarding)

Reject with the given feedback if any fail:

| Check | Feedback |
|---|---|
| Pad is `Boarding` | "Pad is being set up" or "Pad is departing" |
| `CurrentPlayers < MaxPlayers` | "Party is full" |
| Player not already in a party | "You're already in a party" |
| If `FriendsOnly`: `player:IsFriendsWith(HostUserId)` | "This party is friends only" |

**Joiners are not checked against map or difficulty unlocks.** Map access follows the host. A player who hasn't unlocked Frostbite Pass can join a Frostbite party.

### 6.3 Progression on completion (gameplay server, out of scope here but required)

Completion of `(map, difficulty)` is recorded per player **only if that player had already completed the prerequisite themselves**. A player carried through Nightmare by a friend does not unlock Nightmare. The gameplay server needs the prerequisite table from `PartyConfig` to enforce this.

---

## 7. Join data

Sent with `TeleportPartyAsync`:

```lua
{
    mapId        = "Canyon",
    difficultyId = "Normal",
    playerCount  = 4,         -- CurrentPlayers at launch, not MaxPlayers
    hostUserId   = 12345,
    padIndex     = 2,         -- for logging
}
```

`playerCount` is the number actually teleported. The gameplay server uses it for scaling and must not wait for `MaxPlayers`.

---

## 8. Edge cases

| Case | Behaviour |
|---|---|
| Host disconnects during `Configuring` | Pad → `Idle` |
| Host disconnects during `Boarding`, others present | Earliest joiner promoted. Timers unaffected. |
| Host disconnects during `Boarding`, alone | Pad → `Idle` |
| Player disconnects during `Departing` | Excluded from teleport. Existing failed-teleport handling covers stragglers. |
| Party full, then someone leaves before `CapacityTime` expires | Timer keeps counting down. Launches with remaining players. |
| Host presses Launch with 1 player | Launches solo. This is allowed and expected. |
| Player walks onto pad while already in another pad's party | Rejected. Must Exit first. |
| Host changes map after selecting a difficulty locked on the new map | Difficulty selection resets to first unlocked difficulty for the new map. |
| Two players touch an Idle pad simultaneously | First processed becomes host. Second rejected. |
| Server shuts down mid-`Boarding` | Standard Roblox shutdown; no special handling. Players return to a fresh lobby. |

---

## 9. Remove from current implementation

- Per-pad `MapNumber` / `DifficultyNumber` / `MaxPlayers` as authored IntValues
- Per-pad requirement fields (map completion / difficulty completion)
- `Boarding` BoolValue (replaced by `State`)
- `FullTime` (replaced by `boardingTimeout` — different semantics: it now starts at Create, not at first join)
- Any logic that starts the departure timer on first touch

Keep `CapacityTime` — same behaviour, now in `PartyConfig`.

---

## 10. Validation at server start

Walk `PartyConfig` and assert:

- Every map `id` is unique
- Every difficulty `id` is unique
- Every `requires.map` references an existing map
- Every `requires.difficulty` references an existing difficulty
- `creationTimeout > 0`, `boardingTimeout > 0`, `capacityTime > 0`
- `1 <= defaultMaxPlayers <= maxPartySize`
- `defaultVisibility` is `Public` or `FriendsOnly`

Fail loudly at startup with the offending key named.

---

## 11. Feedback messages

All routed through the existing `GivePlayerFeedback` event. Full list used by this system:

- "Pad is being set up"
- "Pad is departing"
- "Party is full"
- "You're already in a party"
- "This party is friends only"
- "Party creation timed out"
- "You are now the party host"
- "Teleport failed" (existing)
