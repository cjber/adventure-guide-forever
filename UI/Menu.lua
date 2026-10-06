---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- The step menu (docs/design.md §2.8), one generator for the tracker's right-click and a step row's. It loads before
-- Tracker.lua, which needs it before Blizzard_WorldMap (and so the guide) has loaded.
---@class AGFMenuModule
local Menu = {}
ns.Menu = Menu

-- "Show again: <title>" for each step skipped this session, in the order they were skipped, then each journey this
-- character is not interested in, then each aside it turned down.
---@param description AGFMenuDescription
function Menu.Skipped(description)
	for _, skipped in ipairs(ns.Skipped()) do
		description:CreateButton(L.SHOW_AGAIN:format(skipped.title), function()
			ns.Unskip(skipped.key)
		end)
	end
end

-- Go's warning (docs/design.md §2.9) for any surface that starts the route: callers ask
-- ns.Integrations.ReplacesJourney() first, since there is nothing to say otherwise.
---@param tooltip GameTooltip
---@param title string
function Menu.GoWarning(tooltip, title)
	GameTooltip_SetTitle(tooltip, title)
	GameTooltip_AddInstructionLine(tooltip, L.REPLACES_JOURNEY)
end

-- "Not this quest" (docs/design.md §2.18) for a step's quests: one button for a lone quest, else one per quest under
-- it. A trainer's or battlemaster's stop has none. The quest stays in the log; Show again brings it back.
---@param root AGFMenuDescription
---@param step AGFStep
local function NotThisQuest(root, step)
	if step.kind == "trainer" or step.kind == "battlemaster" or #step.quests == 0 then
		return
	end
	local log = ns.Snapshot().log
	local function Title(id)
		local entry, quest = log[id], ns.Data.quests[id]
		return (entry and entry.title) or (quest and quest.title) or step.title
	end
	if #step.quests == 1 then
		local id = step.quests[1]
		root:CreateButton(L.NOT_THIS_QUEST, function()
			ns.NotThisQuest(id, Title(id))
		end)
		return
	end
	local submenu = root:CreateButton(L.NOT_THIS_QUEST)
	for _, id in ipairs(step.quests) do
		submenu:CreateButton(Title(id), function()
			ns.NotThisQuest(id, Title(id))
		end)
	end
end

---@param root AGFMenuDescription
---@param step? AGFStep
function Menu.Step(root, step)
	root:CreateTitle(step and step.title or ns.TITLE)
	if step and not ns.Setting("wanderer") then
		local go = root:CreateButton(L.GO, function()
			ns.StartRoute(step)
		end)
		if ns.Integrations.ReplacesJourney() then
			go:SetTooltip(function(tooltip)
				Menu.GoWarning(tooltip, L.GO)
			end)
		end
	end
	if ns.Guidance.Owns() then
		root:CreateButton(L.STOP, ns.Stop)
	end
	-- The quest's map only opens out of combat, so in combat the entry is left out rather than doing nothing.
	if step and ns.InLog(step) and not InCombatLockdown() then
		root:CreateButton(L.SHOW_QUEST, function()
			ns.ShowQuest(step)
		end)
	end
	if step then
		root:CreateButton(L.SKIP, function()
			ns.Skip(step.key, step.title)
		end)
		NotThisQuest(root, step)
	end
	local skipped = #ns.Skipped()
	if skipped > 0 then
		Menu.Skipped(root:CreateButton(L.SKIPPED:format(skipped)))
	end
	if ns.OpenPanel then
		root:CreateButton(L.CHOOSE_JOURNEY, ns.OpenPanel)
	end
end

-- The journey card's menu, including its dungeon companion data.
---@param owner Region
---@param journey AGFJourney
function Menu.Journey(owner, journey)
	ns.ContextMenu(owner, function(_, root)
		root:CreateTitle(journey.title)
		if journey.instance then
			local loot = root:CreateButton(L.DUNGEON_BOSSES_LOOT)
			local bosses, hint = ns.DungeonLoot.Bosses(journey.instance)
			if hint then
				loot:CreateTitle(hint)
			end
			for _, boss in ipairs(bosses) do
				local drops = loot:CreateButton(boss.name)
				drops:CreateTitle(boss.name)
				for _, id in ipairs(boss.items) do
					local name = C_Item.GetItemNameByID(id)
					if not name then
						C_Item.RequestLoadItemDataByID(id)
					end
					drops:CreateButton(name or L.ITEM_LOADING):SetTooltip(function(tooltip)
						tooltip:SetItemByID(id)
					end)
				end
			end
		end
		root:CreateButton(L.NOT_INTERESTED, function()
			ns.NotInterested(journey.key, journey.title)
		end)
	end)
end

---@param owner Region
---@param step? AGFStep
function Menu.Open(owner, step)
	ns.ContextMenu(owner, function(_, root)
		Menu.Step(root, step)
	end)
end

---@return string
function Menu.ClickLine()
	local provider = ns.Integrations.Provider()
	return provider and L.CLICK_TRAVEL:format(provider) or L.CLICK_WAYPOINT
end

---@param _ Region
---@param menu AGFMenuDescription
function Menu.Settings(_, menu)
	local function Setting(label, key)
		return menu:CreateCheckbox(label, function()
			return ns.Setting(key)
		end, function()
			ns.SetSetting(key, not ns.Setting(key))
		end)
	end
	local function Pref(label, key)
		menu:CreateCheckbox(label, function()
			return ns.Prefs()[key]
		end, function()
			local prefs = ns.Prefs()
			prefs[key] = not prefs[key]
			ns.Invalidate()
		end)
	end
	Pref(ns.L.MENU_QUESTS, "quests")
	Pref(ns.L.MENU_DUNGEONS, "dungeons")
	Pref(ns.L.MENU_BATTLEGROUNDS, "battlegrounds")
	Setting(ns.L.MENU_MAP_PINS, "showMapPins")
	-- Givers draw only with map pins on, so the box is grayed until they are (the menu polls a function).
	Setting(ns.L.MENU_GIVERS, "showQuestGivers"):SetEnabled(function()
		return ns.Setting("showMapPins")
	end)
	Setting(ns.L.MENU_TRACKER, "showTracker")
	-- Skipped steps, journeys not wanted and asides turned down, each with Show again.
	local skipped = #ns.Skipped()
	if skipped > 0 then
		ns.Menu.Skipped(menu:CreateButton(ns.L.SKIPPED:format(skipped)))
	end
	menu:CreateButton(ns.L.MENU_MORE_SETTINGS, function()
		ns.OpenSettings()
	end)
end
