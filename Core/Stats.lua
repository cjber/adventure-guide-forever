---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

---@class AGFStats
local Stats = {}
ns.Stats = Stats

local METRIC = "quest_turn_ins"
local SUBJECT = "all"

local function LocalTotal()
	for _, row in ipairs(ns.ActivityStats()) do
		if row.metric == METRIC and row.subject == SUBJECT then
			return row.value, row.eventUnix
		end
	end
	return 0, nil
end

---@return number, number?
function Stats.Local()
	return LocalTotal()
end

return Stats
