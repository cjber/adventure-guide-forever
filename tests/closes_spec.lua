-- Run from the repository root: luajit tests/closes_spec.lua
-- Quests that close another (Model.Closes, Core/Closes.lua, docs/design.md §2.26): a giver's detail window offering
-- a quest whose taking closes another of its exclusive group says so once in chat, by the direction QuestieDB's
-- exclusiveTo gives; versions of the same quest, quests the character can never take, quests done, in the log or
-- already closed are left out; an auto-accepted quest, the setting off or Polestar's own warning say nothing.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- The default character is a level 18 Horde orc shaman.
local function Load(options)
	local h = harness.load(options or {})
	h.flush()
	return h
end

local function Closes(h, id)
	local state = h.ns.State
	return table.concat(h.ns.Model.Closes(h.ns.Data, state.Player(), state.Completed(), state.Log(), id), ",")
end

local function Said(h)
	local lines = {}
	for _, line in ipairs(h.prints) do
		if line:find("for good", 1, true) then
			lines[#lines + 1] = line
		end
	end
	return lines
end

local function Warning(h, offered, lost)
	local quests = h.ns.Data.quests
	local names = {}
	for index, id in ipairs(lost) do
		names[index] = quests[id].title
	end
	return h.ns.L.CLOSES_WARNING:format(quests[offered].title, table.concat(names, h.ns.L.LIST_SEPARATOR))
end

-- The directions the corpus keeps: 861 "The Hunter's Way" and 854 "Journey to the Crossroads" name 844 "Plainstrider
-- Menace" as closing them, and not the other way round; the care packages close each other.
do
	local h = Load()
	local quests = h.ns.Data.quests
	equal(quests[844].group, quests[861].group, "844 and 861 share a group")
	equal(table.concat(quests[861].closedBy or {}, ","), "844", "861 is closed by 844")
	equal(Closes(h, 844), "861", "taking 844 closes 861; 854 is a tauren's")
	equal(Closes(h, 861), "", "taking 861 closes nothing")
	quests[854].races = nil
	equal(Closes(h, 844), "854,861", "without its race filter 854 is lost too")
	quests[854].races = 32
	equal(Closes(h, 7866), "7867,7868", "a care package closes the other two")
	equal(Closes(h, 8410), "8411", "Elemental Mastery closes Mastering the Elements")
	-- Every Call of Water is one quest for different races: none closes another.
	equal(Closes(h, 1528), "", "versions of the same quest")
	-- A rogue's quests, a shaman never takes.
	equal(Closes(h, 2378), "", "another class's quest")
	quests[861].side = 1
	equal(Closes(h, 844), "", "the other side's quest")
	quests[861].side, quests[861].classes = 2, 8
	equal(Closes(h, 844), "", "another class's member")
	quests[861].classes, quests[861].repeatable = nil, true
	equal(Closes(h, 844), "", "a repeatable member")
	quests[861].repeatable = nil
	equal(Closes(h, 844), "861", "restored")
	equal(Closes(h, 999999), "", "an unknown quest")
	equal(Closes(h, 6), "", "a quest in no group")
	equal(#h.errors, 0, "model: errors\n" .. table.concat(h.errors, "\n"))
end

-- Done, in the log, or closed already by another quest done or in the log: nothing left to lose.
do
	local h = Load({ completed = { 7867 } })
	equal(Closes(h, 7866), "", "one done closes the rest already")
	h = Load({ log = { { id = 7868, title = "Outrider Advanced Care Package", level = 45 } } })
	equal(Closes(h, 7866), "", "one in the log closes the rest already")
	h = Load({ completed = { 8411 } })
	equal(Closes(h, 8410), "", "the member is done")
end

-- The detail window: one line naming what would be lost, once per quest; nothing for a quest that closes nothing.
do
	local h = Load()
	h.Offer(7866)
	h.flush()
	local said = Said(h)
	equal(#said, 1, "one line")
	equal(said[1]:find(Warning(h, 7866, { 7867, 7868 }), 1, true) ~= nil, true, "it names both: " .. said[1])
	h.Offer(7866)
	h.flush()
	equal(#Said(h), 1, "not said twice for the same quest")
	h.Offer(861)
	h.flush()
	equal(#Said(h), 1, "a quest that closes nothing says nothing")
	h.Offer(844)
	h.flush()
	said = Said(h)
	equal(#said, 2, "another quest says its own line")
	equal(said[2]:find(Warning(h, 844, { 861 }), 1, true) ~= nil, true, "it names 861: " .. said[2])
	equal(#h.errors, 0, "window: errors\n" .. table.concat(h.errors, "\n"))
end

-- Nothing is said for a quest the game took itself, an unreadable ID, with the setting off, or while Polestar's own
-- warning is on; a failing Polestar read is no warning of its own.
do
	local h = Load()
	h.Offer(7866, true)
	h.flush()
	equal(#Said(h), 0, "auto-accepted: nothing")
	h.Offer(h.Secret())
	h.flush()
	equal(#Said(h), 0, "a secret quest ID: nothing")
	h.ns.SetSetting("warnClosing", false)
	h.Offer(7866)
	h.flush()
	equal(#Said(h), 0, "setting off: nothing")
	h.ns.SetSetting("warnClosing", true)
	local polestarWarns = true
	h.G.Polestar = {
		Get = function(path)
			if path == "behavior.warnClosing" then
				return polestarWarns
			end
			error("unexpected setting " .. tostring(path))
		end,
	}
	h.Offer(7866)
	h.flush()
	equal(#Said(h), 0, "Polestar warns already: nothing")
	h.G.Polestar = {
		Get = function()
			error("broken")
		end,
	}
	h.Offer(7866)
	h.flush()
	equal(#Said(h), 1, "a failing Polestar read: AGF warns")
	h.G.Polestar, polestarWarns = nil, false
	equal(h.ns.DEFAULTS.warnClosing, true, "on by default")
	equal(#h.errors, 0, "quiet: errors\n" .. table.concat(h.errors, "\n"))
end

print(("closes_spec: %d checks passed"):format(checks))
