---@type string, AGFNamespace
local _, ns = ...
local Window, Overview, L = ns.Window, ns.Overview, ns.L
local LEFT = Window.ACTIVITY_LEFT
local WIDTH = Window.INSET_WIDTH - LEFT - Window.RIGHT - 12
local SIZE = 6
---@type AGFDungeonListWidget
local list
---@type FontString
local empty, count
---@type Button
local previous, nextPage
local page = 1
local Refresh

local function Build(parent)
	local heading = Window.Heading(parent, L.JOURNEY_CHOICES)
	heading:SetPoint("TOPLEFT", LEFT, -Window.TOP)
	list = Window.CreateList(parent, LEFT, Window.TOP + 28, WIDTH, 286, 72, function(row, value)
		local choice = value.journey
		row.journey = choice
		Window.SetRingIcon(row.Ring, Overview.KIND_ICONS[choice.kind])
		row.Title:SetText(choice.title)
		row.Info:SetText(choice.reason or choice.subline or Overview.Stops(choice))
	end, function(value)
		ns.Choose(value.journey.key, ns.Setting("titleStartsRoute"))
		Window.Select(1)
	end, function(parentFrame, width, height, click)
		local row = CreateFrame("Button", nil, parentFrame) --[[@as AGFDungeonRow]]
		row:SetSize(width, height)
		local ring = Window.CreateRingIcon(row, 36)
		row.Ring = ring
		ring:SetPoint("LEFT", 4, 0)
		row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		row.Title:SetPoint("TOPLEFT", 50, -12)
		row.Title:SetWidth(width - 62)
		row.Title:SetJustifyH("LEFT")
		row.Title:SetMaxLines(1)
		row.Info = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.Info:SetPoint("TOPLEFT", 50, -34)
		row.Info:SetWidth(width - 62)
		row.Info:SetJustifyH("LEFT")
		row.Info:SetMaxLines(2)
		ns.Art.Slice(row, "PetList-ButtonHighlight", "HIGHLIGHT", 12, 12)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				ns.Menu.Journey(self, self.value.journey)
			else
				click(self.value)
			end
		end)
		row:SetScript("OnEnter", function(self)
			Overview.ShowTooltip(self, { self.value.journey.title, self.value.journey.reason, L.START_ADVENTURE })
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		return row
	end)
	empty = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	empty:SetPoint("TOPLEFT", LEFT, -(Window.TOP + 34))
	empty:SetWidth(WIDTH)
	empty:SetJustifyH("LEFT")
	previous, nextPage, count = Window.CreatePager(parent, function()
		page = math.max(1, page - 1)
		Refresh()
	end, function()
		page = page + 1
		Refresh()
	end)
end

Refresh = function()
	local choices = ns.Route().journeys
	local pages
	page, pages = Window.ClampPage(page, #choices, SIZE)
	local values = {}
	for index = (page - 1) * SIZE + 1, math.min(#choices, page * SIZE) do
		values[#values + 1] = { journey = choices[index] }
	end
	Window.SetList(list, values)
	empty:SetShown(#choices == 0)
	empty:SetText((ns.SourceHint and ns.SourceHint()) or (ns.State.Ready() and L.NO_JOURNEY or L.LOADING))
	previous:SetShown(pages > 1)
	nextPage:SetShown(pages > 1)
	count:SetShown(pages > 1)
	previous:SetEnabled(page > 1)
	nextPage:SetEnabled(page < pages)
	count:SetText(L.JOURNEY_PAGE:format(page, pages))
end

Window.AddActivity({ key = "journeys", label = L.TAB_JOURNEYS, Build = Build, Refresh = Refresh })
