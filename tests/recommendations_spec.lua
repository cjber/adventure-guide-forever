local harness = dofile("tests/harness.lua")
local h = harness.load({ db = { autoStart = false } })
h.flush()
local ns, checks = h.ns, 0
local function Equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local R = ns.Recommendations
local player = ns.State.Player()
local step = { key = "work", title = "A quest", map = player.map, x = player.x, y = player.y, quests = {}, adds = {} }
local journey = { key = "zone:1", kind = "story", title = "A story", steps = { step } }
local dungeon = { key = "dungeon:1", kind = "dungeon", title = "A dungeon", steps = { step } }
local bg = { key = "battleground:1", kind = "battleground", title = "A battleground", steps = { step } }
local trainer = {
	key = "trainer",
	text = "Train spells",
	icon = "class",
	category = "training",
	place = { map = player.map, x = player.x, y = player.y },
}
local profession = { key = "profession", text = "Train Mining", icon = "profession", category = "professions" }
local route = { chosen = true, journey = journey.key, journeys = { journey, dungeon, bg }, steps = { step } }
Equal(R.Build(route, { trainer }, "balanced", player)[1].journey, journey.key, "chosen route survives a nearby trainer")
route.chosen = false
Equal(R.Build(route, { trainer }, "balanced", player)[1].aside, trainer, "nearby training before an unchosen route")
Equal(R.Build(route, { trainer }, "training", player)[1].aside, trainer, "training focus")
Equal(R.Build(route, { trainer }, "professions", player)[1], nil, "empty focus stays honest")
Equal(R.Build(route, { profession }, "professions", player)[1].aside, profession, "unplaced hint remains advice")
Equal(#R.Build(route, { trainer }, "quests", player), 1, "quest focus excludes dungeon and battleground")
Equal(R.Build(route, {}, "dungeons", player)[1].journey, dungeon.key, "dungeon focus uses offered journeys")
Equal(#R.Build(route, { trainer, trainer }, "training", player), 1, "same aside appears once")
ns.Prefs().recommendationFocus = "bad save"
Equal(R.Focus(), "balanced", "unknown focus falls back")
local before = ns.Prefs().journey
R.SetFocus("training")
Equal(ns.Prefs().journey, before, "focus never chooses a journey")
Equal(R.Focus(), "training", "valid focus persists")
R.SetFocus("invalid")
Equal(R.Focus(), "training", "unknown focus ignored")

local savedRoute, savedAsides = ns.Route, ns.Asides.All
local settled = true
ns.RouteSettled = function()
	return settled
end
ns.Route = function()
	assert(settled, "must never build a dirty route")
	return route
end
local hints = { trainer }
ns.Asides.All = function()
	return hints
end
local item = R.Current()[1]
local calls = 0
ns.Asides.Go = function()
	calls = calls + 1
	return true
end
Equal(R.Act(item), true, "fresh action delegates to existing navigation")
Equal(calls, 1, "one navigation")
local changed = {}
for k, v in pairs(trainer) do
	changed[k] = v
end
changed.place = { map = player.map, x = 0.9, y = 0.9 }
hints = { changed }
Equal(R.Act(item), false, "moved hint destination rejects stale click")
hints = {}
Equal(R.Act(item), false, "dismissed hint rejects stale click")
hints = { trainer }
changed.place = trainer.place
changed.renew = 2
hints = { changed }
Equal(R.Act(item), false, "renewed hint rejects an old action at the same destination")
hints = { trainer }
settled = false
Equal(#R.Current(), 0, "pending rebuild shows no stale recommendation")
Equal(R.Act(item), false, "pending rebuild never reads route on click")
settled = true
ns.SetSetting("wanderer", true)
Equal(R.Act(item), false, "wanderer never navigates")
ns.SetSetting("wanderer", false)
h.combat = true
Equal(R.Act(item), false, "combat never navigates")
h.combat = false
Equal(calls, 1, "rejected actions leave guidance untouched")
ns.Route, ns.Asides.All = savedRoute, savedAsides
Equal(#h.errors, 0, "no harness errors")
print("recommendations_spec: " .. checks .. " checks passed")
