-- Recommendations obey the level ceiling; accepted quests remain actionable.
local harness = dofile("tests/harness.lua")
local h = harness.load({ player = { level = 21 }, db = {} })
local ns = h.ns
assert(ns.Setting("maxQuestLevelOffset") == 2, "missing setting defaults to yellow ceiling")
local player = ns.State.Player()
assert(not ns.Model.Hard({ level = 23 }, player), "yellow quest allowed by default")
assert(ns.Model.Hard({ level = 24 }, player), "orange quest avoided by default")
assert(ns.Model.Hard({ level = 26 }, player), "red quest avoided by default")
ns.SetSetting("maxQuestLevelOffset", 3)
player = ns.State.Player()
assert(not ns.Model.Hard({ level = 24 }, player), "slider allows orange quests")
ns.SetSetting("maxQuestLevelOffset", 0)
player = ns.State.Player()
assert(ns.Model.Hard({ level = 22 }, player), "slider can restrict quests to player level")
local reloaded = harness.load({ player = { level = 21 }, db = { maxQuestLevelOffset = 5 } })
assert(reloaded.ns.State.Player().maxQuestLevelOffset == 5, "saved slider survives loading")
assert(#h.errors + #reloaded.errors == 0, "settings registration has no errors")

local data = {
	quests = {
		[1] = {
			title = "A harder quest",
			level = 25,
			min = 1,
			side = 3,
			start = { map = 1, x = 0.5, y = 0.5, name = "Giver" },
		},
	},
	zones = { [1] = { name = "Test zone", min = 18, max = 30 } },
	maps = { [1] = { continent = 1, cx = 0, cy = 0, sx = 1, sy = 1 } },
	hubs = {},
	instances = {},
}
local prefs = { quests = true, dungeons = false, skipped = {} }
player.map, player.x, player.y = 1, 0.5, 0.5
player.maxQuestLevelOffset = 2
assert(#ns.Model.Plan(data, player, {}, {}, prefs).journeys == 0, "orange-only zone not recommended by default")
player.maxQuestLevelOffset = 4
assert(ns.Model.Plan(data, player, {}, {}, prefs).journeys[1].zone == 1, "raised ceiling includes its zone")
player.maxQuestLevelOffset = 0
assert(#ns.Model.Plan(data, player, {}, {}, prefs).journeys == 0, "lowering ceiling removes the recommendation")
local log = { [1] = { id = 1, title = "A harder quest", level = 25, complete = true, map = 1, x = 0.5, y = 0.5 } }
assert(#ns.Model.Plan(data, player, {}, log, prefs).steps > 0, "accepted quest stays visible above the ceiling")
local corrupt = harness.load({ db = { maxQuestLevelOffset = 99 } })
assert(corrupt.ns.Setting("maxQuestLevelOffset") == 10, "saved values stay within the slider range")
local row
for _, initializer in ipairs(h.settings) do
	if initializer.key == "maxQuestLevelOffset" then
		row = initializer
	end
end
assert(row and row.options.minimum == -4 and row.options.maximum == 10, "slider uses the intended range")
assert(row.options.formatter(2) == "+2 levels", "slider explains the relative level")
player.maxQuestLevelOffset = -1
assert(ns.Model.Hard({ level = -1 }, player), "scaling quests use the player level")
print("quest_level_setting_spec: 16 checks passed")
