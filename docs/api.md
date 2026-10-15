# Addon API

Addons can read where the guide is sending the player through `AdventureGuideForever.API` (`version = 1`). Additions
keep `version` at 1 and raise `minor` (1 from `Subscribe`, absent before), so check that a function exists before
calling it.
The stop queries are read-only; `ResumeRestedXP()` is an explicit navigation request. Places use uiMapIDs and
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

### `API.ResumeRestedXP()`

Resume the active RestedXP guide through Adventure Guide's navigation. Returns `true` when the request is accepted, or `false` when integrated RestedXP is unavailable. Use this for an explicit player action after selecting another destination.
