# Dig Defend

Roblox game (Luau). See `gdd.txt` for the game design doc, `milestones.md` for build milestones, and `CLAUDE.md` for architecture and coding standards.

Two places:

| Place | Place id | Rojo project | Rojo port |
|---|---|---|---|
| Lobby (start place) | 133996405589098 | `lobby.project.json` | 34872 |
| Gameplay | 72646464251078 | `gameplay.project.json` | 34873 |

## Setup

```
foreman install
wally install
```

`foreman install` puts `rojo`, `wally`, and `luau-lsp` on the path at the versions in `foreman.toml`. After bumping the Rojo version, run `foreman install` again, quit any running `rojo serve`, then `rojo plugin install` to update the Studio plugin.

## Running a place in Studio

1. `scripts/serve.sh lobby` or `scripts/serve.sh gameplay` (both can run at once).
2. In Studio, open the place from Roblox (File → Open from Roblox).
3. Rojo plugin → Connect, using the port for that place. Each project pins its place id, so connecting to the wrong place is refused.
4. Play. The Output window shows `Dig Defend server started (Lobby)` and the matching client line.

`rojo build lobby.project.json -o build/Lobby.rbxl` produces a local place file for checking a project file without Studio (`build/` is gitignored).

## Static analysis

```
scripts/analyze.sh            # all of src/
scripts/analyze.sh src/shared # a subset
```

Runs luau-lsp with the new solver over a sourcemap built from `analysis.project.json`, which mounts both places. It also regenerates the gitignored `game/` stub tree that resolves `@game/...` requires (see `.luaurc`).

## Tests

Set up in milestone M3 (jest-roblox from the Studio command bar).
