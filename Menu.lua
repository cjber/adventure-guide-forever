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
---@param description SharedMenuDescriptionProxy|AGFMenu
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
---@param root SharedMenuDescriptionProxy
---@param step AGFStep
local function NotThisQuest(root, step)
	if step.kind == "trainer" or step.kind == "battlemaster" or #step.quests == 0 then
		return
	end
	local log = ns.State.Log()
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

---@param root SharedMenuDescriptionProxy
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
	if ns.Integrations.Owns() then
		root:CreateButton(L.STOP, ns.Stop)
	end
	-- Blizzard's details only open out of combat, so in combat the entry is left out rather than doing nothing.
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

-- A journey card's right-click (roadmap #17): its title and "Not interested". What the player carries is theirs, so
-- the carry card has no menu.
---@param owner Region
---@param journey AGFJourney
function Menu.Journey(owner, journey)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag("MENU_ADVENTURE_GUIDE_FOREVER_JOURNEY")
		root:CreateTitle(journey.title)
		root:CreateButton(L.NOT_INTERESTED, function()
			ns.NotInterested(journey.key, journey.title)
		end)
	end)
end

---@param owner Region
---@param tag string
---@param step? AGFStep
function Menu.Open(owner, tag, step)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag(tag)
		Menu.Step(root, step)
	end)
end
