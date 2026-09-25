---@type string, AGFNamespace
local _, ns = ...

-- Following the quest the player is working on (docs/design.md §4.2): walking into the chosen route's step 1 area
-- ("you're here") selects its quest, the stock way (C_SuperTrack.SetSuperTrackedQuestID), so the map draws the game's
-- own blue objective area where the player stands. Only on walking in, and never over a quest the player selected: a
-- selection that is neither none nor the one AGF made is theirs. Leaving the area, finishing its objectives or turning
-- the setting off clears AGF's selection while it is still AGF's, back to none, the only selection AGF ever replaces.
-- The call is not protected (Blizzard_APIDocumentationGenerated/SuperTrackManagerDocumentation.lua on 1.60.1), so it
-- runs in combat too.
---@class AGFFocusModule : AGFFocus
local Focus = {}
ns.Focus = Focus

-- The next selection, from the area step 1 is when the player stands in it (`here`), the quest the client has selected
-- (`current`, nil or 0 for none) and the setting. `state` keeps the area last seen and the quest AGF selected, which
-- this updates. Returns the quest ID to select, 0 to clear, or nil to leave the selection alone.
---@param state AGFFocusState
---@param here? {key: string, quests: integer[]}
---@param current? integer
---@param enabled boolean
---@return integer?
function Focus.Next(state, here, current, enabled)
	current = current ~= 0 and current or nil
	if state.quest and current ~= state.quest then
		-- The player selected another quest, or none: theirs from now on.
		state.quest = nil
	end
	here = enabled and here or nil
	local key = here and here.key
	local entered = key ~= state.area
	state.area = key
	local keep = false
	for _, id in ipairs(here and here.quests or {}) do
		keep = keep or id == state.quest
	end
	if keep then
		return nil
	elseif here and entered and (not current or current == state.quest) then
		state.quest = here.quests[1]
		return state.quest ~= current and state.quest or nil
	elseif state.quest then
		-- Out of the area, its quest's objectives done there, or the setting off: AGF's selection goes.
		state.quest = nil
		return 0
	end
	return nil
end

-- The area the chosen route's step 1 is while the player stands in it, and its quests with objectives open there.
---@param route AGFRoute
---@return {key: string, quests: integer[]}?
local function Here(route)
	local first = route.chosen and route.steps[1]
	if not (first and first.here and first.objectives) then
		return nil
	end
	local quests, seen = {}, {}
	for _, objective in ipairs(first.objectives) do
		if not seen[objective.id] then
			quests[#quests + 1], seen[objective.id] = objective.id, true
		end
	end
	return #quests > 0 and { key = first.key, quests = quests } or nil
end

-- The area step 1 was at the last look; the quest AGF selected is kept per character (AGFPrefs.focus), so a /reload
-- still knows it as AGF's.
---@type string?
local area

-- Before Integrations' own listener, so a selection cleared on walking out is gone before the route is handed on.
ns.OnRouteChange(function()
	local prefs = ns.Prefs()
	local state = { area = area, quest = prefs.focus }
	local set = Focus.Next(state, Here(ns.Route()), C_SuperTrack.GetSuperTrackedQuestID(), ns.Setting("followQuest"))
	area, prefs.focus = state.area, state.quest
	if set then
		C_SuperTrack.SetSuperTrackedQuestID(set)
	end
end)
