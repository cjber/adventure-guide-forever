---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- WFA-5: Legacy Forever holds 0 and -1, SkillUp Forever -2, Shortest Path Forever -3. This is the
-- next free slot.
local UI_ORDER = -4

---@return AGFStep?
local function CurrentStep()
	return ns.Integrations.CurrentStep()
end

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
-- Headers that are not the step's: its click and hover never act on them.
local NOT_STEP = { [STORY_COMPLETE] = true, [ASIDE] = true, [JOURNEY_COMPLETE] = true, [MOMENT] = true }
-- A town's NPC line names this many, then counts the rest.
local NAMED_GIVERS = 2
-- Set by a turn-in that ends a story: the quest, then the first step 1 the route shows without it. The header stays
-- above the steps until step 1 moves on from that.
---@type {quest: integer, key?: string}?
local finished
-- Set when a turn-in ends the chosen journey; `seen` once the route change of that rebuild has passed, and the next
-- one takes the block away.
---@type {seen: boolean}?
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

---@class AGFTrackerModule : ObjectiveTrackerModuleTemplate
local ModuleMixin = { headerText = L.TRACKER_HEADER, blockTemplate = "ObjectiveTrackerAnimBlockTemplate" }

---@param block AGFTrackerBlock the header's own block: the aside's goes to its place, the journey's end opens the guide
---and the story's does nothing; for the step's, CurrentStep() is used since it's always current
---@param mouseButton string
function ModuleMixin:OnBlockHeaderClick(block, mouseButton)
	local aside = ns.Asides.Current()
	if block.id == ASIDE and aside then
		if mouseButton == "RightButton" then
			ns.Asides.Open(self:GetContextMenuParent(), "MENU_ADVENTURE_GUIDE_FOREVER_ASIDE", aside)
		else
			ns.Asides.Go(aside)
		end
		return
	elseif NOT_STEP[block.id] then
		if (block.id == JOURNEY_COMPLETE or block.id == MOMENT) and mouseButton ~= "RightButton" and ns.OpenPanel then
			ns.OpenPanel()
		end
		return
	end
	if mouseButton ~= "RightButton" then
		local step = CurrentStep()
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
		return
	end
	ns.Menu.Open(self:GetContextMenuParent(), "MENU_ADVENTURE_GUIDE_FOREVER_TRACKER", CurrentStep())
end

-- The title's click starts the route when the setting says so, as an aside's with a place does, so each warns as Go
-- does.
---@param block AGFTrackerBlock
function ModuleMixin:OnBlockHeaderEnter(block)
	if not ns.Integrations.ReplacesJourney() then
		return
	end
	local step, aside = CurrentStep(), ns.Asides.Current()
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

-- One quiet line (LayoutLine), something new (Moments.Line) under it, then one block for the current step of the
-- chosen journey, else of the first card, which the guide draws on its own (docs/design.md §2.5, docs/plan.md §7.4):
-- its place (a town's counts), why it is next (a town's NPCs) and the travel line as objective lines, then what
-- follows it, undashed. Nothing is laid out (an empty,
-- self-hiding module) when the setting is off, or there's nothing to say.
function ModuleMixin:LayoutContents()
	if not ns.Setting("showTracker") or not LayoutLine(self) then
		return
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
		block:AddObjective(1, L.CHOOSE_NEXT)
		if not self:LayoutBlock(block) then
			return
		end
	end
	local step = CurrentStep()
	if not step then
		return
	end
	local block = self:GetBlock(step.key)
	block:SetHeader(step.title)
	if ns.Integrations.Guiding() then
		block:AddObjective(1, step.reason)
		self:LayoutBlock(block)
		return
	end
	local line = 0
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
		block:AddObjective(line, place)
	end
	local resume = ns.Resume(step)
	-- A lone hand-in, a turn-in or a town's, is titled "Turn in: …", which already says it is ready.
	local handIn = step.kind == "turnin" or (step.kind == "town" and #step.quests == 1 and #step.handins == 1)
	-- Mid-line, a reason that is a sentence of its own ("Continues a story you started") loses its capital.
	local reason = resume and L.RESUME:format((resume:gsub("^%u", string.lower))) or not handIn and step.reason
	-- A town's reason is its counts unless something more is true there; then who to see takes the line.
	if town and not resume and step.reason == step.detail then
		reason = Givers(step.givers)
	end
	if reason then
		line = line + 1
		block:AddObjective(line, reason)
	end
	for _, giver in ipairs(step.checklist or {}) do
		line = line + 1
		block:AddObjective(line, giver.text, nil, giver.done)
	end
	local travel = ns.Integrations.Travel(step)
	if travel then
		line = line + 1
		block:AddObjective(line, travel)
	end
	local nextStep = ns.Route().steps[2]
	if nextStep then
		line = line + 1
		block:AddObjective(line, L.NEXT:format(nextStep.title), nil, nil, OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE)
	end
	self:LayoutBlock(block)
end

---@type AGFTrackerModule?
local module

local function Available()
	return ObjectiveTrackerManager and ObjectiveTrackerFrame
end

---@param trackerModule AGFTrackerModule
local function Attach(trackerModule)
	ObjectiveTrackerManager:SetModuleContainer(trackerModule, ObjectiveTrackerFrame)
end

---@param _ table
---@param container Frame
local function OnContainerAdded(_, container)
	if container == ObjectiveTrackerFrame and module then
		Attach(module)
	end
end

local function WarnIfUnattached()
	if module and ObjectiveTrackerManager:GetContainerForModule(module) == nil then
		ns.Print(L.TRACKER_UNATTACHED)
	end
end

local function Register()
	if not Available() then
		return
	end
	local frame =
		CreateFrame("Frame", "AdventureGuideForeverObjectiveTracker", UIParent, "ObjectiveTrackerModuleTemplate")
	---@cast frame AGFTrackerModule
	module = frame
	Mixin(module, ModuleMixin)
	module:SetHeader(ModuleMixin.headerText)
	module.uiOrder = UI_ORDER
	hooksecurefunc(ObjectiveTrackerManager, "AddContainer", OnContainerAdded)
	Attach(module)
	EventUtil.ContinueAfterAllEvents(function()
		C_Timer.After(5, WarnIfUnattached)
	end, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
end

local function Refresh()
	if module then
		module:MarkDirty()
	end
end

-- Only a chain whose end the data proves (Model.Story's total) is ever called complete; the sound plays with the
-- glow even during the client's turn-in sound (design §2.7), never without the tracker section to show it.
---@param questID integer
function ns.OnTurnIn(questID)
	local story = ns.Data.quests[questID] and ns.Model.Story(ns.Data, questID)
	if not (module and ns.Setting("showTracker") and story and story.total and story.chapter == story.total) then
		return
	end
	finished = { quest = questID }
	module:SetNeedsFanfare(STORY_COMPLETE)
	ns.Sound.Complete("story:" .. questID, true)
	Refresh()
end

-- Journey completion adds only the visual fanfare; step and story sounds are handled separately.
function ns.OnJourneyComplete()
	if not (module and ns.Setting("showTracker")) then
		return
	end
	journeyDone = { seen = false }
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
	local step = CurrentStep()
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
ns.OnRouteChange(OnRouteChange)
ns.Integrations.OnTravelChange(Refresh)
ns.Integrations.OnGuidanceChange(Refresh)
ns.Asides.OnChange(Refresh)
ns.Moments.OnChange(Refresh)
