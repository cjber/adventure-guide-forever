-- Run from the repository root: luajit tests/pvp_spec.lua
-- PvP (docs/design.md §2.15): the opt-in Battlegrounds card in the planner, then through tests/harness.lua the
-- battleground aside, the next PvP rank's reward, and a client without either API.
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

--[[ The card (Model.lua, roadmap #12): a battleground open to the player, whose one step is its battlemaster ]]

local ns = {}
local core = assert(loadfile("Core.lua"))
setfenv(
	core,
	setmetatable({
		EventUtil = { ContinueOnAddOnLoaded = function() end },
		SlashCmdList = {},
		CreateFrame = function()
			return { SetScript = function() end }
		end,
	}, { __index = _G })
)
core("AdventureGuideForever", ns)
assert(loadfile("Model.lua"))("AdventureGuideForever", ns)
local Model = ns.Model

local arena = {
	quests = {},
	zones = { [1] = { name = "Zone", min = 10, max = 20 } },
	maps = { [1] = { name = "Home", continent = 1, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
	continents = { [1] = { x = 0, y = 0 } },
	hubs = { [5] = { name = "Crossroads, The Barrens" } },
	npcs = {
		[800] = { bg = 2, side = 2, place = { map = 1, x = 0.6, y = 0.5, name = "Near", hub = 5 } },
		[801] = { bg = 2, side = 2, place = { map = 1, x = 0.9, y = 0.5, name = "Far" } },
		[802] = { bg = 2, side = 1, place = { map = 1, x = 0.51, y = 0.5, name = "Alliance" } },
		[803] = { bg = 3, side = 3, place = { map = 1, x = 0.2, y = 0.5, name = "Basin" } },
		[804] = { class = 7, upto = 60, side = 2, place = { map = 1, x = 0.5, y = 0.5, name = "Trainer" } },
	},
}
local WSG = { id = 2, name = "Warsong Gulch", level = 10 }
local AB = { id = 3, name = "Arathi Basin", level = 20 }
local DI = { id = 1157, name = "Darkspear Islands", level = 30 }
local player = { level = 20, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
player.battlegrounds = { AB, WSG }
local function Prefs(extra)
	local prefs = { quests = true, dungeons = false, battlegrounds = true, skipped = {}, notInterested = {} }
	for key, value in pairs(extra or {}) do
		prefs[key] = value
	end
	return prefs
end
local function Card(route)
	for _, journey in ipairs(route.journeys) do
		if journey.kind == "battleground" then
			return journey
		end
	end
end

equal(Card(Model.Plan(arena, player, {}, {}, Prefs({ battlegrounds = false }))), nil, "card: off by default")
local route = Model.Plan(arena, player, {}, {}, Prefs())
local card = Card(route)
equal(card.key, "battleground:3", "card: the newest open battleground")
equal(card.title .. "|" .. card.subline, "Arathi Basin|A battleground open to you", "card: its name and subline")
equal(card.reason, "Battlemaster in Home", "card: its battlemaster's town, else the map's name")
equal(#card.steps, 1, "card: one step")
local step = card.steps[1]
equal(step.kind .. "|" .. step.key, "battlemaster|battlemaster:803", "step: a battlemaster of either side")
equal(step.reason .. "|" .. step.detail, "Queue for Arathi Basin|Queue for Arathi Basin", "step: its reason")
equal(step.place .. "|" .. step.zone .. "|" .. #step.quests, "Basin|Home|0", "step: the NPC, the zone, no quests")
equal(card.hub, "Basin", "card: its hub line is the NPC")

-- The chosen battleground is the card while it is open, at the nearest battlemaster of the player's side.
local chosen = Model.Plan(arena, player, {}, {}, Prefs({ journey = "battleground:2" }))
equal(chosen.chosen, true, "chosen: kept")
equal(chosen.steps[1].key, "battlemaster:800", "chosen: the nearest of the side, never the other side's")
equal(chosen.steps[1].title, "Battlemaster in Crossroads", "chosen: its flight-master town")
local npc, id = Model.Battlemaster(arena, player, 2)
equal(npc.place.name .. "|" .. id, "Near|800", "battlemaster: the NPC and its entry")
equal(Model.Battlemaster(arena, player, 1157), nil, "battlemaster: none where the data places none")
equal(Model.Battlemaster(arena, { side = 2 }, 2), nil, "battlemaster: none without the player's place")
-- In a fight the cheap rebuild keeps the step: nothing changes it there.
equal(
	Model.Refresh(arena, player, {}, {}, Prefs({ journey = "battleground:2" }), chosen).steps[1].key,
	"battlemaster:800",
	"combat: kept"
)

-- Darkspear Islands has no battlemaster in the data: never a card, so the next newest is.
player.level, player.battlegrounds = 30, { DI, AB, WSG }
equal(Card(Model.Plan(arena, player, {}, {}, Prefs())).key, "battleground:3", "no battlemaster: the next newest")
equal(
	Card(Model.Plan(arena, player, {}, {}, Prefs({ journey = "battleground:1157" }))).key,
	"battleground:3",
	"no battlemaster: not even chosen"
)
local dismissed = Prefs({ notInterested = { ["battleground:3"] = "Arathi Basin" } })
equal(Card(Model.Plan(arena, player, {}, {}, dismissed)).key, "battleground:2", "not interested: the next one")
local skipped = Prefs()
skipped.skipped["battlemaster:803"] = true
local held = Model.Plan(arena, player, {}, {}, skipped)
equal(Card(held), nil, "skipped: no card")
equal(held.skipped["battlemaster:803"], true, "skipped: Skipped (n) keeps it")
player.battlegrounds = {}
equal(Card(Model.Plan(arena, player, {}, {}, Prefs())), nil, "none open: no card")
player.battlegrounds = nil
equal(Card(Model.Plan(arena, player, {}, {}, Prefs())), nil, "no list: no card")

--[[ The asides and the cog, through the harness ]]

local OPENS = {
	[10] = { { id = 2, name = "Warsong Gulch" } },
	[20] = { { id = 3, name = "Arathi Basin" } },
	[30] = { { id = 1157, name = "Darkspear Islands" } },
}

-- ui_spec's level-18 orc shaman in The Barrens, with the carry card chosen.
local function Load(options)
	options.charDB = options.charDB or { journey = "carry" }
	options.completed = { 844 }
	options.log =
		{ { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } }
	return harness.load(options)
end
local function Settle(h)
	h.ns.Invalidate()
	h.flush()
end

-- A battleground open to you: the newest, at its nearest battlemaster; the level-up list is asked once a level.
do
	local h = Load({ battlegrounds = OPENS, instanceType = "none" })
	Settle(h)
	local aside = h.ns.Asides.Current()
	equal(aside.key, "battleground:2", "aside: Warsong Gulch at 18")
	equal(aside.text, "Warsong Gulch is open to you", "aside: its line")
	equal(aside.icon, "battlemaster", "aside: the battlemaster mark")
	local master = h.ns.Model.Battlemaster(h.ns.Data, h.ns.State.Player(), 2)
	equal(aside.place, master.place, "aside: at the nearest battlemaster")
	equal(master.side % 4 >= 2 and master.bg, 2, "aside: a Horde Warsong Gulch battlemaster")
	local asks = h.levelUpAsks
	Settle(h)
	equal(h.levelUpAsks, asks, "asks: each level once")
	h.player.level = 30
	Settle(h)
	aside = h.ns.Asides.Current()
	equal(
		aside.text .. "|" .. tostring(aside.place),
		"Darkspear Islands is open to you|nil",
		"aside: text only without one"
	)
	local names = {}
	for _, bg in ipairs(h.ns.State.Battlegrounds()) do
		names[#names + 1] = bg.name .. "@" .. bg.level
	end
	equal(table.concat(names, " "), "Darkspear Islands@30 Arathi Basin@20 Warsong Gulch@10", "open: the newest first")

	-- Standing in a battleground acts on it: gone, and remembered per character; the next to open brings the next.
	h.player.level = 25
	Settle(h)
	h.instanceType = "pvp"
	h.fire("ZONE_CHANGED_NEW_AREA")
	h.flush()
	equal(h.ns.Asides.Current(), nil, "battled: acted on")
	equal(h.G.AdventureGuideForeverCharDB.battled, 25, "battled: the level, per character")
	h.player.level = 30
	Settle(h)
	equal(h.ns.Asides.Current().key, "battleground:1157", "battled: the next battleground to open")
	clean(h, "aside")
end

-- The cog's Battlegrounds box, off by default; a chosen card the box hides keeps its choice.
do
	local h = Load({ battlegrounds = OPENS, charDB = {} })
	Settle(h)
	equal(h.ns.Prefs().battlegrounds, false, "cog: off by default")
	h.ns.OpenPanel()
	local cog = h.Find(function(frame)
		return frame.stockTemplate == "UIPanelIconDropdownButtonTemplate"
	end)[1]
	local box
	for _, entry in ipairs(h.OpenMenu(cog).entries) do
		box = box or (entry.kind == "checkbox" and entry.text == "Battlegrounds" and entry)
	end
	equal(box.isSelected(), false, "cog: unticked")
	box.onClick()
	h.flush()
	equal(box.isSelected(), true, "cog: ticked")
	h.ns.Choose("battleground:2")
	h.flush()
	local cogRoute = h.ns.Route()
	equal(cogRoute.chosen and cogRoute.steps[1].kind, "battlemaster", "cog: the chosen card's step")
	equal(Card(cogRoute).key, "battleground:2", "cog: its card")
	box.onClick()
	h.flush()
	equal(h.ns.Prefs().journey, "battleground:2", "cog: unticked keeps the choice")
	equal(h.ns.Route().chosen, false, "cog: and no card")
	clean(h, "cog")
end

-- A level that opens a battleground brings its card, whose moment says it is open (Moments.lua); the calling, new at
-- the same level, is turned down so the line is the card's.
do
	local charDB = { battlegrounds = true, notInterested = { calling = "Your calling" } }
	local h = harness.load({ battlegrounds = OPENS, charDB = charDB, completed = { 844 }, log = {} })
	h.player.level = 19
	h.fire("PLAYER_LEVEL_UP")
	h.flush()
	h.player.level = 20
	h.fire("PLAYER_LEVEL_UP")
	h.flush()
	equal(Card(h.ns.Route()).key, "battleground:3", "moment: the card of the battleground just opened")
	local block = h.tracker.liveBlocks.moment
	equal(block and block.header, "Arathi Basin is open to you", "moment: its line")
	clean(h, "moment")
end

-- The next PvP rank's reward, in its own words and with its own icon, for a character with rank points.
do
	local rank = {
		info = { renownLevel = 5, renownReputationEarned = 10, renownLevelThreshold = 100, maxLevel = 14 },
		rewards = { [7] = { { icon = 135000 }, { icon = 136000, description = "Knight's tabard" } } },
	}
	local h = Load({ rank = rank })
	Settle(h)
	local aside = h.ns.Asides.Current()
	equal(aside.key .. "|" .. aside.text, "pvprank|Rank 7 · Knight's tabard", "rank: the next reward")
	equal(aside.texture, 136000, "rank: its icon")
	h.ns.OpenPanel()
	Settle(h)
	local line = h.Find(function(frame)
		return frame.Skip ~= nil and frame.Icon ~= nil and frame:IsVisible()
	end)[1]
	equal(line.Icon.file, 136000, "rank: drawn as a texture")
	-- The next rank with rewards speaks for them all, as the character pane does: none described, no line.
	rank.rewards[6] = { { icon = 135000 } }
	Settle(h)
	equal(h.ns.Asides.Current(), nil, "rank: the next rewards have no description")
	rank.rewards[6] = nil
	rank.info = { renownLevel = 0, renownReputationEarned = 0, renownLevelThreshold = 100, maxLevel = 14 }
	Settle(h)
	equal(h.ns.Asides.Current(), nil, "rank: no rank points, no line")
	rank.info.renownReputationEarned = 1
	rank.rewards[1] = { { icon = 134000, description = "A title" } }
	Settle(h)
	equal(h.ns.Asides.Current().text, "Rank 1 · A title", "rank: the first rank's")
	rank.info.renownLevel, rank.info.maxLevel = 14, 14
	Settle(h)
	equal(h.ns.Asides.Current(), nil, "rank: none past the season's last")
	clean(h, "rank")
end

-- A client without C_PvP, C_MajorFactions or IsInInstance: no line, no card, no error.
do
	local h = Load({ charDB = { journey = "carry", battlegrounds = true } })
	Settle(h)
	equal(h.ns.Asides.Current(), nil, "no API: no aside")
	equal(#h.ns.State.Battlegrounds(), 0, "no API: nothing open")
	equal(Card(h.ns.Route()), nil, "no API: no card")
	h.fire("ZONE_CHANGED_NEW_AREA")
	equal(h.G.AdventureGuideForeverCharDB.battled, nil, "no API: nothing recorded")
	clean(h, "no API")
end

print(("pvp_spec: %d checks passed"):format(checks))
