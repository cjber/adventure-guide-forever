# What we can learn from Polestar

[Polestar](https://github.com/fitzforge/polestar) (fitzforge, GPL-3.0, v0.2.x) is a WoW: Forever leveling guide: hand-written
routes compiled from bundled pfQuest, QuestieDB, Wowhead and player recordings, with an arrow, travel planner, quality-of-life
toggles, gear picks, rares and a dungeon lookup in one addon. It overlaps Adventure Guide Forever most, then Shortest Path
Forever (navigation), Tweaks Forever (quality of life) and SkillUp Forever (professions).

This review read Polestar's addon, tools, tests and docs at its default branch on 2026-10-14 and checked each finding against
our own code. Nothing of Polestar's was run or copied; the ideas below are ours to implement in our own way. File references
to Polestar are relative to its repository root, ours to the named repository.

Value is high, med or low; effort is S (an afternoon), M (a few days) or L (a release of its own). Findings that conflict with a
repository's AGENTS.md rules say so.

## Fix first

These are defects or gaps in what we already ship, not new features.

| # | Repo | Finding | Value | Effort |
|---|------|---------|-------|--------|
| 1 | Tweaks | Polestar in every conflict list | high | S |
| 2 | Tweaks | Quest automation pays quest gold and accepts PvP-flagging quests unasked | high | S |
| 3 | AGF, Legacy, SkillUp | Unguarded `UnitGUID` reads in tooltips | med-high | S |
| 4 | AGF | Same-type objectives matched by order, not by name | high | S-M |
| 5 | SPF | Hearthstone unknown until the player rebinds | high | M |
| 6 | Tweaks | No repair retry after junk money arrives | med-high | S |

1. **Polestar in Tweaks' conflict lists.** Polestar publishes `Polestar = ns` with `Polestar.Get(path)` (`addon/Polestar/Core/Init.lua:11`)
   and turns on by default `qol.sellJunk`, `qol.autoRepair`, `qol.fastLoot`, `qol.skipGossip` (`QoL/QoL.lua:54-64`),
   `behavior.autoAccept`, `behavior.autoTurnin` (`Core/Engine.lua:31-32`), `maps.reveal` and `maps.zoneLevels` (`Maps/Maps.lua:21-24`)
   and `qol.questTooltips` (`Quests/QuestDB.lua:26`). No Tweaks conflict entry names it (`Bags/Vendor.lua:252-262`,
   `Bags/Junk.lua:8-13`, `Features/Automation.lua:23-33`, `Map/Exploration.lua:10-34`, `Map/ZoneLevels.lua:10-20`,
   `Quests/QuestProgress.lua:32`). With both loaded, a merchant gets two repairs and two chat lines, junk sales race and loot
   fires twice. Add a `when` per feature reading `Polestar.Get(...)`; reveal conflicts when `maps.reveal ~= "off"`.
2. **Quest automation guards.** Polestar skips accepting when `QuestFlagsPVP()` is set, skips turn-in when
   `GetQuestMoneyToGet() > 0`, and uses `AcknowledgeAutoAcceptQuest` for auto-accept quests (`Core/Automation.lua:57-82`).
   Tweaks' `Features/Automation.lua:172-197` accepts anything and pays a quest's gold cost silently. Add the three guards.
3. **Secret GUIDs in tooltips.** Polestar routes every unit read through `Compat.IsSecret`/`Compat.Readable`
   (`Core/Compat.lua:37-51, 116-124`) and skips forbidden tooltips (`Core/Hooks.lua:115-120`). AGF's `UI/Tooltip.lua:46` calls
   `guid:match` on `UnitGUID(unit)` unguarded; Tweaks guards the same pattern with `canaccessvalue`
   (`Quests/QuestProgress.lua:101`), SkillUp has `ns.Readable`, and AGF and Legacy have nothing. Guard AGF now (`/reload` test:
   hover NPCs in combat), then share one `Readable` helper and a `forever_tools` lint beside `lint_taint`.
4. **Objective matching.** Polestar fixed 135 goals in 46 quests that counted an objective by its place in QuestieDB's text rather
   than the quest log, for example The Guns of Northwatch counting Smythe against Fairmount (`CHANGELOG.md` 0.2.1); it now matches
   by name first (`tools/lib/data/recordings.js:676-705`). AGF's `OpenSlots` (`Planning/Steps.lua:211-240`) gives each client
   objective the first unused slot of its type, so two kill or two collect objectives listed in a different order swap: a finished
   objective's area stays on the route and the open one disappears. When two slots share a type, match the client text against
   the slot's NPC or item name from QuestieSource and fall back to order; add a spec with a two-kill quest from the corpus.
5. **Hearthstone before rebinding.** Polestar resolves `GetBindLocation()` against a generated inn table and learns the innkeeper on
   `HEARTHSTONE_BOUND` (`addon/Polestar/Nav/Travel.lua:884-918`). SPF knows a bind point only once it sees `HEARTHSTONE_BOUND`
   (`Transport/Teleports.lua:13-19, 110-121`), so every new install loses its biggest shortcut. Record the landing point after a
   successful Hearthstone cast (no data needed); optionally map bind names to QuestieDB innkeeper spawns (a WFA-28 waiver entry)
   and mark the known bind on the world map so players can see it.
6. **Repair after junk.** Polestar repairs once its junk sale finishes so the sale pays for it (`QoL/Vendor.lua:64-87`). Tweaks
   repairs on `MERCHANT_SHOW` (`Bags/Vendor.lua:284-301`) before selling starts 0.2 s later (`Bags/Junk.lua:415-424`), and never
   retries. Retry on `PLAYER_MONEY` while the merchant is open.

## Adventure Guide Forever

| # | Finding | Value | Effort |
|---|---------|-------|--------|
| 7 | Learn from the giver's window which quests it really offers | high | M |
| 8 | Hysteresis before the waypoint switches target | med | S |
| 9 | `PLAYER_LEVEL_UP` payload over a lagging `UnitLevel` | med | S |
| 10 | Rank search results by match quality | med | S |
| 11 | "Next camp" and "another NPC" step actions | med | M |
| 12 | Weight drop areas by drop chance and mob level | med | M |
| 13 | Shift-click a locked search row to start its chain | med | M |
| 14 | Skip the full replan when only a count changed | low-med | M |
| 15 | Live quest XP from the client | low | S |

7. **Offered quests.** On gossip, greeting and quest-detail windows Polestar compares the offered quest IDs with what the step
   expects, marks missing ones unavailable with a reason, persists "not offered" per level, clears on level-up or turn-in and shows
   "Skipped <quest>" (`Core/Engine.lua:3047-3175`, `Core/Compat.lua:193-217`). AGF registers none of these events; pickups come
   only from Questie's IsDoable (`Planning/Model.lua:356-362`), so a quest Forever removed or changed keeps sending the player
   back until they choose "Not this quest". Read the giver's offers, mark a missing, non-grey route quest of that NPC as unproven
   with a Why line ("The giver didn't offer it"), and say so quietly. This only tightens the eligibility rule.
8. **Waypoint hysteresis.** Polestar switches spot only when the new one is 40 yd nearer and never while inside the current area
   (`Core/Engine.lua:526-608`). AGF's `Walked` (`Core/Core.lua:546-570`) and `Enter` (`Planning/Steps.lua:521-547`) take the nearest
   every time, so two near-equal givers or nodes can flip the Shortest Path waypoint. Keep the current target unless the new one
   is 30-40 yd nearer.
9. **Level-up lag.** Polestar keeps the event's level because `UnitLevel` can lag it (`Core/Engine.lua:68, 83-86`). AGF's deferred
   rebuild reads `UnitLevel` (`Core/State.lua:451, 510`; `UI/Moments.lua:181`), so post-level-up suggestions can use the old
   level. Store the payload and use the larger.
10. **Search ranking.** Polestar tiers exact, prefix, word-prefix and substring matches, folds accents and requires every word
    (`Core/Search.lua:13-123`). AGF's `Model.Search` (`Planning/Model.lua:449-478`) sorts substring hits alphabetically and cuts
    at 10. Sort by tier, then eligible now, then level closeness, then title.
11. **Another camp or NPC.** Polestar cycles a multi-spot objective as a circuit and has an "Other" button for spots, trainers,
    vendors and inns (`Core/Engine.lua:513-608, 2943-2981`, `UI/GuideFrame.lua:292-301`). AGF keeps up to three cells per
    objective (`Integrations/QuestieObjectives.lua:62-86`) but cannot move on when a camp is cleared or contested. Add a "Next camp"
    step-menu action over the existing cells, and the same for a service stop's next-nearest NPC (`Planning/Services.lua`).
12. **Drop weighting.** Polestar ranks farm spots by missing items over drop rate times kill rate and drops spots 3+ levels above the
    player (`Core/Engine.lua:400-490`). AGF ranks dropper cells by zone then spawn count (`QuestieObjectives.lua:62-121`), so a 1%
    common dropper can beat the real one. Weight by QuestieDB drop rates when its support exposes them (check the installed
    QuestieDB), and rank down over-level cells. With the same data, a quest whose every dropper is below 1% can become optional
    with a reason (Polestar's solo filter, `docs/SIMULATION.md`).
13. **Locked quest chains.** Polestar lists a quest's open prerequisites in order (`addon/Polestar/Lookup/Guide.lua`). AGF's locked
    search rows only explain (`UI/PanelSearch.lua:74-83`). Shift-click could pin the earliest prerequisite that passes
    `Model.Eligible`, with "Starts with <quest>" in the tooltip; only an eligible quest becomes a target.
14. **Count-only log changes.** Polestar separates structural quest-log changes from count changes (`Quests/Tracker.lua:5-13`). AGF
    rebuilds on every `QUEST_LOG_UPDATE` (`Core/State.lua:487-501, 591-635`). Fingerprint IDs and done flags; when only counts moved,
    repaint the tracker and pins without `Shown.Build`.
15. **Quest XP.** Forever changed some quest XP; Polestar reads `GetQuestLogRewardXP` (`addon/Polestar_Recorder/Quests.lua:23-50`).
    AGF uses QuestieDB's QuestXP only (`Integrations/QuestieSource.lua:421-456`). Override for logged quests where the function
    exists, under pcall.

Not recommended for AGF: auto accept and turn-in (design §1), default key bindings and a welcome window (§2.13, §2.19), and map
reveal, rare toasts and quest-level prefixes, which belong to Tweaks.

## Shortest Path Forever

| # | Finding | Value | Effort |
|---|---------|-------|--------|
| 16 | Restore an unowned journey after `/reload` | high | M |
| 17 | Ease and move the fallback arrow like the Compass | med | S |
| 18 | Flights and times in flight-point tooltips | med | S |
| 19 | Route to instance entrances | med | M |
| 20 | Stop idle `OnUpdate` on the minimap route and arrow | med | M |
| 21 | Clamp the sampled run speed | low-med | S |
| 22 | Arrival sound, time remaining, goal on the minimap rim | low-med | S |

16. **Journeys across reloads.** Polestar re-applies its waypoint on login and resumes a flight timer from server time
    (`Nav/Nav.lua:471-475`, `Maps/FlightTimer.lua:189-199, 340-353`). SPF drops journeys on reload (`Journey/JourneyGuide.lua:64`).
    Save the goal in `charDB.journey` and restart unowned journeys (map click, `/way`, Nearby) on `PLAYER_ENTERING_WORLD`, after
    combat; let API owners re-assert; expire after about 30 minutes.
17. **Fallback arrow.** Polestar eases heading every frame and lets the arrow move and scale (`Nav/Arrow.lua:379-469`). SPF's arrow
    steps at 20 Hz and is fixed (`UI/Arrow.lua:58-79`) while its own Compass already eases and moves (`UI/Compass.lua:189-290`).
    Reuse the Compass code.
18. **Flight-point tooltips.** Polestar lists flights from a point with times (`Maps/TravelPins.lua:45-70`). SPF shows the name only
    (`UI/Map.lua:704-711`) despite having InFlight and measured times (`Transport/TaxiTimes.lua:264-268`). List direct
    destinations, measured first.
19. **Instance entrances.** Polestar points dungeon destinations at the entrance (`Lookup/Sources.lua:323-325, 646-650`). SPF drops
    the dungeon AreaTriggers it already reads (`tools/gen_transit.py:545`), so a point on an instance map is unreachable. Emit an
    entrance table from them and retarget such goals to "Enter <instance>" (extends the existing AreaTrigger waiver).
20. **Idle frames.** Polestar redraws only while position, facing or zoom change (`Nav/Pins.lua:1070-1165`). SPF's minimap route
    (`UI/Route.lua:525-596`) and arrow (`UI/Arrow.lua:90-97`, even at alpha 0) tick for the whole journey. Move both onto the
    Compass/MinimapPins wake pattern, polling only on transports.
21. **Run speed.** Polestar clamps live speed to 4-14 yd/s (`Nav/Travel.lua:39-40, 856-871`); SPF takes any positive `GetUnitSpeed`
    (`Core/PlanContext.lua:15-22`), so a plan made under Sprint or a slow is skewed for the whole journey.
22. **Small touches.** An optional stock arrival sound on `"arrived"` (Polestar `Nav/Nav.lua:294-345`); time remaining under the
    compass from `ns.JourneyTime` (Polestar `Nav/Arrow.lua:280-353`); the goal clamped to the minimap rim (Polestar
    `Nav/Pins.lua:1021-1053`), goal only.

SPF is ahead on walking (terrain A* against straight lines), transport data (live timetables, portals, lifts, ferries), flight
timing, hearth cooldown handling and its API and shims. Polestar's travel data adds nothing SPF lacks.

## Tweaks Forever and SkillUp Forever

| # | Repo | Finding | Value | Effort |
|---|------|---------|-------|--------|
| 23 | SkillUp | Expert and Artisan First Aid and Cooking from books and quests | high | M |
| 24 | Tweaks | Social automation: friend and guild exceptions, party and guild invites | med | S-M |
| 25 | Tweaks | Stronger summon, resurrection and battleground-release guards | med | S |
| 26 | Tweaks | Mark the best quest reward | med-high | M |
| 27 | Tweaks | Quest progress on item and object tooltips | med | M |
| 28 | SkillUp | Gathering skill-up colour on nodes and skinnable mobs | med | M |
| 29 | Tweaks | Bindable quest-item and quest-target buttons | med | M |
| 30 | Tweaks | World map coordinates | med | S-M |
| 31 | Tweaks | Small fixes: loot debounce, zone-map reveal, Shift to skip vendor | low | S |

23. **Profession ranks from items and quests.** Polestar's guides take First Aid through the Expert book and Triage, and Cooking
    through the Expert Cookbook and Dirge Quikcleave (`guides/forever/professions/first-aid.guide`, `cooking.guide`). SkillUp's
    `Data/Trainer.lua:432, 437` stops at 150 and `Core/Plan.lua:46-70` ends the route at the first rank no trainer teaches. Generate
    a rank-from-item/quest table from the client's Item and ItemEffect DB2 and route "Buy and read X" or "Do Y".
24. **Social automation.** Polestar exempts friends and guild from duel declines, accepts friends' party invites unless that would
    drop a queue, declines strangers' and guild invites, and stands down under the gamepad interface (`QoL/Social.lua:61-231`).
    Tweaks declines every duel (`Features/Automation.lua:230-235`). Add the exceptions and the invite options, all off by default,
    with Leatrix conflicts.
25. **Summon and resurrection.** Polestar checks `PlayerCanTeleport`, waits out `GetCorpseRecoveryDelay`, re-checks the offerer,
    skips Hardcore and lets Shift suppress (`QoL/Social.lua:109-161`, `QoL/Toggles.lua:165-173`). Tweaks accepts at once and hides
    the popups even if the accept failed (`Features/Automation.lua:199-228`). Hide a popup only after the accept succeeds.
26. **Best reward.** Polestar marks the best upgrade or highest vendor value, retrying uncached items (`QoL/Rewards.lua:60-339`). Start
    with a vendor-value coin on the best choice, own textures through `Art.Fit`; stat-weight upgrades are opinionated and L effort.
27. **Item and object tooltips.** Polestar adds objective progress and "Starts a quest" to item and object tooltips
    (`Quests/Tooltips.lua:75-106`). Tweaks registers a unit post-call only (`Quests/QuestProgress.lua:369`).
28. **Gathering colours.** Polestar encodes node and skinning thresholds (`tools/lib/professions/gathering/tables.js:5-31`). SkillUp
    covers item tooltips only. Colour object and unit tooltips from the live skill, with node requirements from the client's Lock
    DB2 (needs an AGENTS.md note, since recipe colours always come from the game).
29. **Quest buttons.** Polestar's named secure buttons use the nearest quest item and cycle `/targetexact` over kill targets, queuing
    changes until combat ends (`QoL/Buttons.lua`, `QoL/QoL.lua:172-191`). Tweaks' `Quests/QuestDistance.lua` already knows the
    nearest quest.
30. **Coordinates.** Polestar shows player and cursor coordinates and the zone range on the world map (`Maps/WorldMap.lua:118-226`);
    Tweaks adds the range to the hover label only (`Map/ZoneLevels.lua:83-108`).
31. **Small fixes.** Debounce `LOOT_READY` within 0.3 s (`QoL/Toggles.lua:100-117`); reveal on `BattlefieldMapFrame` too
    (`Maps/Reveal.lua:196, 208`); hold Shift to skip selling and repair (`QoL/Vendor.lua:111`).

Lower priority for Tweaks: run back or spirit healer advice (`QoL/Death.lua`, needs spirit healer positions under WFA-28), rare
alerts from vignettes and nameplates (`Rares/Detect.lua`), quest levels on greeting and detail titles (the gossip mixin hook
Polestar uses breaks Tweaks' taint rule) and XP per hour (`QoL/XP.lua`).

Tweaks is ahead on junk (native `SellAllJunkItems`, refundable items, stack re-checks, player-marked junk), guild repair limits,
conflict handling that reads the other addon's setting, escort quests and zone ranges from the client.

## Every repository

| # | Finding | Value | Effort |
|---|---------|-------|--------|
| 32 | In-game report window with a copy box and recent errors | high | M |
| 33 | Issue forms for each addon's wrong data | med-high | S |
| 34 | Check the packaged zip before upload | med-high | M |
| 35 | `Subscribe` callbacks in the AGF and SPF APIs | med | S-M |
| 36 | Accept players' SPF flight and boat observations | med | M |
| 37 | A shared `doctor` setup check | med | S-M |
| 38 | Catch stale screenshots in CI | med | M |
| 39 | THIRD_PARTY.md, a "For addon authors" changelog section, tests and contributor docs | low-med | S |

32. **Report window.** Polestar's report window (`addon/Polestar/UI/Report.lua`, `UI/Copy.lua`) builds versions, build, locale,
    character, the step with goal states and IDs, other addons and the last caught errors (`Core/Init.lua:66-93`) into a pre-selected
    copy box sized for one message. Our `/agf dump` needs a `/reload` and a saved-variables file; every `audit` prints to chat,
    which players cannot copy. Add `/<cmd> report` to each addon (AGF: the current stop, Why lines, QuestieDB version; SPF: the
    journey and ride trace; Legacy and SkillUp: the audit) and record errors through one `SafeCall`. Write it once in AGF and share
    the pattern.
33. **Issue forms.** Polestar's `wrong-step.yml` asks for guide, step, `/polestar where` output, character and version. Ours inherit
    the generic org `bug_report.yml`. Add a "wrong data" form per repo with a field for the report output (AGF wrong stop, Legacy
    wrong objective, SkillUp wrong number, SPF wrong route), copying the org `bug_report.yml` and `config.yml` alongside since a
    repo folder replaces the org defaults; add `/agf where`.
34. **Package check.** Polestar's `tests/pack.test.js` checks the zips' folders, licences and reproducibility. Our release workflow
    runs the BigWigs packager straight to upload, and nothing checks `.pkgmeta` ignores against the TOC. Add a CI job running the
    packager with `-d` that checks every TOC and XML file is present, no `tests`, `tools`, `types` or `.agents` ship, LICENSE ships,
    and the smoke spec passes on the packaged folder; write it once in `forever_tools`.
35. **API callbacks.** AGF (`docs/api.md`) and SPF (`docs/api.md`) tell callers to poll; Legacy already has a batched, error-isolated
    `Subscribe` (`legacy-forever/docs/api.md`). Port it for stop changes and journey start, change and end, which also removes the
    polling between AGF and SPF.
36. **Player observations.** Polestar's opt-in recorder addon and anonymising importer (`addon/Polestar_Recorder`,
    `tools/lib/recording/import.js`) improve its routes. SPF already measures flight times and boat sightings in saved variables
    and uses them only locally. Add `tools/import_observations.py` that strips realm and character and merges into a committed file
    `gen_transit.py` prefers over InFlight; later, AGF could record stop durations to check golden routes.
37. **Doctor.** Polestar's `tools/commands/doctor.js` checks every prerequisite with a fix per platform. Our checks need stylua, ruff,
    luacheck, luajit, LuaLS 3.19.1 with pinned annotations, and Pillow for screenshots, and `tools/typecheck.sh` stops at the first
    problem. A shared `forever_tools/doctor.py` can check every pin from `ci.yml` and `typecheck.sh`.
38. **Stale screenshots.** Polestar's CI regenerates previews and fails on `git diff`. Our PNGs are local-only. Commit a hash of each
    scene dump beside the PNGs and fail CI when a dump moved but its PNG did not.
39. **Docs.** A THIRD_PARTY.md per repo listing each input, its pin, licence and whether it ships (Tweaks ships LibAHTab and LibStub
    without a README credit); an optional `### For addon authors` changelog subsection so API notes stay out of store notes;
    `tests/README.md` for the AGF and SPF harnesses; a "Ways to help" README section pointing at the report command; an
    `.editorconfig` for Markdown, YAML and TOC files.

Not recommended: Polestar's guide-pack format and compiler. AGF plans from QuestieDB at runtime, so there are no hand-written
guides for others to extend; finding 35 covers integration.

## Where we are already ahead

- **Supply chain:** actions pinned to SHAs, Dependabot, actionlint, zizmor and gitleaks; Polestar uses tag-pinned actions and none of
  these.
- **Static checks:** luacheck, LuaLS with coverage, stylua, and the taint, art, multi-value and copy lints; Polestar has a syntax test.
- **Release:** automated through the BigWigs packager, gated on green CI and a changelog entry; Polestar's is a ten-step manual
  process.
- **Data:** a daily pin refresh that regenerates, checks reproducibility and opens a PR; Polestar builds data by hand and CI skips
  the tests that need it.
- **Tests:** golden routes, the 3 ms planner bench, byte-identical screenshots, a contract test against SPF's API and the sift gates.
- **Runtime data:** QuestieDB's Forever store is already in Forever's map frames and the client supplies titles and elite tags, so
  AGF needs none of Polestar's Era-to-Forever coordinate layer or hand-corrected ranks.
