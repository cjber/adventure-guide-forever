---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local NONE = {}
local Cost = ns.Planner.Travel.Cost
local Docks = ns.Planner.Travel.Docks
local HasBit = ns.Model.HasBit
local Position = ns.Planner.Travel.Position
local UNKNOWN = ns.Planner.Travel.UNKNOWN

-- A class trainer who teaches the player's spells to train, the highest of them at `level`. Of the player's
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

-- The nearest battlemaster of the player's side for battleground `bg` (a BattlemasterList ID, which
-- CMaNGOS's bg_template shares), by the route's cost; nil where the data places none (Darkspear Islands).
---@param player AGFPlayer
---@param bg integer
---@return AGFNpc?, integer? npc its creature entry
function Model.Battlemaster(data, player, bg)
	return Nearest(data, player, function(npc)
		return npc.bg == bg and HasBit(npc.side, player.side)
	end) -- multi-value: the NPC and its entry
end

--[[ Where to go next for a profession. SkillUp Forever keeps recipes and skill-ups; this only names the
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

-- The first nudge `wanted` takes (every one, without it) that a trainer of the player's side teaches, with
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

-- Rested XP is low when it is under one bubble of the bar (a twentieth of the level's XP, a night at an
-- inn's worth), or none at all when the client gives no bar. False when the player's rest is unknown (a spec's player),
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
-- and an innkeeper of their side stands in its town: its hub. A reason on the stop, never a step of its own;
-- resting ticks it off, and the stop's own reason is back.
---@param steps AGFStep[]
local function Rest(data, player, steps)
	local last = steps[#steps]
	if not last or player.resting or not Model.RestLow(player) then
		return
	end
	for _, npc in pairs(data.npcs or NONE) do
		if npc.inn and HasBit(npc.side, player.side) and last.hub ~= nil and npc.place.hub == last.hub then
			last.reason = ns.L.REST_HERE
			return
		end
	end
end

-- The chosen journey's trainer stops: with spells to train, one per town among the trainers who teach
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

ns.Planner.Services = {
	Rest = Rest,
	TrainerSteps = TrainerSteps,
}
