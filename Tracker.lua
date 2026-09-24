---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- WFA-5: Legacy Forever holds 0 and -1, SkillUp Forever -2, Shortest Path Forever -3. This is the
-- next free slot.
local UI_ORDER = -4

---@return AGFStep?
local function CurrentStep()
	return ns.Route().steps[1]
end

-- The chapter end (docs/design.md §2.7): Blizzard's anim block glows a header once when its key needs a fanfare.
local STORY_COMPLETE = "story-complete"
-- The trainer line (F16): a block of its own, text only.
local TRAINER = "trainer"
-- Headers that are not the step's: its click and hover never act on them.
local NOT_STEP = { [STORY_COMPLETE] = true, [TRAINER] = true }
-- A town's NPC line names this many, then counts the rest.
local NAMED_GIVERS = 2
-- Set by a turn-in that ends a story: the quest, then the first step 1 the route shows without it. The header stays
-- above the steps until step 1 moves on from that.
---@type {quest: integer, key?: string}?
local finished

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

---@param block AGFTrackerBlock the header's own block: the trainer's and the story's end do nothing; for the step's,
---CurrentStep() is used since it's always current
---@param mouseButton string
function ModuleMixin:OnBlockHeaderClick(block, mouseButton)
	if NOT_STEP[block.id] then
		return
	end
	if mouseButton ~= "RightButton" then
		local step = CurrentStep()
		if step and ns.Setting("trackRouteQuests") then
			ns.TrackRouteQuests()
		end
		if step and ns.Setting("titleStartsRoute") then
			ns.Integrations.Navigate(step)
		end
		-- The step's quest when the log has it, the guide otherwise.
		if not (step and ns.ShowQuest(step)) and ns.OpenPanel then
			ns.OpenPanel()
		end
		return
	end
	ns.Menu.Open(self:GetContextMenuParent(), "MENU_ADVENTURE_GUIDE_FOREVER_TRACKER", CurrentStep())
end

-- The title's click starts the route when the setting says so, so it warns as Go does.
---@param block AGFTrackerBlock
function ModuleMixin:OnBlockHeaderEnter(block)
	local step = CurrentStep()
	if not NOT_STEP[block.id] and step and ns.Setting("titleStartsRoute") and ns.Integrations.ReplacesJourney() then
		GameTooltip:SetOwner(block, "ANCHOR_RIGHT")
		ns.Menu.GoWarning(GameTooltip, step.title)
		GameTooltip:Show()
	end
end

function ModuleMixin:OnBlockHeaderLeave()
	GameTooltip:Hide()
end

-- One block for the current step (docs/design.md §2.5, docs/plan.md §7.4): its place (a town's counts), why it is next
-- (a town's NPCs) and the travel line as objective lines, then what follows it, undashed. Nothing is laid out (an
-- empty, self-hiding module) when the setting is off, there's no route yet, or the route is empty.
function ModuleMixin:LayoutContents()
	if not ns.Setting("showTracker") then
		return
	end
	local trainer = ns.Integrations.Trainer()
	if trainer then
		local block = self:GetBlock(TRAINER)
		block:SetHeader(L.TRAINER)
		block:AddObjective(1, trainer)
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
	local step = CurrentStep()
	if not step then
		return
	end
	local block = self:GetBlock(step.key)
	block:SetHeader(step.title)
	local line = 0
	local town = step.kind == "hub" and #step.quests > 1
	-- A town's header is its name, so its counts come first. One quest's stop says where it is instead: "NPC, zone",
	-- the place alone when it already names the zone, the zone alone when there is no place. No line repeats the header.
	local place = step.place
	if step.place and step.zone and not step.place:find(step.zone, 1, true) then
		place = L.PLACE:format(step.place, step.zone)
	end
	place = town and step.detail or place or step.zone
	if place and not step.title:find(place, 1, true) then
		line = line + 1
		block:AddObjective(line, place)
	end
	local resume = ns.Resume(step)
	-- A lone hand-in, a turn-in or a town's, is titled "Turn in: …", which already says it is ready.
	local handIn = step.kind == "turnin" or (step.kind == "hub" and #step.quests == 1 and #step.handins == 1)
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
	if not self:LayoutBlock(block) then
		return
	end
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
-- glow, never without the tracker section to show it.
---@param questID integer
function ns.OnTurnIn(questID)
	local story = ns.Data.quests[questID] and ns.Model.Story(ns.Data, questID)
	if not (module and ns.Setting("showTracker") and story and story.total and story.chapter == story.total) then
		return
	end
	finished = { quest = questID }
	module:SetNeedsFanfare(STORY_COMPLETE)
	PlaySound(SOUNDKIT.UI_SCENARIO_STAGE_END)
	Refresh()
end

-- The first rebuild whose step 1 isn't the quest just handed in names the step the header stands over.
local function OnRouteChange()
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
