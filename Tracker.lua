---@type string, AGFNamespace
local _, ns = ...

-- WFA-5: Legacy Forever holds 0 and -1, SkillUp Forever -2, Shortest Path Forever -3. This is the
-- next free slot.
local UI_ORDER = -4

---@return AGFStep?
local function CurrentStep()
	return ns.Route().steps[1]
end

-- The chapter end (docs/design.md §2.7): Blizzard's anim block glows a header once when its key needs a fanfare.
local STORY_COMPLETE = "story-complete"
-- Set by a turn-in that ends a story: the quest, then the first step 1 the route shows without it. The header stays
-- above the steps until step 1 moves on from that.
---@type {quest: integer, key?: string}?
local finished

---@class AGFTrackerModule : ObjectiveTrackerModuleTemplate
local ModuleMixin = { headerText = "Adventure Guide", blockTemplate = "ObjectiveTrackerAnimBlockTemplate" }

---@param _block AGFTrackerBlock the header's own block; CurrentStep() is used instead since it's always current
---@param mouseButton string
---@diagnostic disable-next-line: unused-local
function ModuleMixin:OnBlockHeaderClick(_block, mouseButton)
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

-- One block for the current step (docs/design.md §2.5): its place, why it is next and the travel line as objective
-- lines, then what follows it, undashed. Nothing is laid out (an empty, self-hiding module) when the setting is off,
-- there's no route yet, or the route is empty.
function ModuleMixin:LayoutContents()
	if not ns.Setting("showTracker") then
		return
	end
	if finished then
		local block = self:GetBlock(STORY_COMPLETE)
		block:SetHeader(ns.L.STORY_COMPLETE)
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
	-- No line repeats the header: a pickup's title already names its NPC, and a turn-in's is its reason.
	local line = 0
	if step.place and not step.title:find(step.place, 1, true) then
		line = line + 1
		block:AddObjective(line, step.place)
	end
	local resume = ns.Resume(step)
	-- Mid-line, a reason that is a sentence of its own ("Continues a story you started") loses its capital.
	local reason = resume and ns.L.RESUME:format((resume:gsub("^%u", string.lower)))
		or step.kind ~= "turnin" and step.reason
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
		block:AddObjective(line, ns.L.NEXT:format(nextStep.title), nil, nil, OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE)
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
		ns.Print("couldn't add a section to the objective tracker; please report with /agf audit.")
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
