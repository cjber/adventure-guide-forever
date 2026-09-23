---@type string, AGFNamespace
local _, ns = ...

-- WFA-5: Legacy Forever holds 0 and -1, SkillUp Forever -2, Shortest Path Forever -3. This is the
-- next free slot.
local UI_ORDER = -4

---@return AGFStep?
local function CurrentStep()
	return ns.Route().steps[1]
end

---@class AGFTrackerModule : ObjectiveTrackerModuleTemplate
local ModuleMixin = { headerText = "Adventure Guide" }

---@param _block AGFTrackerBlock the header's own block; CurrentStep() is used instead since it's always current
---@param mouseButton string
---@diagnostic disable-next-line: unused-local
function ModuleMixin:OnBlockHeaderClick(_block, mouseButton)
	if mouseButton ~= "RightButton" then
		if ns.OpenPanel then
			ns.OpenPanel()
		end
		return
	end
	MenuUtil.CreateContextMenu(self:GetContextMenuParent(), function(_, root)
		root:SetTag("MENU_ADVENTURE_GUIDE_FOREVER_TRACKER")
		local step = CurrentStep()
		root:CreateTitle(step and step.title or ns.TITLE)
		root:CreateButton("Skip", function()
			if step then
				ns.Skip(step.key)
			end
		end)
		root:CreateButton("Change route", function()
			if ns.OpenPanel then
				ns.OpenPanel()
			end
		end)
		root:CreateButton("Go", function()
			if step then
				ns.Integrations.Navigate(step)
			end
		end)
	end)
end

-- One block for the current step: its place and detail as objective lines, then what
-- follows it. Nothing is laid out (an empty, self-hiding module) when the setting is off,
-- there's no route yet, or the route is empty.
function ModuleMixin:LayoutContents()
	if not ns.Setting("showTracker") then
		return
	end
	local step = CurrentStep()
	if not step then
		return
	end
	local block = self:GetBlock(step.key)
	block:SetHeader(step.title)
	local line = 0
	if step.place then
		line = line + 1
		block:AddObjective(line, step.place)
	end
	line = line + 1
	block:AddObjective(line, step.detail)
	local travel = ns.Integrations.Travel(step)
	if travel then
		line = line + 1
		block:AddObjective(line, travel)
	end
	local nextStep = ns.Route().steps[2]
	if nextStep then
		line = line + 1
		block:AddObjective(line, ("Next: %s"):format(nextStep.title))
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

Register()
ns.OnRouteChange(Refresh)
ns.Integrations.OnTravelChange(Refresh)
