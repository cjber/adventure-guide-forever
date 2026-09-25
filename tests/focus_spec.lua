-- Run from the repository root: luajit tests/focus_spec.lua
-- Following the quest the player is working on (Focus.lua): Focus.Next's guards, one look at a time.
local ns = { OnRouteChange = function() end }
assert(loadfile("Focus.lua"))("AdventureGuideForever", ns)
local Next = ns.Focus.Next

local failures, checks = {}, 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		failures[#failures + 1] = ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual))
	end
end

local wolves = { key = "area:226:0", quests = { 226 } }
local spiders = { key = "area:245:0", quests = { 245 } }
local both = { key = "area:226:0", quests = { 245, 226 } }

-- Walking in selects the quest, once; walking out clears it back to none.
local state = {}
equal(Next(state, wolves, 0, true), 226, "walking in selects the quest")
equal(state.quest, 226, "and keeps it as AGF's")
equal(Next(state, wolves, 226, true), nil, "inside, nothing again")
equal(Next(state, nil, 226, true), 0, "walking out clears AGF's selection")
equal(state.quest, nil, "and forgets it")
equal(Next(state, nil, 0, true), nil, "outside, nothing")

-- (a) Never over the player's own selection, on walking in or out.
state = {}
equal(Next(state, wolves, 99, true), nil, "the player's selection stays on walking in")
equal(Next(state, nil, 99, true), nil, "and on walking out")
state = {}
Next(state, wolves, nil, true)
equal(Next(state, wolves, 99, true), nil, "the player selecting another inside: theirs")
equal(state.quest, nil, "AGF's is forgotten")
equal(Next(state, nil, 99, true), nil, "walking out leaves theirs")

-- (b) Only on walking in: the player clearing it inside stays cleared; a new area selects again.
state = {}
Next(state, wolves, 0, true)
equal(Next(state, wolves, 0, true), nil, "cleared by the player inside: not again")
equal(Next(state, spiders, 0, true), 245, "into another area: its quest")
-- No flip-flop: an area that still holds AGF's quest keeps it, even as its first quest changes.
state = {}
Next(state, wolves, 0, true)
equal(Next(state, both, 226, true), nil, "the area still holds the quest: kept")
equal(state.quest, 226, "still AGF's")
-- Straight from one area into another replaces AGF's own selection.
equal(Next(state, spiders, 226, true), 245, "into another area from AGF's: the new quest")

-- (c) The quest's objectives done while the area stays for another quest: AGF's selection goes.
state = {}
Next(state, both, 0, true)
equal(state.quest, 245, "the area's first quest")
equal(Next(state, wolves, 245, true), 0, "its objectives done: cleared")
equal(Next(state, wolves, 0, true), nil, "and not replaced while still inside")

-- (e) The setting off: nothing selected, and AGF's own selection cleared.
state = {}
equal(Next(state, wolves, 0, false), nil, "off: nothing selected")
state = {}
Next(state, wolves, 0, true)
equal(Next(state, wolves, 226, false), 0, "turned off inside: AGF's selection cleared")
equal(Next(state, wolves, 0, true), 226, "turned on inside: selects on the next look")

for _, failure in ipairs(failures) do
	print("  " .. failure)
end
print(("focus_spec: %d checks, %d failed"):format(checks, #failures))
if #failures > 0 then
	os.exit(1)
end
