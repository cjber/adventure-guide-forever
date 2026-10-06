---@type string, AGFNamespace
local _, ns = ...
local Window, L = ns.Window, ns.L
---@type AGFWindowTab[]
local activities = {}
---@type Frame[]
local contents = {}
---@type Button[]
local buttons = {}
local selected = 1

---@param activity AGFWindowTab
function Window.AddActivity(activity)
	activities[#activities + 1] = activity
end

local function Refresh()
	if not contents[selected] then
		return
	end
	for index, activity in ipairs(activities) do
		contents[index]:SetShown(index == selected)
		buttons[index]:SetEnabled(index ~= selected)
		local muted = activity.Muted and activity.Muted()
		buttons[index]:SetNormalFontObject(muted and "GameFontDisableSmall" or "GameFontNormalSmall")
	end
	activities[selected].Refresh(contents[selected])
end

---@param key string
function Window.SelectActivity(key)
	for index, activity in ipairs(activities) do
		if activity.key == key then
			selected = index
			ns.WindowDB().activity = key
			for tabIndex, tab in ipairs(Window.Tabs()) do
				if tab.key == "activities" then
					Window.Select(tabIndex)
					return
				end
			end
		end
	end
end

---@param parent Frame
local function Build(parent)
	local heading = Window.Heading(parent, L.TAB_ACTIVITIES)
	heading:SetPoint("TOPLEFT", Window.LEFT, -Window.TOP)
	for index, activity in ipairs(activities) do
		local content = CreateFrame("Frame", nil, parent)
		content:SetAllPoints()
		content:Hide()
		contents[index] = content
		activity.Build(content)
		local button =
			CreateFrame("Button", "AdventureGuideForeverActivity" .. activity.key, parent, "UIPanelButtonTemplate")
		---@cast button Button
		button:SetSize(94, 24)
		button:SetPoint("TOPLEFT", Window.LEFT, -(Window.TOP + 26 + (index - 1) * 30))
		button:SetText(activity.label)
		button:SetNormalFontObject(
			activity.Muted and activity.Muted() and "GameFontDisableSmall" or "GameFontNormalSmall"
		)
		button:SetScript("OnClick", function()
			Window.SelectActivity(activity.key)
		end)
		button:SetScript("OnEnter", function(self)
			local muted = activity.Muted and activity.Muted()
			if muted then
				ns.Overview.ShowTooltip(self, { activity.label, muted })
			end
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		buttons[index] = button
		if activity.key == ns.WindowDB().activity or ns.WindowDB().activity == nil and activity.key == "journeys" then
			selected = index
		end
	end
end

Window.AddTab({ key = "activities", label = L.TAB_ACTIVITIES, Build = Build, Refresh = Refresh })
