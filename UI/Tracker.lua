---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end
local L = ns.L

-- WFA-5: Legacy Forever holds 0 and -1, SkillUp Forever -2, Shortest Path Forever -3. This is the
-- next free slot.
local UI_ORDER = -4

-- The chapter end (docs/design.md §2.7): Blizzard's anim block glows a header once when its key needs a fanfare.
local STORY_COMPLETE = "story-complete"
-- A turn-in ended the chosen journey (docs/design.md §2.10): the same glow once, and a click opens the guide.
local JOURNEY_COMPLETE = "journey-complete"
-- The aside (Asides.lua): one line, a block of its own. Its click goes to its place when it has one; right-click is its
-- menu.
local ASIDE = "aside"
-- Something new (Moments.lua, docs/design.md §2.13): "Duskwood is now for your level", glowing once, until the guide
-- opens; a click opens it.
local MOMENT = "moment"
-- The quiet wait while QuestieSource's catalogue builds (docs/design.md §2.14): a line instead of a wrong route.
local LOADING = "loading"
-- Polestar is guiding (Polestar.lua): its line stands alone, and a click takes over again.
local POLESTAR = "polestar"
-- A RestedXP guide's ongoing steps, one line each, under the step under way.
local ONGOING = "rxp-ongoing"
-- The game's quest areas are off (the questPOI CVar, which Questie's Questie and pfQuest objective types turn off):
-- one note says so, a click turns them back on and a right-click hides the note for good (#363). Never turned on
-- without the player's click: it is their choice, or Questie's.
local QUEST_AREAS = "quest-areas"
-- The running guide's progress bar under its title (#365).
local GUIDE_PROGRESS = "rxp-progress"
-- The chapter the chosen story is on, one muted line under the section heading (#394, #395).
local STORY_BEAT = "story-beat"
-- Headers that are not the step's: its click and hover never act on them.
local NOT_STEP = {
	[STORY_COMPLETE] = true,
	[STORY_BEAT] = true,
	[ASIDE] = true,
	[JOURNEY_COMPLETE] = true,
	[MOMENT] = true,
	[LOADING] = true,
	[POLESTAR] = true,
	[ONGOING] = true,
	[QUEST_AREAS] = true,
}
-- A town's NPC line names this many, then counts the rest.
local NAMED_GIVERS = 2
-- Set by a turn-in that ends a story: the quest, then the first step 1 the route shows without it. The header stays
-- above the steps until step 1 moves on from that.
---@type {quest: integer, key?: string}?
local finished
-- Set when a turn-in ends the chosen journey; `seen` once the route change of that rebuild has passed, and the next
-- one takes the block away.
---@type {seen: boolean, next?: string}?
local journeyDone

-- A town's NPCs: the first two by name, the rest counted.
---@param givers string[]
---@return string
local function Givers(givers)
	if #givers <= NAMED_GIVERS then
		return table.concat(givers, L.LIST_SEPARATOR)
	end
	return L.HUB_NPCS_MORE:format(table.concat(givers, L.LIST_SEPARATOR, 1, NAMED_GIVERS), #givers - NAMED_GIVERS)
end

-- Steps can cover several quests, so each gets its own line in the addon-owned block. A quest with no title yet
-- shows the step's own.
local function QuestLine(step, questID)
	local title, color = ns.Pins.QuestLineText(questID)
	if title == "" then
		return ns.StepStyle.StepTitle(step)
	end
	return ns.StepStyle.Wrap(CreateColor(color.r, color.g, color.b), title)
end

---@param block AGFTrackerBlock
---@return AGFStep?
local function BlockStep(block)
	for _, step in ipairs(ns.Route().steps) do
		if step.key == block.id then
			return step
		end
	end
	return ns.Guidance.CurrentStep()
end

---@class AGFTrackerModule : ObjectiveTrackerModuleTemplate, ForeverTrackerModule
---@field rxpActionsReserved? number the height the RestedXP action rows already added to contentsHeight
---@field npcHighlightReserved? number the height the next-NPC target button already added to contentsHeight
---@field AddHeaderMenuEntries? fun(self: AGFTrackerModule, root: ForeverMenuDescription)
local ModuleMixin = {
	headerText = L.TITLE,
	blockTemplate = "ObjectiveTrackerAnimBlockTemplate",
	-- Blizzard pairs its fanfare block with this line (Blizzard_ObjectiveTrackerAnimTemplates.xml:3): every used
	-- line's FadeInAnim is restarted when the block plays its add animation, so the plain line would raise a nil.
	lineTemplate = "ObjectiveTrackerAnimLineTemplate",
}

---@param block AGFTrackerBlock the header's own block: the aside's goes to its place, the journey's end opens the guide
---and the story's does nothing; for the step's, ns.Guidance.CurrentStep() is used since it's always current
---@param mouseButton string
function ModuleMixin:OnBlockHeaderClick(block, mouseButton)
	local aside = ns.Asides.Current()
	if block.id == ASIDE and aside then
		ns.Asides.Click(block.HeaderButton or block, mouseButton, aside)
		return
	elseif block.id == QUEST_AREAS then
		if mouseButton == "RightButton" then
			ns.SetSetting("questAreasNoteHidden", true)
		elseif not InCombatLockdown() then
			SetCVar("questPOI", "1")
		end
		self:MarkDirty()
		return
	elseif block.id == POLESTAR then
		if mouseButton ~= "RightButton" then
			ns.Polestar.TakeOver()
			ns.StartRoute()
		end
		return
	elseif NOT_STEP[block.id] then
		if (block.id == JOURNEY_COMPLETE or block.id == MOMENT) and mouseButton ~= "RightButton" and ns.OpenPanel then
			ns.OpenPanel()
		end
		return
	end
	if mouseButton == "RightButton" then
		-- A step's title opens the same step menu as its row in the guide (#641).
		local step = BlockStep(block)
		ForeverCore.ContextMenu(block.HeaderButton or block, function(_, root)
			ns.Menu.Step(root, step)
		end)
		return
	end
	local step = BlockStep(block)
	if step and ns.Setting("trackRouteQuests") then
		ns.TrackRouteQuests()
	end
	-- The step is the chosen journey's, else the first card's, which this chooses (ns.StartRoute).
	if step and ns.Setting("titleStartsRoute") then
		ns.StartRoute()
	end
	-- The step's quest when the log has it, the guide otherwise.
	if not (step and ns.ShowQuest(step)) and ns.OpenPanel then
		ns.OpenPanel()
	end
end

-- The title's click starts the route when the setting says so, as an aside's with a place does, so each warns as Go
-- does.
---@param block AGFTrackerBlock
function ModuleMixin:OnBlockHeaderEnter(block)
	if block.id == QUEST_AREAS then
		GameTooltip:SetOwner(block, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.QUEST_AREAS_OFF)
		GameTooltip_AddNormalLine(GameTooltip, L.QUEST_AREAS_TOOLTIP)
		GameTooltip:Show()
		return
	end
	if not ns.Integrations.ReplacesJourney() then
		return
	end
	local step, aside = BlockStep(block), ns.Asides.Current()
	local title = (block.id == ASIDE and aside and aside.place and aside.text)
		or (not NOT_STEP[block.id] and step and ns.Setting("titleStartsRoute") and step.title)
	if title then
		GameTooltip:SetOwner(block, "ANCHOR_RIGHT")
		ns.Menu.GoWarning(GameTooltip, title)
		GameTooltip:Show()
	end
end

function ModuleMixin:OnBlockHeaderLeave()
	GameTooltip:Hide()
end

-- The aside's line, when there is one.
---@param module AGFTrackerModule
---@return boolean laid out, or nothing to lay out
local function LayoutLine(module)
	local aside = ns.Asides.Current()
	if not aside then
		return true
	end
	local block = module:GetBlock(ASIDE)
	block:SetHeader(aside.text)
	return module:LayoutBlock(block)
end

-- Why the step wants a group (docs/design.md §2.27), one line each, after why it is next.
---@param block AGFTrackerBlock
---@param step AGFStep
---@param line integer
---@return integer line the last line used
local function GroupLines(block, step, line)
	for _, note in ipairs(ns.Overview.GroupNotes(step)) do
		line = line + 1
		block:AddObjective(line, note)
	end
	return line
end

-- Friendly nameplates are off: one muted line under the talk step, once a session (#401).
---@param block AGFTrackerBlock
---@param step AGFStep
---@param line integer
---@return integer line
local function NpcHint(block, step, line)
	local hint = ns.NpcHighlight and ns.NpcHighlight.Hint(step)
	if hint then
		line = line + 1
		block:AddObjective(line, GRAY_FONT_COLOR:WrapTextInColorCode(hint))
	end
	return line
end

---@param block AGFTrackerBlock
---@param step AGFStep
---@param line integer
local function Preview(block, step, line)
	local steps = ns.Route().steps
	for index, candidate in ipairs(steps) do
		if candidate.key == step.key then
			for nextIndex = index + 1, math.min(index + 2, #steps) do
				local upcoming = steps[nextIndex]
				local text = ns.Overview.VerbMarkup(upcoming, 12) .. L.NEXT:format(upcoming.title)
				line = line + 1
				block:AddObjective(
					line,
					GRAY_FONT_COLOR:WrapTextInColorCode(text),
					nil,
					nil,
					OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE
				)
			end
			return
		end
	end
end

-- The room a block laid out next still has in the section (Blizzard_ObjectiveTrackerModule.lua CanFitBlock), less
-- what the block already holds.
---@param module AGFTrackerModule
---@param block AGFTrackerBlock
---@return number
local function Room(module, block)
	local _, offsetY = module:GetNextBlockAnchoring()
	return module.availableHeight - module.contentsHeight + offsetY - block.height
end

-- Room kept for one more line, and the marks' size in a line.
local LINE_ROOM, MARK_SIZE = 16, 12

---@param text string
---@return string
local function Plain(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Step 1's travel line, then, while its route is paused (cleared in Shortest Path, refused, or never handed), a line
-- saying so: the title's click resumes it, and a walk time alone would read as guidance under way (#361).
---@param block AGFTrackerBlock
---@param step AGFStep
---@param line integer
---@return integer
local function TravelLines(block, step, line)
	local travel = ns.Integrations.Travel(step)
	if travel then
		line = line + 1
		block:AddObjective(line, travel)
	end
	if ns.Guidance.Status() == "paused" then
		line = line + 1
		block:AddObjective(line, L.TRACKER_PAUSED)
	end
	return line
end

-- The quests a guide step's lines work on (its "complete" and "collect" lines).
---@param step AGFStep
---@return table<integer, true>
local function WorkQuests(step)
	local quests = {}
	for _, item in ipairs(step.checklist or {}) do
		if item.rxpQuest and not item.done and (item.rxpTag == "complete" or item.rxpTag == "collect") then
			quests[item.rxpQuest] = true
		end
	end
	return quests
end

-- An ongoing guide step in one line: its progress ("3/7 Small Spider Leg") when a line has one, else its first open
-- line, so the step under way stays the one that reads in full (#353).
---@param step AGFStep
---@return string?
local function OneLine(step)
	local first
	for _, item in ipairs(step.checklist or {}) do
		if not item.done then
			local text = ns.Overview.LineMarkup(item.rxpTag, MARK_SIZE) .. item.text
			if Plain(item.text):find("^%d+/%d+ ") then
				return text
			end
			first = first or text
		end
	end
	return first
end

-- A RestedXP step (docs/design.md §2.5): the step under way in full, each line marked with its kind, the first open
-- line lit as the tracker lights what it points at, done lines greyed; the next step in one grey line; then the
-- ongoing steps, one line each, those whose work the step under way or the quest tracker already shows left out, in
-- the room the section has left, with what does not fit counted (#351, #353). The walk is left to Shortest Path's
-- own section while it guides.
---@param module AGFTrackerModule
---@param block AGFTrackerBlock
---@param step AGFStep
local function GuideSection(module, block, step)
	local colors = OBJECTIVE_TRACKER_COLOR
	local line, lit = 0, false
	-- How far the guide has come, under the guide's title: "Step 95 of 188" and the tracker's own progress bar, as a
	-- quest objective with a bar draws it (#365).
	local journey = ns.CurrentJourney()
	local at, steps = journey and journey.guideStep, journey and journey.guideSteps
	if at and steps and steps > 0 then
		block:AddObjective(
			GUIDE_PROGRESS,
			L.RXP_PROGRESS:format(at, steps),
			nil,
			nil,
			OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE
		)
		local bar = block:AddProgressBar(GUIDE_PROGRESS)
		if bar then
			bar:SetPercent(math.floor((at - 1) / steps * 100))
		end
	end
	for _, item in ipairs(step.checklist or {}) do
		line = line + 1
		-- A done line greys whole, its coloured words too.
		local style, text = colors.Complete, Plain(item.text)
		if not item.done then
			style, text = lit and colors.Normal or colors.NormalHighlight, ns.StepStyle.Checklist(step, item)
			lit = true
		end
		block:AddObjective(line, ns.Overview.LineMarkup(item.rxpTag, MARK_SIZE) .. text, nil, true, nil, style)
	end
	line = GroupLines(block, step, line)
	if not ns.Integrations.Guiding() then
		line = TravelLines(block, step, line)
	end
	local ongoing, upcoming = {}, nil
	for _, other in ipairs(ns.Route().steps) do
		if other ~= step and other.rxpIndex then
			if other.rxpSticky and not other.preview then
				ongoing[#ongoing + 1] = other
			elseif not other.rxpSticky and not upcoming then
				upcoming = other
			end
		end
	end
	if upcoming then
		block:AddObjective(
			line + 1,
			GRAY_FONT_COLOR:WrapTextInColorCode(L.NEXT:format(upcoming.title)),
			nil,
			nil,
			OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE
		)
	end
	if not module:LayoutBlock(block) then
		return
	end
	local shown, lines, seen = WorkQuests(step), {}, {}
	for _, other in ipairs(ongoing) do
		local quests, covered = WorkQuests(other), true
		for questID in pairs(quests) do
			covered = covered and (shown[questID] or C_QuestLog.GetQuestWatchType(questID) ~= nil)
		end
		local text = OneLine(other)
		if text and not (next(quests) and covered) and not seen[text] then
			seen[text] = true
			lines[#lines + 1] = text
			for questID in pairs(quests) do
				shown[questID] = true
			end
		end
	end
	if #lines == 0 then
		return
	end
	local extra = module:GetBlock(ONGOING)
	extra:SetHeader(L.RXP_ONGOING)
	for index, text in ipairs(lines) do
		if Room(module, extra) < LINE_ROOM * (index < #lines and 2 or 1) then
			local more = #lines - index + 1
			extra:AddObjective(index, more == 1 and L.RXP_MORE_STEP or L.RXP_MORE_STEPS:format(more))
			break
		end
		extra:AddObjective(index, text, nil, true)
	end
	module:LayoutBlock(extra)
end

-- The chosen story's chapter, "Chapter 3 of 7: <the chapter's quest>" (#394, #395): the chain's place and the title
-- of the quest it is on. Only a story has one, and a chapter whose quest the data cannot name says nothing.
---@return string?
local function StoryBeat()
	local journey = ns.CurrentJourney()
	local story = journey and journey.story
	if not story then
		return nil
	end
	local id = story.members[story.chapter]
	if not id then
		return nil
	end
	local entry = ns.Snapshot().log[id]
	local quest = ns.Data.quests[id]
	local title = (entry and entry.title) or (quest and quest.title)
	if not title or title == "" then
		return nil
	end
	local chapter = story.total and L.CHAPTER_OF:format(story.chapter, story.total) or L.CHAPTER:format(story.chapter)
	return L.CHAPTER_QUEST:format(chapter, title)
end

-- One quiet line (LayoutLine), something new (Moments.Line) under it, then one block for the current step of the
-- chosen journey, else of the first card, which the guide draws on its own (docs/design.md §2.5):
-- its place (a town's counts), why it is next (a town's NPCs) and the travel line as objective lines, then what
-- follows it, undashed. Nothing is laid out (an empty,
-- self-hiding module) when the setting is off, or there's nothing to say.
function ModuleMixin:LayoutContentsBase()
	if not ns.Setting("showTracker") then
		return
	end
	if ns.Polestar.Active() then
		local block = self:GetBlock(POLESTAR)
		block:SetHeader(L.POLESTAR_GUIDING)
		block:AddObjective(1, L.POLESTAR_TAKE_OVER)
		self:LayoutBlock(block)
		return
	end
	if not LayoutLine(self) then
		return
	end
	if GetCVar("questPOI") == "0" and not ns.Setting("questAreasNoteHidden") then
		local note = self:GetBlock(QUEST_AREAS)
		note:SetHeader(L.QUEST_AREAS_OFF)
		note:AddObjective(1, L.QUEST_AREAS_SHOW)
		note:AddObjective(2, GRAY_FONT_COLOR:WrapTextInColorCode(L.QUEST_AREAS_DISMISS))
		if not self:LayoutBlock(note) then
			return
		end
	end
	local moment = ns.Moments.Line()
	if moment then
		local block = self:GetBlock(MOMENT)
		block:SetHeader(moment)
		if not self:LayoutBlock(block) then
			return
		end
	end
	if finished then
		local block = self:GetBlock(STORY_COMPLETE)
		block:SetHeader(L.STORY_COMPLETE)
		if not self:LayoutBlock(block) then
			return
		end
	end
	if journeyDone then
		local block = self:GetBlock(JOURNEY_COMPLETE)
		block:SetHeader(L.JOURNEY_COMPLETE)
		block:AddObjective(1, journeyDone.next and L.JOURNEY_NEXT:format(journeyDone.next) or L.CHOOSE_NEXT)
		if not self:LayoutBlock(block) then
			return
		end
	end
	local step = ns.Guidance.CurrentStep()
	if not step then
		if ns.QuestieBuilding() then
			local loading = self:GetBlock(LOADING)
			loading:SetHeader(L.TRACKER_LOADING)
			self:LayoutBlock(loading)
		end
		return
	end
	local beat = StoryBeat()
	if beat then
		local storyBlock = self:GetBlock(STORY_BEAT)
		storyBlock:SetHeader(GRAY_FONT_COLOR:WrapTextInColorCode(beat))
		if not self:LayoutBlock(storyBlock) then
			return
		end
	end
	local block = self:GetBlock(step.key)
	block:SetHeader(ns.StepStyle.StepTitle(step, ns.Overview.VerbMarkup(step, 14) .. step.title))
	local line = 0
	if step.rxpIndex then
		GuideSection(self, block, step)
		return
	end
	local guiding = ns.Integrations.Guiding()
	-- A dungeon card's current step says which chain it belongs to, and how far that chain has come. The story's
	-- chapter already has its own line above, so this is only for a dungeon's chains.
	local journey = ns.CurrentJourney()
	local chain = journey and journey.kind == "dungeon" and step.chapter or nil
	if step.kind == "area" or step.kind == "dungeon" or (guiding and #step.quests > 1) then
		for _, questID in ipairs(step.quests) do
			line = line + 1
			block:AddObjective(line, QuestLine(step, questID))
			for _, objective in ipairs(step.objectives or {}) do
				local text = objective.id == questID and ns.Model.ObjectiveText(objective)
				if text then
					line = line + 1
					block:AddObjective(line, GRAY_FONT_COLOR:WrapTextInColorCode(ns.StepStyle.Step(step, text)))
				end
			end
		end
	end
	if guiding then
		if step.reason ~= L.READY_TO_HAND_IN then
			line = line + 1
			block:AddObjective(line, step.reason)
		end
		if chain then
			line = line + 1
			block:AddObjective(line, GRAY_FONT_COLOR:WrapTextInColorCode(chain))
		end
		line = GroupLines(block, step, line)
		line = NpcHint(block, step, line)
		Preview(block, step, line)
		self:LayoutBlock(block)
		return
	end
	local town = step.kind == "town" and #step.quests > 1
	-- A town's header is its name, so its counts come first. One quest's stop says where it is instead: "NPC, zone",
	-- the place alone when it already names the zone, the zone alone when there is no place. A lone quest in a town
	-- names its giver, not the town (design §2.5). No line repeats the header.
	local place = (step.kind == "town" and #step.quests == 1) and step.spots[step.quests[1]].name or step.place
	if place and step.zone and not place:find(step.zone, 1, true) then
		place = L.PLACE:format(place, step.zone)
	end
	place = town and step.detail or place or step.zone
	if place and not step.title:find(place, 1, true) then
		line = line + 1
		block:AddObjective(line, ns.StepStyle.Step(step, place))
	end
	local resume = ns.Resume(step)
	-- A lone hand-in, a turn-in or a town's, is titled "Turn in: %s" (L.TURN_IN), which already says it is ready.
	local handIn = step.kind == "turnin" or (step.kind == "town" and #step.quests == 1 and #step.handins == 1)
	-- Mid-line, a reason that is a sentence of its own ("Continues a story you started") loses its capital; German keeps
	-- it, since there a capital may begin a noun ("Quests in Arbeit").
	if resume and GetLocale() ~= "deDE" then
		resume = resume:gsub("^%u", string.lower)
	end
	local reason = resume and L.RESUME:format(resume) or (not handIn and step.reason) or nil
	-- A town's reason is its counts unless something more is true there; then who to see takes the line.
	if town and not resume and step.reason == step.detail then
		-- The checklist already names each giver and action. Keep the compact giver
		-- summary only when there are no detailed rows to show.
		reason = #(step.checklist or {}) == 0 and Givers(step.givers) or nil
	end
	if reason then
		line = line + 1
		block:AddObjective(line, ns.StepStyle.Step(step, reason))
	end
	if chain then
		line = line + 1
		block:AddObjective(line, GRAY_FONT_COLOR:WrapTextInColorCode(chain))
	end
	line = GroupLines(block, step, line)
	local lit = false
	for _, giver in ipairs(step.checklist or {}) do
		line = line + 1
		local text, style = giver.text, nil
		if not (giver.done or giver.skipped) then
			text = ns.StepStyle.Checklist(step, giver)
			style = lit and OBJECTIVE_TRACKER_COLOR.Normal or OBJECTIVE_TRACKER_COLOR.NormalHighlight
			lit = true
		end
		block:AddObjective(line, text, nil, giver.done, nil, style)
	end
	line = TravelLines(block, step, line)
	line = NpcHint(block, step, line)
	Preview(block, step, line)
	self:LayoutBlock(block)
end

---@type AGFTrackerModule?
local module

-- RestedXP's secure item and target buttons sit inside this section (#334). Their height is added after the section's
-- own blocks lay out, so the column reserves room for them and no section below overlaps.
local Contents = ModuleMixin.LayoutContentsBase
function ModuleMixin:LayoutContents()
	Contents(self)
	if ns.RXPActions then
		ns.RXPActions.Reserve(self)
	end
	if ns.NpcHighlight then
		ns.NpcHighlight.Reserve(self)
	end
end

local function WarnIfUnattached()
	if module and not ForeverCore.TrackerHost.IsAttached(module) then
		ns.Print(L.TRACKER_UNATTACHED)
	end
end

-- The column's scale, Lock and position were the addon's before ForeverCore kept them; the host copies this table
-- once, so the player keeps the layout they chose. Saved variables load with the addon, so attach happens after them.
local function Attach()
	---@cast module AGFTrackerModule
	module.legacySettings = AdventureGuideForeverDB and AdventureGuideForeverDB.trackerHost or nil
	module.safeCall = ns.core.SafeCall
	module.AddHeaderMenuEntries = function(_, root)
		ns.Menu.Step(root, ns.Guidance.CurrentStep())
	end
	ForeverCore.TrackerHost.Attach(module)
	if AdventureGuideForeverDB then
		AdventureGuideForeverDB.trackerHost = nil
	end
end

local function Register()
	local frame =
		CreateFrame("Frame", "AdventureGuideForeverObjectiveTracker", UIParent, "ObjectiveTrackerModuleTemplate")
	---@cast frame AGFTrackerModule
	module = frame
	Mixin(module, ModuleMixin)
	module:SetHeader(ModuleMixin.headerText)
	module.uiOrder = UI_ORDER
	EventUtil.ContinueAfterAllEvents(function()
		C_Timer.After(0, Attach)
		C_Timer.After(5, WarnIfUnattached)
	end, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
end

local function Refresh()
	if module then
		local journey = ns.Route().chosen and not ns.Polestar.Active() and ns.CurrentJourney()
		module.headerText = journey and journey.title or L.TITLE
		module:SetHeader(module.headerText)
		module:MarkDirty()
	end
end

-- StoryCompletion records the milestone independently of tracker visibility.
---@param questID integer
function ns.OnTurnIn(questID)
	local recorded = ns.StoryCompletion.Record(questID)
	if not (recorded and module and ns.Setting("showTracker")) then
		return
	end
	finished = { quest = questID }
	module:SetNeedsFanfare(STORY_COMPLETE)
	Refresh()
end

-- Journey completion adds only the visual fanfare; step and story sounds are handled separately. `next` names the
-- zone the guide moved on to, when it did (#400).
---@param next? string
function ns.OnJourneyComplete(next)
	if not (module and ns.Setting("showTracker")) then
		return
	end
	journeyDone = { seen = false, next = next }
	module:SetNeedsFanfare(JOURNEY_COMPLETE)
	Refresh()
end

-- Something new: the moment's line glows for a journey, the aside's own line for an aside; no sound.
---@param journey boolean
---@param aside boolean
function ns.OnMoment(journey, aside)
	if not (module and ns.Setting("showTracker")) then
		return
	end
	if journey then
		module:SetNeedsFanfare(MOMENT)
	end
	if aside then
		module:SetNeedsFanfare(ASIDE)
	end
	Refresh()
end

-- The first rebuild whose step 1 isn't the quest just handed in names the step the header stands over.
local function OnRouteChange()
	if journeyDone then
		journeyDone = not journeyDone.seen and { seen = true } or nil
	end
	local step = ns.Guidance.CurrentStep()
	if finished and not (step and tContains(step.quests, finished.quest)) then
		local key = step and step.key or ""
		if finished.key == nil then
			finished.key = key
		elseif finished.key ~= key then
			finished = nil
		end
	end
	Refresh()
end

Register()
-- Where the RestedXP secure action buttons attach (#334).
function ns.TrackerModule()
	return module
end
-- The note on hidden quest areas follows the CVar, whoever changes it.
local cvars = CreateFrame("Frame")
cvars:RegisterEvent("CVAR_UPDATE")
cvars:SetScript("OnEvent", function(_, _, name)
	if name == "questPOI" then
		Refresh()
	end
end)
ns.OnRouteChange(OnRouteChange)
ns.Integrations.OnTravelChange(Refresh)
ns.Guidance.OnChange(Refresh)
ns.Asides.OnChange(Refresh)
ns.Moments.OnChange(Refresh)
