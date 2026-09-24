---@type string, AGFNamespace
local _, ns = ...
---@class AGFModel
-- Nine steps: the stock numerals (services-number-1..9) that label each step stop at 9. Three journeys: design §2.2,
-- and the panel builds as many cards.
local Model = { MAX_STEPS = 9, MAX_JOURNEYS = 3 }
ns.Model = Model

-- CMaNGOS mangos-classic/src/game/Tools/Formulas.h, GetQuestGreenRange (quest, not creature XP).
local GREEN_RANGE = { 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12 }
local CLOSE = 0.03 * 0.03
-- What a stop is worth against the yards to reach it (docs/plan.md §7.3): each quest there (at most 8), a quest that
-- goes grey at the next level, each hand-in, and a stop with no hand-in where every quest is red or optional, which
-- waits.
local VALUE_QUEST, VALUE_QUESTS_MAX, VALUE_GREY_RISK, VALUE_HAND_IN, VALUE_WEAK = 40, 8, 150, 60, -300
local RED = 5 -- levels above the player: the stock red

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
---@type table<AGFData, AGFIndex>
local indexes = setmetatable({}, { __mode = "k" })

local function Index(data)
	local index = indexes[data]
	if index then
		return index
	end
	index = { ids = {}, groups = {} }
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
		proven = proven and not quest.preAny and #(quest.pre or {}) <= 1
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
	for _, pre in ipairs(quest.pre or {}) do
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
	for _, other in ipairs((quest.group and groups[quest.group]) or {}) do
		if other ~= id and (completed[other] or log[other]) and not Line(data, lines, false, "group", other, names) then
			return false
		end
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

-- The maps of the three zones that best fit `level` for the quests `ids`, best first. An outdoor elite is optional
-- (roadmap #16): it rides along on its zone's cards but never picks the zone a solo player is sent to.
---@return integer[]
local function Rank(data, ids, level)
	local choices, scores = {}, {}
	for _, id in ipairs(ids) do
		local quest = data.quests[id]
		local map = quest.zone or quest.start.map
		local zone = data.zones[map]
		if zone and not Model.IsGray(quest.level, level) and not (quest.elite and not quest.dungeon) then
			if not choices[map] then
				choices[map] = { map = map, min = zone.min, max = zone.max, quests = 0 }
				scores[map] = 0
			end
			choices[map].quests = choices[map].quests + 1
			local questLevel = quest.level == -1 and level or quest.level
			-- Fit dominates; a bounded density bonus below favors enough quests for a short route.
			scores[map] = scores[map] + math.abs(questLevel - level) + math.max(0, questLevel - level - 2)
		end
	end
	local zones = {}
	for map, choice in pairs(choices) do
		scores[map] = scores[map] / choice.quests
			+ math.max(0, choice.min - level, level - choice.max) * 2
			- math.min(choice.quests, 12) * 0.5
		zones[#zones + 1] = choice
	end
	table.sort(zones, function(a, b)
		if scores[a.map] ~= scores[b.map] then
			return scores[a.map] < scores[b.map]
		end
		if a.quests ~= b.quests then
			return a.quests > b.quests
		end
		return a.map < b.map
	end)
	local maps = {}
	for index = 1, math.min(#zones, 3) do
		maps[index] = zones[index].map
	end
	return maps
end

-- One eligibility pass for two levels: the player's, and `ahead` levels on for the next-zone card. A level reaches
-- eligibility only through a quest's minimum, so what opens at level + ahead holds everything open now. Only an
-- instance's quests wait behind Dungeons: an outdoor elite is a zone's quest, optional and badged for a group.
local function Choices(data, player, completed, log, index, prefs, ahead)
	local eligible, later, target = {}, {}, player.level + (ahead or 0)
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		local instance = quest.dungeon ~= nil
		if
			((instance and prefs.dungeons) or (not instance and prefs.quests))
			and Eligible(data, player, completed, log, id, index.groups, target)
		then
			later[#later + 1] = id
			if quest.min <= player.level and not Model.IsGray(quest.level, player.level) then
				eligible[#eligible + 1] = id
			end
		end
	end
	return Rank(data, eligible, player.level), eligible, ahead and Rank(data, later, target)
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

-- The stop for `place`'s town among `stops` (by key), made and added to `steps` when the town has none yet. Its point
-- is the first quest's place until Build moves it to the giver nearest the route. `prefix` keeps the carry card's
-- towns ("handin:") apart from the other cards' ("hub:"), so a skip on one card never empties a town on another.
---@param place AGFPlace
---@param prefix string
---@return AGFStep
local function HubStop(stops, steps, place, prefix)
	local key = prefix .. Hub(place)
	local stop = stops[key]
	if not stop then
		stop = {
			kind = "hub",
			key = key,
			hub = place.hub,
			title = "",
			detail = "",
			reason = "",
			quests = {},
			pickups = {},
			handins = {},
			givers = {},
			group = 0,
			spots = {},
			map = place.map,
			x = place.x,
			y = place.y,
		}
		stops[key] = stop
		steps[#steps + 1] = stop
	end
	return stop
end

-- Adds quest `id`, which `place` starts or finishes, to a stop's `list` (its pickups or hand-ins).
local function Join(stop, list, id, place)
	list[#list + 1] = id
	stop.quests[#stop.quests + 1] = id
	stop.spots[id] = place
end

-- A hub stop's quests, givers, group count, title and detail, from its pickups and hand-ins; it is optional only when
-- every quest there is. The quests go hand-ins
-- first, then those grey at the next level, then nearest the player's level, then by ID (docs/plan.md §7.3); the givers
-- and the quest ShowQuest opens follow that order. One quest keeps the single step's title; several take the town's
-- name, else their busiest giver's.
---@param step AGFStep
---@param log table<integer, AGFLogQuest>
local function Describe(data, log, player, step)
	local L = ns.L
	local handin, risk, distance, optional = {}, {}, {}, true
	for _, list in ipairs({ step.handins, step.pickups }) do
		for _, id in ipairs(list) do
			local level = QuestLevel(data, log, player, id)
			handin[id], risk[id], distance[id] =
				list == step.handins, GreyRisk(level, player), math.abs(level - player.level)
			optional = optional and Optional(data.quests[id], level, player)
		end
	end
	step.optional = optional or nil
	local function Before(a, b)
		if handin[a] ~= handin[b] then
			return handin[a]
		elseif risk[a] ~= risk[b] then
			return risk[a]
		elseif distance[a] ~= distance[b] then
			return distance[a] < distance[b]
		end
		return a < b
	end
	table.sort(step.handins, Before)
	table.sort(step.pickups, Before)
	local quests, givers, counts, group = {}, {}, {}, 0
	for _, list in ipairs({ step.handins, step.pickups }) do
		for _, id in ipairs(list) do
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
			step.reason = L.READY_TO_HAND_IN
		else
			step.title = L.PICK_UP:format(step.spots[id].name)
			step.reason = (quest.pre or quest.preAny) and L.CONTINUES_STORY or L.NEAR_YOUR_LEVEL
		end
	else
		step.title = step.place
		local parts = {}
		parts[#parts + 1] = #step.handins > 0 and L.HUB_HAND_IN:format(#step.handins) or nil
		parts[#parts + 1] = #step.pickups > 0 and L.HUB_PICK_UP:format(#step.pickups) or nil
		step.reason = table.concat(parts, L.LIST_SEPARATOR)
	end
	step.detail = step.reason
end

-- A town where a hand-in opens the next chapter of its chain says so, when the data proves that chapter starts in the
-- same town and Check proves it shut now and open once the hand-in is done (the data's `next` alone is display-only).
-- It is never added as a pickup before the turn-in: it comes with the rebuild after QUEST_TURNED_IN. Nothing is said
-- when the data cannot prove it.
---@param step AGFStep
local function Opens(data, player, completed, log, step)
	local groups = Index(data).groups
	for _, id in ipairs(step.hub and step.handins or {}) do
		local nextID = data.quests[id] and data.quests[id].next
		local follow = nextID and data.quests[nextID]
		local after = setmetatable({ [id] = true }, { __index = completed })
		if
			follow
			and follow.start
			and follow.start.hub == step.hub
			and not Eligible(data, player, completed, log, nextID, groups)
			and Eligible(data, player, after, log, nextID, groups)
		then
			step.reason = ns.L.OPENS_CHAPTER_HERE
			step.detail = #step.quests == 1 and step.reason or step.detail
			return
		end
	end
end

-- The quest and dungeon prefs choose what to pick up; a quest already carried always shows, whatever its kind.
-- A finished quest in `ready` (the data and the client agree where it is handed in) joins its town's stop; any other
-- finished quest is a turn-in at the client's waypoint.
---@param ready table<integer, AGFPlace>
local function LogSteps(data, player, log, ready)
	local ids, steps, objectives, stops = {}, {}, {}, {}
	for id in pairs(log) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local entry, quest = log[id], data.quests[id]
		local group = quest and (quest.elite or quest.dungeon)
		-- A live completion waypoint is a turn-in; an incomplete waypoint is never replaced with the starter.
		local place = ValidPlace(entry) and entry or (entry.complete and quest and quest.finish)
		local optional = Optional(quest, entry.level, player)
		if ready[id] then
			local stop = HubStop(stops, steps, ready[id], "handin:")
			Join(stop, stop.handins, id, ready[id])
		elseif ValidPlace(place) then
			if entry.complete then
				steps[#steps + 1] = Step(
					"turnin",
					"turnin:" .. id,
					ns.L.TURN_IN:format(entry.title),
					place,
					id,
					optional,
					ns.L.READY_TO_HAND_IN
				)
			else
				local kind = group and "dungeon" or "objective"
				local existing
				for _, step in ipairs(objectives) do
					if step.kind == kind and Distance(step, place) <= CLOSE then
						existing = step
						break
					end
				end
				if existing then
					existing.quests[#existing.quests + 1] = id
					existing.optional = existing.optional and optional or nil
					existing.reason = ns.L.QUESTS_HERE:format(#existing.quests)
					existing.detail = existing.reason
				else
					local step =
						Step(kind, "objective:" .. id, entry.title, place, id, optional, ns.L.QUESTS_IN_PROGRESS)
					objectives[#objectives + 1] = step
					steps[#steps + 1] = step
				end
			end
		end
	end
	return steps
end

-- One stop per town of the eligible quests `wanted` accepts; a group quest joins its town's stop like any other.
---@param wanted fun(quest: AGFQuest): boolean
local function PickupSteps(data, eligible, wanted, steps)
	local stops, chosenGroups = {}, {}
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		if wanted(quest) and not (quest.group and chosenGroups[quest.group]) then
			if quest.group then
				chosenGroups[quest.group] = true
			end
			local stop = HubStop(stops, steps, quest.start, "hub:")
			Join(stop, stop.pickups, id, quest.start)
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

---@return AGFPosition?
local function Position(data, place, docks)
	if not ValidPlace(place) then
		return nil
	end
	local map = data.maps and data.maps[place.map]
	local shift = map and data.continents and data.continents[map.continent]
	if not shift then
		return { x = place.x, y = place.y, continent = "map " .. place.map, known = false }
	end
	return {
		x = shift.x - map.cy + (place.x - 0.5) * map.sx,
		y = shift.y - map.cx + (place.y - 0.5) * map.sy,
		continent = map.continent,
		known = true,
		docks = docks,
	}
end

-- Both directions of every crossing `side` may take whose continents the data places on the Azeroth map.
---@return AGFFrameCrossing[]
local function Docks(data, side)
	local docks = {}
	local function Frame(dock)
		local shift = data.continents and data.continents[dock.continent]
		return shift and { x = shift.x - dock.y, y = shift.y - dock.x }
	end
	for _, crossing in ipairs(data.crossings or {}) do
		local a, b = Frame(crossing.a), Frame(crossing.b)
		if a and b and HasBit(crossing.side, side) then
			docks[#docks + 1] = { from = crossing.a.continent, to = crossing.b.continent, leave = a, land = b }
			docks[#docks + 1] = { from = crossing.b.continent, to = crossing.a.continent, leave = b, land = a }
		end
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
	local here, there = Position(data, a), Position(data, b)
	if here and there and here.known and there.known and here.continent == there.continent then
		return Yards(here, there)
	end
end

local AGREE = 100 -- yards: the town linkage (tools/gen_quests.py LINK); a waypoint this near the data's finish is it

-- The finished log quests whose hand-in the data and the client agree on: the client's waypoint is on a map the data
-- places and lies within AGREE of the data's finish, which is in a town. Each maps to that finish.
---@return table<integer, AGFPlace>
local function Ready(data, log)
	local ready = {}
	for id, entry in pairs(log) do
		local quest = data.quests[id]
		local finish = entry.complete and quest and quest.finish
		if finish and finish.hub then
			local live, there = Position(data, entry), Position(data, finish)
			if live and there and live.known and there.known and live.continent == there.continent then
				ready[id] = Yards(live, there) <= AGREE and finish or nil
			end
		end
	end
	return ready
end

-- Where a step is, for its "NPC, zone" line: the zone is the client's name for its map, the data's otherwise. A turn-in
-- names the data's finish NPC only while its point is within AGREE of that finish; a town named itself in Describe.
---@param step AGFStep
---@param mapName? fun(map: integer): string?
local function Locate(data, step, mapName)
	step.zone = (mapName and mapName(step.map)) or (data.maps and data.maps[step.map] and data.maps[step.map].name)
	if step.kind == "turnin" then
		local quest = data.quests[step.quests[1]]
		local finish = quest and quest.finish
		local here, there = Position(data, step), finish and Position(data, finish)
		local agree = here
			and there
			and here.known
			and there.known
			and here.continent == there.continent
			and Yards(here, there) <= AGREE
		step.place = agree and finish.name or nil
	end
end

-- A stop the player only hands in at: a turn-in, or a town with hand-ins and nothing to pick up.
---@param step AGFStep
local function HandInOnly(step)
	return step.kind == "turnin" or (step.kind == "hub" and #step.pickups == 0)
end

---@param a AGFPosition?
---@param b AGFPosition?
local function Cost(a, b)
	if not (a and b) or (a.continent ~= b.continent and not (a.known and b.known)) then
		return UNKNOWN
	end
	if a.continent == b.continent then
		return Yards(a, b)
	end
	local best
	for _, dock in ipairs(a.docks or {}) do
		if dock.from == a.continent and dock.to == b.continent then
			local via = Yards(a, dock.leave) + Yards(dock.land, b)
			best = (best and best < via) and best or via
		end
	end
	-- No boat for this side between them: the straight line across the sea, as before the docks were known.
	return CROSSING + (best or Yards(a, b))
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

-- A step's worth in yards (VALUE_* above), so selection weighs it against the reach. Only a step placed in yards has
-- one: a map the data cannot place is measured in map units, where yards mean nothing.
---@param step AGFStep
local function Value(data, log, player, step)
	-- A finished quest waits for nothing, so a stop with a hand-in is never weak.
	local handins = step.handins and #step.handins or (step.kind == "turnin" and 1 or 0)
	local risk, weak = false, handins == 0
	for _, id in ipairs(step.quests) do
		local level = QuestLevel(data, log, player, id)
		risk = risk or GreyRisk(level, player)
		weak = weak and (level - player.level >= RED or Optional(data.quests[id], level, player))
	end
	return VALUE_QUEST * math.min(#step.quests, VALUE_QUESTS_MAX)
		+ (risk and VALUE_GREY_RISK or 0)
		+ VALUE_HAND_IN * handins
		+ (weak and VALUE_WEAK or 0)
end

-- The skipped keys a full build still found among its candidates (Model.Plan); nil outside one.
---@type table<string, boolean>?
local skippedSeen

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
	for _, step in ipairs(pool) do
		local cost = Cost(origin, where[step])
		reach[step] = (not measured and cost >= UNKNOWN and HandInOnly(step)) and 0 or cost
		value[step] = (where[step] and where[step].known) and Value(data, log, player, step) or 0
	end
	local function Take(step)
		chosen[step] = true
		selected[#selected + 1] = step
		for _, other in ipairs(pool) do
			if not chosen[other] then
				reach[other] = math.min(reach[other], Cost(where[step], where[other]))
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
			if not chosen[step] and (not best or key < bestKey or (key == bestKey and step.key < best.key)) then
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
		if step.kind == "hub" then
			Describe(data, log, player, step)
			Opens(data, player, completed, log, step)
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
				local cost = Cost(from, Position(data, step.spots[id], docks))
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

-- The journey cards (docs/design.md §2.2): at most three, each holding only steps the player can take now.
local NEXT_ZONE_AHEAD = 2 -- levels: the next zone is the one that fits the player two levels on
local NEXT_ZONE_PICKUPS = 5 -- eligible quests there, or the card is too thin to offer (docs/plan.md §1.5)

local function Count(one, many, count)
	return count == 1 and one or many:format(count)
end

local function ZoneName(data, map, mapName)
	return (mapName and mapName(map)) or data.zones[map].name
end

-- "Finish what you carry": the log's turn-ins and objectives. `carried` is every log step, so the subline counts
-- what the player carries, not only the steps that made the route.
---@param ready table<integer, AGFPlace>
local function Carry(data, player, completed, log, ready, prefs, mapName, cheap)
	local carried = LogSteps(data, player, log, ready)
	local steps = Build(data, player, completed, log, carried, prefs, mapName, cheap)
	if #steps == 0 then
		return nil
	end
	-- A finished quest whose hand-in is across an ocean is not ready yet: the reason line counts those, so no fact
	-- is told twice on the card.
	local L, finished, underway, away, here = ns.L, 0, 0, 0, Position(data, player)
	for _, step in ipairs(carried) do
		if not prefs.skipped[step.key] then
			local there, done =
				Position(data, step), step.handins and #step.handins or (step.kind == "turnin" and 1 or 0)
			underway = underway + #step.quests - done
			if here and there and here.known and there.known and here.continent ~= there.continent then
				away = away + done
			else
				finished = finished + done
			end
		end
	end
	local parts = {}
	parts[#parts + 1] = finished > 0 and L.CARRY_READY:format(finished) or nil
	parts[#parts + 1] = underway > 0 and L.CARRY_IN_PROGRESS:format(underway) or nil
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
			towns[step.key] = step.kind == "hub" and step or nil
		end
		for id in pairs(ready) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local town = towns["hub:" .. Hub(ready[id])]
			if town then
				Join(town, town.handins, id, ready[id])
			end
		end
	end
end

-- A zone's pickups as one journey (kind, key and title are the caller's), and how many eligible quests it holds.
-- The step that offers `leadID` is always among them; the hand-ins in `ready` join the towns it holds.
---@param ready table<integer, AGFPlace>
local function ZoneJourney(data, player, completed, log, ready, eligible, zone, prefs, mapName, leadID)
	local candidates, quests, lead = {}, 0, nil
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		quests = quests + ((quest.zone or quest.start.map) == zone and 1 or 0)
	end
	PickupSteps(data, eligible, function(quest)
		return (quest.zone or quest.start.map) == zone
	end, candidates)
	for _, step in ipairs(candidates) do
		for _, id in ipairs(step.quests) do
			lead = id == leadID and step or lead
		end
	end
	local steps = Build(data, player, completed, log, candidates, prefs, mapName, false, lead, HandIns(ready))
	if #steps == 0 then
		return nil, quests
	end
	-- The lead only when Build kept it: a skipped chapter leaves the card to the zone's count.
	local kept
	for _, step in ipairs(steps) do
		kept = kept or step == lead
	end
	local subline = Count(ns.L.QUESTS_NEAR_ONE, ns.L.QUESTS_NEAR, quests)
	return { map = steps[1].map, steps = steps, subline = subline, count = subline }, quests, kept and lead or nil
end

-- The dungeon card (F15): with dungeons on, the party instance with the most quests the player can take now (the
-- lowest Map.ID on a tie), its steps the givers of those quests; the `chosen` instance instead while it has any, so a
-- choice never moves to another dungeon. Raids are never offered. Named by the client, in the player's language, and
-- by the data otherwise; an instance the data doesn't name gets no card.
---@param instanceName? fun(id: integer): string?
---@param chosen? integer
local function DungeonJourney(data, player, completed, log, eligible, prefs, mapName, instanceName, chosen)
	if not (prefs.dungeons and data.instances) then
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
	best = chosen and counts[chosen] and chosen or best
	if not best then
		return nil
	end
	local candidates = {}
	PickupSteps(data, eligible, function(quest)
		return quest.dungeon == best and not quest.raid
	end, candidates)
	local steps = Build(data, player, completed, log, candidates, prefs, mapName)
	if #steps == 0 then
		return nil
	end
	local name = instanceName and instanceName(best) or data.instances[best].name
	local subline = Count(ns.L.DUNGEON_QUESTS_ONE, ns.L.DUNGEON_QUESTS, counts[best])
	return {
		kind = "dungeon",
		key = "dungeon:" .. best,
		title = name,
		subline = subline,
		map = steps[1].map,
		steps = steps,
	}
end

-- The zone's story (docs/design.md §2.3): of the chains the player can take up in `zone` now, one they have already
-- started before one they would begin, then the longest proven one, then the lowest quest ID. A chapter whose chain
-- was begun elsewhere, with the chapter before it not done, has no honest reason to offer, so it is never the story.
---@return AGFStory?, integer?, boolean? the chain, the quest that takes it up, and whether it continues one
local function ZoneStory(data, completed, eligible, zone)
	local best, bestID, bestRank, continues
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local story = (quest.zone or quest.start.map) == zone and Model.Story(data, id)
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
-- its first stop's town (its flight master's name, before the zone) with HANDS_MIN quests or more to pick up. Nil when
-- none applies; the caller falls back to its plain line. Only names the data has: a chain's giver, a town's flight
-- master.
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
	for _, step in ipairs(player.level < player.maxLevel and journey.steps or {}) do
		for _, id in ipairs(step.pickups or {}) do
			grey = grey + (GreyRisk(QuestLevel(data, log, player, id), player) and 1 or 0)
		end
	end
	if grey >= GREY_REASON_MIN then
		return L.REASON_GREY:format(grey)
	elseif chain and chain.giver then
		return L.REASON_CHAIN_GIVER:format(chain.giver)
	end
	local first = journey.steps[1]
	local town = first and first.hub and data.hubs and data.hubs[first.hub]
	if town and #(first.pickups or {}) >= HANDS_MIN then
		return L.REASON_HANDS:format((town.name:match("^(.-),") or town.name))
	end
end

-- The zone's story card, or nil when `zone` has no step: of a chain when the zone has one the player can take up.
---@param ready table<integer, AGFPlace>
---@return AGFJourney?
local function StoryJourney(data, player, completed, log, ready, eligible, zone, prefs, mapName)
	local L = ns.L
	local chain, chainID, continues = ZoneStory(data, completed, eligible, zone)
	local story, _, lead = ZoneJourney(data, player, completed, log, ready, eligible, zone, prefs, mapName, chainID)
	if not story then
		return nil
	end
	story.kind, story.key = "story", "zone:" .. zone
	story.title = L.JOURNEY_STORY:format(ZoneName(data, zone, mapName))
	---@cast story AGFJourney
	-- With a chain, the card tells its chapter in place of the zone's count, and its step says so on the map.
	if chain and lead then
		local begins = continues and L.CONTINUES_STORY or L.BEGINS_STORY
		local giver = data.quests[chainID].start.name
		story.story = chain
		story.subline = chain.total and L.CHAPTER_OF:format(chain.chapter, chain.total)
			or L.CHAPTER:format(chain.chapter)
		story.reason = WorldReason(data, log, player, story, {
			continues = continues == true,
			giver = giver ~= "" and giver or nil,
		}) or begins
		lead.chapter, lead.reason = story.subline, begins
		-- A lone quest's detail is its reason, so the row never says the chain continues under a card that begins it.
		lead.detail = #lead.quests == 1 and begins or lead.detail
	else
		story.reason = WorldReason(data, log, player, story)
	end
	return story
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

---@param mapName? fun(map: integer): string? the client's (localised) name for a map; the data's English otherwise
---@param instanceName? fun(id: integer): string? the client's name for an instance Map.ID; the data's otherwise
function Model.Journeys(data, player, completed, log, prefs, mapName, instanceName)
	local index, L = Index(data), ns.L
	-- Never past the level cap: a player at it has no next zone to head for.
	local levels = math.min(NEXT_ZONE_AHEAD, player.maxLevel - player.level)
	local zones, eligible, ahead = Choices(data, player, completed, log, index, prefs, levels > 0 and levels or nil)
	local ready = Ready(data, log)
	-- The offer rules below only gate new choices (docs/design.md §2.10): a chosen zone or dungeon is built while it
	-- has a step, whatever would offer it now.
	local chosen = prefs.journey or ""
	local chosenZone, chosenDungeon = tonumber(chosen:match("^zone:(%d+)$")), tonumber(chosen:match("^dungeon:(%d+)$"))
	-- A zone the player is not interested in (roadmap #17) is never a card, chosen or not: the next best takes its place.
	local dismissed = prefs.notInterested or {}
	local function Open(map)
		return map ~= nil and not dismissed["zone:" .. map]
	end
	chosenZone = Open(chosenZone) and chosenZone or nil
	local journeys = { Carry(data, player, completed, log, ready, prefs, mapName) }
	-- The story: the zone the player stands in when it is among the three their level fits now or two levels on (the
	-- next zone's, which is never the zone they are in), or is the chosen zone, so heading to a zone becomes its story
	-- on arrival; otherwise, or when it has no step (a capital), the zone the level fits best.
	local best
	for _, map in ipairs(zones) do
		best = best or (Open(map) and map or nil)
	end
	local zone, tries, here = best, { best }, chosenZone ~= nil and chosenZone == player.map
	for _, map in ipairs(zones) do
		here = here or map == player.map
	end
	for _, map in ipairs(ahead or {}) do
		here = here or map == player.map
	end
	if here and player.map ~= best and Open(player.map) then
		table.insert(tries, 1, player.map)
	end
	for _, map in ipairs(tries) do
		local story = StoryJourney(data, player, completed, log, ready, eligible, map, prefs, mapName)
		if story then
			zone = map
			journeys[#journeys + 1] = story
			break
		end
	end
	-- A player who turned dungeons on asked for this card, so it comes before the next zone's.
	journeys[#journeys + 1] =
		DungeonJourney(data, player, completed, log, eligible, prefs, mapName, instanceName, chosenDungeon)
	-- The zone that fits two levels on, when it is another zone than the story's and the one the player stands in,
	-- and already has enough the player can take now; or the chosen zone, while it has a step.
	local nextMap = chosenZone ~= zone and chosenZone or nil
	for _, map in ipairs(not nextMap and ahead or {}) do
		if map ~= zone and map ~= player.map and Open(map) then
			nextMap = #journeys < Model.MAX_JOURNEYS and map or nil
			break
		end
	end
	if nextMap then
		local nextZone, quests = ZoneJourney(data, player, completed, log, ready, eligible, nextMap, prefs, mapName)
		if nextZone and (nextMap == chosenZone or quests >= NEXT_ZONE_PICKUPS) then
			nextZone.kind, nextZone.key = "nextzone", "zone:" .. nextMap
			nextZone.title = L.JOURNEY_NEXT_ZONE:format(ZoneName(data, nextMap, mapName))
			-- The level it fits, while it is among the zones that fit two levels on.
			local fits = false
			for _, map in ipairs(ahead or {}) do
				fits = fits or map == nextMap
			end
			nextZone.reason = WorldReason(data, log, player, nextZone --[[@as AGFJourney]])
				or (fits and L.NEXT_ZONE_LEVEL:format(player.level + levels) or nil)
			journeys[#journeys + 1] = nextZone
		end
	end
	Cap(journeys, prefs.journey)
	for _, journey in ipairs(journeys) do
		Summarise(journey --[[@as AGFJourney]])
	end
	return journeys
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
function Model.Plan(data, player, completed, log, prefs, mapName, instanceName)
	skippedSeen = {}
	local route = Route(Model.Journeys(data, player, completed, log, prefs, mapName, instanceName), prefs)
	route.skipped, skippedSeen = skippedSeen, nil
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
		for _, id in ipairs(kept and kept.quests or {}) do
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

-- The in-combat rebuild (Core.lua): the carry journey fresh from the live log, which is what changes in a fight,
-- and every other journey as the last full build left it, less any step skipped or no longer open since. Only the
-- retained steps' quests are checked again: no eligibility pass over the data and no 2-opt, so it stays cheap; the
-- full build runs once combat ends.
---@param last AGFRoute
function Model.Refresh(data, player, completed, log, prefs, last, mapName)
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
		end
		local pickups, handins = Keep(step.pickups, Open), Keep(step.handins, Carried)
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
	local journeys, dismissed =
		{ Carry(data, player, completed, log, Ready(data, log), prefs, mapName, true) }, prefs.notInterested or {}
	for _, journey in ipairs(last.journeys) do
		journeys[#journeys + 1] = journey.kind ~= "carry" and not dismissed[journey.key] and Retained(journey, Prune)
			or nil
	end
	-- A carry card the last build lacked pushes out the last card not chosen, as the full build would leave it out.
	Cap(journeys, prefs.journey)
	return Route(journeys, prefs)
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
