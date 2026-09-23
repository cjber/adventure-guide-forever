# Journeys: design

Status: agreed design, not built. It merges the map-first design, which won the panel, with grafts from the
journal and tracker designs. Every claim the judges rejected has been removed. Appendix A has the verdicts.

Paths used below:
- `BLZ` = `wow-handoff/blizzard-ui/Interface/AddOns`
- `CSV` = `skillup-forever/tools/.cache/UiTextureAtlasMember-1.60.1.69913.csv`, cited as `CSV:<file line>` (the header is line 1)
- `PROBE` = `WTF/Account/<account>/SavedVariables/ForeverProbe.lua`
- AGF paths are relative to this repo at `a128f7a`.

## 1. Vision

Journeys is an adventure mode that could pass for Blizzard's own. It offers a few good choices, each with an honest
reason, using stock UI only. It is never a speedrun script and never clutters the map. It follows the three
Forever pillars (Blizzard, *What's Next* panel recap):

- **The world as the main character.** The map remains Blizzard's map. When the Adventure tab is closed, AGF draws
  nothing on it unless the player opts in. Steps are named after places and people ("Sentinel Hill needs hands"),
  not XP.
- **The journey before the destination.** The player chooses from at most three journeys. Chains read as a zone's
  chapters, with later chapter titles left unrevealed. There are no percentages, XP/hour figures or step counters.
- **Approachable and familiar.** The guide lives in the quest log tab and the objective tracker, both stock frames.
  Quest text is Blizzard's own details page. Leaving the plan is normal: Stop and Skip always work, and the route
  rebuilds from the live quest log.

Two standing rules from AGENTS.md:
- A quest whose eligibility the data cannot establish is never recommended.
- A step never points at coordinates the data does not have.

## 2. Surfaces

All atlases below appear as exact rows in the CSV. None of the atlases AGF sets has a `-c60` row, except the
tracker check, where AGF uses the `-c60` name. The tracker header and glow are set by Blizzard's templates, not
by AGF.

### 2.1 Quest-log tab "Adventure" (the journal)

The frame is today's `AdventureGuideForeverPanel`, which sits over `QuestMapFrame` at `ContentsAnchor`
(Panel.lua:741-777). Its background is `QuestLog-main-background` (CSV:11182, 307x510). The tab is AGF's own
`LargeSideTabButtonTemplate` (Panel.lua:704) with `islands-queue-prop-compass` (CSV:3202). Camelot hides the stock
tabs (`BLZ/Blizzard_UIPanels_Game/Camelot/QuestMapFrameOverrides.lua:3-6`; PROBE lines 31-40). The list scrolls
inside the existing `ScrollFrameTemplate` (Panel.lua:510).

```
+-----------------------------------------------+  308 px pane (QuestMapFrame.xml:648)
| [Search quests............]   Level 14   [*]  |  29 px top bar: SearchBoxTemplate (Panel.lua:486),
|-----------------------------------------------|  GameFontHighlightSmall, settings cog (Panel.lua:496, unchanged)
| +-------------------------------------------+ |
| | (?)  Finish what you carry                | |  card 1  288x86
| | ( )  3 quests ready to hand in            | |
| +-------------------------------------------+ |
| +===========================================+ |  card 2, selected (-pressed art)
| | (S)  A Westfall story                     | |
| | ( )  Chapter 2 of 4                       | |
| +===========================================+ |
|    [#][#][ ][ ]                               |  chapter track (2.3)
|  1 Gryan Stoutmantle          Sentinel Hill   |  step rows, 22 px each, 9 at most
|      Fly to Sentinel Hill · 6 min             |    GameFontHighlightSmall
|  2 The Defias Brotherhood                     |
|  3 Red Linen Goods                            |    optional rows at alpha 0.6 (Panel.lua:602)
| +-------------------------------------------+ |
| | (!)  Head to Darkshore at 14              | |  card 3
| | ( )  11 quests near your level            | |
| +-------------------------------------------+ |
|  Skipped (2)                                  |  GameFontNormalSmall text button, hidden at 0
|-----------------------------------------------|
| [          Go          ]          [  Stop  ]  |  40 px footer: UIPanelButtonTemplate 190x26 / 90x26
+-----------------------------------------------+
```

- **Removed:**
  - the three 64 px zone-art cards, `SetZoneArt` and the veil / "Best fit" band (Panel.lua:126-178). The map beside the list already shows the zone.
  - the XP bar (Panel.lua:329-356). The stock XP bar already shows this.
  - "Why these?" (Panel.lua:430-443). Each row now gives its own reason, and "why not" moves to search.
- The quest/dungeon chips move into the cog's settings menu. The cog stays the settings entry and is not reused for anything else.
- Only the selected card shows its step rows. Selecting a card sets `prefs.journey` and rebuilds the route. It never
  starts guidance. **Go** is the only way to start.
- **Stop** appears only while AGF owns the guidance. That means SPF's `CurrentStop(OWNER)` is non-nil, or the
  native user waypoint is still the one AGF set (§5.1).
- Fit: top bar, three cards and footer come to 342 px, which leaves room for about 7 step rows before the list scrolls.

### 2.2 Journey card

The card copies `RenownCardButtonTemplate` (`BLZ/Blizzard_EncounterJournal/Mainline/Blizzard_Journeys.xml:5-107`)
at 0.77 scale. It is copied, not inherited: the Encounter Journal is not loaded on Forever (PROBE `ej`,
lines 367-380: `addonLoaded` false, `EncounterJournal` false, `numTiers` 0).

```
+------------------------------------------+  NormalTexture ui-journeys-renown-button (CSV:15677, 374x112 -> 288x86)
|  .--.                                    |  PushedTexture / selected: ui-journeys-renown-button-pressed (CSV:15676)
| ( S  )  A Westfall story                 |  title: GameFontNormalMed2 (gold), LEFT of IconFrame RIGHT +5,+5 (xml:90-95)
|  '--'   Chapter 2 of 4                   |  subline: GameFontHighlightSmall (white) under the title
|         Continues a story you started    |  reason: GameFontHighlightSmall
+------------------------------------------+
  IconFrame 46x46 at LEFT x=15 (Blizzard 60x60 at x=20, xml:24-28); border ui-journeys-renown-radial-bar (CSV:16221)
  Icon 18x18 at CENTER; hover inherits AlphaHighlightButtonTemplate (SharedUIPanelTemplates.xml:1587)
```

- **Kind icons** follow Blizzard's `QUEST_TAG_ATLAS` (`BLZ/Blizzard_FrameXMLBase/Constants.lua:514-527`):

  | Card kind | Icon | Mock label |
  |---|---|---|
  | Hand-ins ("Finish what you carry") | `questlog-questtypeicon-quest` (CSV:9396) | `(?)` |
  | Zone story | `questlog-questtypeicon-story` (CSV:9400) | `(S)` |
  | Next zone | `QuestNormal` (CSV:1360), the same "!" the map uses | `(!)` |
  | Group quest (elite) | `questlog-questtypeicon-group` (CSV:9388) | — |

- **Fonts.** Blizzard sets the name in white `GameFontHighlightMed2` over a gold `GameFontNormalMed2` subline. AGF deliberately reverses this, to follow the house rule of a gold header over white body text.
- **What a card may offer.** A card only ever holds eligible, recommendable steps. It never shows a lock, never shows "opens at level N", and never marks something new-in-Forever or of unknown location. Locked quests appear only in search (§2.4).
- **Card kinds** (three at most, only those that have steps):
  1. **Finish what you carry**: log turn-ins and objectives.
  2. **The zone story**: the best eligible chain in the chosen zone.
  3. **Next zone**: `Model.Zones` for `level + 2`, shown only when it differs from the current zone.

### 2.3 Zone story chapters

A chain is built from `pre` and `next` by a new `Model.Story(data, questID)`, memoised per data load. `next` stays
display-only, as the generator says (tools/gen_quests.py:5); eligibility never reads it.

```
   [#][#][ ][ ]   Chapter 3 of 4          squares 34x34 drawn at 12x12, GameFontNormalSmall
   Chapter 3                              withheld title for a later chapter (GameFontDisableSmall)
```

- **Square states** keep Blizzard's meanings (`BLZ/Blizzard_FrameXML/RewardTrackTemplates.lua:427-436`):

  | State | Atlas |
  |---|---|
  | Chapters done | `ui-journeys-delve-level-square` (CSV:15642) |
  | The chapter most recently finished | `ui-journeys-delve-level-square-green` (CSV:15640) |
  | The current chapter and those after it | `ui-journeys-delve-level-square-grey` (CSV:15641) |

  Green means "last earned", as in Blizzard's track, not "current".

- **When a total is shown.** "of M" and the squares appear only when all of the following hold:
  - every member has at most one `pre` and no `preAny`;
  - no `next` points outside the data (agf.md counts 11 that do);
  - the forward walk ends on a quest that has no `next`.

  Otherwise the text is just "Chapter N", with no squares and no "?". Tracks longer than 8 show text only.
- **Unrevealed titles.** Future chapter titles are never shown. The step rows list only steps the player can take now.
- **Headings.** Stories are named after the zone ("A Westfall story"). The data has no questline names, and AGF never invents one.

### 2.4 Why-not view (search)

Typing 3 or more characters in the search box replaces the cards with up to 10 matching quests for the
player's side. Eligible matches show as normal rows. Ineligible matches show why:

```
+-----------------------------------------------+
| [red linen.................]                  |
|  [L] Red Linen Goods             Westfall     |  questlog-questtypeicon-lock (CSV:9393) 18x18, GameFontNormal
|      Requires level 14                        |  unmet: GameFontHighlightSmall in RED_FONT_COLOR
|      [v] Completed: The Forgotten Heirloom    |  met: |A:ui-questtracker-tracker-check-c60:12:12|a (CSV:18734), GRAY_FONT_COLOR
|      Warriors only                            |  unmet
|  [L] Grove of the Ancients                    |
|      The guide can't tell where this starts   |  start suppressed by the generator: one line, never a Go
+-----------------------------------------------+
```

- **One source of truth.** A new `Model.Why(data, player, completed, log, id) -> {text, met}[]` is extracted from
  `Eligible` (Model.lua:88-124), so the two cannot disagree. A spec runs both over every quest in the data.
- **Requirements covered** are exactly the fields the data carries:
  - `min`;
  - each `pre`, and `preAny` ("one of");
  - `side`;
  - `races` and `classes`;
  - exclusive `group` ("You chose X instead");
  - the other reasons `Eligible` returns false: completed ("You've done this"), in the log ("In your quest log"),
    repeatable ("Repeatable quests aren't suggested").
- **Not covered.** Reputation has no field, so it is never shown. Quests whose start the generator suppressed
  (gen_quests.py:367-390) get only the "can't tell" line.
- **No ring, no Go.** A locked or unknown quest never gets a map ring or a Go button.
- **Met lines are ticked and dimmed, not struck through.** A FontString cannot be struck through. Blizzard's only
  precedent is a hand-sized 1x2 texture in the shop card
  (`BLZ/Blizzard_CatalogShopSharedTemplates/Blizzard_CatalogShop_SharedProductCards.xml:157-160`).
- **Tooltip.** Hovering a row shows the same lines, using `GameTooltip_AddErrorLine` / `AddDisabledLine`
  (`BLZ/Blizzard_SharedXML/SharedTooltipTemplates.lua:158,162`).

### 2.5 Tracker section

This is the existing `AdventureGuideForeverObjectiveTracker`, built on `ObjectiveTrackerModuleTemplate`
(`BLZ/Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerModule.xml:78`) at `uiOrder = -4` (Tracker.lua:6, 114):
- The module header is drawn by the template: `UI-QuestTracker-Secondary-Objective-Header` (Module.xml:22; the CSV also has a `-c60` row, CSV:18733) in `ObjectiveTrackerHeaderFont`.
- Lines use `block:AddObjective` (`Blizzard_ObjectiveTrackerBlock.lua:161`) with stock dash styles (`Blizzard_ObjectiveTrackerShared.lua:21-23`) and the stock tracker colours.

```
ADVENTURE GUIDE                                 module header (template)
   Turn in: Bathran's Hair                      block header = step title
   - Shindrell Swiftfire, Astranaar             place
   - Where you left off: finishes a story       reason; prefix only on the first login layout
   - Fly to Astranaar · 4 min                   travel line (§5.1), omitted when unknown
   Next: The Ruins of Stardust                  OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE
```

- **Resume line.** `charDB.last = {key, reason}` is saved on each rebuild.
  - The line is added only on `PLAYER_ENTERING_WORLD` with `isInitialLogin` true, and only when `charDB.last.key` equals the *live* step 1 after the rebuild. A stale key shows nothing.
  - It is cleared on the first route change. There is no timer, and a `/reload` does not show it.
- **Travel line.**
  - With EstimateDetail: "Fly to X · N min" (first non-walk leg, plus the total).
  - With Estimate only: "About N min away".
  - Without SPF: omitted.
  - In combat, or when SPF returns nil, the previous line is kept. "Unreachable" is never shown.
- **Clicks.**
  - Left-click on a log quest: `OpenQuestLog()` then `QuestMapFrame_ShowQuestDetails(questID)`
    (`BLZ/Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:1044`). This runs out of combat only. AGF never calls
    `QuestMapFrame_OpenToQuestDetails`, which writes `displayMode` (lua:1175-1178). The existing hook
    (Panel.lua:765-769) closes the guide.
  - Left-click on any other step: opens the Adventure tab.
  - Right-click: the menu (§2.8).

### 2.6 Map pins and route preview

**Map budget.** A headless spec asserts all of this:

| Layer | Max | Shown when |
|---|---|---|
| Numbered route rings | 9 (`MAX_STEPS`, Model.lua:5), only the selected journey's, only on its zone map | the Adventure tab is open (preview), **or** `showMapPins` is on |
| Quest-giver "!" | the zone's eligible, non-gray givers | `showMapPins` **and** `showQuestGivers` are both on; both default **off** |
| Lines, dots, overlays, continent marks | 0 | never drawn by AGF |

While SPF is guiding, AGF's rings hide, because SPF draws its own stops (Pins.lua:15-17).

```
+--------------------------------------------------------------+
| Westfall                                    [filter v]       |
|                    (3)                                       |  stock map art and stock pins untouched
|        (2)                  (4)                              |
|  (1) Sentinel Hill                                           |
|                                    (5)                      |  no "!" field, no dots
+--------------------------------------------------------------+
  (n) = AdventureGuideForeverPinTemplate 26x26 (Panel.xml:17-65):
        adventureguide-ring (CSV:1189) + services-number-1..9 (CSV:1645-1653), hover UI-QuestPoi-InnerGlow (CSV:10079)
```

- **Preview.** Selecting a card turns the map to that journey's first zone (`WorldMapFrame:SetMapID`) and draws
  only its rings. Hovering a step row flashes its ring (`Pins.Ping`, Pins.lua:184-188). Nothing moves until Go.
- **One switch.** `showMapPins` (Core.lua:12) becomes the single control for every AGF layer, and its default
  changes to off (opt-in). `AddGivers` moves under that check: today it runs first (Pins.lua:83-86), so givers
  bypass the switch. `showQuestGivers` (Core.lua:13) defaults to off. This is a default change, not a bug fix,
  because givers already have their own pref.
- **Saved settings.** Saved values survive a default change (Core.lua:7-8), so players who already saved a value keep it.

### 2.7 Chapter end (the "toast")

There is no AlertFrame toast. Instead, the tracker shows a one-time fanfare on the frame the player is already watching:

```
ADVENTURE GUIDE
   Story complete                               block header; HeaderGlow plays once (AddAnim)
   - Next: Shindrell's Request, Astranaar
```

- **Template.** The module's `blockTemplate` becomes `ObjectiveTrackerAnimBlockTemplate`
  (`Blizzard_ObjectiveTrackerAnimTemplates.xml:55`). Its `HeaderGlow` atlas `ui-questtracker-objfx-barglow`
  (template-set; the CSV has a `-c60` row, CSV:18727) plays through `OnLayout` when `NeedsFanfare(self.id)`
  (AnimTemplates.lua:97-100).
- **Trigger.** On `QUEST_TURNED_IN`, AGF calls `module:SetNeedsFanfare(key)` (`Blizzard_ObjectiveTrackerModule.lua:634`)
  and `PlaySound(SOUNDKIT.UI_SCENARIO_STAGE_END)` (31757, `Blizzard_SharedXML/Mainline/SoundKitConstants.lua:125`).
  This fires only when §2.3 establishes that the turned-in quest is the chain's last. A chain with an unknown end
  never claims completion. The header reads "Story complete", never "Chapter N complete".
- **Validation.** It ships only after the `/reload` checks in §8 pass.

### 2.8 Menu

The menu uses `MenuUtil.CreateContextMenu` (`BLZ/Blizzard_Menu/MenuUtil.lua:151`, already used at Tracker.lua:26).
The tracker right-click and a step-row right-click share one generator. The "Skipped (n)" button opens the
Skipped submenu on its own.

```
+-----------------------------+
| Bathran's Hair              |  CreateTitle
| Go                          |  Integrations.Navigate(step)
| Stop                        |  only while AGF owns guidance
| Show quest                  |  only for log quests, out of combat
| Skip for now                |  ns.Skip(key)
| Skipped (2)               > |  "Show again: <title>" -> new ns.Unskip(key) + ns.Invalidate()
| Choose another journey      |  ns.OpenPanel()
+-----------------------------+
```

Skips stay session-only (Core.lua:32-35). The menu has no auto-go.

### 2.9 Tooltips

Tooltips use Blizzard's voice through the helpers in `BLZ/Blizzard_SharedXML/SharedTooltipTemplates.lua`
(SetTitle :128, AddNormalLine :142, AddHighlightLine :150, AddInstructionLine :154). They anchor `ANCHOR_RIGHT`,
as today (Pins.lua).

```
Map ring / step row                         Journey card
+--------------------------------------+    +--------------------------------------+
| 2. The Defias Brotherhood            |    | A Westfall story                     |  SetTitle (gold)
| Chapter 2 of 4                       |    | Chapter 2 of 4                       |  AddNormalLine (gold)
| Fly to Sentinel Hill · 6 min         |    | Continues a story you started        |  AddHighlightLine (white)
| Continues a story you started        |    | 5 steps                              |  AddHighlightLine
| Click to travel with Shortest Path   |    | Click to choose this journey         |  AddInstructionLine (green)
+--------------------------------------+    +--------------------------------------+
```

When `SPF.Active()` exists and reports another journey running, Go's tooltip adds "Replaces your current journey."

## 3. Copy style sheet

- Sentence case. No exclamation marks. Digits for numbers. "·" as the separator.
- The world is the subject where possible ("Sentinel Hill needs hands"), not the player.
- Gold header (`GameFontNormal*`, `NORMAL_FONT_COLOR`) over white body (`GameFontHighlight*`). Detail lines use
  `GameFontHighlightSmall`; dimmed lines use `GameFontDisableSmall`. The tracker keeps its stock colours.
- Never write "%", "XP", "XP/hour", "fast", "fastest", "optimal", "you must", or "?" as a value. If a value is
  unknown, the line is left out.
- Travel verbs match SPF's `VERB` table (shortest-path-forever `Journey.lua:11-20`: "Fly to", "Boat to", …), so
  AGF and SPF speak with one voice.
- All strings live in one `L` table in Core.lua. Titles come from `C_QuestLog.GetTitleForQuestID` when the
  client has them cached, otherwise from the data's English title. Zone names come from `C_Map.GetMapInfo`.

| Where | Example |
|---|---|
| Card titles | `Finish what you carry` · `A Westfall story` · `Head to Darkshore at 14` |
| Card sublines | `3 quests ready to hand in` · `Chapter 2 of 4` · `Chapter 2` · `11 quests near your level` |
| Reasons | `Continues a story you started` · `Begins a Westfall story` · `Ready to hand in` · `Sentinel Hill needs hands` · `Better with others` |
| Travel | `Fly to Sentinel Hill · 6 min` · `Boat to Auberdine · 2 min wait` · `Fly to Astranaar · new flight path` · `About 4 min away` |
| Why-not | `Requires level 14` · `Completed: The Forgotten Heirloom` · `Requires one of: A, B` · `Horde only` · `Warriors only` · `You chose X instead` · `The guide can't tell where this starts` · `You've done this` · `In your quest log` · `Repeatable quests aren't suggested` |
| Tracker | `Where you left off: finishes a story` · `Next: The Ruins of Stardust` · `Story complete` |
| Buttons, menu | `Go` · `Stop` · `Show quest` · `Skip for now` · `Skipped (2)` · `Show again: <title>` · `Choose another journey` |
| Instructions | `Click to travel with Shortest Path` · `Click to set a waypoint` · `Click to choose this journey` · `Replaces your current journey.` |
| Empty | `Nothing nearby fits your level. Try another zone.` |

## 4. Features, in build order

| # | Feature | Tier | Reason |
|---|---|---|---|
| 1 | Map budget: one `showMapPins` switch, off by default, over every layer; givers move under it and default off; spec-tested caps | Must | Map clutter is players' top complaint (games.md pain point 1: Questie #6916, Reddit 1s12dc2). Today the giver "!" draws even with pins off (Pins.lua:83-86). This change needs no new art. |
| 2 | Journey cards, at most 3, replacing zone cards, XP bar and "Why these?" | Must | A few choices, each with a reason (pain points 2 and 8). Uses three stock card atlases, and the EJ is not required. |
| 3 | Select-then-Go, with the rings preview while the tab is open | Must | The player sees the shape of the evening before committing, and nothing acts on their behalf (pain point 2). |
| 4 | Zone stories: `Model.Story` from `pre` and `next`, conservative totals, later titles withheld | Must | Wires the unread `next` (1604 quests, agf.md). Stories, not errands. |
| 5 | `Model.Why` extracted from `Eligible`, plus search-as-why-not | Must | Answers "Am I even eligible?" (Reddit 1wjxhx9), and cannot drift from the planner. |
| 6 | Row or tracker click opens Blizzard quest details (log quests, out of combat) | Must | Quest text stays Blizzard's (pain point 6). Low cost. |
| 7 | Stop with waypoint ownership, plus Skip and "Show again" | Must | Leaving the plan is first-class (RXP #246, Guidelime #107). Wires the uncalled `Integrations.Cancel` (Integrations.lua:67-76), which today clears *any* user waypoint (line 74). |
| 8 | Tracker lines: place, reason, travel, next; resume line validated against live step 1 | Must | The frame players already watch, one line per job. The resume line answers "what was I doing?" without keeping a step index. |
| 9 | YAGNI and contract sweep (see list below the table) | Must | The brief's wired-or-deleted rule. |
| 10 | Travel line from SPF `EstimateDetail` | Should | Honest cost of a choice. Blocked until SPF ships it; `Estimate` covers the gap. |
| 11 | Chapter-end fanfare in the tracker | Should | A small, finite reward. Needs `/reload` validation first. |
| 12 | Route interleaving plus 2-opt over ≤9 stops, out of combat | Should | Today every turn-in comes before any pickup, however far away (agf.md). The pass never adds steps, only removes zig-zags. |
| 13 | SPF `Active()`: Go warns before replacing the player's own journey | Should | Respects a journey the player chose. |
| 14 | Zones 2521 Zephras Isle and 2548 Riverglades in `gen_quests.py` (TF has them, siblings.md §4) | Should | Forever-only zones currently get no range. |
| 15 | One `L` table for all copy | Should | Localisation groundwork. The strings are inline English today. |
| 16 | "New in Forever" tag (`adventureguide-icon-whatsnew`, CSV:2024) on quests already in the log only | Could | Needs the generator to emit the IDs missing from CMaNGOS (count unverified). Never on cards or recommendations. |
| 17 | Dungeon card | Could | Blocked: `dungeon` is set on 0 quests (agf.md) and the EJ is absent (PROBE). Needs a generator fix plus a TF `DungeonEntrance` API. |
| 18 | Discovery hint: one unexplored area named as text | Could | Needs a LegacyForever API that does not exist. Text only, never a ring. |

Contents of the sweep (#9):
- delete `prefs.legacy` and `prefs.professions` (Core.lua:23-24, types/Namespace.lua:58-59, the spec);
- set TOC `OptionalDeps` to `ShortestPathForever` only;
- replace the SPF detection with §5.1 and move its types into `types/Namespace.lua`;
- fix the "3-5 steps" copy (toc:3, Namespace.lua:98) and the stale Panel.xml:3 comment.

## 5. Sibling API contracts

### 5.1 Shortest Path Forever: the only contract AGF uses

SPF `origin/main` 39d9a98 exposes `version = 1`, `Estimate`, `NavigateRoute`, `Navigate`, `CurrentStop` and
`Cancel` (API.lua:84-237). None of this is released: the latest tag is v1.1.0 and the API sits under
`[Unreleased]` in its CHANGELOG. Store users therefore run the native-waypoint path, and that path stays first-class.
`EstimateDetail`, the nil-reason return and `Active` are **proposals** for SPF. They are additive, so the version stays 1.

```lua
---@meta
---@alias AGFSPFMode "walk"|"flight"|"boat"|"zeppelin"|"lift"|"tram"|"portal"|"passage"
---@alias AGFSPFNoRoute "combat"|"invalid"|"unreachable"

---@class AGFSPFStop
---@field map integer
---@field x number
---@field y number
---@field title? string

---@class AGFSPFLeg
---@field mode AGFSPFMode
---@field to string               -- SPF's own node/dock label (NodeLabel)
---@field seconds number
---@field wait? number            -- scheduled transport wait
---@field newFlightPath? boolean  -- destination taxi node not yet known to this character

---@class AGFSPFDetail
---@field seconds number
---@field legs AGFSPFLeg[]        -- copies, never SPF internals

---@class AGFSPFAPI
---@field version integer         -- AGF accepts exactly 1
---@field Estimate fun(fromMap: integer, fromX: number, fromY: number, toMap: integer, toX: number, toY: number): number?, AGFSPFNoRoute?
---@field Navigate fun(owner: string, map: integer, x: number, y: number, title?: string): boolean
---@field NavigateRoute fun(owner: string, stops: AGFSPFStop[]): boolean
---@field CurrentStop fun(owner: string): integer?
---@field Cancel fun(owner: string): boolean
---@field EstimateDetail? fun(fromMap: integer, fromX: number, fromY: number, toMap: integer, toX: number, toY: number): AGFSPFDetail?, AGFSPFNoRoute?  -- proposed
---@field Active? fun(): boolean  -- proposed: any journey running, anyone's
```

Runtime detection replaces today's `version >= 1` (Integrations.lua:22):

```lua
local REQUIRED = { "Estimate", "Navigate", "NavigateRoute", "CurrentStop", "Cancel" }

---@return AGFSPFAPI?
local function SPF()
	local api = ShortestPathForever and ShortestPathForever.API
	if type(api) ~= "table" or api.version ~= 1 then
		return nil
	end
	for _, name in ipairs(REQUIRED) do
		if type(api[name]) ~= "function" then
			return nil
		end
	end
	return api
end
-- Optional members are checked where they are used: type(api.EstimateDetail) == "function".
```

What AGF does when each piece is missing:

| Missing | AGF does |
|---|---|
| All of SPF, or v1.1.0 from the stores | Sets a native user waypoint for step 1. Stop clears it only if `C_Map.GetUserWaypoint()` (MapDocumentation.lua:454) still matches the `UiMapPoint` AGF set (same map, and x/y within 1e-4). Routes are ordered by map distance. There is no travel line. |
| `EstimateDetail` | Travel line reads "About N min away", from `Estimate`. |
| The nil reason | AGF checks `InCombatLockdown()` before calling. A nil result means the line is omitted, or the previous line is kept if there was one. |
| `Active` | Go behaves as it does today, and no warning is shown. |

Not requested:
- `RegisterCallback`. Rings and Stop re-check `CurrentStop(OWNER)` on route change and on map `RefreshAllData`.
- `EstimateMany`. Siblings.md measures 40 estimates at about 0.63 ms warm.
- Stop metadata.
- `Preview`. SPF's dotted preview stays SPF's; AGF draws no lines.

### 5.2 Legacy Forever, Tweaks Forever, SkillUp Forever: none in v1

| Sibling | Contract | Why not |
|---|---|---|
| LegacyForever (formerly LegacyHere) | none | It has no public API (origin/main ea0fb8c; the PROBE `legacy` scan shows only `LegacyForever*` mixins and DB). Its data has 0 quest criteria (siblings.md §3), so no quest can be honestly tagged, and percentages are Legacy's domain. It returns only if Could #18 is promoted, as `Objectives(uiMapID)` with no percent. |
| TweaksForever | none | AGF bakes the same zone table at generation time (siblings.md §4). `DungeonEntrance` is needed only for Could #17. |
| SkillUpForever | none | Profession steps are out of scope for a quest journal. |

## 6. Known flight paths: decision

AGF never reads `C_TaxiMap`. A "new flight path" note reaches the player only as SPF's
`EstimateDetail` leg flag `newFlightPath`. SPF already records each character's known nodes at flight masters, and
its own source says the world-map query "reports every node as discovered on this client" (shortest-path-forever
Taxi.lua:4-6). The probe agrees: away from a flight master, `GetTaxiNodesForMap(1414)` returned 38 nodes with 0
undiscovered (PROBE lines 66-72). That is one sample, from one character in one place, so it supports SPF's comment
but does not prove it on its own. The faction was not recorded, so the result is not read as "Horde saw Alliance
nodes". There is no separate known-flight-paths API.

## 7. Cut, and why

- **AlertFrame toasts** (the scenario and world-quest templates). The tracker fanfare says the same thing without taking the toast slot. The stock labels are hard-coded (`AlertFrameSystems.xml:770`), and registering from addon code is unverified for taint.
- **Continent-view rings, hover hint ring, SPF preview dots.** New map marks work against "never map clutter", and their APIs (SPF `Preview`, LegacyForever `Objectives`) do not exist. Reconsider only after they ship and a `/reload` shows they stay quiet.
- **Legacy tags and any Legacy progress.** Boundary rule, and 0 quest criteria.
- **Locked or "opens at level N" cards, and cards whose start is unknown.** They conflict with the AGENTS.md recommendation rule.
- **"Chapter N of ?" and "?" in any copy.** Unknown values are left out.
- **Chapter completion inferred from a dangling `next`.** Missing data cannot prove an end.
- **Separate story and why-not pages, "Then" rows, "Other roads", zone-art crop.** These add surface area and would not fit the 510 px page. Search and the selected card cover them.
- **Reusing the settings cog as a zone dropdown.** It would remove access to settings.
- **Stretching `pricestrikethrough-gray` over text.** Blizzard draws it at atlas size only. Met requirements are ticked instead.
- **Class trainer reminder.** `spellbook.future = {}` with 34 items at level 18 (PROBE lines 123-127). That is one sample, so this is a re-probe question (§9), not a proven absence.
- **Rest stop.** None of the 28 candidate camp auras was present (PROBE lines 129-147), and the CSV has no camp atlas.
- **Encounter Journal integration.** It is not loaded, and has 0 tiers (PROBE `ej`).
- **Reputation requirements.** There is no data field for them.
- **Traveler's Journal and alt memory.** They need account-wide progress state, which is a treadmill (games.md pain point 9).
- **Weekly bounties.** A progress treadmill, and against the pillars.
- **Bundled quest text.** Uncached quests have no text (PROBE `questtext`: `HaveQuestData` false for 5892 and 7). Blizzard's details page shows log quests.
- **SkillUp steps; TF `ZoneRange` / `IsActive`; SPF `RegisterCallback` / `EstimateMany` / stop metadata.** YAGNI (§5).
- **Hardcore-aware routing.** Future note: when `C_GameRules.IsHardcoreActive()` is true (false in PROBE), drop optional elite steps from cards.

## 8. `/reload` checks for the PR

Nothing below has been validated in game yet.

1. The card art renders cleanly at 0.77 scale, and `AlphaHighlightButtonTemplate` exists on Camelot.
2. Selecting a card turns the map and shows only its rings. Closing the tab clears them (pins off). With pins off, no "!" appears.
3. Row and tracker click opens Blizzard details and closes the guide. In combat nothing opens, and no taint is logged.
4. Stop clears only AGF's waypoint: a waypoint the player set by hand survives.
5. Login (not a `/reload`) shows the resume line once. It stays hidden if step 1 changed.
6. Finishing a chain with an established end glows the tracker header once and plays the stage-end sound. There is no toast.
7. With SPF disabled, the waypoint works and no travel line shows. On SPF v1 without `EstimateDetail`, "About N min away" shows.

## 9. Open questions that need client probes

probes.md records the run from 19:27:32. Its batch-2 results (explore, gamerules, ej, questtext, camp, taxi,
questmap, legacy) exist only in the PROBE SavedVariables written at 19:38:41, which is one session on one level-18
shaman. Each of these needs a probe in `forever-probe/probes.lua`:

1. **FutureSpell.** Does the spellbook list `FutureSpell` entries right after a level-up, before training? If it does, the trainer reminder comes back.
2. **Stock quest-offer "!".** Is it present on Forever? That means `QuestOfferDataProvider` and CVar `questPOILocalStory` (`BLZ/Blizzard_WorldMap/Blizzard_WorldMap.lua:208`). If Blizzard already draws givers, delete AGF's giver layer.
3. **Class and race names.** Do `C_CreatureInfo.GetClassInfo` and `GetRaceInfo` return localised names on Forever? These feed "Warriors only"; the fallback is `LOCALIZED_CLASS_NAMES_MALE`.
4. **`-c60` resolution.** Do `C_Texture.GetAtlasInfo("ui-questtracker-tracker-check")` and its `-c60` twin resolve to different files? This decides whether unsuffixed names in inherited templates render the Classic art.
5. **Questlines.** Does `C_QuestLine` (or `C_QuestLog.GetZoneStoryInfo`) return data on Forever? Authoritative chain lengths would replace the conservative `pre`/`next` rule.
6. **Quest cache.** Does `RequestLoadQuestByID` fill `HaveQuestData` on the next session? This only affects titles in search results.
7. **Faction.** Record `UnitFactionGroup("player")` alongside `taxi`, and repeat the probe once at a flight master, to settle §6 beyond one sample.
8. **Tracker fanfare.** Does `SetNeedsFanfare(key)` on an addon module play `AddAnim` when the key equals the block id? Plausible from Module.lua:634 and AnimTemplates.lua:97-100, but it is a UI check, not a headless one.

## Appendix A: judge verdicts

Codex, the designated judge, chose **map**. Its winner decides ties.

| design | pillars | blizzard_look | player_value | feasible | maintenance | yagni | total |
|---|---:|---:|---:|---:|---:|---:|---:|
| journal | 9 | 8 | 8 | 8 | 6 | 5 | 44 |
| **map** | 9 | 8 | 9 | 8 | 6 | 7 | **47** |
| companion | 5 | 9 | 8 | 7 | 8 | 8 | 45 |

The Claude judge, a second opinion, chose **companion**.

| design | pillars | blizzard_look | player_value | feasible | maintenance | yagni | total |
|---|---:|---:|---:|---:|---:|---:|---:|
| companion | 9 | 8 | 8 | 8 | 8 | 8 | 49 |
| journal | 7 | 8 | 8 | 7 | 5 | 5 | 40 |
| map | 6 | 7 | 7 | 6 | 5 | 5 | 36 |

How the verdicts were merged:
- Map's selection model, map budget and waypoint ownership are kept.
- Map's new layers (continent rings, hint ring, dots) and its unreleased-API dependencies are deferred, following Codex's own caveat and the Claude judge's rejection.
- From the companion: the tracker lines, the validated resume line and the fanfare.
- From the journal: conservative chapter totals, withheld titles, `QUEST_TAG_ATLAS` icons, and `Model.Why` extracted from `Eligible`.
