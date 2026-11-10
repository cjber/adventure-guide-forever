---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

--[[ The current step's NPC (#401): a secure target button in the tracker, a pair of small bouncing arrows either side
     of their nameplate, and one session-long hint when friendly nameplates are off. The arrows are our own frame
     anchored to the client's nameplate; the nameplate itself is never touched, so the client's own quest `?`/`!` at
     its top stays clear. The target button shares its chrome and macro with RestedXP's target rows
     (UI/ActionButton.lua). ]]

local L = ns.L
local ActionButton = ns.ActionButton
local ITEM_SIZE = ActionButton.ITEM_SIZE
-- NPE_ArrowLeft and NPE_ArrowRight both exist in this client (Blizzard_ArrowCalloutFrame/ArrowCalloutFrame.xml;
-- UiTextureAtlasMember). The left arrow points right, the right one points left, so both point at the nameplate.
local ARROW_LEFT_ATLAS = "NPE_ArrowRight"
local ARROW_RIGHT_ATLAS = "NPE_ArrowLeft"
local ARROW_SIZE = 22
local ARROW_BOB = 3
-- Field Guide Forever draws a 17-unit tier mark just right of a nameplate's name, so the right arrow keeps clear of it.
local ARROW_GAP = 6
local ARROW_TIER_GAP = 16
local ROW_GAP = 4

---@class AGFNpcHighlightModule
local Highlight = {}
ns.NpcHighlight = Highlight

---@type table<string, true>
local plates = {}
---@type AGFNpcTalk?
local activeNpc
---@type Frame?
local arrowFrame
---@type Texture?
local arrowLeft
---@type Texture?
local arrowRight
---@type Frame?
local arrowBar

---@type Frame?
local targetRoot
---@type AGFActionButton?
local targetButton
---@type string?
local arrowUnit
local appliedHeight = 0
local lastTargetShown = false
local bounce = 0
local hinted = false

local function Enabled()
	return ns.Setting("npcHighlight") == true
end

-- The NPC a talk step names: a town stop whose quests all share one giver, or a turn-in's data finish. Nil for an
-- area, a trainer, a town of several givers, or a step the data cannot name.
---@param step? AGFStep
---@return AGFNpcTalk?
function Highlight.StepNpc(step)
	if not step or not step.quests or #step.quests == 0 then
		return nil
	end
	if step.kind == "town" then
		local name, npc
		for _, id in ipairs(step.quests) do
			local spot = step.spots and step.spots[id]
			if not spot or not spot.name then
				return nil
			end
			if name and (spot.name ~= name or spot.npc ~= npc) then
				return nil
			end
			name, npc = spot.name, spot.npc
		end
		return name and { name = name, npc = npc } or nil
	elseif step.kind == "turnin" then
		local quest = ns.Data.quests[step.quests[1]]
		local finish = quest and quest.finish
		if finish and finish.name then
			return { name = finish.name, npc = finish.npc }
		end
	end
end

-- Whether `unit` is `npc`: by the creature entry in its GUID when both have one, else by the exact name.
---@param npc AGFNpcTalk
---@param unit string
---@return boolean
function Highlight.Matches(npc, unit)
	local entry = ns.CreatureEntry(ns.Readable(UnitGUID(unit)))
	if npc.npc and entry then
		return entry == npc.npc
	end
	return ns.Readable(UnitName(unit)) == npc.name
end

local function HideArrow()
	if arrowFrame then
		arrowFrame:Hide()
	end
	arrowBar = nil
	arrowUnit = nil
end

-- The arrows at `shift` from their places: the left one moves right and the right one left as `shift` grows, so both
-- bob toward the nameplate and back together.
---@param shift number
local function Place(shift)
	if not (arrowLeft and arrowRight and arrowBar) then
		return
	end
	arrowLeft:ClearAllPoints()
	arrowLeft:SetPoint("RIGHT", arrowBar, "LEFT", -ARROW_GAP + shift, 0)
	arrowRight:ClearAllPoints()
	arrowRight:SetPoint("LEFT", arrowBar, "RIGHT", ARROW_GAP + ARROW_TIER_GAP - shift, 0)
end

local function EnsureArrow()
	if arrowFrame then
		return
	end
	arrowFrame = CreateFrame("Frame", "AdventureGuideForeverNpcArrow", UIParent)
	arrowFrame:SetSize(ARROW_SIZE, ARROW_SIZE)
	arrowFrame:Hide()
	arrowLeft = arrowFrame:CreateTexture(nil, "ARTWORK")
	ns.Art.Fit(arrowLeft, ARROW_LEFT_ATLAS, ARROW_SIZE, ARROW_SIZE)
	arrowRight = arrowFrame:CreateTexture(nil, "ARTWORK")
	ns.Art.Fit(arrowRight, ARROW_RIGHT_ATLAS, ARROW_SIZE, ARROW_SIZE)
	arrowFrame:SetScript("OnUpdate", function(_, elapsed)
		bounce = (bounce + elapsed) % 1
		Place(math.sin(bounce * math.pi * 2) * ARROW_BOB)
	end)
end

local function UpdateArrow()
	if not Enabled() or not activeNpc then
		HideArrow()
		return
	end
	local unit = arrowUnit
	if not (unit and plates[unit] and Highlight.Matches(activeNpc, unit)) then
		unit = nil
		for candidate in pairs(plates) do
			if Highlight.Matches(activeNpc, candidate) then
				unit = candidate
				break
			end
		end
	end
	if not unit then
		HideArrow()
		return
	end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or not plate:IsShown() then
		HideArrow()
		return
	end
	EnsureArrow()
	local frame = arrowFrame
	if not frame then
		return
	end
	arrowUnit = unit
	local unitFrame = plate.UnitFrame --[[@as AGFNamePlateUnitFrame?]]
	arrowBar = (unitFrame and unitFrame.healthBar) or plate
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", arrowBar, "CENTER")
	Place(0)
	frame:Show()
end

-- The arrows' nameplate unit, for the specs and for a report; nil while no talk step's nameplate is shown.
---@return string?
function Highlight.ArrowUnit()
	return arrowUnit
end

---@param module AGFTrackerModule
---@return boolean
local function ModuleVisible(module)
	return module:IsVisible() and not module.isCollapsed
end

---@param module AGFTrackerModule
---@return number
local function BaseHeight(module)
	local reserved = module.npcHighlightReserved or 0
	if (module.contentsHeight or 0) < reserved then
		reserved = 0
	end
	return math.max(0, (module.contentsHeight or 0) - reserved)
end

---@param module AGFTrackerModule
local function Anchor(module)
	if InCombatLockdown() or not targetRoot then
		return
	end
	local left, top = module:GetLeft(), module:GetTop()
	if not left or not top then
		targetRoot:Hide()
		return
	end
	local scale = module:GetEffectiveScale() / UIParent:GetEffectiveScale()
	targetRoot:SetFrameStrata(module:GetFrameStrata())
	targetRoot:SetFrameLevel(module:GetFrameLevel() + 5)
	targetRoot:ClearAllPoints()
	targetRoot:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, (top - BaseHeight(module)) * scale - ROW_GAP)
end

local function ClearTarget()
	if InCombatLockdown() then
		return
	end
	if targetRoot then
		targetRoot:Hide()
	end
	if lastTargetShown then
		lastTargetShown = false
		local module = ns.TrackerModule()
		if module then
			module:MarkDirty()
		end
	end
	if appliedHeight ~= 0 then
		appliedHeight = 0
		local module = ns.TrackerModule()
		if module then
			module:MarkDirty()
		end
	end
end

local function UpdateTarget()
	local module = ns.TrackerModule()
	if not Enabled() or not activeNpc or not ns.Setting("showTracker") or not module or not ModuleVisible(module) then
		ClearTarget()
		return
	end
	if not targetRoot then
		targetRoot = CreateFrame("Frame", "AdventureGuideForeverNpcHighlight", UIParent)
		targetRoot:SetSize(ITEM_SIZE, ITEM_SIZE)
		targetRoot:Hide()
	end
	if not targetButton then
		targetButton = ActionButton.Create(targetRoot, "AdventureGuideForeverNpcTarget")
	end
	ActionButton.SetTarget(targetButton, { name = activeNpc.name, kind = "target" }, ns.Readable(UnitName("target")))
	ActionButton.SetKeybind(targetButton, "AdventureGuideForeverNpcTarget")
	targetRoot:SetSize(ITEM_SIZE, ITEM_SIZE)
	targetRoot:Show()
	Anchor(module)
	if not lastTargetShown then
		lastTargetShown = true
		module:MarkDirty()
	end
end

---@return boolean
function Highlight.TargetShown()
	return targetRoot ~= nil and targetRoot:IsShown()
end

-- The tracker's room for the target button, kept beside its own layout like RestedXP's action rows.
---@param module AGFTrackerModule
function Highlight.Reserve(module)
	local shown = Enabled()
		and activeNpc ~= nil
		and ns.Setting("showTracker")
		and ModuleVisible(module)
		and targetRoot ~= nil
		and targetRoot:IsShown()
	if not InCombatLockdown() then
		if not shown then
			if targetRoot then
				targetRoot:Hide()
			end
		elseif targetRoot then
			targetRoot:Show()
		end
	end
	local height = shown and ITEM_SIZE or 0
	local reserved = module.npcHighlightReserved or 0
	if (module.contentsHeight or 0) < reserved then
		reserved = 0
	end
	local base = (module.contentsHeight or 0) - reserved
	if height <= 0 or base <= 0 then
		if reserved > 0 then
			module.contentsHeight = base
			module.npcHighlightReserved = nil
			if module.UpdateHeight then
				module:UpdateHeight()
			end
		end
	else
		local extra = height + ROW_GAP
		module.contentsHeight = base + extra
		module.npcHighlightReserved = extra
		if module.UpdateHeight then
			module:UpdateHeight()
		end
	end
	appliedHeight = height
	if not InCombatLockdown() then
		Anchor(module)
	end
end

-- Friendly nameplates off: one hint a session, as the tracker's own muted objective line. Nil otherwise.
---@param step? AGFStep
---@return string?
function Highlight.Hint(step)
	if hinted or not Enabled() or not Highlight.StepNpc(step) or GetCVarBool("nameplateShowFriends") then
		return nil
	end
	hinted = true
	return L.NPC_HIGHLIGHT_HINT
end

function Highlight.Refresh()
	if InCombatLockdown() then
		return
	end
	activeNpc = Enabled() and Highlight.StepNpc(ns.Guidance.CurrentStep()) or nil
	UpdateArrow()
	UpdateTarget()
end

local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		plates[unit] = true
		UpdateArrow()
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		plates[unit] = nil
		if arrowUnit == unit then
			HideArrow()
		end
		UpdateArrow()
	elseif event == "PLAYER_TARGET_CHANGED" then
		if not InCombatLockdown() then
			UpdateTarget()
		end
	else
		Highlight.Refresh()
	end
end)

ns.OnRouteChange(Highlight.Refresh)
