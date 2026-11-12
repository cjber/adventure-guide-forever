local addonName, ns = ...

-- The one client icon this addon shows for itself in game, declared once in the TOC and read here so no other file
-- repeats the path.
ns.Icon = C_AddOns.GetAddOnMetadata(addonName, "X-Forever-Icon")

-- The game refuses to load this addon when ForeverCore is absent (## Dependencies), but an older ForeverCore still
-- loads. API 1 has the tracker host, the family suggestions, the map, settings and context menu openers, the
-- the report window, which this addon calls. The shared API kit and the tracker
-- section and line plumbing arrived after it, so a core missing any of those members is older than this addon and the
-- shared warning (Core/ForeverRequire.lua) names the addon whose bundled core to update. Never a version comparison.
local ready = ForeverCore ~= nil
	and type(ForeverCore.APIKit) == "table"
	and type(ForeverCore.APIKit.Hub) == "function"
	and type(ForeverCore.APIKit.NotReady) == "function"
	and type(ForeverCore.TrackerSection) == "table"
	and type(ForeverCore.TrackerSection.Create) == "function"
	and type(ForeverCore.TrackerSection.Room) == "function"
	and type(ForeverCore.TrackerLine) == "table"
	and type(ForeverCore.TrackerLine.SetHeaderTooltip) == "function"

ns.ForeverRequire(ready)
