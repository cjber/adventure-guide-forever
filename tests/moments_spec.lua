-- Run from the repository root: luajit tests/moments_spec.lua
-- Something new (Moments.lua, docs/design.md §2.13) through tests/harness.lua: the seen set, a level or a zone that
-- brings a journey or an aside the character hasn't been offered, the tracker's glow, the card's mark, the pips, and
-- what clears them.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function same(actual, expected, label)
	equal(table.concat(actual, "\n"), table.concat(expected, "\n"), label)
end

local function clean(h, label)
	equal(#h.errors, 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
end

-- ui_spec's level-18 orc shaman in The Barrens, nothing chosen: its cards are The Barrens' story and Stonetalon
-- Mountains and Ashenvale; Hillsbrad becomes useful at level 19, and Moonglade at 20 (the Great Cat Spirit quests,
-- QuestieDB v1.0.5).
local function Load(charDB)
	return harness.load({ charDB = charDB or {}, completed = { 844 }, log = {} })
end

local function LevelUp(h, level)
	h.player.level = level
	h.fire("PLAYER_LEVEL_UP")
	h.flush()
end

local function Pip(frame)
	for _, region in ipairs(frame.regions) do
		if region:GetAtlas() == "adventureguide-microbutton-alert" then
			return region
		end
	end
end

local function Pips(h)
	return Pip(h.G.AdventureGuideForeverTab):IsShown(), Pip(h.G.AddonCompartmentFrame):IsShown()
end

-- The card showing `key`, and whether its "new" mark shows.
local function Marked(h, key)
	local card = h.Find(function(frame)
		return frame.New ~= nil and frame.journey ~= nil and frame.journey.key == key and frame:IsVisible()
	end)[1]
	return card ~= nil and card.New:IsShown()
end

local function Tracker(h)
	local block = h.tracker.liveBlocks.moment
	return block and block.used and block.header or nil
end

-- The first look learns what is offered and says nothing, so an empty seen set (a new character, or a save file the
-- client never loaded, #34) never floods.
local h = Load()
local seen = h.G.AdventureGuideForeverCharDB.seen
equal(seen["zone:1413"], true, "first look: the story is seen")
equal(seen["zone:1442"], true, "first look: the next zone is seen")
equal(seen.carry, nil, "first look: what the player carries is never new")
equal(#h.fanfares, 0, "first look: no glow")
equal(select(1, Pips(h)), false, "first look: no pip on the tab")
equal(select(2, Pips(h)), false, "first look: nor on the compartment")

-- Repeated level notification without new choices says nothing.
LevelUp(h, 18)
equal(#h.fanfares, 0, "same cards: no glow")
equal(Tracker(h), nil, "same cards: no line")

-- A level that brings zones the character hasn't been offered: one glowing line naming the first of them, a pip on
-- the tab and the compartment, and each card's mark. Nothing opens.
LevelUp(h, 22)
same(h.fanfares, { "moment" }, "new zone: the line glows once")
equal(Tracker(h), "Hillsbrad Foothills is now for your level", "new zone: named by the client")
equal(h.G.AdventureGuideForeverPanel:IsShown(), false, "new zone: nothing opens")
equal(select(1, Pips(h)), true, "new zone: the tab's pip")
equal(select(2, Pips(h)), true, "new zone: the compartment's pip")
equal(seen["zone:1424"], true, "new zone: now seen")
equal(seen["zone:1450"], true, "new zone: the quest-visit alternative is also seen")
equal(seen["zone:1442"], true, "new zone: the zone it replaced stays seen")
h.tracker:MarkDirty()
same(h.fanfares, { "moment" }, "new zone: glows once, not on every layout")

-- Its click opens the guide: the pips and the line go, the card keeps its mark while the guide shows.
h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks.moment, "LeftButton")
h.flush()
equal(h.G.AdventureGuideForeverPanel:IsVisible(), true, "click: the guide opens")
equal(select(1, Pips(h)), false, "opened: the tab's pip goes")
equal(select(2, Pips(h)), false, "opened: the compartment's pip goes")
equal(Tracker(h), nil, "opened: the line goes")
equal(Marked(h, "zone:1424"), true, "opened: the new card is marked")
equal(Marked(h, "zone:1413"), false, "opened: the others are not")

-- Closing the guide takes the marks away; a zone change that brings nothing new leaves them away.
h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
h.ns.OpenPanel()
h.flush()
equal(Marked(h, "zone:1424"), false, "closed: the mark goes")
h.fire("ZONE_CHANGED_NEW_AREA")
h.flush()
equal(#h.fanfares, 1, "zone change, nothing new: no glow")
clean(h, "level up")

-- Found with the guide open: the card is marked, and nothing calls the player over.
h = Load()
h.ns.OpenPanel()
h.flush()
LevelUp(h, 22)
equal(#h.fanfares, 0, "guide open: no glow")
equal(select(1, Pips(h)), false, "guide open: no pip")
equal(Marked(h, "zone:1424"), true, "guide open: the card is marked")
clean(h, "guide open")

-- A saved seen set: the same level-up on the next session finds nothing new.
local saved = Load()
LevelUp(saved, 22)
local again = Load(saved.G.AdventureGuideForeverCharDB)
again.player.level = 21
again.ns.Invalidate()
again.flush()
LevelUp(again, 22)
equal(#again.fanfares, 0, "seen last session: no glow")
clean(again, "saved")

-- A level gained before the first look (or with no save file) compares nothing.
h = harness.load({ charDB = {}, completed = { 844 }, log = {}, completedPending = true })
LevelUp(h, 22)
h.completedPending = false
h.fire("PLAYER_ENTERING_WORLD", false, true)
h.flush()
equal(#h.fanfares, 0, "before the first look: no glow")
clean(h, "before the first look")

-- In combat nothing is compared; the rebuild after it is.
h = Load()
h.SetCombat(true)
LevelUp(h, 22)
equal(#h.fanfares, 0, "in combat: nothing yet")
h.SetCombat(false)
h.flush()
same(h.fanfares, { "moment" }, "after combat: the line glows")
clean(h, "combat")

-- A new quest visit in a higher-level zone keeps the same range warning as its card.
h = Load()
h.ns.Prefs().seen["zone:1424"] = true
h.ns.Prefs().seen["zone:1411"] = true
h.ns.Prefs().seen["zone:1412"] = true
LevelUp(h, 22)
local visit
for _, journey in ipairs(h.ns.Route().journeys) do
	if journey.key == "zone:1450" then
		visit = journey
	end
end
equal(visit ~= nil, true, "quest visit: Moonglade is offered")
local warning = h.ns.Overview.VisitWarning(visit)
equal(warning ~= nil, true, "quest visit: the zone is above the character's level")
equal(Tracker(h), warning, "quest visit: alert keeps the range warning")
clean(h, "quest visit")

-- An aside no provider gave before: its own line glows, with the pips, and no moment line. One that stops being
-- given leaves the seen set, so it is new again when it comes back. Hillsbrad and Moonglade, zones to head to from
-- level 20, are turned down so the line level 20 brings is the calling's.
h = Load({
	notInterested = {
		["zone:1424"] = "Head to Hillsbrad Foothills",
		["zone:1450"] = "Head to Moonglade",
		["zone:1411"] = "Durotar",
		["zone:1412"] = "Mulgore",
	},
})
local provider = {}
h.ns.Asides.Register(function()
	return provider.aside
end)
h.ns.Invalidate()
h.flush()
provider.aside = { key = "trainer", text = "Visit your class trainer · 1 new spell", icon = "class" }
LevelUp(h, 19)
same(h.fanfares, { "aside" }, "new aside: its line glows")
equal(Tracker(h), nil, "new aside: no moment line")
equal(select(1, Pips(h)), true, "new aside: the tab's pip")
equal(h.G.AdventureGuideForeverCharDB.seen["aside:trainer"], true, "new aside: seen")
LevelUp(h, 20)
same(h.fanfares, { "aside", "moment" }, "the same aside: no glow; the calling level 20 opens glows")
equal(Tracker(h), "A task for your class: Call of Water", "your calling: says what it offers")
provider.aside = nil
h.ns.Invalidate()
h.flush()
equal(h.G.AdventureGuideForeverCharDB.seen["aside:trainer"], nil, "aside gone: leaves the seen set")
provider.aside = { key = "trainer", text = "Visit your class trainer · 2 new spells", icon = "class" }
LevelUp(h, 21)
same(h.fanfares, { "aside", "moment", "aside" }, "aside back: new again")
-- Every spell trained at the trainer brings no rebuild, only SPELLS_CHANGED; the next level's spells are still new.
provider.aside = nil
h.fire("SPELLS_CHANGED")
h.flush()
equal(h.G.AdventureGuideForeverCharDB.seen["aside:trainer"], nil, "trained: leaves the seen set without a rebuild")
provider.aside = { key = "trainer", text = "Visit your class trainer · 1 new spell", icon = "class" }
LevelUp(h, 21)
same(h.fanfares, { "aside", "moment", "aside", "aside" }, "trained, then a level: new again")
clean(h, "aside")

-- Entering an already offered zone does not repeat the announcement.
h = Load()
h.player.map = 1436
h.fire("ZONE_CHANGED_NEW_AREA")
h.flush()
same(h.fanfares, {}, "known zone entered: no repeated glow")
equal(Tracker(h), nil, "known zone entered: no repeated line")
clean(h, "zone entered")

-- With the tracker section off, the card and the pips still say it; nothing glows.
h = harness.load({ db = { showTracker = false }, charDB = {}, completed = { 844 }, log = {} })
LevelUp(h, 22)
equal(#h.fanfares, 0, "tracker off: no glow")
equal(select(1, Pips(h)), true, "tracker off: the pip")
clean(h, "tracker off")

-- At the cap the dungeon card and a way into an instance are both fresh; the dungeon card leads, so the moment is
-- its level line rather than the way-in's open line.
h = harness.load({ player = { level = 1 }, charDB = { quests = false, seen = { ["dungeon:329"] = true } } })
h.flush()
LevelUp(h, 70)
equal(Tracker(h), "Blackrock Spire is now for your level", "level cap: the dungeon card names the level")
clean(h, "level cap")

print(("moments_spec: %d checks passed"):format(checks))
