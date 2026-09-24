---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- The step menu (docs/design.md §2.8), one generator for the tracker's right-click and a step row's. It loads before
-- Tracker.lua, which needs it before Blizzard_WorldMap (and so the guide) has loaded.
---@class AGFMenuModule
local Menu = {}
ns.Menu = Menu

-- "Show again: <title>" for each step skipped this session, in the order they were skipped.
---@param description SharedMenuDescriptionProxy
function Menu.Skipped(description)
	for _, skipped in ipairs(ns.Skipped()) do
		description:CreateButton(L.SHOW_AGAIN:format(skipped.title), function()
			ns.Unskip(skipped.key)
		end)
	end
end

---@param root SharedMenuDescriptionProxy
---@param step? AGFStep
function Menu.Step(root, step)
	root:CreateTitle(step and step.title or ns.TITLE)
	if step then
		root:CreateButton(L.GO, function()
			ns.Integrations.Navigate(step)
		end)
	end
	if ns.Integrations.Owns() then
		root:CreateButton(L.STOP, ns.Integrations.Cancel)
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
	end
	local skipped = #ns.Skipped()
	if skipped > 0 then
		Menu.Skipped(root:CreateButton(L.SKIPPED:format(skipped)))
	end
	if ns.OpenPanel then
		root:CreateButton(L.CHOOSE_JOURNEY, ns.OpenPanel)
	end
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
