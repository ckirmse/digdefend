# Developer setup

This is the checklist for getting Dig Defend running on a fresh Windows PC. It assumes Claude Code (the desktop app) and Roblox Studio are installed and nothing else is. It is written so Claude can do the setup for a new developer step by step without working anything out; the developer only has to do the few steps that need their own accounts or a GUI (marked **you**). Each step ends with a check. Do them in order.

Related docs: `CLAUDE.md` is the working guide (architecture, standards, the "boot up the project" routine) and `README.md` is the short version of running and testing. Read `CLAUDE.md` once the project runs.

## 0. Access the developer needs (you)

Before any tooling, the project owner has to grant three things. Nothing below works without them.

| Access | Why | Check |
|---|---|---|
| Collaborator on the GitHub repository `ckirmse/digdefend` | `git clone` and pushes | `git ls-remote https://github.com/ckirmse/digdefend.git` lists refs |
| Edit access to both places on Roblox (Lobby `133996405589098`, Gameplay `72646464251078`), through the game's group | Opening the places in Studio; Rojo sync | Both places show under Studio's Open from Roblox, Group experiences |
| Rank 254 or higher in Roblox group `571203718` | The in-game dev tools (RightShift panel) are admin-only; the gate is the group **rank**, not Creator Hub access | The Player gets an `IsAdmin` attribute of true in a Play test |

Set up Git credentials for GitHub the way you prefer (Git Credential Manager comes with Git for Windows and signs in through the browser on the first push). Sign in to Roblox Studio with the account that has the group rank.

## 1. Base tools

Install these once. Claude can run the winget lines; the developer approves any installer prompts.

| Tool | Why | Install | Check |
|---|---|---|---|
| Git for Windows (with Git Bash) | Cloning, commits; `scripts/*.sh` are bash scripts and the Claude Code Bash tool runs in Git Bash | `winget install Git.Git` | `git --version` |
| Python 3 | `scripts/analyze.sh` runs `scripts/regen_shared_stubs.py` | `winget install Python.Python.3.12` | `python3 --version` or `python --version` (the script calls `python3`; if only `python` exists, make a copy or alias named `python3` on the PATH) |
| curl | `scripts/analyze.sh` downloads the Roblox type definitions | ships with Windows 10 and later | `curl --version` |
| Foreman | Installs Rojo, Wally, and luau-lsp at the versions pinned in `foreman.toml` | Download the Windows zip from https://github.com/Roblox/foreman/releases, put `foreman.exe` somewhere on the PATH (for example `%USERPROFILE%\.foreman\bin`, created below) | `foreman --version` |

Add `%USERPROFILE%\.foreman\bin` to the user PATH (that is where Foreman puts the tools it installs). Open a new terminal afterwards so the PATH change is seen. Foreman downloads from GitHub releases and can hit the unauthenticated rate limit; if `foreman install` fails with a 403, run `foreman github-auth <token>` with a GitHub personal access token that has no scopes.

## 2. Clone and install the toolchain

```bash
git clone https://github.com/ckirmse/digdefend.git
```

Open the clone as the project folder in Claude Code. Then, in the project:

```bash
foreman install
```

This installs the three tools at the pinned versions (Rojo 7.7.1, Wally 0.3.2, luau-lsp 1.69.0). Check:

```bash
rojo --version && wally --version && luau-lsp --version
```

**Do not run `wally install`.** The Wally output folders `Packages/` and `DevPackages/` are committed, so the clone already has Iris and jest-roblox. `wally install` is only for dependency changes, and it must never run while a `rojo serve` is up (Rojo 7.7 crashes when a watched folder disappears; see `CLAUDE.md`, "Wally and Rojo").

Reference projects: `CLAUDE.md` mentions `~/square` and `~/md`, two earlier games whose patterns this project copies. They are separate private repositories; a new developer does not need them. If the owner grants access, clone them under `~/Documents` (the paths some notes use) and otherwise ignore every reference to them.

## 3. Rojo plugin in Studio

Rojo syncs `src/` into an open Studio place over a local port. The plugin half lives in Studio.

```bash
rojo plugin install
```

This writes the plugin for the installed Rojo version into Studio's local plugins folder. Restart Studio if it was open. Check: the Plugins tab in Studio shows a Rojo button. After any Rojo version bump in `foreman.toml`, run `foreman install` again, quit any running `rojo serve`, and rerun `rojo plugin install`.

## 4. Run a place

The project is two places with two Rojo project files, each pinned to its place id so the plugin refuses to sync into the wrong one.

| Place | Place id | Project file | Port | Start |
|---|---|---|---|---|
| Lobby (start place) | 133996405589098 | `lobby.project.json` | 34872 | `scripts/serve.sh lobby` |
| Gameplay | 72646464251078 | `gameplay.project.json` | 34873 | `scripts/serve.sh gameplay` |

Steps:

1. Start both servers in the background (Claude does this; both run at once): `scripts/serve.sh lobby` and `scripts/serve.sh gameplay`.
2. **You:** in Studio, File, Open from Roblox, open the Lobby place. Click the Rojo plugin button, set the port to 34872, Connect. Studio prompts to accept the sync; accept it.
3. Press Play. The Output window must show `Dig Defend server started (Lobby)` and the matching client line, with no red errors.
4. Repeat for the Gameplay place in a second Studio window on port 34873. Stop the Lobby Play first: both places share one save profile, and the Lobby's session lock kicks the Gameplay player and its client never starts.

Rojo only pushes `src/`. Everything Studio-side (GUIs under StarterGui, world templates under `ReplicatedStorage/GameAssets`, maps under `ServerStorage/Maps`, sounds under `SoundService`) is saved in the places on Roblox and arrives with the place. Do not run the `scripts/studio/build_*.luau` scripts to "set things up"; they rebuild authored instances and wipe the designer's tuning (see "Never rebuild a GUI without saying so" in `CLAUDE.md`).

`.rbxl` files are gitignored on purpose. The places live on Roblox; publish from Studio, never commit a place file.

## 5. Claude's Studio MCP (lets Claude drive Studio)

Claude authors Studio content, runs the unit tests, and drives playtests through the Roblox Studio MCP server (Model Context Protocol, a local bridge between Claude Code and Studio). Studio ships the bridge as `StudioMCP.exe` inside its own version folder.

1. **You:** in Studio, enable the MCP server. It is in Studio's settings under the Studio section; search the settings for "MCP" and turn it on. Studio then starts listening for the bridge.
2. Create `.mcp.json` in the project root (it is gitignored because the path below is per machine). Find the newest Studio version folder that contains the bridge:

   ```bash
   ls -t /c/Users/$USERNAME/AppData/Local/Roblox/Versions/*/StudioMCP.exe | head -1
   ```

   and write the file with that path, forward slashes:

   ```json
   {
     "mcpServers": {
       "roblox-studio": {
         "command": "C:/Users/<user>/AppData/Local/Roblox/Versions/version-<hash>/StudioMCP.exe",
         "args": []
       }
     }
   }
   ```

3. **You:** restart the Claude Code session (or run `/mcp` in an interactive `claude` terminal) so the server is picked up. Check: Claude lists `roblox-studio` tools, and `get_studio_state` names the open place.

Known behaviours, so nobody debugs them twice:

- **Every Studio update moves the exe** to a new `version-<hash>` folder, and the old folder is deleted. The symptom is the MCP server reporting "Connection closed" or connecting with zero tools. Fix: rerun the `ls -t` line above, update the hash in `.mcp.json`, reconnect.
- `execute_luau` cannot call `require()` directly; Claude uses a `loadstring` substitute for `require` when running build scripts, and a long `task.wait` (over about 15 s) in one call drops the connection. These are documented in `CLAUDE.md` and Claude's memory, not something to fix.
- If the server connects with zero tools and the hash is right, the fallback is to run `StudioMCP.exe` by hand and speak JSON-RPC to it, which is a last resort.

## 6. Checks that the project is healthy

Run these once after setup and after every change (they are the project's two gates).

**Static analysis:**

```bash
scripts/analyze.sh
```

Needs Git Bash, Python 3, curl, Rojo, and luau-lsp from the steps above. The first run downloads `globalTypes.d.luau` and regenerates the gitignored `game/` stub tree that resolves the `@game/...` requires. It prints several thousand diagnostics of one ignored class (colon-method `self` inference under the new Luau solver, a decision recorded in `CLAUDE.md`); that total is not a failure. The real check is that the lines for the files you touched are clean, so filter the output to those files. `scripts/analyze.sh src/shared` analyses a subset.

**Unit tests** (jest-roblox, 700-plus specs): with a place open in Studio in **Edit mode** (not Play) and Rojo connected, run from the Command Bar, or have Claude run it through the MCP `execute_luau` tool:

```lua
task.spawn(function() loadstring(game.ServerScriptService.Tests.TestRunner.Source)():run() end) return "running"
```

Results print to the Output window and must show every suite passing.

## 7. Day-to-day

- Say **"boot up the project"** to Claude at the start of a session: it fetches and fast-forwards git, starts both Rojo servers, and reminds you to connect the plugin in each place (the routine is in `CLAUDE.md`).
- Work goes milestone by milestone from `milestones.md`; design truth is `gdd.txt`. Claude never closes a milestone, commits, or pushes without being told to in that message.
- Studio content Claude authors through the MCP is **unsaved** until someone saves and publishes the place from Studio. Save the place before closing Studio or the work is lost.
- `scripts/analyze.sh` and the tests must stay green before any commit.

## Quick reference

| Thing | Where |
|---|---|
| Tool versions | `foreman.toml` |
| Rojo ports and place ids | `lobby.project.json`, `gameplay.project.json` |
| Analysis mount (both places, for luau-lsp) | `analysis.project.json`, `.luaurc` |
| Studio MCP bridge path | `.mcp.json` (gitignored, per machine) |
| Admin gate for dev tools | `Constants.ADMIN_GROUP_ID` (571203718), `Constants.ADMIN_MIN_RANK` (254) |
| Studio build scripts (never run casually) | `scripts/studio/` |
| Source audio | `audio/` |
