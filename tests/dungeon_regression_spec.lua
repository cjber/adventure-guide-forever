-- Whole-catalog planning and the handoff to Adventure Guide for Classic.
local harness = dofile("tests/harness.lua")
local Button = dofile("tests/ui_helpers.lua").Button
-- Empty eligibility is intentional: planning must survive the full route rebuild anyway.
local h = harness.load()
for _, quest in pairs(h.ns.Data.quests) do
	quest.min = 99
end
local old = harness.load({ charDB = { journey = "dungeon:43" } })
assert(old.ns.Dungeons.Planned(43), "migrate previously selected dungeon")
local planned = {}
for id, instance in pairs(h.ns.Data.instances) do
	if not instance.raid then
		h.ns.Window.OpenDungeon(id)
		h.flush()
		h.Click(Button(h, h.ns.L.DUNGEON_PLAN))
		h.flush()
		assert(h.ns.Dungeons.Planned(id), "planning must persist for " .. id)
		planned[#planned + 1] = id
	end
end
assert(#planned > 15, "exercise the whole Classic catalog")
-- A mapped raid pages through the same window.
for _, raid in ipairs(h.ns.Raids) do
	if raid.map then
		h.ns.Window.OpenDungeon(raid.map)
		h.flush()
	end
end
local reloaded = harness.load({ charDB = h.G.AdventureGuideForeverCharDB })
for _, id in ipairs(planned) do
	assert(reloaded.ns.Dungeons.Planned(id), "plans survive reload")
	assert(h.ns.Prefs().plannedDungeons[id], "other dungeon choices must not clear earlier plans")
	h.ns.Dungeons.SetPlanned(id, false)
	assert(not h.ns.Dungeons.Planned(id))
end
assert(#h.errors == 0, table.concat(h.errors, "\n"))
-- Hand off to the optional guide's public command without importing its data.
local classic = harness.load()
classic.ns.Window.OpenDungeon(43)
classic.flush()
local launch
for _, frame in ipairs(classic.frames) do
	if frame:IsObjectType("Button") and frame:GetText() == classic.ns.L.DUNGEON_BOSSES_LOOT then
		launch = frame
	end
end
assert(launch, "the bosses and loot control is built")
assert(launch:IsShown(), "the control is always shown")
assert(not launch:IsEnabled(), "the control is disabled without the dependency")
classic.Hover(launch)
assert(
	classic.tooltip[1] == "title: " .. classic.ns.L.DUNGEON_BOSSES_LOOT_INSTALL,
	"the disabled control names the addon to install"
)
assert(not classic.ns.Integrations.OpenClassicGuide(), "absent dependency cannot launch")
classic.metadata.AdventureGuideClassic = {}
classic.ns.Window.OpenDungeon(43)
classic.flush()
assert(not launch:IsEnabled(), "loaded dependency without its command cannot launch")
local calls = 0
classic.G.SlashCmdList.ADVENTUREGUIDECLASSIC = function(message)
	assert(message == "", "public command receives its normal home argument")
	calls = calls + 1
end
classic.ns.Window.OpenDungeon(43)
classic.flush()
assert(launch:IsEnabled(), "available dependency enables the control")
classic.Hover(launch)
assert(
	classic.tooltip[1] == "title: " .. classic.ns.L.DUNGEON_BOSSES_LOOT_TOOLTIP,
	"the enabled control names what it opens"
)
classic.Click(launch)
assert(calls == 1, "one click invokes the public guide command once")
assert(#classic.errors == 0, "the public handoff does not raise errors")
print("dungeon_regression_spec: whole-catalog planning and the Adventure Guide for Classic handoff passed")
