---@type string, AGFNamespace
local _, ns = ...
local Integrations = ns.Integrations

-- Tweaks Forever's API when it is at least version 1 (version 2 keeps v1's members and adds Trainers), else nil.
-- A range, not an equality, so a newer additive Tweaks Forever never silently disables the trainer hint.
---@return AGFTFAPI?
local function Tweaks()
	local api = TweaksForever and TweaksForever.API
	if type(api) ~= "table" or type(api.version) ~= "number" or api.version < 1 then
		return nil
	end
	---@cast api AGFTFAPI
	return api
end

-- The player's class trainers with their places (Tweaks Forever API v2). For a class the bundled trainer data does
-- not place (Forever's extra class/race combinations, e.g. a Horde paladin), the asides' trainer hint stands here.
-- Nil without a version 2.
---@return AGFClassTrainer[]?
function Integrations.Trainers()
	local api = Tweaks()
	if not api or api.version < 2 or type(api.Trainers) ~= "function" then
		return nil
	end
	local ok, list = pcall(api.Trainers)
	if not ok or type(list) ~= "table" then
		return nil
	end
	---@cast list AGFTFTrainer[]
	local trainers = {}
	for _, trainer in ipairs(list) do
		if type(trainer) == "table" and type(trainer.npc) == "number" then
			local place = trainer.map
					and trainer.x
					and trainer.y
					and { map = trainer.map, x = trainer.x, y = trainer.y, name = trainer.name }
				or nil
			trainers[#trainers + 1] = { npc = trainer.npc, name = trainer.name, place = place }
		end
	end
	return trainers
end

-- Tweaks Forever's spells to train: how many, and the highest level among them, for the trainer aside
-- (Asides.lua) and a chosen journey's trainer stop. Nil without Tweaks Forever or its answer, and with nothing
-- to train.
---@return AGFTraining?, boolean known
function Integrations.Training()
	local api = Tweaks()
	if not api or type(api.TrainableSpells) ~= "function" then
		return nil, false
	end
	local spells = api.TrainableSpells()
	if not spells or #spells == 0 then
		return nil, spells ~= nil
	end
	-- A trainer hint is an actionable recommendation. Known fees must be
	-- affordable; an absent fee is not safe to present as affordable. A spell
	-- whose level the API does not give cannot be placed either: it is left
	-- out like an unknown fee, never passed to math.max (a rebuild would raise).
	local money = GetMoney()
	local affordable = {}
	for _, spell in ipairs(spells) do
		if
			type(spell.cost) == "number"
			and spell.cost >= 0
			and spell.cost <= money
			and type(spell.level) == "number"
		then
			affordable[#affordable + 1] = spell
		end
	end
	spells = affordable
	if #spells == 0 then
		return nil, true
	end
	local level = 0
	for _, spell in ipairs(spells) do
		level = math.max(level, spell.level)
	end
	return { count = #spells, level = level }, true
end
