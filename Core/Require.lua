local addonName, ns = ...

-- The one client icon this addon shows for itself in game, declared once in the TOC and read here so no other file
-- repeats the path.
ns.Icon = C_AddOns.GetAddOnMetadata(addonName, "X-Forever-Icon")

-- The game refuses to load this addon when ForeverCore is absent (## Dependencies), but an older ForeverCore still
-- loads. Its API version, the shared API kit and the tracker section API say whether it has everything this addon
-- calls, so an out-of-date one stops the addon's own files here with one line on screen, never a chat message.
if
	ForeverCore == nil
	or (ForeverCore.API or 0) < 1
	or ForeverCore.APIKit == nil
	or ForeverCore.TrackerSection == nil
	or ForeverCore.TrackerLine == nil
then
	ns.broken = true
	local errors = rawget(_G, "UIErrorsFrame")
	if errors then
		errors:AddMessage("Adventure Guide Forever needs ForeverCore, which is missing or too old.", 1, 0.1, 0.1)
	end
end
