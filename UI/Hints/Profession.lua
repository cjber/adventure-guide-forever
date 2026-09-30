---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

--[[ The profession aside (roadmap #9, docs/design.md §2.16): a learned line at its rank's cap whose next rank is open
     ("Your Mining has reached 75 of 75 · Journeyman training in Ironforge"), else a free profession slot, else a
     secondary skill not yet learned, each at the nearest trainer of the right rank (Model.Profession); text only when
     the data places none. Only where to go: SkillUp Forever keeps recipes and skill-ups. ]]

local RANKS = { L.PROFESSION_RANK_1, L.PROFESSION_RANK_2, L.PROFESSION_RANK_3, L.PROFESSION_RANK_4 }

-- A line's name: the client's for one the character has, the data's (English) for one it lacks.
---@param skill integer
---@return string
local function Name(skill)
	return ns.State.SkillName(skill) or ns.Data.professions[skill].name
end

ns.Asides.Register(function()
	local player = ns.State.Player()
	local nudge = ns.Model.Profession(ns.Data, player, ns.Asides.Wanted)
	if not nudge then
		return nil
	end
	local npc = nudge.npc
	local town = npc and ns.Model.TownName(ns.Data, npc.place, ns.State.MapName)
	local skill = nudge.skill
	local text
	if nudge.kind == "slot" then
		text = town and L.PROFESSION_LINE:format(L.PROFESSION_SLOT, L.PROFESSION_SLOT_IN:format(town))
			or L.PROFESSION_SLOT
	elseif nudge.kind == "learn" then
		---@cast skill integer
		text = town and L.PROFESSION_LEARN_IN:format(Name(skill), town) or L.PROFESSION_LEARN:format(Name(skill))
	else
		---@cast skill integer
		local rank = RANKS[nudge.rank]
		text = L.PROFESSION_LINE:format(
			L.PROFESSION_CAP:format(Name(skill), player.skills[skill], player.caps[skill]),
			town and L.PROFESSION_RANK_IN:format(rank, town) or L.PROFESSION_RANK:format(rank)
		)
	end
	-- The minimap's profession trainer mark (CSV:1322).
	return { key = nudge.key, text = text, icon = "profession", place = npc and npc.place }
end)

-- A skill-up to a rank's cap, or a line learned, changes the answer. SKILL_LINES_CHANGED fires on every weapon
-- skill-up too, so the providers are asked again only when a profession line's rank or cap, or the count of
-- professions, moved; a frame later, once State has read the lines again.
---@type string?
local last
local function Signature()
	local player, parts = ns.State.Player(), {}
	for skill in pairs(ns.Data.professions or {}) do
		parts[#parts + 1] = ("%d:%s:%s"):format(skill, tostring(player.skills[skill]), tostring(player.caps[skill]))
	end
	table.sort(parts)
	parts[#parts + 1] = tostring(player.primaries)
	return table.concat(parts, ",")
end

local pending = false
local skills = CreateFrame("Frame")
skills:RegisterEvent("SKILL_LINES_CHANGED")
skills:SetScript("OnEvent", function()
	if pending then
		return
	end
	pending = true
	C_Timer.After(0, function()
		pending = false
		local now = Signature()
		if now ~= last then
			last = now
			ns.Asides.Refresh()
		end
	end)
end)
