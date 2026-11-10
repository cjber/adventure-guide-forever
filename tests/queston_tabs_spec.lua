-- Run from the repository root: luajit tests/queston_tabs_spec.lua
-- Queston Forever (CurseForge 1785839) adds its own page and side tab to the world map's quest log without using
-- Forever Core's shared tabs. Choosing either addon's tab must close the other's page, so the map opens on one
-- choice instead of the last-loaded page. The stub mirrors Queston's ChronicleView: one guide tab, a panel under
-- QuestMapFrame, and Show(false) putting the map's own content back.
local harness = dofile("tests/harness.lua")

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local h = harness.load({ log = {} })
local G, map = h.G, h.questMap

-- Queston's attach, as the addon leaves it when Adventure Guide loaded first: a Chronicle tab that shows its
-- panel, and no replacement Quests tab of its own (it anchors to the guide's).
local qtab = G.CreateFrame("Button", "QuestonForeverChronicleTab", map)
qtab:SetChecked(false)
local qpanel = G.CreateFrame("Frame", "QuestonForeverChroniclePanel", map)
qpanel:Hide()
local view = { tab = qtab, panel = qpanel, open = false }
function view:Show(showGuide)
	showGuide = showGuide == true
	for _, frame in ipairs(map.ContentFrames) do
		frame:SetShown(not showGuide and frame.displayMode == map.displayMode)
	end
	self.tab:SetChecked(showGuide)
	self.panel:SetShown(showGuide)
	self.open = showGuide
end
qtab:SetCustomOnMouseUpHandler(function()
	view:Show(true)
end)
G.QuestonForever = { ChronicleView = view }

-- Queston's ADDON_LOADED is when its view exists; the guide hears it and hooks its Show.
h.fire("ADDON_LOADED", "QuestonForever")
h.flush()

local guide = G.AdventureGuideForeverPanel
local questsTab = G.ForeverQuestLogQuestsTab
assert(guide and questsTab, "the guide's map tabs exist")

-- Opening the guide closes Queston's page, so only one page is up.
h.ns.OpenPanel()
h.flush()
equal(guide:IsVisible(), true, "open: the guide shows")
equal(qpanel:IsShown(), false, "open: Queston's page is closed")

-- Choosing Queston's tab puts the guide away and leaves the map's own choice to Queston.
h.ClickTab(qtab)
h.flush()
equal(qpanel:IsShown(), true, "Queston's tab: its page shows")
equal(guide:IsShown(), false, "Queston's tab: the guide's page is closed")
equal(h.G.ForeverCore.QuestLogTabs.Selected(), nil, "Queston's tab: no guide tab stays selected")
-- The guide stepping aside puts the map's own frames back; they must stay hidden behind Queston's page.
local function contentShown()
	for _, frame in ipairs(map.ContentFrames) do
		if frame:IsShown() then
			return true
		end
	end
	return false
end
equal(contentShown(), false, "Queston's tab: the map's own quest frames stay hidden behind its page")

-- Choosing the guide's tab again closes Queston first, so its page is not left underneath.
h.ClickTab(G.AdventureGuideForeverTab)
h.flush()
equal(qpanel:IsShown(), false, "guide tab: Queston's page is closed")
equal(guide:IsShown(), true, "guide tab: the guide shows")

-- Queston opened another way (its window or key) puts the guide away too.
view:Show(true)
h.flush()
equal(guide:IsShown(), false, "Queston's own Show: the guide's page is closed")
equal(contentShown(), false, "Queston's own Show: the map's own quest frames stay hidden")
h.ClickTab(G.AdventureGuideForeverTab)
h.flush()

-- Choosing the map's own Quests page closes both pages.
h.ClickTab(qtab)
h.flush()
h.ClickTab(questsTab)
h.flush()
equal(qpanel:IsShown(), false, "Quests tab: Queston's page is closed")
equal(guide:IsShown(), false, "Quests tab: the guide's page is closed")
equal(map:IsShown(), true, "Quests tab: the map stays open")
equal(contentShown(), true, "Quests tab: the map's own quest list shows")

equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))
print(("queston_tabs_spec: %d checks passed"):format(checks))
