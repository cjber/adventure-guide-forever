# Addon API

Addons can read where the guide is sending the player through `AdventureGuideForever.API` (`version = 1`). Additions
keep `version` at 1 and raise `minor` (1 from `Subscribe`, 2 from `Suggestions` and `StartSuggestion`, absent
before), so check that a function exists before calling it.
The stop and suggestion queries are read-only; `ResumeRestedXP()` and `StartSuggestion(id)` are explicit navigation
requests. Places use uiMapIDs and
normalized 0-1 coordinates, as Shortest Path's API does.

- `CurrentStop()` returns the stop the tracker shows now, or `nil`.
- `NextStops(limit)` returns the stops after it in route order, nearest first: two unless `limit` says otherwise,
  at most eight, and an empty table at the end of the route. A `limit` that is not a whole number of zero or more
  returns `nil`.

`RestedXPNativeUI()` returns true while the display choice is pending or the player chose RestedXP. Navigation addons should preserve the native arrow in that case.

`RestedXPIntegrated()` returns whether the installed RestedXP engine is assigned to AGF, including before its first deferred render. Navigation addons can
use it to defer standalone RXP routing and suppress its native arrow while AGF owns the guide.

A stop is a fresh table on every call:

| Field | |
|---|---|
| `map`, `x`, `y` | where the stop is |
| `name` | the town ("Crossroads"), else the quest giver, zone or step title; for display, not for matching |
| `isTown` | a town visit, grouping its pickups and hand-ins |
| `handins` | how many quests the route hands in there |
| `pickups` | how many quests the route picks up there |

`nil` means ask again later: the game's quest data has not loaded, the route is being worked out, or the current
stop has no known place. The counts are what the route plans for the visit; a hand-in the route returns for later
is counted at its stop. `Subscribe` says when to read again.

- `Subscribe(callback)` calls `callback(changes)` on the frame after what `CurrentStop` answers or the journey the
  route follows changes, at most once per burst of changes and never while the route is being worked out. `changes`
  is a new table each call with either or both set to `true`: `stop` (a stop appeared, moved on, changed or went) and
  `journey` (another journey, or the same one chosen or let go). Read `CurrentStop` and `NextStops` again rather than
  replaying the changes. A callback added by another callback waits for the next burst. It returns a function that
  unsubscribes, safe to call twice. An error in one callback goes to the game's error handler without stopping the
  others. A non-function callback is an error.

```lua
local api = AdventureGuideForever and AdventureGuideForever.API
local function Show()
	local stop = api.CurrentStop()
	if stop and stop.isTown then
		print(("Next town: %s (%d to hand in, %d to pick up)"):format(stop.name, stop.handins, stop.pickups))
	end
end
if api and api.version == 1 then
	Show()
	if type(api.Subscribe) == "function" then
		api.Subscribe(Show)
	end
end
```

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
  `id` no card has now, or when RestedXP refuses its guide in combat. Call it only for a player's click.

A suggestion is a fresh table on every call:

| Field | |
|---|---|
| `id` | the card's key, for `StartSuggestion`; stable while the card is offered |
| `title` | the card's title ("The Barrens story", "Head to Ashenvale"); for display |
| `level` | the lowest level the card shows (a zone's or dungeon's range, a battleground's first level), or `nil` |
| `kind` | `"carry"` (quests in your log), `"story"`, `"nextzone"`, `"dungeon"`, `"calling"`, `"battleground"` or `"guide"` |
| `map` | the uiMapID of its first stop |
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

### `API.ResumeRestedXP()`

Resume the active RestedXP guide through Adventure Guide's navigation. Returns `true` when the request is accepted, or `false` when integrated RestedXP is unavailable. Use this for an explicit player action after selecting another destination.
