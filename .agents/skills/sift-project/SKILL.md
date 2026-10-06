---
name: sift-project
description: "Project profile for sift in Adventure Guide Forever: the exact quality-gate and evidence commands, live roots that must never be deleted as dead code, exclusions, conventions and risk order. Load before running sift or any code-quality, cleanup or dead-code work in this repository."
---

# sift project profile: Adventure Guide Forever

Adventure Guide Forever is a World of Warcraft addon for the WoW: Forever client (Classic content on
the mainline 12.x UI/API, `## Interface: 16001`). It runs inside the game's Lua 5.1 sandbox; there is
no `require`: the client loads the files `AdventureGuideForever.toc` lists, in that order, and each
file receives `local addonName, ns = ...`, the addon's shared table. It ships as a zip built by the
BigWigs packager (`.pkgmeta`) on a `v*` tag. Standard-library Python generators in `tools/` rebuild
`Data/Geometry.lua` (`gen_quests.py`, route geometry from a pinned CMaNGOS classic-db dump and wago.tools
DB2 exports; its quest corpus is test-only, in `tests/fixtures/quests.lua`), `Data/Forever.lua`
(`diff_forever.py`) and `Data/ZoneArt.lua` (`gen_zoneart.py`).

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
| Bench | `luajit -joff tests/plan_bench.lua` | exit 0; after a planner or rebuild change also `AGF_BENCH_STRICT=1` (3 ms frame budget, local only) |
| Changelog | `python3 tools/changelog.py --check` | exit 0: every release has a `CHANGELOG.md` entry |
| Workflows | `uvx --from actionlint-py==1.7.12.25 actionlint && uvx zizmor@1.30.1 --offline .github` | exit 0 |
| Secrets | `gitleaks git --redact --no-banner .` | `no leaks found` |
| Project rules | `python3 .sift/gate.py --base origin/main && python3 .sift/agents.py check` | exit 0 |

CI (`.github/workflows/ci.yml`) runs all of these. The tests are a headless harness, not the game
client: `tests/harness.lua` stubs the client APIs and loads the TOC's files, so the specs drive the planner and the
UI (window, panel, pins, tracker, settings) headlessly. What needs the client itself (art, fonts, host hooks) is a
`/reload` check for the user; the in-game data check is `/agf audit`.

## Evidence

| Concern | Command | Known false positives |
|---|---|---|
| Dead code (Lua) | `luacheck . --no-color` + the live-root searches below | a function stored on `ns` is never "unused" to luacheck: search every file for `ns.<Name>` |
| Dead code (Python) | `uvx vulture tools --min-confidence 60` | none |
| Live roots | `rg -n 'hooksecurefunc|RegisterEvent|RegisterCallback|SetScript|AddDataProvider|AddTooltipPostCall|SLASH_|SlashCmdList' -g '*.lua'` | none |
| Shared-table members | the shared-table command in sift's `languages/lua.md` (it writes `ns-once`) | nested tables (`Model.*`, `ns.Integrations.*`) need their own `rg -n 'Model\.Name'` search |
| Clones | `npx -y jscpd@4 --silent --min-lines 6 --ignore "Data/**,.types/**,**/.cache/**" .` | none (0 clones on 2026-09-24) |
| Standards | `python3 .sift/agents.py standards` | resolves the pinned pack declared in AGENTS.md; `SIFT_STANDARDS_PATH` can override it with a local standards directory |

## Live roots

- `AdventureGuideForever.toc` file list: loads runtime modules in `Core/`, `Planning/`, `Integrations/`, `UI/` and `Data/`.
- `ns.*`: the shared addon table; search all files for `ns.Name`, not the local file.
- `## SavedVariables: AdventureGuideForeverDB`, `## SavedVariablesPerCharacter: AdventureGuideForeverCharDB`: keys in `Core/Core.lua` `DEFAULTS` may hold data written by older versions.
- `## AddonCompartmentFunc: AdventureGuideForever_OnAddonCompartmentClick` and `SLASH_ADVENTUREGUIDEFOREVER1/2`: called by the client by name.
- `EventUtil.ContinueAfterAllEvents`, `EventRegistry:RegisterCallback("QuestLog.SetDisplayMode")`, `WorldMapFrame:AddDataProvider`, `TooltipDataProcessor.AddTooltipPostCall`: host callbacks.
- Optional integrations: QuestieDB supplies quests and entrance points, Questie confirms pickups, AtlasLoot's public ItemDB supplies bosses and drops. Shortest Path, Skill Up, Legacy and Tweaks Forever are companions through public contracts. Dungeon interiors belong to Tweaks Forever; AGF has no Atlas overlay or Classic guide handoff.
- `hooksecurefunc("QuestMapFrame_ShowQuestDetails")`, `EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap")`: host callbacks.
- Methods the host calls by name: the map provider's `RefreshAllData`/`RemoveAllData`; the pin mixins' `OnAcquired`/`OnMouseEnter`/`OnMouseLeave`/`OnClick` (bound through `mixin=` in `UI/Panel.xml`); the tracker module's `LayoutContents`/`OnBlockHeaderClick`.

## Zones

| Path | Zone | Reason |
|---|---|---|
| `Data/*.lua` | generated | `Geometry.lua` by `tools/gen_quests.py` (route geometry; the quest corpus is test-only), `Forever.lua` by `tools/diff_forever.py`, `ZoneArt.lua` by `tools/gen_zoneart.py`; never hand-edit, fix the generator |
| `tools/` | script | data generator, CI helpers; not shipped |
| `tests/` | test | headless LuaJIT harness |
| `types/` | production | LuaLS annotations only, never loaded in game; review for dead classes and stale field docs |
| `.github/`, `.pkgmeta`, `.luacheckrc`, `.luarc.json`, `stylua.toml`, `.styluaignore`, `.gitleaks.toml`, `.gitignore` | config | |
| `README.md`, `CHANGELOG.md`, `docs/`, `AGENTS.md`, `.agents/` | docs | `docs/curseforge.md` is the store listing |
| `media/`, `docs/screenshots/` | assets | |

## Conventions

- One feature per runtime file; each starts `local addonName, ns = ...` (or `local _, ns = ...`) and exports through `ns.Name`. File-private helpers are `local function`.
- Tabs, 120 columns, double quotes (StyLua). PascalCase for functions, camelCase for locals and DB keys.
- Unknown data is left out rather than guessed; generators raise instead of clamping bad data.
- Comments explain *why* (client quirks, Forever beta bugs, data provenance), not what.
- Text shown in game, the `.toc` `## Notes` line and `docs/curseforge.md` are user-facing: audits propose changes, never make them.
- `UI/TrackerHost.lua` is shared with the companion addons (its own comments say so; no script here checks the copies):
  a confirmed finding there is a `decide`, since the edit has to land in every copy.
- New dev-only root files must be added to `.pkgmeta` `ignore:` so they don't ship in the zip.

## Risk order

1. `tools/`: scripts, not shipped; output is diffable.
2. `tests/`: harness only.
3. `Planning/Model.lua` and the planner files the TOC loads after it (`Travel` to `Refresh`), `Planning/Shown.lua`, `Planning/Order.lua`, `Core/Session.lua`, `UI/Settings.lua`, `UI/Hints/*.lua`: the planner and its inputs, under the specs and the bench.
4. `UI/Window*.lua`, `UI/Overview.lua`, `UI/Panel.lua`, `UI/Pins.lua`, `UI/Tracker.lua`, `UI/Tooltip.lua`, `UI/Menu.lua`, `UI/Art.lua`, `UI/Asides.lua`, `UI/Moments.lua`, `UI/PvP.lua`, `UI/ZoneIcon.lua`, `Planning/Focus.lua`, `UI/Sound.lua`, `Integrations/Providers.lua`, `UI/Dump.lua`: UI and host hooks; headless specs plus `/reload` checks.
5. `Core/State.lua`, `Core/Core.lua`, `Core/Guidance.lua`, `Integrations/Integrations.lua`, `Integrations/Companions.lua`, `Integrations/QuestieSource.lua`, `Locales/*.lua`: client state, SavedVariables, the cross-addon contracts and every line the player reads.

## Settled

Shapes that look like defects here but are not. Reviewers and verifiers read this before raising a
finding; audits add an entry when verifiers keep dismissing the same shape for the same reason.

- **Planner look-alikes**: the `Planning/` modules' step builders, locators and shallow-copy loops (`TrainerSteps`/`Battleground`,
  `Locate`/`Build`, `Describe` before and after the overseas override) read alike but take different contracts; five
  `parallel-implementations` candidates were dismissed on the small-idiom and different-contract exclusions in the
  2026-09-27 audit. Raise one only with a caller that needs both to change together.
- **One-line idioms**: a bit test beside `Model.HasBit`, the hub name before the comma, a Find-and-Click loop in a spec:
  one expression under different contracts, dismissed six times on the small-idiom exclusion in the 2026-10-02 audit
  (e.g. `UI/Hints/Explore.lua`, `UI/Hints/Hearth.lua`, `tests/scenes.lua`).
- **Open keys**: `"town:" .. hub` and `"dungeon:" .. id` identify an open, persisted set of steps and journeys, so they
  are not a closed set to type (`stringly-typed` dismissed twice; e.g. `Planning/Model.lua`, `Integrations/Dungeons.lua`).
- **Absence checks**: a spec asserting that a removed field or pin pool stays absent (`pin.More == nil` in
  `tests/ui_spec.lua`) is a regression test for a shipped defect, not a check that cannot fail.
- **Guards a spec needs**: a nil or existence guard that looks unreachable in game but that a spec exercises: the
  harness loads a file without the global or stubs the module that defines the field. Delete the guard in a copy and
  run every spec before raising it (`defensive-noise` dismissed three times in the 2026-10-03 audit: `EventRegistry` in
  `UI/TrackerHost.lua`, `ns.SourceHint` in `UI/Panel.lua`, the nil `api` in `Planning/Geometry.lua` `Maps`).
- **Repeated spec fixtures**: the same character or options literal retyped per spec or scene is fixture input, not a
  parallel implementation (e.g. `tests/feature_rules_spec.lua`, `tests/scenes.lua`).

## Anti-patterns

Shapes this codebase has produced more than once and a reviewer confirmed. An audit guards a
confirmed defect of one of these shapes with `settled:<name>`. An entry leaves when a rule enforces
it or it has not recurred in two audits.

- **Stale leftovers**: comments and annotations left describing code a rewrite replaced: a template, function, format or
  range the code no longer has (`comment-narration`/`stale-docs`; e.g. `UI/Panel.xml` naming
  `QuestLogTabButtonTemplate`, `types/Namespace.lua` "3-5 steps"; six such in the 2026-09-24 audit).
  Grep for the old name when renaming.
- **Sibling config**: config copied from a sibling addon that names files this repo lacks (`dead-code`/`stale-docs`;
  e.g. `.pkgmeta` ignoring `PLAN.md`, `tools/ruff.toml` citing `refresh-data.yml`).
- **Orphaned client declarations**: a harness stub, `types/Client.lua` annotation or `.luacheckrc` global for a client
  API the addon stopped calling (`dead-code`; e.g. `PanelTemplates_TabResize`, `MenuUtil`, `GetBindingText` in the
  2026-10-02 audit). When a call to the client goes, grep its name in `tests/harness.lua`, `types/` and `.luacheckrc`.
- **Unreachable guards**: a nil, existence or default guard on a value every caller or producer already guarantees
  (`defensive-noise`/`speculative-abstraction`; e.g. `X.GetEffectiveScale and X:GetEffectiveScale() or 1` in
  `UI/TrackerHost.lua`, a parameter no caller sets in `Planning/Model.lua`).
- **Appended spec blocks**: checks added after a spec's closing `checks passed` print, or an assertion over the
  spec's own stub that cannot fail (`session-residue`/`test-plumbing`; e.g. `tests/dungeons_spec.lua`,
  `tests/dungeon_regression_spec.lua`). New checks go above the closing print and must fail when the addon regresses.

## Project rules and lenses

- Rules: `.sift/scripts/no-em-dash.py` (an em dash in `tools/*.py` or `Data/*.lua`), with its cases under
  `.sift/script-tests/no-em-dash`.
- Lenses: none yet.

The type gate also runs `tools/lint_taint.py` and `tools/typecheck_coverage.py`; `AGENTS.md`, Secure UI regression checks, states what they enforce.
