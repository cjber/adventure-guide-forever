---@type string, AGFNamespace
local _, ns = ...
local Window, L, Art = ns.Window, ns.L, ns.Art
local RIGHT = Window.RIGHT
-- The Today strip: up to two asides across the art's top band, a ringed icon and its line.
local TODAY_MAX, TODAY_TOP, TODAY_LEFT, TODAY_RING = 2, 4, 18, 26
-- More asides than chips: a button at the right that lists the rest in a menu.
local MORE_WIDTH, MORE_HEIGHT = 90, 22

---@type AGFTodayChip[]
local chips = {}

--[[ The Today strip ]]

---@class AGFTodayChip : Button
---@field Icon AGFRingIcon
---@field Text FontString
---@field aside? AGFAside

---@param parent Frame
---@param width number
---@return AGFTodayChip
local function CreateChip(parent, width)
	local chip = CreateFrame("Button", nil, parent) --[[@as AGFTodayChip]]
	chip:SetSize(width, 36)
	Art.Slice(chip, "PetList-ButtonHighlight", "HIGHLIGHT", 12, 12)
	chip.Icon = Window.CreateRingIcon(chip, TODAY_RING)
	chip.Icon:SetPoint("LEFT", 0, 0)
	chip.Text = chip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	chip.Text:SetPoint("LEFT", chip.Icon, "RIGHT", 8, 0)
	chip.Text:SetWidth(width - TODAY_RING - 14)
	chip.Text:SetJustifyH("LEFT")
	chip.Text:SetWordWrap(true)
	chip.Text:SetMaxLines(2)
	chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	chip:SetScript("OnClick", function(self, mouseButton)
		ns.Asides.Click(self, mouseButton, self.aside)
	end)
	chip:SetScript("OnEnter", function(self)
		ns.Asides.Enter(self, self.aside)
	end)
	chip:SetScript("OnLeave", GameTooltip_Hide)
	return chip
end

-- The aside's icon inline, for its menu entry.
---@param aside AGFAside
---@return string
local function AsideMarkup(aside)
	local texture = aside.texture
	if type(texture) == "number" then
		return ("|T%d:14:14|t "):format(texture)
	end
	return Art.Markup(texture --[[@as string?]] or aside.icon, 14) .. " "
end

---@class AGFTodayMore : Button
---@field asides? AGFAside[]

---@type AGFTodayMore?
local more

-- "+2 more" at the right: a menu of the asides the chips leave out, each going where its chip would.
---@param inset Frame
---@return AGFTodayMore
local function CreateMore(inset)
	local button = CreateFrame("Button", nil, inset) --[[@as AGFTodayMore]]
	button:SetNormalFontObject("GameFontNormalSmall")
	button:SetHighlightFontObject("GameFontHighlightSmall")
	button:SetSize(MORE_WIDTH, MORE_HEIGHT)
	button:SetPoint("RIGHT", inset, "TOPRIGHT", -RIGHT, -(TODAY_TOP + 18))
	button:SetScript("OnClick", function(self)
		ns.ContextMenu(self, function(_, root)
			for _, aside in ipairs(self.asides or {}) do
				local entry = root:CreateButton(AsideMarkup(aside) .. aside.text, function()
					ns.Asides.Go(aside)
				end)
				entry:SetEnabled(aside.place ~= nil and not ns.Setting("wanderer"))
			end
		end)
	end)
	return button
end

---@param inset Frame
function Window.RefreshToday(inset)
	local all = ns.Asides.All()
	local overflow = #all > TODAY_MAX
	local width = (Window.INSET_WIDTH - TODAY_LEFT - RIGHT - (overflow and MORE_WIDTH + 12 or 0)) / TODAY_MAX
	local asides, rest = {}, {}
	for index, aside in ipairs(all) do
		local list = (overflow and index > TODAY_MAX) and rest or asides
		list[#list + 1] = aside
	end
	if overflow and not more then
		more = CreateMore(inset)
	end
	if more then
		more.asides = rest
		more:SetShown(overflow)
		more:SetText(L.TODAY_MORE:format(#rest))
	end
	for index = 1, TODAY_MAX do
		local aside = asides[index]
		local chip = chips[index]
		if aside and not chip then
			chip = CreateChip(inset, width)
			chips[index] = chip
		end
		if chip then
			chip:SetWidth(width)
			chip.Text:SetWidth(width - TODAY_RING - 14)
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", TODAY_LEFT + (index - 1) * width, -TODAY_TOP)
			chip.aside = aside
			chip:SetShown(aside ~= nil)
			if aside then
				Window.SetRingIcon(chip.Icon, aside.texture or aside.icon)
				chip.Text:SetText(aside.text)
			end
		end
	end
end
