-- Run from the repository root: luajit tests/ui_spec.lua
-- Headless UI checks (docs/plan.md §1.1) through tests/harness.lua. What they cannot reach is a /reload check.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function clean(h, label)
	equal(#h.errors, 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
end

-- A level-18 orc shaman in The Barrens with one quest ready to hand in and one under way.
local function Load(spf)
	return harness.load({
		spf = spf or nil,
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, map = 1413, x = 0.46, y = 0.8 },
		},
	})
end

local function Shown(h, test)
	return h.Find(function(frame)
		return frame:IsVisible() and test(frame)
	end)
end

for _, spf in ipairs({ false, "v1", "v1+" }) do
	local label = spf or "no Shortest Path"
	local h = Load(spf)
	clean(h, label .. ": load")
	equal(h.G.ShortestPathForever ~= nil, spf ~= false, label .. ": Shortest Path global")
	equal(h.G.TweaksForever, nil, label .. ": no Tweaks Forever")
	equal(h.G.LegacyForever, nil, label .. ": no Legacy Forever")
	equal(h.ns.Route().steps[1].key, "turnin:845", label .. ": the hand-in leads the route")

	-- Blizzard's displayMode is never written, whatever the player clicks (Panel.lua ShowGuide).
	local panel, questsFrame = h.G.AdventureGuideForeverPanel, h.questMap.QuestsFrame
	h.ns.OpenPanel()
	h.flush()
	equal(panel:IsVisible(), true, label .. ": the guide opens")
	equal(questsFrame:IsShown(), false, label .. ": the quest list steps aside")
	h.Click(Shown(h, function(frame)
		return frame.BestFit ~= nil
	end)[1])
	h.flush()
	h.Click(Shown(h, function(frame)
		return frame.SkipButton ~= nil
	end)[1])
	h.flush()
	h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
	equal(panel:IsShown(), false, label .. ": the Quests tab closes the guide")
	equal(questsFrame:IsShown(), true, label .. ": the quest list is back")
	h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks["turnin:845"], "LeftButton")
	h.flush()
	equal(panel:IsShown(), true, label .. ": a tracker click opens the guide")
	h.TriggerEvent("QuestLog.SetDisplayMode")
	equal(panel:IsShown(), false, label .. ": a display mode change closes the guide")
	h.ns.OpenPanel()
	h.G.QuestMapFrame_ShowQuestDetails(845)
	equal(panel:IsShown(), false, label .. ": quest details close the guide")
	equal(h.counts.displayModeWrites, 0, label .. ": displayMode writes")
	clean(h, label .. ": clicks")
	-- The trap itself: a write raises and is counted.
	equal(
		pcall(function()
			h.G.QuestMapFrame.displayMode = "MapLegend"
		end),
		false,
		label .. ": a displayMode write raises"
	)
	equal(h.counts.displayModeWrites, 1, label .. ": the trap counts writes")
end

print(("ui_spec: %d checks passed"):format(checks))
