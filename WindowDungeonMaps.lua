---@type string, AGFNamespace
local _, ns = ...
local Window, L = ns.Window, ns.L

-- Atlas uses wing IDs in DungeonID, including a shared 35 for Maraudon/Dire Maul.
-- Link by its stable Classic map keys, never by that ambiguous numeric field.
local MAP_GROUPS = {
	[33] = { "ShadowfangKeep" },
	[34] = { "TheStockade" },
	[36] = { "TheDeadmines" },
	[43] = { "WailingCaverns" },
	[47] = { "RazorfenKraul" },
	[48] = { "BlackfathomDeeps" },
	[70] = { "Uldaman" },
	[90] = { "Gnomeregan" },
	[109] = { "TheSunkenTemple" },
	[129] = { "RazorfenDowns" },
	[189] = { "ScarletMonastery", "SM" },
	[209] = { "ZulFarrak" },
	[229] = { "BlackrockSpire" },
	[230] = { "BlackrockDepths" },
	[289] = { "Scholomance" },
	[329] = { "Stratholme" },
	[349] = { "Maraudon" },
	[389] = { "RagefireChasm" },
	[429] = { "DireMaul" },
}

-- Atlas 1.53 / Atlas_ClassicWoW r109: registered Classic maps and their legends.
-- Read the provider's records and artwork in place; never change its selection or database.
---@param instance integer
---@return AGFInteriorMap[]
function Window.DungeonMaps(instance)
	local groups = MAP_GROUPS[instance]
	local maps = {}
	if not (groups and AtlasMaps) then
		return maps
	end
	for key, record in pairs(AtlasMaps) do
		local matches = false
		if type(key) == "string" then
			for _, prefix in ipairs(groups) do
				matches = matches or key:sub(1, #prefix + 3) == "CL_" .. prefix
			end
		end
		if
			type(key) == "string"
			and key:match("^CL_[%w_]+$")
			and type(record) == "table"
			and record.Module == "Atlas_ClassicWoW"
			and matches
			and type(record.ZoneName) == "table"
			and type(record.ZoneName[1]) == "string"
		then
			local lines = {}
			for _, line in ipairs(record) do
				if type(line) == "table" and type(line[1]) == "string" then
					lines[#lines + 1] = line[1]
				end
			end
			maps[#maps + 1] = {
				key = key,
				title = record.ZoneName[1],
				texture = "Interface\\AddOns\\Atlas_ClassicWoW\\Images\\" .. key,
				legend = table.concat(lines, "\n"),
			}
		end
	end
	table.sort(maps, function(a, b)
		return a.key < b.key
	end)
	return maps
end

---@type Frame?
local panel
---@type Texture
local art
---@type FontString
local heading, legend, count, empty
---@type Frame
local legendBody
---@type AGFScrollFrame
local scroll
---@type Button
local previous, nextPage
---@type AGFInteriorMap[]
local maps = {}
local selected = 1

local function Draw()
	local map = maps[selected]
	heading:SetText(map and map.title or L.DUNGEON_MAPS_TAB)
	art:SetShown(map ~= nil)
	scroll:SetShown(map ~= nil)
	empty:SetShown(map == nil)
	previous:SetEnabled(selected > 1)
	nextPage:SetEnabled(selected < #maps)
	count:SetText(map and L.DUNGEON_MAP_PAGE:format(selected, #maps) or "")
	if map then
		art:SetTexture(map.texture)
		legend:SetText(map.legend)
		legendBody:SetHeight(math.max(340, legend:GetStringHeight() + 8))
		scroll:SetVerticalScroll(0)
	end
end

---@param parent Frame
local function Build(parent)
	panel = CreateFrame("Frame", "AdventureGuideForeverDungeonMaps", parent)
	panel:SetAllPoints(parent)
	panel:SetFrameLevel(parent:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.025, 0.02, 0.015, 1)
	heading = Window.Heading(panel, "")
	heading:SetPoint("TOPLEFT", 14, -14)
	heading:SetWidth(Window.INSET_WIDTH - 160)
	local back = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate") --[[@as Button]]
	back:SetSize(112, 22)
	back:SetPoint("TOPRIGHT", -14, -14)
	back:SetText(L.DUNGEON_MAP_BACK)
	back:SetScript("OnClick", function()
		panel:Hide()
	end)
	art = panel:CreateTexture(nil, "ARTWORK")
	art:SetPoint("TOPLEFT", 14, -46)
	art:SetSize(340, 340)
	scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate") --[[@as AGFScrollFrame]]
	scroll:SetPoint("TOPLEFT", 370, -46)
	scroll:SetSize(Window.INSET_WIDTH - 410, 340)
	legendBody = CreateFrame("Frame", nil, scroll)
	legendBody:SetSize(Window.INSET_WIDTH - 410, 340)
	scroll:SetScrollChild(legendBody)
	legend = legendBody:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	legend:SetPoint("TOPLEFT", 0, -4)
	legend:SetWidth(Window.INSET_WIDTH - 418)
	legend:SetJustifyH("LEFT")
	legend:SetWordWrap(true)
	empty = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	empty:SetPoint("CENTER")
	empty:SetWidth(Window.INSET_WIDTH - 100)
	empty:SetText(L.DUNGEON_MAP_MISSING)
	previous = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate") --[[@as Button]]
	previous:SetSize(90, 22)
	previous:SetPoint("BOTTOMLEFT", 14, 8)
	previous:SetText(L.PREVIOUS_PAGE)
	previous:SetScript("OnClick", function()
		selected = math.max(1, selected - 1)
		Draw()
	end)
	nextPage = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate") --[[@as Button]]
	nextPage:SetSize(90, 22)
	nextPage:SetPoint("BOTTOMRIGHT", -14, 8)
	nextPage:SetText(L.NEXT_PAGE)
	nextPage:SetScript("OnClick", function()
		selected = math.min(#maps, selected + 1)
		Draw()
	end)
	count = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	count:SetPoint("BOTTOM", 0, 13)
	parent:HookScript("OnHide", function()
		panel:Hide()
	end)
end

---@param instance integer
---@param parent Frame
function Window.OpenDungeonMaps(instance, parent)
	if not panel then
		Build(parent)
	end
	maps, selected = Window.DungeonMaps(instance), 1
	Draw()
	assert(panel):Show()
end
