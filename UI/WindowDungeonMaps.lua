---@type string, AGFNamespace
local _, ns = ...
local Window, L = ns.Window, ns.L

---@class AGFDungeonMapView
---@field panel Frame
---@field back Button
---@field maps AGFInteriorMap[]
---@field selected integer
---@field SetMaps fun(self: AGFDungeonMapView, maps: AGFInteriorMap[]): AGFDungeonMapView
---@field SetInstance fun(self: AGFDungeonMapView, instance: integer): AGFDungeonMapView
---@field Show fun(self: AGFDungeonMapView)
---@field Hide fun(self: AGFDungeonMapView)
---@class AGFWindow
---@field CreateDungeonMapView fun(parent: Frame): AGFDungeonMapView

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

---@param instance integer
---@return AGFInteriorMap[]
function Window.DungeonMaps(instance)
	local groups, maps = MAP_GROUPS[instance], {}
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
				legendLines = lines,
			}
		end
	end
	table.sort(maps, function(a, b)
		return a.key < b.key
	end)
	return maps
end

local views = setmetatable({}, { __mode = "k" })

local function draw(view)
	local map = view.maps[view.selected]
	view.heading:SetText(map and map.title or L.DUNGEON_MAPS_TAB)
	view.mapCard:SetShown(map ~= nil)
	view.legendCard:SetShown(map ~= nil)
	view.art:SetShown(map ~= nil)
	view.empty:SetShown(map == nil)
	view.previous:SetEnabled(view.selected > 1)
	view.next:SetEnabled(view.selected < #view.maps)
	view.count:SetText(map and L.DUNGEON_MAP_PAGE:format(view.selected, #view.maps) or "")
	if not map then
		return
	end
	view.art:SetTexture(map.texture)
	view.art:SetTexCoord(0, 1, 0, 1)
	for _, row in ipairs(view.rows) do
		row:Hide()
	end
	local rowIndex = 0
	local y = 12
	for _, line in ipairs(map.legendLines or {}) do
		rowIndex = rowIndex + 1
		local row = view.rows[rowIndex]
		if not row then
			row = view.legendBody:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			view.rows[rowIndex] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 12, -y)
		row:SetWidth(view.legendWidth - 24)
		row:SetJustifyH("LEFT")
		row:SetWordWrap(true)
		row:SetText(line)
		row:Show()
		y = y + math.max(20, row:GetStringHeight() + 5)
	end
	view.legendBody:SetHeight(math.max(view.legendHeight, y + 8))
	-- Keep the legend viewport visible for short legends; the template handles the
	-- scroll range, and hiding the ScrollFrame would hide the content as well.
	view.scroll:Show()
	view.scroll:EnableMouseWheel(y + 8 > view.legendHeight)
	view.scroll:SetVerticalScroll(0)
end

---@param parent Frame
---@return AGFDungeonMapView
local function build(parent)
	local view = { maps = {}, selected = 1, rows = {} }
	view.panel = CreateFrame("Frame", nil, parent)
	if not _G["AdventureGuideForeverDungeonMaps"] then
		_G["AdventureGuideForeverDungeonMaps"] = view.panel
	end
	view.panel.DungeonMapView = view
	view.panel:SetAllPoints(parent)
	view.panel:SetFrameLevel(parent:GetFrameLevel() + 20)
	view.panel:EnableMouse(true)
	local background = view.panel:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.025, 0.02, 0.015, 1)
	view.heading = Window.Heading(view.panel, "")
	view.heading:SetPoint("TOPLEFT", 14, -14)
	view.heading:SetWidth(Window.INSET_WIDTH - 160)
	view.back = CreateFrame("Button", nil, view.panel, "UIPanelButtonTemplate")
	view.back:SetSize(112, 22)
	view.back:SetPoint("TOPRIGHT", -14, -14)
	view.back:SetText(L.DUNGEON_MAP_BACK)
	view.back:SetScript("OnClick", function()
		view:Hide()
	end)
	view.mapCard = Window.CreateCard(view.panel, false)
	view.mapCard:EnableMouse(false)
	view.mapCard.Shade:Hide()
	view.mapCard.Fade:Hide()
	view.mapCard.Rim[5]:Hide()
	view.mapCard:SetPoint("TOPLEFT", 12, -46)
	Window.SizeCard(view.mapCard, 360, 360, 0.25)
	view.art = view.mapCard:CreateTexture(nil, "ARTWORK")
	view.art:SetPoint("TOPLEFT", 8, -8)
	view.art:SetPoint("BOTTOMRIGHT", -8, 8)
	view.legendCard = Window.CreateCard(view.panel, false)
	view.legendCard:EnableMouse(false)
	-- The legend is live text above the card fill; the card's decorative cover
	-- would otherwise darken it because the scroll child is below that cover.
	view.legendCard.Shade:Hide()
	view.legendCard.Fade:Hide()
	view.legendCard.Rim[5]:Hide()
	view.legendCard:SetPoint("TOPLEFT", 382, -46)
	view.legendCard:SetPoint("RIGHT", -12, 0)
	view.legendCard:SetHeight(360)
	Window.SizeCard(view.legendCard, Window.INSET_WIDTH - 394, 360, 0.12)
	view.legendWidth = Window.INSET_WIDTH - 394
	view.legendHeight = 334
	view.scroll = CreateFrame("ScrollFrame", nil, view.legendCard, "ScrollFrameTemplate")
	view.scroll:SetPoint("TOPLEFT", 2, -2)
	view.scroll:SetPoint("BOTTOMRIGHT", -20, 2)
	view.legendBody = CreateFrame("Frame", nil, view.scroll)
	view.legendBody:SetSize(view.legendWidth, view.legendHeight)
	view.scroll:SetScrollChild(view.legendBody)
	view.empty = view.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	view.empty:SetPoint("CENTER")
	view.empty:SetWidth(Window.INSET_WIDTH - 100)
	view.empty:SetText(L.DUNGEON_MAP_MISSING)
	view.previous = CreateFrame("Button", nil, view.panel, "UIPanelButtonTemplate")
	view.previous:SetSize(90, 22)
	view.previous:SetPoint("BOTTOMLEFT", 14, 8)
	view.previous:SetText(L.PREVIOUS_PAGE)
	view.previous:SetScript("OnClick", function()
		view.selected = math.max(1, view.selected - 1)
		draw(view)
	end)
	view.next = CreateFrame("Button", nil, view.panel, "UIPanelButtonTemplate")
	view.next:SetSize(90, 22)
	view.next:SetPoint("BOTTOMRIGHT", -14, 8)
	view.next:SetText(L.NEXT_PAGE)
	view.next:SetScript("OnClick", function()
		view.selected = math.min(#view.maps, view.selected + 1)
		draw(view)
	end)
	view.count = view.panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	view.count:SetPoint("BOTTOM", 0, 13)
	local function layout(_, width, height)
		if width <= 0 or height <= 0 then
			return
		end
		local mapSize = math.max(1, math.min(440, height - 84, math.floor((width - 36) * 0.55)))
		local legendWidth = math.max(1, width - mapSize - 36)
		Window.SizeCard(view.mapCard, mapSize, mapSize, 0.25)
		view.legendCard:ClearAllPoints()
		view.legendCard:SetPoint("TOPLEFT", 24 + mapSize, -46)
		Window.SizeCard(view.legendCard, legendWidth, mapSize, 0.12)
		view.legendWidth, view.legendHeight = legendWidth - 20, math.max(1, mapSize - 4)
		view.legendBody:SetWidth(view.legendWidth)
		view.heading:SetWidth(math.max(1, width - 160))
		view.empty:SetWidth(math.max(1, width - 100))
		draw(view)
	end
	view.panel:SetScript("OnSizeChanged", layout)
	layout(view.panel, parent:GetWidth(), parent:GetHeight())
	parent:HookScript("OnHide", function()
		view:Hide()
	end)
	function view:SetMaps(newMaps)
		self.maps, self.selected = newMaps or {}, 1
		draw(self)
		return self
	end
	function view:SetInstance(instance)
		return self:SetMaps(Window.DungeonMaps(instance))
	end
	function view:Show()
		self.panel:Show()
	end
	function view:Hide()
		self.panel:Hide()
	end
	return view --[[@as AGFDungeonMapView]]
end

---@param parent Frame
---@return AGFDungeonMapView
function Window.CreateDungeonMapView(parent)
	assert(parent, "Dungeon map views require a parent frame")
	local view = views[parent]
	if not view then
		view = build(parent)
		views[parent] = view
	end
	return view
end

---@param instance integer
---@param parent Frame
function Window.OpenDungeonMaps(instance, parent)
	local view = Window.CreateDungeonMapView(parent)
	view:SetInstance(instance)
	view:Show()
end
