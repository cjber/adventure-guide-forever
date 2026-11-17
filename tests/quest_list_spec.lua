-- The Forever quest list (UI/QuestList.lua): off by default, carried over once from ForeverCore's own switch, standing
-- down while ForeverCore still ships its list or another tracker owns the quests, and that ownership read from a
-- setting, never from a frame's momentary visibility (cjber/forever-core#795).
local harness = dofile("tests/harness.lua")

local function load(options)
	if options.coreQuestList == nil then
		options.coreQuestList = false
	end
	options.coreDB = options.coreDB or { questList = false }
	local h = harness.load(options)
	return h, h.ns.QuestList
end

local function nativeHidden(h)
	return h.stateDrivers[h.G.ObjectiveTrackerFrame] == "hide" and h.G.ObjectiveTrackerFrame:GetAlpha() == 0
end

local function noErrors(h, label)
	assert(#h.errors == 0, label .. ": " .. table.concat(h.errors, "\n"))
end

-- Off by default: nothing hidden, no reason, the switch reads off.
do
	local h, list = load({})
	assert(not list.Provided(), "default: core without its list leaves the list to this addon")
	assert(list.Enabled() == false, "default: the list is off")
	assert(list.Reason() == nil, "default: nothing blocks turning it on")
	assert(not nativeHidden(h), "default: the game's tracker stays")
	list.SetEnabled(true)
	assert(h.G.AdventureGuideForeverDB.questList == true, "on: saved")
	assert(nativeHidden(h), "on: the game's tracker is hidden through the state driver")
	list.SetEnabled(false)
	assert(h.stateDrivers[h.G.ObjectiveTrackerFrame] == nil, "off: the driver is released")
	assert(h.G.ObjectiveTrackerFrame:GetAlpha() == 1, "off: the game's tracker is shown again")
	noErrors(h, "default")
end

-- Migration: an explicit "on" in ForeverCore carries over once; nil there stays off.
do
	local h, list = load({ coreDB = { questList = true } })
	assert(list.Enabled() == true, "migration: core's on carries over")
	assert(h.G.AdventureGuideForeverDB.questListMigrated == true, "migration: recorded")
	noErrors(h, "migration")
	assert(select(2, load({ coreDB = {} })).Enabled() == false, "migration: unset in core stays off")
	local later =
		select(2, load({ coreDB = { questList = true }, db = { questListMigrated = true, questList = false } }))
	assert(later.Enabled() == false, "migration: runs once, a later off stands")
	-- A core that still ships its list keeps the choice, and the copy waits.
	h, list = load({ coreQuestList = true, coreDB = { questList = true } })
	assert(list.Provided(), "provided: core's own list is the one")
	assert(list.Reason() == h.ns.L.QUEST_LIST_PROVIDED, "provided: the reason says so")
	assert(h.G.AdventureGuideForeverDB.questListMigrated ~= true, "provided: the copy waits for a core without it")
end

-- Questie's tracker owns the quests: the option is blocked with its name and the list never hides the native tracker.
do
	local h, list = load({ db = { questList = true, questListMigrated = true } })
	assert(nativeHidden(h), "questie: the list is on before Questie loads")
	harness.questie(h, {})
	-- The list's ticker is what notices another tracker taking the quests.
	h.tickers()
	assert(list.Owner() == "Questie", "questie: its tracker setting owns the quests")
	assert(list.Reason() == h.ns.L.QUEST_LIST_OWNED:format("Questie"), "questie: the reason names it")
	assert(h.stateDrivers[h.G.ObjectiveTrackerFrame] == nil, "questie: the list stands down")
	noErrors(h, "questie")

	-- #795: during a journey reload the frames flip shown and hidden. Ownership follows Questie's setting alone, so
	-- neither the native tracker's nor Questie's own frame visibility moves the list in or out.
	local native = h.G.ObjectiveTrackerFrame
	local base = h.G.CreateFrame("Frame", "Questie_BaseFrame", h.G.UIParent)
	for round = 1, 4 do
		if round % 2 == 1 then
			native:Hide()
			native:SetAlpha(0)
			base:Hide()
		else
			native:Show()
			native:SetAlpha(1)
			base:Show()
		end
		h.tickers()
		h.flush()
		assert(list.Owner() == "Questie", "reload " .. round .. ": Questie still owns the quests")
		assert(h.stateDrivers[native] == nil, "reload " .. round .. ": the list does not come back")
	end

	-- Turning Questie's tracker off in its options is what hands the quests back.
	h.G.Questie.db.profile.trackerEnabled = false
	h.tickers()
	assert(list.Owner() == nil and list.Reason() == nil, "questie off: nothing owns the quests")
	assert(nativeHidden(h), "questie off: the list takes over")
	noErrors(h, "questie reload")
end

-- With no other tracker, the native tracker's own visibility flipping never reads as another owner.
do
	local h, list = load({ db = { questList = true, questListMigrated = true } })
	local native = h.G.ObjectiveTrackerFrame
	for round = 1, 4 do
		if round % 2 == 1 then
			native:SetAlpha(0)
		else
			native:Show()
			native:SetAlpha(1)
		end
		h.tickers()
		h.flush()
		assert(list.Owner() == nil, "native flip " .. round .. ": no other owner")
		assert(h.stateDrivers[native] == "hide", "native flip " .. round .. ": the list stays on")
	end
	noErrors(h, "native flip")
end

print("quest_list_spec: off by default, migrated once, and owned by a setting, not a frame's visibility")
