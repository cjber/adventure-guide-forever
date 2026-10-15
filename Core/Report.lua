---@type string, AGFNamespace
local addonName, ns = ...

-- Adventure Guide's own lines in /agf report (docs/design.md §2.24): the guide's settings, the quest data, and the
-- stop the tracker shows with each quest's ID and Why lines, then the next stops' titles. Read from the committed
-- route and the snapshot it was planned from: while a build is due the report says so rather than building one.
-- Quest titles are the data's; step titles and Why lines are the client's language.

local NEXT_SHOWN = 2

-- What a stop does with one of its quests.
---@param step AGFStep
---@param id integer
---@return string
local function Verb(step, id)
	for _, handin in ipairs(ns.Model.Handins(step)) do
		if handin == id then
			return "hand in"
		end
	end
	for _, pickup in ipairs(step.pickups or {}) do
		if pickup == id then
			return "pick up"
		end
	end
	return step.kind == "area" and "objectives" or step.kind
end

---@param lines string[]
---@param step AGFStep
---@param label string "Stop" for the stop being guided to, "Route head" for step 1 when nothing is
local function Stop(lines, step, label)
	local Percent = ns.Report.Percent
	lines[#lines + 1] = ("%s: %s [%s %s] map %s %s, %s r%s"):format(
		label,
		step.title or "-",
		step.kind,
		step.key,
		tostring(step.map),
		Percent(step.x),
		Percent(step.y),
		tostring(step.r or 0)
	)
	lines[#lines + 1] = ("  Why: %s | %s"):format(step.reason or "-", step.detail or "-")
	-- What the committed route was planned from, so the Why lines match why the stop is there.
	local data, snapshot = ns.Data, ns.Snapshot()
	local player, completed, log = snapshot.player, snapshot.completed, snapshot.log
	for _, id in ipairs(step.quests) do
		local quest = data.quests[id]
		lines[#lines + 1] = ("  Quest %d %s (level %s): %s%s"):format(
			id,
			quest and quest.title or "-",
			tostring(quest and quest.level or "-"),
			Verb(step, id),
			log[id] and ", in log" or ""
		)
		for _, why in ipairs(quest and ns.Model.Why(data, player, completed, log, id) or {}) do
			lines[#lines + 1] = ("    %s %s"):format(why.met and "+" or "-", why.text)
		end
	end
end

-- The report's Adventure Guide lines.
---@return string[]
function ns.ReportLines()
	local status = ns.QuestieStatus
	local lines = {
		("QuestieDB: %s %s%s"):format(
			status.state,
			status.version or "-",
			status.reason and (" (" .. status.reason .. ")") or ""
		),
		("Settings: %s, %s order, quest levels up to +%s"):format(
			ns.Setting("wanderer") and "wanderer" or "guide",
			ns.Setting("optimisedRoute") and "planned" or "simple",
			tostring(ns.Setting("maxQuestLevelOffset"))
		),
	}
	if not ns.RouteSettled() then
		lines[#lines + 1] = "Route: still being worked out"
		return lines
	end
	local route = ns.Route()
	local journey = ns.CurrentJourney()
	lines[#lines + 1] = ("Journey: %s [%s]%s, %d steps"):format(
		journey and journey.title or "-",
		route.journey or "-",
		route.chosen and ", chosen" or "",
		#route.steps
	)
	local guided = ns.Guidance.CurrentStep()
	local current = guided or route.steps[1]
	if not current then
		lines[#lines + 1] = "Stop: none"
		return lines
	end
	Stop(lines, current, guided and "Stop" or "Route head")
	local after, index = {}, nil
	for position, step in ipairs(route.steps) do
		if step == current then
			index = position
		elseif index and #after < NEXT_SHOWN then
			after[#after + 1] = step.title
		end
	end
	if after[1] then
		lines[#lines + 1] = "Next: " .. table.concat(after, " / ")
	end
	return lines
end

-- /agf where (the wrong-stop issue form's field): just enough to find the stop again, the versions, where the player
-- stands and the report's own lines, without the caught errors and the addon list.
---@return string[]
function ns.WhereLines()
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "-"
	local gameVersion, build = GetBuildInfo()
	local map = C_Map.GetBestMapForUnit("player")
	local point = map and C_Map.GetPlayerMapPosition(map, "player")
	local x, y
	if point then
		x, y = point:GetXY()
	end
	local lines = {
		("%s %s | WoW %s (%s) | %s | level %d"):format(
			addonName,
			version,
			gameVersion,
			build,
			GetLocale(),
			UnitLevel("player") or 0
		),
		("Place: map %s %s, %s"):format(tostring(map or "-"), ns.Report.Percent(x), ns.Report.Percent(y)),
	}
	for _, line in ipairs(ns.ReportLines()) do
		lines[#lines + 1] = line
	end
	return lines
end
