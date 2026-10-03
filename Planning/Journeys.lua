---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local State = ns.Planner.State
local NONE = {}
local Build = ns.Planner.Routing.Build
local Choices = ns.Planner.Zones.Choices
local Count = ns.Planner.Steps.Count
local Describe = ns.Planner.Steps.Describe
local Dropped = ns.Planner.Eligibility.Dropped
local Eligible = ns.Planner.Eligibility.Eligible
local Far = ns.Planner.Zones.Far
local GreyRisk = ns.Planner.Steps.GreyRisk
local Hard = ns.Model.Hard
local Hub = ns.Planner.Steps.Hub
local InZone = ns.Planner.Zones.InZone
local Index = ns.Planner.Eligibility.Index
local Laps = ns.Planner.Laps.Laps
local Locate = ns.Planner.Steps.Locate
local LogSteps = ns.Planner.Steps.LogSteps
local Nodes = ns.Planner.Steps.Nodes
local Opens = ns.Planner.Steps.Opens
local OutdoorElite = ns.Planner.Zones.OutdoorElite
local Oversea = ns.Planner.Travel.Oversea
local PickupSteps = ns.Planner.Steps.PickupSteps
local QuestLevel = ns.Planner.Steps.QuestLevel
local ReadDropped = ns.Planner.Eligibility.ReadDropped
local Ready = ns.Planner.Steps.Ready
local Rest = ns.Planner.Services.Rest
local TrainerSteps = ns.Planner.Services.TrainerSteps
local Trim = ns.Planner.Steps.Trim
local Visit = ns.Planner.Steps.Visit

-- The journey cards (docs/design.md §2.2), each holding only steps the player can take now.
local FITS = 3 -- the zones "that fit": the first this many of a ranking, where the zone the player stands in is theirs
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

-- The quests the player added (shift-click, `prefs.pinned`) that no zone card holds: open now, not ruled out, not
-- orange or red, and not an instance's or a raid's, which only the dungeon card offers. By ID.
---@param elsewhere fun(quest: AGFQuest): boolean
---@return integer[]
local function Added(data, player, completed, log, prefs, elsewhere)
	local ids, groups = {}, Index(data).groups
	for id in pairs(prefs.quests and prefs.pinned or NONE) do
		local quest = data.quests[id]
		if
			quest
			and not (quest.dungeon or quest.raid)
			and not Hard(quest, player)
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

-- "Quests in your log": the log's turn-ins and objectives the story card does not hold (`elsewhere`), plus quests
-- the player added that no zone card holds (`added`). The subline counts every quest the card holds, including
-- those outside the route and those nothing places.
---@param ready table<integer, AGFPlace>
---@param elsewhere fun(id: integer, place?: table): boolean
---@param added integer[]
local function Carry(data, player, completed, log, ready, prefs, mapName, elsewhere, added)
	local candidates, stops = TrainerSteps(data, player, prefs, "carry"), {}
	local held = LogSteps(data, player, log, ready, function(id, place)
		return not Dropped(id) and elsewhere(id, place)
	end, stops, candidates, { areas = {}, anchors = {} })
	PickupSteps(data, added, function()
		return true
	end, candidates, stops)
	local steps = Build(data, player, completed, log, candidates, prefs, mapName)
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
		ready = finished,
		underway = underway,
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
			Build(data, player, completed, log, candidates, prefs, mapName, lead, HandIns(ready))
		)
	if #steps == 0 then
		return nil, quests
	end
	-- The chapter frames the card, not the order (docs/design.md §2.3): `lead` is the candidate step that offers the
	-- chapter's quest. A skipped chapter leaves the card to the zone's count; under the nearest order a far chapter
	-- pickup may fall past the shown steps, so the card still tells its chapter even when the step is not drawn.
	local kept = lead ~= nil and not prefs.skipped[lead.key]
	local L, parts, holds, handIn, underway = ns.L, {}, nil, nil, nil
	if held then
		-- The card counts every log quest it holds on its zone, those its laps take later too; carry holds the rest.
		local finished, away
		finished, away, underway = Tally(data, player, log, held, prefs)
		handIn = finished + away
		parts[#parts + 1] = handIn > 0 and L.CARRY_READY:format(handIn) or nil
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
	return {
		map = steps[1].map,
		steps = steps,
		subline = subline,
		count = subline,
		holds = holds,
		ready = handIn,
		underway = underway,
	},
		quests,
		kept and lead or nil
end

-- The dungeon card's instance: while dungeons are `open` (on, or no next zone), the party instance
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
-- by the data otherwise; an instance the data doesn't name gets no card. Its reason counts the log's
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
		instance = best,
		title = name,
		subline = Count(L.DUNGEON_QUESTS_ONE, L.DUNGEON_QUESTS, quests),
		reason = reason,
		map = steps[1].map,
		steps = steps,
	}
end

-- The eligible quests with the instance quests the Dungeons toggle holds back put in, in the index's order: each open
-- to the player now, as Choices judges its own.
---@param eligible integer[]
---@return integer[]
local function WithInstances(data, player, completed, log, index, eligible)
	local pool = {}
	local eligibleIndex, dungeonIndex = 1, 1
	local dungeons = index.dungeonsByLevel[player.level]
	if not dungeons then
		dungeons = {}
		for _, id in ipairs(index.dungeons) do
			local quest = data.quests[id]
			if quest.min <= player.level and not Model.IsGray(quest.level, player.level) then
				dungeons[#dungeons + 1] = id
			end
		end
		index.dungeonsByLevel[player.level] = dungeons
	end
	local eligibleCount, dungeonCount = #eligible, #dungeons
	while eligibleIndex <= eligibleCount or dungeonIndex <= dungeonCount do
		local eligibleID, dungeonID = eligible[eligibleIndex], dungeons[dungeonIndex]
		local id, alreadyEligible
		if not dungeonID or eligibleID and eligibleID < dungeonID then
			id, alreadyEligible, eligibleIndex = eligibleID, true, eligibleIndex + 1
		elseif not eligibleID or dungeonID < eligibleID then
			id, dungeonIndex = dungeonID, dungeonIndex + 1
		else
			id, alreadyEligible, eligibleIndex, dungeonIndex = eligibleID, true, eligibleIndex + 1, dungeonIndex + 1
		end
		local quest = data.quests[id]
		if alreadyEligible or (quest.dungeon and Eligible(data, player, completed, log, id, index.groups)) then
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

-- A card's hub line and group count: its first stop's place, how many stops follow it, and how
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

-- A zone card's reason in the world's voice, the first that applies: a story the player started, at least
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
	-- The first stop with quests: a trainer's stop ahead of its town never takes the town's reason.
	local first
	for _, step in ipairs(journey.steps) do
		first = first or (step.kind ~= "trainer" and step or nil)
	end
	local town = first and first.hub and data.hubs and data.hubs[first.hub]
	if town and #(first.pickups or {}) >= HANDS_MIN then
		return L.REASON_HANDS:format(Model.TownName(data, first))
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
	story.kind, story.key, story.zone = "story", "zone:" .. zone, zone
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

-- A class quest: one only the player's class may take. A mask of several classes is no calling: Vile
-- Familiars is every Horde class's but the warlock's, a starting zone's quest. A raid's is never offered, as the
-- dungeon card offers none.
---@return fun(quest: AGFQuest): boolean
local function ForClass(classBit)
	return function(quest)
		return quest.classes == classBit and not quest.raid
	end
end

-- Your calling (docs/design.md §2.2): the class quests the player can take now, as one card. It leads with
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

-- A chain that leads into an instance, as a story: `into` holds its quests the player can take now, led
-- by its chapter at `step`, and is named after the instance it goes into, by the client when it can.
---@param into table the chain's Pickups
---@param chain AGFStory
---@param step? AGFStep the chapter's step, when Build kept it
---@param instanceName? fun(id: integer): string?
---@return AGFJourney
local function WayIn(data, into, chain, step, continues, instanceName)
	local instance = Into(data, chain) --[[@as integer]]
	into.kind, into.key, into.instance = "story", "chain:" .. chain.members[1], instance
	into.title = ns.L.JOURNEY_INTO:format(instanceName and instanceName(instance) or data.instances[instance].name)
	---@cast into AGFJourney
	if step then
		into.reason = Chapter(into, chain, step, continues)
	end
	return into
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

-- The diversions' order on a tie in newness: the calling, then the dungeon, then a way into an instance, then the
-- battleground the player asked for.
local DIVERSION_ORDER = { calling = 1, dungeon = 2, chain = 3, battleground = 4 }

-- Opt-in: a battleground open to the player (player.battlegrounds, newest first) as a diversion whose card
-- has one step, its nearest battlemaster: the chosen battleground while it is still open, else the newest one the data
-- places a battlemaster for and the player is interested in. None where the data places none, so a card never points
-- at coordinates the data lacks; none either while its step is skipped, which Skipped (n) then keeps.
---@param prefs AGFPrefs
---@param mapName? AGFMapName
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
			if prefs.skipped[key] then
				if State.skippedSeen then
					State.skippedSeen[key] = true
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

-- The full build is sliced across frames so no frame exceeds the client's budget (WFA-13): when Core runs the rebuild
-- in a coroutine, Model.Journeys yields every this many card routes. The caller commits the route only when the last
-- slice ends, so a partial build is never visible. Outside a coroutine (specs, ns.Route's synchronous path) nothing
-- yields and the build is one frame.
local YIELD_EVERY = 4

---@param mapName? AGFMapName the client's (localised) name for a map; the data's English otherwise
---@param instanceName? fun(id: integer): string? the client's name for an instance Map.ID; the data's otherwise
---@param skippedQuests? table<string, integer[]> the build's AGFPlanInputs.skippedQuests
---@return AGFJourney[] journeys
---@return boolean stranded no next zone
function Model.Journeys(data, player, completed, log, prefs, mapName, instanceName, skippedQuests)
	ReadDropped(prefs, skippedQuests)
	local index, L = Index(data), ns.L
	local zones, eligible = Choices(data, player, completed, log, index, prefs, Far(data, player))
	local ready = Ready(data, log)
	-- The offer rules below only gate new choices (docs/design.md §2.10): a chosen zone or dungeon is built while it
	-- has a step, whatever would offer it now.
	local chosen = prefs.journey or ""
	local chosenZone, chosenDungeon = tonumber(chosen:match("^zone:(%d+)$")), tonumber(chosen:match("^dungeon:(%d+)$"))
	-- A journey the player is not interested in is never a card, chosen or not: the next best takes its
	-- place.
	local dismissed = prefs.notInterested or {}
	local function Open(map)
		return map ~= nil and not dismissed["zone:" .. map]
	end
	chosenZone = Open(chosenZone) and chosenZone or nil
	local journeys = {}
	-- One slice of the build per this many cards when running inside Core's rebuild coroutine (see YIELD_EVERY).
	local cardsSinceYield = 0
	local function YieldCards()
		if coroutine.running() then
			cardsSinceYield = cardsSinceYield + 1
			if cardsSinceYield >= YIELD_EVERY then
				cardsSinceYield = 0
				coroutine.yield()
			end
		end
	end
	-- Keep the current zone when it has useful work or was chosen; otherwise lead with the best-fitting zone.
	-- The story holds its log quests, followed by the remaining quests in the log.
	local best
	for _, map in ipairs(zones) do
		best = best or (Open(map) and map or nil)
	end
	local zone, tries, here = best, { best }, chosenZone ~= nil and chosenZone == player.map
	-- As in the ranking, only a quest that isn't an outdoor elite or a raid's makes the zone the player's: an outdoor
	-- elite is optional, and no card offers a raid's.
	local band, inZone = data.zones[player.map], InZone(player.map)
	if band and band.min <= player.level and player.level <= band.max then
		for _, id in ipairs(here and NONE or eligible) do
			local quest = data.quests[id]
			here = here or (not OutdoorElite(quest) and inZone(quest))
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
	for place = 1, math.min(FITS, #zones) do
		here = here or zones[place] == player.map
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
	-- Carry holds the log's quests off the story's zone, as the in-combat rebuild does: the story holds
	-- those on it, a later lap's too.
	local holds = told and told.holds or {}
	local onStory = InZone(zone)
	local added = Added(data, player, completed, log, prefs, function(quest)
		return not onStory(quest)
	end)
	journeys[#journeys + 1] = Carry(data, player, completed, log, ready, prefs, mapName, function(id)
		return not holds[id]
	end, added)
	-- Every zone with a useful pickup is an option, ranked for the player's level now.
	-- The current story already has a card; chosen zones stay while they have a step.
	local headed = chosenZone ~= zone and chosenZone or nil
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
		nextZone.kind, nextZone.key, nextZone.zone = "nextzone", key, map
		nextZone.title = L.JOURNEY_NEXT_ZONE:format(ZoneName(data, map, mapName))
		nextZone.reason = WorldReason(data, log, player, nextZone --[[@as AGFJourney]])
		return nextZone
	end
	local offered = false
	for _, map in ipairs(zones) do
		local mine = map == chosenZone
		if map ~= zone and (mine or (map ~= player.map and Open(map))) then
			local card = NextZone(map)
			journeys[#journeys + 1] = card
			if card then
				headed, offered = headed or map, offered or mine
			end
			YieldCards()
		end
	end
	if chosenZone and chosenZone ~= zone and not offered then
		journeys[#journeys + 1] = NextZone(chosenZone)
	end
	-- Each diversion offers itself with how many quests it holds and the level its newest one opened at, and the
	-- newest is built first (DIVERSION_ORDER on a tie), so a level just gained or a bracket just opened leads.
	local diversions = {}
	local function Offer(kind, key, belongs, build, from)
		local quests, opened = Newest(data, from or eligible, belongs)
		if opened then
			diversions[#diversions + 1] = { kind = kind, key = key, opened = opened, quests = quests, build = build }
		end
	end
	if not dismissed.calling then
		Offer("calling", "calling", ForClass(player.classBit), function()
			return CallingJourney(data, player, completed, log, ready, eligible, prefs, mapName)
		end)
	end
	-- No next zone: at the level cap, or with no alternative and no story here. The dungeon card is offered
	-- then whatever the Dungeons toggle says, and a chain that leads into an instance shows as a story, so the guide
	-- never ends on "nothing fits".
	local stranded = player.level >= player.maxLevel or not (headed or told)
	local pool = (stranded and not prefs.dungeons) and WithInstances(data, player, completed, log, index, eligible)
		or eligible
	local instance = BestDungeon(data, pool, prefs, prefs.dungeons or stranded, chosenDungeon)
	if instance then
		Offer("dungeon", "dungeon:" .. instance, InDungeon(instance), function(quests)
			return DungeonJourney(data, player, completed, log, pool, prefs, mapName, instanceName, instance, quests)
		end, pool)
	end
	-- A way into an instance: the chain the player can take up that goes inside, when stranded or chosen,
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
		end, pool)
	end
	diversions[#diversions + 1] = prefs.battlegrounds and Battleground(data, player, prefs, mapName) or nil
	table.sort(diversions, function(a, b)
		if a.opened ~= b.opened then
			return a.opened > b.opened
		end
		return DIVERSION_ORDER[a.kind] < DIVERSION_ORDER[b.kind]
	end)
	for _, diversion in ipairs(diversions) do
		journeys[#journeys + 1] = diversion.build(diversion.quests)
		YieldCards()
	end
	for _, journey in ipairs(journeys) do
		Summarise(journey --[[@as AGFJourney]])
		Rest(data, player, journey.steps)
	end
	if journeys[1] then
		journeys[1].drop = Droppable(data, player, log)
	end
	return journeys, stranded
end

ns.Planner.Journeys = {
	Added = Added,
	Carry = Carry,
	Summarise = Summarise,
}
