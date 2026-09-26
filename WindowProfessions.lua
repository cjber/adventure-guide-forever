---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Window, Integrations = ns.Window, ns.Integrations

-- The window's Professions tab (docs/design.md §2.19): SkillUp Forever's next skill-ups for one profession at a time,
-- a card of its rank and next recipes over the profession's own art, its next steps and the reagents on the right.
-- Without a SkillUp Forever that has the API (or with nothing to level) the tab stays, greyed, and says so.

local CARD_WIDTH, RING, RECIPE_ROWS, RECIPE_TOP, RECIPE_PITCH = 440, 44, 5, 96, 40
local STEP_ROWS, STEP_HEIGHT, STEP_PITCH, STEP_HEAD = 3, 44, 49, 18
local REAGENT_ROWS, REAGENT_PITCH, REAGENT_ICON = 8, 22, 18
local PICKER_SIZE, PICKER_GAP = 22, 12
local BUTTON_WIDTH, BUTTON_HEIGHT = 124, 22
-- Blizzard's TradeSkillTypeColor: orange, yellow, green and grey by how likely a craft is to raise the skill.
local DIFFICULTY = {
	orange = { 1, 0.5, 0.25 },
	yellow = { 1, 1, 0 },
	green = { 0.25, 0.75, 0.25 },
	grey = { 0.5, 0.5, 0.5 },
}
-- Each profession's recipe-list art (Professions-Recipe-Background-*), by skill line; any other gets the plain one.
local ART = {
	[171] = "Alchemy",
	[164] = "Blacksmithing",
	[185] = "Cooking",
	[333] = "Enchanting",
	[202] = "Engineering",
	[356] = "Fishing",
	[182] = "Herbalism",
	[773] = "Inscription",
	[755] = "Jewelcrafting",
	[165] = "Leatherworking",
	[186] = "Mining",
	[393] = "Skinning",
	[197] = "Tailoring",
}
local SOURCES = {
	vendor = L.REAGENT_VENDOR,
	craft = L.REAGENT_CRAFT,
	gather = L.REAGENT_GATHER,
	auction = L.REAGENT_AUCTION,
}

local LEFT, TOP = Window.LEFT, Window.TOP
local WIDTH = Window.INSET_WIDTH - LEFT - Window.RIGHT
local HEIGHT = Window.INSET_HEIGHT - 12 - TOP
local SIDE_LEFT = LEFT + CARD_WIDTH + 12
local SIDE_WIDTH = WIDTH - CARD_WIDTH - 12

---@class AGFRecipeRow : Frame
---@field Icon AGFRingIcon
---@field Name FontString
---@field Detail FontString

---@class AGFReagentRow : Frame
---@field Icon Texture
---@field Name FontString
---@field Source FontString

---@class AGFProfessionStepRow : AGFWindowRow
---@field profession? AGFSUProfession
---@field step? AGFSUStep
---@field index? integer

---@class AGFProfessionPick : Button
---@field Icon AGFRingIcon
---@field profession? AGFSUProfession

---@class AGFProfessionCard : AGFWindowCard
---@field Icon AGFRingIcon
---@field Title FontString
---@field Range FontString
---@field Tag FontString
---@field Bar AGFProgressBar
---@field BarLabel FontString
---@field Heading FontString
---@field OpenButton Button
---@field profession? AGFSUProfession

---@type AGFProfessionCard
local card
---@type AGFRecipeRow[]
local recipes = {}
---@type AGFProfessionStepRow[]
local steps = {}
---@type AGFReagentRow[]
local reagents = {}
---@type AGFProfessionPick[]
local picks = {}
---@type FontString
local stepsHeading
---@type FontString
local reagentsHeading
-- The calm page for a missing or outdated SkillUp, or nothing to level: the art dimmed and one line.
---@type Texture
local emptyArt
---@type FontString
local emptyText

-- The line the tab gives while it has no profession to show: why, and what would fill it.
---@return string?
local function Muted()
	local state = Integrations.SkillUpState()
	if state == "missing" then
		return ns.Companions.Hint("SkillUpForever") or L.SKILLUP_ABSENT
	elseif state == "outdated" then
		return L.SKILLUP_OUTDATED
	elseif #Integrations.Professions() == 0 then
		return L.SKILLUP_NONE
	end
end

---@param itemID? integer
---@return string?
local function ItemName(itemID)
	return itemID and C_Item.GetItemNameByID(itemID) or nil
end

---@param copper? number
---@return string?
local function Money(copper)
	return copper and copper > 0 and C_CurrencyInfo.GetCoinTextureString(copper) or nil
end

---@param recipe AGFSURecipe
---@return string
local function RecipeDetail(recipe)
	local parts = { L.PROFESSION_RANGE:format(recipe.fromRank, recipe.toRank) }
	if recipe.learned then
		parts[#parts + 1] = L.RECIPE_LEARNED
	elseif recipe.trainAt then
		parts[#parts + 1] = L.RECIPE_TRAIN_AT:format(recipe.trainAt)
	end
	parts[#parts + 1] = not recipe.learned and Money(recipe.cost) or nil
	return table.concat(parts, L.SEPARATOR)
end

---@param parent Frame
---@return AGFRecipeRow
local function CreateRecipe(parent)
	local row = CreateFrame("Frame", nil, parent) --[[@as AGFRecipeRow]]
	row:SetSize(CARD_WIDTH - 40, 32)
	row.Icon = Window.CreateRingIcon(row, 26)
	row.Icon:SetPoint("TOPLEFT", 4, -3)
	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Name:SetPoint("TOPLEFT", 42, 0)
	row.Name:SetPoint("RIGHT")
	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Detail:SetPoint("TOPLEFT", 42, -16)
	row.Detail:SetPoint("RIGHT")
	row.Detail:SetTextColor(0.8, 0.8, 0.8)
	for _, text in ipairs({ row.Name, row.Detail }) do
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
	end
	return row
end

---@param parent Frame
---@return AGFReagentRow
local function CreateReagent(parent)
	local row = CreateFrame("Frame", nil, parent) --[[@as AGFReagentRow]]
	row:SetSize(SIDE_WIDTH, REAGENT_ICON)
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(REAGENT_ICON, REAGENT_ICON)
	row.Icon:SetPoint("LEFT", 4, 0)
	row.Source = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Source:SetPoint("RIGHT", -8, 0)
	row.Source:SetJustifyH("RIGHT")
	row.Source:SetWordWrap(false)
	row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", 28, 0)
	row.Name:SetPoint("RIGHT", row.Source, "LEFT", -8, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	return row
end

---@param parent Frame
---@return AGFProfessionStepRow
local function CreateStep(parent)
	local row = Window.CreateStepRow(parent, STEP_HEIGHT) --[[@as AGFProfessionStepRow]]
	row:SetWidth(SIDE_WIDTH)
	-- A vendor or trainer SkillUp can route to: its waypoint, through Shortest Path, TomTom or the map's pin.
	row:SetScript("OnClick", function(self)
		if self.profession and self.step and self.step.nav then
			Integrations.SkillUpNavigate(self.profession.skillLineID, self.index --[[@as integer]])
		end
	end)
	row:SetScript("OnEnter", function(self)
		local step = self.step
		if not step then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, step.text)
		if step.detail then
			GameTooltip_AddNormalLine(GameTooltip, step.detail)
		end
		if step.nav then
			GameTooltip_AddInstructionLine(GameTooltip, L.CLICK_WAYPOINT_STEP)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

---@param content Frame
local function Build(content)
	emptyArt = content:CreateTexture(nil, "ARTWORK")
	ns.Art.Cover(emptyArt, "Professions-Recipe-Background", WIDTH, HEIGHT)
	emptyArt:SetPoint("TOPLEFT", LEFT, -TOP)
	emptyArt:SetSize(WIDTH, HEIGHT)
	emptyArt:SetAlpha(0.35)
	emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	emptyText:SetPoint("CENTER", emptyArt, "CENTER", 0, 0)
	emptyText:SetWidth(WIDTH - 120)
	emptyText:SetJustifyH("CENTER")

	card = Window.CreateCard(content, false) --[[@as AGFProfessionCard]]
	Window.SizeCard(card, CARD_WIDTH, HEIGHT, 0.8)
	card:SetPoint("TOPLEFT", LEFT, -TOP)
	card.Shade:Hide()
	card.Fade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
	card.Picture:Show()
	card.Highlight:Hide()
	local inner = CreateFrame("Frame", nil, card)
	inner:SetAllPoints()
	inner:SetFrameLevel(card:GetFrameLevel() + 5)
	card.Icon = Window.CreateRingIcon(inner, RING)
	card.Icon:SetPoint("TOPLEFT", 18, -18)
	card.Tag = inner:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	card.Tag:SetPoint("TOPRIGHT", -16, -16)
	card.Tag:SetText(L.FROM_SKILLUP)
	card.Title = inner:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	card.Title:SetPoint("TOPLEFT", 18 + RING + 14, -16)
	card.Title:SetPoint("RIGHT", card.Tag, "LEFT", -8, 0)
	card.Range = inner:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	card.Range:SetPoint("TOPLEFT", 18 + RING + 14, -42)
	card.Range:SetPoint("RIGHT", -16, 0)
	for _, text in ipairs({ card.Title, card.Range }) do
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
	end
	card.Bar = ns.Overview.CreateBar(inner)
	card.BarLabel = inner:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	card.BarLabel:SetPoint("TOPRIGHT", -18, -73)
	card.BarLabel:SetJustifyH("RIGHT")
	card.Heading = Window.Heading(inner, L.NEXT_RECIPES)
	card.Heading:SetPoint("TOPLEFT", 18, -RECIPE_TOP)
	for index = 1, RECIPE_ROWS do
		local row = CreateRecipe(inner)
		row:SetPoint("TOPLEFT", 18, -(RECIPE_TOP + 20 + (index - 1) * RECIPE_PITCH))
		recipes[index] = row
	end
	card.OpenButton = CreateFrame("Button", nil, inner, "UIPanelButtonTemplate") --[[@as Button]]
	card.OpenButton:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	card.OpenButton:SetPoint("BOTTOMRIGHT", -16, 16)
	card.OpenButton:SetText(L.OPEN_RECIPES)
	card.OpenButton:SetScript("OnClick", function()
		if card.profession then
			Integrations.OpenRecipes(card.profession.skillLineID)
		end
	end)

	stepsHeading = Window.Heading(content, L.NEXT_STEPS)
	stepsHeading:SetPoint("TOPLEFT", SIDE_LEFT + 2, -TOP)
	for index = 1, STEP_ROWS do
		local row = CreateStep(content)
		row:SetPoint("TOPLEFT", SIDE_LEFT, -(TOP + STEP_HEAD + (index - 1) * STEP_PITCH))
		steps[index] = row
	end
	local reagentsTop = TOP + STEP_HEAD + STEP_ROWS * STEP_PITCH + 6
	reagentsHeading = Window.Heading(content, L.REAGENTS)
	reagentsHeading:SetPoint("TOPLEFT", SIDE_LEFT + 2, -reagentsTop)
	for index = 1, REAGENT_ROWS do
		local row = CreateReagent(content)
		row:SetPoint("TOPLEFT", SIDE_LEFT, -(reagentsTop + 18 + (index - 1) * REAGENT_PITCH))
		reagents[index] = row
	end
end

---@param content Frame
---@param professions AGFSUProfession[]
---@return AGFSUProfession
local function Picked(content, professions)
	local saved = ns.WindowDB().profession
	local chosen = professions[1]
	for _, profession in ipairs(professions) do
		if profession.skillLineID == saved then
			chosen = profession
		end
	end
	-- One ringed icon a profession, over the inset's top-right, while there is more than one to choose between.
	for index = 1, math.max(#professions, #picks) do
		local profession = #professions > 1 and professions[index] or nil
		local pick = picks[index]
		if profession and not pick then
			pick = CreateFrame("Button", nil, content) --[[@as AGFProfessionPick]]
			pick:SetSize(PICKER_SIZE, PICKER_SIZE)
			pick:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -12 - (index - 1) * (PICKER_SIZE + PICKER_GAP), 12)
			pick.Icon = Window.CreateRingIcon(pick, PICKER_SIZE)
			pick.Icon:SetAllPoints()
			pick:SetScript("OnClick", function(self)
				if self.profession then
					ns.WindowDB().profession = self.profession.skillLineID
					Window.Refresh()
				end
			end)
			pick:SetScript("OnEnter", function(self)
				if self.profession then
					ns.Overview.ShowTooltip(self, { self.profession.name })
				end
			end)
			pick:SetScript("OnLeave", GameTooltip_Hide)
			picks[index] = pick
		end
		if pick then
			pick.profession = profession
			pick:SetShown(profession ~= nil)
			if profession then
				Window.SetRingIcon(pick.Icon, profession.icon)
				pick.Icon.Icon:SetDesaturated(profession ~= chosen)
				pick:SetAlpha(profession == chosen and 1 or 0.7)
			end
		end
	end
	return chosen
end

---@param profession AGFSUProfession
local function RefreshCard(profession)
	card.profession = profession
	local art = ART[profession.skillLineID]
	Window.SetPicture(card, art and "Professions-Recipe-Background-" .. art or "Professions-Recipe-Background")
	Window.SetRingIcon(card.Icon, profession.icon)
	card.Title:SetText(profession.name)
	card.Range:SetText(
		profession.title and L.PROFESSION_RANGE_TITLE:format(profession.rank, profession.maxRank, profession.title)
			or L.PROFESSION_RANGE:format(profession.rank, profession.maxRank)
	)
	card.BarLabel:SetText(L.PROFESSION_BAR:format(profession.rank, profession.maxRank))
	local room = CARD_WIDTH - 36 - card.BarLabel:GetUnboundedStringWidth() - 8
	ns.Overview.SetBar(card.Bar, 18, 76, room, profession.maxRank > 0 and profession.rank / profession.maxRank or 0)
	card.Heading:SetShown(#profession.recipes > 0)
	for index, row in ipairs(recipes) do
		local recipe = profession.recipes[index]
		row:SetShown(recipe ~= nil)
		if recipe then
			local icon = recipe.itemID and C_Item.GetItemIconByID(recipe.itemID)
				or C_Spell.GetSpellTexture(recipe.spellID)
			Window.SetRingIcon(row.Icon, icon or 134400)
			row.Name:SetText(L.RECIPE_COUNT:format(recipe.name or ItemName(recipe.itemID) or "", recipe.count))
			local color = DIFFICULTY[recipe.color or ""] or DIFFICULTY.grey
			row.Name:SetTextColor(color[1], color[2], color[3])
			row.Detail:SetText(RecipeDetail(recipe))
		end
	end
end

---@param profession AGFSUProfession
local function RefreshSide(profession)
	stepsHeading:SetShown(#profession.steps > 0)
	for index, row in ipairs(steps) do
		local step = profession.steps[index]
		row:SetShown(step ~= nil)
		row.profession, row.step, row.index = profession, step, index
		if step then
			Window.SetStepRow(row, index, step.text, step.detail)
		end
	end
	reagentsHeading:SetShown(#profession.reagents > 0)
	for index, row in ipairs(reagents) do
		local reagent = profession.reagents[index]
		row:SetShown(reagent ~= nil)
		if reagent then
			row.Icon:SetTexture(C_Item.GetItemIconByID(reagent.itemID) or 134400)
			row.Name:SetText(L.REAGENT_NEED:format(reagent.need, ItemName(reagent.itemID) or ""))
			local have = reagent.have or 0
			row.Source:SetText(
				have > 0 and L.REAGENT_HAVE:format(have) or (reagent.source and SOURCES[reagent.source]) or ""
			)
		end
	end
end

---@param content Frame
local function Refresh(content)
	local professions = Integrations.Professions()
	local muted = Muted()
	emptyArt:SetShown(muted ~= nil)
	emptyText:SetShown(muted ~= nil)
	emptyText:SetText(muted or "")
	card:SetShown(muted == nil)
	stepsHeading:SetShown(false)
	reagentsHeading:SetShown(false)
	local profession = muted == nil and Picked(content, professions) or Picked(content, {})
	for _, row in ipairs(steps) do
		row:SetShown(false)
	end
	for _, row in ipairs(reagents) do
		row:SetShown(false)
	end
	if muted == nil then
		---@cast profession -?
		RefreshCard(profession)
		RefreshSide(profession)
	end
end

Window.AddTab({ key = "professions", label = L.TAB_PROFESSIONS, Build = Build, Refresh = Refresh, Muted = Muted })
