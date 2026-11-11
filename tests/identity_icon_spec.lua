-- The guide keeps its established compass on its tab and header.
local harness = dofile("tests/harness.lua")
local h = harness.load()

local declared = h.G.C_AddOns.GetAddOnMetadata("AdventureGuideForever", "X-Forever-Icon")
assert(type(declared) == "string" and declared ~= "", "the TOC declares the addon's client icon")

local tab = assert(h.G.AdventureGuideForeverTab, "no guide tab")
assert(tab.Icon.atlas == "islands-queue-prop-compass", "the guide side tab keeps the compass")

-- The header portrait, and nothing else in the panel, draws the compass.
h.ns.OpenPanel()
h.flush()
local function Textures(frame, atlas, found)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region.objectType == "Texture" and region.atlas == atlas then
			found[#found + 1] = region
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		Textures(child, atlas, found)
	end
	return found
end
local portraits = Textures(assert(h.G.AdventureGuideForeverPanel, "no guide panel"), "islands-queue-prop-compass", {})
assert(#portraits == 1, "the panel header draws the compass once: " .. #portraits)

print("identity icon: ok")
