# Design contract

These are the rules referenced by the source and headless specs. The numbered topics remain stable.

## 1. Intent

Offer a few places to go, with reasons, and let the player choose. Use the game's frames and art.
Never recommend a quest with unproven eligibility or invent a destination. The guide never accepts or
abandons quests.

## 2. Surfaces

- **2.1 Map tab.** The overview scrolls; the expand button opens the window. Chosen steps and
  search can scroll. Quest-giver marks and route pins are opt-in.
- **2.2 Journey cards.** Offer every eligible journey for the current level; the home view scrolls and the window grid
  pages through them. The home view groups its cards under collapsible quest log headers, in order: Continue (the story,
  Quests in your log and your calling), Zones for your level, Dungeons, then Battlegrounds. A group with no card draws
  no header, each header remembers its open state per character, and the header holding the route the guide follows
  stays open. Prefer useful green/yellow quests; exclude orange/red pickups. A choice shows up to ten route actions,
  followed by upcoming quest entries when fewer actions are available. The active route appears above alternative
  destinations.
    One level preference ranks both a zone and the quests in a stop (`Model.LevelPreference`): at the player's level and
  one or two below costs nothing, each level above costs twice its distance, and each level further below costs one, so
  content near the player's level beats content above it and deep green content falls behind. A zone's last level is
  ranked the same way, which costs nothing while the player is inside its range: a zone that still has takeable,
  experience-giving quests stays on offer rather than being buried by the zones that reach higher, while a zone the
  player has long outgrown does not ride one near-level quest past a zone that fits.
    Give each card a reason and only known travel estimates.
- **2.3 Chapters.** Show a total only for a proven chain. A quest tooltip may name its proven next chapter with its level.
- **2.4 Search.** Share eligibility checks with the planner. Explain missing requirements; locked
  quests offer no destination.
- **2.5 Tracker.** Show the current and next step beside quests. Leave the stock quest order alone.
  Quest tracking is opt-in; a step's quest opens on the map only outside combat.
- **2.6 Pins.** Draw only known locations and step aside while Shortest Path supplies guidance. While the player
  stands in the current step's objective area, the world map shows that area's full outline in yellow, the minimap
  turns the game's own quest area gold, and the step's own pin and line step aside.
- **2.7 Completion.** Announce a proven story ending once, using the game's tracker glow and sound.
- **2.8 Menus.** Share step actions between the guide and tracker.
- **2.9 Tooltips.** Explain visits and quest difficulty. Town checklists tick completed givers;
  repeated visits share a map ring.
- **2.10 Lifecycle.** Keep the chosen journey through rebuilds, travel and reloads. Resume paused
  guidance explicitly. Stop clears only owned guidance; a moved waypoint survives. The current stop's
  objective title stays in sync with Shortest Path; text changes in passed stops do not restart them.
- **2.11 Asides.** Keep hints separate from routes. Unknown locations remain text only.
- **2.12 Trainers.** Use known spells and trainer locations; add a stop only when the route passes.
- **2.13 New suggestions.** Announce new offers quietly after a level or zone change, never by opening UI.
- **2.14 QuestieDB.** Enumerate the compatible provider's complete composed quest catalogue after
  Questie's ready callback (policy corrections precede reads). The composed catalogue is kept in the
  character's saved data and reused while QuestieDB's version and flavour, this addon's version, the client
  build, the locale and the character's class and faction all match; any other value rebuilds it, a saved
  catalogue that fails its shape check rebuilds it, and live Questie policy is never saved. No bundled-ID,
  giver or objective whitelist;
  provider absence/failure publishes no partial or fallback quest list. The game owns progress and live POIs;
  QuestieDB owns records, spawns and XP; the live log owns objective counts. Provider objective icon fields are never treated as counts. Questie's IsDoable policy, plus minimum/maximum
  level and guide difficulty preferences, gates pickups. Without live policy, logged quests remain browsable
  but new pickups are not recommended. A place's town is the named area of its map that holds it, one of the areas the
  world map reveals as you explore (WorldMapOverlay; among overlapping rectangles the nearest centre wins), and a place
  in no area, a city map, an instance or a gap between rectangles, belongs to its map itself. A town's name is the
  area's, or the map's for a map-level town, in the client's language, with the bundled English name as the fallback.
  Two places are the same town exactly when they stand in the same area of the same map; no radius, cap or reach enters
  the rule.
  Trainers, battlemasters and innkeepers take their place and side from QuestieDB's NPC rows, and an innkeeper
  is QuestieDB's flag. Only what a trainer teaches is bundled. Map geometry and transport metadata are separate
  data sources.
  Questie owns background markers whenever loaded, including its visibility toggle; AGF owns route markers.
- **2.15 PvP.** Offer only battlegrounds open at the player's level; journey cards are opt-in.
- **2.16 Professions.** Suggest only training the player qualifies for. Crafting routes come from SkillUp.
- **2.17 Pacing.** Rest and hearth hints advise. Wanderer mode chooses without starting guidance.
- **2.18 Choices.** Dropped quests stay in the log. Added quests still pass eligibility checks.
  Skips are reversible; a full log gets advice only.
- **2.19 Window.** Share the map's choices. Optional tabs use sibling public APIs and explain missing
  providers. Assign Shift-J once, only if neither it nor the window already has a binding.
- **2.20 Your order.** Reordering must preserve quest dependencies. Suggested order remains recoverable.

- **2.21 Dungeons.** A window tab below the shared Today strip, with a level-sorted dungeon list, featured
  header and Quests / Prep pages. The list groups dungeons, the announced Forever raids, then
  the client's other raid instances, each raid row tagged with its group size; the raid tier and sizes come from
  `Integrations/Raids.lua` (docs/dungeon-sources.md), never from a copied Classic attunement page. Remember the instance Map.ID in window state. Plan to run
  selects the existing dungeon journey and enables the existing dungeon preference; no parallel plan state.
  Journey cards link back to the dungeon page. A dungeon the guide offers is pinned at its entrance on the world
  map; that pin, the dungeon's Maps control and the Maps tab all open the same interior view, whose floor dropdown
  is the game's own control and returns to the floor last chosen in the session. Without that optional source the
  entrance pin and the selector are absent, and nothing errors. Build on first show, slice source reads at 1 ms,
  cancel on hide, reuse visible rows, and cache a complete optional-source snapshot until the quest data changes.

  Quest statuses use `Model.Eligible`; completed and accepted quests are identified separately. Known faction, race and class exclusions are omitted from quests, Prep and expanded prerequisites.
  A faction-only empty page explains why. Other unproven requirements remain visible as Locked, without a
  pickup recommendation. Expanded steps show prerequisites, including
  alternatives, with no claim that every alternative is required. Only proven giver coordinates are navigable,
  revalidated on click through Integrations. Explicit map actions set the existing SPF/native route, open the
  destination zone with C_Map.OpenWorldMap and play the stock map ping twice. Combat skips opening or
  changing the map but retains navigation. Journey/step map actions and other explicit place buttons share
  the reveal helper; automatic route maintenance never opens panels. Matching AGF pins flash on click and
  glow on map-control hover, with the corresponding row highlighted. Explicit giver navigation is available for locked and earlier quests;
  Map controls are hidden without coordinates. Wanderer mode disables them with an explanatory tooltip. Quest experience uses the planner's level adjustment, counting
  accepted quests and chains provable at the current level, excluding completed quests and counting exclusive
  alternatives once. Unknown experience contributes nothing. Recommended levels use a valid client LFG range, falling back to
  the generator's published Classic dungeon ranges; sorting and every list subtitle use that same range.
  Entry requirements stay in the header and Prep. Enemy-capital entrances remain browsable, marked Hostile and excluded from automatic level-fit selection.
  Other range text uses the client's quest difficulty colour for the
  nearest level in the range, with a tooltip explaining yellow, orange/red and green/grey. Titles remain white.

  Prep derives outside pickups and prerequisite chains from quest records. Each generated entrance keeps its
  level, alternative items, completed-quest gate and unsupported-condition flag. Teleport destinations are inside
  the instance and are never used as outdoor waypoints. QuestieDB's Forever entrance points supply those,
  with Tweaks Forever as the fallback. Door keys absent from
  these sources are not invented or described as unnecessary.

  QuestieDB is read only through QuestieSource's contract-checked runtime layer. Nothing derived from it is
  shipped. The quest detail reads reward `questRewards` and objective text from that layer as one sliced
  snapshot; a quest with no catalogue text falls back to the accepted quest's client log, and unknown item
  data contributes nothing. Neither a missing source nor an empty catalogue invents an objective or a reward.
  Place names use the hub, client map name or bundled map name; an unknown place leaves the NPC alone.
  Experience uses BreakUpLargeNumbers. No internal IDs or missing-value placeholders enter player text.

  The Bosses and Loot pages belong to Adventure Guide for Classic, this addon's recommended companion for
  dungeon and raid bosses and loot. One stock button labelled Bosses and loot sits where those two tabs did
  and opens that addon's window through its public slash entry point; it is always drawn, and disabled with a
  tooltip naming the addon to install when it is absent. No boss, ability, drop-chance or loot data is read or
  bundled, and no private table of the companion is reached into.

  Top sub-tabs use TabSystemTopButtonTemplate on a common baseline; chains use the quest log's
  CollapseButtonTemplate. The header has title, location and a single meta line (entry level and positive remaining XP),
  with a stock Plan to run checkbox and padded action row inside its border. It does not repeat the list's range.
  Sub-tabs meet the content inset. Quest rows are a uniform 38 units: expand at left, title and short status
  in separate columns, giver/place below. Full titles, alternative prerequisites and unmet requirements live in
  the row tooltip; rewards and giver navigation live in the detail inset, with compact Map controls on expanded chain steps.
  Details use a header font, an Objectives heading, spaced wrapping text without an objective line cap, start/end
  NPCs (one line when identical), a Rewards heading and a proven linear chain position. The scrollable body keeps the giver button fixed at the bottom. Item icons remain square,
  tooltips use GameTooltip, and the stock divider keeps its atlas aspect.

  Client dungeon icons are square, as the game draws them; the header otherwise uses the entrance zone's
  existing map art at native aspect. Source findings and
  pins are recorded in [dungeon-sources.md](dungeon-sources.md). The layout is included in `/agf dump` and
  `docs/screenshots/dungeons*.png`, including the owner's Alliance level 19 Darkshore/Ragefire regression.
  The shared Today strip shows two wide hints, with the rest in a small stock-font More menu control on the browsing tabs. Next incorporates those hints in its recommendations instead.
- **2.22 Addon API.** `AdventureGuideForever.API` (docs/api.md) is read-only and versioned. It copies the
  tracker's step from the committed route and answers nil while a route is due, never building one for a caller.
  Fields are added, never renamed or repurposed, within a version.

### Window lists and the Journal look

`UI/WindowList.lua` is the window's one list: a `WowScrollBoxList` with a `MinimalScrollBar`, set up with
`ScrollUtil.InitScrollBoxListWithScrollBar` and `CreateScrollBoxListLinearView`. The scroll box makes a row only
for the elements its viewport shows and pools it, so no page culls rows or manages a row pool by hand.
`Window.CreateList(parent, x, y, width, height, rowHeight, paint, click, create, extent?)` returns the widget:
`create` draws a row once, `paint` fills it from an element, and `extent` measures an element that is not a plain
row height (a heading, or a step with its checklist). `Window.SetList(widget, values)` hands it the elements and
`Window.ScrollListTo(widget, index)` jumps to one. `widget.frame` is the scroll box and keeps `GetVerticalScroll`
and `SetVerticalScroll` in pixels for callers written against the old `ScrollFrameTemplate`. Pages not yet
migrated adopt the same factory.

The Journal's type and palette live on `Window` (`FONT_TITLE`, `FONT_ROW`, `FONT_HEADER`, `GOLD`, `TITLE_INK`,
`BODY_INK`). `Window.CreateSectionHeader(parent, text, onClick?)` is the paper-overlay gold header, collapsible
when `onClick` is given; `Window.CreatePaperWell(parent)` and `Window.SetPaperWell(well, lines)` are the paper
well for text longer than a row, set in the Journal's brown ink. A surface the client has no art for draws a flat
dark tile, never a question mark or a substituted picture.

### Next page

`Core/Recommendations.lua` combines the committed route and wanted hints for `UI/WindowNext.lua`. The Next tab is appended after the existing tabs to preserve their indices. A first open selects it; a valid saved tab remains selected. Focus is a per-character presentation choice, independent of the chosen journey and dungeon opt-ins.

Balanced preserves a chosen journey. Without a choice, training within 600 measured local yards can precede the offered route. Other focuses filter existing eligible offers. Up to three alternatives are visible, without padding an empty list. Text-only hints have no navigation. The selector never synchronously builds a route: pending work shows an updating state. An action revalidates its identity, destination and current step before delegating to Guidance. Combat, Wanderer mode and pending session estimates disable actions. District changes refresh hints without rebuilding the quest plan.

The wider direction and client checks are in [guidance-roadmap.md](guidance-roadmap.md).

The selected focus uses the stock button highlight. The featured card uses the destination's map art, with a dark fade behind its text; unknown locations keep the plain card. Missing quest data uses the shared source message. Entering combat immediately updates visible action buttons without rebuilding the route.

## 3. Copy

Use short, plain player language and the game's names. Unknown values stay absent. Public descriptions
follow the shared family voice.

## 4. Routes

- **4.1 Selection.** Take the nearest action at every step: the nearest town pickup, the nearest area of
  a quest the town handed out or the player carries, or the nearest ready hand-in. A ready hand-in or a pickup
  within a short walk of the player comes before a step whose own target point is farther, so the guide finishes
  what is beside the player first; once it leads it stays until it is done or the player walks clearly away.
  Group town visits and cross
  the sea at most once. This nearest order is the default; the opt-in `optimisedRoute` beta instead keeps the
  older heuristics (the story's chapter lead, a town's-own look-ahead and the committed order), which the
  player turns on from the Add-ons page.
- **4.2 Laps.** A quest's objectives follow its pickup and its hand-in all of them. Respect quest-log capacity.
  Rebuild on events;
  movement changes focus without shuffling the route. Proximity never hides or truncates guidance. Plan a bounded lookahead, then verify and merge visits before limiting the displayed actions. Keep work bounded per frame.
  An area step's point is the objective node nearest the player (a spawn group's medoid, or the generator's point
  inside the shape), so the marker sits on the work rather than on the shape's border; when the player is already
  inside the area the point stays the area's ring (its middle). The ring reaches past the shapes, so a broad area's
  ground between its objectives counts as being in it. Standing in the area step 1 leads to is "you're here":
  its in-progress quest is selected, its travel line and numbered pin go, and the route stays on it until its
  objectives are done (a merged visit takes only the objectives the player can work on now).
- **4.3 Committed order.** Preserve the chosen sequence and visit identities across rebuilds.
  Session limits use rough estimates and retain complete planned work and returns.

The guide uses `ShowUIPanel` / `HideUIPanel` by default, with `UIPanelLayout-*` attributes on its own frame only. It never registers in Blizzard's shared `UIPanelWindows` table. `floatWindow` opts into independent placement and dragging; saved floating positions remain available when switching back. Opening and mode changes defer during combat.

Tweaks can request hidden, lazy creation through `AdventureGuideForever.EnsureWindow`. The guide emits `AdventureGuideForever.WindowCreated` after building and `AdventureGuideForever.WindowLayoutChanged` after switching modes. Tweaks owns layout overrides and scale; the guide retains normal panel occupancy or floating behavior.

### Full guide outline

The Journeys card opens `UI/WindowGuide.lua`, a ten-row paged view of the active lap and the zone's remaining QuestieDB catalogue. Active route steps remain the planner's responsibility. Outline entries never become navigation targets or claim pickup eligibility. Race, class, faction, completion and dungeon/repeatable filters apply; active-chain successors and useful quest levels sort first, with prerequisites before dependents. This is an adaptive zone outline, not a fixed 1–60 walkthrough. Hiding the Journeys page closes the outline.

The Journeys window leads with the committed route's first task and its honest reason, with the journey name as context. Start explicitly chooses and starts that journey through Guidance; a running route offers Show on Map, a paused route Resume. Wanderer mode offers only Show on Map. Recommended applies to an unchosen journey; a chosen journey says Your choice. Alternative eligible journeys remain underneath.
