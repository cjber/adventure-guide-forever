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
  stays open. Prefer useful green/yellow quests; the maximum quest level slider defaults to +2, excluding
  orange/red pickups. The limit applies to recommendations, zone ranking and search recommendation eligibility; higher-level quests remain searchable, and accepted quests keep their steps. A choice shows up to ten route actions,
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
- **2.5 Tracker.** Use the chosen journey as the section heading, with Adventure Guide as the fallback.
  Show the current action and up to two upcoming actions with native action icons beside quests.
  Upcoming actions are muted and follow the resolved current stop. Leave the stock quest order alone.
  Quest tracking is opt-in; a step's quest opens on the map only outside combat.
- **2.6 Pins.** Draw only known locations and step aside while Shortest Path supplies guidance. While the player
  stands in the current step's objective area, the world map shows that area's full outline in yellow, the minimap
  turns the game's own quest area gold, and the step's own pin and line step aside.
- **2.7 Completion.** Record a proven story ending once per character and show a native-style popup with one completion sound. Tracker visibility does not affect it.
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

- **2.21 Dungeons.** Dungeon journeys share the normal planner, guide and Shortest Path integration.
  Accepted dungeon quests and available or accepted preparation chapters keep a journey visible.
  Unplaced objectives may lead to a known entrance, explicitly labelled as an entrance, never an invented objective location.
  QuestieDB supplies quest chains and outdoor entrance points; Tweaks Forever is the entrance fallback.
  The full guide lists remaining prerequisites before their dungeon quest. Future entries are an outline,
  not a pickup recommendation or navigation target. Character restrictions and completion apply throughout.
  Boss names and item drops are read from installed AtlasLoot's public ItemDB, resolving its linked tables
  and selected difficulty. Only the selected dungeon is read; visible item rows request missing item data.
  Bosses and loot sit beside the journey, with item tooltips and no strategies or models.
  Automatic interior maps belong to Tweaks Forever. AGF has no map overlay or separate dungeon browser.
  Source contracts are in [dungeon-sources.md](dungeon-sources.md).
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
when `onClick` is given; A surface the client has no art for draws a flat
dark tile, never a question mark or a substituted picture.

### Guide navigation

Journey is the default page. A compact header names the adventure and its reason, followed by route controls.
Six upcoming stops sit beside the journey's quest list or dungeon bosses and loot. Later stops are paged;
full guide shows the complete route and future prerequisites.
The current stop keeps its gold highlight as guidance advances; later stops use quieter white text.
Optional steps retain readable icons and a full-strength current highlight. Header icons identify the journey
kind, and visible route controls sit together without gaps for hidden actions.
Activities groups journey selection, professions and PvP in a left-hand list. Choosing a journey returns to
Journey, using the same choice and start preferences as the map. Progress records character story milestones;
collections, exploration and zone completion live in Legacy Forever, linked through the world map.
The shared Today strip shows useful hints once on every page. Spell training is opt-in.

`Core/Recommendations.lua` reads the committed route and wanted hints. An action revalidates its identity and destination before delegating to Guidance. Combat and Wanderer mode disable travel. Unknown destinations remain advice. The detailed contracts are in [guide-navigation-design.md](guide-navigation-design.md).

Story completion comes only from a proven final chain hand-in. `UI/StoryCompletion.lua` persists the chain head identity per character and queues an addon-owned notification independently of tracker visibility. It does not announce historical completions on login. Popup and tracker share one completion record and sound.

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

The guide uses `ShowUIPanel` / `HideUIPanel` by default, with `UIPanelLayout-*` attributes on its own frame only. It never registers in Blizzard's shared `UIPanelWindows` table. `floatWindow` opts into independent placement and dragging; saved floating positions remain available when switching back. Opening and mode changes defer during combat.

Tweaks can request hidden, lazy creation through `AdventureGuideForever.EnsureWindow`. The guide emits `AdventureGuideForever.WindowCreated` after building and `AdventureGuideForever.WindowLayoutChanged` after switching modes. Tweaks owns layout overrides and scale; the guide retains normal panel occupancy or floating behavior.

### Full guide outline

The Journey header opens `UI/WindowGuide.lua`, a ten-row paged view of the active lap and the zone's remaining QuestieDB catalogue. Active route steps remain the planner's responsibility. Outline entries never become navigation targets or claim pickup eligibility. Race, class, faction, completion and dungeon/repeatable filters apply; active-chain successors and useful quest levels sort first, with prerequisites before dependents. This is an adaptive zone outline, not a fixed 1–60 walkthrough. Hiding the Journeys page closes the outline.

The Journeys window leads with the committed route's first task and its honest reason, with the journey name as context. Start explicitly chooses and starts that journey through Guidance; a running route offers Show on Map, a paused route Resume. Wanderer mode offers only Show on Map. Recommended applies to an unchosen journey; a chosen journey says Your choice. Alternative eligible journeys live in Activities.

### Journey layout proposal

The approval concept in `journey-preview.png` shows a whole zone map beside the current stop and five upcoming
steps. It is a proposed layout, separate from the implemented UI and store screenshots. Map content and its
frame share one rectangle definition. Container artwork uses fixed eight-pixel corners, and action buttons
share a height and gap. `tools/journey_preview_test.py` checks these contracts in CI, including rejected
misalignment, stretched artwork, overflowing buttons and an underfilled step column. Visual inspection still
checks readability and composition.

Render with `WOWMOCK` configured: `python3 tools/journey_preview.py docs/journey-preview.png`.
