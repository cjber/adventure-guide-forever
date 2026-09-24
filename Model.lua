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
local ORANGE = 3 -- levels above the player: the stock orange, where a quest gets hard alone

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

-- The maps of the three zones that best fit `level` for the quests `ids`, best first. An outdoor elite is optional
-- (roadmap #16): it rides along on its zone's cards but never picks the zone a solo player is sent to. A raid's quest,
-- which no card offers, never picks one either.
---@return integer[]
local function Rank(data, ids, level)
	local choices, scores = {}, {}
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
-- instance's quests wait behind Dungeons: an outdoor elite is a zone's quest, optional and badged for a group. An
-- orange or red quest (ORANGE levels up or more) is never offered, though its minimum allows it: too hard alone. The
-- zones that fit now also count the log's quests the data has, as a pickup each: a zone the player has taken on is
-- where they are adventuring, though little is left there to pick up.
local function Choices(data, player, completed, log, index, prefs, ahead)
	local eligible, later, target, ranked = {}, {}, player.level + (ahead or 0), {}
	for id in pairs(prefs.quests and log or {}) do
		ranked[#ranked + 1] = data.quests[id] and id or nil
	end
	table.sort(ranked)
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		local instance = quest.dungeon ~= nil
		if
			((instance and prefs.dungeons) or (not instance and prefs.quests))
			and Eligible(data, player, completed, log, id, index.groups, target)
		then
			later[#later + 1] = id
			if
				quest.min <= player.level
				and not Model.IsGray(quest.level, player.level)
				and quest.level - player.level < ORANGE
			then
				eligible[#eligible + 1] = id
				ranked[#ranked + 1] = id
			end
		end
	end
	return Rank(data, ranked, player.level), eligible, ahead and Rank(data, later, target)
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
	-- A trainer's stop (roadmap #5) has no quests: its reason is the spells waiting there.
	if step.kind == "trainer" then
		step.reason = Count(L.TRAINER_SPELL, L.TRAINER_SPELLS, player.train.count)
		step.detail = step.reason
		return
	end
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

-- The data's need slots each client objective type fills, each kind in slot order (tools/gen_quests.py): a kill or
-- use takes 0-3, a collect 4-7, an explore 16.
local SLOTS = { monster = { 0, 3 }, object = { 0, 3 }, item = { 4, 7 }, event = { 16, 16 } }

-- The data's need slots still open for a quest under way. The client's objectives line up with the slots only when it
-- lists as many as the data needs and each kind fills a slot of its own; otherwise every slot counts as open.
---@param quest AGFQuest
---@param entry AGFLogQuest
---@return table<integer, boolean>
local function OpenSlots(quest, entry)
	local slots, open = {}, {}
	for slot in pairs(quest.need or {}) do
		slots[#slots + 1], open[slot] = slot, true
	end
	local objectives = entry.objectives
	if not objectives or #objectives ~= #slots then
		return open
	end
	table.sort(slots)
	local aligned, used = {}, {}
	for _, objective in ipairs(objectives) do
		local range, slot = SLOTS[objective.type], nil
		for _, candidate in ipairs(range and slots or {}) do
			if not slot and not used[candidate] and candidate >= range[1] and candidate <= range[2] then
				slot = candidate
			end
		end
		if not slot then
			return open
		end
		used[slot], aligned[slot] = true, not objective.done
	end
	return aligned
end

-- Where a quest under way is done next in the data: the first area (the generator orders them) of its lowest open
-- slot, with its radius. Nil when the data places none.
---@param quest AGFQuest
---@param entry AGFLogQuest
local function Area(quest, entry)
	local open, best = OpenSlots(quest, entry), nil
	for _, area in ipairs(quest.obj or {}) do
		if open[area[1]] and (not best or area[1] < best[1]) then
			best = area
		end
	end
	local map = best and (best[5] or quest.zone)
	if not (best and map) then
		return nil
	end
	return { map = map, x = best[2] / 1000, y = best[3] / 1000, r = best[4] }
end

-- Where a log quest is done next. Finished, its hand-in: the client's waypoint, else the data's finish. Under way, a
-- waypoint when the client gives one (the live client gives none), else the client's point for it on the map, else
-- the data's area for its first open objective. Nil when nothing places it.
---@param entry AGFLogQuest
local function LogPlace(data, entry)
	local quest = data.quests[entry.id]
	if ValidPlace(entry) then
		return entry
	elseif entry.complete then
		return quest and quest.finish
	elseif ValidPlace(entry.poi) then
		return entry.poi
	end
	return quest and Area(quest, entry)
end

-- Objective steps merge when their areas nearly touch: the yards between their points within both radii (0 for a
-- single point or the client's point) and AREA_GAP. On a map the data places nowhere, CLOSE in map units.
local AREA_GAP = 60

local function Near(data, a, b)
	local yards = Model.Yards(data, a, b)
	if yards then
		return yards <= (a.r or 0) + (b.r or 0) + AREA_GAP
	end
	return Distance(a, b) <= CLOSE
end

-- The log quests a card holds, as steps added to `steps`, and the card's count of them. The quest and dungeon prefs
-- choose what to pick up; a quest already carried always shows, whatever its kind. A finished quest in `ready` (the
-- data and the client agree where it is handed in) joins its town's stop in `stops`, the stops the card's pickups
-- share; any other finished quest is a turn-in at its place. A quest under way is an objective step at its place,
-- merged with those nearby (Near). One nothing places has no step, and still counts: `held` maps every quest the card
-- holds to its step, or false.
---@param ready table<integer, AGFPlace>
---@param belongs fun(id: integer, place?: table): boolean which log quests the card holds, by where they are done next
---@param prefix string "handin:" on the carry card; "hub:" on a zone's, whose towns its pickups share (HubStop)
---@return table<integer, AGFStep|false> held
local function LogSteps(data, player, log, ready, belongs, prefix, stops, steps)
	local ids, objectives, held = {}, {}, {}
	for id in pairs(log) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local entry, quest = log[id], data.quests[id]
		---@type AGFPlace?
		local place = ready[id] or LogPlace(data, entry)
		place = ValidPlace(place) and place or nil
		if belongs(id, place) then
			held[id] = false
			local optional = Optional(quest, entry.level, player)
			if ready[id] then
				local stop = HubStop(stops, steps, ready[id], prefix)
				Join(stop, stop.handins, id, ready[id])
				held[id] = stop
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
			elseif place then
				local kind = (quest and (quest.elite or quest.dungeon)) and "dungeon" or "objective"
				local existing
				for _, step in ipairs(objectives) do
					existing = existing or (step.kind == kind and Near(data, step, place) and step or nil)
				end
				if existing then
					existing.quests[#existing.quests + 1] = id
					existing.optional = existing.optional and optional or nil
					existing.reason = ns.L.QUESTS_HERE:format(#existing.quests)
					existing.detail = existing.reason
				else
					existing = Step(kind, "objective:" .. id, entry.title, place, id, optional, ns.L.QUESTS_IN_PROGRESS)
					existing.r = place.r or 0
					objectives[#objectives + 1] = existing
					steps[#steps + 1] = existing
				end
				held[id] = existing
			end
		end
	end
	return held
end

-- One stop per town of the eligible quests `wanted` accepts; a group quest joins its town's stop like any other.
-- `stops` holds the towns the card already has (LogSteps' hand-ins), which a pickup there joins.
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

-- A stop the player only hands in at: a turn-in, or a town with hand-ins and nothing to pick up. Never a trainer's.
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
	for id, npc in pairs(data.npcs or {}) do
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
			return player.level >= entry.level and ((player.skills or {})[skill] or 0) >= entry.skill
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
	for id in pairs(data.professions or {}) do
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
			for _, npc in pairs(data.npcs or {}) do
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
	for _, npc in pairs(data.npcs or {}) do
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
	for id, npc in pairs(data.npcs or {}) do
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
		if step.kind == "hub" then
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
	local finished, away, underway, here = 0, 0, 0, Position(data, player)
	for id, step in pairs(held) do
		if not (step and prefs.skipped[step.key]) then
			local there = step and Position(data, step)
			if not log[id].complete then
				underway = underway + 1
			elseif here and there and here.known and there.known and here.continent ~= there.continent then
				away = away + 1
			else
				finished = finished + 1
			end
		end
	end
	return finished, away, underway
end

-- "Finish what you carry": the log's turn-ins and objectives the story card doesn't hold (`elsewhere`). The subline
-- counts every quest the card holds, not only the steps that made the route, and those nothing places.
---@param ready table<integer, AGFPlace>
---@param elsewhere fun(id: integer, place?: table): boolean
local function Carry(data, player, completed, log, ready, prefs, mapName, cheap, elsewhere)
	local candidates = TrainerSteps(data, player, prefs, "carry")
	local held = LogSteps(data, player, log, ready, elsewhere, "handin:", {}, candidates)
	local steps = Build(data, player, completed, log, candidates, prefs, mapName, cheap)
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
			if town and not town.spots[id] then
				Join(town, town.handins, id, ready[id])
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
local function Pickups(data, player, completed, log, ready, eligible, belongs, key, prefs, mapName, leadID, zone)
	local candidates, stops, quests, lead, held = {}, {}, 0, nil, nil
	for _, id in ipairs(eligible) do
		quests = quests + (belongs(data.quests[id]) and 1 or 0)
	end
	-- With Quests off the story holds no log quest, so it never stays for the log alone: carry holds them.
	if zone and prefs.quests then
		held = LogSteps(data, player, log, ready, function(id, place)
			return OnZone(data, zone, id, place)
		end, "hub:", stops, candidates)
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
	local steps = Build(data, player, completed, log, candidates, prefs, mapName, false, lead, HandIns(ready))
	if #steps == 0 then
		return nil, quests
	end
	-- The lead only when Build kept it: a skipped chapter leaves the card to the zone's count.
	local kept
	for _, step in ipairs(steps) do
		kept = kept or step == lead
	end
	local L, parts = ns.L, {}
	if held then
		local finished, away, underway = Tally(data, player, log, held, prefs)
		parts[#parts + 1] = finished + away > 0 and L.CARRY_READY:format(finished + away) or nil
		parts[#parts + 1] = underway > 0 and L.CARRY_IN_PROGRESS:format(underway) or nil
	end
	parts[#parts + 1] = (quests > 0 or #parts == 0) and Count(L.QUESTS_NEAR_ONE, L.QUESTS_NEAR, quests) or nil
	local subline = table.concat(parts, L.LIST_SEPARATOR)
	return { map = steps[1].map, steps = steps, subline = subline, count = subline }, quests, kept and lead or nil
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
	local steps = Build(data, player, completed, log, candidates, prefs, mapName)
	if #steps == 0 then
		return nil
	end
	local name = instanceName and instanceName(best) or data.instances[best].name
	local L, inside, belongs = ns.L, 0, InDungeon(best)
	for id in pairs(log) do
		inside = inside + ((data.quests[id] and belongs(data.quests[id])) and 1 or 0)
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
		zone
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
	local L, belongs = ns.L, ForClass(player.classBit)
	local chain, leadID, continues = Lead(data, completed, eligible, belongs)
	for _, id in ipairs(leadID and {} or eligible) do
		leadID = leadID or (belongs(data.quests[id]) and id or nil)
	end
	local calling, quests, lead =
		Pickups(data, player, completed, log, ready, eligible, belongs, "calling", prefs, mapName, leadID)
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
-- (roadmap #21), then the battleground the player asked for, then the next zone.
local DIVERSION_ORDER = { calling = 1, dungeon = 2, chain = 3, battleground = 4, nextzone = 5 }

-- Roadmap #12, opt-in: a battleground open to the player (player.battlegrounds, newest first) as a diversion whose card
-- has one step, its nearest battlemaster: the chosen battleground while it is still open, else the newest one the data
-- places a battlemaster for and the player is interested in. None where the data places none, so a card never points
-- at coordinates the data lacks; none either while its step is skipped, which Skipped (n) then keeps.
---@param prefs AGFPrefs
---@param mapName? fun(map: integer): string?
local function Battleground(data, player, prefs, mapName)
	local L, dismissed, open = ns.L, prefs.notInterested or {}, {}
	for _, bg in ipairs(player.battlegrounds or {}) do
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
	local index, L = Index(data), ns.L
	-- Never past the level cap: a player at it has no next zone to head for.
	local levels = math.min(NEXT_ZONE_AHEAD, player.maxLevel - player.level)
	local zones, eligible, ahead = Choices(data, player, completed, log, index, prefs, levels > 0 and levels or nil)
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
		for _, id in ipairs(here and {} or eligible) do
			local quest = data.quests[id]
			here = here or (not quest.elite and not quest.raid and (quest.zone or quest.start.map) == player.map)
		end
		for id in pairs((here or not prefs.quests) and {} or log) do
			local quest = data.quests[id]
			here = here
				or (
					quest ~= nil
					and not quest.raid
					and quest.zone == player.map
					and not Model.IsGray(QuestLevel(data, log, player, id), player.level)
				)
		end
	end
	for _, map in ipairs(zones) do
		here = here or map == player.map
	end
	for _, map in ipairs(ahead or {}) do
		here = here or map == player.map
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
	journeys[#journeys + 1] = Carry(data, player, completed, log, ready, prefs, mapName, false, function(id, place)
		return not (told and OnZone(data, zone, id, place))
	end)
	-- The diversions (roadmap R4) share the slots carry and the story leave: each offers itself with how many quests it
	-- holds and the level its newest one opened at, and the newest since then is built first, so a level just gained or
	-- a bracket just opened takes the slot. Only as many are built as there are slots, and the chosen one always.
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
	-- The zone that fits two levels on, when it is another zone than the story's and the one the player stands in,
	-- and already has enough the player can take now; or the chosen zone, while it has a step.
	local nextMap = chosenZone ~= zone and chosenZone or nil
	for _, map in ipairs(not nextMap and ahead or {}) do
		if map ~= zone and map ~= player.map and Open(map) then
			nextMap = map
			break
		end
	end
	-- No next zone (roadmap #21): at the level cap, or with none ahead and no story here. The dungeon card is offered
	-- then whatever the Dungeons toggle says, and a chain that leads into an instance shows as a story, so the guide
	-- never ends on "nothing fits".
	local stranded = levels <= 0 or not (nextMap or told)
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
			local into, _, step =
				Pickups(data, player, completed, log, ready, pool, Member, key, prefs, mapName, leadID)
			if into then
				return WayIn(data, into, way, step, continues, instanceName)
			end
		end, nil, pool)
	end
	if nextMap then
		Offer("nextzone", "zone:" .. nextMap, InZone(nextMap), function()
			local nextZone = Pickups(
				data,
				player,
				completed,
				log,
				ready,
				eligible,
				InZone(nextMap),
				"zone:" .. nextMap,
				prefs,
				mapName
			)
			if not nextZone then
				return nil
			end
			nextZone.kind, nextZone.key = "nextzone", "zone:" .. nextMap
			nextZone.title = L.JOURNEY_NEXT_ZONE:format(ZoneName(data, nextMap, mapName))
			-- The level it fits, while it is among the zones that fit two levels on.
			local fits = false
			for _, map in ipairs(ahead or {}) do
				fits = fits or map == nextMap
			end
			nextZone.reason = WorldReason(data, log, player, nextZone --[[@as AGFJourney]])
				or (fits and L.NEXT_ZONE_LEVEL:format(player.level + levels) or nil)
			return nextZone
		end, NEXT_ZONE_PICKUPS)
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
function Model.Plan(data, player, completed, log, prefs, mapName, instanceName)
	skippedSeen = {}
	local journeys, stranded = Model.Journeys(data, player, completed, log, prefs, mapName, instanceName)
	local route = Route(journeys, prefs)
	route.skipped, skippedSeen, route.stranded = skippedSeen, nil, stranded or nil
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

-- The in-combat rebuild (Core.lua): the carry journey fresh from the live log, which is what changes in a fight, after
-- the story as the full build orders them, and every other journey as the last full build left it, less any step
-- skipped or no longer open since. Only the retained steps' quests are checked again: no eligibility pass over the
-- data and no 2-opt, so it stays cheap; the full build runs once combat ends.
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
		elseif step.kind == "trainer" or step.kind == "battlemaster" then
			return step -- nothing is learned, and no battleground opens, in a fight
		end
		if not step.pickups then
			-- A log step: its quests still carried, less an objective finished in the fight, which carry hands in.
			-- Objectives ticked short of that wait for the full build.
			local area = step.kind == "objective" or step.kind == "dungeon"
			local quests = Keep(step.quests, function(id)
				return log[id] ~= nil and not (area and log[id].complete)
			end)
			if #quests == #step.quests then
				return step
			elseif #quests == 0 then
				return nil
			end
			local copy = Copy(step) --[[@as AGFStep]]
			copy.quests = quests
			return copy
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
	-- The story's log quests stay on it; one taken on its zone since, or finished there, joins carry until the full
	-- build.
	local journeys, dismissed, zone, told = {}, prefs.notInterested or {}, nil, {}
	for _, journey in ipairs(last.journeys) do
		local kept = journey.kind ~= "carry" and not dismissed[journey.key] and Retained(journey, Prune) or nil
		if kept and kept.kind == "story" and kept.key:match("^zone:") then
			zone = tonumber(kept.key:match("%d+"))
			for _, step in ipairs(kept.steps) do
				for _, id in ipairs(step.handins or (step.kind ~= "trainer" and step.quests) or {}) do
					told[id] = true
				end
			end
		end
		journeys[#journeys + 1] = kept
	end
	local carry = Carry(data, player, completed, log, Ready(data, log), prefs, mapName, true, function(id, place)
		return not (told[id] and OnZone(data, zone, id, place))
	end)
	if carry then
		table.insert(journeys, (journeys[1] and journeys[1].kind == "story") and 2 or 1, carry)
	end
	-- A carry card the last build lacked pushes out the last card not chosen, as the full build would leave it out.
	Cap(journeys, prefs.journey)
	local route = Route(journeys, prefs)
	route.stranded = last.stranded
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
