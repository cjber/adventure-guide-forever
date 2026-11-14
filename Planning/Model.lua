---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end
local Text = ForeverCore.Text --[[@as AGFTextModule]]

---@class AGFModel
-- Ten upcoming route actions; the UI scrolls and the plan rebuilds as quests progress.
local Model = { MAX_STEPS = 10 }
ns.Model = Model

-- The overview's headers in the order they show; UI/Overview.lua labels them (GROUPS).
---@type AGFJourneySection[]
Model.SECTIONS = { "continue", "zones", "library", "dungeons", "battlegrounds" }

-- The cards of `section` in the order the guide draws them: Quests in your log leads Continue, ahead of the zone story
-- and a companion guide, then the route's own order. The carry card is the journey the guide follows until the player
-- picks another (Plan.lua's Route).
---@param journeys AGFJourney[]
---@param section AGFJourneySection
---@return AGFJourney[]
function Model.InSection(journeys, section)
	local kept, carry = {}, nil
	for _, journey in ipairs(journeys) do
		if journey.section == section then
			if journey.kind == "carry" then
				carry = journey
			else
				kept[#kept + 1] = journey
			end
		end
	end
	if carry then
		table.insert(kept, 1, carry)
	end
	return kept
end

-- The guide's cards in the order its panel draws them (UI/Panel.lua LayoutJourneys): with one chosen, that card and
-- then the rest as the route offered them; with none, each header's cards in turn, Quests in your log first.
---@param route AGFRoute
---@return AGFJourney[]
function Model.Cards(route)
	local cards = {}
	if route.chosen then
		for _, journey in ipairs(route.journeys) do
			if journey.key == route.journey then
				table.insert(cards, 1, journey)
			else
				cards[#cards + 1] = journey
			end
		end
		return cards
	end
	for _, section in ipairs(Model.SECTIONS) do
		for _, journey in ipairs(Model.InSection(route.journeys, section)) do
			cards[#cards + 1] = journey
		end
	end
	return cards
end

-- The levels a card shows: a battleground's opening level with no top, else its guide's, zone's or instance's span.
-- Nil when it has none to show.
---@param data AGFData
---@param journey AGFJourney
---@return integer? low
---@return integer? high nil for "from `low`"
function Model.LevelRange(data, journey)
	if journey.level then
		return journey.level, nil
	end
	local zone = journey.zone and data.zones[journey.zone] or nil
	---@type AGFInstance?
	local instance = journey.instance and data.instances and data.instances[journey.instance] or nil
	local low, high
	if zone then
		low, high = zone.min, zone.max
	elseif instance then
		low, high = instance.low, instance.high
	end
	if journey.guideLow and journey.guideHigh then
		low, high = journey.guideLow, journey.guideHigh
	end
	if low and high and low > 0 and high >= low then
		return low, high
	end
end
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

-- Whether a quest is open to this character by its permanent restrictions alone: the side it names, then its race
-- and class masks. A restriction the data does not state keeps the quest visible rather than hiding it.
---@param quest AGFQuest
---@param player AGFPlayer
---@return boolean
function Model.ForCharacter(quest, player)
	return (quest.side ~= 1 and quest.side ~= 2 or quest.side == player.side)
		and (player.raceBit == 0 or HasBit(quest.races, player.raceBit))
		and (player.classBit == 0 or HasBit(quest.classes, player.classBit))
end

-- Whether the player could ever take `quest`: it is open to their character, and the data places its start. The
-- shortlist the zone choices and a dungeon card's leftovers share.
---@param quest AGFQuest
---@param player AGFPlayer
---@return boolean
function Model.CouldTake(quest, player)
	return (quest.side == 3 or quest.side == player.side)
		and ValidPlace(quest.start)
		and HasBit(quest.races, player.raceBit)
		and HasBit(quest.classes, player.classBit)
end

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
	local kind = step.kind --[[@as string]]
	return step.handins or ((kind == "turnin" or kind == "bookhandin") and step.quests) or NONE
end

-- The quests a step picks up: a town's eligible pickups, else a lone pickup step's own quests.
---@param step AGFStep
---@return integer[]
function Model.Pickups(step)
	local kind = step.kind --[[@as string]]
	return step.pickups or ((kind == "pickup" or kind == "book") and step.quests) or NONE
end

-- The distinct quest IDs a step works on, ascending: an area step's open objectives, or an objective step's own quests.
---@param step AGFStep
---@return integer[]
function Model.Objectives(step)
	local ids, seen = {}, {}
	for _, objective in ipairs(step.objectives or NONE) do
		if objective.id and not seen[objective.id] then
			seen[objective.id] = true
			ids[#ids + 1] = objective.id
		end
	end
	local kind = step.kind --[[@as string]]
	if not ids[1] and (kind == "objective" or step.verb == "objective") then
		for _, id in ipairs(step.quests or NONE) do
			if not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
	end
	table.sort(ids)
	return ids
end

-- Only published quest data is memoized; player/log/completion tables may change in place.
---@type table<AGFData, AGFIndex>
local indexes = setmetatable({}, { __mode = "k" })

-- An exclusive group's members, ascending; `directed` when any member's links keep their direction (closedBy).
---@class AGFExclusiveGroup: integer[]
---@field directed? boolean

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
			---@type AGFExclusiveGroup
			local group = index.groups[quest.group] or {}
			index.groups[quest.group] = group
			group[#group + 1] = id
			-- A group whose links keep their direction (closedBy, QuestieSource.lua) closes a member only through them.
			group.directed = group.directed or quest.closedBy ~= nil
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

-- Preparation for an instance (docs/design.md §2.21): the chains that lead into it, walked back through every
-- prerequisite link. A story follows `next` links, so it cannot describe a chain that forks (92742 + 92744 > 92745);
-- the dungeon card walks `pre` and `preAny` instead, which is the only direction the data gives for both branches.
-- Memoized per data, like Index.
---@class AGFPreparation
---@field dependents table<integer, table<integer, true>>
---@field leads table<integer, table<integer, true>>
---@field chains table<integer, AGFDungeonChain[]>
---@field visiting table<integer, true>

---@type table<AGFData, AGFPreparation>
local preparations = setmetatable({}, { __mode = "k" })

---@param data AGFData
---@return AGFPreparation
local function Preparation(data)
	local memo = preparations[data]
	if memo then
		return memo
	end
	local dependents = {}
	for id, quest in pairs(data.quests) do
		for _, list in ipairs({ quest.pre or NONE, quest.preAny or NONE }) do
			for _, pre in ipairs(list) do
				if data.quests[pre] then
					local users = dependents[pre]
					if not users then
						users = {}
						dependents[pre] = users
					end
					users[id] = true
				end
			end
		end
	end
	memo = { dependents = dependents, leads = {}, chains = {}, visiting = {} }
	preparations[data] = memo
	return memo
end

-- The instances `questID`'s prerequisite chain leads into: itself when it is filed under one, and every instance a
-- quest that needs it leads into. Memoized. Empty when the data has no such quest.
---@param data AGFData
---@param questID integer
---@return table<integer, true>
function Model.Leads(data, questID)
	local memo = Preparation(data)
	local leads = memo.leads[questID]
	if leads then
		return leads
	end
	local quest = data.quests[questID]
	if not quest or memo.visiting[questID] then
		return NONE
	end
	memo.visiting[questID] = true
	leads = {}
	if quest.dungeon and not quest.raid and data.instances and data.instances[quest.dungeon] then
		leads[quest.dungeon] = true
	end
	for dependent in pairs(memo.dependents[questID] or NONE) do
		for instance in pairs(Model.Leads(data, dependent)) do
			leads[instance] = true
		end
	end
	memo.visiting[questID] = nil
	memo.leads[questID] = leads
	return leads
end

-- The instance's own quests, grouped into the chains their prerequisites form: two quests whose ways back share any
-- quest are one chain, so a branch (92742 + 92744 > 92745) and its later forks stay together. Ascending by the lowest
-- direct quest ID. Memoized.
---@param data AGFData
---@param instance integer
---@return AGFDungeonChain[]
function Model.Chains(data, instance)
	local memo = Preparation(data)
	local cached = memo.chains[instance]
	if cached then
		return cached
	end
	local direct = {}
	for id, quest in pairs(data.quests) do
		if quest.dungeon == instance and not quest.raid then
			direct[#direct + 1] = id
		end
	end
	table.sort(direct)
	local closures = {}
	for _, id in ipairs(direct) do
		local set, stack = {}, { id }
		while #stack > 0 do
			local questID = table.remove(stack)
			if not set[questID] then
				set[questID] = true
				local quest = data.quests[questID]
				if quest then
					for _, list in ipairs({ quest.pre or NONE, quest.preAny or NONE }) do
						for _, pre in ipairs(list) do
							if data.quests[pre] and not set[pre] then
								stack[#stack + 1] = pre
							end
						end
					end
				end
			end
		end
		closures[id] = set
	end
	local parent = {}
	for index = 1, #direct do
		parent[index] = index
	end
	local function Find(index)
		while parent[index] ~= index do
			parent[index] = parent[parent[index]]
			index = parent[index]
		end
		return index
	end
	local owner = {}
	for index, id in ipairs(direct) do
		for questID in pairs(closures[id]) do
			local first = owner[questID]
			if first then
				local a, b = Find(index), Find(first)
				if a ~= b then
					parent[math.max(a, b)] = math.min(a, b)
				end
			else
				owner[questID] = index
			end
		end
	end
	local groups, byRoot = {}, {}
	for index, id in ipairs(direct) do
		local root = Find(index)
		local group = byRoot[root]
		if not group then
			group = { direct = {}, members = {}, set = {} }
			byRoot[root] = group
			groups[#groups + 1] = group
		end
		group.direct[#group.direct + 1] = id
		for questID in pairs(closures[id]) do
			group.set[questID] = true
		end
	end
	for _, group in ipairs(groups) do
		for questID in pairs(group.set) do
			group.members[#group.members + 1] = questID
		end
		table.sort(group.members)
		table.sort(group.direct)
	end
	table.sort(groups, function(a, b)
		return a.direct[1] < b.direct[1]
	end)
	memo.chains[instance] = groups
	return groups
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
	elseif
		player.notOffered
		and player.notOffered[id] == player.level
		and not Line(data, lines, false, "WHY_NOT_OFFERED")
	then
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
	-- An exclusive group closes a quest once one of the quests that close it is done or taken: its closedBy where the
	-- links keep their direction (a breadcrumb never closes its target), every other member where they don't.
	local members = quest.group and groups[quest.group]
	local closers = members and (members.directed and (quest.closedBy or NONE) or members) or NONE
	for _, other in ipairs(closers) do
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
		and not (player.notOffered and player.notOffered[id] == player.level)
end

-- The library books the player carries, by book quest ID, as one string a rebuild compares: a bag or bank change that
-- moves no quest log shape still moves the Library books card, so it must plan in full rather than repaint (#767).
---@param owned table<integer, boolean>?
---@return string
function Model.OwnedShape(owned)
	local ids = {}
	for id in pairs(owned or NONE) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

-- The quest log's shape (docs/design.md §4.4): each quest by ID, whether it is complete, whether it carries an item
-- that runs out (`expiring`), its waypoint, and each objective's type and done flag. The counts are left out, so two
-- logs that differ only in a kill or an item count share a shape.
---@param log table<integer, AGFLogQuest>
---@return string
function Model.LogShape(log)
	local ids, parts = {}, {}
	for id in pairs(log) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local entry = log[id]
		parts[#parts + 1] = ("%d%s%s%s:%.3f:%.3f"):format(
			id,
			entry.complete and "+" or "-",
			entry.expiring and "!" or "",
			tostring(entry.map),
			entry.x or 0,
			entry.y or 0
		)
		for _, objective in ipairs(entry.objectives or NONE) do
			parts[#parts + 1] = tostring(objective.type) .. (objective.done and "1" or "0")
		end
	end
	return table.concat(parts, ",")
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

-- What taking `questID` closes for good (docs/design.md §2.26): the other members of its exclusive group that name it
-- in their closedBy. Left out: a quest done or in the log, one already closed by another quest done or in the log
-- (or by its breadcrumb target), one the character can never take (side, race, class, a repeatable, or a start the
-- data cannot place), a follow-up that needs another member of the group first (its lead is the loss), and another
-- version of the same quest (the same title). Ascending; empty when nothing is lost.
---@param data AGFData
---@param player AGFPlayer
---@param completed table<integer, boolean>
---@param log table<integer, AGFLogQuest>
---@param questID integer
---@return integer[]
function Model.Closes(data, player, completed, log, questID)
	local closes = {}
	local quest = data.quests[questID]
	local members = quest and quest.group and Index(data).groups[quest.group] or NONE
	for _, id in ipairs(members) do
		local other = data.quests[id]
		local named, closed, follows = false, false, false
		for _, by in ipairs(id ~= questID and other.closedBy or NONE) do
			named = named or by == questID
			closed = closed or completed[by] == true or log[by] ~= nil
		end
		local target = other.breadcrumb
		closed = closed or (target ~= nil and (completed[target] == true or log[target] ~= nil))
		for _, list in ipairs(named and { other.pre or NONE, other.preAny or NONE } or NONE) do
			for _, pre in ipairs(list) do
				follows = follows or (pre ~= id and data.quests[pre] ~= nil and data.quests[pre].group == quest.group)
			end
		end
		if
			named
			and not closed
			and not follows
			and ValidPlace(other.start)
			and not completed[id]
			and not log[id]
			and not other.repeatable
			and other.title ~= quest.title
			and (other.side == 3 or other.side == player.side)
			and HasBit(other.races, player.raceBit)
			and HasBit(other.classes, player.classBit)
		then
			closes[#closes + 1] = id
		end
	end
	-- The group lists its members ascending (Index), so the result is too.
	return closes
end

-- Why a quest wants a group, from what the data and the quest log already say (docs/design.md §2.27): a raid's or a
-- dungeon's quest names its instance; an elite quest gives the log's suggested group size (2 or more) when it has
-- one, else just the tag. Nil for a quest done alone, and for one ready to hand in: its group work is done.
---@param data AGFData
---@param log table<integer, AGFLogQuest>
---@param questID integer
---@return AGFGroupNeed? kind
---@return integer? value the instance Map.ID for a raid or a dungeon, the group size for "size"
function Model.GroupNeed(data, log, questID)
	local quest, entry = data.quests[questID], log[questID]
	if not quest or (entry and entry.complete) then
		return nil
	end
	local instance = quest.dungeon
	if instance and data.instances and data.instances[instance] then
		return quest.raid and "raid" or "dungeon", instance
	elseif quest.raid then
		return "raid", nil
	end
	if not quest.elite then
		return nil
	elseif entry and entry.groupSize then
		return "size", entry.groupSize
	end
	return "elite", nil
end

local SEARCH_MAX = 10
-- How many of the best text matches the search asks "open now?" of: Eligible asks Questie's live policy about a
-- QuestieDB quest, so a short query never asks it about hundreds.
local SEARCH_ASKED = 30

-- Search folds text with the suite's one fold and ranks a match with its one ranking, both in Forever Core's
-- Core/Text.lua (`ForeverCore.Text.Fold` and `ForeverCore.Text.Rank`), so "dun garok" finds "Dûn Garok" here exactly as
-- it does in Shortest Path and Hoard.

-- The player's side's quests whose title holds every word of `query` (plain, case-insensitive, accents folded), at
-- most 10: the search's rows (docs/design.md §2.4). Best match first: the whole title, then a title starting with the
-- query, then every word starting a title word, then the words anywhere; within a tier a quest open now (eligible and
-- not too hard, as its row says; given `completed` and `log`, and asked of the best SEARCH_ASKED matches only), then
-- Model.LevelPreference, then title and ID. `title` is the client's, the data's otherwise.
---@param title? fun(questID: integer): string?
---@param completed? table<integer, boolean>
---@param log? table<integer, AGFLogQuest>
---@return integer[]
function Model.Search(data, player, query, title, completed, log)
	local words = {}
	for word in Text.Fold(query):gmatch("%S+") do
		words[#words + 1] = word
	end
	if not words[1] then
		return {}
	end
	query = table.concat(words, " ")
	local found, rank = {}, {}
	for id, quest in pairs(data.quests) do
		if quest.side == 3 or quest.side == player.side then
			local name = (title and title(id)) or quest.title
			local tier = Text.Rank(Text.Fold(name), query)
			if tier then
				local level = (quest.level or 0) > 0 and quest.level or player.level
				found[#found + 1] = id
				rank[id] = { tier, 1, Model.LevelPreference(level, player.level), name }
			end
		end
	end
	local function Before(a, b)
		local x, y = rank[a], rank[b]
		for index = 1, 4 do
			if x[index] ~= y[index] then
				return x[index] < y[index]
			end
		end
		return a < b
	end
	table.sort(found, Before)
	for index = #found, SEARCH_ASKED + 1, -1 do
		found[index] = nil
	end
	if completed and log then
		for _, id in ipairs(found) do
			if Model.Eligible(data, player, completed, log, id) and not Model.Hard(data.quests[id], player) then
				rank[id][2] = 0
			end
		end
		table.sort(found, Before)
	end
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

-- A quest level past the player's chosen ceiling (the maxQuestLevelOffset setting): too high to recommend.
---@param level integer
---@param player AGFPlayer
---@return boolean
function Model.AboveCeiling(level, player)
	return level - player.level > (player.maxQuestLevelOffset or (ORANGE - 1))
end
local AboveCeiling = Model.AboveCeiling

-- Pickup recommendations respect the chosen level ceiling; accepted quests keep their log steps.
---@param quest AGFQuest
---@param player AGFPlayer
function Model.Hard(quest, player)
	return AboveCeiling(quest.level > 0 and quest.level or player.level, player)
end
local Hard = Model.Hard

-- Where a locked quest's chain starts for the player (docs/design.md §2.4): the earliest of its prerequisites, deepest
-- first in the data's order (all-of, then one-of), that is open now and not orange or red. Nil when none is, or when
-- what locks the quest is no prerequisite (a level, a side, a skill). Never a quest the eligibility rule rejects.
---@return integer?
function Model.ChainStart(data, player, completed, log, questID)
	local groups, seen = Index(data).groups, {}
	local function Start(id, depth)
		local quest = data.quests[id]
		if not quest or seen[id] or depth > 30 then
			return nil
		end
		seen[id] = true
		for _, list in ipairs({ quest.pre or NONE, quest.preAny or NONE }) do
			for _, pre in ipairs(list) do
				if not completed[pre] and not log[pre] then
					local found = Start(pre, depth + 1)
					if found then
						return found
					end
					local before = data.quests[pre]
					if before and Eligible(data, player, completed, log, pre, groups) and not Hard(before, player) then
						return pre
					end
				end
			end
		end
	end
	return Start(questID, 0)
end

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
				giver =
					{ map = mapID, x = start.x, y = start.y, z = start.z, title = start.name, quests = {}, adds = {} }
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

-- A journey shared with party members (docs/design.md §4.5): a quest the group still needs is one anybody synced
-- still needs, so the group's completed set is what every member's own completed set holds, the player's included.
---@param completed table<integer, boolean>
---@param synced AGFPartyMember[]
---@return table<integer, boolean>
function Model.GroupCompleted(completed, synced)
	local group = {}
	for id in pairs(completed) do
		local done = true
		for _, member in ipairs(synced) do
			if not member.completed[id] then
				done = false
				break
			end
		end
		group[id] = done or nil
	end
	return group
end

-- `names` joined the way a line of people reads: "Ana", "Ana and Bo", "Ana, Bo and Cy".
---@param names string[]
---@return string
function Model.NameList(names)
	local count = #names
	if count == 0 then
		return ""
	elseif count == 1 then
		return names[1]
	end
	local head = {}
	for index = 1, count - 1 do
		head[index] = names[index]
	end
	return table.concat(head, ns.L.LIST_SEPARATOR) .. " " .. ns.L.SYNC_AND .. " " .. names[count]
end

-- Who a stop is for, while synced (docs/design.md §4.5): "Everyone" when the player and every synced member still
-- need one of its quests, else "For you", "For <name>", or a list. Nil when the player is not synced, the step holds
-- no quests, or the group has nothing left there.
---@param completed table<integer, boolean> the player's own completed quests
---@param synced AGFPartyMember[]
---@param ids? integer[]
---@return string?
function Model.SyncLabel(completed, synced, ids)
	if #synced == 0 or not ids or #ids == 0 then
		return nil
	end
	local you = false
	for _, id in ipairs(ids) do
		you = you or not completed[id]
	end
	local names, everyone = {}, you
	for _, member in ipairs(synced) do
		local needs = false
		for _, id in ipairs(ids) do
			if not member.completed[id] then
				needs = true
				break
			end
		end
		everyone = everyone and needs
		if needs then
			names[#names + 1] = member.name
		end
	end
	local L = ns.L
	if everyone then
		return L.SYNC_EVERYONE
	elseif you and #names == 0 then
		return L.SYNC_FOR_YOU
	elseif you then
		return L.SYNC_FOR_YOU_AND:format(Model.NameList(names))
	elseif #names > 0 then
		return L.SYNC_FOR:format(Model.NameList(names))
	end
	return nil
end
