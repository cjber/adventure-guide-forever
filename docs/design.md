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
- **The journey before the destination.** The player chooses from a handful of journeys (six at most): the story
  where they are, the zones they could head to next, and a dungeon or their calling when one fits. Until they do, the
  tab is an overview (the first card featured over its first steps, the rest two across), and the tracker and map
  draw the first card's steps on their own, so a new
  character has a route without a click; a choice overrides it.
  Chains read as a zone's chapters, with later chapter titles left unrevealed. There are no percentages, XP/hour figures or step counters.
  The one exception is the card's hub line ("Lakeshire, Redridge and 2 more stops"). The user asked for it, and it
  counts towns, not progress (plan §7.4).
- **A stop is a town.** One stop per hub (plan §7.2) merges its hand-ins and pickups. The route leads to the
  hub's nearest giver, and the stock "!" and "?" marks cover the last yards.
- **Approachable and familiar.** The guide lives in the quest log tab and the objective tracker, both stock frames.
  Quest text is Blizzard's own details page. Leaving the plan is normal: Stop and Skip always work, and the route
  rebuilds from the live quest log.
- **The player steers.** "Not this quest" drops a quest from every route, a shift-click adds one, and a nearly full
  log gets a count of what could go (§2.18). The guide advises; it never abandons, accepts or tracks a quest for
  the player.
- **A steady route.** The route rebuilds on events (a quest taken, an objective done, a hand-in, a zone, a skip or a
  choice), never because the player walked. Each card keeps its order for the session (`route.orders`): its lap goes
  on until it ends, a new step goes where it adds the fewest yards, and a new order replaces it only when it saves
  15% and 200 yd. The town or open area the player stands in leads; walking into one is checked every 2 s
  only while the player moves. Leaving an area the player stands in takes 30 yd past its edge, so its border
  does not flicker.

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
+-----------------------------------------------+  none chosen: the overview
| (c)          Adventure Guide                  |  header: the title, and under it the player's zone
|             The Barrens · level 18            |    and level (GameFontHighlightSmall)
|-----------------------------------------------|
|  (t) Visit your class trainer in Durotar      |  every aside the player still wants, 16 px apart
|  (t) You have 1 talent point to spend         |
| +===========================================+ |  featured: 288x82, the renown art 6 px outside, sliced 12
| | (map)  The Barrens story        Suggested | |  zone icon 40 across, ring 1.4x, kind badge 16
| |  (S)   2 quests will soon turn grey       | |  title GameFontNormalMed2, the reason, then the counts
| |        ? 2 ready to hand in  ! 1 in prog. | |    with the map's own marks; a 7 px bar on real progress
| +===========================================+ |
| (1) Crossroads, The Barrens  1 to hand in,... |  its first 3 steps: 288x22 pet-list rows, ring 18, the
| (2) Turn in: Counterattack!  ready to hand in |    number, title and detail on one line, 24 px apart
| (3) Ratchet, The Barrens  5 to pick up        |
|  ---------------------------------------      |  divider, 10 px
| +-------------------+ +-------------------+   |  the others two across: 141.5x92, 5 px apart
| |(map) Loose ends   | |(map) Head to      |   |    icon 30, badge 13; title up to 2 lines (3 when the
| | (?)               | | (!)  Stonetalon   |   |    reason gives way), never clipped
| | Orgrimmar, Durotar| | Makaba Flathoof...|   |    reason up to 2 lines
| | [==]   1 of 1 ready| | For level 20      |   |    footer: a bar and "N of M ready", "For level N",
| +-------------------+ +-------------------+   |      or the stop count
+-----------------------------------------------+

+-----------------------------------------------+  308 px pane (QuestMapFrame.xml:648): one chosen
| [Search quests..........................] [*] |  29 px top bar: SearchBoxTemplate across the width
|-----------------------------------------------|    (no step count, §1), settings cog
| [(?) Loose ends                           +] |  the others, one line each: 288x26, 2 px apart
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
  Being optional, it never picks the zone: zones are ranked by their other quests. A raid's quest (`raid`) is on
  no card at all, neither a zone's nor the dungeon card, and never ranks or picks a zone: a raid is not a step a
  short route can hold. The generator flags a quest filed in a raid instance, and one of CMaNGOS Type 62 or 88
  (QuestInfo Raid) wherever it is filed: Zul'Gurub's Paragons of Power are filed under the outdoor Zul'Gurub area and
  given on Yojamba Isle, yet ask for the raid's drops, so only their type says so (83 such quests at the pin).
- **None chosen** is the default (a fresh character, the back arrow, or a saved choice whose card is no longer
  offered), and the tab is the **overview**, cjber's pick of the mocks (A3). The header gains a subline, "The
  Barrens · level 18", the player's zone and level. Every aside the player still wants shows, not only the first
  (the tracker keeps one line). Then the **featured** card: the route's card (the first shown when its key is not
  among them), tagged "Suggested", with its title, its reason and its counts ("? 2 ready to hand in", "! 1 in
  progress", the map's own turn-in and quest marks), and a 7 px bar only on real progress: a story past chapter 1 of
  a known length ("1 of 4 done"), or loose ends with something ready ("1 of 3 ready"). Under it its first 3 steps
  (`journey.steps`) as small pet-list rows with the ring, number, title and detail, the chosen rows' tooltip, click
  and menu. A divider, then the other cards **two across** (141.5x92, 5 px apart): the zone icon, the title beside
  it on up to 2 lines (3 when the reason drops to 1) and never cut, the reason under both on up to 2 lines, and a
  footer: the bar with "N of M ready", else the next zone's "For level N", else the stop count ("3 stops"). A reason
  equal to the footer is left out. A click on any card chooses it. No minutes here: they belong to the chosen card.
  Every card in the overview is the renown card's art, drawn 6 px outside the button (the atlas's empty margin)
  and sliced at 12 so its rim keeps its width at both sizes.
  It replaced every card whole over a dash list of its steps, which gave each card the same weight and scrolled
  after two; before that, the first card drawn whole over its steps with the others as rows looked
  the same as the chosen view whenever the chosen card was the first, so the back arrow seemed to do nothing.
- **Zone icons** (ZoneIcon.lua): the Suggested Content recipe, the zone's own map cut round
  (`CircleMaskScalable` on every tile, the whole clipped with `SetClipsChildren`) inside `adventureguide-ring` at
  1.4x, the kind icon as a badge at its bottom-right. The base is `C_Map.GetMapArtLayerTextures(uiMapID, 1)`, the
  12 tiles the client gives; over it every overlay `Data/ZoneArt.lua` has, explored or not (generated by
  `tools/gen_zoneart.py` from the pinned wago `UiMapArt`/`WorldMapOverlay`/`WorldMapOverlayTile` tables: 40 zones,
  525 overlays, 22 KB). The window is 420 map pixels across on the featured card, 240 on the grid, centred on the
  card's first town on its map (else its first step) and kept 20 px inside the art. Only the tiles the window
  touches are drawn, and an unchanged window builds nothing. A card with no map, a city or dungeon the data has no
  art for, or a client that gives fewer than 12 tiles keeps the plain ring with the kind icon centred in it.
  Behind it the route still falls back to the first card (`route.chosen` false, auto-start), and the tracker, the
  map preview (§2.6) and the NPC line follow that card as before: kept, since the overview lists it first and a
  click on its ring or the tracker title chooses it. Nothing guides until the player asks: a card click, the tracker
  title, a ring's click or Go. A stale saved key stays saved and is chosen again should its card come back.
- **One chosen** (a click on any card in the overview): the others fold to one-line rows above it, in their order, and it sits whole and lit right over
  its track and step rows. Its steps start at the same place whichever card it is (two rows, 58 px, then the card),
  and no card sits between a card and its steps, which the old order did (a middle card's steps pushed the last card
  below the fold). A row chooses its card. The chosen card is no toggle: a click on it turns the map to it again,
  or resumes its route while that is paused (§2.10), and nothing more.
- **Back to all suggestions.** While a card is chosen the header shows the game's back arrow,
  `common-icon-backarrow` (CSV:4624, as Forever's character creation draws it on its Back button), 22x22 at the
  header's left, the compass moved 20 px right of it. Its tooltip is "All suggestions", adding "Also stops the
  route" while AGF's route runs. A click, or a right-click anywhere on the header, chooses none: the guide shows the
  overview again, and the route AGF started stops, as for any cleared choice. With none chosen the arrow is hidden and the header's right-click does nothing.
  No animation: the quest log's own headers fold at once, and a height tween would need an OnUpdate.
- **Choosing starts the route.** Selecting a card (whole or a row) sets `prefs.journey`, rebuilds the route and, on
  the rebuild that has its steps, hands them to `Integrations.Navigate`: SPF's journey, or the native waypoint
  without it. There is no Go button: choosing is already the commitment, and a second click to start the same route
  was a step with no decision in it. Without SPF the waypoint is placed too, since Stop and clearing the choice still
  clear only a waypoint where AGF put it. The back arrow chooses none and stops AGF's route (never anyone else's),
  so the lit card and the guidance never disagree.
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
  Forever added that it lacks and the player hasn't finished, one `GameFontDisableSmall` line sits under the shown
  card's steps, above Skipped: "This land has stories the guide doesn't know yet; look for the "!" over quest givers." It points
  at the giver's own mark, since Forever draws no givers on the map (§9 `questoffer`). It is never on a card (§2.2) and
  never beside the search's results. `Model.Unlisted` decides. The added quests come from `Data/Forever.lua`, which
  `tools/diff_forever.py` generates: the QuestV2 IDs Forever's build has and Classic Era 1.15.9.69722 lacks, each placed
  on the zone maps its `QuestPOIBlob` rows name. Only 26 of the 1795 added quests have a blob, so the zone half is
  narrow; a quest with no blob has no zone and is left out. The slice also lists the 160 added AreaTable IDs, which
  put an unexplored area first (§2.11), and the added lands (§2.11); TaxiNodes and Map diffs are printed only.
- Fit: with one chosen, it takes 86 px and each other card a 28 px row, so with five others the cards take 226 px
  and its step rows scroll below them. The overview takes 167 px for the featured card, its 3 steps and the divider,
  then 97 px a grid row: six cards take 453 px, so they fit whole under one or two asides.

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
  lost. The chosen card's tooltip says "Click the back arrow to see all suggestions". Pooled: the six card buttons
  (`Model.MAX_JOURNEYS`) are resized in place, no frame is made per refresh.
  - Why this art: it is a stock single-line row drawn at native height with a "+" that says it opens; the renown
    card squeezed to 28 px pinched its frame, `friendslist-categorybutton` read as a second heavy card and
    `collections-slotheader` too faint to read as a button.
- **Chosen card:** the card's own `ui-journeys-renown-button` with its highlight locked, never
  `ui-journeys-renown-button-pressed`, which is drawn a few pixels off true; its pushed art is the same atlas, so
  neither a press nor the choice moves any art, text or icon.
- **Kind icons** follow Blizzard's `QUEST_TAG_ATLAS` (`BLZ/Blizzard_FrameXMLBase/Constants.lua:514-527`):

  | Card kind | Icon | Mock label |
  |---|---|---|
  | Hand-ins ("Loose ends") | `questlog-questtypeicon-quest` (CSV:9396) | `(?)` |
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
  - **Line 3.** It shows the log-full note on the first card when it has one (§2.18), else the journey's reason,
    else the hub line: "Lakeshire, Redridge and 2 more stops".
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
- **Card kinds** (`Model.MAX_JOURNEYS`, six, at most; only those that have steps). The story, carry and the zones
  to head to keep their slots, in that order; the diversions share what is left (roadmap R4):
  1. **The zone story**: the best eligible chain in the zone that ranks first now (below), or the zone they stand in
     while its quests are theirs to take or carry. It also holds the log's quests done next on its map: hand-ins
     share its towns' stops, and quests under way are steps at the client's point for them, else the data's area
     for their first open objective. Its subline counts them first.
  2. **Loose ends**: the log's turn-ins and objectives the story does not hold, and the quests the player added
     (§2.18) that no zone card holds; its subline counts those as "N you added".
  3. **Zones to head to** ("Head to Duskwood"), up to three, best ranked first: the zones that rank for `level + 2`
     in the same eligibility pass (`Choices` in `Model.Journeys`), or for the level itself at the cap. Each is another
     zone than the story's and the one the player stands in, one whose range the player hasn't outgrown (their level
     is at most its top), with at least 5 quests there two levels on and 3 of them open now, so a zone just come into
     range (Duskwood at 19, with 4) is offered. Its reason is "For level N" while it is among the three that rank
     best two levels on; never at the cap.
  4. **Diversions**, newest first:
     - **Your calling** (roadmap #7): the class quests the player can take now, as one card: a `classes` mask of the
       player's class alone (Vile Familiars, every Horde class's but the warlock's, is a starting quest), never a
       raid's. It leads with a chain as the story does (§2.3), else the lowest quest ID. Its reason names that quest:
       "Your class trainer has a task: Call of Earth" only when the data proves its giver trains the player's class
       (`start.trainer`, from CMaNGOS TrainerClass), else "A task for your class: Call of Earth".
     - **Dungeon** (Dungeons on, or no next zone): the party instance with the most quests open now. Its reason
       (roadmap #15) counts the log's quests filed under it, which end inside: "2 of your quests end inside Wailing
       Caverns", "1 of your quests ends inside Wailing Caverns"; none carried, no reason. There is no "Find group"
       button: R5 found `LFGVanilla_ShowFrame` but never called it, so its taint is unknown, and the button waits on a
       probe that calls it.
     - **A way into an instance** (roadmap #21, no next zone only): the chain (§2.3) the player can take up now that
       has a quest filed under an instance the data names, from its chapter on, as a story card: "The way into
       Scholomance", its chapter as the subline, "Begins a new story" or "Continues a story you started". The data
       never says a chain is an attunement, only that it goes inside, so the card says no more. The story's own chain
       is never offered twice. Key `chain:<first quest>`.
     - **Battleground** (opt-in, §2.15).
- **Zone ranking.** `Rank` scores each zone with a quest open (lowest first), from the data's quests and the client's
  zone levels (`data.zones[map].min`/`max`):
  - **Quest fit** leads: the mean of each quest's distance from the level, doubled past two levels up.
  - **The zone's range**: 2 a level outside it; up to 1 less in its lower half, which the player has just entered;
    up to 3 more in its top fifth, where what is left is cleanup that the story's laps and Loose ends already hold.
    At 19 Duskwood (18-30) and the Wetlands (20-30) outrank Westfall and Darkshore (10-20), though those hold more.
  - **Density**: 0.25 less a quest, for up to 8, so a zone with enough for a lap edges ahead.
  - **Distance** from the player to the zone's middle, at a like fit: 1 a 4000 yd on their own continent, up to 1.5.
    On another it is the whole way through their side's docks, the crossing included (§4.1), so a zone next door
    beats one overseas unless it fits clearly worse: at 18 in Westfall, Redridge comes before Ashenvale. Nothing when
    the data can't place the player (an instance), so the ranking never guesses.
- **Which diversion.** Each is ranked by the level its newest quest opened at (the highest `min` among its quests
  open now), highest first, so a level just gained or a bracket just opened takes the slot and an older one yields
  as the player levels on. A tie goes calling, dungeon, a way in, battleground. It is stateless: nothing is
  remembered between sessions. Only as many are built as there are free slots, plus the chosen one, which always
  keeps its slot.
- **Budget.** Only card 1 and the chosen card plan laps (§4.2); every other card is Build's short route over its
  towns, about 0.1 ms a card, so six cards keep the rebuild inside its 3 ms frame.
- **No next zone** (roadmap #21): at the level cap, or when no zone is ahead and no story was built, the guide never
  ends on "nothing fits". The dungeon card comes whatever the Dungeons toggle says (its eligibility pass then takes in
  the instance quests the toggle holds back), and a way into an instance may take a slot. The route carries
  `stranded`, so a chosen dungeon that goes then has ended rather than been filtered (§2.10).

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
  - `breadcrumb`, the quest a breadcrumb leads to ("Only until you take X"): open only while that quest is neither
    completed nor in the log. The generator emits CMaNGOS `BreadcrumbForQuestId` (wago's QuestV2 export has no such
    column) and withholds the start when the target is not in QuestV2 (124 breadcrumb starts at the pin);
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
- **No journey chosen.** The step block is the first card's step 1, as the guide draws it (§2.1). Its title click
  chooses that card as a click on it does, starting the route with "Choosing a journey starts the route";
  right-click is the tracker menu.
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

While SPF is guiding, AGF's rings hide, because SPF draws its own stops (Pins.lua:15-17). A wanderer (§2.17) sees
no layer at all.

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

- **Preview.** The open guide previews the chosen card's rings, else the first card's, which the guide draws on its
  own behind the overview (§2.1); a ring's click chooses that card. Selecting a card turns the map to that journey's
  first zone (`WorldMapFrame:SetMapID`) and draws only its rings. Hovering a step row flashes its ring (`Pins.Ping`,
  Pins.lua:184-188).
- **Areas** (a quest's objective area): AGF draws no disc over one. The game's own objective mark shows the area,
  and hovering it draws the area's true shape, where a disc round its middle covered ground no objective is on and
  hid the map. Walking into step 1's area selects its quest the stock way (`C_SuperTrack.SetSuperTrackedQuestID`,
  in Forever's 1.60.1 API and not protected), so the map draws the game's own blue area where the player works
  (Focus.lua, the "Follow the quest you're working on" setting, on by default): only on walking in, never over a
  quest the player selected, and cleared on walking out or finishing the area while the selection is still AGF's.
  An area step's number sits where the route enters it (§4.2); while the player stands in step 1's area it has no
  number.
  The choice going, however it goes, stops what AGF guides (Core.lua's `wasChosen` listener): the overview shows and
  the first card is previewed again, nothing guides until a click, and a route the player started in SPF stays.
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
| Not this quest            > |  ns.NotThisQuest(id); a submenu per quest when the stop has several
| Skipped (2)               > |  "Show again: <title>" -> new ns.Unskip(key) + ns.Invalidate()
| Choose another journey      |  ns.OpenPanel()
+-----------------------------+
```

Step skips stay session-only. The menu has no auto-go.

**Not interested (roadmap #17).** A journey card's right-click (not the carry card's: what the player carries is
theirs) opens its title and "Not interested". That saves `charDB.notInterested[key] = {title, chosen}` for this
character, so the card stays gone across sessions; the planner offers the next best zone or dungeon in its place, and a
choice of it ends as a click on its card would. "Skipped (n)" (under the cards, in the step menu and in the cog) counts
these after the session's step skips and offers each back with "Show again: <title>". `chosen` records that the
journey was the chosen one, so Show again chooses it again, after a `/reload` or a login too. A saved bare title (the
shape before `chosen` was kept) loads as a journey that was not chosen. The card's tooltip ends with "Right-click if
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
and the tracker title. The chosen card's tooltip reads "Click the back arrow to see all suggestions"; while its route is paused (§2.10), it
first says "Click to resume the route", with the warning when another journey runs.

**NPC line (roadmap #19, `Tooltip.lua`).** Hovering an NPC the shown journey's steps visit adds one
`AddNormalLine` to the unit tooltip: "Adventure guide: <journey title>". The NPCs are a town stop's givers and enders
(its spots) and a turn-in's finish NPC, matched by the creature entry in `UnitGUID` against the places' `npc` (the
generator's creature entry; an object giver has none). An objective or dungeon step visits no NPC. The set is
gathered on each route change, so a hover only reads; the line comes from a `TooltipDataProcessor` post call, in
combat too, and touches no secure frame. For every other unit nothing is added.

### 2.10 A journey's lifecycle

A **choice** (`prefs.journey`, one card) is kept apart from **guidance** (`prefs.guided`, the key of the chosen
journey whose route AGF started). Choosing, starting and ending all live in Core (`ns.Choose`, `ns.StartRoute`), so
the cards, the tracker title, the menus and the map's rings behave the same, with the guide open or closed.

Keys: `carry`, `zone:<map>` for a zone's story and its next-zone card alike (so heading to a zone becomes its story
on arrival), `dungeon:<instance>`, `calling`, and `chain:<quest>` for a way into an instance (§2.2). `LoadCharDB`
migrates the old `story:` and `nextzone:` keys once.

Invariants:

1. **Offer rules only gate new choices.** A chosen journey is built while it has a step, whatever would offer it
   now, and keeps its slot when a new card pushes one out.
2. **The story is the zone you stand in** when it fits (in the top 3 of the ranking now, or two levels on), when
   your level is within its range and it has a quest open now that is not an outdoor elite (a zone whose quests you
   have mostly taken up ranks low, yet is still where you are adventuring), or when it is the chosen zone.
3. **Only a chosen journey is guided.** With none chosen the guide, tracker and map draw the first card's steps
   (auto-start, §2.1), but nothing guides until the player chooses or asks for Go; the tracker title, a card or a
   ring chooses the card it shows.
4. **Guidance follows the journey.** On each rebuild and on the frame after Shortest Path's super-tracking events,
   `Integrations.Stale` sends the route again, once, when a stop it has yet to reach left the steps, step 1 is neither
   the stop it heads for nor the one just reached, or step 1's point moved more than 100 yd (the town linkage).
   Never in combat, on a taxi or off the map. Without Shortest Path the waypoint moves to step 1 instead, quietly.
5. **Nothing starts on its own,** except the restore after a `/reload` or login (once, on the first full build out
   of combat, never over someone else's journey) and the extension of a route that arrived to steps it never had.
   While the player stands in step 1's town (within 100 yd of any of its quests' places) with steps after it,
   Shortest Path is handed the town alone: it arrives there and draws no way out of town before its quests are
   taken, and the route goes on once the town is done or the player walks out. While they stand in step 1's
   objective area there is nothing to walk to: no waypoint and no Shortest Path route, until the area is done or
   they walk out, and then the route goes on by itself.
6. **Losing something is never silent.** A turn-in that ends the chosen journey glows "Journey complete" in the
   tracker; a route that stopped says "Route paused" in the footer.
7. **Endings are judged on full builds only,** out of combat, once the completed quests have loaded.

Guidance states:

| State | Test | Chosen card click (the back arrow always clears the choice) | Footer |
|---|---|---|---|
| Idle | nothing of ours | chooses | |
| Pending | a start waits for combat | turns the map to it | "The route starts when combat ends" |
| Guiding | `CurrentStop` and `Active()` | turns the map to it | Stop |
| Held | `CurrentStop`, `Active()` false ("Guide me" off) | turns the map to it | Stop |
| Here | guiding, the player stands in step 1's objective area: no waypoint, no Shortest Path route | turns the map to it | Stop |
| Paused | chosen, `guided` (or cleared or replaced), no route | resumes it (so does the tracker title) | "Route paused. Click the journey to resume." |
| Arrived | ended at its last stop | turns the map to it | |

Stop, in the footer or a step's menu, does what the back arrow does while the route runs: the route stops and the
choice clears, so no journey is left chosen with nothing to resume it.

An end is classified by Shortest Path's `API.Ended(owner)` when present ("arrived", "cleared", "replaced",
"cancelled"). Without it: another journey running means replaced, standing within 100 yd of the last stop means
arrived, and anything else means cleared. Arrived keeps `guided`; cleared and replaced forget it, so nothing sends
the route again until the card resumes it.

A chosen journey the full build no longer has ends: its route is cancelled and the choice cleared, so the guide
shows the overview again. A Quests or Dungeons filter keeps the key (the player's own toggle can bring it back) but stops the
route; Quests covers `zone:` and `chain:` keys and `calling`, Dungeons `dungeon:` keys, except with no next zone,
when Dungeons hides nothing. Skipping every step of a chosen journey ends it the same way, quietly.

### 2.11 Asides

An aside is a one-line hint beside the journeys, never a route: `Asides.lua`, after `Integrations.lua` in the TOC.
Each domain registers a provider returning at most one `{key, text, icon, place?}`: `icon` an atlas the CSV has,
`place` only a place from the data. Providers are asked in step 1's travel frame after each rebuild
(Core), never in a rebuild's frame and never in combat, when the last answers stand; views redraw only when the
asides shown change. Each provider's answer the player has not skipped or turned down is an aside (`Asides.All`),
in the providers' order; the first is the tracker's.

- **Two surfaces.** Above the cards, one line per aside, 16 px apart (icon, `GameFontNormal` text, a row's
  `common-icon-redx` skip), hidden while searching; and the tracker's one line (§2.5), the first of them.
- **Skip for now** hides it for the session: the line's red X, or its menu. **Not interested** hides it for the
  character (`charDB.asides[key]` = its text); the cog's "Skipped (n)" submenu, shared with skipped journeys, offers each back as
  "Show again: <text>", its provider's text now when it still answers, else the saved one.
- **Clicks.** Right-click on either line is its menu (Go with a place, Skip for now, Not interested). Left-click goes
  to its place, as a step's Go does (§5.1), and does nothing without one.
- **Providers.** The class trainer (F16): "Visit your class trainer in Stormwind · 3 new spells" with the minimap's
  `class` mark (CSV:1321), from Tweaks Forever's `TrainableSpells`, asked again on `SPELLS_CHANGED`. Its place is the
  nearest trainer who teaches the spells (§2.12); without one (a class and side the data has no trainer for, or no
  place for the player) it is text only: "Visit your class trainer · 3 new spells". Unspent talent points (#25):
  "You have 2 talent points to spend" with the Legion `minortalents-icon-book` (CSV:388, the atlas's one square
  talent mark), from `GetNumUnspentTalents` (R5 found it; `UnitCharacterPoints` is missing on Forever), while any wait,
  asked again on `CHARACTER_POINTS_CHANGED`; no API, no line. Then the profession aside (§2.16), then a battleground
  open to you and the next PvP rank's reward (§2.15), then a new land and the zone's unexplored area (below). Providers
  are asked in that order, the TOC's.
- **News again.** A provider may give `renew`, how often the aside became news (a talent point gained): Skip for now
  holds only while it is unchanged, so each new point brings the line back once. An event a provider needs is
  registered through `Asides.RefreshOn`, which skips one the client lacks.
- **Several candidates.** A provider with several offers the first the player still wants (`Asides.Wanted`), and Skip
  for now and Not interested ask the providers again, so the next one shows at once.
- **New lands (roadmap #14).** "Riverglades · For levels 36-44" with the minimap's `flightmaster` mark (CSV:1330),
  key `land:<uiMapID>`: a zone map Forever added (`tools/diff_forever.py` `lands`) whose range holds the player's
  level, never before it or after (no teaser). The range is the least and greatest non-zero
  `AreaTable.ExplorationLevel` of the land's areas and their children, so a land whose areas are all 0 (Mount Hyjal,
  Shen'dralas) is never one. Its place is the first Forever-added flight master on the land that serves the player's
  side (TaxiNodes Flags; Rog'mar for the Horde, Farholde Keep for the Alliance), projected as a quest giver is. A
  land with none for the side says nothing: Zephras Isle (3-12) has no flight master the data places, and nothing
  says how to reach it. It retires once the client reports any of the land explored, and never shows while the
  player stands in it. The name is the client's (`C_Map.GetMapInfo`), else the data's.
- **Unexplored nearby (roadmap #13).** "You haven't seen Thorn Hill yet" with the guide tab's compass, key `explore`
  (Not interested ends every area), text only: no place, no ring, no waypoint. The areas are the zone map's
  `WorldMapOverlay` rows with a texture (`Data.overlays`, `tools/gen_quests.py` `overlays`), each named by its first
  AreaTable row, left out at ExplorationLevel 0. The client reports an explored overlay by its offset
  (`C_MapExplorationInfo.GetExploredMapTextures`, probe `explore`: 7 of Darkshore's 9 at level 18, matching the
  data's offsets), so the aside names one of the player's zone the client doesn't report, at most two levels above
  them: an area Forever added first, then the nearest by its hit rectangle's centre (never shown or pointed at),
  then the lowest area ID. The name is the client's (`C_Map.GetAreaInfo`), else the data's. `MAP_EXPLORATION_UPDATED`
  (the client's "Discovered") asks the providers again at once, so the line moves on or goes.
- **Order.** A new land, then the zone's area: `Hints/Explore.lua` registers after `PvP.lua`, last. Without
  `C_MapExplorationInfo` neither exploration aside says anything.

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
  dungeon's card title; a way into an instance "The way into Scholomance is open to you") under the quiet line,
  glowing once as §2.7's fanfare does, with no sound; its click opens the guide. A new aside: its own tracker line glows. Either way `adventureguide-microbutton-alert` (CSV:2025) pips the
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
  into one group per connected set), chain, breadcrumb target (else the bundled one), repeatable, skill and
  reputation gates.
- **Still bundled:** zones, maps, continents, crossings, towns (a place joins the nearest bundled town place within
  100 yd), hub names, NPC roles, instances, elite and a raid's quest (a quest typed Raid stays one wherever QuestieDB
  files it); and what QuestieDB leaves out: a level of -1 (it scales), a
  missing minimum level, a dungeon it files outside an instance, and the place of a giver none of whose spawns it
  places when the bundled data names the same NPC.
- **Withheld start:** any quest the bundled data lacks, or whose bundled start it withholds (nothing says what else
  gates it: the generator's Method, condition and event gates, and givers CMaNGOS spawns only for an event, which
  QuestieDB lists as ordinary spawns); a prerequisite, exclusive quest or breadcrumb target outside the data; and `parentQuest`, `requiredSpell`, `requiredSpecialization`,
  `requiredMaxLevel` below the cap, `availableUntilCompleted`, `availableStartingWith`, `requiredRanks`,
  `disabledByQuest`, flags 1024 or 16384, or a gate on a skill line or faction the data doesn't name.
- **Fallback:** any failed check or read keeps the bundled data; `/agf audit` names the source and the reason.
  Questie and QuestieDB carry no licence, so the repo, specs and goldens hold none of their code, types or data; the
  specs use a synthetic stand-in, mostly a mirror of the bundled data (`harness.questieMirror`).

### 2.15 PvP (roadmap #12, #28)

`PvP.lua`, after `Hints/Profession.lua` in the TOC, gives two asides; the opt-in card is the planner's.

- **Open to you.** Only `C_PvP.GetLevelUpBattlegrounds(level)` says which battlegrounds are open: each level up to
  the player's is asked once (R5: Warsong Gulch at 10, Arathi Basin at 20, Darkspear Islands at 30). `canEnter` gates
  nothing, since R5 found it false for all three at level 19. A battleground behind a condition (Battle for
  Blackrock) or with no levels (Battle for Gilneas) is on no list, so neither shows falsely. No API, nothing shows.
- **The aside.** "Warsong Gulch is open to you" with the minimap's `battlemaster` mark (CSV:1319), for the newest open
  battleground, until the character stands in a battleground (`IsInInstance` names "pvp") at a level at or past the
  one it opened at: `charDB.battled` keeps the highest such level, so the next battleground to open brings the next
  line. Its place is the nearest battlemaster of the player's side the data has (CMaNGOS `battlemaster_entry`, whose
  `bg_template` is the BattlemasterList ID the API gives); Darkspear Islands has none, so its line is text only.
- **The Battlegrounds card.** Opt-in: *Battlegrounds* in the cog, per character, off by default. The card is the
  newest open battleground the data places a battlemaster for and the player is interested in (the chosen one while
  it is open), titled by the client's name, "A battleground open to you", with one step, "Battlemaster in
  Crossroads" ("Queue for Warsong Gulch"; `kind = "battlemaster"`, key `battlemaster:<npc>`, no quests), which combat's
  cheap rebuild keeps. It is a diversion (R4) as new as the level the battleground opened at, after the dungeon on a
  tie; the chosen one keeps its slot. A new card's moment reads "Arathi Basin is open to you". The stock queue is
  never opened: Forever has no `TogglePVPFrame` (R5).
- **The next rank's reward (#28).** For a character with rank points (major faction 2800, Camelot's
  `PVPRankFrame.lua`): "Rank 7 · <description>" with the reward's own icon, for the next rank with rewards and the
  first of them with a description, as the character pane's next-reward rows show them. The icon is a texture, so an
  aside may give `texture`, drawn in place of its atlas. No probe reached `GetMajorFactionProgressionInfo`: without it,
  nothing shows. Asked again on `PLAYER_PVP_RANK_CHANGED` and `MAJOR_FACTION_RENOWN_LEVEL_CHANGED`.

### 2.16 Professions (roadmap #9)

Only where to go next: SkillUp Forever keeps recipes, skill-up colours and its levelling route. `Hints/Profession.lua`,
after `Asides.lua` in the TOC, registers the profession aside, after the class trainer's. `Model.Profession` gives the
first of these the player still wants:

- **Rank cap.** A learned line at its rank's cap whose next rank they can train now: "Your Mining has reached 75 of 75
  · Journeyman training in Durotar". The cap is C_SkillInfo's `maxRank`; its rank is the cap over 75 (CMaNGOS
  `Spell::EffectSkillStep` sets the cap to 75 times the rank), and a cap off that scale says nothing. The next rank
  must be one a trainer teaches (`Data.professions`: Expert Cooking and Fishing come from books, so 150 of 150 says
  nothing) and the player must have the level and skill its rank spell asks (`npc_trainer` reqlevel, reqskillvalue).
- **Free slot.** Fewer than two professions (C_SkillInfo's `skillLineCategoryID` 11; two is CMaNGOS
  MaxPrimaryTradeSkill's default) while one they lack is one they can learn now: "A profession slot is free ·
  trainers in Crossroads", at the nearest trainer of any such profession's Apprentice rank.
- **Secondary skill.** First Aid, Cooking or Fishing not learned, once the player has its Apprentice level: "You can
  learn Fishing in Crossroads", the name from the data (English) since the client names only learned lines.

Each goes to the nearest trainer of the player's side who teaches that rank (`Data.npcs` `ranks`), by the route's
cost (§4.1), with the minimap's `profession` mark (CSV:1322). A rank only the other side's trainers teach (Artisan
Fishing is Katoom the Angler's, Horde) is no nudge; with no place for the player the line is text only ("Journeyman
training is open to you", "A profession slot is free"). The keys are `profession:<skill>:<rank>` and
`profession:slot`. `SKILL_LINES_CHANGED` asks the providers again a frame later, only when a profession line's rank or
cap, or the count of professions, moved; a weapon skill-up asks nothing. SkillUp Forever has no public API (its
`NextRanks` is local to its Route.lua), so AGF reads its own copy of the CMaNGOS trainer rows; `IsSpellKnown` on the
rank spells is not needed, since the cap already says which rank is known.

### 2.17 Rest and pacing (roadmap #11, #24)

- **Rest at the inn (#11).** State reads `GetXPExhaustion()` (0 when nil), `UnitXPMax("player")` when the client has
  it, and `IsResting()`. Rest is low under one bubble (a twentieth of the level's XP: a night at an inn), or at none
  when there is no bar to measure by; never at the cap, and never when the rest is unknown (a spec's player, so the
  goldens keep their reasons). Then each journey's last stop whose town has an innkeeper of the player's side
  (`Data.npcs` `inn`: its hub, or within 100 yards) reads "Rest at the inn here" in place of its reason; its detail
  stays. It is a reason, never a step, so it moves no route. Resting (an inn or a city) ticks it off, and the stop's
  own reason is back. `PLAYER_UPDATE_RESTING`, `UPDATE_EXHAUSTION` and `PLAYER_XP_UPDATE` are registered by
  feature detection and rebuild only when low or resting flips. Combat's cheap rebuild keeps the last build's line.
- **Hint strength (#24).** One account-wide setting, "Wanderer: name places only" (`wanderer`, off: Guide). A wanderer
  gets the same cards, steps and asides, which already name places ("Lakeshire, Redridge"), and is never taken
  there: `Integrations.Navigate` and `Restore` set no waypoint and hand Shortest Path nothing, `StartRoute` starts
  nothing (and waits for nothing in combat), Pins draws no rings or givers (the open guide's preview included), and
  no menu offers Go or tooltip a click line. Choosing a journey still chooses it. Turning it on stops what Go started,
  as Stop does.

### 2.18 Choice: dropping and adding quests

The player steers the route a quest at a time, per character, and the guide only ever advises.

- **Not this quest.** A step's menu (§2.8) has "Not this quest": one button for a stop with one quest, else a
  submenu naming each. It saves `charDB.notInterested["quest:<id>"] = {title}`, the store "Not interested" uses, so
  "Skipped (n)" counts it and "Show again: <title>" brings it back. A dropped quest is never a pickup, never a
  hand-in or objective step and never counts towards a card; it stays in the log, since the guide never abandons.
  Trainer and battlemaster stops have no quest to drop.
- **Adding a quest.** A shift-click on a quest giver's "!" or on an open search result (§2.4) adds its quests
  (`charDB.pinned[id] = true`); a second shift-click takes them off. Their tooltips say which it will do. An added
  quest skips the lap's filters (a timed or event quest, an objective the data does not place) and the ratio cut, so
  it is on the route whenever it is eligible; eligibility and the orange/red rule (§4.1) still apply. So a shift-click
  never adds an orange or red quest: a giver's leaves those out, and such a search result offers none. One on the
  story's map joins the story; one elsewhere is on Loose ends, within the log's room. A search result it added
  wears the tradeskill favourite's star (`tradeskills-star`). Dropping a quest takes it off; adding one forgets a
  drop.
- **Log-full note.** With 2 or fewer free slots in the log, the first card's line 3 reads "Log nearly full: N you
  could drop", and its tooltip lists them under "To make room in your log, you could drop:". They are the log's
  unfinished quests the data knows that are dropped, grey, placed nowhere the data has, or on another continent.
  Advice only: nothing is abandoned, and a finished quest is never listed.

### 2.19 The Adventure Guide window

The guide on its own, away from the world map, for a player who wants the whole picture without the map open.

- **Frame.** `PortraitFrameTemplate`, 800 by 496, the compass in the portrait, titled "Adventure Guide" with
  "<zone> · level N" under it. An `InsetFrameTemplate` from (4, -60) to (-4, 5) holds `UI-EJ-Classic`. It is
  movable, clamped to the screen, closes on Escape (`UISpecialFrames`) and keeps its place and tab in
  `db.window`. No search box: the map tab's search stays where the quests are.
- **Opening.** `/agf` or `/agf window`, a left-click on the addon compartment (a right-click opens the map tab as
  before), the expand arrow in the map tab's header, and the key binding (`Bindings.xml`). Shift-J is set once per
  account, only when nothing uses it and the addon has no key yet, out of combat, and saved to the current binding
  set with a chat line saying so; a player who clears it is never offered it again.
- **Tabs.** `PanelTabButtonTemplate` under the frame; a tab is one `Window.AddTab{key, label, Build, Refresh,
  Muted}` call. A tab with nothing to show keeps its place and stays clickable, its label grey and its tooltip
  saying why.
- **Today.** Up to four asides (§2.9 onwards) along the top of the inset, each a ring and its line, clicked and
  right-clicked as on the map tab. With five or more, three chips and a stock `UIPanelButtonTemplate` "+2 more" in
  the last slot, whose context menu lists the rest; an entry goes where its chip would, greyed when it has no place.
  Setting your hearth is one of them (Hints/Hearth.lua).
- **Session.** A stock `WowStyle1DropdownTemplate` at the steps' top right: No limit, 15, 30 or 60 minutes, as
  radios under "Time for this journey". Session.lua trims the route to the whole tasks that fit; under the steps
  "About 25 min" (only when it has an estimate), and "No complete task fits this session." in their place when
  none does. Only the chosen journey has a session.
- **Go to entrance.** A dungeon card's button beside *Show on Map*, sending Tweaks Forever's entrance for its
  instance to Shortest Path or the waypoint. Greyed, with the reason beside it and in the tooltip, when Tweaks
  Forever is missing or too old, or has no entrance for the instance. It never changes which quests the card offers.
- **Journeys.** The overview (§2.1) at the window's size: the first card featured over its zone's map with the
  "Suggested" tag, its counts, a bar only when there is progress, and *Show on Map*, which picks the card as a
  click does, starts or resumes the route, and opens the map on step 1; its next three steps beside it; up to four
  other cards in a row below. Clicks and tooltips are the map tab's, through the same `ns.Choose`, so both show
  the same route.
- **Professions.** SkillUp Forever's `API.Professions()` (version 1 or later), read through `Integrations.lua` and
  copied, never written. One profession at a time, the picker's rings at the top right when there are two or
  more: its recipe art, rank to cap with the bar, the next five recipes in their difficulty colour with what they
  cost to train, its next three steps (a click asks SkillUp for the waypoint when it has one) and up to eight
  reagents, then *Open Recipes*. Without SkillUp the tab reads "Your next skill-ups come from SkillUp Forever.
  Install it and they show here."; with an older SkillUp it asks to update it; with no crafting profession it says
  there is none to level.
- **PvP.** Over the battleground queue's own art for your side: your rank's badge, "Rank 2" (or Unranked, or
  "Highest rank reached"), the rank points bar and the next reward, as the character pane's rank tab reads them. On
  the right every battleground open at your level, with the nearest battlemaster of your side; a click goes there,
  and one the data has no battlemaster for says so and goes nowhere. No honour, match count or queue time: the
  client gives none.
- **Completion.** Legacy Forever's API (version 1 or later) for your zone and the next ones on your journeys, at
  most four: the zone over its map with each category's count ("Flight paths 2/2 · Account" ticked when done),
  pending counted apart and never as done, the overall bar, its next three objectives (a click asks Legacy for the
  waypoint; one with no place says "Location unknown"), and the other zones as cards that feature on a click.
  Without Legacy the tab stays, greyed, and says to install it; an older Legacy, to update it. Subscribed only
  while the window is shown.
- **Cost.** Built on first open. While hidden it listens to nothing and redraws nothing; shown, it redraws on the
  route, the asides, Legacy's changes and the few profession events, once a frame at most.

### 2.20 Your order

The suggested order is distance (§4.1), but the player can change it for the chosen journey.

- **Moves.** Right-click a step (map tab or window) for *Do this next*, *Do this sooner* and *Do this later* after
  the step menu, each greyed where Order.lua says the route would break (a hand-in before its pickup, past the log's
  room). Or drag a row onto another with the stock move cursor: rows it can't land on dim while the drag lasts, and
  a drop there does nothing. Row tooltips end "Drag to change the order".
- **Showing it.** The chosen card's tag reads "Your order" in place of "Suggested", and "Back to suggested order", a
  small gold text button under the steps (over them on the map tab) and the last menu entry, shows only while the
  order is yours.
- **Town checklist.** A town's row lists its givers under it, a line each ("Thork: pick up 2, turn in 0"), ticked
  with the tracker's check once done and faded when skipped. *Skip this giver* in the town's menu skips one still
  open for this visit.
- **Kinds.** Each step's ring carries its kind at the lower right, the map's own marks: "!" for a pickup (or a town
  with any), "?" for a hand-in, the objective mark, the tracking menu's trainer and battlemaster.
- **Revisits.** A place the route comes back to keeps one map ring, numbered for its first visit, with "+1" at its
  corner and a "Stop 5: Ratchet, The Barrens" line a visit in its tooltip.

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
| Card titles | `Loose ends` · `Westfall story` · `Head to Darkshore` · `Your calling` |
| Card sublines | `3 quests ready to hand in` · `Chapter 2 of 4` · `Chapter 2` · `11 quests near your level` · `2 quests for your class` |
| Reasons | `Your class trainer has a task: Call of Earth` · `A task for your class: Call of Earth` · `Continues a story you started` · `3 quests will soon turn grey` · `A chain begins with Gryan Stoutmantle` · `Sentinel Hill needs hands` · `Begins a new story` · `Ready to hand in` · `For level 14` · `Opens the next chapter here` |
| Card line 3, tooltip | `Lakeshire, Redridge and 2 more stops` · `Lakeshire, Redridge and 1 more stop` · `1 needs a group` · `3 need a group` · `Log nearly full: 3 you could drop` · `To make room in your log, you could drop:` |
| Hub stops | `Lakeshire, Redridge` · `2 to hand in, 4 to pick up` · `Marshal Marris, Verner Osgood and 2 more` · `Guard Parker, Redridge Mountains` · `And 3 more` |
| Travel | `Fly to Sentinel Hill · 6 min` · `Boat to Auberdine · 2 min wait` · `Fly to Astranaar · new flight path` · `About 4 min away` · card: `6 min` · `15 min by boat` · `15 min by zeppelin` |
| Why-not | `Requires level 14` · `Completed: The Forgotten Heirloom` · `Requires one of: A, B` · `Horde only` · `Warriors only` · `You chose X instead` · `The guide can't tell where this starts` · `You've done this` · `In your quest log` · `Repeatable quests aren't suggested` |
| Tracker | `Where you left off: finishes a story` · `Next: The Ruins of Stardust` · `Story complete` |
| Asides | `Visit your class trainer in Stormwind · 3 new spells` · `Visit your class trainer · 3 new spells` · `Riverglades · For levels 36-44` · `You haven't seen Thorn Hill yet` |
| Trainer stop | `Train in Stormwind` · `3 new spells` · `1 new spell` |
| Buttons, menu | `Go` (menus only) · `Stop` · `Show quest` · `Skip for now` · `Not this quest` · `Not interested` · `Skipped (2)` · `Show again: <title>` · `Choose another journey` |
| Instructions | `Click to travel with Shortest Path` · `Click to set a waypoint` · `Click to choose this journey` · `Click the back arrow to see all suggestions` · `Shift-click to add it to your route` · `Shift-click to take it off your route` · `Replaces your current journey.` |
| Dungeon, way in | `2 of your quests end inside Wailing Caverns` · `1 of your quests ends inside Wailing Caverns` · `The way into Scholomance` · `The way into Scholomance is open to you` |
| Empty | `The guide has no journey for you here; look for the "!" over quest givers.` |
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
| 18 | Discovery hint: one unexplored area named as text | Could | Built as roadmap #13 (§2.11) from `C_MapExplorationInfo` and the map's overlays, with no LegacyForever API. Text only, never a ring. |
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
  - less when every quest is optional (more than two levels up, elite, or in an instance);
  - a stop with no quests is worth what its kind says: a trainer's, one hand-in.

  The order itself stays on travel alone. Within a stop, hand-ins come first, then grey risk, then closeness to the
  player's level.
- **Orange and red.** A quest three or more levels up (the stock orange or red) is never a pickup, though its
  minimum allows it: too hard alone. At 19, Missing In Action (25) waits in a Blackrock camp. The map's
  quest-giver "!" still shows it, as the game does.
- **The player's choices (§2.18).** A dropped quest is never a candidate. An added quest always is while eligible:
  it passes the lap's filters and the ratio cut, but not the orange/red rule or the log's room.
- **Unchanged.** A quest whose eligibility the data cannot establish is never a candidate, and every step keeps
  the data's coordinates.

### 4.2 Laps

Card 1 and the chosen card are routed as a player running a guide goes (`Model.Laps`); every other card keeps
Build's route, so a rebuild stays inside its frame budget.
- **A lap.** Pick up in town, clear the objective areas out one side of it, come back and hand in: about a quarter
  of an hour's travel and work. A lap takes up a new quest only when no script or timer ends it and the data places
  each of its objectives; one worth less than half its town's XP per yard waits for a later lap. A finished quest
  handed in within half a lap of the lap's town comes along from a later lap, except that the lap the player stands
  in (its area leads) takes a hand-in-only stop only when it adds no more yards there than to its own lap: in
  Duskwood's worg ground the lap goes on west to Lars, not east to Darkshire and back first.
- **Checked in order.** A quest's objectives never come before its pickup, its hand-in never before all of them, and
  the log never goes past the client's limit.
- **Steady.** Each card's order is committed for the session (`route.orders`): its lap goes on until it ends, and a
  fresh order replaces it only when it saves 15% and 200 yd.
- **Entry point.** An objective area's step points where the route enters it, not at its middle: on the edge of its
  nearest part (an area is the union of its places' circles), 10 yd in, facing the previous stop or the player.
  A long, thin area is entered at its near end.
- **You're here.** The town (within 100 yd) or open area the player stands in leads: inside one of its shapes, the
  data's objective circles, not a ring merged round them. Standing in step 1's area, nothing guides to it: no
  waypoint, and Shortest Path is handed only the stops after it, so its line from the area to step 2 and its dots on
  through the rest still show, numbered from 1. Without Shortest Path the later stops keep their numbered rings.
  The whole route is handed again once the area is done or they walk 30 yd out of it. Step 1 has no travel line
  then: they are there.

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
| LegacyForever (formerly LegacyHere) | none | It has no public API (origin/main ea0fb8c; the PROBE `legacy` scan shows only `LegacyForever*` mixins and DB). Its data has 0 quest criteria (siblings.md §3), so no quest can be honestly tagged, and percentages are Legacy's domain. Could #18 needed none: the client's own exploration API serves it (§2.11). |
| TweaksForever | `TweaksForever.API.TrainableSpells()` (TF PR #45, `version = 1`), for Should #19 and the trainer stop (§2.12) | Returns fresh `{spellID, name, level, cost?, line, lineID}` tables for the trainer spells the player's level allows and they haven't learned, or nil before login and in combat. AGF checks `type(api.TrainableSpells) == "function"` where it uses it, and treats nil as "no step this rebuild". The zone table is still baked at generation time (siblings.md §4); `DungeonEntrance` is needed only for Could #17. AGF never re-sorts the stock tracker, which TF's "Nearest quests first" owns. A public `DungeonEntrance(mapID)` is a follow-up (plan §7.5). |
| WorkOrdersForever | none | It messages agents, and has no gameplay data or API. |
| SkillUpForever | none | It has no public API. The profession aside (§2.16) names only the next rank's trainer, a free slot and an unlearned secondary skill, from AGF's own CMaNGOS trainer rows; recipes, skill-ups and levelling routes stay SkillUp's. |

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
11. With no journey chosen the tab is the overview: the header reads "<zone> · level N" under its title, every
    aside shows, the first card is featured ("Suggested", its counts with the "?" and "!" marks) over its first 3
    steps as small numbered rows, and the others sit two across under a divider, with no chapter squares. The first card's rings are on the map and its step 1 in the
    tracker, and nothing guides; the tracker title or a ring's click chooses that card and starts its route.
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
16. Hovering the shown journey's next stop's giver adds "Adventure guide: <title>" under the stock unit lines
    (in combat too, with no taint logged); another NPC and a player add nothing.
17. Something new (§2.13): a level-up that brings a new next-zone card glows "<Zone> is now for your level" once,
    with the tab and compartment pips; opening the tab clears both, the card's mark stays until it closes. A login
    or `/reload` never glows.
18. QuestieDB (§2.14): with it loaded, `/agf audit` names "QuestieDB <version>" a few seconds after login with no
    hitch, and the cards, rings and town stops match the bundled run; with it disabled, or Questie alone without it,
    the audit names the bundled data and why.
19. Not interested (§2.8) on the chosen journey, then `/reload`: the cog's "Skipped (1)" → "Show again: <title>"
    brings its card back chosen, with its steps; on a journey that was not chosen it only brings the card back.
20. Breadcrumbs (§2.4): a level-10 orc shaman in Durotar is offered Call of Fire at Searn Firewarder; searching "Call
    of Fire" ticks "Only until you take Call of Fire", and once Kranal Fiss's Call of Fire is in the log the
    breadcrumb's pickup leaves the route and its line turns red. With QuestieDB, a level-12 paladin is offered Tome of
    Divinity at the class trainer.
21. Raids (§2.1): a level-60 character on Yojamba Isle with Dungeons on sees no Paragons of Power pickup on any card.
22. Talent points (§2.11): a level that brings a point shows "You have 1 talent point to spend" above the cards and
    in the tracker, with the talents book and no ring; spending it removes the line at once; after Skip for now, the
    next level's point brings it back. Confirms `GetNumUnspentTalents` counts Forever's points (R5 read 0 at 19).
23. Battlegrounds (§2.15): at 10 or more, "Warsong Gulch is open to you" with the battlemaster mark, and its click
    goes to the nearest battlemaster of your side. Entering a battleground ends it for good (`IsInInstance` naming
    "pvp" there is unprobed). *Battlegrounds* in the cog is off; ticked, with the card chosen, the step rings the
    battlemaster, and unticking hides the card but keeps the choice. At 30, "Darkspear Islands is open to you" is
    text only; Battle for Blackrock and Battle for Gilneas never show.
24. PvP rank (§2.15): a character with rank points sees "Rank N · <reward>" with the reward's icon, matching the
    character pane's next-reward row; one with none sees nothing, and no error shows where
    `C_MajorFactions.GetMajorFactionProgressionInfo` is missing.
25. Professions (§2.16): `C_SkillInfo` reports professions and secondary skills by their base SkillLine IDs (186
    Mining, not Forever's 2946), with `maxRank` 75/150/225/300 and `skillLineCategoryID` 11 for a profession. A
    character with Mining at 75 of 75 and level 10 sees "Your Mining has reached 75 of 75 · Journeyman training in
    <town>" with the profession mark, above the cards and in the tracker; its click goes to that trainer, and
    learning Journeyman removes the line without a `/reload`. A character with one profession sees "A profession
    slot is free · trainers in <town>"; one with two professions and no Cooking at level 5 or more sees "You can
    learn Cooking in <town>". Skip for now moves on to the next at once; a weapon skill-up changes nothing.
26. Unexplored nearby (§2.11): in a zone with an area not yet explored, "You haven't seen <area> yet" shows with the
    compass and no ring, in the client's name for the area; discovering it replaces the line with the next area, or
    removes it, without a `/reload`; Not interested ends every area. `/dump C_MapExplorationInfo.GetExploredMapTextures`
    on a map never visited returns nothing (not every overlay).
27. New lands (§2.11, level 36-44 only, so after launch): a character in range who has never been to Riverglades sees
    "Riverglades · For levels 36-44" with the flight master mark; Go routes to Rog'mar (Horde) or Farholde Keep
    (Alliance); entering Riverglades removes it, and it stays gone after leaving. A character below 36 never sees it.
28. Dungeons (roadmap #15): with Wailing Caverns quests in the log and Dungeons on, its card reads "N of your quests
    end inside Wailing Caverns" in the client's name for it, and no Group Finder button shows.
29. No next zone (roadmap #21; the level cap is above the beta's 30, so after launch): at 60 with Dungeons off, the
    guide shows a dungeon card and, where a chain goes inside, "The way into <instance>" as a story with its chapter;
    choosing either routes to its givers, and once its quests are all taken up the choice ends instead of waiting on
    the toggle. A new one glows "The way into <instance> is open to you" once. With nothing at all, the guide says to
    look for the "!" over quest givers.
30. Rest (§2.17): with little rested XP, a route whose last town has an inn ends "Rest at the inn here" on its
    ring's tooltip, and in the tracker once that stop is next; stepping into the inn clears it without a
    `/reload`, and no Lua error is logged at login (the rest events are registered by feature detection). `UnitXPMax`
    and the three events were never probed on Forever: with any missing, the line shows only at no rest at all, or
    waits for the next rebuild.
31. Wanderer (§2.17): turning it on in Settings stops a running route and clears AGF's waypoint; then choosing a card,
    the tracker title and an aside's click set no waypoint and no Shortest Path route, the map shows no rings or
    givers (guide open or not), and no menu has Go. Turning it off brings them back.
32. Choice (§2.18): a step's right-click "Not this quest" takes the quest off the route and leaves it in the log;
    "Skipped (1)" → "Show again" brings it back, also after `/reload`. Shift-clicking a "!" giver (pins and givers
    on) or an open search result adds its quests (the result wears a star) and a second shift-click takes them off;
    one in another zone shows on Loose ends as "1 you added". With the log two short of full, the first card reads
    "Log nearly full: N you could drop" and its tooltip names them; nothing is abandoned.
33. More choices (§2.2): a level-19 Alliance character in Redridge with its quests taken on sees Redridge's story,
    Loose ends, "Head to Wetlands" and "Head to Duskwood", and at most six cards with no empty space under them; each
    one-line row chooses its card, and the empty-panel line shows only when there is no card at all.
34. Areas (§4.2): with an objective area next, the waypoint and Shortest Path's line end at its near edge, not its
    middle, and no yellow disc covers the area: only the game's own objective mark, whose hover shows its shape.
    Walking into the area (onto its objectives' ground, not just near its middle) clears the waypoint, and Shortest
    Path's route no longer points into it but goes on from it: its line to step 2 and its dotted stops after, with
    no stop on the area; without Shortest Path, steps 2 on keep their numbers and step 1 has none. The tracker shows
    the counts. Walking 30 yd out brings the waypoint or the whole Shortest Path route back, and finishing the area
    moves on to the next stop.
35. Adding (§2.18): shift-clicking a giver whose only quests are orange or red adds nothing, and its tooltip has no
    shift line. Heading on (§2.2): at 18 in Westfall, "Head to Redridge" comes before "Head to Ashenvale".
36. Back (§2.1): with nothing chosen the header shows no arrow. Choose a card: the game's yellow back arrow shows
    left of the compass, crisp at 22 px, and lights on hover; its tooltip reads "All suggestions" and "Also stops
    the route". Clicking the lit card keeps the route running and only turns the map to it. The arrow (and, after
    choosing again, a right-click on the header) unlights the card, shows the overview again, stops Shortest Path's route or AGF's waypoint, and hides the arrow; the footer's Stop still stops the
    route as before.
37. Overview (§2.1): from the overview, clicking the second or third card lights it over its numbered steps with the
    others folded to rows above, turns the map to it and starts its route; the back arrow returns to the overview
    (the featured card and the grid again, no arrow). The previews read cleanly beside the cards (no clipping at the right edge, no
    overlap with the next card), and scrolling reaches the last card and "Skipped (n)". `/agf dump` with the Barrens
    story chosen, then `luajit tests/dump_diff.lua` on the saved variables, reports no differences.
38. Overview cards (§2.1): the renown art's rim is the same width on the featured card and the small ones (the
    slice margins hold), with no stretched corners; hovering a card lights it softly. A grid title that needs 2 lines
    ("Head to Stonetalon Mountains") wraps beside its icon and is never cut; its reason sits under it. The 7 px bar
    draws its frame and a fill matching "1 of 3 ready" (Loose ends with one quest done), and a story past chapter 1
    shows "N of M done".
39. Zone icons (§2.1): in The Barrens, Westfall or Elwynn the featured icon shows the zone's own map, round (the
    CircleMaskScalable mask, no square corners), nothing drawn outside the ring (SetClipsChildren), centred near the
    card's next town with its explored and unexplored areas alike; the ring and kind badge draw over the art, never
    under it. A city (Orgrimmar, Stormwind) or dungeon card keeps the plain ring with its kind icon centred. Opening
    and closing the tab again redraws nothing visibly (no flicker).
40. Window (§2.19): on a fresh account Shift-J opens the window, a chat line says so once, and *Key Bindings >
    Adventure Guide* lists it; on an account where Shift-J was taken, it stays as it was. `/agf`, the compartment's
    left-click and the map header's arrow open it; the compartment's right-click opens the map tab; Escape closes
    it; dragged, it reopens where it was after `/reload`.
41. Window, Journeys: the frame, the tabs and the EJ art look like the stock Adventure Guide; the featured card's map,
    rim and fade match `docs/screenshots/window.png`; clicking a lower card picks it on the map tab too; *Show on Map*
    opens the map on step 1 and starts the route.
42. Window, Professions: with SkillUp Forever loaded the card, recipes, steps and reagents fill; a step with a
    waypoint sets it; *Open Recipes* opens the profession window; the picker switches professions and remembers.
    With SkillUp disabled the tab is grey, its tooltip and the empty text say to install it, and it still opens.
43. Following the quest (§2.6, §4.2): in Duskwood with Wolves at Our Heels under way, walk onto the worgs' ground
    north of Raven Hill. The quest is selected and the map draws its blue area; the tracker has no "Walk to Duskwood"
    line; Shortest Path's way on goes west to Lars, not east to Darkshire. Walk 30 yd out: the selection clears.
    Select another quest yourself, walk in again: yours stays. Turn off "Follow the quest you're working on": nothing
    is selected.
44. Window, PvP (§2.19): the badge, bar and reward match the character pane's rank tab; a battleground row with a
    battlemaster sets the waypoint; the art matches your side.
45. Window, Completion: with Legacy Forever loaded the counts match Legacy's own window, a target click sets its
    waypoint, and the numbers change while the window is open. Disable Legacy: the tab greys, stays clickable, and
    says to install it.
46. Go to entrance: on a Ragefire Chasm card with Tweaks Forever loaded the button routes to the entrance; without
    it the button greys and the note says to install it.
47. Today: with five asides, "+2 more" opens a menu in the stock style whose entries route like the chips.
48. Session: the dropdown looks like the stock one, ticks the length picked, trims the steps, and "About N min"
    matches; a length nothing fits shows the empty line.
49. Your order (§2.20): drag a row with the move cursor, refused rows dim, the drop reorders the steps on both the
    map tab and the window, the tag reads "Your order", and "Back to suggested order" restores it. The step menu's
    three moves grey where refused. Dragging does nothing on the overview.
50. Kinds and checklist: each ring's badge sits at its lower right, as Shortest Path's stops do; a town's givers tick
    off as you hand in; a revisited town's map ring shows "+1" and both visits in its tooltip.

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
