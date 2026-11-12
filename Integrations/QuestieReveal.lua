---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

--[[ Information mode's click shows the stop's quests with Questie's own map icons (#715). Questie exposes no public
     per-quest pin API, so this feature-detects the modules AGF already uses through QuestieLoader and calls only their
     flashing helpers. TrackerUtils' ShowQuestOnMap and ShowQuestObjectivesOnMap are not used: they call the restricted
     C_Map.OpenWorldMap from addon taint (adventure-guide-forever#411, forever-core#333) and ignore its result. AGF
     opens the map through ForeverCore.OpenMap and, one frame later, flashes only when that exact map is showing.

     Nothing here writes Questie's db, settings or frames. FlashFinisher/FlashObjectives are Questie's own read of the
     player's current pins: they flash only icons it already draws, and leave a hidden, untracked or minimap pin alone.
     No retry is queued: a missing module, a different map, a quest with no shown icon or an error asks the caller for
     its own pin reveal instead. ]]
---@class AGFQuestieReveal
local Reveal = {}
ns.QuestieReveal = Reveal

---@param name string
---@return table?
local function Module(name)
	local loader = rawget(_G, "QuestieLoader")
	if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
		return nil
	end
	local ok, module = pcall(loader.ImportModule, loader, name)
	return ok and type(module) == "table" and module or nil
end

---@return table?
local function Profile()
	local questie = rawget(_G, "Questie")
	local db = type(questie) == "table" and questie.db
	return type(db) == "table" and type(db.profile) == "table" and db.profile or nil
end

-- The world map icons Questie already draws for a quest, and only those that are really shown: a minimap twin, a pin
-- hidden by the player's settings, or an icon flashed by another call is not a target to flash.
---@param id integer
---@return table[]
local function ShownFrames(id)
	local map = Module("QuestieMap")
	local names = map and map.questIdFrames and map.questIdFrames[id]
	local frames = {}
	if type(names) ~= "table" then
		return frames
	end
	for _, name in ipairs(names) do
		local icon = _G[name]
		if icon and not icon.miniMapIcon and type(icon.data) == "table" and type(icon.IsShown) == "function" then
			local ok, shown = pcall(icon.IsShown, icon)
			if ok and (shown or icon._hidden_by_flash) then
				frames[#frames + 1] = icon
			end
		end
	end
	return frames
end

-- Whether one Questie objective has a world map icon the player can already see (or Questie is flashing now). The
-- objective's AlreadySpawned entries hold its mapRefs; a minimap-only or hidden ref is not a target, even when another
-- objective of the same quest has a visible icon.
---@param raw table?
---@return boolean
local function Spawned(raw)
	local spawned = type(raw) == "table" and raw.AlreadySpawned
	if type(spawned) ~= "table" then
		return false
	end
	for _, spawn in pairs(spawned) do
		local refs = type(spawn) == "table" and spawn.mapRefs
		if type(refs) == "table" then
			for _, icon in pairs(refs) do
				if type(icon) == "table" and not icon.miniMapIcon and type(icon.IsShown) == "function" then
					local ok, shown = pcall(icon.IsShown, icon)
					if ok and (shown or icon._hidden_by_flash) then
						return true
					end
				end
			end
		end
	end
	return false
end

---@return boolean
function Reveal.Available()
	local questie = rawget(_G, "Questie")
	if type(questie) ~= "table" or type(questie.API) ~= "table" or questie.API.isReady ~= true then
		return false
	end
	local profile = Profile()
	if not profile or profile.enabled == false or profile.enableMapIcons == false then
		return false
	end
	local utils = Module("TrackerUtils")
	return type(utils) == "table"
		and (type(utils.FlashFinisher) == "function" or type(utils.FlashObjectives) == "function")
		and Module("QuestieMap") ~= nil
end

-- The objective tables for a stop's open quests, from QuestieDB's own records: Questie keys its objectives by the
-- client's 1-based log index, which the planner's alignment carries as `index`, never by the data's need slot; only
-- ones Questie has spawned, so FlashObjectives cannot hide every icon to flash nothing.
---@param refs AGFAreaObjective[]
---@return table[]
local function Objectives(refs)
	local questieDB = Module("QuestieDB")
	if not (questieDB and type(questieDB.GetQuest) == "function") then
		return {}
	end
	local objectives = {}
	for _, ref in ipairs(refs) do
		local id = type(ref) == "table" and ref.id
		local index = type(ref) == "table" and ref.index
		if type(id) == "number" and type(index) == "number" then
			local ok, quest = pcall(questieDB.GetQuest, id)
			local held = ok and type(quest) == "table" and quest.Objectives
			local raw = type(held) == "table" and held[index]
			if Spawned(raw) then
				objectives[#objectives + 1] = raw
			end
		end
	end
	return objectives
end

-- Opens the stop's map, then flashes the stop's Questie icons one frame later. False when the reveal cannot be
-- scheduled at all; otherwise `onFail` runs if the deferred reveal finds no map, no module, no shown pin or an error.
---@param step AGFStep|AGFGiver
---@param quests integer[] the stop's quests in the log, in route order
---@param refs? AGFAreaObjective[] the stop's objective slots, when it has them
---@param onFail? fun() the caller's own pin reveal
---@return boolean
function Reveal.Show(step, quests, refs, onFail)
	local function Schedule()
		if InCombatLockdown() or not step or type(step.map) ~= "number" then
			return false
		end
		if not Reveal.Available() then
			return false
		end
		local any = false
		for _, id in ipairs(quests or {}) do
			if #ShownFrames(id) > 0 then
				any = true
				break
			end
		end
		if not any then
			return false
		end
		local ok, opened = pcall(ForeverCore.OpenMap, step.map)
		if not (ok and opened) then
			return false
		end
		local function Fail()
			if onFail then
				onFail()
			end
		end
		C_Timer.After(0, function()
			local ran = pcall(function()
				-- Combat started between the click and the frame: leave the stop alone, as every AGF map action does.
				if InCombatLockdown() then
					return
				end
				-- Questie may have been disabled or reloaded since the click: its icons are no longer ours to flash.
				if not Reveal.Available() then
					Fail()
					return
				end
				local map = WorldMapFrame
				if not map then
					Fail()
					return
				end
				local view = ns.core.MapCanvas.Watch(map)
				local rightMap = view.shown and view.mapID == step.map
				if not rightMap then
					-- The canvas observes a newly shown map on its next update; the map itself answers the same exact
					-- question now, so the first click after a closed map still flashes the right zone.
					rightMap = map:IsShown() and map:GetMapID() == step.map
				end
				if not rightMap then
					Fail()
					return
				end
				local utils = Module("TrackerUtils")
				if not utils then
					Fail()
					return
				end
				local used = false
				local objectives = Objectives(refs or {})
				if #objectives > 0 and type(utils.FlashObjectives) == "function" then
					local flashed = pcall(utils.FlashObjectives, utils, objectives)
					used = flashed
				end
				local questieDB = Module("QuestieDB")
				if
					not used
					and questieDB
					and type(questieDB.GetQuest) == "function"
					and type(utils.FlashFinisher) == "function"
				then
					for _, id in ipairs(quests or {}) do
						if #ShownFrames(id) > 0 then
							local got, quest = pcall(questieDB.GetQuest, id)
							if got and type(quest) == "table" and quest.Id then
								local flashed = pcall(utils.FlashFinisher, utils, quest)
								if flashed then
									used = true
									break
								end
							end
						end
					end
				end
				if not used then
					Fail()
				end
			end)
			if not ran then
				Fail()
			end
		end)
		return true
	end
	local ok, scheduled = pcall(Schedule)
	return ok and scheduled == true
end
