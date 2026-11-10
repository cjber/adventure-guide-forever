-- The guide's side tab and panel header draw the same client icon as the minimap button and the Forever Leaderboards
-- tab: the one the TOC declares in ## X-Forever-Icon.
local harness = dofile("tests/harness.lua")
local h = harness.load()

local declared = h.G.C_AddOns.GetAddOnMetadata("AdventureGuideForever", "X-Forever-Icon")
assert(type(declared) == "string" and declared ~= "", "the TOC declares the addon's client icon")

local tab = assert(h.G.AdventureGuideForeverTab, "no guide tab")
assert(tab.Icon.file == declared, "the guide's side tab draws the identity icon: " .. tostring(tab.Icon.file))

-- The header portrait, and nothing else in the panel, draws the identity icon.
h.ns.OpenPanel()
h.flush()
local function Textures(frame, file, found)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.objectType == "Texture" and region.file == file then
			found[#found + 1] = region
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		Textures(child, file, found)
	end
	return found
end
local portraits = Textures(assert(h.G.AdventureGuideForeverPanel, "no guide panel"), declared, {})
assert(#portraits == 1, "the panel header draws the identity icon once: " .. #portraits)

print("identity icon: ok")
