---@type string, AGFNamespace
local _, ns = ...

-- Record completed quest turn-ins from the client's authoritative event. These are local character records; this
-- addon does not transmit them or claim that a local record is a realm first.
local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_TURNED_IN")
local function Activity()
	local prefs = ns.Prefs()
	if type(prefs.activity) ~= "table" then
		prefs.activity = { questTurnIns = 0, quests = {} }
	end
	if type(prefs.activity.questTurnIns) ~= "number" then
		prefs.activity.questTurnIns = 0
	end
	if type(prefs.activity.quests) ~= "table" then
		prefs.activity.quests = {}
	end
	return prefs.activity
end

events:SetScript("OnEvent", function(_, _, questID)
	if type(questID) ~= "number" or questID < 1 then
		return
	end
	local activity = Activity()
	activity.questTurnIns = activity.questTurnIns + 1
	local eventUnix = type(time) == "function" and time() or nil
	activity.lastEventUnix = eventUnix
	local record = activity.quests[questID]
	if type(record) ~= "table" then
		record = { count = type(record) == "number" and record or 0 }
		activity.quests[questID] = record
	end
	record.count = record.count + 1
	record.eventUnix = eventUnix
end)

---@return AGFActivityRecord[] local rows suitable for a future suite transport; this function never transmits them
function ns.ActivityStats()
	local activity = Activity()
	local rows = {
		{
			addon = "AdventureGuideForever",
			metric = "quest_turn_ins",
			subject = "all",
			value = activity.questTurnIns,
			eventUnix = activity.lastEventUnix,
		},
	}
	for questID, record in pairs(activity.quests) do
		if type(record) == "table" and record.count > 0 then
			rows[#rows + 1] = {
				addon = "AdventureGuideForever",
				metric = "quest_turn_in",
				subject = tostring(questID),
				value = record.count,
				eventUnix = record.eventUnix,
			}
		end
	end
	table.sort(rows, function(a, b)
		if a.metric ~= b.metric then
			return a.metric < b.metric
		end
		return a.subject < b.subject
	end)
	return rows
end
