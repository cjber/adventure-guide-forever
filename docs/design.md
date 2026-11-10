# Design contract

These are the rules referenced by the source and headless specs. The numbered topics remain stable.

## 1. Intent

Offer a few places to go, with reasons, and let the player choose. Use the game's frames and art.
Never recommend a quest with unproven eligibility or invent a destination. The guide never accepts or
abandons quests.

## 2. Surfaces

- **2.1 Map tab.** The overview scrolls; the overview keeps two Continue cards and one card per other section until expanded. Chosen steps and
  search can scroll. Quest-giver marks and route pins are opt-in.
- **2.2 Journey cards.** Offer every eligible journey for the current level; the map overview scrolls and the guide
  pages through them. The home view groups its cards under collapsible quest log headers, in order: Continue (Quests in
  your log, the story and your calling), Zones for your level, Dungeons, then Battlegrounds. With no journey chosen the
  route follows Quests in your log, and its card leads; RestedXP guides stay selectable cards and take over only when
  the player picks one. A group with no card draws no header, each header remembers its open state per character, and
  the header holding the route the guide follows stays open. Prefer useful green/yellow quests; the maximum quest level slider defaults to +2, excluding
  orange/red pickups. The limit applies to recommendations, zone ranking and search recommendation eligibility; higher-level quests remain searchable, and accepted quests keep their steps. A choice shows up to ten route actions,
  followed by upcoming quest entries when fewer actions are available. The active route appears above alternative
  destinations.
    One level preference ranks both a zone and the quests in a stop (`Model.LevelPreference`): at the player's level and
  one or two below costs nothing, each level above costs twice its distance, and each level further below costs one, so
  content near the player's level beats content above it and deep green content falls behind. A zone's last level is
  ranked the same way, which costs nothing while the player is inside its range: a zone that still has takeable,
  experience-giving quests stays on offer rather than being buried by the zones that reach higher, while a zone the
  player has long outgrown does not ride one near-level quest past a zone that fits.
    Quests in your log also offers a few eligible quests to pick up on its way while the client's log has room: the
  giver, every objective and the hand-in all stand near a stop the route already makes, the smallest detour first, and
  no more than the free slots, a card's worth of actions less the log's own quests, or three. The route keeps the
  pickups it chose while they stay open, so walking or taking one quest up does not shuffle its head.
    Give each card a reason and only known travel estimates.
- **2.3 Chapters.** Show a total only for a proven chain. A quest tooltip may name its proven next chapter with its level.
- **2.4 Search.** Share eligibility checks with the planner. Explain missing requirements; locked
  quests offer no destination. Every word of the query must appear in the title (case and Latin accents folded); the
  best match comes first (the whole title, the title's start, the start of its words, anywhere), then a quest open
  now, then the level nearest the player's, then the title. Ten at most. A locked row whose chain can start now
  names its earliest prerequisite open now and not orange or red ("Starts with …", `Model.ChainStart`), and a
  shift-click adds that quest; the locked quest itself never becomes a target.
- **2.5 Tracker.** Use the chosen journey as the section heading, with Adventure Guide as the fallback.
  Show the current action and up to two upcoming actions with native action icons beside quests.
  Upcoming actions are muted and follow the resolved current stop. Leave the stock quest order alone.
  Quest tracking is opt-in; a step's quest opens on the map only outside combat.
  Shared objective stops use a combined heading and show each quest's live objective progress beneath it.
  Completed objectives leave the stop during combat without clearing unfinished work.
- **2.6 Pins.** Draw only known locations and step aside while Shortest Path supplies guidance. While OpenMap stitches
  the zones around the map's own onto one canvas, their route stops draw too, numbered as on their own map; givers and
  town visit spots stay on the map's own zone. While the player
  stands in the current step's objective area, the world map shows that area's full outline in yellow, the minimap
  turns the game's own quest area gold, and the step's own pin and line step aside. A town visit keeps one numbered
  stop, and every other NPC or object it covers draws a small mark at its own spot, with its name and the quests done
  there in its tooltip.
- **2.7 Completion.** Record a proven story ending once per character and show a native-style popup with one completion sound. Tracker visibility does not affect it.
- **2.8 Menus.** Share step actions between the guide and tracker. An area with more than one objective spot (each
  objective's node and its other camps on that map, AreaNode's `alternates`; standing at any of them is standing in
  the area) offers Next spot: the spot it points at is passed over for the session and the point moves to the nearest spot not passed
  over; a spot not passed over keeps the arrow through rebuilds and walking. Inside the area it passes over the spot
  the player is at (the nearest edge, since an area's spots are close and often overlap). Model.Here doesn't count
  standing at a spot passed over as standing in the area (with a switching margin), so the arrow leads on, and at a
  spot not passed over it is theirs; walking between spots rebuilds when that changes. Passing over the last spot
  starts the round again from it.
- **2.9 Tooltips.** Explain visits and quest difficulty. Town checklists tick completed givers;
  repeated visits share a map ring.
- **2.10 Lifecycle.** Keep the chosen journey through rebuilds, travel and reloads. Resume paused
  guidance explicitly. Stop clears only owned guidance; a moved waypoint survives. A town visit's arrow stays on the
  giver it points at while that giver has work, until another is 35 yards nearer; that point moving alone does not
  restart the route Shortest Path already walks. The current stop's
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
  level and guide difficulty preferences, gates pickups. A prerequisite our data layer corrects also gates the
  quest, since the live policy predates that correction. Without live policy, logged quests remain browsable
  but new pickups are not recommended. A place's town is the named area of its map that holds it, one of the areas the
  world map reveals as you explore (WorldMapOverlay; among overlapping rectangles the nearest centre wins), and a place
  in no area, a city map, an instance or a gap between rectangles, belongs to its map itself. A town's name is the
  area's, or the map's for a map-level town, in the client's language, with the bundled English name as the fallback.
  Two places are the same town exactly when they stand in the same area of the same map; no radius, cap or reach enters
  the rule.
  Trainers, battlemasters and innkeepers take their place and side from QuestieDB's NPC rows, and an innkeeper
  is QuestieDB's flag. Only what a trainer teaches is bundled. Map geometry and transport metadata are separate
  data sources.
  Questie owns background giver markers while it shows them on the world map; when its icons, map icons or
  available-quest icons are off, AGF draws its own givers under its own "Show quest givers" setting. AGF owns route
  markers.
- **2.15 PvP.** Offer only battlegrounds open at the player's level; journey cards are opt-in.
- **2.16 Professions.** Suggest only training the player qualifies for. Crafting routes come from SkillUp.
- **2.17 Pacing.** Rest and hearth hints advise. Wanderer mode chooses without starting guidance.
- **2.18 Choices.** Dropped quests stay in the log. Added quests still pass eligibility checks.
  Skips are reversible; a full log gets advice only.
- **2.19 Guide access.** The map tab, minimap button, addon compartment, Alt-G and `/agf` open the same guide. No standalone window.
- **2.20 Your order.** Reordering must preserve quest dependencies. Suggested order remains recoverable.

- **2.21 Dungeons.** Dungeon journeys share the normal planner, guide and Shortest Path integration.
  Accepted dungeon quests and available or accepted preparation chapters keep a journey visible.
  Unplaced objectives may lead to a known entrance, explicitly labelled as an entrance, never an invented objective location.
  QuestieDB supplies quest chains and outdoor entrance points; Tweaks Forever is the entrance fallback.
  The full guide lists remaining prerequisites before their dungeon quest. Future entries are an outline,
  not a pickup recommendation or navigation target. The dungeon card itself walks every prerequisite chain back to
  what the player can do now, through branches, and offers the steps that open another of its quests first, then the
  rest, before its entrance; each chain carries its label and progress, and the entrance says how many of the
  instance's quests are still to pick up. Character restrictions and completion apply throughout.
  Boss names and item drops are read from installed AtlasLoot's public ItemDB, resolving its linked tables
  and selected difficulty. Only the selected dungeon is read; visible item rows request missing item data.
  Bosses and loot sit beside the journey, with item tooltips and no strategies or models.
  Automatic interior maps belong to Tweaks Forever. AGF has no map overlay or separate dungeon browser.
  Source contracts are in [dungeon-sources.md](dungeon-sources.md).
- **2.22 Addon API.** `AdventureGuideForever.API` (docs/api.md) is read-only and versioned. It copies the
  tracker's step from the committed route and answers nil while a route is due, never building one for a caller.
  Fields are added, never renamed or repurposed, within a version; `minor` counts the additions. `Subscribe` calls
  back the frame after the stop, the journey or the status changes. Shortest Path's own `Subscribe`, when it has one, replaces
  watching the super-tracking events. `Suggestions` copies the panel's cards in the order it draws them, and
  `StartSuggestion` starts one through the same `ns.StartJourney` as the guide's Start, so another addon's menu and the
  guide never disagree.
- **2.23 Secret values.** A value the client hands over but keeps secret (a unit's GUID or token in some combat and
  instance states) is read only through `ns.Readable` (`Core/Secret.lua`), which answers nil for a secret, and a
  forbidden tooltip only after `ns.Usable` says it may be touched. A secret reads as absent: the line it would have
  fed is left out, never guessed and never an error.
- **2.24 Report.** `/agf report` shows one block of text, selected, in a stock portrait frame: the versions, build,
  locale, character and place; the guide's settings, QuestieDB, the stop the tracker shows with each quest's ID and
  Why lines; the errors caught this session; the other loaded addons. At most 2,000 characters (one message): the
  addon's lines capped at 1,000 and the errors at 600, the addon list in what is left. It reads only the committed route and never builds one. Errors are caught through one
  wrapper, `ns.core.SafeCall`, which keeps the last five and still passes each to the game's error handler. The pattern and
  how to port it are in [report-window.md](report-window.md). `/agf where`, for the Wrong stop issue form, shows only
  the versions, level, place and the guide's own lines in the same window.

- **2.25 What a giver offers.** A route pickup its giver's gossip or greeting window leaves out, and that isn't grey
  for the player, is marked not offered at the player's level: unproven, with the Why line "The giver didn't offer
  it", one quiet chat line, and off the route. A listed quest, a quest already taken or done, a window the guide
  can't read whole, another NPC's or a single quest's detail window marks nothing. A mark holds only at the level it
  was made at; a hand-in clears the marks it could open (quests that need it, and quests its ender gives).
  `Core/Offers.lua`.

- **2.26 Quests that close another.** QuestieDB's `exclusiveTo` names, for each quest, the quests whose taking
  closes it; AGF keeps those links inside each exclusive group as `closedBy`, so a breadcrumb that closes once its
  target is taken never reads as closing the target. When a giver's detail window offers a quest that would close
  another for good, one chat line names what you'd lose, once per quest a session: "Taking X closes Y for good."
  Left out: quests done or in the log, quests something else already closed (another closer, or a breadcrumb's
  target), quests the character can never take (side, race, class, repeatable, a start the data cannot place), a
  follow-up that needs another member of the group first (its lead is the loss), and other versions of the offered
  quest (the same title); each title is named once. The planner's eligibility reads the same directions: a group
  whose links carry `closedBy` closes a member only once one of its own closers is done or in the log. A quest the game took
  itself (auto-accept) says nothing. The setting `warnClosing` (on) turns it off; with Polestar's own warning on
  (`Polestar.Get("behavior.warnClosing")`) AGF says nothing, so it is never said twice. `Model.Closes`,
  `Core/Closes.lua`.
- **2.27 Group lines.** A step says why it wants a group, from what AGF already knows, one line per reason and each
  once: "Dungeon: X" or "Raid: X" for a quest filed under an instance (the client's name for it, else the data's),
  "Group of N" for an elite quest the quest log suggests a group of 2 or more for, and "Elite: group advised" for any
  other elite quest. A quest ready to hand in says nothing: its group work is done. The lines go after the reason in
  the step's tooltip (its ring and its row) and in the tracker's step block (a RestedXP step's after its checklist);
  the row keeps its group icon. `Model.GroupNeed`, `Overview.GroupNote`.

- **2.28 Reward upgrades.** A quest giver's detail or reward window marks each reward choice that is an upgrade
  with the game's own green arrow (`bags-greenarrow`, top left of the icon, as the bags draw it): an item the game
  shows usable, of the armour type the class wears at its level (cloth, leather, mail from 40 for hunters and
  shamans, plate from 40 for warriors and paladins; a cloak and jewellery take any), with no primary stat the class
  never uses, and a higher item level than the weaker worn item in the slots it would take (an empty slot counts as
  0). Weapons follow the game tutorial's rules (Blizzard_TutorialServices.lua): a main-hand weapon only for the same
  kind (two-handed or not) as the one held, nothing for the off hand behind a two-hander, and a one-hander's off-hand
  slot only with dual wield. No stat weights. The quest log's reward display is left alone. With Pawn loaded nothing
  is marked, since Pawn marks the same rewards with every stat weighed. Tweaks Forever's best-selling coin sits on
  the icon's other corner and answers a different question. The setting `markUpgrades` (on) turns it off.
  `UI/Upgrades.lua`.

### Guide navigation

The world-map sidebar is the guide. Folded sections show two Continue journeys and one journey per other
section. Expanding a header reveals the remaining choices. Existing settings from the paged overview do
not expand the new previews. Accepted quests, including the current story's quests, form Quests in your log,
the default suggested route until the player chooses a journey. This does not start guidance automatically.
Shared row art lives in `UI/Widgets.lua`.

`Core/Recommendations.lua` reads the committed route and wanted hints. An action revalidates its identity and destination before delegating to Guidance. Combat and Wanderer mode disable travel. Unknown destinations remain advice. The detailed contracts are in [guide-navigation-design.md](guide-navigation-design.md).

Story completion comes only from a proven final chain hand-in. `UI/StoryCompletion.lua` persists the chain head identity per character and, independently of tracker visibility, queues the client's own achievement toast (`AchievementAlertFrameTemplate` in a queued `AlertFrame` subsystem, with no achievement ID) headed "Story complete" and naming the chain. It does not announce historical completions on login. Toast and tracker share one completion record and sound.

## 3. Copy

Use short, plain player language and the game's names. Unknown values stay absent. Public descriptions
follow the shared family voice.

## 4. Routes

- **4.1 Selection.** Take the best action for the player now at every step, not the nearest alone: every stop that is
  work for now comes before a stop above the player's level ceiling, and within each tier the nearest action decides.
  The ceiling is the one that limits pickups: the "Maximum quest level above yours" setting, two levels up by default. A stop is
  above only when every quest the player would act on there is past that ceiling and it holds no ready hand-in; a quest
  counts as past it by its own level, or on an area step by the highest mob level (`obj[i][6]`) among that quest's spots
  the step sends the player to, so an area whose mobs outlevel the ceiling waits even when its quest does not. A town or pickup stop
  reads the quest's own level only. A
  ready hand-in, a quest within the ceiling, and a stop with no quest at all (a trainer, an entrance) are work for now. So near-level and lower-level work, and hand-ins already done, lead a quest several levels above the
  player. Then take the nearest town pickup, the nearest area of a quest the town handed out or the player carries, or
  the nearest ready hand-in. A ready hand-in or a pickup within a short walk of the player comes before a step whose
  own target point is farther, so the guide finishes what is beside the player first; once it leads it stays until it
  is done or skipped (the held step, §4.2).
  A quest whose item runs out in the bags (one the client lets last a day or less, ItemSparse DurationInInventory,
  that the quest hands over, needs or collects) goes first while the player carries one, ahead even of the area they
  stand in and of a held step: its hand-in once it is done, else its objectives, with the reason "before <item> runs out".
  Group town visits and cross
  the sea at most once. This nearest order is the default; the opt-in `optimisedRoute` beta instead keeps the
  older heuristics (the story's chapter lead, a town's-own look-ahead and the committed order), which the
  player turns on from the Add-ons page.
- **4.2 Laps.** A quest's objectives follow its pickup and its hand-in all of them. Respect quest-log capacity.
  Objective areas merge only on the same map and for the same activity kind; separate maps keep separate visits. A
  quest a lap picks up joins an area only when every quest picked up for it there comes from the same town. Current objective data does not distinguish floors on the same map.
  The step the tracker shows holds (§2.5): a re-plan from a new place, including a trip to a city to train, keeps it at
  step 1 and only reorders the stops after it, until the player finishes or skips it. With nothing held yet (a fresh
  journey, or the held step just finished or skipped), an objective area the player stands in takes step 1.
  Rebuild on events;
  movement changes focus without shuffling the route. Proximity never hides or truncates guidance. Plan a bounded lookahead, then verify and merge visits before limiting the displayed actions. Keep work bounded per frame.
  An objective's spawns form camps: 100-yard cells ranked by the spawns in and around them, so a camp across a cell's
  edge stays one camp and a lone spawn ranks behind it, up to three per slot, none beside another, each at its camp's
  medoid with a ring to the camp's farthest spawn within 100 yards. Each objective's node is its first camp in the
  data's order (its zone, then the biggest camp), passing over a harder camp for the next easier one on the same map:
  one whose mobs' lowest level (QuestieDB minLevel) is 3 or more above the player is harder, one whose mobs are all
  elites (QuestieDB rank 1 to 3) harder still, so normal mobs come first, then normal mobs far above, then elites. A
  camp with an object or an NPC without a level is never over, one with an object or a normal mob never elite, and when
  every camp is as hard the first stays.
  An area step's point is the objective node nearest the player (a camp's medoid), so the marker sits on the work
  rather than on the shape's border; when the player is already
  inside the area the point stays the area's ring (its middle). The ring reaches past the shapes, so a broad area's
  ground between its objectives counts as being in it; standing at a spot Next spot passed over does not (§2.8).
  Standing in the area step 1 leads to is "you're here":
  its in-progress quest is selected, its travel line and numbered pin go, and the route stays on it until its
  objectives are done (a merged visit takes only the objectives the player can work on now).
- **4.3 Committed order.** Preserve the chosen sequence and visit identities across rebuilds.
- **4.4 Count ticks.** A burst of quest-log events that leaves the log's shape alone (the same quests, complete flags
  and objective done flags; `Model.LogShape`) only moved counts: the last route is repainted with the live counts
  (`Model.Repaint`), every journey, order, `here` hold and choice kept, without a plan. Anything else plans in full.
  An objective whose count reaches its need is done, and a quest whose objectives are all done is complete, even
  while the client's finished and complete flags lag the count (a looted quest item reports it a tick later;
  `ITEM_COUNT_CHANGED` and `BAG_UPDATE_DELAYED` re-read it). The objective's words carry the live count too.
- **4.5 Party quests.** In a party (not a raid) with *Favour quests your party has* on (the default), a step holding
  a quest someone in the party also has costs half as much to reach, but never more than 300 yards less
  (`Model.PartyCost`, in the selection, the nearest order and the laps' walk alike). The route stays the nearest
  action at every step, so it leans towards shared work without a fixed order, and a step the player stands in or a
  ready hand-in beside them still comes first; the optimised-route beta's committed order still holds the steps it
  has (§4.3), so there only new steps lean. A pickup someone in the party has says so. The party's quests
  (`Core/Party.lua`) are what the client shows, `C_QuestLog.IsUnitOnQuest` for each quest in the player's log, and
  what party members running the guide say: one hidden addon message (prefix `AGFParty`, to `PARTY` only) carrying
  their log's quest IDs in base 36, never text. It goes out 2 seconds after the log or the party changes, at most
  once every 15 seconds, never in combat (it waits for the fight's end) and never on a timer of its own; one that
  says what the last said is not sent again unless it asks or someone asked, one the client throttles is tried once
  more, and one it refuses counts as unsaid. Joining a party, or someone new in it, asks the others for theirs once.
  Only the home party counts (`LE_PARTY_CATEGORY_HOME`), never an instance group of strangers; members are told apart
  as "Name-Realm", and a message from someone whose name the client doesn't know yet waits until it does. A sender's name is read through `ns.Readable`; a malformed
  message, another version's, our own echo or a raid's is ignored. With the setting off, or out of a party, nothing
  is sent, kept or favoured.

### Full guide outline

The map guide includes the zone's remaining QuestieDB catalogue after actionable route steps.
`UI/GuideOutline.lua` orders prerequisites before successors and filters race, class, faction and completed
quests. Outline entries never become navigation targets or claim pickup eligibility.

Dungeon choices rank by recommended level range, accepted quest count and travel to the first actionable stop.
Available quest count and instance identity break ties. Unknown ranges follow known ones. Class quests and
battlegrounds keep their unlock priority; dungeon ranking does not reorder an active route.

## RestedXP guide mode

When the optional RestedXP addon is available, `Integrations/RestedXP.lua` adapts its active steps into a presentation snapshot. RestedXP remains responsible for parsing guides, eligibility, automatic quest handling, objective completion and step progression. The Adventure tab and addon-owned tracker display that snapshot. Available guides use the existing Continue cards, ordered by their level ranges after RXP eligibility checks. A single matching chapter loads automatically when no guide is selected; imports in progress and existing selections are preserved. Guide selection and step controls delegate to RestedXP. Imports use its own importer.

`restedxpGuide` adds the active guide as an ordinary journey in Continue. Other journeys and activity hints remain available. The guide uses the existing card, selected step rows, checklist, pins and tracker. A character's selected journey is retained. Guide step order stays with RXP and cannot be rearranged by AGF.

AGF hands the current guide waypoint to SPF as `AdventureGuideForever`, held until RXP changes it. Sticky objectives remain visible without becoming future travel stops. Unknown destinations have no pin or travel estimate. SPF's direct RXP adapter defers while `AdventureGuideForever.API.RestedXPIntegrated()` is true, so Stop and route ownership stay with the existing frontend.

When RXP hides its current step from its window, the step it shows next leads and is handed on; the step under way is never a read-only preview. A guide step's walk names the NPC its lines name, else its zone when RXP gave it no title. A chosen guide waits while RXP has no guide loaded (its empty guide during a purchased-guide import, or between two loads): it is neither ended nor replaced by an auto-started journey, and a chosen guide key follows the guide RXP loads.

While the chosen guide leads and `guideTracksQuests` is on (default), `Integrations/RestedXPWatch.lua` keeps the client's quest watches to the quests in the log that the guide's non-preview steps name. The player's watch list is saved on the character when the guide takes over and given back when it stops leading. Only watches it or the client's auto watch on accept added are removed later, so a quest the player tracks or untracks by hand meanwhile stays as they left it. Questie mirrors the client's watches on Forever, so its tracker follows without being written to.

RXP active-item and target windows and its minimap icon are suppressed alongside its guide window. `UI/RXPActions.lua` draws their native-styled replacement in the AGF tracker section: a secure item button per usable item of the current step, with the client's cooldown, count, range marker and key binding, and secure `/target` macro buttons for the step's talk and kill targets, with the current target marked. Their secure frames are built, shown, hidden, moved and given attributes only out of combat, and changes seen during a fight wait for `PLAYER_REGEN_ENABLED`. Restoring the original frontend shows RXP's windows again through its own update. Its arrow is suppressed too while SPF is loaded, since SPF's arrow points at the step AGF hands it. Without SPF, RXP's arrow is the guide's only arrow and is suppressed only while another journey is chosen. The adapter does not change the player's RXP arrow preference. Native RXP windows retain their engine updates while their presentation is suppressed; restoring the original frontend restores its captured presentation state.

RXP's explicit `.ingamewaypoint` instructions can still set the native user waypoint; ordinary RXP arrow steps do not write it. If the player or another addon moves or unfocuses AGF's native waypoint, AGF forgets ownership and neither refresh nor Stop overwrites or clears the replacement. Its own automatic quest highlighting puts an already super-tracked native waypoint back after focusing the quest, whoever placed it, and never focuses one that was not super-tracked.

The integration ships original adapter code and requires the separately installed RXP addon. It does not include RXP code, guide files or artwork, export guides, or bypass its account and eligibility checks. Paid guides remain subject to RestedXP's personal-use terms. Public preview text is an original test fixture.

## Alongside Polestar

Polestar is a separate leveling guide with its own window and arrow. `Integrations/Polestar.lua` reads two things,
each feature-detected and called through `pcall`: `Polestar.Engine.GetGuide()`, and `GetStepIndex()`, since a finished
guide stays loaded with no step left. It reads them again on Polestar's `GUIDE_CHANGED` and `GUIDE_COMPLETED`
messages, or every 5 seconds where Polestar has no message bus (`Polestar.On`). An error reads as no guide. Nothing of
Polestar's is written, hooked or copied.

While `polestarAside` is on (the default) and Polestar has a guide running, the route steps aside:
`Guidance.StepAside` drops a start waiting for combat's end and stops only what Go started; Restore neither brings
back nor auto-starts a route until Polestar stops; Follow sends nothing; the map switch draws no rings or givers (the
guide window's own preview still does); and the tracker holds one line, "Polestar is guiding you", under the generic
title. Clicking the line, or starting a journey's route (`ns.StartRoute`), takes over: Adventure Guide leads again
until Polestar runs a different guide. The guide taken over from is kept per character (`polestarTakenFrom`), so
Polestar reopening it after a reload does not undo the choice, and it is forgotten once Polestar runs none. A one-off
Go (a trainer, a giver pin, a dungeon entrance) sets its waypoint without taking over. With Polestar absent or idle, or
the setting off, nothing changes.

## Alongside Waypoint UI

Waypoint UI (github.com/Adaptvx/Waypoint-UI) drives the client's own user waypoint with its own arrow, compass and pin.
`Integrations/Integrations.lua` reads its public `WaypointUIAPI.Navigation` at the point of use, since it may load after
AGF, and only while Shortest Path Forever has no usable API: with Shortest Path loaded its journey is the one Waypoint UI
already follows, and a second waypoint handed over would fight it. `SetWaypoint` gives `NewUserNavigation` the stop's
name, map and point in percent, as the API takes them; `ClearWaypoint` calls `ClearUserNavigation` only while the
navigation still sits where Go put it, so a pin the player moved is left alone. A missing function, a raise, or a map
the client allows no pin on leaves the native waypoint as the fallback. There is no setting.

With Naowh's Journeys (NaowhForever_Utilities) on and its Map Pins on, Go's native waypoint becomes that module's own journey, and a journey still headed for the place Go put down counts as the guide's guidance until it is cleared or moved (#304).
