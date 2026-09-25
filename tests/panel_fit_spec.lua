local harness = dofile("tests/harness.lua")
local checks = 0
local function eq(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local h = harness.load({ log = { { id = 99999, title = "Unknown quest", level = 18 } } })
local ns = h.ns
ns.OpenPanel()
h.flush()
local panel = h.G.AdventureGuideForeverPanel
local route = ns.Route()
local journeys = {}
for index = 1, ns.Model.MAX_JOURNEYS do
	local journey = {}
	for key, value in pairs(route.journeys[1]) do
		journey[key] = value
	end
	journey.key = "fit:" .. index
	journey.title = "Head to Stonetalon Mountains and the farthest reaches of the world"
	journey.reason = "A very long detail naming several towns and all the people waiting there"
	journeys[index] = journey
end
route.journeys = journeys

local function Resize(height, width)
	panel.rect = { 0, 0, width or 306, height }
	h.call(panel:GetScript("OnSizeChanged"), panel, panel:GetWidth(), height)
end

local function Rows()
	local rows = h.Find(function(frame)
		return frame:IsVisible() and frame.Icon and frame.Icon.Clip and frame.journey
	end)
	table.sort(rows, function(a, b)
		return select(5, a:GetPoint(1)) > select(5, b:GetPoint(1)) -- multi-value: y offset
	end)
	return rows
end

local function Link()
	for _, entry in ipairs(ns.DumpLayout(panel, h.Describe)) do
		if entry.text and entry.text:find(ns.L.MORE_IN_GUIDE, 1, true) == 1 then
			local text
			ns.DumpLayout(panel, function(region, item)
				if item.path == entry.path then
					text = region
				end
			end)
			return text:GetParent(), entry.text
		end
	end
end

-- Exact-fit boundaries, overflow, a smaller map, and a taller map. Insets include the search,
-- footer, header and bottom padding. No visible row or optional section may use that reserved space.
for _, case in ipairs({
	{ height = 160, rows = 0, link = false },
	{ height = 185, rows = 0, link = true },
	{ height = 253, rows = 1, link = true },
	{ height = 389, rows = 3, link = true },
	{ height = 524, rows = 4, link = true },
	{ height = 525, rows = 6, link = false },
	{ height = 600, rows = 6, link = false },
}) do
	Resize(case.height)
	local rows, link = Rows(), Link()
	eq(#rows, case.rows, "rows fitting height " .. case.height)
	eq(link ~= nil, case.link, "overflow at height " .. case.height)
	local bottom = case.height - 29 - 40 - 44 - 8
	for index, row in ipairs(rows) do
		local y = select(5, row:GetPoint(1))
		eq(-y + row:GetHeight() <= bottom, true, "row fits")
		eq(row:GetWidth(), panel:GetWidth() - 16, "full width")
		eq(row.journey, journeys[index], "route order")
		for _, text in ipairs({ row.Title, row.Reason, row.Foot }) do
			eq(text.wordWrap, false, "no wrapping")
			eq(text.maxLines, 1, "one line")
			eq(text:GetNumLines(), 1, "long text stays on one line")
		end
		h.Hover(row)
		eq(h.tooltip[1], "title: " .. row.journey.title, "full title in tooltip")
		eq(table.concat(h.tooltip, "\n"):find(row.journey.reason, 1, true) ~= nil, true, "full detail in tooltip")
	end
	if link then
		local y = select(5, link:GetPoint(1))
		eq(-y + link:GetHeight() <= bottom, true, "link fits")
	end
	local coverage = false
	for _, entry in ipairs(ns.DumpLayout(panel, h.Describe)) do
		eq(entry.type == "ScrollFrame" or entry.stockTemplate == "ScrollFrameTemplate", false, "no scrolling overview")
		if entry.text == ns.L.UNLISTED then
			coverage = true
			for _, point in ipairs(entry.anchors) do
				if point.point == "TOPLEFT" then
					eq(-point.y + 26 <= bottom, true, "coverage fits")
				end
			end
		end
	end
	eq(coverage, case.height == 524 or case.height == 600, "coverage only with spare room")
end
eq(#h.Find(function(frame)
	return frame:GetObjectType() == "ScrollFrame"
end), 0, "overview never creates a ScrollFrame")

Resize(389, 380)
eq(Rows()[1]:GetWidth(), 364, "rows follow panel width")
local _, text = Link()
eq(text, "More in the Adventure Guide (Shift-J)", "default binding")
h.bindings = { ["CTRL-K"] = "ADVENTUREGUIDEFOREVER_WINDOW" }
h.fire("UPDATE_BINDINGS")
_, text = Link()
eq(text, "More in the Adventure Guide (Ctrl-K)", "current binding")
h.bindings = {}
h.fire("UPDATE_BINDINGS")
local link
link, text = Link()
eq(text, "More in the Adventure Guide", "unbound has no shortcut")

ns.OpenWindow()
ns.Window.Select(3)
h.G.AdventureGuideForeverWindow:Hide()
h.Click(link)
eq(ns.WindowShown(), true, "overflow opens window")
eq(h.G.AdventureGuideForeverWindow.selectedTab, 1, "overflow opens Journeys from another tab")
eq(route.chosen, false, "overflow does not choose or navigate")

local getAsides, getSkipped = ns.Asides.All, ns.Skipped
ns.Asides.All = function()
	local asides = {}
	for index = 1, 8 do
		asides[index] = { key = "aside:" .. index, text = "A reminder", icon = "QuestNormal" }
	end
	return asides
end
ns.Skipped = function()
	return { { key = "skipped", title = "A skipped stop" } }
end
for _, height in ipairs({ 185, 253, 330, 600, 800 }) do
	Resize(height)
	local bottom = height - 121
	local list = h.Find(function(frame)
		return frame.Icon and frame.Icon.Clip and frame.journey
	end)[1]
		:GetParent()
	for _, child in ipairs(list.childFrames) do
		if child:IsVisible() then
			for index = 1, child:GetNumPoints() do
				local point, parent, _, _, y = child:GetPoint(index)
				if parent == list and (point == "TOPLEFT" or point == "TOP") then
					eq(-y + child:GetHeight() <= bottom, true, "rows, asides and Skipped fit at " .. height)
				end
			end
		end
	end
end
route.journeys = {}
Resize(253)
ns.DumpLayout(panel, function(region, entry)
	if entry.text == ns.L.NO_JOURNEY then
		local y = select(5, region:GetPoint(1))
		eq(-y + 26 <= 253 - 121, true, "empty message fits below asides")
	end
end)
route.journeys = journeys
ns.Asides.All, ns.Skipped = getAsides, getSkipped

-- The existing chosen view keeps scrolling; returning to the overview detaches its content.
ns.Choose(nil)
ns.Invalidate()
h.flush()
ns.Choose(ns.Route().journeys[1].key, false)
h.flush()
eq(#h.Find(function(frame)
	return frame:GetObjectType() == "ScrollFrame" and frame:IsVisible()
end), 1, "chosen journey keeps its scroll frame")
ns.Choose(nil)
h.flush()
eq(#h.Find(function(frame)
	return frame:GetObjectType() == "ScrollFrame" and frame:IsVisible()
end), 0, "returning overview has no scrollbar")
Resize(600)
eq(#Rows() > 0, true, "rows survive returning and resizing")
eq(#h.errors, 0, table.concat(h.errors, "\n"))
print("panel_fit_spec: " .. checks .. " checks passed")
