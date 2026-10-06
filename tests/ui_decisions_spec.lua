local harness = dofile("tests/harness.lua")
local checks, failures = 0, {}
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		failures[#failures + 1] = label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
	end
end

do
	local h = harness.load()
	local ns = h.ns
	ns.Data.quests = { [999999] = { title = "Scaling quest", level = -1, min = 1, side = 3, zone = 1413 } }
	local journey = ns.Route().journeys[1]
	journey.key, journey.zone, journey.title = "zone:1413", 1413, "The Barrens"
	ns.Route = function()
		return { journey = journey.key, steps = {}, journeys = { journey }, chosen = true }
	end
	local difficulty
	h.G.GetQuestDifficultyColor = function(level)
		difficulty = level
		return { r = 1, g = 0.5, b = 0 }
	end
	ns.OpenPanel()
	h.flush()
	local row = assert(h.Find(function(frame)
		return frame.questID == 999999
	end)[1])
	local title = ns.L.QUEST_LEVEL:format(h.player.level, "Scaling quest")
	equal(row.Title:GetText(), title, "outline resolves a scaling quest level")
	equal(difficulty, h.player.level, "outline difficulty uses the resolved level")
	h.Hover(row)
	equal(h.tooltip[1], "title: " .. title, "outline tooltip resolves a scaling quest level")
	equal(#h.errors, 0, "outline has no errors")
end

assert(#failures == 0, table.concat(failures, "\n"))
print(("ui_decisions_spec: %d checks passed"):format(checks))
