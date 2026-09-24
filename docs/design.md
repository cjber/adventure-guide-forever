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
  The one exception is the card's hub line ("Lakeshire, Redridge and 2 more stops"). The user asked for it, and it
  counts towns, not progress (plan §7.4).
- **A stop is a town.** One stop per hub (plan §7.2) merges its hand-ins and pickups. The route leads to the
  hub's nearest giver, and the stock "!" and "?" marks cover the last yards.
- **Approachable and familiar.** The guide lives in the quest log tab and the objective tracker, both stock frames.
  Quest text is Blizzard's own details page. Leaving the plan is normal: Stop and Skip always work, and the route
  rebuilds from the live quest log.

Two standing rules from AGENTS.md:
- A quest whose eligibility the data cannot establish is never recommended.
- A step never points at coordinates the data does not have.

## 2. Surfaces

All atlases below appear as exact rows in the CSV. AGF always passes the **plain** atlas name, never a `-c60`
name: on Forever `C_Texture.GetAtlasInfo` returns nil for every `-c60` name tried, and the plain name resolves to
the `-c60` art where one exists (probe `c60`, §9). The tracker header and glow are set by Blizzard's templates, not
by AGF.

### 2.1 Quest-log tab "Adventure" (the journal)

The frame is today's `AdventureGuideForeverPanel`, which sits over `QuestMapFrame` at `ContentsAnchor`
(Panel.lua:741-777). Its background is `QuestLog-main-background` (CSV:11182, 307x510). The tab is AGF's own
`LargeSideTabButtonTemplate` (Panel.lua:704) with `islands-queue-prop-compass` (CSV:3202). Camelot hides the stock
tabs (`BLZ/Blizzard_UIPanels_Game/Camelot/QuestMapFrameOverrides.lua:3-6`; PROBE lines 31-40). The list scrolls
inside the existing `ScrollFrameTemplate` (Panel.lua:510).

```
+-----------------------------------------------+  308 px pane (QuestMapFrame.xml:648)
| [Search quests..........................] [*] |  29 px top bar: SearchBoxTemplate across the width
|-----------------------------------------------|    (no step count, §1), settings cog
| +-------------------------------------------+ |  none chosen: every card whole, 288x86, in order
| | (?)  Finish what you carry                | |
| | ( )  3 quests ready to hand in            | |
| +-------------------------------------------+ |
|  ... the story and next-zone cards, likewise   |
|  Choose a journey to see its steps.           |  GameFontDisableSmall hint; nothing guides
|                                               |
|  --- after choosing the story: ---            |
| [(?) Finish what you carry                +] |  the others, one line each: 288x26, 2 px apart
| [(!) Head to Darkshore                    +] |
| +===========================================+ |  the chosen card, whole and lit (its own art),
| | (S)  Westfall story                       | |    4 px under the rows
| | ( )  Chapter 2 of 4                       | |
| +===========================================+ |
|    [#][#][ ][ ]                               |  chapter track (2.3)
|  1 Sentinel Hill, Westfall                    |  step rows, 44 px each, 9 at most; a town is titled by its name
|      2 to hand in, 3 to pick up · 6 min       |    GameFontHighlightSmall: the counts, step 1 adds its minutes
|  2 The Defias Brotherhood                     |
|  3 Red Linen Goods                            |    optional rows at alpha 0.6
|  Skipped (2)                                  |  GameFontNormalSmall text button, hidden at 0
|-----------------------------------------------|
|  The route starts when combat ends  [  Stop  ]  |  40 px footer: GameFontNormalSmall, only while a
|                                               |    choice waits out combat; UIPanelButtonTemplate 90x26
+-----------------------------------------------+
```

- **Removed:**
  - the three 64 px zone-art cards, `SetZoneArt` and the veil / "Best fit" band (Panel.lua:126-178). The map beside the list already shows the zone.
  - the XP bar (Panel.lua:329-356). The stock XP bar already shows this.
  - "Why these?" (Panel.lua:430-443). Each row now gives its own reason, and "why not" moves to search.
- The quest/dungeon chips move into the cog's settings menu. Dungeons holds back only an instance's quests (a quest
  with `dungeon`); an outdoor elite (Hogger) is a zone's quest under Quests, shown optional with the group badge.
  Being optional, it never picks the zone: zones are ranked by their other quests.
- **None chosen** is the default (a fresh character, a card clicked again, or a saved choice whose card is no longer
  offered): every card whole in order, no step rows, the hint "Choose a journey to see its steps." under them, and
  nothing guides. The route still falls back to the first card (`route.chosen` false), but the tracker shows no
  step until a journey is chosen, only its one quiet line (§2.5). A stale saved key stays saved and is chosen again
  should its card come back.
- **One chosen:** the others fold to one-line rows above it, in their order, and it sits whole and lit right over
  its track and step rows. Its steps start at the same place whichever card it is (two rows, 58 px, then the card),
  and no card sits between a card and its steps, which the old order did (a middle card's steps pushed the last card
  below the fold). A row chooses its card; the chosen card is a toggle, and clicking it again chooses none.
  No animation: the quest log's own headers fold at once, and a height tween would need an OnUpdate.
- **Choosing starts the route.** Selecting a card (whole or a row) sets `prefs.journey`, rebuilds the route and, on
  the rebuild that has its steps, hands them to `Integrations.Navigate`: SPF's journey, or the native waypoint
  without it. There is no Go button: choosing is already the commitment, and a second click to start the same route
  was a step with no decision in it. Without SPF the waypoint is placed too, since Stop and clearing the choice still
  clear only a waypoint where AGF put it. Clicking the chosen card again chooses none and stops AGF's route (never
  anyone else's), so the lit card and the guidance never disagree.
- The setting "Choosing a journey starts the route" (key `titleStartsRoute`, default on, kept from when it covered
  only the tracker title) governs both the card and the tracker title: one preference for "a pick starts guidance",
  and a player who turned the title click off keeps that choice here. Off, a card only chooses and clearing it stops
  nothing; the step row menu's and the tracker menu's Go still start the route.
- **In combat** a choice still chooses at once. SPF refuses every route in combat, so the start waits for the
  rebuild `PLAYER_REGEN_ENABLED` brings (Core's combat deferral, no OnUpdate), and the footer reads "The route starts
  when combat ends" meanwhile, so the wait reads as queued, not failed. Clearing the choice first cancels it.
- **Stop** appears only while AGF owns the guidance. That means SPF's `CurrentStop(OWNER)` is non-nil, or the
  native user waypoint is still the one AGF set (§5.1).
- **Honest coverage (roadmap #23).** When the log holds a quest `Data.quests` lacks, or the player's zone map has quests
  Forever added that it lacks and the player hasn't finished, one `GameFontDisableSmall` line sits under the cards and
  hint, above Skipped: "This land has stories the guide doesn't know yet; look for the "!" over quest givers." It points
  at the giver's own mark, since Forever draws no givers on the map (§9 `questoffer`). It is never on a card (§2.2) and
  never beside the search's results. `Model.Unlisted` decides. The added quests come from `Data/Forever.lua`, which
  `tools/diff_forever.py` generates: the QuestV2 IDs Forever's build has and Classic Era 1.15.9.69722 lacks, each placed
  on the zone maps its `QuestPOIBlob` rows name. Only 26 of the 1795 added quests have a blob, so the zone half is
  narrow; a quest with no blob has no zone and is left out. The slice also lists the 160 added AreaTable IDs for later
  exploration work; TaxiNodes and Map diffs are printed only.
- Fit: with a card chosen the three cards take 148 px (was 270), so the list holds between two and three more 46 px
  step rows before it scrolls.

### 2.2 Journey card

The card copies `RenownCardButtonTemplate` (`BLZ/Blizzard_EncounterJournal/Mainline/Blizzard_Journeys.xml:5-107`)
at 0.77 scale. It is copied, not inherited: the Encounter Journal is not loaded on Forever (PROBE `ej`,
lines 367-380: `addonLoaded` false, `EncounterJournal` false, `numTiers` 0).

```
+------------------------------------------+  NormalTexture ui-journeys-renown-button (CSV:15677, 374x112 -> 288x86)
|  .--.                                    |  selected: the same art, highlight locked (never the -pressed art)
| ( S  )  Westfall story                   |  title: GameFontNormalMed2 (gold), LEFT of IconFrame RIGHT +5,+5 (xml:90-95)
|  '--'   Chapter 2 of 4            6 min  |  subline: GameFontHighlightSmall (white) under the title;
|         Continues a story you started [g]|    minutes right-aligned; reason, else the hub line; [g] group
+------------------------------------------+
  IconFrame 46x46 at LEFT x=15 (Blizzard 60x60 at x=20, xml:24-28); border ui-journeys-renown-radial-bar (CSV:16221)
  Icon 18x18 at CENTER; hover inherits AlphaHighlightButtonTemplate (SharedUIPanelTemplates.xml:1587)
```

- **One-line row** (another card is chosen): the Settings list's collapsible category header in three slices at its
  own 26 px height, `options_listexpand_left` (12x26), `_options_listexpand_middle` (tiled) and
  `options_listexpand_right` (28x26, its "+"), 288x26 in all, with the 16x16 kind icon at LEFT x=12 and no ring, and
  the title (GameFontNormalMed2) at the icon's RIGHT +6. Its tooltip has the title, subline and reason, so nothing is
  lost. The chosen card's tooltip says "Click again to see every journey". Pooled: the three card buttons are
  resized in place, no frame is made per refresh.
  - Why this art: it is a stock single-line row drawn at native height with a "+" that says it opens; the renown
    card squeezed to 28 px pinched its frame, `friendslist-categorybutton` read as a second heavy card and
    `collections-slotheader` too faint to read as a button.
- **Chosen card:** the card's own `ui-journeys-renown-button` with its highlight locked, never
  `ui-journeys-renown-button-pressed`, which is drawn a few pixels off true; its pushed art is the same atlas, so
  neither a press nor the choice moves any art, text or icon.
- **Kind icons** follow Blizzard's `QUEST_TAG_ATLAS` (`BLZ/Blizzard_FrameXMLBase/Constants.lua:514-527`):

  | Card kind | Icon | Mock label |
  |---|---|---|
  | Hand-ins ("Finish what you carry") | `questlog-questtypeicon-quest` (CSV:9396) | `(?)` |
  | Zone story | `questlog-questtypeicon-story` (CSV:9400) | `(S)` |
  | Next zone | `QuestNormal` (CSV:1360), the same "!" the map uses | `(!)` |
  | Dungeon | `questlog-questtypeicon-dungeon` (CSV:9387) | `(D)` |
  | Your calling | `questlog-questtypeicon-class` (CSV:9385), the same sheet's class icon | `(C)` |
  | Group quest (elite) | `questlog-questtypeicon-group` (CSV:9388) | — |

- **Card detail (batch F, plan §7.4).** No new line and no new art:
  - **Travel.** Line 2's right edge shows the minutes from the player to the journey's first stop: "6 min", or "15
    min by boat" when a crossing leg exists and it fits. The subline truncates first.
  - **Fetching.** The minutes are fetched only while the tab is shown and out of combat, one Shortest Path
    estimate per frame. They are never fetched in the rebuild. Without SPF, or with no answer, the minutes are
    left out.
  - **Line 3.** It shows the journey's reason, or else the hub line: "Lakeshire, Redridge and 2 more stops".
  - **Reason (roadmap #3).** A zone card (story or next zone) takes one reason in the world's voice, the first that
    applies: "Continues a story you started"; "3 quests will soon turn grey" (two or more of its pickups grey at the
    next level, never at the level cap); "A chain begins with Gryan Stoutmantle" (the chain's lead giver); "Sentinel
    Hill needs hands" (the first quest stop's town, past a trainer's stop, has a flight-master name, cut before its
    ", zone", and 3 or more pickups). Otherwise the plain line: "Begins a new story", "For level N", or none. Only
    names the data has; the chapter's row keeps "Begins a new story" or "Continues a story you started".
  - **Group badge.** A 12x12 `questlog-questtypeicon-group` sits at line 3's right edge when any quest needs a
    group. Dungeon cards, whose kind icon says so already, do not get it.
  - **Tooltip.** Whole cards now have one as well (§2.9).
- **Fonts.** Blizzard sets the name in white `GameFontHighlightMed2` over a gold `GameFontNormalMed2` subline. AGF deliberately reverses this, to follow the house rule of a gold header over white body text.
- **What a card may offer.** A card only ever holds eligible, recommendable steps. It never shows a lock, never shows "opens at level N", and never marks something new-in-Forever or of unknown location (§2.13's mark says new to the character). Locked quests appear only in search (§2.4).
- **Card kinds** (three at most, only those that have steps). Carry and the story keep their fixed slots; the
  diversions share what is left (roadmap R4):
  1. **Finish what you carry**: log turn-ins and objectives.
  2. **The zone story**: the best eligible chain in the zone the player's level fits best.
  3. **Diversions**, newest first:
     - **Your calling** (roadmap #7): the class quests the player can take now, as one card: a `classes` mask of the
       player's class alone (Vile Familiars, every Horde class's but the warlock's, is a starting quest), never a
       raid's. It leads with a chain as the story does (§2.3), else the lowest quest ID. Its reason names that quest:
       "Your class trainer has a task: Call of Earth" only when the data proves its giver trains the player's class
       (`start.trainer`, from CMaNGOS TrainerClass), else "A task for your class: Call of Earth".
     - **Dungeon** (Dungeons on): the party instance with the most quests open now.
     - **Next zone**: the zone that ranks first for `level + 2` in the same eligibility pass (`Choices` in
       `Model.Journeys`), shown only when it differs from the story's zone and the player's own and has at least 5
       quests to take now.
- **Which diversion.** Each is ranked by the level its newest quest opened at (the highest `min` among its quests
  open now), highest first, so a level just gained or a bracket just opened takes the slot and an older one yields
  as the player levels on. A tie goes calling, dungeon, next zone. It is stateless: nothing is remembered between
  sessions. Only as many are built as there are free slots, plus the chosen one, which always keeps its slot.

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
- **Headings.** Stories are named after the zone ("Westfall story"). The data has no questline names, and AGF never invents one.

### 2.4 Why-not view (search)

Typing 3 or more characters in the search box replaces the cards with up to 10 matching quests for the
player's side. Eligible matches show as normal rows. Ineligible matches show why:

```
+-----------------------------------------------+
| [red linen.................]                  |
|  [L] Red Linen Goods             Westfall     |  questlog-questtypeicon-lock (CSV:9393) 18x18, GameFontNormal
|      Requires level 14                        |  unmet: GameFontHighlightSmall in RED_FONT_COLOR
|      [v] Completed: The Forgotten Heirloom    |  met: |A:ui-questtracker-tracker-check:12:12|a (CSV:10177), GRAY_FONT_COLOR
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
  - `skill` ("Requires Tailoring 150") and `rep` ("Requires Friendly with Timbermaw Hold", "Only while below
    Revered with Argent Dawn"; "Depends on your standing with X" when the value falls between ranks), in the
    client's names for the skill line, faction and standing (`FACTION_STANDING_LABEL1-8`) when it has them;
  - the other reasons `Eligible` returns false: completed ("You've done this"), in the log ("In your quest log"),
    repeatable ("Repeatable quests aren't suggested").
- **Skill and reputation gates (roadmap #8).** The generator keeps the start of a quest gated only by CMaNGOS
  RequiredSkill/Value or RequiredMin/MaxRep (141 more starts at the pin) and emits `skill = {id, value}` and
  `rep = {faction, min, max}`, checked as `Player::SatisfyQuestSkill` and `SatisfyQuestReputation` do: rank at least
  `value`; reputation at least `min` and below `max`. A skill value of 0 asks nothing. CMaNGOS reputation is base
  plus earned, 0 at the start of Neutral (3000 Friendly, 42000 Exalted), the same scale as the client's
  `FactionData.currentStanding` (the stock reputation bar subtracts `currentReactionThreshold` from it). A gate on
  a weapon skill, a faction with no reputation, or two factions stays suppressed. At runtime State reads ranks from
  `C_SkillInfo` (the global `GetSkillLineInfo` is missing on Forever; an unlearned line is rank 0) again on
  `SKILL_LINES_CHANGED`, and standings from `C_Reputation.GetFactionDataByID`; a faction it gives none for (the
  other side's) meets neither bound. `UPDATE_FACTION` or `SKILL_LINES_CHANGED` rebuilds only when a rank or
  standing a gate names moved, not on every weapon skill-up or reputation kill.
- **Not covered.** Quests whose start the generator suppressed (gen_quests.py `generate`) get only the "can't
  tell" line.
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

   Lakeshire, Redridge                          a hub stop (plan §7.4): header = hub name
   - 2 to hand in, 4 to pick up                 counts
   - Marshal Marris, Verner Osgood and 2 more   givers, at most 2 names; a real reason replaces it
   - Fly to Lakeshire · 6 min                   travel
```

- **One quiet line first.** The aside (§2.11) when there is one, as a block whose header is its whole line.
- **No journey chosen.** The tracker shows that one line and nothing else: the aside, else the top story's hook
  ("Westfall story · Begins a new story": the first story card's title, then its reason or subline; the
  first card when no story is offered). Its click chooses that journey as its card does, starting the route with
  "Choosing a journey starts the route"; right-click is the tracker menu. The step block, with its "Next:" line,
  appears only once a journey is chosen, and a fanfare header sits under the line.
- **Something new** (§2.13): "Duskwood is now for your level" sits under the quiet line, glowing once, until the
  guide opens.
- **Place line.** A stop with one giver reads "NPC, zone". The zone name comes from the client by map ID, with the
  data's name as the fallback. A turn-in placed by `GetNextWaypoint` uses the data's finish NPC only when that NPC
  is within the hub; otherwise it shows the zone alone.
- **Order.** Only this section and the panel are ordered by AGF. The stock quest tracker's order is never touched,
  because Tweaks Forever's "Nearest quests first" owns it.

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
  - With "Clicking the tracker title tracks the route's quests" (`trackRouteQuests`, **off** by default since
    roadmap #17; a saved on stays on), the left-click also puts the route's log quests on the stock tracker.
  - Right-click: the menu (§2.8).

### 2.6 Map pins and route preview

**Map budget.** A headless spec asserts all of this:

| Layer | Max | Shown when |
|---|---|---|
| Numbered route rings | 9 (`MAX_STEPS`, Model.lua:5), only the selected journey's, only on its zone map | the Adventure tab is open (preview), **or** `showMapPins` is on |
| Quest-giver "!" | the zone's eligible, non-gray givers | `showMapPins` **and** `showQuestGivers` are both on; both default **off**. Kept because Blizzard draws no givers on Forever (probe `questoffer`, §9) |
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

- **Preview.** With no card chosen the open guide previews no rings: rings numbered for a card that is not lit
  would read as a choice made (with `showMapPins` on they still show the first card's route, as the tracker does).
  Selecting a card turns the map to that journey's first zone (`WorldMapFrame:SetMapID`) and draws
  only its rings. Hovering a step row flashes its ring (`Pins.Ping`, Pins.lua:184-188).
- **Layering.** A route ring marks "your destination", so it takes the stock level of the user-waypoint pin,
  `PIN_FRAME_LEVEL_WAYPOINT_LOCATION`. That is above every quest "!" and "?", including the super-tracked one.
  AGF's preview ring uses this level, and SPF's stop ring does too (plan §7.9). Givers stay at `AREA_POI`, below
  the stock marks. A faded later stop fades its ring and number, not its disc, so a POI never shows through.
- **One ring per town.** A hub is one stop (plan §7.2), so a town no longer piles several rings into one.
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

Step skips stay session-only. The menu has no auto-go.

**Not interested (roadmap #17).** A journey card's right-click (not the carry card's: what the player carries is
theirs) opens its title and "Not interested". That saves `charDB.notInterested[key] = title` for this character, so
the card stays gone across sessions; the planner offers the next best zone or dungeon in its place, and a choice of it
ends as a click on its card would. "Skipped (n)" (under the cards, in the step menu and in the cog) counts these after
the session's step skips and offers each back with "Show again: <title>". The card's tooltip ends with "Right-click if
you're not interested".

### 2.9 Tooltips

Tooltips use Blizzard's voice through the helpers in `BLZ/Blizzard_SharedXML/SharedTooltipTemplates.lua`
(SetTitle :128, AddNormalLine :142, AddHighlightLine :150, AddInstructionLine :154). They anchor `ANCHOR_RIGHT`,
as today (Pins.lua).

```
Map ring / step row                         Journey card
+--------------------------------------+    +--------------------------------------+
| 2. The Defias Brotherhood            |    | Westfall story                       |  SetTitle (gold)
| Chapter 2 of 4                       |    | Chapter 2 of 4                       |  AddNormalLine (gold)
| Fly to Sentinel Hill · 6 min         |    | Continues a story you started        |  AddHighlightLine (white)
| Continues a story you started        |    | Sentinel Hill and 2 more stops       |  AddHighlightLine (hub line)
|                                      |    | Fly to Sentinel Hill · 6 min         |  AddHighlightLine (travel)
|                                      |    | 1 needs a group                      |  AddHighlightLine
| Click to travel with Shortest Path   |    | Click to choose this journey         |  AddInstructionLine (green)
+--------------------------------------+    +--------------------------------------+

Hub stop (row and ring)
+--------------------------------------+
| 3. Lakeshire, Redridge               |  SetTitle
| Fly to Lakeshire · 6 min             |  AddHighlightLine (travel, on hover)
| Marshal Marris                       |  AddNormalLine per giver
| (?) Solomon's Law                    |  AddHighlightLine per quest, questturnin / questnormal icon,
| (!) [18] Redridge Goulash            |    coloured by GetQuestDifficultyColor; group icon suffix
| And 3 more                           |  after 8 quest lines
| Click to travel with Shortest Path   |  AddInstructionLine
+--------------------------------------+
```

The journey card tooltip now shows on whole cards and on one-line rows. Its "5 steps" line became the hub line,
which counts towns, not steps (§1).

When `SPF.Active()` exists and reports another journey running, every way to start the route warns with "Replaces
your current journey.": a card or row another click would choose (while choosing starts the route), the menus' Go
and the tracker title. The chosen card's tooltip, while AGF's route runs, reads "Click again to stop the route and
see every journey"; while it is paused (§2.10), "Click to resume the route", with the warning when another journey
runs.

**NPC line (roadmap #19, `Tooltip.lua`).** While a journey is chosen, hovering an NPC its steps visit adds one
`AddNormalLine` to the unit tooltip: "Adventure guide: <journey title>". The NPCs are a town stop's givers and enders
(its spots) and a turn-in's finish NPC, matched by the creature entry in `UnitGUID` against the places' `npc` (the
generator's creature entry; an object giver has none). An objective or dungeon step visits no NPC. The set is
gathered on each route change, so a hover only reads; the line comes from a `TooltipDataProcessor` post call, in
combat too, and touches no secure frame. With no journey chosen, and for every other unit, nothing is added.

### 2.10 A journey's lifecycle

A **choice** (`prefs.journey`, one card) is kept apart from **guidance** (`prefs.guided`, the key of the chosen
journey whose route AGF started). Choosing, starting and ending all live in Core (`ns.Choose`, `ns.StartRoute`), so
the cards, the tracker title, the menus and the map's rings behave the same, with the guide open or closed.

Keys: `carry`, `zone:<map>` for a zone's story and its next-zone card alike (so heading to a zone becomes its story
on arrival), `dungeon:<instance>`, and `calling`. `LoadCharDB` migrates the old `story:` and `nextzone:` keys once.

Invariants:

1. **Offer rules only gate new choices.** A chosen journey is built while it has a step, whatever would offer it
   now, and keeps its slot when a new card pushes one out.
2. **The story is the zone you stand in** when it fits (top 3 now, or two levels on), when your level is within its
   range and it has a quest open now that is not an outdoor elite (a zone whose quests you have mostly taken up ranks
   low, yet is still where you are adventuring), or when it is the chosen zone.
3. **Only a chosen journey is guided.** The tracker shows a step only for a chosen journey; with none, its hook line
   chooses one (§2.5).
4. **Guidance follows the journey.** On each rebuild and on the frame after Shortest Path's super-tracking events,
   `Integrations.Stale` sends the route again, once, when a stop it has yet to reach left the steps, step 1 is neither
   the stop it heads for nor the one just reached, or step 1's point moved more than 100 yd (the town linkage).
   Never in combat, on a taxi or off the map. Without Shortest Path the waypoint moves to step 1 instead, quietly.
5. **Nothing starts on its own,** except the restore after a `/reload` or login (once, on the first full build out
   of combat, never over someone else's journey) and the extension of a route that arrived to steps it never had.
   While the player stands in step 1's town (within 100 yd of any of its quests' places) with steps after it,
   Shortest Path is handed the town alone: it arrives there and draws no way out of town before its quests are
   taken, and the route goes on once the town is done or the player walks out.
6. **Losing something is never silent.** A turn-in that ends the chosen journey glows "Journey complete" in the
   tracker; a route that stopped says "Route paused" in the footer.
7. **Endings are judged on full builds only,** out of combat, once the completed quests have loaded.

Guidance states:

| State | Test | Card click | Footer |
|---|---|---|---|
| Idle | nothing of ours | chooses | |
| Pending | a start waits for combat | clears the choice | "The route starts when combat ends" |
| Guiding | `CurrentStop` and `Active()` | stops it and clears the choice | Stop |
| Held | `CurrentStop`, `Active()` false ("Guide me" off) | stops it and clears the choice; the rings come back | Stop |
| Paused | chosen, `guided` (or cleared or replaced), no route | resumes it (so does the tracker title) | "Route paused. Click the journey to resume." |
| Arrived | ended at its last stop | clears the choice | |

Stop, in the footer or a step's menu, does what a click on the guided card does: the route stops and the choice
clears, so no journey is left chosen with nothing to resume it.

An end is classified by Shortest Path's `API.Ended(owner)` when present ("arrived", "cleared", "replaced",
"cancelled"). Without it: another journey running means replaced, standing within 100 yd of the last stop means
arrived, and anything else means cleared. Arrived keeps `guided`; cleared and replaced forget it, so nothing sends
the route again until the card resumes it.

A chosen journey the full build no longer has ends: its route is cancelled and the choice cleared, so the cards are
whole again. A Quests or Dungeons filter keeps the key (the player's own toggle can bring it back) but stops the
route; Quests covers `zone:` keys and `calling`, Dungeons `dungeon:` keys. Skipping every step of a chosen journey ends it the same way, quietly.

### 2.11 Asides

An aside is a one-line hint beside the journeys, never a route: `Asides.lua`, after `Integrations.lua` in the TOC.
Each domain registers a provider returning at most one `{key, text, icon, place?}`: `icon` an atlas the CSV has,
`place` only a place from the data. Providers are asked in step 1's travel frame after each rebuild
(Core), never in a rebuild's frame and never in combat, when the last answers stand; views redraw only when the
aside shown changes. The first provider's answer the player has not skipped or turned down is the aside.

- **Two surfaces at most.** One line above the cards (icon, `GameFontNormal` text, a row's `common-icon-redx`
  skip), hidden while searching, and the tracker's line (§2.5). Both show the same aside.
- **Skip for now** hides it for the session: the line's red X, or its menu. **Not interested** hides it for the
  character (`charDB.asides[key]` = its text); the cog's "Skipped (n)" submenu, shared with skipped journeys, offers each back as
  "Show again: <text>", its provider's text now when it still answers, else the saved one.
- **Clicks.** Right-click on either line is its menu (Go with a place, Skip for now, Not interested). Left-click goes
  to its place, as a step's Go does (§5.1), and does nothing without one.
- **Providers.** The class trainer (F16): "Visit your class trainer in Stormwind · 3 new spells" with the minimap's
  `class` mark (CSV:1321), from Tweaks Forever's `TrainableSpells`, asked again on `SPELLS_CHANGED`. Its place is the
  nearest trainer who teaches the spells (§2.12); without one (a class and side the data has no trainer for, or no
  place for the player) it is text only: "Visit your class trainer · 3 new spells".

### 2.12 Trainers (roadmap R3, #5)

- **Who teaches.** A `Data.npcs` class trainer of the player's class and side whose list starts at level 1 (no
  `from`: a mage's portal trainer teaches only portals) and reaches the highest level among Tweaks Forever's spells
  to train (`upto`: a starting-area trainer stops at 6). CMaNGOS lists no Forever-only trainer, so a class and side it
  has none for (a Horde paladin) stays text only. `Model.Trainer` takes the nearest by the route's cost (§4.1).
- **Town name.** The hub's flight-master town before ", zone"; a town with none (Razor Hill, Goldshire) takes the
  zone's name from the client, since no proper source names it.
- **A stop on the chosen route.** Only while a journey is chosen and there are spells to train. The candidates are
  one step per town (`kind = "trainer"`, key `trainer:<npc>`, no quests), and Build opens one only after it has
  chosen a stop in the trainer's hub or within 100 yards of it (the town linkage), and one at most: the route never
  detours to train. Its title is "Train in <town>", its reason "3 new spells", its place line "NPC, zone". It is worth a
  hand-in in selection (never weak), is never a hand-in-only stop, and survives combat's cheap rebuild. Core asks
  Tweaks Forever at the full rebuild only while a journey is chosen, and rebuilds on `SPELLS_CHANGED` when the answer
  moved, so a spell learned ends the stop.
- **Not built.** Hunter pet trainers: no signal says a pet has something to learn (Tweaks Forever's list is the
  player's spells). "You can learn to ride" (#20): at the pinned build SpellLevels gives Apprentice Riding (33388)
  BaseLevel and SpellLevel 0, and SkillLineAbility (line 762) and SkillRaceClassInfo no level, so the data cannot
  say when it opens; the riding trainers CMaNGOS has teach the old per-race mounts, not 33388.

### 2.13 Something new

After a level gained or a zone entered (`PLAYER_LEVEL_UP`, `ZONE_CHANGED_NEW_AREA`), a journey card or an aside the
character has never been offered is announced once, quietly: `Moments.lua`, after `Asides.lua` in the TOC.

- **The seen set.** `charDB.seen` holds every journey key the character has been offered (never `carry`), and
  `aside:<key>` while a provider gives that aside; one that stops being given leaves (checked on every change of the
  aside shown too, since training every spell brings no rebuild), so the trainer's next spells are new again. Step 1's travel frame after each rebuild, once the asides have answered, adds what is offered now; out of
  combat, and only once the completed quests have loaded.
- **When it compares.** Only on the first such look after the rebuild a level or a zone brings, and never against an
  empty set: the session's first look, a new character and a save file the client never loaded (#34) all learn
  silently, so nothing floods.
- **What it shows.** A new journey: the tracker line "Duskwood is now for your level" (the zone's client name, a
  dungeon's card title) under the quiet line, glowing once as §2.7's fanfare does, with no sound; its click opens the
  guide. A new aside: its own tracker line glows. Either way `adventureguide-microbutton-alert` (CSV:2025) pips the
  Adventure tab and the addon compartment's button, and a new card carries `adventureguide-icon-whatsnew` (CSV:2024)
  over its ring's top-right (beside the "+" on a one-line row). No toast; nothing opens by itself; the tracker section
  off leaves the pips and marks.
- **Clearing.** Opening the guide clears the pips and the tracker line; the marks stay while it shows and go when it
  closes. Found with the guide already open, only the marks show. Pips and marks last the session only.

### 2.14 QuestieDB as the quest source

`QuestieSource.lua`, after `Integrations.lua` in the TOC; QuestieDB is an `## OptionalDeps`. After `PLAYER_LOGIN` it
checks the installed QuestieDB (contract 2 through `RequireContract`, `X-Flavor` Forever, every field it reads in
`Meta.*Meta.*Keys`, ZoneDB's zone tables) and rebuilds the bundled data's quests from it in 2 ms slices, one a frame;
then `ns.Data` is swapped and `ns.Invalidate()` rebuilds the route. Nothing may hold `ns.Data` past a call (the one
cache that did, Integrations' town places, is keyed on it).

- **From QuestieDB:** title, levels, races, classes, zone (area to parent zone to uiMap), each start and finish from its
  NPCs' and objects' spawns (quest zone first, then the giver's usual map), prerequisites, exclusive quests (merged
  into one group per connected set), chain, repeatable, skill and reputation gates.
- **Still bundled:** zones, maps, continents, crossings, towns (a place joins the nearest bundled town place within
  100 yd), hub names, NPC roles, instances and elite; and what QuestieDB leaves out: a level of -1 (it scales), a
  missing minimum level, a dungeon it files outside an instance, and the place of a giver none of whose spawns it
  places when the bundled data names the same NPC.
- **Withheld start:** any quest the bundled data lacks, or whose bundled start it withholds (nothing says what else
  gates it: the generator's Method, condition and event gates, and givers CMaNGOS spawns only for an event, which
  QuestieDB lists as ordinary spawns); a prerequisite or exclusive quest outside the data; and `parentQuest`, `breadcrumbForQuestId`, `requiredSpell`, `requiredSpecialization`,
  `requiredMaxLevel` below the cap, `availableUntilCompleted`, `availableStartingWith`, `requiredRanks`,
  `disabledByQuest`, flags 1024 or 16384, or a gate on a skill line or faction the data doesn't name.
- **Fallback:** any failed check or read keeps the bundled data; `/agf audit` names the source and the reason.
  Questie and QuestieDB carry no licence, so the repo, specs and goldens hold none of their code, types or data; the
  specs use a synthetic stand-in, mostly a mirror of the bundled data (`harness.questieMirror`).

## 3. Copy style sheet

- Sentence case. No exclamation marks. Digits for numbers. "·" as the separator.
- The world is the subject where possible ("Sentinel Hill needs hands"), not the player.
- Gold header (`GameFontNormal*`, `NORMAL_FONT_COLOR`) over white body (`GameFontHighlight*`). Detail lines use
  `GameFontHighlightSmall`; dimmed lines use `GameFontDisableSmall`. The tracker keeps its stock colours.
- Never write "%", "XP", "XP/hour", "fast", "fastest", "optimal", "you must", or "?" as a value. If a value is
  unknown, the line is left out.
- Travel verbs match SPF's `VERB` table (shortest-path-forever `Journey.lua:11-20`: "Fly to", "Boat to", …), so
  AGF and SPF speak with one voice.
- All strings live in one `L` table in Core.lua.
- Names the game already localises come from the game: zone names from `C_Map.GetMapInfo(uiMapID).name`, quest
  titles from `C_QuestLog.GetTitleForQuestID(questID)`, class and race names from `C_CreatureInfo.GetClassInfo` /
  `GetRaceInfo` (probe `classnames`). The data's English name or title is only the fallback when the client
  returns nothing (an uncached quest, a headless spec).

| Where | Example |
|---|---|
| Card titles | `Finish what you carry` · `Westfall story` · `Head to Darkshore` · `Your calling` |
| Card sublines | `3 quests ready to hand in` · `Chapter 2 of 4` · `Chapter 2` · `11 quests near your level` · `2 quests for your class` |
| Reasons | `Your class trainer has a task: Call of Earth` · `A task for your class: Call of Earth` · `Continues a story you started` · `3 quests will soon turn grey` · `A chain begins with Gryan Stoutmantle` · `Sentinel Hill needs hands` · `Begins a new story` · `Ready to hand in` · `For level 14` · `Opens the next chapter here` |
| Card line 3, tooltip | `Lakeshire, Redridge and 2 more stops` · `Lakeshire, Redridge and 1 more stop` · `1 needs a group` · `3 need a group` |
| Hub stops | `Lakeshire, Redridge` · `2 to hand in, 4 to pick up` · `Marshal Marris, Verner Osgood and 2 more` · `Guard Parker, Redridge Mountains` · `And 3 more` |
| Travel | `Fly to Sentinel Hill · 6 min` · `Boat to Auberdine · 2 min wait` · `Fly to Astranaar · new flight path` · `About 4 min away` · card: `6 min` · `15 min by boat` · `15 min by zeppelin` |
| Why-not | `Requires level 14` · `Completed: The Forgotten Heirloom` · `Requires one of: A, B` · `Horde only` · `Warriors only` · `You chose X instead` · `The guide can't tell where this starts` · `You've done this` · `In your quest log` · `Repeatable quests aren't suggested` |
| Tracker | `Where you left off: finishes a story` · `Next: The Ruins of Stardust` · `Story complete` · `Westfall story · Begins a new story` |
| Asides | `Visit your class trainer in Stormwind · 3 new spells` · `Visit your class trainer · 3 new spells` |
| Trainer stop | `Train in Stormwind` · `3 new spells` · `1 new spell` |
| Buttons, menu | `Go` (menus only) · `Stop` · `Show quest` · `Skip for now` · `Not interested` · `Skipped (2)` · `Show again: <title>` · `Choose another journey` |
| Instructions | `Click to travel with Shortest Path` · `Click to set a waypoint` · `Click to choose this journey` · `Replaces your current journey.` |
| Empty | `Nothing nearby fits your level.` |
| Coverage | `This land has stories the guide doesn't know yet; look for the "!" over quest givers.` |

## 4. Features, in build order

| # | Feature | Tier | Reason |
|---|---|---|---|
| 1 | Map budget: one `showMapPins` switch, off by default, over every layer; givers move under it and default off; spec-tested caps | Must | Map clutter is players' top complaint (games.md pain point 1: Questie #6916, Reddit 1s12dc2). Today the giver "!" draws even with pins off (Pins.lua:83-86). This change needs no new art. |
| 2 | Journey cards, at most 3, replacing zone cards, XP bar and "Why these?" | Must | A few choices, each with a reason (pain points 2 and 8). Uses three stock card atlases, and the EJ is not required. |
| 3 | Choosing a journey starts it (a setting, default on), with the rings preview while the tab is open | Must | One click from a choice to the road; the player who wants to look first turns the setting off, and nothing replaces someone else's journey without a warning (pain point 2). |
| 4 | Zone stories: `Model.Story` from `pre` and `next`, conservative totals, later titles withheld | Must | Wires the unread `next` (1604 quests, agf.md). Stories, not errands. |
| 5 | `Model.Why` extracted from `Eligible`, plus search-as-why-not | Must | Answers "Am I even eligible?" (Reddit 1wjxhx9), and cannot drift from the planner. |
| 6 | Row or tracker click opens Blizzard quest details (log quests, out of combat) | Must | Quest text stays Blizzard's (pain point 6). Low cost. |
| 7 | Stop with waypoint ownership, plus Skip and "Show again" | Must | Leaving the plan is first-class (RXP #246, Guidelime #107). Wires the uncalled `Integrations.Cancel` (Integrations.lua:67-76), which today clears *any* user waypoint (line 74). |
| 8 | Tracker lines: place, reason, travel, next; resume line validated against live step 1 | Must | The frame players already watch, one line per job. The resume line answers "what was I doing?" without keeping a step index. |
| 9 | YAGNI and contract sweep (see list below the table) | Must | The brief's wired-or-deleted rule. |
| 10 | Travel line from SPF `EstimateDetail` | Should | Honest cost of a choice. Blocked until SPF ships it; `Estimate` covers the gap. |
| 11 | Chapter-end fanfare in the tracker | Should | A small, finite reward. Needs `/reload` validation first. |
| 12 | Continent-aware ordering: one numeric cost, selection by it, nearest-neighbour plus 2-opt over ≤9 stops, at most one continent crossing (§4.1) | **Must** | Today every turn-in comes before any pickup, however far away (agf.md): the `ne21_crosszone` golden puts a Stormwind turn-in between Kalimdor steps, and SPF then draws a straight line across the ocean. |
| 13 | SPF `Active()`: Go warns before replacing the player's own journey | Should | Respects a journey the player chose. |
| 14 | Zones 2521 Zephras Isle and 2548 Riverglades in `gen_quests.py` (TF has them, siblings.md §4) | Should | Forever-only zones currently get no range. |
| 15 | One `L` table for all copy | Should | Localisation groundwork. The strings are inline English today. |
| 16 | "New in Forever" tag (`adventureguide-icon-whatsnew`, CSV:2024) on quests already in the log only | Could | Needs the generator to emit the IDs missing from CMaNGOS (count unverified). Never on cards or recommendations. |
| 17 | Dungeon card | Could | Blocked: `dungeon` is set on 0 quests (agf.md) and the EJ is absent (PROBE). Needs a generator fix plus a TF `DungeonEntrance` API. |
| 18 | Discovery hint: one unexplored area named as text | Could | Needs a LegacyForever API that does not exist. Text only, never a ring. |
| 19 | "Visit your class trainer" step from Tweaks Forever's `TrainableSpells` (§5.2), feature-detected | Should | The client lists no `FutureSpell` entries (probe `spellbook2`), so only Tweaks Forever's trainer data can tell. The aside goes to the nearest trainer who teaches the spells, and a chosen route may stop to train in a town it passes (§2.12). |
| 20 | Hubs: one stop per town, named from flight masters (plan §7.2) | Must | A Redridge route spent 4 of 9 steps in Lakeshire, and their rings merged into one. |
| 21 | Level-aware selection and in-stop order for carried quests (plan §7.3) | Must | The user asked for quests picked up to be ordered by level distance. Travel still orders the route. |
| 22 | Card minutes, hub line, group badge, and tooltips on whole cards (plan §7.4) | Should | The honest cost of a choice at a glance, with no percentages. |
| 23 | Route rings above quest POIs (SPF and AGF, §2.6) | Must | A merged stop ring drew under the super-tracked "?". |

**NPC roles (`Data.npcs`, roadmap R2).** The generator emits class trainers (with the class, and `upto`, the highest
level they teach, so a starting-area trainer is told apart, and `from`, the lowest, when above 1, so a trainer of
only part of the class's spells, a mage's portal trainer, is too), hunter pet trainers, riding trainers (with
CMaNGOS's TrainerRace), profession trainers (skill line and each rank taught: the SKILL_STEP effect of a
taught spell in wago SpellEffect, on a SkillLine profession or secondary skill; a Journeyman-only trainer teaches no
Apprentice), battlemasters (`battlemaster_entry`) and innkeepers, from the pinned CMaNGOS dump. `Data.professions`
gives each line those trainers teach its name, whether it is a secondary skill, and each taught rank's `npc_trainer`
reqlevel and reqskillvalue (the most any trainer asks).
The side is every side the FactionTemplate's EnemyGroup is not hostile to. The place is a non-seasonal spawn
projected as a quest giver's is. Within 100 yards of a quest place it takes that place's hub and the map most of
the hub's quest places use, since zone rectangles overhang (Astranaar is Ashenvale, not Stonetalon); elsewhere it
takes the smallest map the quests use. NPCs never renumber or merge towns. An NPC with no side or no zone-map spawn is left out.

### 4.1 Route ordering (#12)

- **One cost, in yards.** Every place is placed in one frame: its map's world rectangle, then its continent's
  rectangle on the Azeroth map (UiMap 947's `UiMapAssignment` rows), both generated from wago. On one continent the
  cost is the straight distance. Across an ocean it is a large fixed crossing penalty plus the distance to the
  departure dock and from the landing dock, over the cheapest boat or zeppelin the player's side takes, so the route
  enters the far continent at the step nearest where it lands (Auberdine, not southern Darkshore). The docks are
  `Data.crossings`: each transport's two TaxiPathNode stops, its side from the flight masters by each dock, both
  generated from wago. SPF v1 has no arrival point to ask for (`EstimateDetail` is a proposal), and the rebuild
  never calls SPF anyway. With no crossing for the side the straight line on the Azeroth map stands in.
- **Selection by cost, not by phase.** Steps grow from the player outward: each next pick is the candidate
  cheapest to reach from the player or any step already picked. A turn-in on another continent no longer pushes out
  a nearby pickup. Skipped steps are never candidates. With no known place for the player (an instance, or a
  map the data lacks) nothing measures from them: turn-ins lead and the route grows from the first of them.
- **Order.** Nearest neighbour from the player, grouped by continent so the route crosses at most once (the
  player's continent first), then 2-opt on the same cost. A turn-in on another continent is kept but goes last,
  with the reason "Hand in when you're in <zone>".
- **Value (batch F, plan §7.3).** Selection subtracts a value from the reach, in yards:
  - more for each of a stop's quests;
  - more for a quest one level from grey;
  - more for each hand-in;
  - less when every quest is red or optional;
  - a stop with no quests is worth what its kind says: a trainer's, one hand-in.

  The order itself stays on travel alone. Within a stop, hand-ins come first, then grey risk, then closeness to the
  player's level.
- **Unchanged.** A quest whose eligibility the data cannot establish is never a candidate, and every step keeps
  the data's coordinates.

Contents of the sweep (#9):
- delete `prefs.legacy` and `prefs.professions` (Core.lua:23-24, types/Namespace.lua:58-59, the spec);
- set TOC `OptionalDeps` to `ShortestPathForever` only (Tweaks Forever is read at rebuild time, never at load, so
  load order does not matter for #19);
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
---@field Ended? fun(owner: string): AGFSPFEnded?, number?  -- why owner's last journey ended (§2.10); SPF ee2346b
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
| All of SPF, or v1.1.0 from the stores | Sets a native user waypoint for step 1, only when `C_Map.CanSetUserWaypointOnMap(map)` is true. Stop clears it only if `C_Map.GetUserWaypoint()` (MapDocumentation.lua:454) still matches the `UiMapPoint` AGF set (same map, and x/y within 1e-4). Routes are ordered as §4.1. There is no travel line. |
| `Navigate` / `NavigateRoute` returns false | The same native waypoint as when SPF is absent: SPF declined, so the player still gets a destination. |
| `EstimateDetail` | Travel line reads "About N min away", from `Estimate`. |
| The nil reason | AGF checks `InCombatLockdown()` before calling. A nil result means the line is omitted, or the previous line is kept if there was one. |
| `Active` | Go behaves as it does today, and no warning is shown. |

Not requested:
- `RegisterCallback`. Rings and Stop re-check `CurrentStop(OWNER)` on route change and on map `RefreshAllData`.
- `EstimateMany`. Siblings.md measures 40 estimates at about 0.63 ms warm.
- Stop metadata.
- `Preview`. SPF's dotted preview stays SPF's; AGF draws no lines. `NavigateRoute` previews every later stop as
  one walk path, drawn as straight dots even across an ocean (SPF `Route.lua` `SetJourneyRoute`); SPF PR #29 fixes
  that on SPF's side, and §4.1 keeps AGF's routes to one crossing.

### 5.2 Legacy Forever, Tweaks Forever, SkillUp Forever

| Sibling | Contract | Why not |
|---|---|---|
| LegacyForever (formerly LegacyHere) | none | It has no public API (origin/main ea0fb8c; the PROBE `legacy` scan shows only `LegacyForever*` mixins and DB). Its data has 0 quest criteria (siblings.md §3), so no quest can be honestly tagged, and percentages are Legacy's domain. It returns only if Could #18 is promoted, as `Objectives(uiMapID)` with no percent. |
| TweaksForever | `TweaksForever.API.TrainableSpells()` (TF PR #45, `version = 1`), for Should #19 and the trainer stop (§2.12) | Returns fresh `{spellID, name, level, cost?, line, lineID}` tables for the trainer spells the player's level allows and they haven't learned, or nil before login and in combat. AGF checks `type(api.TrainableSpells) == "function"` where it uses it, and treats nil as "no step this rebuild". The zone table is still baked at generation time (siblings.md §4); `DungeonEntrance` is needed only for Could #17. AGF never re-sorts the stock tracker, which TF's "Nearest quests first" owns. A public `DungeonEntrance(mapID)` is a follow-up (plan §7.5). |
| WorkOrdersForever | none | It messages agents, and has no gameplay data or API. |
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
- **Rest stop.** None of the 28 candidate camp auras was present (PROBE lines 129-147), and the CSV has no camp atlas.
- **Encounter Journal integration.** It is not loaded, and has 0 tiers (PROBE `ej`, again in batch 2).
- **Traveler's Journal and alt memory.** They need account-wide progress state, which is a treadmill (games.md pain point 9).
- **Weekly bounties.** A progress treadmill, and against the pillars.
- **Bundled quest text.** Uncached quests have no text (PROBE `questtext`: `HaveQuestData` false for 5892 and 7). Blizzard's details page shows log quests.
- **SkillUp steps; TF `ZoneRange` / `IsActive`; SPF `RegisterCallback` / `EstimateMany` / stop metadata.** YAGNI (§5).
  The card minutes take one estimate per frame instead, and the footer follows `SUPER_TRACKING_CHANGED` /
  `USER_WAYPOINT_UPDATED`, which SPF itself registers on Forever.
- **Localised hub names.** `TaxiNodes` in the generator is enUS, and reading `C_TaxiMap` is barred (§6).
- **Hearthstone in travel estimates.** SPF has no hearth edge, and `GetBindLocation` gives only a name.
- **Hub names for towns with no flight master** (Goldshire, Razor Hill). No proper source names them, so these
  towns take their lead NPC's name instead.
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
8. When SPF declines a route (Go returns false), the native waypoint appears instead.
9. With a turn-in on another continent, the route stays on this continent first, crosses once, and ends with that
   turn-in ("Hand in when you're in <zone>").
10. With Tweaks Forever (PR #45) loaded and spells to train, "Visit your class trainer in <town> · N new spells"
    shows above the cards and in the tracker with the class trainer mark and no ring; its click goes to the nearest
    trainer; its X, Skip for now and Not interested hide it, and the cog's "Skipped (1)" brings it back. Without
    Tweaks Forever, nothing changes.
11. With no journey chosen the tracker shows one line (the aside, else the story's hook) and no step; its click
    chooses the story and the full step block appears.
12. Batch F (plan §7.10): Lakeshire is one stop; a stop ring draws over a super-tracked "?"; the cards show minutes
    and the hub line; the footer's Stop goes as soon as Shortest Path ends the journey.
13. Batch G (plan §8.2): a chosen journey lasts through travel, turn-ins and `/reload`, and a paused route resumes
    from its card or the tracker title.
14. Roadmap #8: searching a quest gated on a profession the character has ("Requires <skill> <rank>") ticks it at or
    past that rank; on an unlearned line it is unmet. A reputation-gated quest reads "Requires Friendly with …" in
    the client's words and ticks once the standing is reached; learning a rank or gaining the standing opens it
    without a `/reload`.
15. Trainers (§2.12): with spells to train and a journey chosen whose route passes the trainer's town, a "Train in
    <town>" stop shows with a ring and Go; training the spells removes it at once.
16. With a journey chosen, hovering its next stop's giver adds "Adventure guide: <title>" under the stock unit lines
    (in combat too, with no taint logged); another NPC, a player, and every NPC once the choice is cleared add nothing.
17. Something new (§2.13): a level-up that brings a new next-zone card glows "<Zone> is now for your level" once,
    with the tab and compartment pips; opening the tab clears both, the card's mark stays until it closes. A login
    or `/reload` never glows.
18. QuestieDB (§2.14): with it loaded, `/agf audit` names "QuestieDB <version>" a few seconds after login with no
    hitch, and the cards, rings and town stops match the bundled run; with it disabled, or Questie alone without it,
    the audit names the bundled data and why.

## 9. Open questions that need client probes

**Answered** by the batch-2 run on 2026-09-23 (client 1.60.1.69977, a level-18 Alliance shaman in Auberdine):

| Probe | Result | Decision |
|---|---|---|
| 1 FutureSpell (`spellbook2`) | 0 `FutureSpell` entries in all 4 lines at level 18 | The client can't tell; #19 asks Tweaks Forever instead |
| 2 `questoffer` | `QuestOfferDataProvider` exists, but 0 quest lines and no `QuestOfferPinTemplate` in the live pin pools | Blizzard draws no givers: AGF's giver layer stays, off by default (§2.6) |
| 3 `classnames` | `C_CreatureInfo.GetClassInfo` / `GetRaceInfo` return names | Use them (§3) |
| 4 `c60` | `GetAtlasInfo` is nil for every `-c60` name; plain names resolve to the `-c60` art | Plain names only (§2) |
| 5 `questline` | `GetQuestLineInfo` nil for all 5 log quests; 0 lines | Keep the conservative `pre`/`next` rule |
| 6 cache | A quest requested last session is cached next session; another is not | Live title when cached, else the data's (§3) |
| `templates` | `AlphaHighlightButtonTemplate` exists; it errors on `Hide` before a `NormalTexture` is set | Inherit it; set the normal texture first |
| `ej` | Loadable but not loaded, 0 tiers | No Encounter Journal use (§7) |
| 8 fanfare | `SetNeedsFanfare` exists | Whether the glow plays for an addon module stays a `/reload` check |

The original questions follow for the record.

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
