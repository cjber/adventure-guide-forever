# Addon API

Addons can read where the guide is sending the player through `AdventureGuideForever.API` (`version = 1`). Additions
keep `version` at 1 and raise `minor` (1 from `Subscribe`, 2 from `Suggestions` and `StartSuggestion`, 3 from
`Stats`, 4 from `Leaderboard`, 5 from `Status`, `Pause`, `Resume` and each stop's quest IDs), so check that a function
exists before calling it.
The stop and suggestion queries are read-only; `ResumeRestedXP()`, `StartSuggestion(id)`, `Pause()` and `Resume()` are
explicit navigation requests. Places use uiMapIDs and
normalized 0-1 coordinates, as Shortest Path's API does.

- `CurrentStop()` returns the stop the tracker shows now, or `nil`.
- `NextStops(limit)` returns the stops after it in route order, nearest first: two unless `limit` says otherwise,
  at most eight, and an empty table at the end of the route. A `limit` that is not a whole number of zero or more
  returns `nil`.
- `Stats()` returns fresh read-only activity rows: an aggregate `quest_turn_ins` row and one `quest_turn_in` row per
  quest ID. Each row has `addon`, `metric`, `subject`, `value`, and the latest observed `eventUnix` when available.
  These are local SavedVariables. Adventure Guide does not broadcast them or assert that a record is a first for
  anyone else.
- `Leaderboard(limit)` returns cumulative quest turn-ins ranked among this character and the guild and group members
  who report theirs: `{ metric = "quest_turn_ins", scope = "guild_group", sharing, total, rows }`. `rows` holds the top
  `limit` rows (ten unless given, 25 at most) and this character's row when it ranks below them; each row has `rank`,
  `name`, `value`, `eventUnix` and `self` (true on this character's). Ties fall to the lowercase name. Values are
  what each player's addon reported, so they are neither verified nor realm-wide, and a player who has not reported
  is unknown rather than zero. With `sharing` false (the player turned it off), only this character's row is
  returned. A `limit` that is not a whole number of zero or more returns `nil`. The result is a fresh table.

`RestedXPNativeUI()` returns true while the display choice is pending or the player chose RestedXP. Navigation addons should preserve the native arrow in that case.

`RestedXPIntegrated()` returns whether the installed RestedXP engine is assigned to AGF, including before its first deferred render. Navigation addons can
use it to defer standalone RXP routing and suppress its native arrow while AGF owns the guide.

A stop is a fresh table on every call:

| Field | |
|---|---|
| `map`, `x`, `y` | where the stop is |
| `name` | the town ("Crossroads"), else the quest giver, zone or step title; for display, not for matching |
| `isTown` | a town visit, grouping its pickups and hand-ins |
| `kind` | what the stop is: `"town"`, `"pickup"`, `"turnin"`, `"objective"`, `"trainer"`, `"battlemaster"` or `"guide"` |
| `handins` | how many quests the route hands in there; agrees with `#turninQuests` |
| `pickups` | how many quests the route picks up there; agrees with `#pickupQuests` |
| `pickupQuests` | fresh ascending quest IDs the route picks up there; empty when none |
| `turninQuests` | fresh ascending quest IDs the route hands in there; empty when none |
| `objectiveQuests` | fresh ascending quest IDs whose objectives are done there; empty when none |

`nil` means ask again later: the game's quest data has not loaded, the route is being worked out, or the current
stop has no known place. The counts are what the route plans for the visit; a hand-in the route returns for later
is counted at its stop. A pickup or turn-in step that is not a town carries its quests the same way a town does.
`Subscribe` says when to read again.

- `Status()` returns `"running"` while the chosen journey's route runs, `"paused"` while it is stopped but kept,
  `"queued"` while a start waits for combat's end, `"arrived"` once it reached its last stop, or `nil` when no journey
  is chosen or nothing guides it.
- `Pause()` stops the chosen journey's route without dropping the choice, in the same paused state as a route cleared
  in Shortest Path, so the card and the tracker title resume it. It returns `true` when the journey is paused, or
  `false` while the route is being worked out or no journey is chosen. Call it for a player's action, or when another
  guide takes over.
- `Resume()` starts the chosen journey's route again as the card's Start does. It returns `true` when the route is
  running or under way, or `false` when nothing is chosen, the route is being worked out, or it cannot start.
- `Subscribe(callback)` calls `callback(changes)` on the frame after what `CurrentStop` answers, the journey the
  route follows or `Status()` changes, at most once per burst of changes and never while the route is being worked
  out. `changes` is a new table each call with one or more set to `true`: `stop` (a stop appeared, moved on, changed
  or went), `journey` (another journey, or the same one chosen or let go) and `status` (the status above changed).
  Read `CurrentStop` and `NextStops` again rather than replaying the changes. A callback added by another callback
  waits for the next burst. It returns a function that unsubscribes, safe to call twice. An error in one callback goes
  to the game's error handler without stopping the others. A non-function callback is an error.

```lua
local api = AdventureGuideForever and AdventureGuideForever.API
local function Show()
	local stop = api.CurrentStop()
	if stop then
		print(("Next stop: %s (%s)"):format(stop.name, stop.kind))
		for _, id in ipairs(stop.turninQuests) do
			print(("  hand in quest %d"):format(id))
		end
		for _, id in ipairs(stop.pickupQuests) do
			print(("  pick up quest %d"):format(id))
		end
	end
end
if api and api.version == 1 then
	Show()
	if type(api.Subscribe) == "function" then
		api.Subscribe(Show)
	end
end
```

```lua
-- Another guide taking over: pause Adventure Guide, then run your own route.
local api = AdventureGuideForever and AdventureGuideForever.API
if api and type(api.Pause) == "function" and api.Pause() then
	myGuide.Start()
end
-- Its card or the tracker title resumes it later, or:
local resumed = api and type(api.Resume) == "function" and api.Resume()
```

### `API.ResumeRestedXP()`

Resume the active RestedXP guide through Adventure Guide's navigation. Returns `true` when the request is accepted, or `false` when integrated RestedXP is unavailable. Use this for an explicit player action after selecting another destination.

## Suggestions

- `Suggestions(limit)` returns the guide's cards in the order its panel draws them: the chosen one first, then each
  header's cards (Continue, Zones, Dungeons, Battlegrounds) in the order the route offers them. Five unless `limit`
  says fewer, and never more than five. It copies what the guide has already worked out and plans nothing for the
  caller. `nil` means ask again later, as for the stops; a `limit` that is not a whole number of zero or more also
  returns `nil`.
- `StartSuggestion(id)` starts the card with that `id` as the guide's own Start does: it chooses the card and starts
  its route on the rebuild that has its steps (through Shortest Path when it is loaded, the game's waypoint
  otherwise), resumes the chosen card's route when it is paused or not running, and hands a RestedXP guide's card to
  RestedXP. It returns `true` when it accepted the request, or `false` while the route is being worked out, for an
  `id` no card has now, when RestedXP refuses its guide in combat, or when the chosen card's route could not start.
  With the guide's wanderer setting on, it chooses the card and starts nothing, as the guide's own Start does. Call it
  only for a player's click.

Read `Suggestions` when your menu opens: `Subscribe` does not call back when only the cards change.

A suggestion is a fresh table on every call:

| Field | |
|---|---|
| `id` | the card's key, for `StartSuggestion`; stable while the card is offered |
| `title` | the card's title ("The Barrens story", "Head to Ashenvale"); for display |
| `level` | the lowest level the card shows (a zone's or dungeon's range, a battleground's first level), or `nil` |
| `kind` | `"carry"` (quests in your log), `"story"`, `"nextzone"`, `"dungeon"`, `"calling"`, `"battleground"` or `"guide"` |
| `map` | the uiMapID of its first stop, where `x` and `y` are; the card's map when that stop has no known place |
| `x`, `y` | its first stop, normalized 0-1; `nil` when that stop has no known place |

```lua
local api = AdventureGuideForever and AdventureGuideForever.API
if api and type(api.Suggestions) == "function" then
	for _, suggestion in ipairs(api.Suggestions(3) or {}) do
		local label = suggestion.level and ("[%d] %s"):format(suggestion.level, suggestion.title) or suggestion.title
		-- On the player's click: api.StartSuggestion(suggestion.id)
	end
end
```
