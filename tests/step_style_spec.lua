-- Run from the repository root: luajit tests/step_style_spec.lua
-- One renderer for every step line (UI/StepStyle.lua): AGF's own journeys take their colours from AGF's data, and
-- RestedXP's roles use the same colours only for its own steps (#376).
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function includes(text, part, label)
	check(text:find(part, 1, true) ~= nil, label .. ": expected " .. part .. " in " .. text)
end

local GREEN, RED, GOLD, WHITE = "|cff009919", "|cffcc4c38", "|cffffd100", "|cffffffff"

local h = harness.load({
	planned = true,
	db = { autoStart = false },
	charDB = { journey = "zone:1413" },
	completed = { 844 },
	items = {
		[3823] = { name = "Lesser Healing Potion", quality = 3 },
		[4888] = { name = "Crawler Mucus", quality = 2 },
	},
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	},
})
h.flush()
local ns, G = h.ns, h.G
local Style = ns.StepStyle

-- The roles and their colours live once, here: AGF's own words and RestedXP's roles both ask this table.
equal(Style.Color("friendly"), G.FACTION_GREEN_COLOR, "friendly NPCs are green")
equal(Style.Color("enemy"), G.FACTION_RED_COLOR, "enemies are red")
equal(Style.Color("RXP_FRIENDLY_"), G.FACTION_GREEN_COLOR, "a RestedXP friendly role uses the same green")
equal(Style.Color("RXP_ENEMY_"), G.FACTION_RED_COLOR, "a RestedXP enemy role uses the same red")
equal(Style.Color("item", 3823), G.ITEM_QUALITY_COLORS[3].color, "an item takes its quality colour")
equal(Style.Color("RXP_LOOT_", 3823), G.ITEM_QUALITY_COLORS[3].color, "a RestedXP loot role takes it too")
equal(Style.Quest("The Zhevra"), GOLD .. "The Zhevra|r", "quest names are gold")
equal(Style.Wrap(nil, "plain"), "plain", "a role without a colour leaves text alone")

-- AGF's own journey: a town's giver is a friendly NPC, and a monster its objective names is an enemy, from the data.
local town, giver
for _, step in ipairs(ns.Route().steps) do
	for _, row in ipairs(step.checklist or {}) do
		if not town and not row.done and row.name then
			town, giver = step, row
		end
	end
end
check(town ~= nil and giver ~= nil, "the story has a town with a giver to see")
local line = Style.Checklist(town, giver)
includes(line, GREEN .. giver.name .. "|r", "a town giver is a friendly NPC")

local area
for _, step in ipairs(ns.Route().steps) do
	if not area and #(step.objectives or {}) > 0 then
		for _, id in ipairs(step.quests) do
			local quest = ns.Data.quests[id]
			if quest and quest.names and next(quest.names) then
				area = step
			end
		end
	end
end
check(area ~= nil, "the story has an area step that names its enemies")
-- A creature's own name has no reaction in the data: a neutral mob stays plain, and only a proved side takes a colour.
includes(Style.Step(area, "Southsea brigand slain: 3/10"), "Southsea brigand", "a neutral objective name stays plain")
check(
	Style.Step(area, "Southsea brigand slain: 3/10"):find(RED, 1, true) == nil,
	"a monster kind alone never paints a name red"
)
includes(Style.Step(area, "The Barrens"), WHITE .. "The Barrens|r", "a zone is styled")
local enemyQuest, enemyName
for id, quest in pairs(ns.Data.quests) do
	if not enemyQuest and quest.side == 1 and quest.start and quest.start.npc and quest.start.name then
		enemyQuest, enemyName = id, quest.start.name
	end
end
check(enemyQuest ~= nil, "the data has an opposite-side giver")
includes(
	Style.Step({ quests = { enemyQuest }, spots = {} }, enemyName),
	RED .. enemyName .. "|r",
	"an opposite-side NPC is red"
)
equal(
	Style.Step({ quests = { 818 }, spots = {} }, "Crawler mucus"),
	Style.Wrap(G.ITEM_QUALITY_COLORS[2].color, "Crawler mucus"),
	"an item in AGF's own data takes its quality colour"
)

-- The surfaces share it: the tracker, the guide's checklist and a pin's tooltip all show the same giver line.
h.tracker:LayoutContents()
local block = h.tracker.liveBlocks[town.key]
check(block ~= nil, "the tracker lays out the town")
local found
for _, key in ipairs(block.order) do
	if block.lines[key]:find(giver.name, 1, true) then
		found = block.lines[key]
	end
end
includes(found or "", GREEN .. giver.name .. "|r", "the tracker uses the shared renderer")

ns.OpenPanel()
h.flush()
local panelLines = h.Find(function(frame)
	return frame.Tick and frame.Text and frame.Text:GetText():find(giver.name, 1, true)
end)
check(#panelLines > 0, "the guide shows the town's checklist")
local styled = false
for _, frame in ipairs(panelLines) do
	styled = styled or frame.Text:GetText():find(GREEN .. giver.name .. "|r", 1, true) ~= nil
end
check(styled, "the guide's checklist uses the shared renderer")

G.GameTooltip:Hide()
ns.Pins.StepTooltip(G.GameTooltip, town, 1)
includes(table.concat(h.tooltip, "\n"), GREEN .. giver.name .. "|r", "a pin tooltip uses the shared renderer")
G.GameTooltip:Hide()

equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))
print(("step_style_spec: %d checks passed"):format(checks))
