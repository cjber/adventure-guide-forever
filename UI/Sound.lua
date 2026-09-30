---@type string, AGFNamespace
local _, ns = ...
---@class AGFSound
local Sound = {}
ns.Sound = Sound
local played, journey, suppressUntil = {}, nil, 0

function Sound.ClientEvent()
	suppressUntil = GetTime() + 1
end

function Sound.Complete(key, story)
	if played[key] then
		return
	end
	played[key] = true
	if (story or GetTime() >= suppressUntil) and ns.Setting("stepSound") then
		PlaySound(SOUNDKIT.UI_SCENARIO_STAGE_END)
	end
end

function Sound.Observe(previous, current, completed, log, trained)
	if not previous.chosen or ns.Prefs().journey ~= previous.journey then
		return
	end
	if journey ~= previous.journey then
		played, journey = {}, previous.journey
	end
	local present = {}
	for _, step in ipairs(current.steps) do
		present[step.orderKey or step.key] = true
	end
	for _, step in ipairs(previous.steps) do
		if not present[step.orderKey or step.key] and not ns.Prefs().skipped[step.key] then
			local done = #step.quests > 0
			for _, id in ipairs(step.quests) do
				local picked = false
				for _, pickup in ipairs(step.pickups or {}) do
					picked = picked or pickup == id
				end
				done = done
					and (
						completed[id]
						or (picked and log[id] ~= nil)
						or (step.objectives ~= nil and log[id] ~= nil and log[id].complete)
					)
			end
			if step.objectives and not done then
				done = #step.objectives > 0
				for _, objective in ipairs(step.objectives) do
					local entry = log[objective.id]
					local matched = completed[objective.id] == true
						or (entry ~= nil and (entry.complete or ns.Model.ObjectiveDone(ns.Data, entry, objective.slot)))
					for _, live in ipairs(entry and entry.objectives or {}) do
						matched = matched or (objective.text ~= nil and objective.text == live.text and live.done)
					end
					done = done and matched
				end
			end
			if step.kind == "trainer" then
				done = trained == true
			end
			if step.checklist then
				local remaining = {}
				for key, value in pairs(step) do
					remaining[key] = value
				end
				ns.Model.TownChecklist(ns.Data, ns.State.Player(), completed, log, remaining --[[@as AGFStep]], step)
				done = remaining.complete
			end
			if done then
				Sound.Complete((step.orderKey or step.key) .. ":" .. table.concat(step.quests, ","))
			end
		end
	end
end
