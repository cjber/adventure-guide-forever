---
name: sift-project
description: "Project profile for sift in Adventure Guide Forever: the exact quality-gate and evidence commands, live roots that must never be deleted as dead code, exclusions, conventions and risk order. Load before running sift or any code-quality, cleanup or dead-code work in this repository."
---

# sift project profile — Adventure Guide Forever

Adventure Guide Forever is a World of Warcraft addon for the WoW: Forever client (Classic content on
the mainline 12.x UI/API, `## Interface: 16001`). It runs inside the game's Lua 5.1 sandbox; there is
no `require` — the client loads the files `AdventureGuideForever.toc` lists, in that order, and each
file receives `local addonName, ns = ...`, the addon's shared table. It ships as a zip built by the
BigWigs packager (`.pkgmeta`) on a `v*` tag. A standard-library Python generator in `tools/` rebuilds
`Data/Quests.lua` from a pinned CMaNGOS classic-db dump and wago.tools DB2 exports.

## Gate

Run in order from the repository root. All must pass before and after any audit slice.

| Step | Command | Pass means |
|---|---|---|
| Format (Lua) | `stylua --check .` | exit 0 (StyLua 2.5.2) |
| Format (Python) | `ruff format --check tools` | exit 0 (config: `tools/ruff.toml`) |
| Lint (Lua) | `luacheck .` | `0 warnings / 0 errors`, exit 0 |
| Lint (Python) | `ruff check tools` | exit 0 |
| Types and multi-values | `tools/typecheck.sh` | LuaLS 3.19.1 reports no diagnostics; the multi-value lint and its tests pass |
| Tests | `for s in tests/*_spec.lua; do luajit "$s" \|\| exit 1; done` | each prints `<name>_spec: N checks passed`, exit 0 |
| Workflows | `uvx --from actionlint-py==1.7.12.25 actionlint && uvx zizmor@1.30.1 --offline .github` | exit 0 |
| Secrets | `gitleaks git --redact --no-banner .` | `no leaks found` |

CI (`.github/workflows/ci.yml`) runs all of these. The tests are a headless harness, not the game
client: `tests/model_spec.lua` loads `Model.lua` and `Data/Quests.lua` with `loadfile`. Everything else
(the map tab, pins, tracker, settings) is only verified in game; the in-game data check is `/agf audit`.

## Evidence

| Concern | Command | Known false positives |
|---|---|---|
| Dead code (Lua) | `luacheck . --no-color` + the live-root searches below | a function stored on `ns` is never "unused" to luacheck — search every file for `ns.<Name>` |
| Dead code (Python) | `uvx vulture tools --min-confidence 60` | — |
| Live roots | `rg -n 'hooksecurefunc|RegisterEvent|RegisterCallback|SetScript|AddDataProvider|AddTooltipPostCall|SLASH_|SlashCmdList' -g '*.lua'` | — |

## Live roots

- `AdventureGuideForever.toc` file list — loads every top-level `.lua` and `Data/*.lua`.
- `ns.*` — the shared addon table; search all files for `ns.Name`, not the local file.
- `## SavedVariables: AdventureGuideForeverDB`, `## SavedVariablesPerCharacter: AdventureGuideForeverCharDB` — keys in `Core.lua` `DEFAULTS` may hold data written by older versions.
- `## AddonCompartmentFunc: AdventureGuideForever_OnAddonCompartmentClick` and `SLASH_ADVENTUREGUIDEFOREVER1/2` — called by the client by name.
- `hooksecurefunc(ObjectiveTrackerManager, "AddContainer")`, `EventRegistry:RegisterCallback("QuestLog.SetDisplayMode")`, `WorldMapFrame:AddDataProvider`, `TooltipDataProcessor.AddTooltipPostCall` — host callbacks.
- Optional integration (`## OptionalDeps: ShortestPathForever`) — code guarded by `ShortestPathForever.API` is live only with that addon installed.

## Zones

| Path | Zone | Reason |
|---|---|---|
| `Data/*.lua` | generated | written by `tools/gen_quests.py`; never hand-edit, fix the generator |
| `tools/` | script | data generator, CI helpers; not shipped |
| `tests/` | test | headless LuaJIT harness |
| `.github/`, `.pkgmeta`, `.luacheckrc`, `.luarc.json`, `stylua.toml`, `.gitleaks.toml` | config | |
| `README.md`, `CHANGELOG.md`, `docs/` | docs | `docs/curseforge.md` is the store listing |
| `media/`, `docs/screenshots/` | assets | |

## Conventions

- One feature per top-level file; each starts `local addonName, ns = ...` (or `local _, ns = ...`) and exports through `ns.Name`. File-private helpers are `local function`.
- Tabs, 120 columns, double quotes (StyLua). PascalCase for functions, camelCase for locals and DB keys.
- Unknown data is left out rather than guessed; generators raise instead of clamping bad data.
- Comments explain *why* (client quirks, Forever beta bugs, data provenance), not what.
- Text shown in game and `docs/curseforge.md` are user-facing: audits propose changes, never make them.
- New dev-only root files must be added to `.pkgmeta` `ignore:` so they don't ship in the zip.

## Risk order

1. `tools/` — scripts, not shipped; output is diffable.
2. `tests/` — harness only.
3. `Model.lua`, `Settings.lua` — pure planner / settings, the planner under test.
4. `Pins.lua`, `Panel.lua`, `Tracker.lua`, `Tooltip.lua` — UI hooks, in-game verification only.
5. `State.lua`, `Core.lua`, `Integrations.lua` — client state, SavedVariables and the cross-addon contract.

## Project rules and lenses

- Rules: none yet.
- Lenses: none yet.
