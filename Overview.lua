---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- What the map panel's overview and the Adventure Guide window share (docs/design.md §2.2): the kind icons, a card's
-- lines and progress, the first card and the others, and what a click or hover on a card or a step does. Both draw
-- from the same route and choose through the same ns.Choose, so they never disagree.
---@class AGFOverview
local Overview = {}
ns.Overview = Overview

-- Blizzard's QUEST_TAG_ATLAS icons (Blizzard_FrameXMLBase/Constants.lua:514-527); the next zone gets the map's "!",
-- the calling the quest log's class icon from the same sheet (CSV:9385).
local KIND_ICONS = {
	carry = "questlog-questtypeicon-quest",
	story = "questlog-questtypeicon-story",
	nextzone = "QuestNormal",
	dungeon = "questlog-questtypeicon-dungeon",
	calling = "questlog-questtypeicon-class",
	-- The minimap's battlemaster mark (CSV:1319).
	battleground = "battlemaster",
}

---@param step AGFStep
local function FocusStep(step)
	WorldMapFrame:SetMapID(step.map)
	-- The map's data providers (Pins.lua among them) refresh in response to SetMapID; wait a
	-- frame so the pin exists before it's asked to flash.
	C_Timer.After(0, function()
		ns.Pins.Ping(step.key)
	end)
end

---@param owner Frame
---@param lines string[]
local function ShowTooltip(owner, lines)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, lines[1])
	for index = 2, #lines do
		GameTooltip_AddNormalLine(GameTooltip, lines[index])
	end
	GameTooltip:Show()
end

-- A step row's lines: the ring's; a row after step 1 asks Shortest Path for its travel line once, on hover.
---@param self AGFRouteRow
local function RowEnter(self)
	local step, index = self.step, self.index
	if not (step and index) then
		return
	end
	local travel = index == 1 and ns.Integrations.Travel(step) or ns.Integrations.TravelLine(step)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	ns.Pins.StepTooltip(GameTooltip, step, index, travel)
	-- The chosen journey's rows drag into another order (docs/design.md §2.20).
	if ns.Route().chosen then
		GameTooltip_AddInstructionLine(GameTooltip, L.ORDER_DRAG)
	end
	-- Without Shortest Path a step is a waypoint as the crow flies; a wanderer wants neither.
	local hint = not ns.Setting("wanderer") and ns.Companions.Hint("ShortestPathForever")
	if hint then
		GameTooltip_AddInstructionLine(GameTooltip, hint)
	end
	GameTooltip:Show()
end

-- The step's kind at a glance (docs/design.md §2.9), the map's own marks: a pickup's "!", a hand-in's "?", an
-- objective's mark (a dungeon's work too), and the minimap tracking menu's trainer and battlemaster. A town reads as
-- its pickups when it has any, else its hand-ins. Nil for a step the model gave no verb.
local VERB_ATLAS = {
	pickup = "QuestNormal",
	turnin = "QuestTurnin",
	objective = "questobjective",
	battlemaster = "battlemaster",
}
local TRAINER_FILE = "Interface\\Minimap\\Tracking\\Class"

---@param step AGFStep
---@return string? atlas
---@return string? file
local function VerbIcon(step)
	local verb = step.verb
	if verb == "town" then
		return (step.pickups and #step.pickups > 0) and VERB_ATLAS.pickup or VERB_ATLAS.turnin
	elseif verb == "trainer" then
		return nil, TRAINER_FILE
	end
	return verb and VERB_ATLAS[verb] or nil
end

-- The kind's mark on `texture`, hidden when the step has none.
---@param texture Texture
---@param step AGFStep
local function SetVerbIcon(texture, step)
	local atlas, file = VerbIcon(step)
	if atlas then
		texture:SetAtlas(atlas)
	elseif file then
		texture:SetTexture(file)
	end
	texture:SetShown(atlas ~= nil or file ~= nil)
end

-- A step's badge: the kind's mark over its ring's lower right, `size` wide and `out` past the ring's edge, as Shortest
-- Path badges a numbered stop (its Route.lua: BADGE_SIZE 16, BADGE_OFFSET 4 on a 22 ring).
---@param parent Frame
---@param ring Region
---@param size number
---@param out number
---@return Texture
local function CreateBadge(parent, ring, size, out)
	local badge = parent:CreateTexture(nil, "OVERLAY", nil, 1)
	badge:SetSize(size, size)
	badge:SetPoint("BOTTOMRIGHT", ring, "BOTTOMRIGHT", out, -out)
	badge:Hide()
	return badge
end

--[[ Reordering the chosen journey (docs/design.md §2.20): the right-click menu's Do this next, sooner and later, and a
     drag from one row onto another with the stock move cursor. Order.lua says which moves keep the route whole; a
     row it would not take is dimmed while the drag lasts, and nothing moves but the step dragged. ]]

local DRAG_CURSOR = "Interface\\CURSOR\\UI-Cursor-Move"
local DIMMED = 0.35

-- After the step menu (Menu.lua), the chosen journey's order: each move greyed where Order.lua refuses it, the way
-- back while the order is the player's, and a town's givers still to see, a skip each.
---@param root SharedMenuDescriptionProxy
---@param step AGFStep
---@param index? integer
local function OrderEntries(root, step, index)
	local Order = ns.Order
	if not (index and ns.Route().chosen) then
		return
	end
	root:CreateDivider()
	for _, move in ipairs({ { L.ORDER_NEXT, 1 }, { L.ORDER_SOONER, index - 1 }, { L.ORDER_LATER, index + 1 } }) do
		local to = move[2]
		local button = root:CreateButton(move[1], function()
			Order.Move(index, to)
		end)
		button:SetEnabled(to >= 1 and Order.CanMove(index, to))
	end
	if Order.IsCustom() then
		root:CreateButton(L.ORDER_RESET, Order.Reset)
	end
	local open = {}
	for _, giver in ipairs(step.checklist or {}) do
		open[#open + 1] = not (giver.done or giver.skipped) and giver or nil
	end
	if #open > 0 then
		local skip = root:CreateButton(L.TOWN_SKIP_GIVER)
		for _, giver in ipairs(open) do
			skip:CreateButton(giver.name, function()
				Order.SkipGiver(step.key, giver.key)
			end)
		end
	end
end

-- A step row's right-click: the step menu, then its order.
---@param owner Region
---@param step AGFStep
---@param index? integer
local function StepMenu(owner, step, index)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag("MENU_ADVENTURE_GUIDE_FOREVER_STEP")
		ns.Menu.Step(root, step)
		OrderEntries(root, step, index)
	end)
end

---@class AGFDraggableRow : Button
---@field step? AGFStep
---@field index? integer

-- Lets a row of `rows` be dragged onto another; `redraw` puts every row's own alpha back once the drag ends.
---@param row AGFDraggableRow
---@param rows AGFDraggableRow[]
---@param redraw fun()
local function Draggable(row, rows, redraw)
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function(self)
		if not (self.index and ns.Route().chosen) then
			return
		end
		GameTooltip_Hide()
		SetCursor(DRAG_CURSOR)
		for _, other in ipairs(rows) do
			if other ~= self and other.index and other:IsShown() and not ns.Order.CanMove(self.index, other.index) then
				other:SetAlpha(DIMMED)
			end
		end
	end)
	row:SetScript("OnDragStop", function(self)
		ResetCursor()
		local target
		for _, other in ipairs(rows) do
			if other ~= self and other.index and other:IsShown() and other:IsMouseOver() then
				target = other
			end
		end
		redraw()
		if self.index and target and ns.Order.CanMove(self.index, target.index) then
			ns.Order.Move(self.index, target.index)
		end
	end)
end

--[[ A town's checklist (docs/design.md §2.9): a line a giver under the town's row, ticked once done as the tracker
     ticks an objective; a giver skipped for now greys out with no tick. ]]

local CHECK_HEIGHT, CHECK_ICON = 14, 12

---@class AGFCheckLine : Frame
---@field Tick Texture
---@field Text FontString

---@param parent Frame
---@return AGFCheckLine
local function CreateCheckLine(parent)
	local line = CreateFrame("Frame", nil, parent) --[[@as AGFCheckLine]]
	line:SetHeight(CHECK_HEIGHT)
	line.Tick = line:CreateTexture(nil, "ARTWORK")
	line.Tick:SetSize(CHECK_ICON, CHECK_ICON)
	line.Tick:SetPoint("LEFT")
	line.Text = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	line.Text:SetPoint("LEFT", CHECK_ICON + 4, 0)
	line.Text:SetPoint("RIGHT")
	line.Text:SetJustifyH("LEFT")
	line.Text:SetWordWrap(false)
	return line
end

-- `step`'s checklist in `pool`'s lines from `first` on (made as needed on `parent`), from `top` down, `left` in and
-- `width` wide, while a line ends above `bottom`. Returns the top under the last line and the next free line.
---@param pool AGFCheckLine[]
---@param first integer
---@param parent Frame
---@param step AGFStep
---@param left number
---@param top number
---@param width number
---@param bottom? number
---@return number top
---@return integer next
local function LayoutChecklist(pool, first, parent, step, left, top, width, bottom)
	local index = first
	for _, giver in ipairs(step.checklist or {}) do
		if bottom and top + CHECK_HEIGHT > bottom then
			break
		end
		local line = pool[index] or CreateCheckLine(parent)
		pool[index] = line
		line:SetWidth(width)
		line:SetPoint("TOPLEFT", left, -top)
		line.Tick:SetAtlas(giver.done and "UI-QuestTracker-Tracker-Check" or "UI-QuestTracker-Objective-Nub")
		line.Tick:SetAlpha(giver.skipped and 0.4 or 1)
		line.Text:SetText(giver.text)
		local shade = (giver.done or giver.skipped) and 0.6 or 0.9
		line.Text:SetTextColor(shade, shade, shade)
		line:Show()
		top, index = top + CHECK_HEIGHT, index + 1
	end
	return top, index
end

-- Hides `pool`'s lines from `from` on.
---@param pool AGFCheckLine[]
---@param from integer
local function HideChecklist(pool, from)
	for index = from, #pool do
		pool[index]:Hide()
	end
end

-- A quest in the log opens its details; any other step turns the map to it. Right-click is the step menu and order.
---@param self AGFRouteRow
---@param mouseButton string
local function RowClick(self, mouseButton)
	if not self.step then
		return
	end
	if mouseButton == "RightButton" then
		StepMenu(self, self.step, self.index)
	elseif not ns.ShowQuest(self.step) then
		FocusStep(self.step)
	end
end

-- Choosing a journey shows its route and turns the map to it, and with the setting on starts it (ns.Choose, once the
-- rebuild has its steps). The map turns before the invalidation, so its redraw reads the route as it is and the one
-- rebuild waits a frame. The chosen card is no toggle: the header's back arrow goes back to the overview and the
-- footer's Stop stops the route, so a click on it only turns the map to it again, or resumes its route while that is
-- paused. Right-click offers "Not interested", except on what the player carries.
---@param self AGFCardButton
---@param mouseButton string
local function CardClick(self, mouseButton)
	local journey = self.journey
	if not journey then
		return
	end
	if mouseButton == "RightButton" then
		if journey.kind ~= "carry" then
			GameTooltip_Hide()
			ns.Menu.Journey(self, journey)
		end
		return
	end
	if self.state == "chosen" and ns.Paused() then
		ns.StartRoute()
	elseif self.state == "chosen" then
		WorldMapFrame:SetMapID(journey.map)
	else
		WorldMapFrame:SetMapID(journey.map)
		ns.Choose(journey.key, ns.Setting("titleStartsRoute"))
	end
	-- Its tooltip spoke for the state the click just left.
	GameTooltip_Hide()
end

-- A card's first stop and how many stops follow it, its third line when it has no reason.
---@param journey AGFJourney
---@return string?
local function HubLine(journey)
	local more = journey.more or 0
	if not journey.hub then
		return nil
	end
	return (more > 1 and L.HUB_MORE:format(journey.hub, more))
		or (more == 1 and L.HUB_MORE_ONE:format(journey.hub))
		or journey.hub
end

-- The log-full note (docs/design.md §2.18) on the card that has it: how many quests could go.
---@param journey AGFJourney
---@return string?
local function DropLine(journey)
	local drop = journey.drop and #journey.drop or 0
	return (drop == 1 and L.LOG_FULL_ONE) or (drop > 1 and L.LOG_FULL:format(drop)) or nil
end

-- The dungeon card's way in (docs/design.md §2.19): Tweaks Forever's entrance for its instance (a Map.ID), else the
-- line saying why there is none. Nil for any other card.
---@param journey AGFJourney
---@return integer? instance
---@return AGFPoint? point
---@return string? note
local function Entrance(journey)
	local instance = journey.kind == "dungeon" and tonumber(journey.key:match("^dungeon:(%d+)$"))
	if not instance then
		return nil
	end
	local point, reason = ns.Providers.DungeonEntrance(instance)
	local note = not point
		and (
			(reason == "missing" and L.TWEAKS_MISSING)
			or (reason == "outdated" and L.TWEAKS_OUTDATED)
			or L.ENTRANCE_UNKNOWN
		)
	return instance, point, note or nil
end

-- Every card's tooltip, whole or one-line: its lines, the hub line when line 3 holds the reason
-- or is folded away, how many quests need a group, the quests the log-full note means, then what a click does. The
-- chosen card points to the back arrow; a card whose click would replace someone else's journey warns
-- first, as Go did (docs/design.md §2.9).
---@param card AGFCardButton
local function CardTooltip(card)
	local journey = card.journey
	if not journey then
		return
	end
	local starts = ns.Setting("titleStartsRoute")
	local chosen = card.state == "chosen"
	GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, journey.title)
	GameTooltip_AddNormalLine(GameTooltip, journey.subline)
	if journey.reason then
		GameTooltip_AddHighlightLine(GameTooltip, journey.reason)
	end
	local hub = HubLine(journey)
	if hub and (journey.reason or journey.drop or card.state == "compact" or card.detail == hub) then
		GameTooltip_AddHighlightLine(GameTooltip, hub)
	end
	if card.detail and card.detail ~= journey.reason and card.detail ~= journey.subline and card.detail ~= hub then
		GameTooltip_AddHighlightLine(GameTooltip, card.detail)
	end
	local travel = ns.Integrations.CardTravel(journey)
	if travel and travel.line then
		GameTooltip_AddHighlightLine(GameTooltip, travel.line)
	end
	local group = journey.group or 0
	if group > 0 then
		GameTooltip_AddHighlightLine(GameTooltip, group == 1 and L.GROUP_ONE or L.GROUP_MANY:format(group))
	end
	local _, _, note = Entrance(journey)
	if note then
		GameTooltip_AddNormalLine(GameTooltip, note)
	end
	if journey.drop then
		local log = ns.State.Log()
		GameTooltip_AddNormalLine(GameTooltip, L.LOG_FULL_LIST)
		for _, id in ipairs(journey.drop) do
			local entry = log[id]
			GameTooltip_AddHighlightLine(GameTooltip, entry and entry.title or ns.Data.quests[id].title)
		end
	end
	local resumes = chosen and ns.Paused()
	if not chosen then
		GameTooltip_AddInstructionLine(GameTooltip, L.CLICK_TO_CHOOSE)
	elseif resumes then
		GameTooltip_AddInstructionLine(GameTooltip, L.CLICK_TO_RESUME)
	end
	if chosen then
		GameTooltip_AddInstructionLine(GameTooltip, L.BACK_TO_ALL)
	end
	if (resumes or not chosen and starts) and ns.Integrations.ReplacesJourney() then
		GameTooltip_AddInstructionLine(GameTooltip, L.REPLACES_JOURNEY)
	end
	if journey.kind ~= "carry" then
		GameTooltip_AddInstructionLine(GameTooltip, L.RIGHT_CLICK_NOT_INTERESTED)
	end
	GameTooltip:Show()
end

-- How far a journey has come, when it has come some way: a story's chapters done of a chain the data proves the length
-- of, Loose ends' quests ready of all it holds. The bar's value and the grid footer's words.
---@param journey AGFJourney
---@return number? value
---@return string? label
local function Progress(journey)
	local story = journey.story
	if story and story.total and story.chapter > 1 then
		return (story.chapter - 1) / story.total, L.CHAPTERS_DONE:format(story.chapter - 1, story.total)
	end
	local ready, underway = journey.ready or 0, journey.underway or 0
	if journey.kind == "carry" and ready > 0 then
		return ready / (ready + underway), L.READY_OF:format(ready, ready + underway)
	end
end

-- The zone icon's centre: the card's first town on its zone, else its first stop.
---@param journey AGFJourney
---@return AGFStep?
local function IconStep(journey)
	for _, step in ipairs(journey.steps) do
		if step.kind == "town" and step.map == journey.map then
			return step
		end
	end
	return journey.steps[1]
end

-- A grid card's footer when it has come no way: the level a zone to head to fits, else how many stops it has.
---@param journey AGFJourney
---@return string
local function Stops(journey)
	local stops = journey.more and journey.more + 1 or #journey.steps
	return stops == 1 and L.STOPS_ONE or L.STOPS:format(stops)
end

-- The featured card's counts, after the map's own turn-in and quest marks.
local READY_MARK, UNDERWAY_MARK, COUNT_GAP = "|A:QuestTurnin:12:12|a ", "|A:QuestNormal:12:12|a ", "  "

-- The featured card's line of counts, with the map's marks; its subline when it has none.
---@param journey AGFJourney
---@return string
local function Counts(journey)
	local ready, underway, counts = journey.ready or 0, journey.underway or 0, {}
	counts[#counts + 1] = ready > 0 and READY_MARK .. L.CARRY_READY:format(ready) or nil
	counts[#counts + 1] = underway > 0 and UNDERWAY_MARK .. L.CARRY_IN_PROGRESS:format(underway) or nil
	return #counts > 0 and table.concat(counts, COUNT_GAP) or journey.subline
end

-- The overview's split with no card chosen: the card the route follows, else the first, and the others in order.
---@param route AGFRoute
---@return AGFJourney? first
---@return AGFJourney[] others
local function Split(route)
	local first, others = nil, {}
	for _, journey in ipairs(route.journeys) do
		if not first and journey.key == route.journey then
			first = journey
		else
			others[#others + 1] = journey
		end
	end
	-- The route follows the first card while none is chosen; one it does not name is the first all the same.
	if not first and #others > 0 then
		first = table.remove(others, 1)
	end
	return first, others
end

-- A step on the world map: the map opens when it is closed, then turns to the step and flashes its ring.
---@param step AGFStep
local function ShowOnMap(step)
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	FocusStep(step)
end

-- The Journeys renown bar is 18 tall at its own scale, too tall for a card: its frame is scaled to draw it 7 tall.
local BAR_HEIGHT, BAR_ART = 7, 18

---@class AGFProgressBar : Frame
---@field Fill Texture

---@param parent Frame
---@return AGFProgressBar
local function CreateBar(parent)
	local bar = CreateFrame("Frame", nil, parent) --[[@as AGFProgressBar]]
	bar:SetScale(BAR_HEIGHT / BAR_ART)
	bar:SetHeight(BAR_ART)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAtlas("UI-Journeys-renown-progressbar-BG")
	back:SetAllPoints()
	bar.Fill = bar:CreateTexture(nil, "ARTWORK")
	bar.Fill:SetAtlas("UI-Journeys-renown-progressbar-fill")
	bar.Fill:SetPoint("TOPLEFT")
	bar.Fill:SetPoint("BOTTOMLEFT")
	local rim = bar:CreateTexture(nil, "OVERLAY")
	rim:SetAtlas("UI-Journeys-renown-progressbar-frame")
	rim:SetAllPoints()
	return bar
end

-- The bar `width` wide at (x, y) in its card, filled to `value` (0-1]; a scaled frame's offsets and size are in its
-- own units. An empty bar hides its fill: the client takes a width of 0 as unset, and the fill, anchored by its left
-- edge only, would then draw at its atlas's own width, far past the bar.
---@param bar AGFProgressBar
---@param x number
---@param y number
---@param width number
---@param value number
---@param height? number drawn this tall, BAR_HEIGHT by default
local function SetBar(bar, x, y, width, value, height)
	local scale = (height or BAR_HEIGHT) / BAR_ART
	bar:SetScale(scale)
	bar:SetWidth(width / scale)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", x / scale, -y / scale)
	local fill = width / scale * math.min(value, 1)
	bar.Fill:SetShown(fill > 0)
	if fill > 0 then
		bar.Fill:SetWidth(fill)
	end
	bar:Show()
end

-- A rebuild redraws a hovered card's tooltip only while the card is on screen and the tooltip still up: a card that
-- closed with the map or window has no OnLeave to clear its ownership, and redrawing it would leave the tooltip
-- floating where the card was.
---@param card AGFCardButton
local function RefreshCardTooltip(card)
	if card:IsVisible() and GameTooltip:IsShown() and GameTooltip:IsOwned(card) then
		CardTooltip(card)
	end
end

-- Hiding a frame fires no OnLeave on the one under the pointer, so the tooltip goes when it belongs to `root` or
-- anything inside it; another addon's tooltip stays.
---@param root Frame
local function HideTooltipWithin(root)
	local owner = GameTooltip:GetOwner()
	while owner do
		if owner == root then
			GameTooltip:Hide()
			return
		end
		owner = owner:GetParent()
	end
end

Overview.KIND_ICONS = KIND_ICONS
Overview.SetVerbIcon = SetVerbIcon
Overview.CreateBadge = CreateBadge
Overview.StepMenu = StepMenu
Overview.Draggable = Draggable
Overview.LayoutChecklist = LayoutChecklist
Overview.HideChecklist = HideChecklist
Overview.Entrance = Entrance
Overview.CreateBar = CreateBar
Overview.SetBar = SetBar
Overview.FocusStep = FocusStep
Overview.ShowOnMap = ShowOnMap
Overview.ShowTooltip = ShowTooltip
Overview.RowEnter = RowEnter
Overview.RowClick = RowClick
Overview.CardClick = CardClick
Overview.CardTooltip = CardTooltip
Overview.RefreshCardTooltip = RefreshCardTooltip
Overview.HideTooltipWithin = HideTooltipWithin
Overview.HubLine = HubLine
Overview.DropLine = DropLine
Overview.Progress = Progress
Overview.IconStep = IconStep
Overview.Stops = Stops
Overview.Split = Split
Overview.Counts = Counts
