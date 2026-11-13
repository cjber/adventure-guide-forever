---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

local PIN_TEMPLATE = "AdventureGuideForeverPinTemplate"
local GIVER_TEMPLATE = "AdventureGuideForeverGiverPinTemplate"
local SPOT_TEMPLATE = "AdventureGuideForeverSpotPinTemplate"
local PING_TEMPLATE = "AdventureGuideForeverPingPinTemplate"
-- Warm gold route markers keep future stops readable against the map.
local LATER_STOP_ALPHA = 0.7
local NONE = {}
local MAP_GROUP_SIZE = 32
local BADGE_SIZE, BADGE_OFFSET = 16, 4
-- A town visit's NPC and object marks, smaller than its numbered stop.
local SPOT_ICON = 14

---@class AGFPinsModule
local Pins = {}
ns.Pins = Pins

---@type table<string, true>
local minimapOwner = {}
local minimapIcons = {}
local RingsShown, MarkerTooltip

---@class AGFMinimapIcon : Frame
---@field marker Texture
---@field visits AGFPinVisit[]
---@field Stack? Texture

---@param eligible fun(step: AGFStep): boolean
---@param close fun(first: AGFStep, step: AGFStep, firstX: number, firstY: number, x: number, y: number): boolean
---@param space? fun(step: AGFStep): integer, number, number the grouping map and point, defaulting to the step's own
---@return AGFPinVisit[][]
local function Groups(eligible, close, space)
	space = space or function(step)
		return step.map, step.x, step.y
	end
	local groups = {}
	for index, step in ipairs(ns.Route().steps) do
		if eligible(step) then
			local map, x, y = space(step)
			local group
			for _, visits in ipairs(groups) do
				local first = visits[1].step
				local firstMap, firstX, firstY = space(first)
				if
					firstMap == map
					and (
						first.key == step.key
						or (first.kind == "town" and step.kind == "town" and first.hub and first.hub == step.hub)
						or (x ~= nil and firstX ~= nil and firstX == x and firstY == y)
						or ((step.preview or first.preview) and close(first, step, firstX, firstY, x, y))
					)
				then
					group = visits
					break
				end
			end
			if not group then
				group = {}
				groups[#groups + 1] = group
			end
			group[#group + 1] = { step = step, index = index }
		end
	end
	return groups
end

-- One NPC or object a town visit covers: where it stands and what the visit does there.
---@class AGFVisitSpot
---@field map integer
---@field x number
---@field y number
---@field name string the NPC's or object's name
---@field pickups integer[] quest IDs picked up there
---@field handins integer[] quest IDs handed in there

-- The town visits' spots on `mapID`, the points numbered stops already stand on left to those pins: one mark per NPC
-- or object, carrying every quest the route does there. The first visit that comes there sets the mark's fade.
---@class AGFSpotPinRow : AGFVisitSpot
---@field index integer the route index of the first visit that comes there

---@param mapID integer
---@param numbered table<string, true>
---@return AGFSpotPinRow[]
local function VisitSpotRows(mapID, numbered)
	local rows, byKey = {}, {}
	local function Add(id, into)
		for _, old in ipairs(into) do
			if old == id then
				return
			end
		end
		into[#into + 1] = id
	end
	for index, step in ipairs(ns.Route().steps) do
		if step.kind == "town" and step.map == mapID and not step.here then
			for _, list in ipairs({ "handins", "pickups" }) do
				for _, id in ipairs(step[list] or NONE) do
					local place = step.spots and step.spots[id]
					if place and place.map == mapID and not numbered[ns.Model.SpotKey(place)] then
						local key = ns.Model.SpotKey(place) .. ":" .. place.name
						local row = byKey[key]
						if not row then
							row = {
								map = place.map,
								x = place.x,
								y = place.y,
								name = place.name,
								pickups = {},
								handins = {},
								index = index,
							}
							byKey[key], rows[#rows + 1] = row, row
						end
						Add(id, row[list])
					end
				end
			end
		end
	end
	return rows
end

-- A minimap step marker's side in pixels; also the spacing under which nearby steps share one marker.
local MINIMAP_ICON = 24

-- As the minimap's own buttons (Blizzard_Minimap Minimap.lua): the tooltip to the left, toward the screen.
---@param icon AGFMinimapIcon
local function MinimapIconEnter(icon)
	if not icon.visits then
		return
	end
	GameTooltip:SetOwner(icon, "ANCHOR_LEFT")
	MarkerTooltip(GameTooltip, icon.visits)
	GameTooltip:Show()
end

---@param icon AGFMinimapIcon
local function MinimapIconLeave(icon)
	if GameTooltip:GetOwner() == icon then
		GameTooltip:Hide()
	end
end

local function RefreshMinimap()
	local pins = LibStub and LibStub:GetLibrary("HereBeDragons-Pins-2.0", true)
	if not pins then
		return
	end
	pins:RemoveAllMinimapIcons(minimapOwner)
	for _, icon in ipairs(minimapIcons) do
		icon:Hide()
	end
	if
		not (RingsShown() or (ns.Integrations.Guiding() and not ns.Setting("wanderer")))
		or not (ns.Route().steps[1] and ns.Route().steps[1].rxpIndex)
	then
		return
	end
	local radius = C_Minimap.GetViewRadius()
	local reach = radius * 2 * MINIMAP_ICON / math.max(1, Minimap:GetWidth())
	local groups = Groups(function(step)
		return step.map > 0 and not step.here and step.x >= 0 and step.x <= 1 and step.y >= 0 and step.y <= 1
	end, function(_, step, firstX, firstY, x, y)
		local map = ns.Data.maps[step.map]
		return map ~= nil
			and map.sx ~= nil
			and map.sy ~= nil
			and math.abs(firstX - x) * map.sx <= reach
			and math.abs(firstY - y) * map.sy <= reach
	end)
	for slot, visits in ipairs(groups) do
		local step, index = visits[1].step, visits[1].index
		do
			local icon = minimapIcons[slot]
			if not icon then
				icon = CreateFrame("Frame") --[[@as AGFMinimapIcon]]
				icon:SetSize(MINIMAP_ICON, MINIMAP_ICON)
				icon:SetFrameStrata("MEDIUM")
				-- Hover only, set once outside combat (Refresh never draws in it): clicks fall through to the minimap,
				-- which pings as before. A plain frame of ours, so its scripts touch nothing protected.
				icon:EnableMouse(false)
				icon:SetMouseMotionEnabled(true)
				icon:SetScript("OnEnter", MinimapIconEnter)
				icon:SetScript("OnLeave", MinimapIconLeave)
				local texture = icon:CreateTexture(nil, "ARTWORK")
				ns.Art.SetStepMarker(texture, index, MINIMAP_ICON)
				texture:SetPoint("CENTER")
				icon.marker = texture
				minimapIcons[slot] = icon
			end
			ns.Art.SetStepMarker(icon.marker, index, MINIMAP_ICON)
			icon.marker:SetAlpha(index == 1 and 1 or LATER_STOP_ALPHA)
			icon.visits = visits
			if not icon.Stack then
				icon.Stack = icon:CreateTexture(nil, "BACKGROUND")
				ns.Art.SetStepRing(icon.Stack, MINIMAP_ICON)
				icon.Stack:SetPoint("CENTER", 3, -3)
				icon.Stack:SetAlpha(0.7)
			end
			icon.Stack:SetShown(#visits > 1)
			icon:Show()
			pins:AddMinimapIconMap(minimapOwner, icon, step.map, step.x, step.y, true, false)
		end
	end
end

-- One switch over every mark AGF draws (design §2.6): nothing unless showMapPins is on, and nothing for a wanderer
-- who is told where and never shown. While Polestar guides (Polestar.lua) the switch draws nothing.
-- While the guide is open the markers preview the route it shows whatever the switch says: the chosen journey's,
-- else the first card's, which the guide draws on its own (docs/design.md §2.2). Either way they step aside while
-- Shortest Path guides, since it numbers its stops itself.
---@return boolean
RingsShown = function()
	local preview = ns.PanelShown ~= nil and ns.PanelShown()
	local first = ns.Route().steps[1]
	local guideActive = first ~= nil and first.rxpIndex ~= nil
	return (preview or (ns.Setting("showMapPins") and not ns.Polestar.Active()))
		and (not ns.Integrations.Guiding() or guideActive)
		and not ns.Setting("wanderer")
end

-- Questie draws available-quest icons on the world map only while all three of its switches are on: `enabled` (its
-- hide/show toggle) plus `enableMapIcons` and `enableAvailable`
-- (Questie/Modules/Map/QuestieMap.lua:604-611, Modules/Options/IconsTab/QuestieOptionsIcons.lua). While it does, it
-- owns the background giver markers. A Questie whose profile is not built yet counts as the owner too, so its startup
-- shows no duplicates.
---@return boolean
local function QuestieOwnsGivers()
	if not C_AddOns.IsAddOnLoaded("Questie") then
		return false
	end
	local db = Questie and Questie.db
	local profile = type(db) == "table" and db.profile
	if type(profile) ~= "table" then
		return true
	end
	return profile.enabled ~= false and profile.enableMapIcons ~= false and profile.enableAvailable ~= false
end

-- Questie redraws its own map notes through QuestieQuest:ToggleNotes when the player flips its hide/show switch, and
-- who owns the giver markers moves with it. Hooked once, through its loader (Core/State.lua guards the same global),
-- from the first refresh after Questie is ready: the route rebuilds then, so a refresh always follows.
local questieHooked = false
local function HookQuestieToggle()
	if questieHooked or not (Questie and Questie.API and Questie.API.isReady) then
		return
	end
	local loader = QuestieLoader
	if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
		return
	end
	local ok, module = pcall(loader.ImportModule, loader, "QuestieQuest")
	if not (ok and type(module) == "table" and type(module.ToggleNotes) == "function") then
		return
	end
	questieHooked = true
	hooksecurefunc(module, "ToggleNotes", function() -- taint-ok: Questie's own module, not a Blizzard frame.
		Pins.Refresh()
	end)
end

-- Questie owns background giver markers while it shows them on the world map; when its icons, map icons or
-- available-quest icons are off, AGF draws its own givers under its own "Show quest givers" setting. Without Questie,
-- givers stay while Shortest Path guides: it draws no givers of its own.
---@return boolean
local function GiversShown()
	return not QuestieOwnsGivers()
		and ns.Setting("showMapPins")
		and ns.Setting("showQuestGivers")
		and not ns.Setting("wanderer")
		and not ns.Polestar.Active()
end

---@param tooltip GameTooltip
local function AddClickLine(tooltip)
	GameTooltip_AddInstructionLine(tooltip, ns.Menu.ClickLine())
end

-- The map's own marks, inline: a hand-in's "?", a pickup's "!", and the quest log's group tag.
local HAND_IN_ICON = ns.Art.Markup("questturnin", 14) .. " "
local PICK_UP_ICON = ns.Art.Markup("questnormal", 14) .. " "
local GROUP_ICON = " " .. ns.Art.Markup("questlog-questtypeicon-group", 12)
-- A town's quests listed in its tooltip; the rest are counted.
local HUB_QUEST_LINES = 8

-- Known levels appear on pickup, objective and turn-in lines alike; uncached quests never invent a level.
---@param tooltip GameTooltip
---@param id integer
---@param mark string
local function QuestLine(tooltip, id, mark)
	local title, color, group = Pins.QuestLineText(id)
	GameTooltip_AddColoredLine(
		tooltip,
		mark .. title .. (group and GROUP_ICON or ""),
		CreateColor(color.r, color.g, color.b)
	)
end

-- Shared quest title/level logic for AGF tooltips and the optional Shortest Path stop detail.
---@param id integer
---@return string title, table color, boolean group
function Pins.QuestLineText(id)
	local quest = ns.Data.quests[id]
	local level = C_QuestLog.GetQuestDifficultyLevel(id)
	if not level or level <= 0 then
		level = quest and (quest.level == -1 and ns.State.Level() or quest.level)
	end
	local title = ns.State.QuestTitle(id) or (quest and quest.title) or ""
	local known = level and level > 0
	local color = known and GetQuestDifficultyColor(level) or NORMAL_FONT_COLOR
	if known and not title:match("^%[%d+%+?%]") then
		title = ns.L.QUEST_LEVEL:format(level, title)
	end
	local group = quest and (quest.elite or quest.dungeon or quest.raid) and true or false
	return title, color, group
end

local function ColorTitle(title, color)
	return ns.StepStyle.Wrap(CreateColor(color.r, color.g, color.b), title)
end

---@param step AGFStep|AGFGiver
---@return string?
function Pins.StopTooltip(step)
	local lines = {}
	for _, id in ipairs(step.quests) do
		local title, color = Pins.QuestLineText(id)
		if title ~= "" then
			lines[#lines + 1] = ColorTitle(title, color)
			local story = ns.Model.Story(ns.Data, id)
			if story and story.total then
				lines[#lines + 1] = ns.L.CHAPTER_OF:format(story.chapter, story.total)
				local nextID = story.members[story.chapter + 1]
				if nextID then
					local nextTitle, nextColor = Pins.QuestLineText(nextID)
					local nextQuest = ns.Data.quests[nextID]
					local nextLevel = nextQuest and nextQuest.min
					if nextLevel and nextLevel > 0 and nextLevel > ns.State.Level() then
						lines[#lines + 1] = ns.L.CONTINUES_AT_LEVEL:format(nextLevel, ColorTitle(nextTitle, nextColor))
					else
						lines[#lines + 1] = ns.L.THEN:format(ColorTitle(nextTitle, nextColor))
					end
				end
			end
		end
	end
	return #lines > 0 and table.concat(lines, "\n") or nil
end

-- One line per quest at a town, under the NPC it is handed to or taken from, in the town's order (hand-ins first, then
-- by level).
---@param tooltip GameTooltip
---@param step AGFStep
local function TownQuests(tooltip, step)
	local handin, shown = {}, 0
	for _, id in ipairs(step.handins or {}) do
		handin[id] = true
	end
	for _, giver in ipairs(step.givers or {}) do
		local named = false
		for _, id in ipairs(step.quests) do
			local spot, quest = step.spots and step.spots[id], ns.Data.quests[id]
			if quest and spot and spot.name == giver then
				if shown == HUB_QUEST_LINES then
					GameTooltip_AddHighlightLine(tooltip, ns.L.HUB_MORE_QUESTS:format(#step.quests - shown))
					return
				end
				if not named then
					GameTooltip_AddNormalLine(tooltip, ns.StepStyle.Step(step, giver))
					named = true
				end
				shown = shown + 1
				QuestLine(tooltip, id, handin[id] and HAND_IN_ICON or PICK_UP_ICON)
			end
		end
	end
end

-- An area's quests, each with its open objectives done there as the quest log words them: the client's words, else
-- its count so far. An objective the client's count can't be matched to shows under its quest with no line.
---@param tooltip GameTooltip
---@param step AGFStep
local function AreaObjectives(tooltip, step)
	local last
	for _, objective in ipairs(step.objectives or {}) do
		if objective.id ~= last then
			QuestLine(tooltip, objective.id, "")
			last = objective.id
		end
		-- A count only when one is known: a needed count of 0 is a kind the client does not tally, and "2/0" says nothing.
		local text = ns.Model.ObjectiveText(objective)
		local line = text and ns.StepStyle.Step(step, ns.L.OBJECTIVE_LINE:format(text))
		if line then
			GameTooltip_AddHighlightLine(tooltip, line)
		end
	end
end

-- A guide step's checklist as the tracker words it ("Talk to Iverron", "Turn in Iverron's Antidote"), done lines
-- greyed, then the quests it touches that no objective line below names already.
---@param tooltip GameTooltip
---@param step AGFStep
local function GuideLines(tooltip, step)
	for _, item in ipairs(step.checklist or {}) do
		if item.done then
			GameTooltip_AddColoredLine(tooltip, item.text, GRAY_FONT_COLOR)
		else
			GameTooltip_AddHighlightLine(tooltip, ns.StepStyle.Checklist(step, item))
		end
	end
	local named = {}
	for _, objective in ipairs(step.objectives or {}) do
		named[objective.id] = true
	end
	for _, id in ipairs(step.quests) do
		if not named[id] then
			QuestLine(tooltip, id, "")
		end
	end
end

-- A step's lines (docs/design.md §2.9), shared by its map marker and its row in the guide: the title numbered as the
-- route numbers it, the chapter, the travel line when there is one, why it is on the route, why it wants a group
-- (§2.27), a town's quests by NPC, and an area's objectives.
---@param tooltip GameTooltip
---@param step AGFStep
---@param index number
---@param travel? string
function Pins.StepTooltip(tooltip, step, index, travel)
	GameTooltip_SetTitle(tooltip, ns.StepStyle.StepTitle(step, ns.L.STEP_NUMBERED:format(index, step.title)))
	if step.chapter then
		GameTooltip_AddNormalLine(tooltip, ns.StepStyle.Step(step, step.chapter))
	end
	if travel then
		GameTooltip_AddHighlightLine(tooltip, travel)
	end
	-- A guide step's reason is empty: its checklist below says what to do.
	if step.reason ~= "" then
		GameTooltip_AddHighlightLine(tooltip, ns.StepStyle.Step(step, step.reason))
	end
	for _, note in ipairs(ns.Overview.GroupNotes(step)) do
		GameTooltip_AddNormalLine(tooltip, note)
	end
	if step.kind == "town" then
		TownQuests(tooltip, step)
	elseif step.kind == "turnin" or step.kind == "bookhandin" then
		for _, id in ipairs(step.quests) do
			QuestLine(tooltip, id, HAND_IN_ICON)
		end
	elseif step.rxpIndex then
		GuideLines(tooltip, step)
	end
	AreaObjectives(tooltip, step)
end

-- What a step marker says on hover, on the world map and the minimap alike: the first visit's lines, then every visit
-- when the route comes back to the place.
---@param tooltip GameTooltip
---@param visits AGFPinVisit[]
MarkerTooltip = function(tooltip, visits)
	local first = visits[1]
	Pins.StepTooltip(tooltip, first.step, first.index, ns.Integrations.Travel(first.step))
	if #visits > 1 then
		for _, visit in ipairs(visits) do
			GameTooltip_AddNormalLine(tooltip, ns.L.STOP_VISIT:format(visit.index, visit.step.title))
		end
	end
end

---@type WorldMapFrame?
local map
---@type ForeverCanvasPool?, ForeverCanvasPool?, ForeverCanvasPool?, ForeverCanvasPool?
local routePool, giverPool, spotPool, pingPool
---@type AGFPoint|AGFPlace|AGFStep|AGFGiver?
local reveal
local afterCombat = CreateFrame("Frame")

-- The world map's own quest pins repeat a journey's stops (#468): QuestDataProvider's QuestPinTemplate draws a "..."
-- or "?" circle for each quest on the map, so a quest a numbered stop already marks reads twice. The pass below hides
-- only those pins, one per quest at a stop drawn on the map shown, and brings every pin back when its stop goes. It
-- reads each pin's quest ID field, calls no pin method but Hide and Show, and leaves the questPOI setting and the data
-- provider as the player set them (WFA-38).
local QUEST_PINS = "QuestPinTemplate"
-- The events QuestDataProvider refreshes its pins on, plus SUPER_TRACKING_CHANGED; CVAR_UPDATE counts only for
-- questPOI.
local PROVIDER_EVENTS = {
	"QUEST_LOG_UPDATE",
	"QUEST_WATCH_LIST_CHANGED",
	"QUEST_POI_UPDATE",
	"SUPER_TRACKING_CHANGED",
	"CVAR_UPDATE",
}
-- The pins this pass hid, so it shows only those again: a pin another addon hid is never ours to show.
---@type table<AGFQuestPin, true>
local hiddenPins = setmetatable({}, { __mode = "k" })

-- The quests whose game pins a numbered stop on `mapID` marks, kept while the route, the map and the marker switch
-- stay as they were: a quest-log event then runs no walk of the route's steps and allocates nothing (WFA-13). A stop
-- the player stands in draws no numbered marker, so its quests keep their pins; RingsShown already leaves a
-- wanderer's map alone.
---@type AGFRoute?, integer?, boolean?, table<integer, true>?
local markedRoute, markedMap, markedRings, markedQuests
---@param mapID integer
---@return table<integer, true>
local function MarkedQuests(mapID)
	local route, rings = ns.Route(), RingsShown()
	if markedRoute == route and markedMap == mapID and markedRings == rings then
		return markedQuests --[[@as table<integer, true>]]
	end
	local marked = {}
	if rings then
		for _, step in ipairs(route.steps) do
			if step.map == mapID and not step.here then
				for _, id in ipairs(step.quests or NONE) do
					marked[id] = true
				end
			end
		end
	end
	markedRoute, markedMap, markedRings, markedQuests = route, mapID, rings, marked
	return marked
end

-- The pins one pass walked, cleared at its end so the next pass reuses the table: a quest-log event's pass allocates
-- nothing of its own (WFA-13).
local seenPins = {}

-- One pass over the map's quest pins: hide the marked quests, bring back the pins this pass hid, and forget the pins
-- the provider has released. Nothing marked and nothing hidden is nothing to do, a hidden map has nothing to do, and
-- combat waits for its end redraw.
local function RefreshQuestPins()
	if not map or InCombatLockdown() or not map:IsShown() then
		return
	end
	local mapID = map:GetMapID()
	if not mapID then
		return
	end
	local marked = MarkedQuests(mapID)
	if next(marked) == nil and next(hiddenPins) == nil then
		return
	end
	for pin in map:EnumeratePinsByTemplate(QUEST_PINS) do
		---@cast pin AGFQuestPin
		seenPins[pin] = true
		if pin.questID and marked[pin.questID] then
			if not hiddenPins[pin] then
				hiddenPins[pin] = true
			end
			if pin:IsShown() then
				pin:Hide()
			end
		elseif hiddenPins[pin] then
			hiddenPins[pin] = nil
			if not pin:IsShown() then
				pin:Show()
			end
		end
	end
	for pin in pairs(hiddenPins) do
		if not seenPins[pin] then
			hiddenPins[pin] = nil
		end
	end
	for pin in pairs(seenPins) do
		seenPins[pin] = nil
	end
end

-- The pass runs in the frame its event arrived in, from this frame's OnUpdate: after every event handler of that frame
-- and before the client draws it. The provider registers its own events on the map's OnShow, after these, so its
-- re-acquired pins exist by then and no pin of a stopped quest shows for a frame (#718). Many events in one frame share
-- one pass, and a closed map has none: opening it redraws through Draw. Draw never cancels a queued pass: it can run
-- from a handler that fires before the provider's, which then re-acquires its pins, and the pass's early-outs make a
-- second run in the frame free.
local pinPass = CreateFrame("Frame")
pinPass:Hide()
pinPass:SetScript("OnUpdate", function(self)
	self:Hide()
	RefreshQuestPins()
end)

local function QueueQuestPins()
	if pinPass:IsShown() or not (map and map:IsShown()) then
		return
	end
	pinPass:Show()
end

local providerEvents = CreateFrame("Frame")
providerEvents:SetScript("OnEvent", function(_, event, cvar)
	if event == "CVAR_UPDATE" and cvar ~= "questPOI" then
		return
	end
	QueueQuestPins()
end)
for _, event in ipairs(PROVIDER_EVENTS) do
	providerEvents:RegisterEvent(event)
end

local function ReleaseMarks()
	for _, pool in ipairs({ routePool, giverPool, spotPool }) do
		pool:ReleaseAll()
	end
end

-- Active route and giver pins, used by the layout dump.
---@return (AGFPinFrame|AGFGiverPinFrame|AGFSpotPinFrame)[]
function Pins.Active()
	local pins = {}
	for _, pool in ipairs({ routePool, giverPool, spotPool }) do
		for _, pin in ipairs(pool:Active()) do
			pins[#pins + 1] = pin
		end
	end
	return pins
end

-- Givers first, so the route's numbered pins draw above them. A giver whose quest is a stop drawn already is left
-- to that stop: our marker for the chosen journey, or Shortest Path's numbered stop for what the last Go handed it.
---@param mapID integer
local function AddGivers(mapID)
	if not giverPool or not GiversShown() or not ns.State.Ready() then
		return
	end
	local routed = {}
	for _, step in ipairs(RingsShown() and ns.Route().steps or ns.Guidance.Guided()) do
		for _, id in ipairs(step.quests) do
			routed[id] = true
		end
	end
	-- The settled route's snapshot, so a map refresh walks no quest log of its own; a fresh read only while a
	-- rebuild is due (reading the route then would plan it in this frame).
	local world = ns.RouteSettled() and ns.Snapshot()
		or { player = ns.State.Player(), completed = ns.State.Completed(), log = ns.State.Log() }
	local givers = ns.Model.Givers(ns.Data, world.player, world.completed, world.log, mapID)
	for _, giver in ipairs(givers) do
		local covered = false
		for _, id in ipairs(giver.quests) do
			covered = covered or routed[id] == true
		end
		if not covered then
			giverPool:Acquire(giver)
		end
	end
end

-- The steps drawn are those on the map currently shown: a continent view gets no pins, matching how the route already
-- only points at zone-level maps. While OpenMap stitches the zones around it onto the same canvas, their stops draw at
-- the place each has on that canvas too.
local function Draw()
	if not map or not routePool or not spotPool then
		return
	end
	if InCombatLockdown() then
		ns.core.MapCanvas.SetShown(map, false)
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	afterCombat:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ReleaseMarks()
	ns.core.MapCanvas.SetShown(map, true)
	local mapID = map:GetMapID()
	if not mapID then
		return
	end
	AddGivers(mapID)
	if RingsShown() then
		-- A numbered pin at each step's point, but none for the area the player stands in: they are there (§4.2). An
		-- area draws nothing more: the game's own objective mark and its hover shape show where its objectives are.
		-- A place the route comes back to keeps one marker, numbered for its first visit, with its quest-action badge
		-- intact and every visit in its tooltip (docs/design.md §2.9).
		local canvas = map:GetCanvas()
		local scale = map:GetCanvasScale() or 1
		local reachX = MAP_GROUP_SIZE / math.max(1, canvas:GetWidth() * scale)
		local reachY = MAP_GROUP_SIZE / math.max(1, canvas:GetHeight() * scale)
		-- Each drawn step's point in the shown map's fractions: its own, or its place on OpenMap's stitched canvas.
		local stitched = ns.OpenMapStitch.Stitched()
		local placed = {}
		for _, step in ipairs(ns.Route().steps) do
			if not step.here then
				if step.map == mapID then
					placed[step] = { x = step.x, y = step.y }
				elseif stitched then
					local x, y = ns.OpenMapStitch.Place(step, mapID)
					if x ~= nil and y ~= nil then
						placed[step] = { x = x, y = y }
					end
				end
			end
		end
		local groups = Groups(function(step)
			return placed[step] ~= nil and not step.here
		end, function(_, _, firstX, firstY, x, y)
			return math.abs(firstX - x) <= reachX and math.abs(firstY - y) <= reachY
		end, function(step)
			local point = placed[step]
			return mapID, point.x, point.y
		end)
		for _, visits in ipairs(groups) do
			local first, point = visits[1].step, placed[visits[1].step]
			routePool:Acquire(first, visits[1].index, visits, point.x, point.y)
		end
		-- A town visit's other NPCs and objects, so a hand-in away from its numbered stop shows where it is: one small
		-- quest mark each, never on a point a numbered stop already has, faded as the stop it belongs to.
		local numbered = {}
		for _, visits in ipairs(groups) do
			numbered[ns.Model.SpotKey(visits[1].step)] = true
		end
		for _, spot in ipairs(VisitSpotRows(mapID, numbered)) do
			spotPool:Acquire(spot, spot.index)
		end
	end
	RefreshQuestPins()
end

---@class AGFPinVisit
---@field step AGFStep
---@field index number

-- The step's kind (a pickup, a hand-in, an objective...) as a small badge on the marker's lower right, as Shortest
-- Path badges its own stops; made on first use.
---@param pin AGFPinFrame
---@return AGFBadge
local function Badge(pin)
	if not pin.Badge then
		pin.Badge = ns.Overview.CreateBadge(pin, pin, BADGE_SIZE, BADGE_OFFSET)
	end
	return pin.Badge
end

---@class AGFPinFrame : ForeverCanvasPin
---@field Icon Texture
---@field Badge? AGFBadge
---@field step? AGFStep
---@field index? number
---@field visits? AGFPinVisit[]
---@field Stack? Texture
AdventureGuideForeverPinMixin = CreateFromMixins(ns.core.MapCanvas.PinMixin, { takesMouse = true, clicks = true })

function AdventureGuideForeverPinMixin.ShouldMouseButtonBePassthrough(_, button)
	return button ~= "LeftButton" and button ~= "RightButton"
end

---@param step AGFStep
---@param index number
---@param visits? AGFPinVisit[]
---@param x? number the point in the shown map's fractions; nil keeps the step's own
---@param y? number
function AdventureGuideForeverPinMixin:OnAcquired(step, index, visits, x, y)
	-- The stock user waypoint's level (WaypointLocationDataProvider), above every quest "!" and "?", the super-tracked
	-- one's included (Blizzard_WorldMap.lua:291-311); givers stay at AREA_POI, under both.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
	self.step, self.index, self.visits = step, index, visits
	if visits and #visits > 1 then
		if not self.Stack then
			self.Stack = self:CreateTexture(nil, "BACKGROUND", nil, -1)
			ns.Art.SetStepRing(self.Stack, 24)
			self.Stack:SetPoint("CENTER", self, "CENTER", 4, -4)
			self.Stack:SetAlpha(0.7)
		end
		self.Stack:Show()
	elseif self.Stack then
		self.Stack:Hide()
	end
	local current = index == 1
	ns.Art.SetStepMarker(self.Icon, index, 24)
	local badge = Badge(self)
	ns.Overview.SetVerbIcon(badge, step)
	local alpha = current and 1 or LATER_STOP_ALPHA
	self.Icon:SetAlpha(alpha)
	badge:SetAlpha(alpha)
	-- The badge hangs past the button; the pin takes the clicks it gets.
	local corner = badge:IsShown() and -BADGE_OFFSET or 0
	self:SetHitRectInsets(0, corner, 0, corner)
	self:SetPosition(x or step.x, y or step.y)
	self:SetIgnoreGlobalPinScale(true)
	self:SetScalingLimits(1, 1, 1)
	self:ApplyScale()
end

function AdventureGuideForeverPinMixin:OnMouseEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.step and self.index then
		MarkerTooltip(GameTooltip, self.visits or { { step = self.step, index = self.index } })
		AddClickLine(GameTooltip)
		-- A step past the first still has a clear way back to the story's start (docs/design.md §2.10).
		if self.index and self.index > 1 then
			GameTooltip_AddInstructionLine(GameTooltip, ns.L.PIN_RETURN_STORY)
		end
	end
	GameTooltip:Show()
end

function AdventureGuideForeverPinMixin:OnMouseLeave()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

function AdventureGuideForeverPinMixin:OnMouseClickAction(button)
	if not self.step then
		return
	end
	if button == "RightButton" then
		-- Back to the story's start: the same journey, guided from its first step (docs/design.md §2.10).
		ns.StartRoute()
	elseif button == "LeftButton" then
		ns.StartRoute(self.step)
	end
end

---@class AGFGiverPinFrame : ForeverCanvasPin
---@field Icon Texture
---@field Glow Texture
---@field giver? AGFGiver
AdventureGuideForeverGiverPinMixin = CreateFromMixins(ns.core.MapCanvas.PinMixin, { takesMouse = true, clicks = true })

---@param giver AGFGiver
function AdventureGuideForeverGiverPinMixin:OnAcquired(giver)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self.giver = giver
	self:SetPosition(giver.x, giver.y)
	self:SetScalingLimits(1, 1.0, 1.2)
	self:ApplyScale()
end

-- The NPC, then each quest it offers, as the pickups they are; the click line and the shift-click's follow.
function AdventureGuideForeverGiverPinMixin:OnMouseEnter()
	local giver = self.giver
	if not giver then
		return
	end
	self.Glow:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, giver.title)
	for _, id in ipairs(giver.quests) do
		QuestLine(GameTooltip, id, PICK_UP_ICON)
	end
	AddClickLine(GameTooltip)
	if #giver.adds > 0 then
		GameTooltip_AddInstructionLine(GameTooltip, ns.Pinned(giver.adds) and ns.L.SHIFT_REMOVE or ns.L.SHIFT_ADD)
	end
	GameTooltip:Show()
end

function AdventureGuideForeverGiverPinMixin:OnMouseLeave()
	self.Glow:Hide()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

-- A shift-click adds the giver's quests to the route (docs/design.md §2.18), or takes them off: those not orange or
-- red, which no route takes.
function AdventureGuideForeverGiverPinMixin:OnMouseClickAction(button)
	if button == "LeftButton" and self.giver and IsShiftKeyDown() then
		if #self.giver.adds > 0 then
			ns.TogglePinned(self.giver.adds)
		end
		GameTooltip:Hide()
	elseif button == "LeftButton" and self.giver then
		ns.Guidance.Navigate(self.giver)
	end
end

-- A visit spot's own mark: the game's turn-in "?" where something is handed in there, else its pickup "!".
---@param spot AGFVisitSpot
---@return string
local function SpotAtlas(spot)
	return #spot.handins > 0 and "QuestTurnin" or "QuestNormal"
end

---@class AGFSpotPinFrame : ForeverCanvasPin
---@field Icon Texture
---@field spot? AGFVisitSpot
---@field index? integer
AdventureGuideForeverSpotPinMixin = CreateFromMixins(ns.core.MapCanvas.PinMixin, { takesMouse = true })

---@param spot AGFVisitSpot
---@param index integer
function AdventureGuideForeverSpotPinMixin:OnAcquired(spot, index)
	-- Under the numbered stops, which keep the user waypoint's level.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self.spot, self.index = spot, index
	ns.Art.Fit(self.Icon, SpotAtlas(spot), SPOT_ICON, SPOT_ICON)
	self.Icon:SetAlpha(index == 1 and 1 or LATER_STOP_ALPHA)
	self:SetPosition(spot.x, spot.y)
	self:SetIgnoreGlobalPinScale(true)
	self:SetScalingLimits(1, 1, 1)
end

-- The NPC or object, then the quests picked up and handed in there.
function AdventureGuideForeverSpotPinMixin:OnMouseEnter()
	local spot = self.spot
	if not spot then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, spot.name)
	for _, id in ipairs(spot.handins) do
		QuestLine(GameTooltip, id, HAND_IN_ICON)
	end
	for _, id in ipairs(spot.pickups) do
		QuestLine(GameTooltip, id, PICK_UP_ICON)
	end
	GameTooltip:Show()
end

function AdventureGuideForeverSpotPinMixin:OnMouseLeave()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

-- A requested reveal waits for the canvas to observe the target map before playing.
local function PlayReveal()
	local point = reveal
	if
		not point
		or not map
		or not pingPool
		or InCombatLockdown()
		or not map:IsShown()
		or map:GetMapID() ~= point.map
	then
		return
	end
	reveal = nil
	pingPool:ReleaseAll()
	pingPool:Acquire(point.x, point.y)
end

---@param point AGFPoint|AGFPlace|AGFStep|AGFGiver
function Pins.Reveal(point)
	if InCombatLockdown() or not ns.Model.ValidPlace(point) or ns.Setting("wanderer") then
		return
	end
	reveal = point
	-- The client's own opener, run securely (Core/OpenMap.lua): its code turns the map, as from the quest tracker's
	-- menu.
	ForeverCore.OpenMap(point.map)
	C_Timer.After(0, function()
		if not InCombatLockdown() and map then
			local view = ns.core.MapCanvas.Watch(map)
			if view.shown and view.mapID == point.map then
				PlayReveal()
			end
		end
	end)
end

function Pins.Refresh()
	if InCombatLockdown() then
		reveal = nil
		if map then
			ns.core.MapCanvas.SetShown(map, false)
		end
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	HookQuestieToggle()
	RefreshMinimap()
	if map and map:IsShown() then
		Draw()
	end
end

afterCombat:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" then
		reveal = nil
		if map then
			ns.core.MapCanvas.SetShown(map, false)
		end
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
	Pins.Refresh()
end)

afterCombat:RegisterEvent("MINIMAP_UPDATE_ZOOM")
afterCombat:RegisterEvent("PLAYER_REGEN_DISABLED")

local function Attach()
	map = WorldMapFrame
	routePool =
		ns.core.MapCanvas.Pool(map, AdventureGuideForeverPinMixin, { template = PIN_TEMPLATE, marker = "route" })
	-- The native ping keeps its art and animations; private placement overrides its native pin base.
	local pingMixin = CreateFromMixins(MapPinPingMixin, ns.core.MapCanvas.PinMixin, {
		OnLoad = MapPinPingMixin.OnLoad,
		OnAcquired = function(self, x, y)
			self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_PING")
			self:SetNumLoops(2)
			self:PlayAt(x, y)
		end,
		OnReleased = function(self)
			self:Stop()
		end,
	})
	giverPool = ns.core.MapCanvas.Pool(map, AdventureGuideForeverGiverPinMixin, { template = GIVER_TEMPLATE })
	spotPool = ns.core.MapCanvas.Pool(map, AdventureGuideForeverSpotPinMixin, { template = SPOT_TEMPLATE })
	pingPool = ns.core.MapCanvas.Pool(map, pingMixin, { template = PING_TEMPLATE })
	ns.core.MapCanvas.Watch(map, function(_, what)
		if what == "map" or what == "hide" then
			pingPool:ReleaseAll()
		end
		if what == "map" and reveal and map:GetMapID() ~= reveal.map then
			reveal = nil
		end
		if what == "hide" then
			reveal = nil
		else
			Pins.Refresh()
			PlayReveal()
		end
	end)
	ns.OpenMapStitch.OnStitchedChanged(Pins.Refresh)
	ns.OnRouteChange(Pins.Refresh)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)
