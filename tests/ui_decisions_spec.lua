local harness = dofile("tests/harness.lua")
local checks, failures = 0, {}
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		failures[#failures + 1] = label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
	end
end

do
	local h = harness.load({ legacy = { summaries = {}, targets = {} } })
	h.G.C_Map.GetMapInfo = function() end
	h.ns.Route = function()
		return { journeys = {} }
	end
	equal(h.ns.Providers.Completion().zones[1].name, "The Barrens", "completion uses bundled zone name")
	h.player.map = 999999
	equal(#h.ns.Providers.Completion().zones, 0, "completion omits an unnamed zone")
end

do
	local h = harness.load()
	local ns = h.ns
	ns.Data.quests = { [999999] = { title = "Scaling quest", level = -1, min = 1, side = 3, zone = 1413 } }
	local journey = { key = "zone:1413", zone = 1413, title = "The Barrens" }
	ns.Route = function()
		return { journey = journey.key, steps = {}, journeys = {} }
	end
	local difficulty
	h.G.GetQuestDifficultyColor = function(level)
		difficulty = level
		return { r = 1, g = 0.5, b = 0 }
	end
	ns.Window.OpenGuide(journey, h.G.CreateFrame("Frame"))
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

do
	local items, bosses, loot = {}, {}, {}
	for boss = 1, 3 do
		bosses[boss] = { id = boss, name = "Boss " .. boss }
		for drop = 1, (boss == 3 and 1 or 6) do
			local id = boss * 100 + drop
			items[id] = { name = "Drop " .. id, quality = 3 }
			loot[#loot + 1] = { id = id, name = items[id].name, droppers = { { id = boss } } }
		end
	end
	local h = harness.load({ items = items })
	h.ns.Dungeons.Source = function()
		return { bosses = { [43] = bosses }, loot = { [43] = loot }, rewards = {}, objectives = {} }
	end
	h.ns.Window.OpenDungeon(43)
	h.flush()
	local tab = assert(h.Find(function(frame)
		return frame:IsVisible() and frame:GetText() == h.ns.L.DUNGEON_BOSSES_TAB
	end)[1])
	h.Click(tab)
	local row = assert(h.Find(function(frame)
		return frame:IsVisible() and frame.value and frame.value.boss and frame.value.title == "Boss 2"
	end)[1])
	local scroll = row:GetParent():GetParent()
	h.Click(row)
	equal(scroll:GetVerticalScroll(), 22 + 6 * 44, "boss jump accounts for heading height")
	h.Click(tab)
	local last = assert(h.Find(function(frame)
		return frame:IsVisible() and frame.value and frame.value.boss and frame.value.title == "Boss 3"
	end)[1])
	h.Click(last)
	equal(scroll:GetVerticalScroll(), 3 * 22 + 13 * 44 - 222, "boss jump clamps to the measured content height")
	equal(#h.errors, 0, "boss jump has no errors")
end

-- A loot heading with a level line under the boss's name is tall enough that the first item starts below that line.
do
	local items = { [101] = { name = "Drop 101", quality = 3 }, [201] = { name = "Drop 201", quality = 3 } }
	local h = harness.load({ items = items })
	h.ns.Dungeons.Source = function()
		return {
			bosses = { [43] = { { id = 1, name = "Boss 1", low = 20 }, { id = 2, name = "Boss 2" } } },
			loot = {
				[43] = {
					{ id = 101, name = "Drop 101", droppers = { { id = 1 } } },
					{ id = 201, name = "Drop 201", droppers = { { id = 2 } } },
				},
			},
			rewards = {},
			objectives = {},
		}
	end
	h.ns.Window.OpenDungeon(43)
	h.flush()
	h.Click(assert(h.Find(function(frame)
		return frame:IsVisible() and frame:GetText() == h.ns.L.DUNGEON_LOOT_TAB
	end)[1]))
	local function Row(test)
		return assert(h.Find(function(frame)
			return frame:IsVisible() and frame.value and test(frame.value)
		end)[1])
	end
	local function Top(row)
		return -(select(5, row:GetPoint())) -- multi-value: the y offset only
	end
	local heading = Row(function(value)
		return value.heading and value.title == "Boss 1"
	end)
	local item = Row(function(value)
		return value.item == 101
	end)
	equal(heading.Info:GetText(), h.ns.L.DUNGEON_LEVEL:format(20), "loot heading shows the boss's level")
	local infoBottom = Top(heading) - (select(5, heading.Info:GetPoint())) + heading.Info:GetStringHeight()
	equal(Top(item) >= infoBottom, true, "loot heading's level line ends above the first item")
	equal(heading:GetHeight() >= infoBottom - Top(heading), true, "loot heading row holds its level line")
	local plain = Row(function(value)
		return value.heading and value.title == "Boss 2"
	end)
	equal(plain:GetHeight(), 20, "a loot heading without a level line stays one line tall")
	equal(#h.errors, 0, "loot heading has no errors")
end

assert(#failures == 0, table.concat(failures, "\n"))
print(("ui_decisions_spec: %d checks passed"):format(checks))
