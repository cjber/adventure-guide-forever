---@type string, AGFNamespace
local _, ns = ...
local Window, L = ns.Window, ns.L
---@type AGFDungeonListWidget
local milestones
---@type FontString
local empty, note
---@type Button
local legacy
local function Build(parent)
	local heading = Window.Heading(parent, L.STORY_COMPLETE)
	heading:SetPoint("TOPLEFT", Window.LEFT, -Window.TOP)
	milestones = Window.CreateList(
		parent,
		Window.LEFT,
		Window.TOP + 28,
		Window.Cards.available - 12,
		236,
		40,
		function(row, record)
			row.Title:SetText(record.title)
			row.Info:SetText("")
		end,
		function() end,
		function(parentFrame, width, height)
			local row = CreateFrame("Button", nil, parentFrame) --[[@as AGFDungeonRow]]
			row:SetSize(width, height)
			row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			row.Title:SetPoint("LEFT", 30, 0)
			row.Title:SetWidth(width - 38)
			row.Title:SetJustifyH("LEFT")
			row.Title:SetMaxLines(1)
			row.Info = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			local icon = row:CreateTexture(nil, "ARTWORK")
			ns.Art.Fit(icon, "UI-QuestTracker-Tracker-Check", 18, 18)
			icon:SetPoint("LEFT", 4, 0)
			return row
		end
	)
	empty = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	empty:SetPoint("TOPLEFT", Window.LEFT, -(Window.TOP + 40))
	empty:SetWidth(Window.Cards.available)
	empty:SetJustifyH("LEFT")
	empty:SetText(L.JOURNEY_PROGRESS_EMPTY)
	note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", Window.LEFT, -340)
	note:SetWidth(Window.Cards.available)
	note:SetJustifyH("LEFT")
	note:SetText(L.LEGACY_PROGRESS_NOTE)
	legacy = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	legacy:SetSize(220, 24)
	legacy:SetPoint("TOPLEFT", Window.LEFT, -366)
	legacy:SetText(L.LEGACY_PROGRESS_LINK)
	legacy:SetScript("OnClick", function()
		C_Map.OpenWorldMap()
	end)
end
local function Refresh()
	local hint = ns.Companions.Hint("LegacyForever")
	note:SetText(hint or L.LEGACY_PROGRESS_NOTE)
	legacy:SetEnabled(ns.Companions.State("LegacyForever") == "loaded")
	local records = {}
	for key, record in pairs(ns.Prefs().completedStories) do
		records[#records + 1] = { key = key, title = record.title }
	end
	table.sort(records, function(a, b)
		return a.title < b.title or a.title == b.title and a.key < b.key
	end)
	Window.SetList(milestones, records)
	empty:SetShown(#records == 0)
end
Window.AddTab({ key = "progress", label = L.TAB_PROGRESS, Build = Build, Refresh = Refresh })
