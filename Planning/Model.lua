---@type string, AGFNamespace
local _, ns = ...
---@class AGFModel
-- Ten upcoming route actions; the UI scrolls and the plan rebuilds as quests progress.
local Model = { MAX_STEPS = 10 }
ns.Model = Model
---@class AGFPlanner
local Planner = { State = {} }
ns.Planner = Planner
local State = Planner.State

-- CMaNGOS mangos-classic/src/game/Tools/Formulas.h, GetQuestGreenRange (quest, not creature XP).
local GREEN_RANGE = { 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12 }
local ORANGE = 3 -- levels above the player: the stock orange, where a quest gets hard alone
local NONE = {} -- an empty list for the hot loops to walk without allocating one; never written

function Model.IsGray(questLevel, playerLevel)
	local range = GREEN_RANGE[math.min(#GREEN_RANGE, math.floor(playerLevel / 5) + 1)] or 4
	return questLevel > 0 and playerLevel - questLevel > range
end

-- The planner's level preference, shared by the zone ranking and a step's quest order (docs/design.md §2.2): lower is
-- taken first. At the player's level and one or two below is free, each level above costs twice its distance, and each
-- level further below costs one, so deep green content ranks behind content near the player's level.
---@param questLevel integer
---@param playerLevel integer
---@return integer
function Model.LevelPreference(questLevel, playerLevel)
	local gap = questLevel - playerLevel
	if gap > 0 then
		return 2 * gap
	end
	if gap < -2 then
		return -gap - 2
	end
	return 0
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

Model.ValidPlace = ValidPlace

local function HasBit(mask, bit)
	return not mask or mask == 0 or (bit > 0 and math.floor(mask / bit) % 2 == 1)
end

Model.HasBit = HasBit

-- A zone map's art in pixels (tools/gen_quests.py CANVAS): overlay rectangles and their centres are on this canvas,
-- so which of two overlaps is nearer is measured across and down, as the client's own shading does.
local CANVAS_W, CANVAS_H = 1002, 668

-- A town is the named area of its map a place stands in (Data/Geometry `towns`, the world map's overlays): among
-- the areas whose rectangle holds the point, the one whose centre is nearest wins, as the client's own shading does.
-- A place in no area (a city map, an instance, a gap between rectangles) is its map's own town. Nil on a map the
-- data doesn't place.
---@param data AGFData
---@param place {map: integer, x: number, y: number}
---@return string?
function Model.Hub(data, place)
	if not (data.maps and data.maps[place.map]) then
		return nil
	end
	local best, bestNear
	for _, area in ipairs((data.towns and data.towns[place.map]) or NONE) do
		if place.x >= area.x0 and place.x <= area.x1 and place.y >= area.y0 and place.y <= area.y1 then
			local dx, dy = (place.x - area.cx) * CANVAS_W, (place.y - area.cy) * CANVAS_H
			local near = dx * dx + dy * dy
			if not best or near < bestNear then
				best, bestNear = area, near
			end
		end
	end
	return place.map .. ":" .. (best and best.area or 0)
end

function Model.Handins(step)
	return step.handins or (step.kind == "turnin" and step.quests) or NONE
end

-- Only published quest data is memoized; player/log/completion tables may change in place.
---@type table<AGFData, AGFIndex>
local indexes = setmetatable({}, { __mode = "k" })

local function Index(data)
	local index = indexes[data]
	if index then
		return index
	end
	index = {
		ids = {},
		dungeons = {},
		dungeonsByLevel = {},
		choicesByLevel = { {}, {} },
		groups = {},
		sides = { {}, {} },
		starts = {},
	}
	for id in pairs(data.quests) do
		index.ids[#index.ids + 1] = id
	end
	table.sort(index.ids)
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		if quest.dungeon then
			index.dungeons[#index.dungeons + 1] = id
		end
		if quest.start and quest.start.map then
			local mapID = quest.start.map
			index.starts[mapID] = index.starts[mapID] or {}
			table.insert(index.starts[mapID], id)
		end
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

-- Stories (docs/design.md §2.3): the chain a quest belongs to, from the data's `next` links.
-- `prev[id]` is the one quest whose `next` is id, or false when several lead into it. Memoized like Index.
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
		if math.floor(bits / bit) % 2 == 1 and not HasBit(mask, bit) then
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
-- class) is left out.
local function Check(data, player, completed, log, id, groups, lines, names)
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
	met = player.level >= quest.min
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
	if quest.provider then
		local available = (not quest.max or quest.max == 0 or player.level <= quest.max)
				and player.questAvailable
				and player.questAvailable(id)
			or false
		return Line(data, lines, available, "WHY_PROVIDER")
	end
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

local Eligible = Check

-- A quest with no requirement beyond completion, the log and the side/level/grey/start/race/class filters is open
-- without rewalking the full requirement checker on every rebuild.
local function SimpleOpen(quest, player, completed, log, id)
	return not completed[id]
		and not log[id]
		and (quest.side == 3 or quest.side == player.side)
		and quest.min <= player.level
		and not Model.IsGray(quest.level, player.level)
		and ValidPlace(quest.start)
		and HasBit(quest.races, player.raceBit)
		and HasBit(quest.classes, player.classBit)
		and not quest.repeatable
		and not quest.provider
		and not quest.skill
		and not quest.rep
		and not quest.pre
		and not quest.preAny
		and not quest.group
		and not quest.breadcrumb
end

function Model.Eligible(data, player, completed, log, questID)
	return Eligible(data, player, completed, log, questID, Index(data).groups)
end

-- Why a quest is or isn't open to the player: each requirement the data carries, met or not (docs/design.md §2.4).
---@param names? AGFWhyNames the client's names for quests, races and classes
---@return AGFWhyLine[]
function Model.Why(data, player, completed, log, questID, names)
	local lines = {}
	Check(data, player, completed, log, questID, Index(data).groups, lines, names)
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
---@param skippedQuests? table<string, integer[]> the build's AGFPlanInputs.skippedQuests
local function ReadDropped(prefs, skippedQuests)
	droppedIDs = {}
	for key, ids in pairs(skippedQuests or NONE) do
		if State.skippedSeen then
			State.skippedSeen[key] = true
		end
		for _, id in ipairs(ids) do
			droppedIDs[id] = true
		end
	end
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

-- Pickup recommendations respect the chosen level ceiling; accepted quests keep their log steps.
---@param quest AGFQuest
---@param player AGFPlayer
function Model.Hard(quest, player)
	local level = quest.level > 0 and quest.level or player.level
	return level - player.level > (player.maxQuestLevelOffset or (ORANGE - 1))
end
local Hard = Model.Hard

-- Every quest giver on `mapID` with a quest the player can take now, one entry per NPC or object, like the
-- game's own "!". Gray quests stay hidden, as the game hides them unless low-level tracking is on. An orange or red
-- quest shows but is not among the giver's `adds`, since no route takes it.
---@return AGFGiver[]
function Model.Givers(data, player, completed, log, mapID)
	local index, byPlace, givers = Index(data), {}, {}
	for _, id in ipairs(index.starts[mapID] or NONE) do
		local quest = data.quests[id]
		local start = quest.start
		if
			start
			and not Model.IsGray(quest.level, player.level)
			and Eligible(data, player, completed, log, id, index.groups)
		then
			local key = string.format("%s:%.4f:%.4f", start.name, start.x, start.y)
			local giver = byPlace[key]
			if not giver then
				giver = { map = mapID, x = start.x, y = start.y, title = start.name, quests = {}, adds = {} }
				byPlace[key] = giver
				givers[#givers + 1] = giver
			end
			giver.quests[#giver.quests + 1] = id
			giver.adds[#giver.adds + 1] = not Hard(quest, player) and id or nil
		end
	end
	return givers
end

-- Honest coverage: the log holds a quest the data lacks, or Forever added quests on this zone map
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

ns.Planner.Eligibility = {
	Dropped = Dropped,
	Eligible = Eligible,
	Index = Index,
	ORANGE = ORANGE,
	ReadDropped = ReadDropped,
	SimpleOpen = SimpleOpen,
}
