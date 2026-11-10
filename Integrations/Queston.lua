---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- Queston Forever (CurseForge 1785839) draws its own page in the world map's quest log and adds its own side tab,
-- without joining Forever Core's shared tabs. Each addon used to leave its page shown when the other's was chosen,
-- so both pages stayed under the map and the one built last covered the other. This module is the handshake, done
-- only through Queston's published view and its own Show: the guide closes Queston's page when the guide shows, and
-- Queston's page, whenever it opens, puts the guide away. Nothing is written to Queston's settings or to the map.

---@class AGFQuestonModule
---@field Close fun() close Queston's map page when it is open
---@field Register fun(questsTab: Frame?): boolean hook Queston's view once it exists
local Queston = {}
ns.Queston = Queston

---@return QuestonChronicleView?
local function View()
	local addon = rawget(_G, "QuestonForever")
	local view = type(addon) == "table" and rawget(addon, "ChronicleView")
	if type(view) ~= "table" or type(view.Show) ~= "function" then
		return nil
	end
	return view
end

-- Closes Queston's page when it is open, through its own Show, so the content frames it hid and the tabs it checked
-- go back to the map's own choice. A failure there is Queston's, and leaves the guide as it was.
function Queston.Close()
	local view = View()
	if not view or view.open ~= true then
		return
	end
	ns.core.SafeCall("Queston page", view.Show, view, false)
end

-- Queston's page opened (its tab, its window or its key) while the guide's page is up: the guide steps aside, which
-- restores the map's own frames, so Queston's Show runs once more to hide them again behind its page.
---@param view QuestonChronicleView
---@param showGuide boolean?
local function QuestonShown(view, showGuide)
	if showGuide == true and ForeverCore.QuestLogTabs.Selected() == "guide" then
		ForeverCore.QuestLogTabs.ShowQuests()
		ns.core.SafeCall("Queston page", view.Show, view, true)
	end
end

local hooked, tabHooked = false, false

-- Queston builds its view when it loads; the shared Quests tab exists once the guide has registered its tab.
---@param questsTab Frame?
function Queston.Register(questsTab)
	-- The map's own Quests tab is outside Queston's view: choosing it closes Queston's page as well as the guide's.
	if questsTab and not tabHooked then
		tabHooked = true
		questsTab:HookScript("OnMouseUp", function(_, mouseButton, upInside)
			if mouseButton == "LeftButton" and upInside then
				Queston.Close()
			end
		end)
	end
	local view = View()
	if not view then
		return false
	end
	if not hooked then
		hooked = true
		hooksecurefunc(view, "Show", QuestonShown) -- taint-ok: post-hook on Queston's own table, no Blizzard frame
	end
	return true
end

EventUtil.ContinueOnAddOnLoaded("QuestonForever", function()
	Queston.Register()
end)
