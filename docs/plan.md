# Journeys: implementation plan

Builds `docs/design.md`. Paths as there: `BLZ` = `wow-handoff/blizzard-ui/Interface/AddOns`, `DOC` =
`BLZ/Blizzard_APIDocumentationGenerated`, `CSV:<line>` = `skillup-forever/tools/.cache/UiTextureAtlasMember-1.60.1.69913.csv`
(header is line 1), `WFA-n` = the `wow-forever-addon` skill's rules. Every number below was measured on 2026-09-23
against `a128f7a`, unless it says "pinned by the spec". The review in `plan-review.md` is applied; see
"Review dispositions" at the end.

## 0. Scope changes against design.md §4

| Design | Now | Evidence |
|---|---|---|
| #10 travel line, Should, blocked on SPF | **Must**. SPF PR (§2) adds `EstimateDetail`, the nil reason and `Active()`. AGF degrades to `Estimate` ("About N min away"), then to no line | Lead decision (a) |
| #13 SPF `Active()` | Should, delivered in the same SPF PR | Lead decision (a) |
| #17 dungeon card, Could | **Should**, with a generator-only fix: a flag, no Tweaks Forever API, no Encounter Journal, routes to quest givers only | The data is offline, see §0.1 |
| #16 "New in Forever" tag, Could | **Not planned** | See §0.2 |
| #14 zones 2521 / 2548 | **Cut** | `Data/Quests.lua` has 0 quests with a place on map 2521 or 2548 (`grep -c 'map = 2521'` = 0, same for 2548). A range for a zone with no quests changes nothing a player sees |
| (new) Plan ranking | `Model.Plan` stops calling SPF. It ranks by map distance, then by zone centres (F0), and SPF is asked for step 1's travel line only, in its own frame | Plan asks for 3 to 36 estimates per rebuild today (§1.4). At 2.45 ms per cold estimate, that is up to 88 ms |
| (new) Pins and zone choice | **Deleted** end to end (F9): `prefs.pinned`, `ns.TogglePin`, the row PinButton, `prefs.zone`, `AGFZoneChoice`, `route.zones` | The design's cards and menu (§2.2, §2.8) never mention pins; journeys replace the zone choice |
| #18 discovery hint | Stays Could, not planned | Needs a Legacy Forever API that does not exist |

### 0.1 Dungeon flag: available offline

- **Why the flag is empty today.** `gen_quests.py:360` sets `dungeon` from UiMap `Type == 4` through `UiMapAssignment.AreaID`. The pinned `UiMapAssignment-1.60.1.69913.csv` has 61 rows and no instance maps, so 0 quests get the flag.
- **Path that works.** CMaNGOS `quest_template.ZoneOrSort` (> 0) is an `AreaTable.ID`. `AreaTable.ContinentID` gives the `Map.ID`, and `Map.InstanceType` 1 means party and 2 means raid. Example: 1581 The Deadmines → ContinentID 36 → Map 36 `Deadmines`, InstanceType 1.
- **Where the sources are.** Both are wago exports of the pinned build 1.60.1.69913, fetched through the URL `db2()` already uses:
  - `AreaTable-1.60.1.69913.csv` is cached in `legacy-forever/tools/.cache`;
  - `Map-1.60.1.69913.csv` is cached in `skillup-forever/tools/.cache` and `shortest-path-forever/tools/.cache` (the two copies are byte-identical).
- **Result.** A dry run over the cached files, restricted to quests in QuestV2:
  - 133 party-dungeon quests and 90 raid quests, from 19 instances (Dire Maul 32, Stratholme 15, …, Deadmines 5);
  - 93 of the 133 party quests have a `start` in today's data.
- **Side effect.** Flagged quests fall under `prefs.dungeons` (default off) for **pickups only**. F15 changes `LogSteps` so a quest in the log is never hidden by the dungeon filter, and its dry run prints how many of the 223 are not already `elite`.

### 0.2 "New in Forever": not computable honestly

- `QuestV2-1.60.1.69913.csv` is cached, but it holds only `ID, UniqueBitFlag, UiQuestDetailsThemeID`. The theme is 0 on all 6600 rows.
- 3065 of its IDs are missing from CMaNGOS: 1 to 9999 has 3756 IDs in QuestV2, 30000 to 79999 has 263, 80000 to 89999 has 839, and 90000 to 99999 has 1742.
- Those missing IDs include IDs retired from Classic and Season of Discovery ranges. "Not in CMaNGOS" is therefore not "new in Forever".
- A proper diff needs a QuestV2 export from 1.15.x, and none is cached. Guessing would break the rule "missing data is omitted". Not planned.

### 0.3 Sibling PRs

| Sibling | PR? | Reason |
|---|---|---|
| Shortest Path Forever | **Yes** (§2) | Travel line and `Active()` |
| Legacy Forever | No | AGF reads no Legacy data. Its `tools/.cache/AreaTable-1.60.1.69913.csv` is only a local copy of a public wago export, and AGF's generator downloads its own. The discovery hint (#18) stays unplanned |
| Tweaks Forever | No | The dungeon card routes to quest givers only, so no `DungeonEntrance`. #14 is cut, so no `ZoneRange` |
| SkillUp Forever | No | Profession steps are out of scope. Its `Map` CSV is again just a copy of a public export |

## 1. Test and verification infrastructure (built first)

Every later feature lands with a check from this section.

### 1.0 Probe gate (blocks F1, F2 and F5)

Design §9's batch-2 probes have not run: `ForeverProbe.lua` still holds only the `19:38:41` run, with no
`questoffer`, `templates`, `c60`, `classnames` or `questline` keys. The user runs the new `forever-probe` build
once and sends the SavedVariables; F1, F2 and F5 start only after that file is read.

| Probe (design §9) | Decides | If present | Fallback |
|---|---|---|---|
| 2 `questoffer` | F1 giver layer | Delete `AddGivers`, `showQuestGivers` and the giver pin template | Keep AGF's givers, gated as in F1 |
| `templates`: `AlphaHighlightButtonTemplate` | F2 card hover | Inherit it | A `HighlightTexture` using the card's own atlas with `alphaMode="ADD"`, alpha 0.4 |
| 3 `classnames` | F5 "Warriors only" | `C_CreatureInfo.GetClassInfo` / `GetRaceInfo` names | `LOCALIZED_CLASS_NAMES_MALE`; for races, the line is omitted |
| 4 `c60` | F5 check icon, F8/F11 template art | Use the `-c60` rows as cited | Plain names |
| 5 `questline` | F4 totals | Stays on the conservative rule for v1 (a follow-up may adopt the API) | Conservative `pre`/`next` rule |
| 6 quest cache | F5 titles | `GetTitleForQuestID` after `RequestLoadQuestByID` | The data's English title |
| 8 fanfare | F11 glow | Keep `SetNeedsFanfare` | Sound and "Story complete" only; /reload check 9 decides |

### 1.1 `tests/harness.lua` + `tests/ui_spec.lua`

- **Harness files.** `tests/harness.lua` is forked from `wow-handoff/scratch/harness2.lua` (2006 lines). Keep:
  - the frame, texture and font-string stubs;
  - `visibilityChanged`;
  - `animationGroup`;
  - the `ObjectiveTrackerModuleTemplate` block stubs.

  Drop the SPF-only parts: the arrow, the trail, minimap, taxi, ride, and every absolute `loadfile` (harness2.lua:150, 421, 467) and the `ShortestPathForever.toc` loader (:487).
- **Regions and anchors.** Every region stub keeps all its points: `SetPoint`/`SetAllPoints`/`ClearAllPoints`, `GetNumPoints`, `GetPoint(i)` returning `point, relativeTo, relativePoint, x, y`, plus `SetSize`/`GetSize` that record whether the size was set explicitly. Font strings record their font object name (`SetFontObject`, template `inherits`).
- **XML templates.** A small Lua reader for `Panel.xml` (tags and attributes only) instantiates AGF's own `virtual="true"` templates recursively: `Layers/Layer/Texture/FontString`, `Frames`, `Size`, `Anchors/Anchor`, `parentKey`, `atlas`, `useAtlasSize`, `mixin` and `inherits` (AGF templates recurse; a stock template name is recorded on the frame as `stockTemplate` and gets no children). So `AcquirePin` and `AdventureGuideForeverJourneyCardTemplate` build their real regions.
- **Loading.** The harness parses `AdventureGuideForever.toc` (lines not starting with `##`) and `loadfile`s each `.lua` with `(addonName, ns)`, using paths relative to the repo root. It then fires `ADDON_LOADED("AdventureGuideForever")`, `ADDON_LOADED("Blizzard_WorldMap")` (so `EventUtil.ContinueOnAddOnLoaded` runs Panel's `Attach`, Panel.lua:779), `PLAYER_ENTERING_WORLD` and `VARIABLES_LOADED`.
- **Stubs.**
  - `WorldMapFrame`: `AddDataProvider`, `AcquirePin` / `RemoveAllPinsByTemplate` with counts, `GetMapID` / `SetMapID`, `IsShown`.
  - `QuestMapFrame`: a proxy whose `__newindex` raises on `displayMode`, with `ContentsAnchor`, `DetailsFrame` and `QuestsFrame`.
  - `ObjectiveTrackerManager` / `ObjectiveTrackerFrame`, and `MenuUtil.CreateContextMenu`, whose recording root captures titles, buttons and submenus.
  - `Settings`: `RegisterVerticalLayoutCategory`, `RegisterAddOnSetting`, `CreateCheckbox`.
  - `C_QuestLog`, `C_Map` (user waypoint get, set and clear, as a value store), `C_SuperTrack`, `InCombatLockdown` (a toggle that also fires `PLAYER_REGEN_DISABLED`/`ENABLED`), `C_Timer.After` (queued, drained by `harness.flush()`), `EventRegistry`, `EventUtil`, `hooksecurefunc`, `GameTooltip` (records `GameTooltip_*` lines), a movable player position.
  - SPF, in three profiles: absent, `v1` (`Estimate`, `Navigate`, `NavigateRoute`, `CurrentStop`, `Cancel`) and `v1+` (adds `EstimateDetail`, `Active`). Each profile counts its calls per function.
  - A `Model` call counter (wraps `Model.Journeys`, `Model.Plan`).
- **`tests/ui_spec.lua` asserts (numbers are exact):**
  1. The addon loads with no sibling globals, and again with each SPF profile. `harness.errors` has 0 entries.
  2. There are 0 writes to `QuestMapFrame.displayMode` across open, close, card select, row click and tracker click.
  3. No `OnUpdate` script is set on any frame after `harness.flush()` while idle (the tab closed and no animation playing).
  4. `CreateFrame` is called 0 times across 10 `ns.Invalidate()` + `flush()` cycles after the first render. Pins are pooled, so `AcquirePin` does not count.
  5. Pin lifecycle: `RefreshAllData` twice gives the same pin count. `RemoveAllData` leaves 0 live pins. The ring and giver tooltips and the tracker menu equal an exact list. **Changed (commit 4):** that list is today's text (ring: "1. Turn in: …", detail, reason, click line; menu: title, Skip, Change route, Go), not the design's. The §2.9 lines need F4's chapter and F10's travel line, and the §2.8 menu needs F6's "Show quest" and F7's Stop and "Skipped (n)"; asserting them at commit 4 would fail or pull those features forward. F6, F7 and F10 each update the expected lists in the commit that changes the text, and F7 adds "Show quest is absent for a non-log step".
  6. Combat: `InCombatLockdown` on + 10 invalidations + `flush()` → 0 `Model.Journeys` calls; after `PLAYER_REGEN_ENABLED` + `flush()` → 1. **Lands with commit 19** (the combat rule); commits 2-4 cover asserts 1-5.
- **No paths outside the repo.** CI runs `! grep -rnE '/home/|~/|drive/proj' tests/`.
- **Command:** `luajit tests/ui_spec.lua`, picked up by CI's existing `tests/*_spec.lua` loop.

### 1.2 Layout dump: `Dump.lua` + `tests/golden/layout.json`

- **`Dump.lua`** (new TOC entry after `Settings.lua`). `ns.DumpLayout(root)` walks visible regions depth-first and returns a plain Lua table with, for each region:
  - its parentKey path, and `stockTemplate` / `inherits`;
  - every anchor (`GetNumPoints`; for each: point, relativeTo as a parentKey path, relativePoint, x, y) and the size, marking explicitly set sizes;
  - its atlas;
  - for text, the font object name and text;
  - `onUpdate = frame:GetScript("OnUpdate") ~= nil` for frames.
- **In game.** `/agf dump` writes `AdventureGuideForeverDB.dump = { build, layout = DumpLayout(AdventureGuideForeverPanel), tracker = ..., route = step keys, frames = every AGF frame's name and onUpdate }`. It runs only on the command. The key survives `/reload` (so the user can send it) and is cleared on the next `PLAYER_ENTERING_WORLD` with `isInitialLogin`.
- **Headless.** `tests/json.lua` (not shipped) emits sorted keys and numbers with `%.2f`. After `ShowGuide(true)` the harness writes `tests/golden/layout.json`. `ui_spec` fails on any difference, and `AGF_UPDATE_GOLDEN=1` rewrites the file.
- **In-game vs headless.** `luajit tests/dump_diff.lua <AdventureGuideForever.lua>` compares only parentKey paths, atlases and explicitly set sizes (font metrics and template sizes legitimately differ) and prints the differences. Used by /reload check 2.

### 1.3 `tools/screenshots.py` (renders from the JSON)

- **Input.** It reads `tests/golden/layout.json`, resolves each region's rect from its anchors (two-point anchors give the size, as in `Panel.lua:511-512`), and draws its atlas and font with `~/.claude/skills/wow-mock-screenshots/wowmock.py`.
- **Stock chrome.** Stock templates produce no regions headlessly, so `screenshots.py` keeps one small recipe per `stockTemplate` the dump names (`SearchBoxTemplate`, `UIPanelButtonTemplate`, `ScrollFrameTemplate`, `QuestLogBorderFrameTemplate`, `LargeSideTabButtonTemplate`, `QuestLogTabButtonTemplate`, the tracker header), each citing its BLZ XML, as the wow-mock-screenshots skill does. An unknown `stockTemplate` fails the run. AGF's own layout is never re-described in Python.
- **Scenes.** `docs/screenshots/{panel,search,map,tracker,menu,tooltip}.png`.
- **Route geometry (map scene only).** This is the SPF line as SPF itself draws it while guiding; AGF draws no lines. It comes from SPF's LuaJIT `Path.FindSync(map, from, to)` (shortest-path-forever `Path.lua:1516`), run with `luajit -` in `tools/.cache/spf-<sha>/`. That directory is extracted with `git -C $SPF archive <sha>`, and the fallback is `https://codeload.github.com/cjber/shortest-path-forever/tar.gz/<sha>`. SPF's own `tools/screenshots.py:91,134` does the same.
- **Manifest.** `docs/screenshots/manifest.txt` records the build (1.60.1.69913), the SPF sha, the layout.json sha256 and each PNG's sha256. PNGs are saved without timestamps.
- **Pillow is optional in CI.** `tools/typecheck.sh` runs `unittest discover -s tools` in CI, where Pillow is not installed. `screenshots.py` imports Pillow inside its render functions only. `tools/screenshots_test.py` tests the Pillow-free anchor-to-rect resolver, and any render test is `skipUnless(importlib.util.find_spec("PIL"))`.
- **Compare montages** in `docs/screenshots/_compare/`: each AGF scene next to its sibling reference at the same scale, labelled. The references come from `git show`, with a raw.githubusercontent fallback, since all three repos are public. The refs are verified:

  | Montage | Reference |
  |---|---|
  | `menu.png` | legacy-forever `8afee98` (`8afee98cff5f…`, "chore: release 0.2.0") `docs/screenshots/menu.png` |
  | `map.png` | legacy-forever `8afee98` `docs/screenshots/map.png` |
  | `tracker.png` | legacy-forever `8afee98` `docs/screenshots/tracker.png` |
  | `tooltip.png` | skillup-forever `be11638` (`be1163841bac…`) `docs/screenshots/tooltip.png` |
  | `panel.png` | skillup-forever `be11638` `docs/screenshots/window.png` |

  The design says legacy-here; that repo is now `legacy-forever`, and the sha resolves there.
- **Command:** `python3 tools/screenshots.py`. It is not run in CI: it needs wago downloads and Pillow. `ruff` covers the file in CI.

### 1.4 `tests/plan_bench.lua`

- **Budget.** WFA-13: no frame over 3 ms. The client runs plain Lua 5.1, so `luajit -joff` is the honest proxy, as in SPF's own measurements (`API.lua:132`: 2.45 ms cold, 0.51 ms warm; the ~4 ms JIT first call does not exist in the client).
- **Today's cost** (`-joff`, full data, 14 profiles, level × faction): `Model.Plan` takes 0.33 to 0.45 ms median, and asks for 3 to 36 estimates per rebuild. At 2.45 ms per cold estimate that is 7 to 88 ms. Hence F0.
- **Two frames, measured separately.** F0 splits the work (see F0 and F10):
  - **rebuild frame**: the coalesced `C_Timer.After(0)` in `ns.Invalidate` runs `Rebuild` (the full `ns.Route()` build: `Model.Journeys`, `Model.Zones`, `Model.Story`, `Model.Plan`, 2-opt) and `NotifyRouteChange`, with 0 SPF calls;
  - **travel frame**: a second `C_Timer.After(0)` queued after `NotifyRouteChange` runs `TravelLine(step 1)`, with at most 1 SPF call.
- **Stub: a counted cost model, not a real sleep.** It copies SPF's cache semantics (origin rounded to 1e-4 plus the exact destination, 256 slots, 5 s TTL on a fake clock; SPF `API.lua:9,166-181`), charges **2.45 ms per miss** and 0.003 ms per hit, and resets the cache before every sample, so every sample is the cold worst case.
- **Harness.** The bench loads the addon through `tests/harness.lua` so it times the real `Rebuild`, not `Model.Plan` alone.
- **Profiles.** Levels 1, 10, 20, 30, 40, 50, 60 × both factions, 20 samples each (280 in all). The completed set holds every quest of the faction whose level is below `level - 5`, which is deterministic.
- **Asserts in CI (deterministic):** SPF calls in the rebuild frame == 0; in the travel frame ≤ 1; `CreateFrame` 0 after the first render.
- **Asserts locally** (`AGF_BENCH_STRICT=1`, listed in AGENTS.md Commands; shared runners would flake): **max** rebuild-frame CPU < 3 ms, and **max** travel-frame modelled time (CPU + 2.45 ms per miss) < 3 ms. Re-run after F2, F4 and F12.
- **Command:** `luajit -joff tests/plan_bench.lua`, as a new CI step. It is not named `_spec`, so the spec loop does not run it twice.

### 1.5 `tests/plan_golden_spec.lua`

- **Fixtures.** `tests/fixtures/characters.lua` holds fixed characters. Each has a level, side, race and class bits, a map position, completed quests (as rules plus explicit IDs), a log and prefs. Seed set, with today's `Model.Zones` output recorded while writing this plan:

  | Fixture | Today's zone choices (quests) |
  |---|---|
  | `ne21_darkshore` (Teldrassil and Darkshore done) | Wetlands 7 · Redridge 17 · Ashenvale 8 |
  | the same at level 23, for the next-zone card at `level + 2` | Redridge 13 · Duskwood 11 · Wetlands 10 |
  | `human12_elwynn` | Darkshore 13 · Westfall 11 · Loch Modan 10 |
  | `orc18_barrens` (the probe's level-18 shaman) | The Barrens 24 · Stonetalon 13 · Westfall 3 |
  | `human60` | Silithus 15 · Eastern Plaguelands 22 · Moonglade 1 |
  | `human18_westfall` (F15) | recorded when F15 lands |
  | `ne21_crosszone` (F0): `ne21_darkshore` with a complete log quest whose turn-in is in Ashenvale | recorded when F0 lands |

  The lead's example "at 21 with Darkshore done → Ashenvale" is **not** what the model gives today: Ashenvale ranks 3rd at 21 and is absent at 23. No expected value is invented.
- **Next-zone rule (decided).** The next-zone card needs **at least 5 eligible pickups** in the zone. `plan_golden_spec` asserts it for every fixture, so `orc18_barrens` gets no Westfall card (3 quests; ids 103/136-140/152 are `side = 3`, so the data is right, the zone is just thin) and `human60` no Moonglade card.
- **Golden files.** `tests/golden/<fixture>.txt` holds one line per card, and per step `key | title | map x,y | reason`, with 4-decimal coordinates and a sorted, stable order. `AGF_UPDATE_GOLDEN=1` rewrites them, so every model change shows as a reviewable text diff.
- **Command:** `luajit tests/plan_golden_spec.lua`.

### 1.6 `tests/contract_spec.lua`

- **What it compares.** It parses `---@class` / `---@field name type` from SPF `types/API.lua` and from AGF `types/Namespace.lua` (the `AGFSPF*` classes), through an explicit alias map (`AGFSPFAPI`↔`SPFPublicAPI`, `AGFSPFStop`↔`SPFAPIStop`, `AGFSPFLeg`↔`SPFAPILeg`, `AGFSPFDetail`↔`SPFAPIDetail`, `AGFSPFMode`↔`SPFAPIMode`, `AGFSPFNoRoute`↔`SPFAPINoRoute`).
  - **Excluded classes:** `SPFPublicAddon` (AGF reads `ShortestPathForever.API` through a typed accessor, not a mirror).
  - Every AGF field must exist in SPF with an identical type, and every SPF field of a non-excluded class must be mirrored in AGF.
  - AGF's `REQUIRED` list in `Integrations.lua` must be exactly the non-optional function fields.
- **Type token.** SPF writes prose after the type with no `--` (e.g. `---@field Estimate fun(...): number? seconds, nil when unknown or in combat`). The parser takes the longest type prefix: a balanced `fun(...)` followed by an optional `: ret` clause, whose items are split on `, ` only there and each must match a type atom (`name`, `name?`, `name[]`, `"lit"`, `a|b`); the first item that is not a type atom ends the token (`number? seconds` → `number?`). Non-function fields take the first whitespace-delimited word. The SPF PR also moves its descriptions after `--`, so the new sha parses trivially; the rule covers the pinned sha.
- **Negative tests.** A vendored copy with `Cancel fun(owner: string)` (today's AGF drift, Integrations.lua:17) must fail against SPF's `fun(owner: string): boolean`, as must a missing mirror field.
- **Pin.** `local SPF_SHA = "39d9a986d423557ab13039b45732d0c9dd12bf02"` (SPF `origin/main` today). The AGF commit that adopts `EstimateDetail` bumps it to the SPF PR's merge sha.
- **Offline fallback.** The spec reads the vendored `tests/fixtures/spf_types_API.lua`, whose first line is `-- shortest-path-forever <SPF_SHA>:types/API.lua`. It checks that header against `SPF_SHA`, so it runs with no network.
- **CI proves the vendored copy matches upstream:**

  ```sh
  sha=$(sed -n 's/^local SPF_SHA = "\(.*\)"/\1/p' tests/contract_spec.lua)
  curl -sSfL "https://raw.githubusercontent.com/cjber/shortest-path-forever/$sha/types/API.lua" \
    | diff <(tail -n +2 tests/fixtures/spf_types_API.lua) -
  ```

### 1.7 Wiring

- **`.github/workflows/ci.yml` (`check` job):**
  - add `luajit -joff tests/plan_bench.lua`, the contract diff step above, and the `tests/` path grep (§1.1);
  - `ui_spec`, `plan_golden_spec` and `contract_spec` already run through the `tests/*_spec.lua` loop.
- **`.luacheckrc`:** exclude `tests/fixtures/**` and `tests/golden/**`, and add `Dump.lua`'s and `Menu.lua`'s globals (none expected).
- **`tools/typecheck.sh`:** add `python3 tools/lint_copy.py` (F14) next to `lint_multivalue.py`. `tools/screenshots_test.py` is picked up by the existing `unittest discover` and is Pillow-free (§1.3). LuaLS already ignores `tests/` (`.luarc.json`).
- **`AGENTS.md` Commands:** add `AGF_BENCH_STRICT=1 luajit -joff tests/plan_bench.lua` and `python3 tools/screenshots.py`; Layout gains `Menu.lua` and `Dump.lua`.

## 2. Shortest Path Forever PR (merges first)

- **Worktree.** Branch off SPF `origin/main` in its own worktree, and never touch the local checkout's branch:
  `git -C ~/drive/proj/shortest-path-forever worktree add .claude/worktrees/api-detail -b cb/api-detail origin/main`.
- **Files.**
  - `API.lua`: `Estimate` gains a second return, `EstimateDetail` and `Active` are new, and the cache holds `{at, seconds, legs}`.
  - `Journey.lua`: `VERB` and `NodeLabel` become `ns.LegLabel(leg)`, and Journey keeps using it.
  - `types/API.lua`: adds `SPFAPIMode`, `SPFAPINoRoute`, `SPFAPILeg` and `SPFAPIDetail`, appends the three fields, and moves every field description after `--`.
  - `tests/api_spec.lua`, `CHANGELOG.md` `[Unreleased]`, `README.md` API section.
- **Contract** (additive, `version` stays 1):
  - `Estimate(...) -> number?, ("combat"|"invalid"|"unreachable")?`:
    - `"combat"` when `not Ready()` and `InCombatLockdown()`;
    - `"invalid"` for other not-ready cases or a `Point` failure;
    - `"unreachable"` for a nil plan or a cached `false`.
  - `EstimateDetail(...) -> {seconds, legs = {mode, to, seconds, wait?, newFlightPath?}[]}?, reason?`:
    - it shares the ring cache;
    - `to = ns.LegLabel(leg)`;
    - leg `seconds = leg.arrive − previous leg's arrive` (the first leg from the plan's start); Planner legs carry `arrive`, not `seconds` (Planner.lua:666,700);
    - `wait = leg.wait` when it is ≥ 60 s, else absent;
    - `newFlightPath = true` when `leg.mode == "walk" and leg.to.undiscovered` (the same test as `Journey.lua:488`);
    - it returns fresh copies, with no internal tables.
  - `Active() -> boolean`: `ns.IsJourneyGuided() == true` (Journey.lua:435), meaning anyone's journey, AGF's included.
  - `estimated` is not exposed (no AGF string uses it).
- **Acceptance** (`luajit tests/api_spec.lua` in SPF):
  - 3 nil reasons, one per cause;
  - `EstimateDetail(...).seconds == Estimate(...)` and `Σ legs[i].seconds == seconds` for the existing fixtures;
  - a fixture with an undiscovered flight master sets `newFlightPath` on exactly that walk leg;
  - mutating a returned leg leaves a second call unchanged;
  - `Active()` is false, then true after `Navigate("OtherAddon", …)`, then false after `Cancel`.
- **Checks.** SPF's `tools/typecheck.sh` is clean, and so is the spec loop.
- **Release.** cjber tags an SPF release (e.g. `v1.2.0`) after the merge. AGF does not wait for it (§4).

## 3. AGF features, in build order

Each block lists: files · types (`types/Namespace.lua`) · data · atlases · client APIs · acceptance (the player sentence and its number → proof). `ns.L` (F14's table) lands before F2, so all new UI copy goes into it from the start; F14 is then only the sweep of old strings and the lint.

**F0 Rank without SPF; travel in its own frame (a prerequisite for the bench)**
- **Files:**
  - `tools/gen_quests.py` + `Data/Quests.lua` (regenerated): each `zones[id]` gains `continent` (`UiMapAssignment.MapID`) and `cx, cy`, the world-coordinate centre of its `Region_*` box. `tools/gen_quests_test.py` covers one zone.
  - `Model.lua`: `Plan` drops the `travel` argument. `Cost` orders lexicographically by tier, then distance: tier 0 same map (`Distance`), tier 1 same continent (world distance between the two zones' centres), tier 2 other continent (then by key). No SPF call.
  - `Core.lua`: `ns.Invalidate`'s callback runs `Rebuild` + `NotifyRouteChange`, then queues a separate `C_Timer.After(0)` for `ns.Integrations.RefreshTravel()`.
  - `Integrations.lua`: `TravelLine(step)` with **no AGF cache** (SPF caches 5 s, API.lua:9); it is refetched on every rebuild and on `ZONE_CHANGED_NEW_AREA`.
- **Types:** `AGFModel.Plan` loses `travel?`, `AGFStep.seconds` goes, `AGFRoute.minutes` goes (the design has no totals), `AGFZone` gains `continent`, `cx`, `cy`.
- **Acceptance:**
  - "Opening the guide never waits on travel maths" → `plan_bench`: 0 SPF calls in the rebuild frame, ≤ 1 in the travel frame (§1.4).
  - "A turn-in in the next zone is not ranked at random" → `ne21_crosszone` golden: the Ashenvale turn-in follows every Darkshore step and precedes any other-continent step.
  - `ui_spec`: move the player stub, invalidate, flush → exactly 1 new SPF call.

**F1 Map budget (Must; after §1.0)**
- **Files:** `Core.lua:12-13` (defaults become `showMapPins=false` and `showQuestGivers=false`) · `Pins.lua:77-94` (`RefreshAllData`: givers gated on `showMapPins and showQuestGivers` only, independent of SPF guiding; rings keep `Active()`, extended by the preview flag `Pins.previewJourney`) · `Settings.lua` tooltips. If the `questoffer` probe is present, `AddGivers` and `showQuestGivers` are deleted instead (§1.0).
- **Atlases:** unchanged. `adventureguide-ring` CSV:1189, `services-number-1..9` CSV:1645-1653, `UI-QuestPoi-InnerGlow` CSV:10079, `QuestNormal` CSV:1360. None has a `-c60` row.
- **Acceptance:**
  - "On a fresh install the map shows 0 Adventure Guide marks with the tab closed" → `ui_spec`: a fresh DB and 10 `RefreshAllData` give `AcquirePin` count 0.
  - "Opted in, the map shows at most 9 rings and exactly the zone's eligible givers" → `ui_spec`: rings ≤ 9; both prefs on → givers == `#Model.Givers(...)`, also while the SPF stub guides; either off → 0 givers.
  - "A saved `true` survives" → `ui_spec` loads `{showMapPins=true}` and the value is still `true`.

**F2 Journey cards (Must; after §1.0)**
- **Files:** `Model.lua` (new `Model.Journeys`; next-zone needs ≥ 5 eligible pickups, §1.5) · `Panel.lua` (remove the zone cards: `AGFZoneCard`, `SetZoneArt`, `CreateZoneCard` 114-206 and `RefreshChoices` from 566; the XP bar: `BuildExperience` 329-352 and `RefreshExperience` 537-562; "Why these?" 430-443; add `CreateJourneyCard`, and move the quest and dungeon chips (`BuildChips` 357-) into `BuildSettingsMenu`) · `Panel.xml` (`AdventureGuideForeverJourneyCardTemplate`, 288x86, inherits `AlphaHighlightButtonTemplate` `BLZ/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml:1587` or the §1.0 fallback, layout copied from `Blizzard_Journeys.xml:5-107`).
- **Types:**
  - `---@alias AGFJourneyKind "carry"|"story"|"nextzone"|"dungeon"`;
  - `AGFJourney{kind, key, title, subline, reason, map, steps: AGFStep[], story?: AGFStory}`;
  - `AGFRoute.journeys`;
  - `AGFPrefs.journey?: string`.
- **Atlases:** `ui-journeys-renown-button` CSV:15677 (374x112), `-pressed` CSV:15676, `ui-journeys-renown-radial-bar` CSV:16221, `questlog-questtypeicon-quest` CSV:9396, `-story` CSV:9400, `-group` CSV:9388, `QuestNormal` CSV:1360, `QuestLog-main-background` CSV:11182. None has a `-c60` row, so the plain names are used.
- **APIs:** `C_Map.GetMapInfo(uiMapID) -> UiMapDetails?` (DOC/MapDocumentation.lua:312) for zone names.
- **Acceptance:**
  - "The guide offers at most 3 journeys, each with at least 1 step it can take now" → `plan_golden_spec` over all fixtures (`#journeys ≤ 3`, every step Eligible or in the log).
  - `layout.json` shows each card at 288x86 with a 46x46 `IconFrame` (the harness instantiates the template's regions, §1.1).
  - `panel.png` montage.

**F3 Select, then Go (Must)**
- **Files:** `Panel.lua` (card `OnClick` sets `prefs.journey`, calls `ns.Invalidate()` and `WorldMapFrame:SetMapID(journey.map)`) · `Pins.lua` (shows the selected journey's rings while the panel is shown).
- **Acceptance:** "Choosing a journey moves nothing until Go" → `ui_spec`: 5 card clicks give `SetUserWaypoint` 0, `Navigate`/`NavigateRoute` 0, ≤ 1 `Estimate`/`EstimateDetail` per click (the step-1 travel line), `SetMapID` 5, and rings == the selected steps on that map. Closing the tab with pins off gives 0 pins.

**F4 Zone stories (Must)**
- **Files:** `Model.lua` (`Model.Story(data, questID)`, memoised in a weak table keyed by data, the same way as `Index`) · `Panel.lua` (the chapter track: 12x12 squares, text-only when longer than 8).
- **Types:** `AGFStory{chapter: integer, total?: integer, members: integer[]}` · `AGFModel.Story`.
- **Atlases:** `ui-journeys-delve-level-square` CSV:15642, `-green` CSV:15640, `-grey` CSV:15641. None has a `-c60` row.
- **Acceptance:** "Every story shows a total only when the prerequisite graph proves it" → a `model_spec` check over all 3535 quests.
  - Data today: 1604 quests carry `next`, 11 `next` values dangle, and there are 815 chain heads.
  - The spec's independent walker agrees with `Model.Story` for all 815 heads, and asserts 0 totals on chains that touch a dangling `next`, a `preAny` or a multi-`pre`.
  - The established count is pinned by the spec. This plan's pre-check found about 499 heads with a total and 316 with text only.
  - `ui_spec` shows 0 later-chapter titles in any rendered text. `plan_bench` stays green.

**F5 `Model.Why` and search as why-not (Must; after §1.0)**
- **Files:** `Model.lua` (`Why`, with `Eligible` (Model.lua:88-124) rewritten to use it) · `Panel.lua` (search results, 10 at most, when the query is 3+ characters).
- **Why lines.** The design's lines (`min`, `pre`, `preAny`, `side`, `races`, `classes`, `group`, suppressed start) plus the three other reasons `Eligible` returns false, added to design §2.4 and §3: `completed` → "You've done this", `log` → "In your quest log", `repeatable` → "Repeatable quests aren't suggested". Each is one unmet line; all go in `ns.L`.
- **Types:** `AGFWhyLine{text: string, met: boolean}` · `AGFModel.Why`.
- **Atlases:** `questlog-questtypeicon-lock` CSV:9393; `ui-questtracker-tracker-check-c60` CSV:18734 (the `-c60` row is preferred; the plain row is CSV:10177; §1.0 decides).
- **APIs:** `C_QuestLog.GetTitleForQuestID(questID) -> cstring?` (DOC/QuestLogDocumentation.lua:668); `C_QuestLog.RequestLoadQuestByID(questID)` (:1219).
- **Acceptance:**
  - "Why-not and the planner never disagree" → a `model_spec` loop over 3535 quests × 5 fixtures (with completed and log quests in each): `Eligible == (every Why line met)`, with 0 mismatches.
  - "A quest whose start is suppressed shows exactly 1 line, and no Go" → `ui_spec`.

**F6 Click opens Blizzard's quest details (Must)**
- **Files:** `Tracker.lua` (`OnBlockHeaderClick`) · `Panel.lua` (row `OnClick`).
- **APIs:** `InCombatLockdown() -> bool` (DOC/RestrictedActionsDocumentation.lua:45); `OpenQuestLog()`; `QuestMapFrame_ShowQuestDetails(questID)` (`BLZ/Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:1044`, which does not write `displayMode`). Never `QuestMapFrame_OpenToQuestDetails` (:1175).
- **Acceptance:** "Clicking a log quest opens its page once, and nothing opens in combat" → `ui_spec`: 1 `ShowQuestDetails(id)` call, 0 `displayMode` writes, and 0 calls with combat on. If F6 adds the "Show quest" menu entry, it updates §1.1 assert 5's menu list in the same commit.

**F7 Stop with waypoint ownership, Skip, "Skipped (n)" and "Show again" (Must)**
- **Files:** `Integrations.lua` (`Cancel` clears only AGF's own waypoint; `Owns()` compares the live user waypoint with `charDB.waypoint` within 1e-4, and clears `charDB.waypoint` when it no longer matches) · `Core.lua` (`ns.Unskip`, `charDB.waypoint`) · new `Menu.lua`, in the TOC right after `Integrations.lua` (the generator shared by `Tracker.lua` and `Panel.lua`; Tracker needs it even before Blizzard_WorldMap loads) · `Panel.lua` (the "Skipped (n)" text button under the rows, design §2.1, opening the same Skipped submenu).
- **Types:** `AGFPrefs.waypoint?: {map: integer, x: number, y: number}`.
- **APIs:** `C_Map.GetUserWaypoint() -> UiMapPoint?` (DOC/MapDocumentation.lua:454); `C_Map.SetUserWaypoint(point) -> bool` (:599); `C_Map.ClearUserWaypoint()` (:26); `C_SuperTrack.SetSuperTrackedUserWaypoint(bool)` (DOC/SuperTrackManagerDocumentation.lua:169); `MenuUtil.CreateContextMenu` (`BLZ/Blizzard_Menu/MenuUtil.lua:151`).
- **Acceptance:** "Stop never removes a waypoint you placed yourself" → `ui_spec`:
  - without SPF: Go, then the player moves the waypoint 0.01 away, then Stop: 0 `ClearUserWaypoint` calls; Go, then Stop: 1 call;
  - after a simulated reload (harness reloads with the saved DB) Stop is still shown for a matching native waypoint;
  - with the `v1` profile: Stop calls `Cancel(OWNER)` once, and Stop hides when `CurrentStop(OWNER)` is nil;
  - "Skipped (n)" is hidden at 0; after 2 skips it reads "Skipped (2)" and opens the same submenu; "Show again" restores the skipped step to the golden route.
  - the tracker menu list pinned by §1.1 assert 5 becomes design §2.8's for a log quest, and "Show quest" is absent for a non-log step.

**F8 Tracker lines and the resume line (Must)**
- **Files:** `Tracker.lua` (`LayoutContents`: place, reason, travel, next) · `State.lua:131` (pass `isInitialLogin`) · `Core.lua` (`charDB.last`; a latch set by an initial login and held until the first rebuild with `State.Ready()` true and ≥ 1 step, which then compares once with the live step 1).
- **Types:** `AGFPrefs.last?: {key: string, reason: string}`.
- **Atlases:** the header is template-set: `UI-QuestTracker-Secondary-Objective-Header` CSV:10176 (`-c60` CSV:18733).
- **Acceptance:** "The first login shows 'Where you left off' once; a /reload shows it 0 times" → `ui_spec`:
  - `PLAYER_ENTERING_WORLD(true,false)` with Ready true and a matching key: 1 line;
  - `(true,false)` with Ready false, then Ready true and a rebuild: 1 line;
  - `(false,true)`: 0 lines;
  - a stale key: 0 lines;
  - after a route change: 0 lines.

**F9 YAGNI and contract sweep (Must)**
- **Files:**
  - `Core.lua:23-25` and `:98` (remove `legacy`, `professions` and `pinned`), `Core.lua:109-121` (`ns.TogglePin`);
  - `Model.lua` (pinned logic at 287-296 and 369-375; `prefs.zone` at 347; `Model.Zones`' result is used only inside `Journeys`, and `route.zones` goes);
  - `Panel.lua` (row `PinButton`, 215/261-262/603; `prefs.zone` 187-190);
  - `Pins.lua:35` (`step.pinned`);
  - `types/Namespace.lua:58-60` and `:62` (`legacy`, `professions`, `zone`, `pinned`; `skipped` stays), `:79` (`AGFStep.pinned`), `:89-100` (`AGFZoneChoice`, `route.zones`, `route.zone`), `:142` (`TogglePin`);
  - `tests/model_spec.lua:40`, `:119-126`, `:166-167`;
  - README/CHANGELOG pin copy (in the docs step);
  - TOC: `## OptionalDeps: ShortestPathForever` (was `…, TweaksForever, LegacyForever`); `Notes` no longer says "3-5";
  - `Panel.xml:3`: the comment names `QuestLogTabButtonTemplate`, but Panel.lua:704 uses `LargeSideTabButtonTemplate`; it names the real template;
  - `Integrations.lua:11-17`: types move to `types/Namespace.lua` (lands with §1.6), and `REQUIRED` detection is added. `AGFSPFAPI.Cancel` becomes `fun(owner: string): boolean`, `Navigate`'s `title` becomes optional, and `NavigateRoute`/`CurrentStop` become required (they are v1 members in SPF).
  - `includeDungeonsDefault` stays: it seeds each new character's `prefs.dungeons` (Core.lua:57), which the cog menu then toggles.
- **Acceptance:**
  - `grep -nE 'legacy|professions|3-5|pinned|TogglePin|AGFZoneChoice|prefs\.zone' Core.lua Model.lua Panel.lua Pins.lua types/Namespace.lua tests/model_spec.lua AdventureGuideForever.toc` → 0 lines;
  - `grep -c '^## OptionalDeps: ShortestPathForever$' AdventureGuideForever.toc` == 1;
  - `grep -c 'QuestLogTabButtonTemplate' Panel.xml` == 0 and `grep -c 'LargeSideTabButtonTemplate' Panel.xml` ≥ 1;
  - `contract_spec` is green.

**F10 Travel line (Must)**
- **Files:** `Integrations.lua` (`TravelLine(step)`, skipped when `InCombatLockdown()`, keeping the last line) · `Tracker.lua` · `Panel.lua` (step-1 row, and the hover tooltip for other rows, with one call per hover).
- **TravelLine, fully:**
  1. With `EstimateDetail`: take the first non-walk leg, `VERB .. to .. " · " .. N min` (N = ceil of the route's seconds to that leg's arrival / 60, at least 1); if every leg walks, "Walk to " .. the last leg's `to` .. " · N min".
  2. Append " · new flight path" when any walk leg has `newFlightPath`; append " · N min wait" when the chosen leg has `wait` (≥ 60 s).
  3. Else with `Estimate` only: "About N min away".
  4. Else, or on any nil reason: no line. "unreachable" is never shown.
- **Types:** `AGFSPFAPI`, `AGFSPFLeg`, `AGFSPFDetail`, `AGFSPFMode` and `AGFSPFNoRoute`, as design §5.1 minus `estimated` (unused by any AGF string, so the SPF PR does not expose it; design §5.1 is updated to match).
- **Acceptance** → `ui_spec`, across the three SPF profiles, one case per string:
  - `{mode="flight", to="Sentinel Hill"}`, 360 s → "Fly to Sentinel Hill · 6 min";
  - a boat leg with `wait=120` → "Boat to Auberdine · … · 2 min wait";
  - a walk leg with `newFlightPath` before a flight → "Fly to Astranaar · … · new flight path";
  - all-walk → "Walk to … · N min";
  - `v1` → "About 6 min away"; absent → no line;
  - combat on gives 0 SPF calls, and the text is unchanged;
  - `grep -ci unreachable` over `layout.json` gives 0;
  - the ring tooltip pinned by §1.1 assert 5 becomes design §2.9's lines.

**F11 Chapter-end fanfare (Should)**
- **Files:** `Tracker.lua` (`blockTemplate = "ObjectiveTrackerAnimBlockTemplate"`, `BLZ/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerAnimTemplates.xml:55`; `SetNeedsFanfare(key)` `Blizzard_ObjectiveTrackerModule.lua:634`) · `State.lua` (`QUEST_TURNED_IN` → `ns.OnTurnIn`).
- **Atlases:** `ui-questtracker-objfx-barglow` is template-set (`-c60` CSV:18727).
- **APIs:** `PlaySound(soundKitID, ...) -> success, handle` (DOC/SoundDocumentation.lua:52) with `SOUNDKIT.UI_SCENARIO_STAGE_END` = 31757 (`BLZ/Blizzard_SharedXML/Mainline/SoundKitConstants.lua:125`).
- **Acceptance:** "Finishing a proven chain glows once and plays 1 sound; an unproven chain plays 0" → `ui_spec` (fanfare keys and `PlaySound` count). The `/reload` check 9 must pass before release.

**F12 Interleaving plus 2-opt over ≤ 9 stops (Should)**
- **Files:** `Model.lua` (after selection: nearest-neighbour over turn-ins and pickups together, then 2-opt on the F0 cost).
- **Combat.** `Core.lua`'s `Rebuild` checks `InCombatLockdown()`: in combat it runs only the cheap path (the carry journey's log steps via `LogSteps`; other cards keep the last full build; no `Journeys`, `Story` or 2-opt), sets `pendingFull`, and registers `PLAYER_REGEN_ENABLED` once to run the full rebuild. Event-driven, no timer. `ns.Route()`'s lazy path follows the same rule. (Lands with F2 so the rule exists before the heavier builds; F12 only adds 2-opt to the full path.)
- **Acceptance:** "Routes zig-zag less, and no step is added or lost" → `plan_golden_spec`: per fixture, the step key set is unchanged, and summed map distance ≤ the F0 golden value. The spec prints the count of fixtures that improved. `ui_spec` assert 6 (§1.1) and `plan_bench` stay green.

**F13 Go warns before replacing someone else's journey (Should)**
- **Files:** `Panel.lua` / the menu tooltip.
- **Acceptance:** "With another addon's journey running, Go's tooltip adds 1 line 'Replaces your current journey.'" → `ui_spec` with the `v1+` stub: `Active()` true and `CurrentStop(OWNER) == nil` → 1 line; AGF owns the journey (`CurrentStop(OWNER)` non-nil) → 0 lines; `Active` absent → 0 lines.

**F14 One `L` table and a copy lint (Should)**
- **Files:** `Core.lua` (`ns.L`, created before F2) · every UI file (the sweep of pre-existing strings, at the end) · new `tools/lint_copy.py` + `tools/lint_copy_test.py`.
- **Rule.** Banned in `L` values: a literal percent sign (`%%`, or `%` not followed by a format spec `[-0-9.]*[dsfgi]`), "XP", "fast", "fastest", "optimal", "you must", and "?" as a value. Format strings such as `"%d quests near your level"` and `"Chapter %d of %d"` pass; `lint_copy_test.py` covers both sides.
- **Acceptance:** `python3 tools/lint_copy.py` reports 0 banned tokens in `L`, and 0 string literals passed to `SetText` / `AddObjective` / `CreateButton` / `GameTooltip_*` outside `L`. It runs from `tools/typecheck.sh`.

**F15 Dungeon card (Should)**
- **Files:**
  - `tools/gen_quests.py`: add `db2("AreaTable", ("ID","ContinentID"))` and `db2("Map", ("ID","MapName_lang","InstanceType"))`. `dungeon` = `Map.ID` when `InstanceType ∈ {1,2}` through `ZoneOrSort → AreaTable.ContinentID`; `raid = true` for 2. Emit `zones`-style `instances = {[36] = {name = "Deadmines"}}`, and print `flagged dungeon`, `flagged raid` and `flagged, not elite`.
  - `tools/gen_quests_test.py`: a fixture where 1581 → 36 → party.
  - `Data/Quests.lua`: regenerated, never hand-edited.
  - `Model.lua`: `LogSteps` (Model.lua:243-244) applies the `quests`/`dungeons` prefs to nothing: log quests always show; the prefs gate pickups only. `Journeys` gains a dungeon kind, only when `prefs.dungeons` is on and the instance is not a raid. Its steps are only the eligible givers' `start` places.
  - `Panel.lua`.
- **Data:** before `--offline`, copy `AreaTable-1.60.1.69913.csv` and `Map-1.60.1.69913.csv` into `tools/.cache`, or run without `--offline` to fetch the same URLs.
- **Types:** `AGFQuest.dungeon` becomes "instance Map.ID (not a uiMapID)", plus `AGFQuest.raid?` and `AGFData.instances`.
- **Atlases:** `questlog-questtypeicon-dungeon` CSV:9387 (`QUEST_TAG_ATLAS[Enum.QuestTag.Dungeon]`, `BLZ/Blizzard_FrameXMLBase/Constants.lua:525`). It has no `-c60` row.
- **APIs:** `GetRealZoneText(mapID?) -> cstring` (DOC/ZoneScriptDocumentation.lua:28; the argument is an instance Map.ID) for the localised name, falling back to `instances[id].name` when it is empty (`/reload` check 12 proves it).
- **Acceptance:**
  - "133 dungeon and 90 raid quests are tagged" → `python3 tools/gen_quests.py --offline` prints `flagged dungeon: 133` and `flagged raid: 90`, and `model_spec` counts 223 `dungeon` fields.
  - "A dungeon quest you carry never disappears" → golden fixture with a flagged, non-elite quest complete in the log: its turn-in appears with dungeons off.
  - "With dungeons on, an Alliance level-18 character sees a Deadmines card whose steps are all quest givers with data coordinates; with dungeons off, 0 dungeon cards" → the `human18_westfall` golden fixture, and a `model_spec` loop showing that 0 dungeon-card steps lack `ValidPlace(start)`.

**Docs (Must, last)**
- `CHANGELOG.md` `[Unreleased]`: rewrite the prose per WFA-12. Nothing is released yet, so the current bullets are simply replaced: journeys instead of "pick the zone", no pins, map marks and givers off by default ("Turn them on under *Show map pins*").
- `README.md` per WFA-10 (centred icon, bold-led bullets, under 1,200 words); drop "Pin and skip" (README:17).
- `docs/curseforge.md` per WFA-11 (pitch, headline screenshots, under 600 words, no Install/Development).
- Screenshots from `docs/screenshots/` (WFA-9).
- After merge, the user pastes the store description through the `wow-addon-publish` skill.
- **Acceptance:** `wc -w README.md` < 1200, `wc -w docs/curseforge.md` < 600, `grep -ci 'pin or skip\|pick the zone' CHANGELOG.md README.md docs/curseforge.md` == 0.

## 4. Merge order

1. **SPF PR** `cb/api-detail`: review and merge. cjber tags the SPF release when convenient.
2. **AGF PR** `cb/journeys`. AGF runs on any SPF version:
   - `REQUIRED` covers only the v1 members;
   - `EstimateDetail` and `Active` are checked with `type(api.X) == "function"` where they are used;
   - `ui_spec` runs all three SPF profiles.
3. Only the AGF commit that bumps `contract_spec`'s `SPF_SHA` to the merge sha (and re-vendors `spf_types_API.lua`) waits for the SPF merge.
4. The AGF `v*` tag waits for the §5 checks, not for an SPF tag: on SPF v1.1.0 or v1, AGF shows the degraded line or none.

## 5. In-game `/reload` checklist (the user runs it; Claude never drives the client)

**Setup, once:** `/console scriptErrors 1`, `/console taintLog 1`. Before F1, F2 and F5: run the `forever-probe` batch (§1.0).

**Standard captures:**
- **SV**: `/agf dump`, then `/reload`, then send `WTF/Account/<acct>/SavedVariables/AdventureGuideForever.lua`;
- **TAINT**: send `Logs/taint.log`;
- **SHOT**: a screenshot of the named frame.

| # | Action | What to see | Capture |
|---|---|---|---|
| 1 | First login on a new level-1 character, SPF enabled | The tracker shows the Adventure Guide section. No "Where you left off" line (no saved key) | SHOT tracker, SV |
| 2 | Open the map, then the Adventure tab | 1 to 3 cards at 0.77-scale renown art with a clean border and hover highlight | SHOT panel, SV (`luajit tests/dump_diff.lua` vs `layout.json`) |
| 3 | Close the tab, and look at the zone map | 0 AGF rings and 0 "!" (pins off by default) | SHOT map |
| 4 | Reopen the tab and select card 2 | The map turns to the journey's zone. Only its rings are shown, and no waypoint is set | SHOT map + panel |
| 5 | Type `red linen` in search | Why-not lines: red unmet, ticked grey met, no Go on locked quests | SHOT panel |
| 6 | Click a log quest in the tracker, then enter combat (attack a training dummy or a mob) and click again | Blizzard's details open and the guide closes. In combat nothing opens | SHOT, TAINT (expect 0 AGF lines) |
| 7 | Set your own map waypoint, press Go with SPF disabled (`/disable ShortestPathForever`, `/reload`), then move the waypoint by hand and press Stop | Your own waypoint survives Stop. The tracker has no travel line | SHOT map, SV |
| 7b | Press Go without SPF, `/reload`, press Stop | Stop is still offered, and clears AGF's waypoint | SHOT map |
| 8 | With SPF enabled (the release with `EstimateDetail`), press Go | The tracker reads "Fly to … · N min" or, for a short trip, "Walk to … · N min". On an SPF build without `EstimateDetail` it reads "About N min away"; on v1.1.0 there is no line | SHOT tracker |
| 9 | Hand in the last quest of a chain the panel showed as "Chapter N of N" | "Story complete", the header glows once, and the stage-end sound plays. No toast | SHOT tracker (right after the turn-in), SV |
| 10 | `/reload` | No resume line appears | SHOT tracker |
| 11 | Log out, then log in to the same character | "Where you left off: …" appears once, and it goes after the next route change | SHOT tracker, SV |
| 12 | Enable dungeons in the cog menu at level ≥ 17 (Alliance) | A card named after the instance (localised through `GetRealZoneText`), whose steps are givers only | SHOT panel, SV |
| 13 | Level up (or ding during the test) | The cards rebuild once. No error, and no frame flicker | SV (`dump.route` changes), TAINT |
| 14 | Stand idle 60 s with the tab closed, then `/agf dump` and `/reload` | SV: 0 AGF frames with `onUpdate = true` | SV |
| 15 | Pull a mob with the tab open, loot a quest item mid-fight | No rebuild hitch in combat; the cards refresh once after combat | SV, TAINT |

## 6. Commit plan (each commit signed with `git commit -S`, one idea, about 50 lines)

**SPF (`cb/api-detail`):**
1. `refactor(journey): expose leg labels as ns.LegLabel`
2. `feat(api): Estimate returns why it has no answer`
3. `feat(api): EstimateDetail with copied legs, sharing the estimate cache`
4. `feat(api): Active reports any running journey`
5. `docs(api): types (descriptions after --), README and CHANGELOG for the additions`

**AGF (`cb/journeys`):**
1. `test: headless harness that loads the TOC in order and instantiates Panel.xml templates`
2. `test(ui): loads with and without Shortest Path; displayMode is never written`
3. `test(ui): no idle OnUpdate and no frames created on refresh`
4. `test(ui): pin lifecycle, tooltip and menu text`
5. `feat(debug): layout dump and /agf dump`
6. `test(ui): golden layout.json and the in-game dump diff`
7. `test: character fixtures and golden routes`
8. `feat(gen): zone continent and centre for cross-zone ranking` (F0; regenerates data)
9. `refactor(model): rank without Shortest Path; travel line in its own frame` (F0)
10. `test: plan bench with a counted Shortest Path cost`
11. `refactor(types): move the Shortest Path contract into types/Namespace.lua` (part of F9)
12. `test: contract spec against a pinned Shortest Path sha`
13. `ci: run the bench, diff the vendored contract, forbid outside paths in tests`
14. `tools: screenshots rendered from layout.json, with stock-template chrome`
15. `tools(screenshots): Shortest Path route geometry from Path.FindSync`
16. `tools(screenshots): manifest and compare montages against Legacy Forever and SkillUp`
17. `refactor: ns.L table for copy` (F14 part 1)
    — gate: §1.0 probe results read —
18. `feat(map)!: pins and givers off by default; givers ignore guiding` (F1)
19. `feat(core): cheap rebuild in combat, full rebuild after` (combat rule, F12 part 1)
20. `feat(model): Model.Journeys, hand-in and next-zone kinds` (F2)
21. `refactor(panel): remove zone cards, XP bar and "Why these?"`
22. `feat(panel): journey card template`
23. `feat(panel): journey cards in the guide`
24. `refactor(panel): quest and dungeon chips move to the cog menu`
25. `feat(panel): select a journey, then Go; the rings preview` (F3)
26. `feat(model): Model.Story with conservative totals` (F4)
27. `test(model): Story agrees with an independent walk over all data`
28. `feat(panel): chapter track and the story card`
29. `refactor(model): Eligible built on Model.Why` (F5)
30. `feat(panel): search shows why a quest is unavailable`
31. `feat: rows and tracker open Blizzard's quest details` (F6)
32. `fix(integrations): Stop clears only our own waypoint, across reloads` (F7)
33. `feat(menu): one step menu with Skip, Skipped (n) and Show again`
34. `feat(tracker): place, reason and next lines` (F8)
35. `feat(tracker): resume line on first login only`
36. `refactor!: remove pins and the zone choice` (F9)
37. `chore: drop legacy and professions prefs, and fix stale TOC and XML copy` (F9 remainder)
38. `feat(integrations): travel line from EstimateDetail, falling back to Estimate` (F10; bumps `SPF_SHA`)
39. `feat(tracker): chapter-end fanfare` (F11)
40. `feat(model): interleave steps and remove zig-zags` (F12)
41. `feat: warn before replacing another addon's journey` (F13)
42. `refactor: remaining copy into L, and the copy lint` (F14 part 2)
43. `fix(model): log quests are never hidden by the quest or dungeon filters` (F15 part 1)
44. `feat(gen): flag dungeon and raid quests from AreaTable and Map` (F15; regenerates data. Data/ is excluded from the 50-line target)
45. `feat(model): dungeon journey card`
46. `docs: CHANGELOG prose for the journeys release`
47. `docs: README and store page per WFA-10/11, with screenshots`

## Review dispositions

Every blocker and major in `plan-review.md` is applied above. Minor findings are applied except as noted:

- **#18 (in-game dump):** kept, not dropped, because /reload checks 2, 13 and 14 read it. Applied the rest: `json()` moved to `tests/`, the key clears on the next login, the compared fields are fixed (`tests/dump_diff.lua`), the manifest is cut, and `--verify` is dropped.
- **#13 ("breaking change" for pins and givers):** no version has been released (`CHANGELOG.md` has only `[Unreleased]`), so there is no player to break; the prose is rewritten, not flagged as breaking.
- **#28 (ranges):** the review's corrected ranges were themselves off. Panel 208-217 is `AGFRouteRow`'s annotations, not zone-card code, so the zone cards are 114-206. Pins `RefreshAllData` ends at 94, not 92. The plan uses the re-measured ranges.
- **#8 (cross-map ranking):** took the offline option (zone centres from `UiMapAssignment`), not capped SPF estimates, so the rebuild frame keeps 0 SPF calls.
- **#15 `questline`:** even if present, v1 keeps the conservative rule; adopting the API is a follow-up, so it does not block F4.
