-- Run from the repository root: luajit tests/report_spec.lua
-- The report window and caught errors (UI/Report.lua, Core/Report.lua, Core/SafeCall.lua; docs/design.md §2.24):
-- /agf report shows one selected block of text with the versions, character, the stop and its Why lines, the caught
-- errors and the other addons, never longer than one message; ns.SafeCall keeps errors and still reports them.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function has(text, part, label)
	checks = checks + 1
	if not text:find(part, 1, true) then
		error(("%s: %q not in\n%s"):format(label, part, text), 2)
	end
end

local function lacks(text, part, label)
	checks = checks + 1
	if text:find(part, 1, true) then
		error(("%s: %q in\n%s"):format(label, part, text), 2)
	end
end

-- ui_spec's level-18 orc shaman in The Barrens, The Zhevra ready to hand in, on The Barrens story.
local function Load(options)
	options = options or {}
	local h = harness.load({
		charDB = { journey = "zone:1413" },
		planned = true,
		version = "1.2.3",
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
		questiedb = options.questiedb,
	})
	h.flush()
	return h
end

-- The report window: the one frame /agf report made, with its edit box.
local function Window(h)
	local edit = h.focus
	return edit and edit:GetParent():GetParent():GetParent(), edit
end

do
	local h = Load()
	h.metadata.Questie = { Version = "9.1.0" }
	h.metadata.ShortestPathForever = { Version = "0.9.0" }
	local before = h.counts.CreateFrame
	h.Slash("report")
	local frame, edit = Window(h)
	equal(edit and edit:GetObjectType(), "EditBox", "the report's edit box has the focus")
	local text = edit:GetText()
	equal(edit.highlighted, text, "the whole report is selected")
	equal(frame.stockTemplate, "PortraitFrameTemplate", "a stock portrait frame")
	equal(frame.TitleText.text, "Adventure Guide report", "its title")
	equal(frame:IsShown(), true, "shown")
	has(text, "AdventureGuideForever 1.2.3 | WoW 1.60.1 (69913) 16001 | enUS", "versions, build and locale")
	has(text, "Character: level 18 ", "character")
	has(text, "Place: map ", "place")
	has(text, "QuestieDB: ", "QuestieDB line")
	has(text, "Settings: guide, ", "settings")
	has(text, "Journey: The Barrens story [zone:1413], chosen", "the chosen journey")
	local step = h.ns.Guidance.CurrentStep() or h.ns.Route().steps[1]
	has(text, ("Stop: %s [%s %s]"):format(step.title, step.kind, step.key), "the current stop, kind and key")
	has(text, "  Why: ", "its Why line")
	has(text, ("  Quest %d "):format(step.quests[1]), "its quests by ID")
	has(text, "    + ", "the quest's requirements, met")
	has(text, "Errors: none caught", "no errors yet")
	has(text, "Other addons (2): Questie 9.1.0, ShortestPathForever 0.9.0", "the other addons with versions")
	equal(#text <= 2000, true, "one message")

	-- Read-only: a key typed in the box puts the report back, selected.
	edit.text, edit.highlighted = "x", nil
	edit.scripts.OnTextChanged(edit, true)
	equal(edit:GetText(), text, "typing restores the report")
	equal(edit.highlighted, text, "and selects it again")
	-- Escape closes it; a second /agf report reuses the frame.
	edit.scripts.OnEscapePressed(edit)
	equal(frame:IsShown(), false, "Escape hides it")
	local made = h.counts.CreateFrame - before
	h.Slash("report")
	equal(frame:IsShown(), true, "shown again")
	equal(h.counts.CreateFrame - before, made, "the window is made once")
	equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))
end

-- ns.SafeCall: pcall's answers, and each failure kept (label, count, short stack) and passed to the error handler.
do
	local h = Load()
	local ns = h.ns
	local ok, a, b, c = ns.SafeCall("test", function(x)
		return x, nil, 3
	end, 1)
	equal(ok, true, "SafeCall: ok")
	equal(a, 1, "SafeCall: first result")
	equal(b, nil, "SafeCall: a nil result kept in place")
	equal(c, 3, "SafeCall: last result")
	equal(#ns.CaughtErrors(), 0, "SafeCall: nothing caught")
	local failed, message = ns.SafeCall("test", error, "boom", 0)
	equal(failed, false, "SafeCall: failure")
	equal(message, "boom", "SafeCall: the error")
	equal(#h.errors, 1, "SafeCall: passed to the error handler")
	ns.SafeCall("test", error, "boom", 0)
	local caught = ns.CaughtErrors()
	equal(#caught, 1, "SafeCall: a repeat is one entry")
	equal(caught[1].count, 2, "SafeCall: counted")
	equal(caught[1].label, "test", "SafeCall: labelled")
	ns.SafeCall("deep", function()
		local t = nil
		return t.field
	end)
	caught = ns.CaughtErrors()
	equal(caught[2].label, "deep", "SafeCall: newest last")
	has(caught[2].stack, "report_spec.lua:", "SafeCall: the stack names the file")
	for index = 1, 6 do
		ns.SafeCall("many", error, "error " .. index, 0)
	end
	caught = ns.CaughtErrors()
	equal(#caught, 5, "SafeCall: the last five kept")
	equal(caught[5].message, "error 6", "SafeCall: newest kept")
	equal(caught[1].message, "error 2", "SafeCall: oldest dropped")
	caught[1].message = "changed"
	equal(ns.CaughtErrors()[1].message, "error 2", "SafeCall: copies")
	ns.SafeCall("long", error, ("x"):rep(400), 0)
	equal(#ns.CaughtErrors()[5].message, 300, "SafeCall: a long message is cut")

	h.Slash("report")
	local _, edit = Window(h)
	local text = edit:GetText()
	has(text, "Errors (5):", "report: the caught errors")
	has(text, "- [long] x1 xxx", "report: newest first")
	equal(#text <= 2000, true, "report: still one message")
end

-- A route listener that fails is caught and kept; the listeners after it still run.
do
	local h = Load()
	local ns = h.ns
	local ran = 0
	ns.OnRouteChange(function()
		error("listener failed", 0)
	end)
	ns.OnRouteChange(function()
		ran = ran + 1
	end)
	ns.Invalidate()
	h.flush()
	equal(ran > 0, true, "listener: the next listener still runs")
	local caught = ns.CaughtErrors()
	equal(caught[#caught].label, "route listener", "listener: caught")
	equal(caught[#caught].message, "listener failed", "listener: its error")
	equal(#h.errors > 0, true, "listener: still passed to the error handler")
end

-- Many other addons: the list says how many more, and the report stays one message.
do
	local h = Load()
	for index = 1, 300 do
		h.metadata[("SomeAddon%03d"):format(index)] = { Version = "1.0." .. index }
	end
	h.Slash("report")
	local _, edit = Window(h)
	local text = edit:GetText()
	equal(#text <= 2000, true, "many addons: one message")
	has(text, "Other addons (300): SomeAddon001 1.0.1, ", "many addons: counted")
	has(text, " more", "many addons: the rest counted")
	lacks(text, "SomeAddon300", "many addons: the last left out")
end

-- While a build is due the report says so, and doesn't build one.
do
	local h = Load()
	h.ns.Invalidate()
	local plans = h.modelCalls.Plan
	h.Slash("report")
	local _, edit = Window(h)
	has(edit:GetText(), "Route: still being worked out", "unsettled: said")
	equal(h.modelCalls.Plan, plans, "unsettled: no build for the report")
end

-- The help lists the command.
do
	local h = Load()
	h.Slash("help")
	local found = false
	for _, line in ipairs(h.prints) do
		found = found or line:find("/agf report", 1, true) ~= nil
	end
	equal(found, true, "help names /agf report")
end

print(("report_spec: %d checks passed"):format(checks))
