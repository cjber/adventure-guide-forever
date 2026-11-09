-- Run from the repository root: luajit tests/tab_anchor_spec.lua
-- The Quests tab the guide brings to the map's right edge sits flush with the frame (#447). The client's Camelot
-- offset is tuned for stock tab art that Forever hides and never draws, so its horizontal part leaves a dark strip.
local harness = dofile("tests/harness.lua")
local h = harness.load({ log = {} })
local map, tab = h.G.QuestMapFrame, h.G.ForeverQuestLogQuestsTab
assert(tab, "the guide brings its own Quests tab when the stock tabs are hidden")
local point, relativeTo, relativePoint, x, y = tab:GetPoint(1)
assert(point == "TOPLEFT", "the tab hangs off the frame's top right: " .. tostring(point))
assert(relativeTo == map, "off the map frame itself")
assert(relativePoint == "TOPRIGHT", "at the frame's right edge: " .. tostring(relativePoint))
assert(x == 0, "flush with the edge, so no dark strip: x=" .. tostring(x))
assert(y == -28, "the client's vertical offset is kept: y=" .. tostring(y))
-- The guide's own tab stacks directly under it, so the two read as one column.
local guidePoint, guideRelative, _, guideX, guideY = h.G.AdventureGuideForeverTab:GetPoint(1)
assert(guidePoint == "TOP" and guideRelative == tab, "the guide tab sits under the Quests tab")
assert(guideX == 0 and guideY == -3, "with the stock gap between tabs: " .. tostring(guideX) .. "," .. tostring(guideY))
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("tab_anchor_spec: the map's tabs touch the frame's right edge")
