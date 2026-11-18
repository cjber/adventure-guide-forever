# Adventure Guide Forever

A WoW: Forever addon (`Interface 16001`) that suggests a short, player-steered route of next steps from your level,
finished quests and quest log. It requires ForeverCore (tracker column, report window, leaderboards, error journal,
debug log, context menu, settings chrome, family page); none of that is vendored here. Players install the zip the
BigWigs packager builds on a `v*` tag.

## Gate

```sh
tools/gate.sh            # stylua, luacheck, ruff on tools, the quick specs under LuaJIT, changelog check
GATE_SLOW=1 tools/gate.sh  # adds playthrough, laps, smoke and ui specs (~3 min); use for a planner or UI change
tools/gate.sh --changed  # the same, linting only the Lua files changed against origin/main; specs only when a Lua, TOC or XML file changed
tools/typecheck.sh       # LuaLS, load graph, shared lints; run after a signature or type change
luajit -joff tests/plan_bench.lua   # after a planner or rebuild change, then again with AGF_BENCH_STRICT=1 (the measured budget)
```

Set `FOREVER_CORE` to a ForeverCore checkout at `tools/forever-core.txt`'s ref when it is not at `../forever-core`
(always, from a worktree). The gate rebuilds the gitignored `tests/.corpus/` with `tools/gen_corpus.py`.
`python3 tools/doctor.py` checks this machine against the tool pins. CI runs the rest (generated data, screenshots,
sim, API docs, repo rules, package, workflows, secrets); never run it whole here. `tests/plan_bench.lua` fails a frame
over 3 ms (7 ms for the once-a-login catalogue build) at three times the measured time; `speedpatrol.yml` times it
against the base branch. `AGF_UPDATE_GOLDEN=1` rewrites `tests/golden/`: re-base a golden route only when new data
explains the change. `tools/forever_tools/` and `tools/forever_sim/` are copied from forever-core byte for byte: never
edit them. Release: `.agents/skills/release/SKILL.md`.

After a UI change run `python3 tools/screenshots.py` (WFA-9; local only, needs Pillow and wago.tools, and
`FOREVER_CORE` at the shared renderer) and commit the PNGs and `scenes.sha256`. On the bot's `data/refresh` PR a stale
image is only a warning (`SCREENSHOTS_STALE_WARN`), so re-render straight after it merges.

## Data

- `Data/Geometry.lua` (`tools/gen_quests.py`), `Data/Forever.lua` (`tools/diff_forever.py`), `Data/ZoneArt.lua`
  (`tools/gen_zoneart.py`) and `Data/Territory.lua` (`tools/gen_territory.py`) are generated: never hand-edit. Geometry
  holds only what neither QuestieDB nor the client answers; it carries no quest records, NPC places or towns, which
  come from the installed QuestieDB at runtime (`Integrations/QuestieSource.lua`, `QuestieTowns.lua`).
- `tests/.corpus/` is built from the sha-pinned QuestieDB release by `tools/gen_corpus.py`. It is gitignored and never
  committed or shipped (QuestieDB 1.0.16 is GPLv3 only from 2026-10-21 and earlier content is all rights reserved), so
  nothing is copied and the runtime-only waiver stands (WFA-28). `tests/fixtures/client.lua` holds the hand-written
  client-only facts.
- `refresh-data.yml` runs daily, moves the pins (`BUILD`, `ERA`, `QUESTIEDB_*`), regenerates `Data/` and the corpus and
  opens the `data/refresh` PR; `retry-refresh.yml` re-runs a failed run once. A check that rejects new client data is
  corrected from that data and kept exact, never loosened.
- Pins moved by hand: `UI_ART_BUILD` in `tools/screenshots.py`, `LEGACY_MAP_BUILD`, `CLASSICDB_COMMIT` (waivers below;
  not bumped), `SPF_SHA` in `tests/contract_spec.lua` and `tools/screenshots_spf.py` (review a new Shortest Path API's
  types). Tool versions live in `tools/toolchain.json` and `tools/pyproject.toml`, vendored from ForeverCore.

## Invariants

- Lua 5.1 in the game's sandbox: no `require`. A new file goes in `AdventureGuideForever.toc` or never runs.
- A quest whose eligibility the data cannot establish is never recommended; a step never points at coordinates the data
  lacks. `Planning/Model.lua` (`ns.Model`) is the headless-testable planner; `Planning/Shown.lua` is the one caller of
  the planner, and the planner reads no other module; `Core/Guidance.lua` is the one writer of `prefs.guided` and `prefs.waypoint`.
- Host globals go in `.luacheckrc`; add missing integration APIs with real types in `types/`, never
  `diagnostics.globals`. Addon contracts live in `types/Namespace.lua`.
- A final `select(...)` argument, table element or return is parenthesised, or carries `-- multi-value: reason`.
- Art is drawn at its native aspect through `UI/Art.lua`; `tools/lint_art.py` refuses a raw `SetAtlas`, `SetTexture`,
  button atlas or `|A`/`|T` markup elsewhere unless the line says `-- art-ok: reason`.
- Every line the player reads is in `Locales/enUS.lua`; after changing copy run
  `python3 tools/phrases.py > Locales/phrases.txt`.
- Tracker section: keep it in ForeverCore's shared column (set `legacySettings` and `safeCall`, add
  `AddHeaderMenuEntries`, attach with `ForeverCore.TrackerHost.Attach`); never register with Blizzard's tracker
  manager. This supersedes WFA-5. Render only after `PLAYER_ENTERING_WORLD` and `VARIABLES_LOADED`, deferred one
  frame. Never touch Blizzard's Lua state (WFA-38). Test event ordering and reuse, not just method existence.
- Player-facing notes go in `changes/<issue>.md`; only the release commit edits `CHANGELOG.md`
  (`python3 tools/changelog.py release X.Y.Z`). Read `.sloppatrol/instructions.md` before dead-code or refactoring work.
- Checks that need the client run in the headless client (forever-core's `wow-forever-addon/in-game.md`); the PR lists
  what was checked and what waits as a `/reload` test for the user.

## Standards

- `repo-standards`: the RS-* requirements every cjber and agent-labs-dev repo meets; its `audit.py` checks this repo.
- `wow-forever-addon`: the WFA-* addon requirements (UI, assets, README and store page, CI and release); wins where
  stricter. UI work also reads `wow-retail-ui-style` and its asset registry in forever-core.

## Waivers

- WFA-2: quest records, NPC places and towns use installed QuestieDB, with Questie supplying live pickup availability.
  Do not substitute a smaller bundled quest catalogue. WFA-28 names QuestieDB as the one companion install this allows.
- WFA-28: trainer roles (class and level span, profession and ranks, riding race, pet training, a battlemaster's
  battleground), profession rank requirements, dungeon entrance requirements (`areatrigger_teleport`) and transports
  (`gameobject_template` with wago.tools `TaxiPathNode`) come from CMaNGOS classic-db, because QuestieDB holds only a
  generic trainer flag, where an entrance is, and no transport docks, and the client reveals rank requirements only
  while that trainer's window is open. Where each stands and its side are QuestieDB's.
- WFA-3: the map-pin, quest-giver and tracker toggles stay in the guide's cog as well as Settings > AddOns, as quick
  switches next to the map.
