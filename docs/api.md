# Addon API

Addons can read where the guide is sending the player through `AdventureGuideForever.API` (`version = 1`). It is
read-only: no call rebuilds the route, starts guidance or changes what the tracker shows. Places use uiMapIDs and
normalized 0–1 coordinates, as Shortest Path's API does.

- `CurrentStop()` returns the stop the tracker shows now, or `nil`.
- `NextStops(limit)` returns the stops after it in route order, nearest first: two unless `limit` says otherwise,
  at most eight, and an empty table at the end of the route. A `limit` that is not a whole number of zero or more
  returns `nil`.

A stop is a fresh table on every call:

| Field | |
|---|---|
| `map`, `x`, `y` | where the stop is |
| `name` | the town (“Crossroads”), else the quest giver, zone or step title; for display, not for matching |
| `isTown` | a town visit, grouping its pickups and hand-ins |
| `handins` | how many quests the route hands in there |
| `pickups` | how many quests the route picks up there |

`nil` means ask again later: the game's quest data has not loaded, the route is being worked out, or the current
stop has no known place. The counts are what the route plans for the visit; a hand-in the route returns for later
is counted at its stop. The guide fires no event of its own when the stop changes, so poll, for example when your
own panel opens or on `QUEST_LOG_UPDATE`.

```lua
local api = AdventureGuideForever and AdventureGuideForever.API
local stop = api and api.version == 1 and api.CurrentStop()
if stop and stop.isTown then
	print(("Next town: %s (%d to hand in, %d to pick up)"):format(stop.name, stop.handins, stop.pickups))
end
```
