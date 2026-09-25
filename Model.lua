---@type string, AGFNamespace
local _, ns = ...
---@class AGFModel
-- Nine steps: the stock numerals (services-number-1..9) that label each step stop at 9. Six journeys (design §2.2): the
-- story, Loose ends, three zones to head to and a diversion, in the room the panel has; it builds as many cards.
local Model = { MAX_STEPS = 9, MAX_JOURNEYS = 6 }
ns.Model = Model

-- CMaNGOS mangos-classic/src/game/Tools/Formulas.h, GetQuestGreenRange (quest, not creature XP).
local GREEN_RANGE = { 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12 }
local CLOSE = 0.03 * 0.03
-- What a stop is worth against the yards to reach it (docs/plan.md §7.3): each quest there (at most 8), a quest that
-- goes grey at the next level, each hand-in, and a stop with no hand-in where every quest is red or optional, which
-- waits.
local VALUE_QUEST, VALUE_QUESTS_MAX, VALUE_GREY_RISK, VALUE_HAND_IN, VALUE_WEAK = 40, 8, 150, 60, -300
local ORANGE = 3 -- levels above the player: the stock orange, where a quest gets hard alone
local NONE = {} -- an empty list for the hot loops to walk without allocating one; never written

function Model.IsGray(questLevel, playerLevel)
	local range = GREEN_RANGE[math.min(#GREEN_RANGE, math.floor(playerLevel / 5) + 1)] or 4
	return questLevel > 0 and playerLevel - questLevel > range
end

local function ValidPlace(place)
	return place
		and type(place.map) == "number"
		and place.map > 0
		and type(place.x) == "number"
		and place.x >= 0
		and place.x <= 1
		and type(place.y) == "number"
		and place.y >= 0
		and place.y <= 1
end

local function HasBit(mask, bit)
	return not mask or mask == 0 or (bit > 0 and math.floor(mask / bit) % 2 == 1)
end

local function Count(one, many, count)
	return count == 1 and one or many:format(count)
end

local function Distance(a, b)
	if not ValidPlace(a) or a.map ~= b.map then
		return 1000000
	end
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

-- Only immutable bundled data is memoized; player/log/completion tables may change in place.
---@class AGFIndex
---@field ids integer[]
---@field groups table<integer, integer[]>
---@field sides table<integer, integer[]> by side, the IDs a player of it could ever take: its own side's or both
---sides', with a start the data places, not repeatable (Check's first lines)
---@type table<AGFData, AGFIndex>
local indexes = setmetatable({}, { __mode = "k" })

local function Index(data)
	local index = indexes[data]
	if index then
		return index
	end
	index = { ids = {}, groups = {}, sides = { {}, {} } }
	for id in pairs(data.quests) do
		index.ids[#index.ids + 1] = id
	end
	table.sort(index.ids)
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		if quest.group and quest.group > 0 then
			local group = index.groups[quest.group] or {}
			index.groups[quest.group] = group
			group[#group + 1] = id
		end
		for side, ids in ipairs(ValidPlace(quest.start) and not quest.repeatable and index.sides or NONE) do
			ids[#ids + 1] = (quest.side == 3 or quest.side == side) and id or nil
		end
	end
	indexes[data] = index
	return index
end

-- Stories (docs/design.md §2.3): the chain a quest belongs to, from the data's `next` links, which nothing else reads.
-- `prev[id]` is the one quest whose `next` is id, or false when several lead into it. Memoized like Index.
---@class AGFChains
---@field prev table<integer, integer|false>
---@field stories table<integer, AGFStory|false>
---@type table<AGFData, AGFChains>
local chains = setmetatable({}, { __mode = "k" })

-- Walks back to the chain's head, then forward along `next`. No story when the way back forks (which head's
-- chapter count would it be?) or loops, or when the chain is one quest. The total is shown only when the data proves
-- it: every member has at most one `pre` and no `preAny`, and the walk ends on a quest in the data with no `next`.
---@return AGFStory?
local function Walk(data, prev, questID)
	local head, seen = questID, { [questID] = true }
	while prev[head] ~= nil do
		local before = prev[head]
		if not before or seen[before] then
			return nil
		end
		head, seen[before] = before, true
	end
	local members, proven, chapter, id = {}, true, nil, head
	seen = {}
	while id do
		local quest = data.quests[id]
		if not quest or seen[id] then
			proven = false -- a `next` that dangles or loops: the end is unknown
			break
		end
		seen[id], members[#members + 1] = true, id
		chapter = id == questID and #members or chapter
		proven = proven and not quest.preAny and #(quest.pre or NONE) <= 1
		id = quest.next
	end
	if #members < 2 or not chapter then
		return nil
	end
	return { chapter = chapter, total = proven and #members or nil, members = members }
end

---@return AGFStory?
function Model.Story(data, questID)
	local memo = chains[data]
	if not memo then
		memo = { prev = {}, stories = {} }
		for _, id in ipairs(Index(data).ids) do
			local nextID = data.quests[id].next
			if nextID then
				memo.prev[nextID] = memo.prev[nextID] == nil and id or false
			end
		end
		chains[data] = memo
	end
	local story = memo.stories[questID]
	if story == nil then
		story = data.quests[questID] and Walk(data, memo.prev, questID) or false
		memo.stories[questID] = story
	end
	return story or nil
end

-- English race and class names by UnitRace/UnitClass ID, the fallback when the client names none (a headless spec).
local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }
RACES[10], RACES[11] = "Blood Elf", "Draenei"
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest" }
CLASSES[7], CLASSES[8], CLASSES[9], CLASSES[11] = "Shaman", "Mage", "Warlock", "Druid"
local SIDE_RACES = { 1 + 4 + 8 + 64, 2 + 16 + 32 + 128 } -- each side's four classic races, as bit masks
local ALL_CLASSES = 1 + 2 + 4 + 8 + 16 + 64 + 128 + 256 + 1024

-- Whether `mask` holds every bit of `bits`; an absent or zero mask holds everything, as in HasBit.
local function Covers(mask, bits)
	for id = 0, 15 do
		local bit = 2 ^ id
		if math.floor(bits / bit) % 2 == 1 and not (not mask or mask == 0 or math.floor(mask / bit) % 2 == 1) then
			return false
		end
	end
	return true
end

-- Every name a mask holds, joined: the client's (`lookup`) first, the English above otherwise.
local function MaskNames(mask, lookup, english)
	local names = {}
	for id = 1, 16 do
		if math.floor(mask / 2 ^ (id - 1)) % 2 == 1 then
			names[#names + 1] = (lookup and lookup(id)) or english[id]
		end
	end
	return table.concat(names, ns.L.LIST_SEPARATOR)
end

-- Reputation standings in the data's and the client's scale (0 starts Neutral), each rank's first point in reaction
-- order 1 Hated to 8 Exalted, and their English names (the client's FACTION_STANDING_LABEL1-8 otherwise).
local THRESHOLDS = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }
local STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- The reaction whose rank starts at exactly `value`; nil between ranks.
local function Reaction(value)
	for reaction, threshold in ipairs(THRESHOLDS) do
		if threshold == value then
			return reaction
		end
	end
	return nil
end

-- A reputation line: "Requires Friendly with X", "Only while below Exalted with X" (a maximum below a rank's first
-- point, or one short of it), or a plain line naming the faction when the value falls between ranks.
---@param names? AGFWhyNames
local function RepText(data, rep, key, names)
	local L = ns.L
	local faction = (names and names.faction and names.faction(rep.faction))
		or (data.factions and data.factions[rep.faction] and data.factions[rep.faction].name)
		or ""
	local reaction
	if key == "repMin" then
		reaction = Reaction(rep.min)
	else
		reaction = Reaction(rep.max) or Reaction(rep.max + 1)
	end
	if not reaction then
		return L.WHY_REPUTATION:format(faction)
	end
	local standing = (names and names.standing and names.standing(reaction)) or STANDINGS[reaction]
	return (key == "repMin" and L.WHY_REP_MIN or L.WHY_REP_BELOW):format(standing, faction)
end

---@param names? AGFWhyNames
local function Title(data, id, names)
	local quest = data.quests[id]
	return (names and names.title and names.title(id)) or (quest and quest.title) or ns.L.WHY_EARLIER_QUEST
end

-- One requirement's line. Built only when Why asks, so the planner's pass never formats a string.
---@param names? AGFWhyNames
local function WhyText(data, key, arg, names)
	local L = ns.L
	if key == "side" then
		return arg == 1 and L.WHY_ALLIANCE or L.WHY_HORDE
	elseif key == "level" then
		return L.WHY_LEVEL:format(arg)
	elseif key == "races" then
		return L.WHY_RACES:format(MaskNames(arg, names and names.race, RACES))
	elseif key == "classes" then
		return L.WHY_CLASSES:format(MaskNames(arg, names and names.class, CLASSES))
	elseif key == "pre" then
		return L.WHY_COMPLETED:format(Title(data, arg, names))
	elseif key == "preAny" then
		local titles = {}
		for index, id in ipairs(arg) do
			titles[index] = Title(data, id, names)
		end
		return L.WHY_ONE_OF:format(table.concat(titles, L.LIST_SEPARATOR))
	elseif key == "group" then
		return L.WHY_CHOSE:format(Title(data, arg, names))
	elseif key == "breadcrumb" then
		return L.WHY_BREADCRUMB:format(Title(data, arg, names))
	elseif key == "skill" then
		local name = (names and names.skill and names.skill(arg.id))
			or (data.skills and data.skills[arg.id] and data.skills[arg.id].name)
			or ""
		return L.WHY_SKILL:format(name, arg.value)
	elseif key == "repMin" or key == "repMax" then
		return RepText(data, arg, key, names)
	end
	return L[key]
end

-- Records one requirement when Why passes `lines`. False tells the planner's pass (no `lines`) to stop there.
local function Line(data, lines, met, key, arg, names)
	if lines then
		lines[#lines + 1] = { text = WhyText(data, key, arg, names), met = met }
	end
	return met or lines ~= nil
end

-- The one eligibility check (docs/design.md §2.4). The planner passes no `lines` and it stops at the first unmet
-- requirement; Why passes `lines` and gets every requirement as a line. So the two never disagree: a quest is
-- eligible exactly when every line is met. A met line that says nothing (level 1, a whole side's races, every
-- class) is left out. `level` stands in for the player's own (the next-zone card asks what opens two levels on).
local function Check(data, player, completed, log, id, groups, level, lines, names)
	local quest = data.quests[id]
	if not quest then
		return false
	elseif not ValidPlace(quest.start) then
		-- The generator suppressed the start: the only line, since nothing else about the quest can be acted on.
		Line(data, lines, false, "WHY_NO_START")
		return false
	end
	if completed[id] and not Line(data, lines, false, "WHY_DONE") then
		return false
	elseif log[id] and not Line(data, lines, false, "WHY_IN_LOG") then
		return false
	elseif quest.repeatable and not Line(data, lines, false, "WHY_REPEATABLE") then
		return false
	end
	-- Each line below is written only when unmet (the planner stops there) or when Why asks and it says something.
	local met = quest.side == 3 or quest.side == player.side
	if not met or (lines and quest.side ~= 3) then
		if not Line(data, lines, met, "side", quest.side, names) then
			return false
		end
	end
	met = (level or player.level) >= quest.min
	if not met or (lines and quest.min > 1) then
		if not Line(data, lines, met, "level", quest.min, names) then
			return false
		end
	end
	met = HasBit(quest.races, player.raceBit)
	if not met or (lines and not Covers(quest.races, SIDE_RACES[player.side] or 0)) then
		if not Line(data, lines, met, "races", quest.races, names) then
			return false
		end
	end
	met = HasBit(quest.classes, player.classBit)
	if not met or (lines and not Covers(quest.classes, ALL_CLASSES)) then
		if not Line(data, lines, met, "classes", quest.classes, names) then
			return false
		end
	end
	-- A skill line the player hasn't learned has rank 0; a faction the client gives no standing for (the other side's)
	-- meets neither a minimum nor a maximum, since the data can't say where it stands.
	local skill = quest.skill
	if skill then
		met = ((player.skills and player.skills[skill.id]) or 0) >= skill.value
		if not Line(data, lines, met, "skill", skill, names) then
			return false
		end
	end
	local rep = quest.rep
	if rep then
		local standing = player.reputation and player.reputation(rep.faction)
		if rep.min and not Line(data, lines, standing ~= nil and standing >= rep.min, "repMin", rep, names) then
			return false
		elseif rep.max and not Line(data, lines, standing ~= nil and standing < rep.max, "repMax", rep, names) then
			return false
		end
	end
	for _, pre in ipairs(quest.pre or NONE) do
		met = pre > 0 and completed[pre] == true
		if (lines or not met) and not Line(data, lines, met, "pre", pre, names) then
			return false
		end
	end
	if quest.preAny then
		met = false
		for _, pre in ipairs(quest.preAny) do
			met = met or (pre > 0 and completed[pre] == true)
		end
		if not Line(data, lines, met, "preAny", quest.preAny, names) then
			return false
		end
	end
	for _, other in ipairs((quest.group and groups[quest.group]) or NONE) do
		if other ~= id and (completed[other] or log[other]) and not Line(data, lines, false, "group", other, names) then
			return false
		end
	end
	-- A breadcrumb leads to its target, and closes once the target is taken or done.
	local target = quest.breadcrumb
	if target and not Line(data, lines, not completed[target] and not log[target], "breadcrumb", target, names) then
		return false
	end
	return true
end

local function Eligible(data, player, completed, log, id, groups, level)
	return Check(data, player, completed, log, id, groups, level)
end

function Model.Eligible(data, player, completed, log, questID)
	return Eligible(data, player, completed, log, questID, Index(data).groups)
end

-- Why a quest is or isn't open to the player: each requirement the data carries, met or not (docs/design.md §2.4).
---@param names? AGFWhyNames the client's names for quests, races and classes
---@return AGFWhyLine[]
function Model.Why(data, player, completed, log, questID, names)
	local lines = {}
	Check(data, player, completed, log, questID, Index(data).groups, nil, lines, names)
	return lines
end

local SEARCH_MAX = 10

-- The player's side's quests whose title holds `query` (plain, case-insensitive, as the quest log's search), by title
-- then ID, at most 10: the search's rows (docs/design.md §2.4). `title` is the client's, the data's otherwise.
---@param title? fun(questID: integer): string?
---@return integer[]
function Model.Search(data, player, query, title)
	query = query:lower()
	local found, titles = {}, {}
	for id, quest in pairs(data.quests) do
		if quest.side == 3 or quest.side == player.side then
			local name = (title and title(id)) or quest.title
			if name:lower():find(query, 1, true) then
				found[#found + 1], titles[id] = id, name
			end
		end
	end
	table.sort(found, function(a, b)
		if titles[a] ~= titles[b] then
			return titles[a] < titles[b]
		end
		return a < b
	end)
	for index = #found, SEARCH_MAX + 1, -1 do
		found[index] = nil
	end
	return found
end

-- "Not this quest" (docs/design.md §2.18): a quest ruled out on this character stays in the log, and out of every plan.
-- The IDs are read from `prefs.notInterested` once per build (ReadDropped, at Model.Journeys and Model.Refresh), so the
-- planner's loops over every quest never build a key.
---@type table<integer, true>
local droppedIDs = {}

---@param prefs AGFPrefs
local function ReadDropped(prefs)
	droppedIDs = {}
	for key in pairs(prefs.notInterested or NONE) do
		local id = type(key) == "string" and tonumber(key:match("^quest:(%d+)$"))
		if id then
			droppedIDs[id] = true
		end
	end
end

---@param id integer
---@return boolean
local function Dropped(id)
	return droppedIDs[id] == true
end

-- How a zone ranks (docs/design.md §2.2), lowest first. Quest fit leads: each quest's distance from the level, doubled
-- past two levels up. The zone's range (the client's zone levels, `data.zones`) comes next: two a level outside it, up
-- to one less in the lower half the player has just entered, and up to three more in its top fifth, where what is left
-- is cleanup the story's laps and Loose ends already hold. A zone with more quests edges ahead, up to eight of them; at
-- a like fit the nearer one does (`far`).
local ZONE_OUTSIDE = 2 -- a level outside the zone's range
local ZONE_FRESH = 2 -- the lower half: this less, times how far short of its middle the level is
local ZONE_TOP, ZONE_CLEANUP = 0.8, 3 -- the top fifth: up to this more, at the zone's last level
local ZONE_QUEST, ZONE_QUESTS = 0.25, 8 -- this less a quest, for this many at most

-- The maps of the zones that fit `level` for the quests `ids`, best first, and how many of those quests each holds. An
-- outdoor elite is optional (roadmap #16): it rides along on its zone's cards but never picks the zone a solo player is
-- sent to. A raid's quest, which no card offers, never picks one either. `far` is a zone's distance cost from the
-- player (Journeys' Far).
---@param far fun(map: integer): number
---@return integer[] maps
---@return table<integer, integer> quests
local function Rank(data, ids, level, far)
	local choices, scores, quests = {}, {}, {}
	for _, id in ipairs(ids) do
		local quest = data.quests[id]
		local map = quest.zone or (quest.start and quest.start.map)
		local zone = map and data.zones[map]
		if
			zone
			and not quest.raid
			and not Model.IsGray(quest.level, level)
			and not (quest.elite and not quest.dungeon)
		then
			if not quests[map] then
				choices[#choices + 1], quests[map], scores[map] = map, 0, 0
			end
			quests[map] = quests[map] + 1
			local questLevel = quest.level == -1 and level or quest.level
			scores[map] = scores[map] + math.abs(questLevel - level) + math.max(0, questLevel - level - 2)
		end
	end
	for _, map in ipairs(choices) do
		local zone = data.zones[map]
		local into = zone.max > zone.min and (level - zone.min) / (zone.max - zone.min) or 0
		scores[map] = scores[map] / quests[map]
			+ math.max(0, zone.min - level, level - zone.max) * ZONE_OUTSIDE
			- math.max(0, 0.5 - into) * ZONE_FRESH
			+ math.max(0, math.min(into, 1) - ZONE_TOP) / (1 - ZONE_TOP) * ZONE_CLEANUP
			- math.min(quests[map], ZONE_QUESTS) * ZONE_QUEST
			+ far(map)
	end
	table.sort(choices, function(a, b)
		if scores[a] ~= scores[b] then
			return scores[a] < scores[b]
		end
		if quests[a] ~= quests[b] then
			return quests[a] > quests[b]
		end
		return a < b
	end)
	return choices, quests
end

-- One eligibility pass for two levels: the player's, and `ahead` levels on for the next-zone cards. A level reaches
-- eligibility only through a quest's minimum, so what opens at level + ahead holds everything open now. Only an
-- instance's quests wait behind Dungeons: an outdoor elite is a zone's quest, optional and badged for a group. An
-- orange or red quest (ORANGE levels up or more) is never offered, though its minimum allows it: too hard alone. The
-- zones that fit now also count the log's quests the data has, as a pickup each: a zone the player has taken on is
-- where they are adventuring, though little is left there to pick up. A quest the player ruled out (Dropped) counts
-- nowhere; one they added (shift-click, `prefs.pinned`) is offered once open whatever its colour.
---@param far fun(map: integer): number
local function Choices(data, player, completed, log, index, prefs, ahead, far)
	local eligible, later, target, ranked, pinned = {}, {}, player.level + (ahead or 0), {}, prefs.pinned or {}
	for id in pairs(prefs.quests and log or NONE) do
		ranked[#ranked + 1] = data.quests[id] and not Dropped(id) and id or nil
	end
	table.sort(ranked)
	for _, id in ipairs(index.sides[player.side] or index.ids) do
		local quest = data.quests[id]
		local instance = quest.dungeon ~= nil
		-- The level and completion first: Eligible would say no to most for them, at more cost.
		if
			quest.min <= target
			and not completed[id]
			and ((instance and prefs.dungeons) or (not instance and prefs.quests))
			and not Dropped(id)
			and Eligible(data, player, completed, log, id, index.groups, target)
		then
			later[#later + 1] = id
			if
				quest.min <= player.level
				and (
					pinned[id]
					or (not Model.IsGray(quest.level, player.level) and quest.level - player.level < ORANGE)
				)
			then
				eligible[#eligible + 1] = id
				ranked[#ranked + 1] = id
			end
		end
	end
	local zones = Rank(data, ranked, player.level, far)
	if not ahead then
		return zones, eligible
	end
	return zones, eligible, Rank(data, later, target, far) -- multi-value: the zones ahead and their quests
end

-- Every quest giver on `mapID` with a quest the player can take now, one entry per NPC or object, like the
-- game's own "!". Gray quests stay hidden, as the game hides them unless low-level tracking is on.
---@return AGFGiver[]
function Model.Givers(data, player, completed, log, mapID)
	local index, byPlace, givers = Index(data), {}, {}
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		local start = quest.start
		if
			start
			and start.map == mapID
			and not Model.IsGray(quest.level, player.level)
			and Eligible(data, player, completed, log, id, index.groups)
		then
			local key = string.format("%s:%.4f:%.4f", start.name, start.x, start.y)
			local giver = byPlace[key]
			if not giver then
				giver = { map = mapID, x = start.x, y = start.y, title = start.name, quests = {} }
				byPlace[key] = giver
				givers[#givers + 1] = giver
			end
			giver.quests[#giver.quests + 1] = id
		end
	end
	return givers
end

-- A quest's level for its colour: the log's, the data's otherwise; a scaling quest (-1) is the player's own.
local function QuestLevel(data, log, player, id)
	local entry, quest = log[id], data.quests[id]
	local level = (entry and entry.level) or (quest and quest.level)
	return (level and level > 0) and level or player.level
end

-- Not grey now, grey at the next level: the stock colours' last chance.
local function GreyRisk(level, player)
	return not Model.IsGray(level, player.level) and Model.IsGray(level, player.level + 1)
end

local function Optional(quest, level, player)
	return (quest and (quest.elite or quest.dungeon) and true)
		or level > player.level + 2
		or Model.IsGray(level, player.level)
end

local function Step(kind, key, title, place, id, optional, reason)
	return {
		kind = kind,
		key = key,
		title = title,
		detail = reason,
		reason = reason,
		quests = { id },
		map = place.map,
		x = place.x,
		y = place.y,
		optional = optional or nil,
	}
end

-- The town a place stands in (the data's hub), so a stop keeps its identity when one of the town's quests is taken
-- or done. A place the generator could not put in a town is a town of its own.
---@param place AGFPlace
local function Hub(place)
	return place.hub and tostring(place.hub) or string.format("%d:%.4f:%.4f", place.map, place.x, place.y)
end

-- The visit to `place`'s town among `stops` (by key), made and added to `steps` when the card has none yet, with quest
-- `id` added to its `list` ("handins" or "pickups"), which `place` finishes or starts. Every card keys a town the same
-- way, so a town skipped is skipped wherever it shows. Its point is the first quest's place until Build moves it to
-- the giver nearest the route. `follow` holds the chapters its hand-ins open there (Opens).
---@param place AGFPlace
---@param list "handins"|"pickups"
---@return AGFStep
local function Visit(stops, steps, place, list, id)
	local key = "town:" .. Hub(place)
	local town = stops[key]
	if not town then
		town = {
			kind = "town",
			key = key,
			hub = place.hub,
			title = "",
			detail = "",
			reason = "",
			quests = {},
			pickups = {},
			handins = {},
			follow = {},
			givers = {},
			group = 0,
			spots = {},
			map = place.map,
			x = place.x,
			y = place.y,
		}
		stops[key] = town
		steps[#steps + 1] = town
	end
	town[list][#town[list] + 1] = id
	town.quests[#town.quests + 1] = id
	town.spots[id] = place
	return town
end

-- A town's quests, givers, group count, title and detail, from its pickups and hand-ins; it is optional only when
-- every quest there is. The quests go hand-ins
-- first, then those grey at the next level, then nearest the player's level, then by ID (docs/plan.md §7.3); the givers
-- and the quest ShowQuest opens follow that order. One quest keeps the single step's title; several take the town's
-- name, else their busiest giver's.
-- Describe's sort key per quest ID, reused across calls: hand-in first, then grey at the next level, then the level
-- gap, then the ID, packed into one exact number.
---@type table<integer, number>
local describeOrder = {}
local function DescribeBefore(a, b)
	return describeOrder[a] < describeOrder[b]
end

---@param step AGFStep
---@param log table<integer, AGFLogQuest>
local function Describe(data, log, player, step)
	local L = ns.L
	-- A trainer's stop (roadmap #5) has no quests: its reason is the spells waiting there.
	if step.kind == "trainer" then
		step.reason = Count(L.TRAINER_SPELL, L.TRAINER_SPELLS, player.train.count)
		step.detail = step.reason
		return
	end
	local optional, handins, pickups = true, step.handins or NONE, step.pickups or NONE
	for pass = 1, 2 do
		for _, id in ipairs(pass == 1 and handins or pickups) do
			local level = QuestLevel(data, log, player, id)
			describeOrder[id] = ((pass - 1) * 2 + (GreyRisk(level, player) and 0 or 1)) * 2 ^ 40
				+ math.abs(level - player.level) * 2 ^ 32
				+ id
			optional = optional and Optional(data.quests[id], level, player)
		end
	end
	step.optional = optional or nil
	table.sort(step.handins, DescribeBefore)
	table.sort(step.pickups, DescribeBefore)
	local quests, givers, counts, group = {}, {}, {}, 0
	for pass = 1, 2 do
		for _, id in ipairs(pass == 1 and handins or pickups) do
			quests[#quests + 1] = id
			local name, quest = step.spots[id].name, data.quests[id]
			if not counts[name] then
				counts[name], givers[#givers + 1] = 0, name
			end
			counts[name] = counts[name] + 1
			group = group + ((quest and (quest.elite or quest.dungeon or quest.raid)) and 1 or 0)
		end
	end
	local busiest = givers[1]
	for _, name in ipairs(givers) do
		busiest = counts[name] > counts[busiest] and name or busiest
	end
	local town = step.hub and data.hubs and data.hubs[step.hub]
	step.quests, step.givers, step.group = quests, givers, group
	step.place = town and town.name or busiest
	if #quests == 1 then
		local id, quest = quests[1], data.quests[quests[1]]
		if #step.handins == 1 then
			step.title = L.TURN_IN:format((log[id] and log[id].title) or quest.title)
			step.reason = (step.returns and step.returns[id]) and L.HAND_IN_WHEN_DONE or L.READY_TO_HAND_IN
		else
			step.title = L.PICK_UP:format(step.spots[id].name)
			step.reason = (quest.pre or quest.preAny) and L.CONTINUES_STORY or L.NEAR_YOUR_LEVEL
		end
	else
		step.title = step.place
		local handing = #step.handins > 0 and L.HUB_HAND_IN:format(#step.handins) or nil
		local picking = #step.pickups > 0 and L.HUB_PICK_UP:format(#step.pickups) or nil
		step.reason = handing and picking and handing .. L.LIST_SEPARATOR .. picking or handing or picking or ""
	end
	step.detail = step.reason
end

-- A town's `follow`: the next chapters its hand-ins open there, when the data proves each starts in the same town and
-- Check proves it shut now and open once the hand-in is done (the data's `next` alone is display-only). The town then
-- says so. A follow-up is never added as a pickup before the turn-in: it comes with the rebuild after QUEST_TURNED_IN,
-- and `follow` tells a route the hand-in comes first. Nothing is said when the data cannot prove it.
---@param step AGFStep
local function Opens(data, player, completed, log, step)
	local groups, follow = Index(data).groups, {}
	for _, id in ipairs(step.hub and step.handins or NONE) do
		local nextID = data.quests[id] and data.quests[id].next
		local quest = nextID and data.quests[nextID]
		local after = setmetatable({ [id] = true }, { __index = completed })
		if
			quest
			and quest.start
			and quest.start.hub == step.hub
			and not Eligible(data, player, completed, log, nextID, groups)
			and Eligible(data, player, after, log, nextID, groups)
		then
			follow[#follow + 1] = nextID
		end
	end
	step.follow = follow
	if #follow > 0 then
		step.reason = ns.L.OPENS_CHAPTER_HERE
		step.detail = #step.quests == 1 and step.reason or step.detail
	end
end

-- The data's need slots each client objective type fills, each kind in slot order (tools/gen_quests.py): a kill or
-- use takes 0-3, a collect 4-7, an explore 16.
local SLOTS = { monster = { 0, 3 }, object = { 0, 3 }, item = { 4, 7 }, event = { 16, 16 } }

-- The data's need slots still open for a quest under way, each to the client's objective for it. The client's
-- objectives line up with the slots only when it lists as many as the data needs and each kind fills a slot of its
-- own; otherwise every slot counts as open, to `true`, and the second return is false.
---@param quest AGFQuest
---@param entry AGFLogQuest
---@return table<integer, AGFLogObjective|true>, boolean aligned
local function OpenSlots(quest, entry)
	local slots, open = {}, {}
	for slot in pairs(quest.need or NONE) do
		slots[#slots + 1], open[slot] = slot, true
	end
	local objectives = entry.objectives
	if not objectives or #objectives ~= #slots then
		return open, false
	end
	table.sort(slots)
	local aligned, used = {}, {}
	for _, objective in ipairs(objectives) do
		local range, slot = SLOTS[objective.type], nil
		for _, candidate in ipairs(range and slots or NONE) do
			if not slot and not used[candidate] and candidate >= range[1] and candidate <= range[2] then
				slot = candidate
			end
		end
		if not slot then
			return open, false
		end
		used[slot], aligned[slot] = true, (not objective.done) and objective or nil
	end
	return aligned, true
end

-- One open objective of a quest under way: the client's count and words for it when its objectives line up with the
-- data's slots (`counted`), the data's count otherwise, and the town it is handed in at, which a route visits after.
---@param quest? AGFQuest
---@param entry AGFLogQuest
---@param slot integer
---@param counted AGFLogObjective|true|nil
---@return AGFAreaObjective
local function Objective(quest, entry, slot, counted)
	local client = counted ~= true and counted or nil
	local finish = quest and quest.finish
	return {
		id = entry.id,
		slot = slot,
		have = client and client.have,
		need = client and client.need or (quest and quest.need and quest.need[slot]),
		text = client and client.text ~= "" and client.text or nil,
		finish = (finish and ValidPlace(finish)) and "town:" .. Hub(finish) or nil,
	}
end

-- Where a quest under way is done next, in slot order: each open objective the data places, at its first area (the
-- generator orders them) with its radius. The client's point for the quest stands in for them all when its objectives
-- don't line up with the data's slots or the data places none of the open ones, and the client's waypoint (the live
-- client gives one only once finished) before anything. Empty when nothing places it.
---@param entry AGFLogQuest
---@return AGFNode[]
local function Nodes(data, entry)
	local quest = data.quests[entry.id]
	local open, aligned, slots, nodes = {}, false, {}, {}
	if quest then
		open, aligned = OpenSlots(quest, entry)
	end
	for slot in pairs(open) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	for _, slot in ipairs(ValidPlace(entry) and NONE or slots) do
		local best
		for _, area in ipairs(quest.obj or NONE) do
			best = best or (area[1] == slot and area or nil)
		end
		local map = best and (best[5] or quest.zone)
		if map then
			nodes[#nodes + 1] = {
				map = map,
				x = best[2] / 1000,
				y = best[3] / 1000,
				r = best[4],
				slot = slot,
				objectives = { Objective(quest, entry, slot, open[slot]) },
			}
		end
	end
	if #nodes > 0 and (aligned or not ValidPlace(entry.poi)) then
		return nodes
	end
	local point = ValidPlace(entry) and entry or ValidPlace(entry.poi) and entry.poi or nil
	if not point then
		return nodes
	end
	local objectives = {}
	for _, slot in ipairs(slots) do
		objectives[#objectives + 1] = Objective(quest, entry, slot, open[slot])
	end
	return { { map = point.map, x = point.x, y = point.y, r = 0, slot = slots[1] or 0, objectives = objectives } }
end

-- An area's reason: how many quests are done there; a lone quest the route picks up first says so.
---@param area AGFStep
local function Tell(area)
	local planned = area.planned and area.planned[area.quests[1]]
	area.reason = #area.quests > 1 and ns.L.QUESTS_HERE:format(#area.quests)
		or planned and ns.L.AFTER_PICK_UP
		or ns.L.QUESTS_IN_PROGRESS
	area.detail = area.reason
end

-- Objective nodes share an area when one's point lies in the other's ring (0 for a single point or the client's
-- point) or within AREA_GAP of it: rings that merely overlap stay apart, so a merged ring never runs across a zone.
-- On a map the data places nowhere, CLOSE in map units.
local AREA_GAP = 60

---@param a AGFNode
---@param b AGFNode
local function Inside(yards, a, b)
	return yards <= math.max(a.r, b.r) + AREA_GAP
end

---@param a AGFNode
---@param b AGFNode
local function Near(data, a, b)
	local yards = Model.Yards(data, a, b)
	if yards then
		return Inside(yards, a, b)
	end
	return Distance(a, b) <= CLOSE
end

-- Adds `node` (quest `id`'s) to the first of `areas` of its kind it nearly touches (`near`, against the area's first
-- node in `anchors`), else as a new area keyed by its quest and slot, added to `steps` too; the ring grows to hold it.
-- A quest the route picks up first (`planned`) is marked so on the area.
---@param node AGFNode
---@param near fun(a: AGFNode, b: AGFNode): boolean
---@return AGFStep
local function Gather(data, areas, anchors, steps, node, id, title, kind, optional, near, planned)
	local area
	for _, step in ipairs(areas) do
		area = area or (step.kind == kind and near(anchors[step], node) and step or nil)
	end
	if area then
		area.quests[#area.quests + 1] = area.quests[#area.quests] ~= id and id or nil
		area.optional = area.optional and optional or nil
	else
		area = Step(kind, ("area:%d:%d"):format(id, node.slot), title, node, id, optional, "")
		area.objectives, area.r, anchors[area] = {}, node.r, node
		areas[#areas + 1], steps[#steps + 1] = area, area
	end
	if planned then
		area.planned = area.planned or {}
		area.planned[id] = true
	end
	for _, objective in ipairs(node.objectives) do
		area.objectives[#area.objectives + 1] = objective
	end
	area.r = math.max(area.r, (Model.Yards(data, area, node) or 0) + node.r)
	return area
end

-- The log quests a card holds, as steps added to `steps`, and the card's count of them. The quest and dungeon prefs
-- choose what to pick up; a quest already carried always shows, whatever its kind. A finished quest in `ready` (the
-- data and the client agree where it is handed in) joins its town's visit in `stops`, the towns the card's pickups
-- share; any other finished quest is a turn-in at its hand-in. A quest under way is done in areas (Nodes), each merged
-- with the nearby ones of its kind (Near) into one visit keyed by its first quest and slot, its ring wide enough for
-- them all. One nothing places has no step, and still counts: `held` maps every quest the card holds to its first
-- step, or false. `plan` keeps the areas and their first nodes, for a lap's pickups to join (Laps).
---@param ready table<integer, AGFPlace>
---@param belongs fun(id: integer, place?: table): boolean which log quests the card holds, by where they are done next
---@param plan AGFPlanAreas
---@return table<integer, AGFStep|false> held
local function LogSteps(data, player, log, ready, belongs, stops, steps, plan)
	local ids, held = {}, {}
	local function Touches(a, b)
		return Near(data, a, b)
	end
	for id in pairs(log) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local entry, quest = log[id], data.quests[id]
		local nodes = entry.complete and {} or Nodes(data, entry)
		---@type AGFPlace?
		local place = ready[id]
			or (entry.complete and (ValidPlace(entry) and entry or quest and quest.finish))
			or nodes[1]
		place = ValidPlace(place) and place or nil
		if belongs(id, place) then
			held[id] = false
			local optional = Optional(quest, entry.level, player)
			if ready[id] then
				held[id] = Visit(stops, steps, ready[id], "handins", id)
			elseif place and entry.complete then
				steps[#steps + 1] = Step(
					"turnin",
					"turnin:" .. id,
					ns.L.TURN_IN:format(entry.title),
					place,
					id,
					optional,
					ns.L.READY_TO_HAND_IN
				)
				held[id] = steps[#steps]
			end
			local kind = (quest and (quest.elite or quest.dungeon)) and "dungeon" or "area"
			for _, node in ipairs(place and nodes or NONE) do
				local area =
					Gather(data, plan.areas, plan.anchors, steps, node, id, entry.title, kind, optional, Touches)
				held[id] = held[id] or area
			end
		end
	end
	for _, area in ipairs(plan.areas) do
		Tell(area)
	end
	return held
end

-- One visit per town of the eligible quests `wanted` accepts; a group quest joins its town's like any other. `stops`
-- holds the towns the card already has (LogSteps' hand-ins), which a pickup there joins.
---@param wanted fun(quest: AGFQuest): boolean
local function PickupSteps(data, eligible, wanted, steps, stops)
	local chosenGroups = {}
	stops = stops or {}
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		if wanted(quest) and not (quest.group and chosenGroups[quest.group]) then
			if quest.group then
				chosenGroups[quest.group] = true
			end
			Visit(stops, steps, quest.start, "pickups", id)
		end
	end
end

-- One cost in yards, offline, so a rebuild never waits on travel maths (docs/design.md §4.1). A place goes into one
-- frame: its map's world rectangle, then its continent's place on the Azeroth map, so two steps an ocean apart still
-- get a distance. Across an ocean it runs through the player's side's boat or zeppelin docks, so the far side's step
-- nearest the landing is the one the route enters at.
local CROSSING = 10000 -- the wait and the sail, which the distance to and from the docks cannot see
local UNKNOWN = 1000000 -- no way to measure: dearer than any crossing, so it never ties by accident

-- `continent` is the world map ID when the data places the map on the Azeroth map (`known`). A map it doesn't is an
-- island of its own, measured in map units, so its steps still order among themselves but never against the rest.
-- `docks` are the crossings the player's side can take, shared by every position of one plan.
---@class AGFPosition
---@field x number
---@field y number
---@field continent integer|string
---@field known boolean
---@field docks? AGFFrameCrossing[]

-- One direction of an AGFCrossing, its docks in the shared frame.
---@class AGFFrameCrossing
---@field from integer
---@field to integer
---@field leave {x: number, y: number}
---@field land {x: number, y: number}

-- A place's point in its frame, without a table: x, y, continent and whether the data places it on the Azeroth map.
---@return number?, number, integer|string, boolean
local function Point(data, place)
	if not ValidPlace(place) then
		return nil, 0, "", false
	end
	local map = data.maps and data.maps[place.map]
	local shift = map and data.continents and data.continents[map.continent]
	if not shift then
		return place.x, place.y, "map " .. place.map, false
	end
	return shift.x - map.cy + (place.x - 0.5) * map.sx, shift.y - map.cx + (place.y - 0.5) * map.sy, map.continent, true
end

---@return AGFPosition?
local function Position(data, place, docks)
	local x, y, continent, known = Point(data, place)
	if not x then
		return nil
	end
	return { x = x, y = y, continent = continent, known = known, docks = known and docks or nil }
end

-- Docks by side for the Plan under way (its `data`), so its cards share one list; nil outside a Plan.
---@type {data: AGFData, [integer]: AGFFrameCrossing[]}?
local planDocks

-- Both directions of every crossing `side` may take whose continents the data places on the Azeroth map.
---@return AGFFrameCrossing[]
local function Docks(data, side)
	local kept = planDocks and planDocks.data == data and planDocks[side]
	if kept then
		return kept
	end
	local docks = {}
	local function Frame(dock)
		local shift = data.continents and data.continents[dock.continent]
		return shift and { x = shift.x - dock.y, y = shift.y - dock.x }
	end
	for _, crossing in ipairs(data.crossings or NONE) do
		local a, b = Frame(crossing.a), Frame(crossing.b)
		if a and b and HasBit(crossing.side, side) then
			docks[#docks + 1] = { from = crossing.a.continent, to = crossing.b.continent, leave = a, land = b }
			docks[#docks + 1] = { from = crossing.b.continent, to = crossing.a.continent, leave = b, land = a }
		end
	end
	if planDocks and planDocks.data == data then
		planDocks[side] = docks
	end
	return docks
end

local function Yards(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

-- Yards between two places on one continent the data places; nil when it cannot say (another continent, or a map
-- the data has no geometry for).
---@param a {map: integer, x: number, y: number}
---@param b {map: integer, x: number, y: number}
---@return number?
function Model.Yards(data, a, b)
	local ax, ay, here, aKnown = Point(data, a)
	local bx, by, there, bKnown = Point(data, b)
	if aKnown and bKnown and here == there then
		return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
	end
end

local AGREE = 100 -- yards: the town linkage (tools/gen_quests.py LINK); a waypoint this near the data's finish is it

-- The finished log quests whose hand-in the data and the client agree on: the client's waypoint is on a map the data
-- places and lies within AGREE of the data's finish, which is in a town. Each maps to that finish; none ruled out.
---@return table<integer, AGFPlace>
local function Ready(data, log)
	local ready = {}
	for id, entry in pairs(log) do
		local quest = not Dropped(id) and data.quests[id]
		local finish = entry.complete and quest and quest.finish
		if finish and finish.hub then
			local yards = Model.Yards(data, entry, finish)
			if yards then
				ready[id] = yards <= AGREE and finish or nil
			end
		end
	end
	return ready
end

-- Where a step is, for its "NPC, zone" line: the zone is the client's name for its map, the data's otherwise. A turn-in
-- names the data's finish NPC only while its point is within AGREE of that finish; a town named itself in Describe; a
-- trainer's stop is titled by its town.
---@param step AGFStep
---@param mapName? fun(map: integer): string?
local function Locate(data, step, mapName)
	step.zone = (mapName and mapName(step.map)) or (data.maps and data.maps[step.map] and data.maps[step.map].name)
	if step.kind == "trainer" then
		step.title = ns.L.TRAIN_IN:format(Model.TownName(data, step, mapName))
	elseif step.kind == "turnin" then
		local quest = data.quests[step.quests[1]]
		local finish = quest and quest.finish
		local yards = finish and Model.Yards(data, step, finish)
		step.place = yards and yards <= AGREE and finish.name or nil
	end
end

-- A stop the player only hands in at: a turn-in, or a town with hand-ins and nothing to pick up. Never a trainer's.
---@param step AGFStep
local function HandInOnly(step)
	return step.kind == "turnin" or (step.kind == "town" and #step.pickups == 0)
end

---@param a AGFPosition?
local function CostTo(a, bx, by, bContinent, bKnown)
	if not (a and bx) or (a.continent ~= bContinent and not (a.known and bKnown)) then
		return UNKNOWN
	end
	local straight = math.sqrt((a.x - bx) ^ 2 + (a.y - by) ^ 2)
	if a.continent == bContinent then
		return straight
	end
	local best
	for _, dock in ipairs(a.docks or NONE) do
		if dock.from == a.continent and dock.to == bContinent then
			local via = Yards(a, dock.leave) + math.sqrt((dock.land.x - bx) ^ 2 + (dock.land.y - by) ^ 2)
			best = (best and best < via) and best or via
		end
	end
	-- No boat for this side between them: the straight line across the sea, as before the docks were known.
	return CROSSING + (best or straight)
end

---@param a AGFPosition?
---@param b AGFPosition?
local function Cost(a, b)
	if not b then
		return UNKNOWN
	end
	return CostTo(a, b.x, b.y, b.continent, b.known)
end

-- Whether the data places both on the Azeroth map, on different continents.
local function Oversea(data, a, b)
	local _, _, here, aKnown = Point(data, a)
	local _, _, there, bKnown = Point(data, b)
	return aKnown and bKnown and here ~= there
end

-- A town's name for the player: its flight master's town (before ", zone"), else the client's name for its map, else
-- the data's. Only names the data has.
---@param data AGFData
---@param place {map: integer, hub?: integer}
---@param mapName? fun(map: integer): string?
---@return string
function Model.TownName(data, place, mapName)
	local town = data.hubs and place.hub and data.hubs[place.hub] or nil
	if town then
		return (town.name:match("^(.-),") or town.name)
	end
	return (mapName and mapName(place.map)) or data.maps[place.map].name
end

-- Roadmap #5: a class trainer who teaches the player's spells to train, the highest of them at `level`. Of the player's
-- class and side, teaching the class's list from its start (no `from`: a portal trainer teaches only part of it) up to
-- at least `level` (a starting-area trainer stops at 6).
---@param npc AGFNpc
local function Teaches(npc, player, level)
	return npc.class ~= nil
		and player.classBit > 0
		and HasBit(player.classBit, 2 ^ (npc.class - 1))
		and HasBit(npc.side, player.side)
		and npc.from == nil
		and npc.upto >= level
end

-- The nearest NPC `fits` takes, by the route's own cost, so across an ocean it runs through the side's docks; the
-- lowest NPC ID on a tie. Nil when the data places none, or cannot measure from the player (no place for them).
---@param player AGFPlayer
---@param fits fun(npc: AGFNpc): boolean
---@return AGFNpc?, integer? npc its creature entry
local function Nearest(data, player, fits)
	local docks = Docks(data, player.side)
	local origin = Position(data, player, docks)
	local best, bestCost, bestID
	for id, npc in pairs(data.npcs or NONE) do
		if fits(npc) then
			local cost = Cost(origin, Position(data, npc.place, docks))
			if cost < UNKNOWN and (not best or cost < bestCost or (cost == bestCost and id < bestID)) then
				best, bestCost, bestID = npc, cost, id
			end
		end
	end
	return best, bestID
end

-- The nearest trainer who teaches the player's spells to train (Teaches).
---@param player AGFPlayer
---@param level integer the highest level among the spells to train
---@return AGFNpc?
function Model.Trainer(data, player, level)
	return (Nearest(data, player, function(npc)
		return Teaches(npc, player, level)
	end))
end

-- Roadmap #12: the nearest battlemaster of the player's side for battleground `bg` (a BattlemasterList ID, which
-- CMaNGOS's bg_template shares), by the route's cost; nil where the data places none (Darkspear Islands).
---@param player AGFPlayer
---@param bg integer
---@return AGFNpc?, integer? npc its creature entry
function Model.Battlemaster(data, player, bg)
	return Nearest(data, player, function(npc)
		return npc.bg == bg and HasBit(npc.side, player.side)
	end) -- multi-value: the NPC and its entry
end

--[[ Roadmap #9: where to go next for a profession. SkillUp Forever keeps recipes and skill-ups; this only names the
     trainer of the next rank, a free profession slot and a secondary skill not yet learned. ]]

local RANK_SKILL = 75 -- a rank's cap per step: CMaNGOS Spell::EffectSkillStep sets the cap to 75 times the rank
local PROFESSION_SLOTS = 2 -- CMaNGOS MaxPrimaryTradeSkill's default: two professions; secondary skills take none

-- A rank of the line the player can train now: a trainer teaches it (Data.professions), and they have the level and
-- the skill its rank spell asks.
---@param player AGFPlayer
---@param skill integer
---@param rank integer
---@return boolean
local function Trainable(data, player, skill, rank)
	for _, entry in ipairs(data.professions[skill].ranks) do
		if entry.rank == rank then
			return player.level >= entry.level and ((player.skills or NONE)[skill] or 0) >= entry.skill
		end
	end
	return false
end

-- A profession trainer of the player's side who teaches this rank of this line.
---@param npc AGFNpc
---@param player AGFPlayer
local function TeachesRank(npc, player, skill, rank)
	if npc.skill ~= skill or not HasBit(npc.side, player.side) then
		return false
	end
	for _, taught in ipairs(npc.ranks) do
		if taught == rank then
			return true
		end
	end
	return false
end

-- Every nudge the player's skills call for, in order: a learned line at its rank's cap whose next rank they can train
-- now, then a free profession slot while a profession they lack is one they can learn now, then each secondary skill
-- they lack and can learn now; lines by ID. A player with no `primaries` (no client count) has no slot nudge.
---@param player AGFPlayer
---@return AGFProfessionNudge[]
local function Nudges(data, player)
	local ids, nudges = {}, {}
	for id in pairs(data.professions or NONE) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local skills, caps = player.skills or {}, player.caps or {}
	for _, id in ipairs(ids) do
		local rank, cap = skills[id], caps[id]
		local upcoming = rank and cap and rank >= cap and cap % RANK_SKILL == 0 and cap / RANK_SKILL + 1
		if upcoming and Trainable(data, player, id, upcoming) then
			local key = ("profession:%d:%d"):format(id, upcoming)
			nudges[#nudges + 1] = { key = key, kind = "cap", skill = id, rank = upcoming }
		end
	end
	-- The lines the player lacks and can learn now: professions under false, secondary skills under true.
	local open = { [false] = {}, [true] = {} }
	for _, id in ipairs(ids) do
		local secondary = data.professions[id].secondary == true
		if not skills[id] and Trainable(data, player, id, 1) then
			open[secondary][#open[secondary] + 1] = id
		end
	end
	if player.primaries and player.primaries < PROFESSION_SLOTS and #open[false] > 0 then
		nudges[#nudges + 1] = { key = "profession:slot", kind = "slot", rank = 1, skills = open[false] }
	end
	for _, id in ipairs(open[true]) do
		nudges[#nudges + 1] = { key = ("profession:%d:1"):format(id), kind = "learn", skill = id, rank = 1 }
	end
	return nudges
end

-- Roadmap #9: the first nudge `wanted` takes (every one, without it) that a trainer of the player's side teaches, with
-- the nearest such trainer; for a free slot, of any profession it lists. Its `npc` is nil when the data cannot measure
-- from the player (no place for them); a rank only the other side's trainers teach is no nudge.
---@param player AGFPlayer
---@param wanted? fun(key: string): boolean
---@return AGFProfessionNudge?
function Model.Profession(data, player, wanted)
	for _, nudge in ipairs(Nudges(data, player)) do
		local lines = nudge.skills or { nudge.skill }
		local function Teacher(npc)
			for _, skill in ipairs(lines) do
				if TeachesRank(npc, player, skill, nudge.rank) then
					return true
				end
			end
			return false
		end
		if not wanted or wanted(nudge.key) then
			for _, npc in pairs(data.npcs or NONE) do
				if Teacher(npc) then
					nudge.npc = (Nearest(data, player, Teacher))
					return nudge
				end
			end
		end
	end
end

-- Roadmap #11: rested XP is low when it is under one bubble of the bar (a twentieth of the level's XP, a night at an
-- inn's worth), or none at all when the client gives no bar. Nil when the player's rest is unknown (a spec's player),
-- and never at the level cap, where rested XP buys nothing.
local REST_BUBBLE = 0.05
---@param player AGFRest
---@return boolean
function Model.RestLow(player)
	local rested, max = player.rested, player.xpMax
	return rested ~= nil
		and player.level < player.maxLevel
		and (rested == 0 or (max ~= nil and max > 0 and rested < max * REST_BUBBLE))
end

-- The route's last stop reads "Rest at the inn here" when rest is low (RestLow), the player isn't already resting,
-- and an innkeeper of their side stands in its town: its hub, or within the town linkage of its point. A reason on
-- the stop, never a step of its own; resting ticks it off, and the stop's own reason is back.
---@param steps AGFStep[]
local function Rest(data, player, steps)
	local last = steps[#steps]
	if not last or player.resting or not Model.RestLow(player) then
		return
	end
	for _, npc in pairs(data.npcs or NONE) do
		if npc.inn and HasBit(npc.side, player.side) then
			local yards = Model.Yards(data, last, npc.place)
			if (last.hub ~= nil and npc.place.hub == last.hub) or (yards ~= nil and yards <= AGREE) then
				last.reason = ns.L.REST_HERE
				return
			end
		end
	end
end

-- The chosen journey's trainer stops (roadmap #5): with spells to train, one per town among the trainers who teach
-- them, the lowest NPC ID in each. Build takes one only after a stop in its town (Open), so none is a detour. A trainer
-- the data puts in no town is never a stop; the aside still names them.
---@param prefs AGFPrefs
---@param key string the journey's key
---@return AGFStep[]
local function TrainerSteps(data, player, prefs, key)
	local train, steps = prefs.journey == key and player.train, {}
	if not train then
		return steps
	end
	local ids, towns = {}, {}
	for id, npc in pairs(data.npcs or NONE) do
		ids[#ids + 1] = npc.place.hub and Teaches(npc, player, train.level) and id or nil
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local place = data.npcs[id].place
		if not towns[place.hub] then
			towns[place.hub] = true
			steps[#steps + 1] = {
				kind = "trainer",
				key = "trainer:" .. id,
				hub = place.hub,
				title = "",
				detail = "",
				reason = "",
				quests = {},
				map = place.map,
				x = place.x,
				y = place.y,
				place = place.name,
			}
		end
	end
	return steps
end

-- Nearest neighbour from `from`; TwoOpt then removes crossings with that start fixed and the end open.
local function Path(steps, from, where)
	local path, left = {}, {}
	for _, step in ipairs(steps) do
		left[#left + 1] = step
	end
	while #left > 0 do
		local best
		for index, step in ipairs(left) do
			local cost = Cost(from, where[step])
			if not best or cost < best.cost or (cost == best.cost and step.key < left[best.index].key) then
				best = { index = index, cost = cost }
			end
		end
		local step = table.remove(left, best.index)
		path[#path + 1] = step
		from = where[step]
	end
	return path
end

local function TwoOpt(path, start, where)
	local function At(index)
		return index == 0 and start or where[path[index]]
	end
	local improved = true
	while improved do
		improved = false
		for i = 1, #path - 1 do
			for j = i + 1, #path do
				local before = Cost(At(i - 1), At(i)) + (j < #path and Cost(At(j), At(j + 1)) or 0)
				local after = Cost(At(i - 1), At(j)) + (j < #path and Cost(At(i), At(j + 1)) or 0)
				if after < before - 1e-6 then
					for k = 0, math.floor((j - i - 1) / 2) do
						path[i + k], path[j - k] = path[j - k], path[i + k]
					end
					improved = true
				end
			end
		end
	end
	return path
end

-- Groups the selected steps by continent, the player's first and the rest by how dear they are to reach, so the
-- route crosses each ocean once. In each group the turn-ins in `away` (another continent than the player's) go last.
-- `cheap` (the in-combat rebuild) keeps the nearest-neighbour order and skips 2-opt.
local function Order(selected, origin, where, away, cheap)
	local groups, byContinent = {}, {}
	for _, step in ipairs(selected) do
		local continent = where[step].continent
		local group = byContinent[continent]
		if not group then
			group = { continent = continent, main = {}, last = {}, reach = math.huge }
			byContinent[continent] = group
			groups[#groups + 1] = group
		end
		table.insert(away[step] and group.last or group.main, step)
		group.reach = math.min(group.reach, Cost(origin, where[step]))
	end
	local home = origin and origin.continent
	table.sort(groups, function(a, b)
		if (a.continent == home) ~= (b.continent == home) then
			return a.continent == home
		end
		if a.reach ~= b.reach then
			return a.reach < b.reach
		end
		return tostring(a.continent) < tostring(b.continent)
	end)
	local steps, from = {}, origin
	for _, group in ipairs(groups) do
		for _, part in ipairs({ group.main, group.last }) do
			local start = from
			local path = Path(part, start, where)
			for _, step in ipairs(cheap and path or TwoOpt(path, start, where)) do
				steps[#steps + 1] = step
				from = where[step]
			end
		end
	end
	return steps
end

-- A step with no quests is worth what its kind says, never VALUE_WEAK: training waits for nothing, as a hand-in does.
local KIND_VALUE = { trainer = VALUE_HAND_IN }

-- A step's worth in yards (VALUE_* above), so selection weighs it against the reach. Only a step placed in yards has
-- one: a map the data cannot place is measured in map units, where yards mean nothing.
---@param step AGFStep
local function Value(data, log, player, step)
	local worth = KIND_VALUE[step.kind]
	if worth then
		return worth
	end
	-- A finished quest waits for nothing, so a stop with a hand-in is never weak.
	local handins = step.handins and #step.handins or (step.kind == "turnin" and 1 or 0)
	local risk, weak = false, handins == 0
	for _, id in ipairs(step.quests) do
		local level = QuestLevel(data, log, player, id)
		risk = risk or GreyRisk(level, player)
		weak = weak and Optional(data.quests[id], level, player)
	end
	return VALUE_QUEST * math.min(#step.quests, VALUE_QUESTS_MAX)
		+ (risk and VALUE_GREY_RISK or 0)
		+ VALUE_HAND_IN * handins
		+ (weak and VALUE_WEAK or 0)
end

-- The skipped keys a full build still found among its candidates (Model.Plan); nil outside one.
---@type table<string, boolean>?
local skippedSeen

-- Each card's committed order (docs/design.md §4.3), by journey key: a full build reads the last route's and records
-- its own (Model.Plan); nil outside one.
---@type table<string, AGFOrder>?
local committedOrders

-- Chooses up to MAX_STEPS of `candidates` and orders them from the player (docs/design.md §4.1). `lead`, the story
-- card's chapter, is chosen first, then ordered by cost like the rest. `join` adds to the chosen steps (hand-ins to
-- their towns) before they are described and ordered, so it never adds a step. `log` titles the hand-ins.
---@param join? fun(selected: AGFStep[])
local function Build(data, player, completed, log, candidates, prefs, mapName, cheap, lead, join)
	local pool, where, docks = {}, {}, Docks(data, player.side)
	for _, step in ipairs(candidates) do
		if not (prefs.skipped and prefs.skipped[step.key]) then
			pool[#pool + 1] = step
			where[step] = Position(data, step, docks)
		elseif skippedSeen then
			skippedSeen[step.key] = true
		end
	end
	local origin = Position(data, player, docks)

	-- Selection grows from the player: each pick is the step cheapest to reach from the player or any step already
	-- picked, less its worth (Value). There is no phase, so a far turn-in never pushes out a nearby pickup.
	-- Without a known place for the player (no position in an instance, a map the data lacks) most steps cost UNKNOWN
	-- from them. A turn-in among those leads, as turn-ins did before costs, and the route grows from it instead of
	-- dropping it for whichever key sorts first.
	local measured = origin ~= nil and origin.known
	local reach, value, chosen, selected = {}, {}, {}, {}
	-- A trainer's stop (roadmap #5) opens only once a stop in its town is chosen, its hub or within the town linkage
	-- (AGREE) of it, and one at most: the route stops to train only where it passes anyway.
	local near, trained = {}, false
	local function Open(step)
		return step.kind ~= "trainer" or (near[step] and not trained)
	end
	for _, step in ipairs(pool) do
		local cost = Cost(origin, where[step])
		reach[step] = (not measured and cost >= UNKNOWN and HandInOnly(step)) and 0 or cost
		value[step] = (where[step] and where[step].known) and Value(data, log, player, step) or 0
	end
	local function Take(step)
		chosen[step] = true
		selected[#selected + 1] = step
		trained = trained or step.kind == "trainer"
		for _, other in ipairs(pool) do
			if not chosen[other] then
				local cost = Cost(where[step], where[other])
				reach[other] = math.min(reach[other], cost)
				near[other] = near[other]
					or (
						other.kind == "trainer"
						and step.kind ~= "trainer"
						and ((step.hub ~= nil and step.hub == other.hub) or cost <= AGREE)
					)
			end
		end
	end
	if lead and where[lead] then
		Take(lead)
	end
	-- Each pick weighs the reach against the step's worth; Order and 2-opt then look at travel alone.
	while #selected < Model.MAX_STEPS do
		local best, bestKey
		for _, step in ipairs(pool) do
			local key = reach[step] - value[step]
			if
				not chosen[step]
				and Open(step)
				and (not best or key < bestKey or (key == bestKey and step.key < best.key))
			then
				best, bestKey = step, key
			end
		end
		if not best then
			break
		end
		Take(best)
	end
	if join then
		join(selected)
	end
	for _, step in ipairs(selected) do
		if step.kind == "town" then
			Describe(data, log, player, step)
			Opens(data, player, completed, log, step)
		elseif step.kind == "trainer" then
			Describe(data, log, player, step)
		end
	end

	-- A turn-in across an ocean waits for the rest of that continent's steps, and says where it is.
	local away = {}
	for _, step in ipairs(selected) do
		local position = where[step]
		if
			HandInOnly(step)
			and origin
			and origin.known
			and position.known
			and position.continent ~= origin.continent
		then
			away[step] = true
			local name = (mapName and mapName(step.map)) or (data.maps[step.map] and data.maps[step.map].name)
			if name then
				step.reason = ns.L.HAND_IN_WHEN:format(name)
				step.detail = step.reason
			end
		end
	end
	-- The order starts from the player when some step is measurable from them, from the first pick otherwise.
	local start = selected[1] and where[selected[1]]
	for _, step in ipairs(selected) do
		if Cost(origin, where[step]) < UNKNOWN then
			start = origin
			break
		end
	end
	-- Each town's point is the place of its quest nearest the stop before it (the player, for the first): a real
	-- giver, never a centre, so Shortest Path takes the player to the nearest door of the town.
	local steps, from = Order(selected, start, where, away, cheap), start
	for _, step in ipairs(steps) do
		if step.spots then
			local best, bestCost
			for _, id in ipairs(step.quests) do
				local cost = CostTo(from, Point(data, step.spots[id])) -- multi-value: the spot's point
				if not best or cost < bestCost then
					best, bestCost = step.spots[id], cost
				end
			end
			step.map, step.x, step.y = best.map, best.x, best.y
		end
		Locate(data, step, mapName)
		from = Position(data, step, docks)
	end
	return steps
end

--[[ Laps (docs/design.md §4.3): the route of card 1 and of the chosen card as a player running a guide goes: pick up
     in town, clear the objective areas out one side of it, come back and hand in. Every other card keeps Build's route,
     so a rebuild stays inside its frame budget. ]]

-- The areas a card's quests are done in and the first node of each, which a lap's pickups join (LogSteps, Laps).
---@class AGFPlanAreas
---@field areas AGFStep[]
---@field anchors table<AGFStep, AGFNode>

local RUN = 7 -- yards a second at a run
local LAP_YARDS = 15 * 60 * RUN -- a lap's travel and work: about a quarter of an hour out of town and back
local LAP_STOPS = Model.MAX_STEPS - 3 -- a lap's stops, so the town before, the town after and one more fit the numerals
local WORK_YARDS = 4 * RUN -- one count of an objective (a kill, an item): about four seconds' work
local TALK_YARDS = 10 * RUN -- a quest's pickup and its hand-in
local HERE = 100 -- yards: a town (a hub) this near the player is the one they stand in, visited before any lap
local KEEP = 0.5 -- a new quest worth less than this share of its town's mean XP per yard waits for a later lap

-- The XP `quest` gives at `level`: CMaNGOS Quest::XPValue, whole up to 5 levels above the quest, then 0.8, 0.6, 0.4 and
-- 0.2 of it, and 0.1 from 10 levels on. Nil where the data has none (a scaling quest's).
---@param quest AGFQuest
local function Worth(quest, level)
	if not quest.xp or quest.level < 1 then
		return nil
	end
	local over = level - quest.level
	return quest.xp * (over <= 5 and 1 or over >= 10 and 0.1 or 1 - (over - 5) * 0.2)
end

-- Whether a lap may take up a new quest for the player (docs/design.md §4.2, §4.5): not one a script completes or a
-- timer ends, and each of its objectives in an area the data has. A quest with none (a talk or delivery quest) needs
-- only its pickup and hand-in.
---@param quest AGFQuest
local function Pickable(quest)
	local flags = quest.flags
	if flags and (flags.event or flags.timed) then
		return false
	end
	for slot in pairs(quest.need or NONE) do
		local placed = false
		for _, area in ipairs(quest.obj or NONE) do
			placed = placed or area[1] == slot
		end
		if not placed then
			return false
		end
	end
	return true
end

-- A new quest's objective nodes, one for each slot at its first area (as Nodes does for a quest under way), each
-- counting the data's need.
---@param quest AGFQuest
---@return AGFNode[]
local function Planned(quest, id)
	local slots, nodes = {}, {}
	for slot in pairs(quest.need or NONE) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	local finish = ValidPlace(quest.finish) and "town:" .. Hub(quest.finish) or nil
	for _, slot in ipairs(slots) do
		local best
		for _, area in ipairs(quest.obj or NONE) do
			best = best or (area[1] == slot and area or nil)
		end
		local node = best
			and {
				map = best[5] or quest.zone,
				x = best[2] / 1000,
				y = best[3] / 1000,
				r = best[4],
				slot = slot,
				objectives = { { id = id, slot = slot, need = quest.need[slot], finish = finish } },
			}
		nodes[#nodes + 1] = ValidPlace(node) and node or nil
	end
	return nodes
end

-- The cost between two stops: an area is entered at its ring, so both radii come off.
local function Gap(a, ra, b, rb)
	return math.max(0, Cost(a, b) - ra - rb)
end

-- A town's lists after some of its quests went: its hand-ins first, as Visit adds them.
---@param town AGFStep
local function Trim(town, handins, pickups)
	town.handins, town.pickups, town.quests = handins, pickups, {}
	for _, list in ipairs({ handins, pickups }) do
		for _, id in ipairs(list) do
			town.quests[#town.quests + 1] = id
		end
	end
end

-- One lap in order from `from`: `open` (the town's visit that hands out its quests) before every stop in `after`,
-- `close` (the hand-ins) last, the rest by cheapest insertion, then or-opt (runs of up to three stops moved while that
-- saves yards and keeps `open` first). `stops` come by key and ties keep the first, so a rebuild gives the same order.
---@param stops AGFStep[]
---@param after table<AGFStep, boolean>
---@param at fun(step: AGFStep): AGFPosition?
---@return AGFStep[]
local function Sequence(from, open, stops, close, after, at)
	local all = {}
	all[#all + 1] = open or nil
	for _, step in ipairs(stops) do
		all[#all + 1] = step
	end
	all[#all + 1] = close or nil
	local cost = {}
	for i = 0, #all do
		local row, a, ra = {}, i == 0 and from or at(all[i]), i == 0 and 0 or (all[i].r or 0)
		for j = 1, #all do
			row[j] = Gap(a, ra, at(all[j]), all[j].r or 0)
		end
		cost[i] = row
	end
	local first, last = open and 1 or nil, close and #all or nil
	local route, pending = {}, {}
	route[#route + 1] = first
	route[#route + 1] = last
	for i = (open and 2 or 1), #all - (close and 1 or 0) do
		pending[#pending + 1] = i
	end
	local function Leg(a, b)
		return b and cost[a or 0][b] or 0
	end
	-- Where `open` stands in `path`, and whether each stop that needs it comes after it.
	local function Feasible(path)
		local seen = not first
		for _, i in ipairs(path) do
			seen = seen or i == first
			if not seen and after[all[i]] then
				return false
			end
		end
		return true
	end
	while #pending > 0 do
		local best
		for p, i in ipairs(pending) do
			local seen = not (first and after[all[i]])
			for k = 1, #route + (last and 0 or 1) do
				local prev, nextStop = route[k - 1], route[k]
				local delta = Leg(prev, i) + Leg(i, nextStop) - Leg(prev, nextStop)
				if seen and (not best or delta < best.delta - 1e-6) then
					best = { p = p, k = k, delta = delta }
				end
				seen = seen or route[k] == first
			end
		end
		table.insert(route, best.k, table.remove(pending, best.p))
	end
	for _ = 1, 2 do
		local improved = false
		for size = 1, 3 do
			for s = 1, #route - size + 1 - (last and 1 or 0) do
				local segment, rest = {}, {}
				for k, i in ipairs(route) do
					table.insert((k >= s and k < s + size) and segment or rest, i)
				end
				local before = Leg(route[s - 1], segment[1]) + Leg(segment[size], route[s + size])
				local saving = before - Leg(route[s - 1], route[s + size])
				for t = 1, #rest + (last and 0 or 1) do
					local added = Leg(rest[t - 1], segment[1]) + Leg(segment[size], rest[t]) - Leg(rest[t - 1], rest[t])
					if t ~= s and added < saving - 1e-6 then
						local moved = {}
						for k = 1, #rest + 1 do
							if k == t then
								for _, i in ipairs(segment) do
									moved[#moved + 1] = i
								end
							end
							moved[#moved + 1] = rest[k]
						end
						if Feasible(moved) then
							route, improved = moved, true
							break
						end
					end
				end
			end
		end
		if not improved then
			break
		end
	end
	local steps = {}
	for _, i in ipairs(route) do
		steps[#steps + 1] = all[i]
	end
	return steps
end

-- The work at a stop in yards: each count still to do in an area, a talk anywhere else.
---@param step AGFStep
local function Work(step)
	if not step.objectives then
		return TALK_YARDS
	end
	local work = 0
	for _, objective in ipairs(step.objectives) do
		work = work + math.max(1, (objective.need or 1) - (objective.have or 0)) * WORK_YARDS
	end
	return work
end

---@class AGFAnchor
---@field key string the town's key ("town:<hub>"), or "" for the stops no town reaches, swept around the player
---@field place table the town's point
---@field pos? AGFPosition
---@field open? AGFStep the town's visit that hands out its quests and takes its finished ones
---@field stops AGFStep[] the areas and stops its laps go out to
---@field hands integer[] the quests a lap hands in back there, once all their objectives are done
---@field visited? boolean

---@class AGFLap
---@field key string
---@field anchor AGFAnchor
---@field stops AGFStep[]

-- An anchor's stops cut into laps by sweep: by angle around its town from the widest gap between them, each lap as long
-- as its loop out and back and its work fit LAP_YARDS, its stops shared evenly among as few laps as LAP_STOPS allows;
-- a stop too far alone is a lap alone.
---@param anchor AGFAnchor
---@param at fun(step: AGFStep): AGFPosition?
---@return AGFLap[]
local function Sweep(anchor, at)
	local stops, angle, home = anchor.stops, {}, anchor.pos
	for _, step in ipairs(stops) do
		local p = at(step)
		angle[step] = (home and p and p.continent == home.continent) and math.atan2(p.y - home.y, p.x - home.x) or 0
	end
	table.sort(stops, function(a, b)
		if angle[a] ~= angle[b] then
			return angle[a] < angle[b]
		end
		return a.key < b.key
	end)
	local start, widest = 1, -1
	for i = 1, #stops > 1 and #stops or 0 do
		local gap = (angle[stops[i]] - angle[stops[i - 1] or stops[#stops]]) % (2 * math.pi)
		if gap > widest then
			start, widest = i, gap
		end
	end
	local laps, lap, loop, spent = {}, nil, {}, 0
	local size = #stops > 0 and math.ceil(#stops / math.ceil(#stops / LAP_STOPS)) or 0
	for k = 0, #stops - 1 do
		local step = stops[(start - 1 + k) % #stops + 1]
		local p, r = at(step), step.r or 0
		local best, where = math.huge, 1
		for i = 1, #loop + 1 do
			local a, b = loop[i - 1], loop[i]
			local pa, pb = a and at(a) or home, b and at(b) or home
			local ra, rb = a and (a.r or 0) or 0, b and (b.r or 0) or 0
			local delta = pa and pb and Gap(pa, ra, p, r) + Gap(p, r, pb, rb) - Gap(pa, ra, pb, rb) or UNKNOWN
			if delta < best then
				best, where = delta, i
			end
		end
		if not lap or (#lap.stops >= size or spent + best + Work(step) > LAP_YARDS) then
			lap = { key = ("%s:%d"):format(anchor.key, #laps + 1), anchor = anchor, stops = {} }
			laps[#laps + 1], loop, where = lap, {}, 1
			best = home and p and 2 * Gap(home, 0, p, r) or UNKNOWN
			spent = 0
		end
		table.insert(loop, where, step)
		lap.stops[#lap.stops + 1] = step
		spent = spent + best + Work(step)
	end
	return laps
end

local SETTLE_SHARE = 0.15 -- a fresh order replaces the committed one only when it saves this share of the rest...
local SETTLE_YARDS = 200 -- ...and this many yards

-- Each step's identity in a card's committed order: its key, "<<" on a lap's visit back to hand in what it did, "<"
-- on another town visited only to hand in (the hand-ins split from a later lap's town), and "#n" on the nth step with
-- the same (Idents).
---@param step AGFStep
local function Ident(step)
	local only = step.pickups and #step.pickups == 0
	return step.key .. (only and (step.returns and "<<" or "<") or "")
end

---@param route AGFStep[]
---@return string[]
local function Idents(route)
	local idents, seen = {}, {}
	for index, step in ipairs(route) do
		local ident = Ident(step)
		seen[ident] = (seen[ident] or 0) + 1
		idents[index] = seen[ident] > 1 and ("%s#%d"):format(ident, seen[ident]) or ident
	end
	return idents
end

-- Each step's place in the committed order, by index, or nil for a new one: its identity's, and a town that hands in
-- and hands out at once takes the place of its committed hand-in-only visit when no step holds that, as the visit
-- split from its pickups by the last build is one again.
---@param route AGFStep[]
---@param rank table<string, integer>
---@return table<integer, integer>
local function Ranks(route, rank)
	local idents, ranks, claimed = Idents(route), {}, {}
	for index, ident in ipairs(idents) do
		ranks[index], claimed[ident] = rank[ident], true
	end
	for index, step in ipairs(route) do
		local back = step.kind == "town" and #step.handins > 0 and idents[index] == step.key and step.key .. "<"
		if back and rank[back] and not claimed[back] and rank[back] < (ranks[index] or math.huge) then
			ranks[index], claimed[back] = rank[back], true
		end
	end
	return ranks
end

-- The yards along `route` from `from`, else from its first stop.
---@param route AGFStep[]
---@param at fun(step: AGFStep): AGFPosition?
local function Length(route, from, at)
	local total, a, ra = 0, from, 0
	for index, step in ipairs(route) do
		local p, r = at(step), step.r or 0
		total = total + ((from or index > 1) and Gap(a, ra, p, r) or 0)
		a, ra = p, r
	end
	return total
end

-- The steps the committed order holds back in that order, and the new ones after them, before the route is checked
-- in order: so the log's limit leaves the committed pickups as they were. Stabilise then puts the new ones in place.
---@param route AGFStep[]
---@param rank table<string, integer>
---@return AGFStep[]
local function Recommit(route, rank)
	local held, fresh, at, ranks = {}, {}, {}, Ranks(route, rank)
	for index, step in ipairs(route) do
		at[step] = ranks[index]
		table.insert(ranks[index] and held or fresh, step)
	end
	table.sort(held, function(a, b)
		return at[a] < at[b]
	end)
	for _, step in ipairs(fresh) do
		held[#held + 1] = step
	end
	return held
end

-- The route in the card's committed order (docs/design.md §4.3), so a rebuild never shuffles what the player follows:
-- the steps the order holds keep their places, each new one goes where it adds the fewest yards after the head, and
-- the fresh order (`plain`, after the same head) replaces it only when that saves SETTLE_SHARE of the rest and
-- SETTLE_YARDS. A route that shares no step with the order (its lap ended), or whose steps the order cannot hold, is
-- the fresh one, else `route` as Recommit left it.
---@param route AGFStep[] the steps, the committed ones first in their order (Recommit)
---@param plain AGFStep[] the same steps in the fresh order
---@param rank table<string, integer> each identity's place in the committed order
---@param holds fun(steps: AGFStep[]): boolean
---@param at fun(step: AGFStep): AGFPosition?
---@param settle fun(steps: AGFStep[]): AGFStep[] the order as it is drawn: the next lap's town last
---@return AGFStep[]
local function Stabilise(route, plain, rank, holds, at, origin, settle)
	local fallback = holds(plain) and plain or route
	local ranks, kept, fresh, place = Ranks(route, rank), {}, {}, {}
	for index, step in ipairs(route) do
		place[step] = ranks[index]
		table.insert(place[step] and kept or fresh, step)
	end
	if #kept == 0 then
		return settle(fallback)
	end
	table.sort(kept, function(a, b)
		return place[a] < place[b]
	end)
	for _, step in ipairs(fresh) do
		local best, bestAdded
		local p, r = at(step), step.r or 0
		for k = 2, #kept + 1 do
			local prev, nextStop = kept[k - 1], kept[k]
			local added = Gap(at(prev), prev.r or 0, p, r)
			if nextStop then
				local q, rn = at(nextStop), nextStop.r or 0
				added = added + Gap(p, r, q, rn) - Gap(at(prev), prev.r or 0, q, rn)
			end
			if not bestAdded or added < bestAdded - 1e-6 then
				table.insert(kept, k, step)
				if holds(kept) then
					best, bestAdded = k, added
				end
				table.remove(kept, k)
			end
		end
		if not best then
			return settle(fallback)
		end
		table.insert(kept, best, step)
	end
	if not holds(kept) then
		return settle(fallback)
	end
	local head, alt = kept[1], { kept[1] }
	for _, step in ipairs(plain) do
		alt[#alt + 1] = step ~= head and step or nil
	end
	kept, alt = settle(kept), settle(holds(alt) and alt or fallback)
	local from = alt[1] ~= head and origin or nil
	local was, now = Length(kept, from, at), Length(alt, from, at)
	return was - now >= math.max(SETTLE_SHARE * was, SETTLE_YARDS) and alt or kept
end

-- The open area the player stands in (docs/design.md §4.3): the head when it is one, else the first on the route. An
-- area with a quest the route picks up first is not open yet. Nil when they stand in none.
---@param where? {map?: integer, x?: number, y?: number}
---@param steps AGFStep[]
---@return integer?
function Model.Here(data, where, steps)
	if not ValidPlace(where) then
		return nil
	end
	---@cast where {map: integer, x: number, y: number}
	for index, step in ipairs(steps) do
		local yards = step.kind == "area" and not step.planned and Model.Yards(data, where, step)
		if yards and yards <= (step.r or 0) then
			return index
		end
	end
	return nil
end

-- The lap route (docs/design.md §4.3), or nil when the player's place is unknown, where Build's route stands. The
-- card's towns hand out their quests and take the finished ones; each new quest is done in areas of the data's (merged
-- with the log's), and one whose XP per yard falls below KEEP of its town's mean waits. Each quest's stops are laps
-- around the town it goes back to (its pickup town when new, else its hand-in's when a lap reaches it), cut by Sweep.
-- The lap that leads (the story's chapter, else the least reach less worth) is ordered by Sequence, and another follows
-- only while no area has come; then, while the numerals have room, the next lap's town last, so a short lap still
-- shows the pickups waiting after it. Then the route is checked in order: a quest's objectives never before its
-- pickup, its hand-in never before all of them, and the log never past the client's limit, the least XP per yard left
-- in town first. The card's committed order (`card`, its journey key) keeps the route steady: its lap goes on until it
-- ends, its towns before that lap keep their visits, and its order stands unless a fresh one is much shorter
-- (Stabilise).
-- The town or open area the player stands in leads (Model.Here). A second visit to a town is keyed "town:<hub>:2".
---@param candidates AGFStep[]
---@param plan AGFPlanAreas
---@param leadID? integer
---@param join? fun(selected: AGFStep[])
---@return AGFStep[]?
local function Laps(data, player, completed, log, candidates, plan, prefs, mapName, leadID, join, card)
	local docks = Docks(data, player.side)
	local origin = Position(data, player, docks)
	if not (origin and origin.known) then
		return nil
	end
	local rank = {}
	for index, ident in ipairs(committedOrders and committedOrders[card] or NONE) do
		rank[ident] = index
	end
	local skipped, where, pinned = prefs.skipped or {}, {}, prefs.pinned or {}
	local function At(place)
		local position = where[place]
		if position == nil then
			position = Position(data, place, docks) or false
			where[place] = position
		end
		return position or nil
	end
	local function Skip(key)
		if skippedSeen then
			skippedSeen[key] = true
		end
	end
	local towns, kept, others, groups = {}, {}, {}, {}
	for _, step in ipairs(candidates) do
		if skipped[step.key] then
			Skip(step.key)
		elseif step.kind == "town" then
			towns[#towns + 1] = step
		elseif step.kind == "area" then
			kept[step] = true
		elseif step.kind == "dungeon" then
			groups[#groups + 1] = step
		else
			others[#others + 1] = step
		end
	end
	local areas = {}
	for _, area in ipairs(plan.areas) do
		areas[#areas + 1] = kept[area] and area or nil
	end

	-- The new quests each town hands out, and their objective nodes.
	local picks, ids, nodes = {}, {}, {}
	for _, town in ipairs(towns) do
		local pickups = {}
		for _, id in ipairs(town.pickups) do
			-- One the player added (shift-click) goes whatever its kind, as the lead does.
			if id == leadID or pinned[id] or Pickable(data.quests[id]) then
				pickups[#pickups + 1], picks[id], ids[#ids + 1] = id, town, id
				-- An outdoor elite is picked up, optional and with the group badge, but its work waits for a group.
				nodes[id] = data.quests[id].elite and {} or Planned(data.quests[id], id)
			end
		end
		Trim(town, town.handins, pickups)
	end
	table.sort(ids)

	-- Each new quest's worth against its detour: out to each of its nodes from the nearest of its town, the log's areas
	-- and the other new nodes, and back, with the work there and the talk.
	local ratio, sums, counts, all, owner = {}, {}, {}, {}, {}
	for _, id in ipairs(ids) do
		for _, node in ipairs(nodes[id]) do
			all[#all + 1], owner[node] = node, id
		end
	end
	for _, id in ipairs(ids) do
		local quest, town = data.quests[id], picks[id]
		local worth = Worth(quest, player.level)
		if worth then
			local yards = TALK_YARDS
			for _, node in ipairs(nodes[id]) do
				local p = At(node)
				local nearest = Gap(At(town) or origin, 0, p, node.r)
				for _, area in ipairs(areas) do
					nearest = math.min(nearest, Gap(At(area), area.r, p, node.r))
				end
				-- Nothing is nearer than touching, so the search stops there.
				for _, near in ipairs(all) do
					if nearest == 0 then
						break
					end
					nearest = owner[near] ~= id and math.min(nearest, Gap(At(near), near.r, p, node.r)) or nearest
				end
				yards = yards + 2 * nearest + node.objectives[1].need * WORK_YARDS
			end
			ratio[id] = worth / yards
			sums[town], counts[town] = (sums[town] or 0) + ratio[id], (counts[town] or 0) + 1
		end
	end
	local function Touches(a, b)
		local here, there = At(a), At(b)
		if here and there and here.known and there.known and here.continent == there.continent then
			return Inside(Yards(here, there), a, b)
		end
		return Distance(a, b) <= CLOSE
	end
	local fresh = {}
	for _, town in ipairs(towns) do
		local pickups = {}
		for _, id in ipairs(town.pickups) do
			if id == leadID or pinned[id] or not ratio[id] or ratio[id] >= KEEP * sums[town] / counts[town] then
				pickups[#pickups + 1] = id
				local quest = data.quests[id]
				local optional = Optional(quest, QuestLevel(data, log, player, id), player)
				for _, node in ipairs(nodes[id]) do
					Gather(data, areas, plan.anchors, fresh, node, id, quest.title, "area", optional, Touches, true)
				end
			else
				picks[id] = nil
			end
		end
		Trim(town, town.handins, pickups)
	end
	for index = #areas, 1, -1 do
		if skipped[areas[index].key] then
			Skip(areas[index].key)
			table.remove(areas, index)
		end
	end
	-- An area keeps the key the committed order knows it by when a quest taken up since, or the lap's pickup, joins
	-- it and would key it anew: the key of its objective the order places first.
	local named = {}
	for _, area in ipairs(areas) do
		named[area.key] = true
	end
	for _, area in ipairs(areas) do
		Tell(area)
		local best = rank[area.key] and area.key or nil
		for _, objective in ipairs(best and NONE or area.objectives) do
			local key = ("area:%d:%d"):format(objective.id, objective.slot)
			if rank[key] and not named[key] and (not best or rank[key] < rank[best]) then
				best = key
			end
		end
		if best and best ~= area.key then
			named[area.key], named[best], area.key = nil, true, best
		end
	end

	-- The anchors: each town with a visit, and each town a lap takes the log's quests back to.
	local anchors, list = {}, {}
	local function Anchor(key, place)
		local anchor = anchors[key]
		if not anchor then
			anchor = { key = key, place = place, pos = At(place), stops = {}, hands = {} }
			anchors[key], list[#list + 1] = anchor, anchor
		end
		return anchor
	end
	for _, town in ipairs(towns) do
		if #town.quests > 0 then
			Anchor(town.key, town).open = town
		end
	end
	local pending, carried, homes = {}, {}, {}
	for _, area in ipairs(areas) do
		for _, objective in ipairs(area.objectives) do
			local id = objective.id
			pending[id] = (pending[id] or 0) + 1
			if not picks[id] and homes[id] == nil then
				carried[#carried + 1], homes[id] = id, false
				local finish = data.quests[id] and data.quests[id].finish
				local key = ValidPlace(finish) and "town:" .. Hub(finish)
				if key and not skipped[key] and Cost(At(area), At(finish)) <= LAP_YARDS / 2 then
					homes[id] = Anchor(key, finish)
				end
			end
		end
	end
	table.sort(carried)
	for _, id in ipairs(carried) do
		table.insert(homes[id] and homes[id].hands or {}, id)
	end
	for _, id in ipairs(ids) do
		local town, finish = picks[id], data.quests[id].finish
		homes[id] = town and anchors[town.key] or false
		-- A lap hands in only what it does: not an outdoor elite, whose work waits for a group, nor a lead whose work
		-- the data places nowhere.
		local quest = data.quests[id]
		local planned = not quest.elite and (#nodes[id] > 0 or next(quest.need or NONE) == nil)
		if town and planned and ValidPlace(finish) and "town:" .. Hub(finish) == town.key then
			table.insert(anchors[town.key].hands, id)
		end
	end
	-- A town with only hand-ins ready, which no lap comes back to, is a stop on the way like a turn-in.
	for index = #list, 1, -1 do
		local anchor = list[index]
		if #list > 1 and anchor.open and #anchor.open.pickups == 0 and #anchor.hands == 0 then
			others[#others + 1], anchors[anchor.key] = anchor.open, nil
			table.remove(list, index)
		end
	end
	-- A stop no quest's town takes goes to the nearest town within half a lap, else to the laps around the player.
	local function Closest(step)
		local best, bestCost
		for _, anchor in ipairs(list) do
			local cost = anchor.key ~= "" and anchor.pos and Cost(anchor.pos, At(step)) or UNKNOWN
			if cost <= LAP_YARDS / 2 and (not best or cost < bestCost) then
				best, bestCost = anchor, cost
			end
		end
		return best or Anchor("", player)
	end
	-- An area goes with the town most of its objectives go back to, the first of them on a tie.
	for _, area in ipairs(areas) do
		local anchor, votes = nil, {}
		for _, objective in ipairs(area.objectives) do
			local home = homes[objective.id]
			if home then
				votes[home] = (votes[home] or 0) + 1
				anchor = (not anchor or votes[home] > votes[anchor]) and home or anchor
			end
		end
		anchor = anchor or Closest(area)
		anchor.stops[#anchor.stops + 1] = area
	end
	local trained = false
	for _, step in ipairs(others) do
		-- A trainer only in a town a lap visits anyway (its hub, or one within the town linkage: a town of several
		-- hubs), and once.
		local anchor
		if step.kind == "trainer" then
			anchor = not trained and step.hub and anchors["town:" .. step.hub] or nil
			for _, near in ipairs(not (anchor or trained) and list or NONE) do
				local cost = near.key ~= "" and near.pos and Cost(near.pos, At(step)) or UNKNOWN
				anchor = anchor or (cost <= AGREE and near or nil)
			end
			trained = trained or anchor ~= nil
		else
			anchor = Closest(step)
		end
		table.insert(anchor and anchor.stops or {}, step)
	end

	-- The laps, the one that leads first, and more while none has gone out to an area.
	local laps = {}
	for _, anchor in ipairs(list) do
		local cut = Sweep(anchor, At)
		if #cut == 0 and anchor.open then
			cut[1] = { key = anchor.key .. ":1", anchor = anchor, stops = {} }
		end
		for _, lap in ipairs(cut) do
			laps[#laps + 1] = lap
		end
	end
	local route, used, from, out, done, handed = {}, {}, origin, false, {}, {}
	local leadTown = leadID and picks[leadID]
	local leadAnchor = leadTown and anchors[leadTown.key]
	local standing
	for _, lap in ipairs(laps) do
		for _, stop in ipairs(lap.stops) do
			local yards = stop.kind == "area" and not stop.planned and Model.Yards(data, player, stop)
			standing = standing or (yards and yards <= (stop.r or 0) and lap) or nil
		end
	end
	-- The lap under way goes on until it ends: the one out to the area first in the committed order is the only one
	-- that may go out.
	local underway, first
	for _, lap in ipairs(laps) do
		for _, stop in ipairs(lap.stops) do
			local at = stop.kind == "area" and rank[stop.key]
			if at and (not first or at < first) then
				underway, first = lap, at
			end
		end
	end
	-- Its last area in the committed order: a town the order visits before it is one the lap under way takes in.
	local ends = first
	for _, stop in ipairs(underway and underway.stops or NONE) do
		ends = math.max(ends, stop.kind == "area" and rank[stop.key] or 0)
	end
	-- The town the player stands in comes first, whatever leads: its trainer, hand-ins and pickups are a word away. So
	-- does a town the committed order visits before the lap under way ends, out of another lap (only the lap under way
	-- goes out), as it did when the player stood in it.
	local function Before(stop, lap)
		return lap ~= underway and (rank[Ident(stop)] or math.huge) < (ends or 0)
	end
	for _, lap in ipairs(laps) do
		local goes = false
		for index = #lap.stops, 1, -1 do
			local stop = lap.stops[index]
			goes = goes or stop.kind == "area"
			local town = (stop.kind == "town" or stop.kind == "trainer") and stop.hub
			if town and (Cost(origin, At(stop)) <= HERE or Before(stop, lap)) then
				route[#route + 1] = table.remove(lap.stops, index)
			end
		end
		local open = not lap.anchor.visited and lap.anchor.open or nil
		if open and open.hub and (Cost(origin, At(open)) <= HERE or (goes and Before(open, lap))) then
			lap.anchor.visited, route[#route + 1] = true, open
		end
	end
	from = route[#route] and At(route[#route]) or from
	-- The lap to take next from `from`, or nil.
	local function Pick()
		local best, bestScore
		for _, lap in ipairs(laps) do
			local anchor = lap.anchor
			local open = not anchor.visited and anchor.open or nil
			-- A lap to a town the committed order visits before the lap under way ends comes in that order, before it.
			local held = open and rank[Ident(open)]
			local goes = false
			for _, stop in ipairs(lap.stops) do
				local at = stop.kind ~= "area" and rank[Ident(stop)]
				held = at and math.min(held or at, at) or held
				goes = goes or stop.kind == "area"
			end
			held = lap ~= underway and held and held < (ends or math.huge) and held or nil
			-- Until the lead's town is visited, only its lap, one that never goes out to an area, or the one whose area
			-- the player stands in may come first; while a lap is under way, only it and those towns.
			local waits = (
				goes
				and leadAnchor ~= nil
				and not leadAnchor.visited
				and anchor ~= leadAnchor
				and lap ~= standing
			) or (underway ~= nil and lap ~= underway and not held)
			if not used[lap] and (open or #lap.stops > 0) and not waits then
				local reach = open and Cost(from, At(open)) or UNKNOWN
				local value = open and Value(data, log, player, open) or 0
				for _, stop in ipairs(lap.stops) do
					reach = math.min(reach, Gap(from, 0, At(stop), stop.r or 0))
					value = value + VALUE_QUEST * #stop.quests
				end
				local score = held and held - UNKNOWN * UNKNOWN or reach - value
				if not best or score < bestScore or (score == bestScore and lap.key < best.key) then
					best, bestScore = lap, score
				end
			end
		end
		return best
	end
	while not out and #route < Model.MAX_STEPS do
		local best = Pick()
		-- The lap under way that can no longer come (it waits for the lead's town, or is taken) holds nothing back.
		if not best and underway then
			underway = nil
			best = Pick()
		end
		if not best then
			break
		end
		used[best] = true
		-- A finished quest waits for nothing, so one handed in within half a lap of this lap's town comes along from a
		-- later lap: a hand-in-only stop, or the hand-ins of a town whose own lap comes later, split from its pickups.
		local home = best.anchor.pos or from
		for _, lap in ipairs(laps) do
			for index = used[lap] and 0 or #lap.stops, 1, -1 do
				local stop = lap.stops[index]
				if HandInOnly(stop) and stop.kind ~= "trainer" and Cost(home, At(stop)) <= LAP_YARDS / 2 then
					best.stops[#best.stops + 1] = table.remove(lap.stops, index)
				end
			end
			local town = lap.anchor ~= best.anchor and not lap.anchor.visited and lap.anchor.open or nil
			if town and #town.handins > 0 and #town.pickups > 0 and Cost(home, At(town)) <= LAP_YARDS / 2 then
				local fields = {}
				for key, value in pairs(town) do
					fields[key] = value
				end
				local split = fields --[[@as AGFStep]]
				split.follow, split.givers = {}, {}
				Trim(split, town.handins, {})
				Trim(town, {}, town.pickups)
				best.stops[#best.stops + 1] = split
			end
		end
		local anchor = best.anchor
		local open = not anchor.visited and anchor.open or nil
		anchor.visited = anchor.visited or open ~= nil
		local after, closing, closes = {}, {}, {}
		for _, stop in ipairs(best.stops) do
			for _, objective in ipairs(stop.objectives or NONE) do
				done[objective.id] = (done[objective.id] or 0) + 1
				after[stop] = after[stop] or (open ~= nil and picks[objective.id] == open)
			end
			out = out or stop.kind == "area"
		end
		for _, id in ipairs(anchor.hands) do
			local ready = (done[id] or 0) == (pending[id] or 0)
			if ready and not handed[id] and (log[id] or anchor.visited) then
				closing[#closing + 1], handed[id] = id, true
			end
		end
		local close
		for _, id in ipairs(closing) do
			close = Visit(closes, {}, data.quests[id].finish, "handins", id)
			close.returns = close.returns or {}
			close.returns[id] = true
			if not log[id] then
				close.planned = close.planned or {}
				close.planned[id] = true
			end
		end
		for _, step in ipairs(Sequence(from, open, best.stops, close, after, At)) do
			route[#route + 1] = step
			from = At(step) or from
		end
	end
	-- The next lap's town once the lap under way has gone out, when a step is left over: the first by reach and worth
	-- with quests to pick up, the committed order's first. Its areas wait for the lap it leads, so the route stays one
	-- lap long.
	underway, ends = nil, nil
	local nextTown
	while out and #route + #groups < Model.MAX_STEPS do
		local nextLap = Pick()
		if not nextLap then
			break
		end
		used[nextLap] = true
		local open = not nextLap.anchor.visited and nextLap.anchor.open or nil
		if open and #open.pickups > 0 then
			nextTown, nextLap.anchor.visited, route[#route + 1] = open, true, open
			break
		end
	end
	for _, step in ipairs(groups) do
		route[#route + 1] = step
	end
	for index = #route, Model.MAX_STEPS + 1, -1 do
		route[index] = nil
	end

	-- The route checked in order, as the player would play it.
	local cap, count = player.logMax or math.huge, 0
	for _ in pairs(log) do
		count = count + 1
	end
	-- The committed route's pickups keep their slots in the log: a new one is taken only with room left for every
	-- committed one after it, so a rebuild never trades one for another.
	local picked = committedOrders and committedOrders[card] and committedOrders[card].picked or {}
	local function Verify(steps)
		local have, did, checked, left, owed = {}, {}, {}, count, 0
		for _, step in ipairs(steps) do
			for _, id in ipairs(step.kind == "town" and step.pickups or NONE) do
				owed = owed + (picked[id] and 1 or 0)
			end
		end
		for _, step in ipairs(steps) do
			if step.kind == "town" then
				local handins, pickups = {}, {}
				for _, id in ipairs(step.handins) do
					local entry, back = log[id], step.returns and step.returns[id]
					if
						(entry and entry.complete and not back)
						or (back and (entry or have[id]) and (did[id] or 0) >= (pending[id] or 0))
					then
						handins[#handins + 1], left = id, left - 1
					end
				end
				local order = {}
				for _, id in ipairs(step.pickups) do
					order[#order + 1] = id
				end
				table.sort(order, function(a, b)
					if (a == leadID) ~= (b == leadID) then
						return a == leadID
					elseif (ratio[a] or math.huge) ~= (ratio[b] or math.huge) then
						return (ratio[a] or math.huge) > (ratio[b] or math.huge)
					end
					return a < b
				end)
				for _, id in ipairs(order) do
					owed = owed - (picked[id] and 1 or 0)
					if left + (picked[id] and 0 or owed) < cap and not have[id] then
						pickups[#pickups + 1], have[id], left = id, true, left + 1
					end
				end
				table.sort(pickups)
				Trim(step, handins, pickups)
			elseif step.objectives then
				local objectives, quests = {}, {}
				for _, objective in ipairs(step.objectives) do
					local id = objective.id
					if (log[id] and not log[id].complete) or have[id] then
						objectives[#objectives + 1], did[id] = objective, (did[id] or 0) + 1
						quests[#quests + 1] = quests[#quests] ~= id and id or nil
					end
				end
				step.objectives, step.quests = objectives, quests
			end
			if #step.quests > 0 or step.kind == "trainer" then
				checked[#checked + 1] = step
			end
		end
		return checked
	end
	-- Whether `steps` may be walked in order: every objective after its quest's pickup, a hand-in the route comes back
	-- for after all its objectives there, and the log never past its limit.
	local function Holds(steps)
		local have, did, total, left = {}, {}, {}, count
		for _, step in ipairs(steps) do
			for _, objective in ipairs(step.objectives or NONE) do
				total[objective.id] = (total[objective.id] or 0) + 1
			end
		end
		for _, step in ipairs(steps) do
			for _, id in ipairs(step.handins or (step.kind == "turnin" and step.quests) or NONE) do
				if
					not (log[id] or have[id])
					or (step.returns and step.returns[id] and (did[id] or 0) < (total[id] or 0))
				then
					return false
				end
				left = left - 1
			end
			for _, id in ipairs(step.pickups or NONE) do
				have[id], left = true, left + 1
				if left > cap then
					return false
				end
			end
			for _, objective in ipairs(step.objectives or NONE) do
				local id = objective.id
				if not (log[id] or have[id]) then
					return false
				end
				did[id] = (did[id] or 0) + 1
			end
		end
		return true
	end
	-- Where the player stands leads, whatever the committed order: the town (its trainer, hand-ins and pickups a word
	-- away), else the open area.
	local function Front(leads)
		local moved = {}
		for _, step in ipairs(route) do
			moved[#moved + 1] = leads[step] and step or nil
		end
		for _, step in ipairs(route) do
			moved[#moved + 1] = not leads[step] and step or nil
		end
		route = Holds(moved) and moved or route
	end
	-- Checked in the committed order, then settled against the steps kept in the fresh order.
	-- The next lap's town stays after the lap under way, wherever an older order had it, and the orders are weighed
	-- so.
	local function Last(steps)
		local last = {}
		for _, step in ipairs(steps) do
			last[#last + 1] = step ~= nextTown and step or nil
		end
		last[#last + 1] = #last < #steps and nextTown or nil
		return Holds(last) and last or steps
	end
	local verified, survived, plain = Verify(Recommit(route, rank)), {}, {}
	for _, step in ipairs(verified) do
		survived[step] = true
	end
	for _, step in ipairs(route) do
		plain[#plain + 1] = survived[step] and step or nil
	end
	route = Stabilise(verified, plain, rank, Holds, At, origin, Last)
	local inTown = {}
	for _, step in ipairs(route) do
		inTown[step] = step.kind ~= "area" and step.hub ~= nil and Cost(origin, At(step)) <= HERE or nil
	end
	Front(inTown)
	local here = not inTown[route[1]] and Model.Here(data, player, route)
	if here and here > 1 then
		Front({ [route[here]] = true })
	end
	-- The order is committed before the visits merge, so the next build, which splits them again, keeps to it.
	local order = committedOrders and card and Idents(route) --[[@as AGFOrder?]]
	-- Two visits to one town in a row are one, unless the second hands in what the first handed out.
	for index = #route, 2, -1 do
		local a, b = route[index - 1], route[index]
		if a.kind == "town" and b.kind == "town" and a.key == b.key then
			local apart = false
			for _, id in ipairs(b.handins) do
				apart = apart or a.spots[id] ~= nil
			end
			if not apart then
				local lists = { handins = {}, pickups = {} }
				for name, merged in pairs(lists) do
					for _, step in ipairs({ a, b }) do
						for _, id in ipairs(step[name]) do
							merged[#merged + 1], a.spots[id] = id, a.spots[id] or step.spots[id]
						end
					end
				end
				for _, name in ipairs({ "planned", "returns" }) do
					for id in pairs(b[name] or NONE) do
						a[name] = a[name] or {}
						a[name][id] = true
					end
				end
				Trim(a, lists.handins, lists.pickups)
				table.remove(route, index)
			end
		end
	end
	local visits = {}
	for index = 1, #route do
		local step = route[index]
		if step.kind == "town" then
			visits[step.key] = (visits[step.key] or 0) + 1
			step.key = visits[step.key] > 1 and ("%s:%d"):format(step.key, visits[step.key]) or step.key
		end
	end
	for index = #route, 1, -1 do
		if skipped[route[index].key] then
			Skip(route[index].key)
			table.remove(route, index)
		end
	end
	route = Verify(route)
	if order then
		order.picked = {}
		for _, step in ipairs(route) do
			for _, id in ipairs(step.kind == "town" and step.pickups or NONE) do
				order.picked[id] = true
			end
		end
		committedOrders[card] = order
	end
	if join then
		join(route)
	end
	from = origin
	for _, step in ipairs(route) do
		if step.kind == "town" then
			Describe(data, log, player, step)
			Opens(data, player, completed, log, step)
			local best, bestCost
			for _, id in ipairs(step.quests) do
				local cost = CostTo(from, Point(data, step.spots[id])) -- multi-value: the spot's point
				if not best or cost < bestCost then
					best, bestCost = step.spots[id], cost
				end
			end
			step.map, step.x, step.y = best.map, best.x, best.y
		elseif step.objectives then
			Tell(step)
		elseif step.kind == "trainer" then
			Describe(data, log, player, step)
		end
		Locate(data, step, mapName)
		from = Position(data, step, docks) or from
	end
	return route
end

-- The journey cards (docs/design.md §2.2): at most MAX_JOURNEYS, each holding only steps the player can take now.
local NEXT_ZONE_AHEAD = 2 -- levels: the next zones are those that fit the player two levels on
local NEXT_ZONES = 3 -- zone cards besides the story's, best ranked first
local NEXT_ZONE_PICKUPS = 5 -- quests there two levels on, or the card is too thin to offer (docs/plan.md §1.5)...
local NEXT_ZONE_NOW = 3 -- ...of which this many open now: a zone the player has just come of age for is offered early
local FITS = 3 -- the zones "that fit": the first this many of a ranking, where the zone the player stands in is theirs
local ZONE_AWAY = 3 -- a zone's cost on another continent than the player's (Rank)
local ZONE_YARDS, ZONE_NEAR = 4000, 1.5 -- one a this many yards to a zone's middle on the player's own, at most this

-- Each zone's middle, placed once (Far).
---@type table<AGFData, table<integer, AGFPosition|false>>
local middles = setmetatable({}, { __mode = "k" })

-- A zone's distance cost from the player for Rank: none when the data cannot place them both, so the ranking never
-- guesses.
---@return fun(map: integer): number
local function Far(data, player)
	local here = Position(data, player)
	local kept = middles[data] or {}
	middles[data] = kept
	return function(map)
		kept[map] = kept[map] or Position(data, { map = map, x = 0.5, y = 0.5 }) or false
		local there = here and here.known and kept[map] or nil
		if not (here and there and there.known) then
			return 0
		elseif there.continent ~= here.continent then
			return ZONE_AWAY
		end
		return math.min(Yards(here, there) / ZONE_YARDS, ZONE_NEAR)
	end
end

local function ZoneName(data, map, mapName)
	return (mapName and mapName(map)) or data.zones[map].name
end

-- Whether the story card of `zone` holds log quest `id` (LogSteps): it is done next on the zone's map, or, with no
-- place known, the data files it under the zone. Every other log quest is carry's.
---@param zone? integer
---@param place? {map: integer}
local function OnZone(data, zone, id, place)
	if place then
		return place.map == zone
	end
	local quest = data.quests[id]
	return zone ~= nil and quest ~= nil and quest.zone == zone
end

-- A card's count of the log quests it holds (LogSteps' `held`), placed or not, less those whose step is skipped: the
-- finished ones, those of them handed in across an ocean from the player, and those under way.
---@param held table<integer, AGFStep|false>
---@return integer finished, integer away, integer underway
local function Tally(data, player, log, held, prefs)
	local finished, away, underway = 0, 0, 0
	for id, step in pairs(held) do
		if not (step and prefs.skipped[step.key]) then
			if not log[id].complete then
				underway = underway + 1
			elseif step and Oversea(data, player, step) then
				away = away + 1
			else
				finished = finished + 1
			end
		end
	end
	return finished, away, underway
end

-- The log nearly full (docs/design.md §2.18): with LOG_ROOM slots or fewer left, the quests under way the player
-- could drop to make room, by ID: one they ruled out, one gone grey, one nothing places, and one done across an ocean
-- from them. Never a finished one, nor one the data lacks. Advice only: the guide abandons nothing. Nil otherwise.
local LOG_ROOM = 2
---@return integer[]?
local function Droppable(data, player, log)
	local count, ids = 0, {}
	for _ in pairs(log) do
		count = count + 1
	end
	if not player.logMax or player.logMax - count > LOG_ROOM then
		return nil
	end
	for id, entry in pairs(log) do
		if data.quests[id] and not entry.complete then
			local place = Nodes(data, entry)[1]
			if
				Dropped(id)
				or Model.IsGray(QuestLevel(data, log, player, id), player.level)
				or not place
				or Oversea(data, player, place)
			then
				ids[#ids + 1] = id
			end
		end
	end
	table.sort(ids)
	return #ids > 0 and ids or nil
end

-- Build's route within the log's limit (Laps keeps its own): walked in order, a pickup past it waits, and a town left
-- with nothing goes.
---@param steps AGFStep[]
---@return AGFStep[]
local function Within(data, player, completed, log, steps)
	local left, cap, kept = 0, player.logMax or math.huge, {}
	for _ in pairs(log) do
		left = left + 1
	end
	for _, step in ipairs(steps) do
		if step.kind == "town" then
			left = left - #step.handins
			local pickups = {}
			for _, id in ipairs(step.pickups) do
				if left < cap then
					pickups[#pickups + 1], left = id, left + 1
				end
			end
			if #pickups < #step.pickups then
				Trim(step, step.handins, pickups)
				Describe(data, log, player, step)
				Opens(data, player, completed, log, step)
			end
		end
		kept[#kept + 1] = #step.quests > 0 and step or (step.kind == "trainer" and step) or nil
	end
	return kept
end

-- The quests the player added (shift-click, `prefs.pinned`) that no zone card holds: open now, not ruled out, and not
-- an instance's or a raid's, which only the dungeon card offers. By ID.
---@param elsewhere fun(quest: AGFQuest): boolean
---@return integer[]
local function Added(data, player, completed, log, prefs, elsewhere)
	local ids, groups = {}, Index(data).groups
	for id in pairs(prefs.quests and prefs.pinned or NONE) do
		local quest = data.quests[id]
		if
			quest
			and not (quest.dungeon or quest.raid)
			and not Dropped(id)
			and elsewhere(quest)
			and Eligible(data, player, completed, log, id, groups)
		then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	return ids
end

-- "Loose ends": the log's turn-ins and objectives the story card doesn't hold (`elsewhere`), and the quests the player
-- added that no zone card holds (`added`). The subline counts every quest the card holds, not only the steps that made
-- the route, and those nothing places.
---@param ready table<integer, AGFPlace>
---@param elsewhere fun(id: integer, place?: table): boolean
---@param added integer[]
local function Carry(data, player, completed, log, ready, prefs, mapName, cheap, elsewhere, added)
	local candidates, stops = TrainerSteps(data, player, prefs, "carry"), {}
	local held = LogSteps(data, player, log, ready, function(id, place)
		return not Dropped(id) and elsewhere(id, place)
	end, stops, candidates, { areas = {}, anchors = {} })
	PickupSteps(data, added, function()
		return true
	end, candidates, stops)
	local steps = Build(data, player, completed, log, candidates, prefs, mapName, cheap)
	steps = #added > 0 and Within(data, player, completed, log, steps) or steps
	if #steps == 0 then
		return nil
	end
	-- A finished quest whose hand-in is across an ocean is not ready yet: the reason line counts those, so no fact
	-- is told twice on the card.
	local L = ns.L
	local finished, away, underway = Tally(data, player, log, held, prefs)
	local parts = {}
	parts[#parts + 1] = finished > 0 and L.CARRY_READY:format(finished) or nil
	parts[#parts + 1] = underway > 0 and L.CARRY_IN_PROGRESS:format(underway) or nil
	parts[#parts + 1] = #added > 0 and L.CARRY_ADDED:format(#added) or nil
	local farther = away > 0 and L.CARRY_AWAY:format(away) or nil
	return {
		kind = "carry",
		key = "carry",
		title = L.JOURNEY_CARRY,
		subline = #parts > 0 and table.concat(parts, L.LIST_SEPARATOR) or farther,
		reason = #parts > 0 and farther or nil,
		map = steps[1].map,
		steps = steps,
	}
end

-- The finished quests in `ready` join the chosen towns they are handed in at, hand-ins first; none adds a town.
---@param ready table<integer, AGFPlace>
---@return fun(selected: AGFStep[])
local function HandIns(ready)
	return function(selected)
		local towns, ids = {}, {}
		for _, step in ipairs(selected) do
			towns[step.key] = step.kind == "town" and step or nil
		end
		for id in pairs(ready) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local town = towns["town:" .. Hub(ready[id])]
			if town and not town.spots[id] then
				Visit(towns, selected, ready[id], "handins", id)
			end
		end
	end
end

-- The quests a zone's cards hold: those filed under it, else those picked up on it; never a raid's, which no zone card
-- offers, as the dungeon card offers none (F15).
---@return fun(quest: AGFQuest): boolean
local function InZone(zone)
	return function(quest)
		return not quest.raid and (quest.zone or quest.start.map) == zone
	end
end

-- The eligible quests `belongs` keeps as one journey (kind, key and title are the caller's), and how many it holds.
-- The step that offers `leadID` is always among them; the hand-ins in `ready` join the towns it holds. A story card
-- (`zone`) also holds the log quests done next on its zone (OnZone), its towns' hand-ins with their pickups, and its
-- subline counts them first.
---@param ready table<integer, AGFPlace>
---@param belongs fun(quest: AGFQuest): boolean
---@param key string the journey's key: its trainer stop joins it while it is chosen
---@param zone? integer
---@param laps? boolean the card is card 1 or the chosen one: its route is laps (Laps), Build's otherwise
local function Pickups(data, player, completed, log, ready, eligible, belongs, key, prefs, mapName, leadID, zone, laps)
	local candidates, stops, quests, lead, held = {}, {}, 0, nil, nil
	local plan = { areas = {}, anchors = {} }
	for _, id in ipairs(eligible) do
		quests = quests + (belongs(data.quests[id]) and 1 or 0)
	end
	-- With Quests off the story holds no log quest, so it never stays for the log alone: carry holds them.
	if zone and prefs.quests then
		held = LogSteps(data, player, log, ready, function(id, place)
			return not Dropped(id) and OnZone(data, zone, id, place)
		end, stops, candidates, plan)
	end
	PickupSteps(data, eligible, belongs, candidates, stops)
	for _, step in ipairs(TrainerSteps(data, player, prefs, key)) do
		candidates[#candidates + 1] = step
	end
	for _, step in ipairs(candidates) do
		for _, id in ipairs(step.quests) do
			lead = id == leadID and step or lead
		end
	end
	local steps = laps
			and Laps(
				data,
				player,
				completed,
				log,
				candidates,
				plan,
				prefs,
				mapName,
				lead and leadID,
				HandIns(ready),
				key
			)
		or Within(
			data,
			player,
			completed,
			log,
			Build(data, player, completed, log, candidates, prefs, mapName, false, lead, HandIns(ready))
		)
	if #steps == 0 then
		return nil, quests
	end
	-- The lead only when the route kept it: a skipped chapter leaves the card to the zone's count.
	local kept
	for _, step in ipairs(steps) do
		kept = kept or step == lead
	end
	local L, parts, holds = ns.L, {}, nil
	if held then
		-- The card counts every log quest it holds on its zone, those its laps take later too; carry holds the rest.
		local finished, away, underway = Tally(data, player, log, held, prefs)
		parts[#parts + 1] = finished + away > 0 and L.CARRY_READY:format(finished + away) or nil
		parts[#parts + 1] = underway > 0 and L.CARRY_IN_PROGRESS:format(underway) or nil
		local drawn, later = {}, 0
		for _, step in ipairs(steps) do
			for _, id in ipairs(step.handins or (step.kind ~= "trainer" and step.quests) or NONE) do
				drawn[id] = true
			end
		end
		holds = {}
		for id, step in pairs(held) do
			holds[id] = true
			later = later + ((drawn[id] or (step and prefs.skipped[step.key])) and 0 or 1)
		end
		parts[#parts + 1] = later > 0 and #parts > 0 and L.LATER_LAPS:format(later) or nil
	end
	parts[#parts + 1] = (quests > 0 or #parts == 0) and Count(L.QUESTS_NEAR_ONE, L.QUESTS_NEAR, quests) or nil
	local subline = table.concat(parts, L.LIST_SEPARATOR)
	return { map = steps[1].map, steps = steps, subline = subline, count = subline, holds = holds },
		quests,
		kept and lead or nil
end

-- The dungeon card's instance (F15): while dungeons are `open` (on, or no next zone: roadmap #21), the party instance
-- with the most quests the player can take now (the lowest Map.ID on a tie); the `chosen` instance instead while it has
-- any, so a choice never moves to another dungeon. Raids are never offered. Nil when none has a quest.
---@param open boolean
---@param chosen? integer
---@return integer?
local function BestDungeon(data, eligible, prefs, open, chosen)
	if not (open and data.instances) then
		return nil
	end
	local counts, best, dismissed = {}, nil, prefs.notInterested or {}
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local instance = not quest.raid and quest.dungeon
		if instance and data.instances[instance] and not dismissed["dungeon:" .. instance] then
			counts[instance] = (counts[instance] or 0) + 1
		end
	end
	for instance, count in pairs(counts) do
		if not best or count > counts[best] or (count == counts[best] and instance < best) then
			best = instance
		end
	end
	return chosen and counts[chosen] and chosen or best
end

-- The quests a dungeon card holds: its instance's, never a raid's.
---@return fun(quest: AGFQuest): boolean
local function InDungeon(instance)
	return function(quest)
		return quest.dungeon == instance and not quest.raid
	end
end

-- The dungeon card for `best`: its steps the givers of its quests. Named by the client, in the player's language, and
-- by the data otherwise; an instance the data doesn't name gets no card. Its reason (roadmap #15) counts the log's
-- quests filed under the instance, which end inside it: "2 of your quests end inside Wailing Caverns".
---@param instanceName? fun(id: integer): string?
---@param best integer
---@param quests integer how many of its quests the player can take now
local function DungeonJourney(data, player, completed, log, eligible, prefs, mapName, instanceName, best, quests)
	local candidates = {}
	PickupSteps(data, eligible, InDungeon(best), candidates)
	for _, step in ipairs(TrainerSteps(data, player, prefs, "dungeon:" .. best)) do
		candidates[#candidates + 1] = step
	end
	local steps = Within(data, player, completed, log, Build(data, player, completed, log, candidates, prefs, mapName))
	if #steps == 0 then
		return nil
	end
	local name = instanceName and instanceName(best) or data.instances[best].name
	local L, inside, belongs = ns.L, 0, InDungeon(best)
	for id in pairs(log) do
		inside = inside + ((data.quests[id] and not Dropped(id) and belongs(data.quests[id])) and 1 or 0)
	end
	local reason = inside == 1 and L.DUNGEON_INSIDE_ONE:format(name)
		or inside > 1 and L.DUNGEON_INSIDE:format(inside, name)
		or nil
	return {
		kind = "dungeon",
		key = "dungeon:" .. best,
		title = name,
		subline = Count(L.DUNGEON_QUESTS_ONE, L.DUNGEON_QUESTS, quests),
		reason = reason,
		map = steps[1].map,
		steps = steps,
	}
end

-- The eligible quests with the instance quests the Dungeons toggle holds back put in, in the index's order: each open
-- to the player now, as Choices judges its own (roadmap #21).
---@param eligible integer[]
---@return integer[]
local function WithInstances(data, player, completed, log, index, eligible)
	local open, pool = {}, {}
	for _, id in ipairs(eligible) do
		open[id] = true
	end
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		if
			open[id]
			or (
				quest.dungeon
				and quest.min <= player.level
				and not Model.IsGray(quest.level, player.level)
				and Eligible(data, player, completed, log, id, index.groups)
			)
		then
			pool[#pool + 1] = id
		end
	end
	return pool
end

-- The instance a chain leads into: the first quest from its chapter on filed under an instance the data names. Nil
-- when none is: the data never says a chain is an attunement, only that it goes inside.
---@param chain AGFStory
---@return integer?
local function Into(data, chain)
	for index = chain.chapter, #chain.members do
		local instance = data.quests[chain.members[index]].dungeon
		if instance and data.instances and data.instances[instance] then
			return instance
		end
	end
end

-- The chain a card leads with (docs/design.md §2.3): of the chains among the quests `belongs` keeps that the player
-- can take up now, one they have already started before one they would begin, then the longest proven one, then the
-- lowest quest ID. A chapter whose chain was begun elsewhere, with the chapter before it not done, has no honest reason
-- to offer, so it never leads. Of an exclusive group only the first quest leads, the one PickupSteps offers.
---@param belongs fun(quest: AGFQuest, id: integer): boolean
---@return AGFStory?, integer?, boolean? the chain, the quest that takes it up, and whether it continues one
local function Lead(data, completed, eligible, belongs)
	local best, bestID, bestRank, continues
	local groups = {}
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local offered = belongs(quest, id) and not (quest.group and groups[quest.group])
		if offered and quest.group then
			groups[quest.group] = true
		end
		local story = offered and Model.Story(data, id)
		local started = story and story.chapter > 1 and completed[story.members[story.chapter - 1]] == true
		if story and (started or story.chapter == 1) then
			local rank = (started and 0 or 1000) - (story.total or 0)
			if not bestRank or rank < bestRank then
				best, bestID, bestRank, continues = story, id, rank, started
			end
		end
	end
	return best, bestID, continues
end

-- A card's hub line and group count (docs/plan.md §7.4): its first stop's place, how many stops follow it, and how
-- many of its quests need a group.
---@param journey AGFJourney
local function Summarise(journey)
	local first, group = journey.steps[1], 0
	for _, step in ipairs(journey.steps) do
		group = group + (step.group or 0)
	end
	journey.hub = first and (first.place or first.title)
	journey.more, journey.group = #journey.steps - 1, group
end

-- A zone card's reason in the world's voice (roadmap #3), the first that applies: a story the player started, at least
-- GREY_REASON_MIN of its quests going grey at the next level (never at the cap), the giver who begins its chain, then
-- its first quest stop's town (its flight master's name, before the zone) with HANDS_MIN quests or more to pick up.
-- Nil when none applies; the caller falls back to its plain line. Only names the data has: a chain's giver, a town's
-- flight master.
local GREY_REASON_MIN, HANDS_MIN = 2, 3
---@param journey AGFJourney
---@param chain? {continues: boolean, giver?: string}
---@return string?
local function WorldReason(data, log, player, journey, chain)
	local L = ns.L
	if chain and chain.continues then
		return L.CONTINUES_STORY
	end
	-- At the level cap there is no next level, so nothing is about to turn grey.
	local grey = 0
	for _, step in ipairs(player.level < player.maxLevel and journey.steps or NONE) do
		for _, id in ipairs(step.pickups or NONE) do
			grey = grey + (GreyRisk(QuestLevel(data, log, player, id), player) and 1 or 0)
		end
	end
	if grey >= GREY_REASON_MIN then
		return L.REASON_GREY:format(grey)
	elseif chain and chain.giver then
		return L.REASON_CHAIN_GIVER:format(chain.giver)
	end
	-- The first stop with quests: a trainer's stop (roadmap #5) ahead of its town never takes the town's reason.
	local first
	for _, step in ipairs(journey.steps) do
		first = first or (step.kind ~= "trainer" and step or nil)
	end
	local town = first and first.hub and data.hubs and data.hubs[first.hub]
	if town and #(first.pickups or {}) >= HANDS_MIN then
		return L.REASON_HANDS:format((town.name:match("^(.-),") or town.name))
	end
end

-- A card with a chain tells its chapter in place of its count, and the step that takes the chain up says so on the
-- map (docs/design.md §2.3). Returns the chapter row's reason: the chain begins or continues.
---@param journey AGFJourney
---@param chain AGFStory
---@param lead AGFStep
---@param continues? boolean
---@return string
local function Chapter(journey, chain, lead, continues)
	local L = ns.L
	local begins = continues and L.CONTINUES_STORY or L.BEGINS_STORY
	journey.story = chain
	journey.subline = chain.total and L.CHAPTER_OF:format(chain.chapter, chain.total) or L.CHAPTER:format(chain.chapter)
	lead.chapter, lead.reason = journey.subline, begins
	-- A lone quest's detail is its reason, so the row never says the chain continues under a card that begins it.
	lead.detail = #lead.quests == 1 and begins or lead.detail
	return begins
end

-- The zone's story card, or nil when `zone` has no step: of a chain when the zone has one the player can take up.
---@param ready table<integer, AGFPlace>
---@return AGFJourney?
local function StoryJourney(data, player, completed, log, ready, eligible, zone, prefs, mapName)
	local L = ns.L
	local chain, chainID, continues = Lead(data, completed, eligible, InZone(zone))
	local story, _, lead = Pickups(
		data,
		player,
		completed,
		log,
		ready,
		eligible,
		InZone(zone),
		"zone:" .. zone,
		prefs,
		mapName,
		chainID,
		zone,
		true
	)
	if not story then
		return nil
	end
	story.kind, story.key = "story", "zone:" .. zone
	story.title = L.JOURNEY_STORY:format(ZoneName(data, zone, mapName))
	---@cast story AGFJourney
	if chain and lead then
		local begins = Chapter(story, chain, lead, continues)
		local giver = data.quests[chainID].start.name
		story.reason = WorldReason(data, log, player, story, {
			continues = continues == true,
			giver = giver ~= "" and giver or nil,
		}) or begins
	else
		story.reason = WorldReason(data, log, player, story)
	end
	return story
end

-- A class quest (roadmap #7): one only the player's class may take. A mask of several classes is no calling: Vile
-- Familiars is every Horde class's but the warlock's, a starting zone's quest. A raid's is never offered, as the
-- dungeon card offers none (F15).
---@return fun(quest: AGFQuest): boolean
local function ForClass(classBit)
	return function(quest)
		return quest.classes == classBit and not quest.raid
	end
end

-- Your calling (roadmap #7, docs/design.md §2.2): the class quests the player can take now, as one card. It leads with
-- a chain as a zone's story does (§2.3), else the first class quest by ID, and its reason names that quest: "Your class
-- trainer has a task" only when the data proves its giver trains the player's class.
---@param ready table<integer, AGFPlace>
---@return AGFJourney?
local function CallingJourney(data, player, completed, log, ready, eligible, prefs, mapName)
	local laps = prefs.journey == "calling"
	local L, belongs = ns.L, ForClass(player.classBit)
	local chain, leadID, continues = Lead(data, completed, eligible, belongs)
	for _, id in ipairs(leadID and NONE or eligible) do
		leadID = leadID or (belongs(data.quests[id]) and id or nil)
	end
	local calling, quests, lead =
		Pickups(data, player, completed, log, ready, eligible, belongs, "calling", prefs, mapName, leadID, nil, laps)
	if not calling then
		return nil
	end
	calling.kind, calling.key, calling.title = "calling", "calling", L.JOURNEY_CALLING
	calling.subline = Count(L.CALLING_QUESTS_ONE, L.CALLING_QUESTS, quests)
	calling.count = calling.subline
	---@cast calling AGFJourney
	if lead then
		local quest = data.quests[leadID]
		local trainer = quest.start.trainer and 2 ^ (quest.start.trainer - 1) == player.classBit
		calling.reason = (trainer and L.CALLING_TRAINER or L.CALLING_TASK):format(quest.title)
		if chain then
			Chapter(calling, chain, lead, continues)
		end
	end
	return calling
end

-- A chain that leads into an instance, as a story (roadmap #21): `into` holds its quests the player can take now, led
-- by its chapter at `step`, and is named after the instance it goes into, by the client when it can.
---@param into table the chain's Pickups
---@param chain AGFStory
---@param step? AGFStep the chapter's step, when Build kept it
---@param instanceName? fun(id: integer): string?
---@return AGFJourney
local function WayIn(data, into, chain, step, continues, instanceName)
	local instance = Into(data, chain) --[[@as integer]]
	into.kind, into.key = "story", "chain:" .. chain.members[1]
	into.title = ns.L.JOURNEY_INTO:format(instanceName and instanceName(instance) or data.instances[instance].name)
	---@cast into AGFJourney
	if step then
		into.reason = Chapter(into, chain, step, continues)
	end
	return into
end

-- At most MAX_JOURNEYS cards: the last one not chosen makes way, so the chosen journey always keeps its slot.
---@param journeys AGFJourney[]
---@param chosen? string
local function Cap(journeys, chosen)
	while #journeys > Model.MAX_JOURNEYS do
		for index = #journeys, 1, -1 do
			if journeys[index].key ~= chosen then
				table.remove(journeys, index)
				break
			end
		end
	end
end

-- How many of the eligible quests `belongs` keeps, and the highest level any of them opened at (its newest quest's
-- minimum); nil when it keeps none.
---@param belongs fun(quest: AGFQuest): boolean
---@return integer, integer?
local function Newest(data, eligible, belongs)
	local count, opened = 0, nil
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		if belongs(quest) then
			count, opened = count + 1, math.max(opened or 0, quest.min)
		end
	end
	return count, opened
end

-- The diversions' order on a tie in newness (roadmap R4): the calling, then the dungeon, then a way into an instance
-- (roadmap #21), then the battleground the player asked for.
local DIVERSION_ORDER = { calling = 1, dungeon = 2, chain = 3, battleground = 4 }

-- Roadmap #12, opt-in: a battleground open to the player (player.battlegrounds, newest first) as a diversion whose card
-- has one step, its nearest battlemaster: the chosen battleground while it is still open, else the newest one the data
-- places a battlemaster for and the player is interested in. None where the data places none, so a card never points
-- at coordinates the data lacks; none either while its step is skipped, which Skipped (n) then keeps.
---@param prefs AGFPrefs
---@param mapName? fun(map: integer): string?
local function Battleground(data, player, prefs, mapName)
	local L, dismissed, open = ns.L, prefs.notInterested or {}, {}
	for _, bg in ipairs(player.battlegrounds or NONE) do
		local key = "battleground:" .. bg.id
		if not dismissed[key] then
			table.insert(open, key == prefs.journey and 1 or #open + 1, bg)
		end
	end
	for _, bg in ipairs(open) do
		local npc, id = Model.Battlemaster(data, player, bg.id)
		if npc and id then
			local key, place = "battlemaster:" .. id, npc.place
			if prefs.skipped and prefs.skipped[key] then
				if skippedSeen then
					skippedSeen[key] = true
				end
				return nil
			end
			local reason = L.BATTLEMASTER_QUEUE:format(bg.name)
			local step = {
				kind = "battlemaster",
				key = key,
				hub = place.hub,
				title = L.BATTLEMASTER_IN:format(Model.TownName(data, place, mapName)),
				detail = reason,
				reason = reason,
				quests = {},
				map = place.map,
				x = place.x,
				y = place.y,
				place = place.name,
			}
			Locate(data, step, mapName)
			local journey = {
				kind = "battleground",
				key = "battleground:" .. bg.id,
				title = bg.name,
				subline = L.BATTLEGROUND_SUBLINE,
				reason = step.title,
				map = step.map,
				steps = { step },
			}
			return {
				kind = "battleground",
				key = journey.key,
				opened = bg.level,
				quests = 0,
				build = function()
					return journey
				end,
			}
		end
	end
end

---@param mapName? fun(map: integer): string? the client's (localised) name for a map; the data's English otherwise
---@param instanceName? fun(id: integer): string? the client's name for an instance Map.ID; the data's otherwise
---@return AGFJourney[] journeys
---@return boolean stranded no next zone (roadmap #21)
function Model.Journeys(data, player, completed, log, prefs, mapName, instanceName)
	ReadDropped(prefs)
	local index, L = Index(data), ns.L
	-- Never past the level cap: a player at it has no next zone to head for.
	local levels = math.min(NEXT_ZONE_AHEAD, player.maxLevel - player.level)
	local zones, eligible, ahead, aheadQuests =
		Choices(data, player, completed, log, index, prefs, levels > 0 and levels or nil, Far(data, player))
	local ready = Ready(data, log)
	-- The offer rules below only gate new choices (docs/design.md §2.10): a chosen zone or dungeon is built while it
	-- has a step, whatever would offer it now.
	local chosen = prefs.journey or ""
	local chosenZone, chosenDungeon = tonumber(chosen:match("^zone:(%d+)$")), tonumber(chosen:match("^dungeon:(%d+)$"))
	-- A journey the player is not interested in (roadmap #17) is never a card, chosen or not: the next best takes its
	-- place.
	local dismissed = prefs.notInterested or {}
	local function Open(map)
		return map ~= nil and not dismissed["zone:" .. map]
	end
	chosenZone = Open(chosenZone) and chosenZone or nil
	local journeys = {}
	-- The story: the zone the player stands in when it is among the three their level fits now or two levels on (the
	-- next zone's, which is never the zone they are in), when their level is within its range and it has a quest they
	-- can take or carry (a zone whose quests they have taken up is still where they are adventuring), or is the chosen
	-- zone, so heading to a zone becomes its story on arrival; otherwise, or when it has no step (a capital), the zone
	-- the level fits best. It comes first, holding the log's quests on its zone; carry follows with the rest.
	local best
	for _, map in ipairs(zones) do
		best = best or (Open(map) and map or nil)
	end
	local zone, tries, here = best, { best }, chosenZone ~= nil and chosenZone == player.map
	-- As in the ranking, only a quest that isn't an outdoor elite or a raid's makes the zone the player's: an elite is
	-- optional, and no card offers a raid's.
	local band = data.zones[player.map]
	if band and band.min <= player.level and player.level <= band.max then
		for _, id in ipairs(here and NONE or eligible) do
			local quest = data.quests[id]
			here = here or (not quest.elite and not quest.raid and (quest.zone or quest.start.map) == player.map)
		end
		for id in pairs((here or not prefs.quests) and {} or log) do
			local quest = not Dropped(id) and data.quests[id] or nil
			here = here
				or (
					quest ~= nil
					and not quest.raid
					and quest.zone == player.map
					and not Model.IsGray(QuestLevel(data, log, player, id), player.level)
				)
		end
	end
	for _, ranking in ipairs({ zones, ahead or {} }) do
		for place = 1, math.min(FITS, #ranking) do
			here = here or ranking[place] == player.map
		end
	end
	if here and player.map ~= best and Open(player.map) then
		table.insert(tries, 1, player.map)
	end
	local told
	for _, map in ipairs(tries) do
		local story = StoryJourney(data, player, completed, log, ready, eligible, map, prefs, mapName)
		if story then
			zone, told = map, story
			journeys[#journeys + 1] = story
			break
		end
	end
	-- Carry (Loose ends) holds the log's quests off the story's zone, as the in-combat rebuild does: the story holds
	-- those on it, a later lap's too.
	local holds = told and told.holds or {}
	local onStory = InZone(zone)
	local added = Added(data, player, completed, log, prefs, function(quest)
		return not onStory(quest)
	end)
	journeys[#journeys + 1] = Carry(data, player, completed, log, ready, prefs, mapName, false, function(id)
		return not holds[id]
	end, added)
	-- The zones to head to (docs/design.md §2.2), best ranked first: two levels on, or now at the level cap. Each is
	-- another zone than the story's and the one the player stands in, whose range the player hasn't outgrown, with
	-- NEXT_ZONE_PICKUPS quests there at that level and NEXT_ZONE_NOW of them open now; and the chosen zone while it has
	-- a step, in its place or last. Only NEXT_ZONES are built, with Build's route: laps are for card 1 and the chosen
	-- card alone (§4.3).
	local open, headed, zoneCards = {}, chosenZone ~= zone and chosenZone or nil, 0
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local map = not quest.raid and (quest.zone or quest.start.map)
		if map then
			open[map] = (open[map] or 0) + 1
		end
	end
	local function NextZone(map)
		local key = "zone:" .. map
		local nextZone = Pickups(
			data,
			player,
			completed,
			log,
			ready,
			eligible,
			InZone(map),
			key,
			prefs,
			mapName,
			nil,
			nil,
			chosen == key
		)
		if not nextZone then
			return nil
		end
		nextZone.kind, nextZone.key = "nextzone", key
		nextZone.title = L.JOURNEY_NEXT_ZONE:format(ZoneName(data, map, mapName))
		-- The level it fits, while it is among the zones that fit two levels on.
		local fits, fitting = false, ahead or {}
		for place = 1, math.min(FITS, #fitting) do
			fits = fits or fitting[place] == map
		end
		nextZone.reason = WorldReason(data, log, player, nextZone --[[@as AGFJourney]])
			or (fits and L.NEXT_ZONE_LEVEL:format(player.level + levels) or nil)
		return nextZone
	end
	local offered = false
	for _, map in ipairs(ahead or zones) do
		local mine = map == chosenZone
		if map ~= zone and (mine or (map ~= player.map and Open(map))) then
			headed = headed or map
			local enough = (ahead and aheadQuests or {})[map] or open[map] or 0
			-- Never a zone the player has outgrown: what is left there is cleanup, which Loose ends holds.
			if
				mine
				or (
					player.level <= data.zones[map].max
					and zoneCards < NEXT_ZONES
					and enough >= NEXT_ZONE_PICKUPS
					and (open[map] or 0) >= NEXT_ZONE_NOW
				)
			then
				local card = NextZone(map)
				journeys[#journeys + 1] = card
				zoneCards, offered = zoneCards + (card and 1 or 0), offered or mine
			end
		end
	end
	if chosenZone and chosenZone ~= zone and not offered then
		journeys[#journeys + 1] = NextZone(chosenZone)
	end
	-- The diversions (roadmap R4) share the slots the zones leave: each offers itself with how many quests it holds and
	-- the level its newest one opened at, and the newest since then is built first, so a level just gained or a bracket
	-- just opened takes the slot. Only as many are built as there are slots, and the chosen one always.
	local diversions = {}
	local function Offer(kind, key, belongs, build, enough, from)
		local quests, opened = Newest(data, from or eligible, belongs)
		if opened and (key == prefs.journey or quests >= (enough or 1)) then
			diversions[#diversions + 1] = { kind = kind, key = key, opened = opened, quests = quests, build = build }
		end
	end
	if not dismissed.calling then
		Offer("calling", "calling", ForClass(player.classBit), function()
			return CallingJourney(data, player, completed, log, ready, eligible, prefs, mapName)
		end)
	end
	-- No next zone (roadmap #21): at the level cap, or with none ahead and no story here. The dungeon card is offered
	-- then whatever the Dungeons toggle says, and a chain that leads into an instance shows as a story, so the guide
	-- never ends on "nothing fits".
	local stranded = levels <= 0 or not (headed or told)
	local pool = (stranded and not prefs.dungeons) and WithInstances(data, player, completed, log, index, eligible)
		or eligible
	local instance = BestDungeon(data, pool, prefs, prefs.dungeons or stranded, chosenDungeon)
	if instance then
		Offer("dungeon", "dungeon:" .. instance, InDungeon(instance), function(quests)
			return DungeonJourney(data, player, completed, log, pool, prefs, mapName, instanceName, instance, quests)
		end, nil, pool)
	end
	-- A way into an instance (roadmap #21): the chain the player can take up that goes inside, when stranded or chosen,
	-- and not the one the story already leads with.
	local chosenHead = tonumber(chosen:match("^chain:(%d+)$"))
	local chain, leadID, continues
	if stranded or chosenHead then
		chain, leadID, continues = Lead(data, completed, pool, function(_, id)
			local story = Model.Story(data, id)
			if not story then
				return false
			end
			local head = story.members[1]
			return (chosenHead == nil or head == chosenHead)
				and not dismissed["chain:" .. head]
				and not (told and told.story and told.story.members[1] == head)
				and Into(data, story) ~= nil
		end)
	end
	if chain and leadID then
		local way, members = chain, {}
		for _, id in ipairs(way.members) do
			members[data.quests[id]] = true
		end
		local function Member(quest)
			return members[quest] == true
		end
		local key = "chain:" .. way.members[1]
		Offer("chain", key, Member, function()
			local into, _, step = Pickups(
				data,
				player,
				completed,
				log,
				ready,
				pool,
				Member,
				key,
				prefs,
				mapName,
				leadID,
				nil,
				key == chosen
			)
			if into then
				return WayIn(data, into, way, step, continues, instanceName)
			end
		end, nil, pool)
	end
	diversions[#diversions + 1] = prefs.battlegrounds and Battleground(data, player, prefs, mapName) or nil
	table.sort(diversions, function(a, b)
		if a.opened ~= b.opened then
			return a.opened > b.opened
		end
		return DIVERSION_ORDER[a.kind] < DIVERSION_ORDER[b.kind]
	end)
	for _, diversion in ipairs(diversions) do
		if #journeys < Model.MAX_JOURNEYS or diversion.key == prefs.journey then
			journeys[#journeys + 1] = diversion.build(diversion.quests)
		end
	end
	Cap(journeys, prefs.journey)
	for _, journey in ipairs(journeys) do
		Summarise(journey --[[@as AGFJourney]])
		Rest(data, player, journey.steps)
	end
	if journeys[1] then
		journeys[1].drop = Droppable(data, player, log)
	end
	return journeys, stranded
end

-- The route is the chosen journey's steps. With none chosen (never, cleared, or the choice is gone) it is the first
-- journey's, so the tracker still has a next step, and `chosen` says the player picked nothing: the guide then shows
-- every card whole and no steps (docs/design.md §2.1).
local function Route(journeys, prefs)
	local chosen
	for _, journey in ipairs(journeys) do
		chosen = journey.key == prefs.journey and journey or chosen
	end
	local route = chosen or journeys[1]
	return {
		journeys = journeys,
		journey = route and route.key,
		chosen = chosen ~= nil,
		steps = route and route.steps or {},
	}
end

---@param mapName? fun(map: integer): string? the client's (localised) name for a map; the data's English otherwise
---@param instanceName? fun(id: integer): string? the client's name for an instance Map.ID; the data's otherwise
---@param last? AGFRoute the route before, whose committed orders (`orders`) this one keeps to
function Model.Plan(data, player, completed, log, prefs, mapName, instanceName, last)
	skippedSeen, committedOrders, planDocks = {}, {}, { data = data }
	for key, order in pairs(last and last.orders or NONE) do
		committedOrders[key] = order
	end
	local journeys, stranded = Model.Journeys(data, player, completed, log, prefs, mapName, instanceName)
	local route = Route(journeys, prefs)
	route.skipped, skippedSeen, route.stranded = skippedSeen, nil, stranded or nil
	route.orders, committedOrders, planDocks = committedOrders, nil, nil
	return route
end

local function Copy(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

-- A journey from the last full build less what went since: every step on it is a town, and a quest the player has
-- taken, done or ruled out (a group choice), or handed in, leaves its town, which goes only once it is empty or
-- skipped; the full build after combat brings back anything else. The same table when nothing went.
---@param journey AGFJourney
---@param prune fun(step: AGFStep): AGFStep? the step, a copy less the quests gone, or nil when none is left
---@return AGFJourney?
local function Retained(journey, prune)
	local steps, changed, chapterGone = {}, false, false
	local chapterID = journey.story and journey.story.members[journey.story.chapter]
	for _, step in ipairs(journey.steps) do
		local kept = prune(step)
		changed = changed or kept ~= step
		local chapterKept = false
		for _, id in ipairs(kept and kept.quests or NONE) do
			chapterKept = chapterKept or id == chapterID
		end
		if step.chapter and not chapterKept then
			chapterGone = true
			if kept then
				kept.chapter = nil -- a copy: its chapter's quest went
			end
		elseif kept and kept ~= step and step.chapter then
			-- The chapter stays: its town keeps the story's reason, as the full build gives it.
			kept.reason, kept.detail = step.reason, #kept.quests == 1 and step.reason or kept.detail
		end
		steps[#steps + 1] = kept
	end
	if not changed or #steps == 0 then
		return #steps > 0 and journey or nil
	end
	local copy = Copy(journey)
	copy.steps, copy.map = steps, steps[1].map
	-- A chapter that went takes the card's chain with it, as the full build does.
	if chapterGone then
		copy.story, copy.reason, copy.subline = nil, nil, journey.count
	end
	Summarise(copy --[[@as AGFJourney]])
	return copy --[[@as AGFJourney]]
end

-- The in-combat rebuild (Core.lua): the carry journey fresh from the live log, which is what changes in a fight, after
-- the story as the full build orders them, and every other journey as the last full build left it, less any step
-- skipped or no longer open since. Only the retained steps' quests are checked again: no eligibility pass over the
-- data and no 2-opt, so it stays cheap; the full build runs once combat ends.
---@param last AGFRoute
function Model.Refresh(data, player, completed, log, prefs, last, mapName)
	ReadDropped(prefs)
	local skipped, groups = prefs.skipped or {}, Index(data).groups
	local function Keep(ids, open)
		local kept = {}
		for _, id in ipairs(ids) do
			kept[#kept + 1] = open(id) and id or nil
		end
		return kept
	end
	local function Open(id)
		return Eligible(data, player, completed, log, id, groups)
	end
	local function Carried(id)
		return log[id] ~= nil and log[id].complete
	end
	local function Prune(step)
		if skipped[step.key] then
			return nil
		elseif step.kind == "trainer" or step.kind == "battlemaster" then
			return step -- nothing is learned, and no battleground opens, in a fight
		end
		if not step.pickups then
			-- A log step: its quests still carried, less an objective finished in the fight, which carry hands in, and
			-- a lap's quests not yet picked up while they are still open. Objectives ticked short of that wait for the
			-- full build.
			local function Carrying(id)
				if log[id] == nil then
					return step.planned ~= nil and step.planned[id] ~= nil and Open(id)
				end
				return not (step.objectives and log[id].complete)
			end
			local quests = Keep(step.quests, Carrying)
			if #quests == #step.quests then
				return step
			elseif #quests == 0 then
				return nil
			end
			local copy = Copy(step) --[[@as AGFStep]]
			copy.quests = quests
			if step.objectives then
				copy.objectives = {}
				for _, objective in ipairs(step.objectives) do
					copy.objectives[#copy.objectives + 1] = Carrying(objective.id) and objective or nil
				end
				Tell(copy)
			end
			return copy
		end
		-- A lap's return hands in what it picks up or carries once done: kept while carried, or while still open.
		local function Due(id)
			return Carried(id) or (step.returns ~= nil and step.returns[id] ~= nil and (log[id] ~= nil or Open(id)))
		end
		local pickups, handins = Keep(step.pickups, Open), Keep(step.handins, Due)
		if #pickups + #handins == #step.quests then
			return step
		elseif #pickups + #handins == 0 then
			return nil
		end
		local copy = Copy(step) --[[@as AGFStep]]
		copy.pickups, copy.handins = pickups, handins
		Describe(data, log, player, copy)
		Opens(data, player, completed, log, copy)
		-- A point whose giver has nothing left moves to the first quest's place.
		local here = false
		for _, id in ipairs(copy.quests) do
			local spot = copy.spots[id]
			here = here or (spot.map == copy.map and spot.x == copy.x and spot.y == copy.y)
		end
		if not here then
			local spot = copy.spots[copy.quests[1]]
			copy.map, copy.x, copy.y = spot.map, spot.x, spot.y
			Locate(data, copy, mapName)
		end
		return copy
	end
	-- The story's log quests stay on it; one taken on its zone since, or finished for a lap the story doesn't draw yet,
	-- joins carry until the full build.
	local journeys, dismissed, zone, told, drawn = {}, prefs.notInterested or {}, nil, {}, {}
	for _, journey in ipairs(last.journeys) do
		local kept = journey.kind ~= "carry" and not dismissed[journey.key] and Retained(journey, Prune) or nil
		if kept and kept.kind == "story" then
			zone = tonumber(kept.key:match("^zone:(%d+)$"))
			told = kept.holds or told
			for _, step in ipairs(kept.steps) do
				for _, id in ipairs(step.handins or (step.kind ~= "trainer" and step.quests) or NONE) do
					drawn[id] = true
				end
			end
		end
		journeys[#journeys + 1] = kept
	end
	local story = InZone(zone)
	local added = Added(data, player, completed, log, prefs, function(quest)
		return not story(quest)
	end)
	local carry = Carry(data, player, completed, log, Ready(data, log), prefs, mapName, true, function(id)
		return not told[id] or (log[id].complete and not drawn[id])
	end, added)
	if carry then
		table.insert(journeys, (journeys[1] and journeys[1].kind == "story") and 2 or 1, carry)
	end
	-- A carry card the last build lacked pushes out the last card not chosen, as the full build would leave it out.
	Cap(journeys, prefs.journey)
	local route = Route(journeys, prefs)
	route.stranded, route.orders = last.stranded, last.orders
	return route
end

-- Honest coverage (docs/design.md §2.1): the log holds a quest the data lacks, or Forever added quests on this zone map
-- (Data/Forever.lua) that the data lacks and the player hasn't finished. Either way the cards can't be every story
-- here, and the panel says so.
---@param data AGFData
---@param map? integer the player's zone map
---@param completed table<integer, boolean>
---@param log table<integer, AGFLogQuest>
---@return boolean
function Model.Unlisted(data, map, completed, log)
	for id in pairs(log) do
		if not data.quests[id] then
			return true
		end
	end
	local added = map and data.forever and data.forever.quests[map] or {}
	for _, id in ipairs(added) do
		if not data.quests[id] and not completed[id] then
			return true
		end
	end
	return false
end
