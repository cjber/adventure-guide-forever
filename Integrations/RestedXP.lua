---@type string, AGFNamespace
local _, ns = ...
---@class AGFRestedXPModule : AGFRestedXPAdapter
local Guide = {}
ns.RestedXP = Guide
---@type fun()[]
local listeners = {}
local active, ready, queued = false, false, false
---@type AGFRXPSnapshot
local snapshot = { name = "", group = "", index = 0, total = 0, steps = {} }
local signature = ""
local autoSelected
---@type table<Frame, {alpha: number, mouse: boolean}>
local mapLines = {}
local PREVIEW_STEPS = 10

---@type AGFRXPEngine?
local registered
local receiver = {}
---@type table<AGFRXPWindow, {alpha: number, points: table[], dontSave: boolean, savePosition?: boolean}>
local windows = {}
---@type table<Frame, boolean>
local clamps = {}

---@return AGFRXPEngine?
local function Engine()
	local engine = RXP
	if
		type(engine) == "table"
		and type(engine.SetStep) == "function"
		and type(engine.GetGuideProgress) == "function"
		and engine.RXPFrame
	then
		return engine
	end
end

---@param engine AGFRXPEngine
---@param value string?
---@param element? AGFRXPElement
---@return string
local function Text(engine, value, element)
	if type(value) ~= "string" then
		return ""
	end
	if engine.locale and engine.locale.Get then
		value = engine.locale.Get(value)
	end
	if engine.ReplaceNpcIds then
		value = engine.ReplaceNpcIds(value, element)
	end
	return (value:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

---@param frame Frame
local function Unclamp(frame)
	if clamps[frame] == nil then
		clamps[frame] = frame:IsClampedToScreen()
	end
	if frame:IsClampedToScreen() then
		frame:SetClampedToScreen(false)
	end
	for _, child in ipairs({ frame:GetChildren() }) do -- multi-value: all RestedXP-owned descendants need unclamping.
		Unclamp(child)
	end
end

---@param frame AGFRXPWindow?
local function Window(frame)
	if not frame then
		return
	end
	local saved = windows[frame]
	if not saved then
		saved = {
			alpha = frame:GetAlpha(),
			points = {},
			dontSave = frame:GetDontSavePosition(),
			savePosition = frame.savePosition,
		}
		for index = 1, frame:GetNumPoints() do
			saved.points[index] = { frame:GetPoint(index) }
		end
		windows[frame] = saved
	end
	-- RXP runs engine callbacks on its window and descendants, even when the guide is elsewhere.
	-- Neither RXP profiles nor the client layout cache should persist the suppressed anchors.
	frame.savePosition = false
	frame:SetDontSavePosition(true)
	frame:SetAlpha(0)
	Unclamp(frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
end

---@param engine AGFRXPEngine
local function SuppressMap(engine)
	local pins = LibStub and LibStub:GetLibrary("HereBeDragons-Pins-2.0", true)
	if pins then
		pins:RemoveAllWorldMapIcons(engine)
		pins:RemoveAllMinimapIcons(engine)
	end
	local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
	if not canvas or not engine.currentGuide then
		return
	end
	for _, child in ipairs({ canvas:GetChildren() }) do -- multi-value: inspect canvas children for RXP-owned lines.
		local line = child --[[@as AGFRXPMapLine]]
		local element = line.lineData and line.lineData.element
		local step = element and element.step
		if step and engine.currentGuide.steps[step.index] == step then
			if mapLines[line] == nil then
				mapLines[line] = { alpha = line:GetAlpha(), mouse = line:IsMouseEnabled() }
			end
			line:SetAlpha(0)
			line:EnableMouse(false)
		end
	end
end

local function Restore()
	for frame, saved in pairs(mapLines) do
		frame:SetAlpha(saved.alpha)
		frame:EnableMouse(saved.mouse)
	end
	mapLines = {}
	for frame, saved in pairs(windows) do
		frame.savePosition = saved.savePosition
		frame:SetDontSavePosition(saved.dontSave)
		frame:SetAlpha(saved.alpha)
		frame:ClearAllPoints()
		for _, point in ipairs(saved.points) do
			frame:SetPoint(unpack(point))
		end
	end
	for frame, clamped in pairs(clamps) do
		frame:SetClampedToScreen(clamped)
	end
	windows, clamps = {}, {}
end

---@param element? AGFRXPElement
---@param step AGFRXPStep
---@return integer, number, number
local function Coordinates(element, step, preview)
	if
		not element
		or (not preview and not step.active)
		or not element.arrow
		or element.skip
		or element.hidden
		or (element.generated and element.generated ~= 0)
		or (type(element.parent) == "table" and (element.parent.completed or element.parent.skip))
		or (element.text and element.completed)
	then
		return 0, 0, 0
	end
	local map, x, y = element.zone, element.x, element.y
	if
		type(map) ~= "number"
		or not (map > 0 and map < math.huge and map == math.floor(map))
		or type(x) ~= "number"
		or not (x >= 0 and x <= 100)
		or type(y) ~= "number"
		or not (y >= 0 and y <= 100)
	then
		return 0, 0, 0
	end
	return map, x / 100, y / 100
end

---@param engine AGFRXPEngine
---@return AGFRXPSnapshot
local function Snapshot(engine)
	local guide = engine.currentGuide
	---@type AGFRXPSnapshot
	local result = { name = "", group = "", index = 0, total = 0, steps = {} }
	if not guide or guide.empty then
		return result
	end
	result.name, result.group = guide.name or "", guide.group or ""
	result.index = engine.GetGuideProgress()
	result.total = #(guide.steps or {})
	local arrowElement = engine.arrowFrame and engine.arrowFrame.element
	local seen, nonSticky = {}, 0
	local function AddStep(step, preview)
		if not step.index or seen[step.index] or step.hidewindow or step.hidetip then
			return
		end
		if not step.sticky or preview then
			nonSticky = nonSticky + 1
		end
		seen[step.index] = true
		local map, sx, sy = 0, 0, 0
		if not preview and not step.sticky and step.index == result.index and arrowElement and arrowElement.step then
			local frame = engine.arrowFrame
			if
				engine.activeWaypoints
				and #engine.activeWaypoints > 0
				and not (engine.hideArrow and not (frame and frame.wrongContinent))
			then
				map, sx, sy = Coordinates(arrowElement, arrowElement.step, false)
			end
		elseif step.sticky or preview then
			for _, element in ipairs(step.elements or {}) do
				map, sx, sy = Coordinates(element, step, preview)
				if map > 0 then
					break
				end
			end
		end
		---@type AGFRXPDisplayStep
		local row = {
			index = step.index,
			title = Text(engine, step.title or ns.L.RXP_STEP:format(step.index)),
			sticky = not preview and not not step.sticky,
			preview = not not preview,
			lines = {},
			map = map,
			x = sx,
			y = sy,
		}
		for index, element in ipairs(step.elements or {}) do
			local text = Text(engine, element.text or element.tooltipText or element.rawtext, element)
			if text ~= "" and not element.hideTooltip and not element.hidden then
				row.lines[#row.lines + 1] = {
					text = text,
					done = not preview and not element.textOnly and not not (element.completed or element.skip),
					questId = element.questId,
					tag = element.tag,
					elementIndex = not preview and not element.textOnly and not element.optional and index or nil,
				}
			end
		end
		result.steps[#result.steps + 1] = row
	end
	for _, step in ipairs(engine.RXPFrame.activeSteps or {}) do
		if step.active then
			AddStep(step, false)
		end
	end
	-- Read future authored rows only. RXP still activates and evaluates them.
	for index = result.index + 1, result.total do
		if nonSticky >= PREVIEW_STEPS then
			break
		end
		local step = guide.steps[index]
		if step then
			AddStep(step, true)
		end
	end
	return result
end

function Guide.Enabled()
	local engine = Engine()
	local profile = engine and engine.settings and engine.settings.profile
	return engine ~= nil
		and not not ns.Setting("restedxpChoiceMade")
		and not not ns.Setting("restedxpGuide")
		and not (profile and (profile.hideGuideWindow or profile.showEnabled == false))
end

function Guide.Active()
	return active
end
function Guide.Snapshot()
	return snapshot
end
function Guide.OnChange(callback)
	listeners[#listeners + 1] = callback
end

local function Sync()
	queued = false
	if not ready or InCombatLockdown() then
		return
	end
	local engine = Engine()
	if engine and not ns.Setting("restedxpChoiceMade") then
		ns.GuideSetup.Show()
	end
	local enabled = Guide.Enabled()
	local changed = active ~= not not enabled
	active = not not enabled
	if active and engine then
		Window(engine.RXPFrame)
		Window(engine.activeItemFrame)
		Window(engine.targeting and engine.targeting.activeTargetFrame)
		Window(LibDBIcon10_RXPGuides)
		SuppressMap(engine)
		Window(engine.v2 and engine.v2.state and engine.v2.state.guideWindow and engine.v2.state.guideWindow.frame)
		snapshot = Snapshot(engine)
		if
			snapshot.name == ""
			and not (
				engine.guideImporter
				and (engine.guideImporter.importCoroutine or (engine.guideImporter.importBufferSize or 0) > 0)
			)
		then
			local level, candidate, count = ns.State.Player().level, nil, 0
			for _, card in ipairs(Guide.Cards()) do
				if card.guideLow and card.guideHigh and level >= card.guideLow and level < card.guideHigh then
					candidate, count = card, count + 1
				end
			end
			if count == 1 and candidate and autoSelected ~= candidate.key then
				autoSelected = candidate.key
				Guide.Select(assert(candidate.rxpGroup), assert(candidate.rxpName))
			end
		end
	else
		Restore()
		if changed and engine then
			engine.UpdateMap(true)
		end
		snapshot = { name = "", group = "", index = 0, total = 0, steps = {} }
	end
	local parts = { snapshot.name, snapshot.group, tostring(snapshot.index), tostring(snapshot.total) }
	for _, step in ipairs(snapshot.steps) do
		parts[#parts + 1] = tostring(step.index)
			.. step.title
			.. tostring(step.sticky)
			.. tostring(step.preview)
			.. tostring(step.map)
			.. tostring(step.x)
			.. tostring(step.y)
		for _, line in ipairs(step.lines) do
			parts[#parts + 1] = line.text
				.. tostring(line.done)
				.. tostring(line.elementIndex)
				.. tostring(line.questId)
				.. tostring(line.tag)
		end
	end
	local key = table.concat(parts, "\000")
	if changed or key ~= signature then
		signature = key
		ns.Invalidate()
		for _, callback in ipairs(listeners) do
			callback()
		end
	end
end

function Guide.Refresh()
	if not queued then
		queued = true
		C_Timer.After(0, Sync)
	end
end

local function Attach()
	local engine = Engine()
	if engine and registered ~= engine then
		registered = engine
		if engine.RegisterMessage then
			for _, message in ipairs({
				"RXP_GUIDE_LOADED",
				"RXP_STEP_ACTIVATED",
				"RXPGuidesV2_UpdateActiveSteps",
				"RXPGuidesV2_GuideStepsChanged",
				"RXPGuidesV2_GuideWindowRefresh",
			}) do
				engine.RegisterMessage(receiver, message, Guide.Refresh)
			end
		end
		if engine.v2 and type(engine.v2.UpdateGuideWindow) == "function" then
			hooksecurefunc(engine.v2, "UpdateGuideWindow", function() -- taint-ok: RestedXP owns its v2 controller.
				if active and not InCombatLockdown() then
					local state = engine.v2 and engine.v2.state
					Window(state and state.guideWindow and state.guideWindow.frame)
				end
			end)
		end
		local current = engine.RXPFrame.CurrentStepFrame
		if current and type(current.UpdateText) == "function" then
			hooksecurefunc(current, "UpdateText", Guide.Refresh) -- taint-ok: RestedXP owns CurrentStepFrame.UpdateText.
		end
		if type(engine.RenderFrame) == "function" then
			hooksecurefunc(engine, "RenderFrame", Guide.Refresh) -- taint-ok: RestedXP owns the RXP runtime table.
		end
		if type(engine.DisplayLines) == "function" then
			hooksecurefunc(engine, "DisplayLines", Guide.Refresh) -- taint-ok: RXP owns this map-line controller.
		end
		if type(engine.UpdateMap) == "function" then
			hooksecurefunc(engine, "UpdateMap", function() -- taint-ok: RestedXP owns the RXP runtime table.
				if active and not InCombatLockdown() then
					SuppressMap(engine)
				end
				Guide.Refresh()
			end)
		end
		for _, method in ipairs({ "UpdateItemFrame", "ResetItemPosition" }) do
			if type(engine[method]) == "function" then
				hooksecurefunc(engine, method, Guide.Refresh) -- taint-ok: RestedXP owns its active-item controller.
			end
		end
		if engine.targeting and type(engine.targeting.UpdateTargetFrame) == "function" then
			hooksecurefunc(engine.targeting, "UpdateTargetFrame", Guide.Refresh) -- taint-ok: RXP owns this controller.
		end
		if type(engine.UpdateGotoSteps) == "function" then
			hooksecurefunc(engine, "UpdateGotoSteps", Guide.Refresh) -- taint-ok: RestedXP owns the RXP runtime table.
		end
	end
	Guide.Refresh()
end

function Guide.Guides()
	local result = {}
	local engine = Engine()
	if not engine then
		return result
	end
	for _, group in pairs(engine.guideList or {}) do
		for _, entry in ipairs(group.names_ or {}) do
			local guide = engine.GetGuideTable(entry.group, entry.name)
			if guide and not guide.chapter and not guide.OnClick and engine.IsGuideActive(guide) then
				result[#result + 1] = { group = entry.group, name = entry.name }
			end
		end
	end
	table.sort(result, function(a, b)
		return a.group == b.group and a.name < b.name or a.group < b.group
	end)
	return result
end

local function GuideKey(group, name)
	return "guide:" .. tostring(#group) .. ":" .. group .. ":" .. tostring(#name) .. ":" .. name
end

---@param current? AGFJourney
---@return AGFJourney[]
function Guide.Cards(current)
	if not active then
		return {}
	end
	local engine = Engine()
	if not engine then
		return {}
	end
	current = current or Guide.Journey()
	local result = current and { current } or {}
	local seen = current and { [current.key] = true } or {}
	local level = ns.State.Player().level
	for _, entry in ipairs(Guide.Guides()) do
		local key = GuideKey(entry.group, entry.name)
		if not seen[key] and not ns.Prefs().notInterested[key] then
			seen[key] = true
			local data = engine.GetGuideTable(entry.group, entry.name)
			local low, high = entry.name:match("^(%d+)%-(%d+)")
			low, high = tonumber(low), tonumber(high)
			if not (low and high and high <= level) and not (data and data.lowPrio) then
				result[#result + 1] = {
					kind = "guide",
					section = "continue",
					key = key,
					title = entry.name,
					subline = entry.group,
					map = 0,
					steps = {},
					rxpGroup = entry.group,
					rxpName = entry.name,
					guideLow = low,
					guideHigh = high,
				}
			end
		end
	end
	table.sort(result, function(a, b)
		if current and (a.key == current.key or b.key == current.key) then
			return a.key == current.key
		end
		local da = a.guideLow and math.max(0, a.guideLow - level) or math.huge
		local db = b.guideLow and math.max(0, b.guideLow - level) or math.huge
		if da ~= db then
			return da < db
		end
		if a.guideHigh ~= b.guideHigh then
			return (a.guideHigh or math.huge) < (b.guideHigh or math.huge)
		end
		return a.key < b.key
	end)
	return result
end

---@param group string
---@param name string
---@param start? boolean
function Guide.Choose(group, name, start)
	if not Guide.Select(group, name) then
		return
	end
	C_Timer.After(0, function()
		local current = Guide.Snapshot()
		local journey = Guide.Journey()
		if journey and current.name == name and current.group == group then
			ns.Choose(journey.key, start)
		end
	end)
end

function Guide.Select(group, name)
	local engine = Engine()
	if not engine or not active or InCombatLockdown() then
		return false
	end
	for _, guide in ipairs(Guide.Guides()) do
		if guide.group == group and guide.name == name then
			engine:LoadGuideTable(group, name)
			Guide.Refresh()
			return true
		end
	end
	return false
end

function Guide.Move(delta)
	local engine = Engine()
	if not engine or not active or InCombatLockdown() or snapshot.total == 0 then
		return false
	end
	engine.SetStep(math.max(1, math.min(snapshot.total + 1, snapshot.index + delta)))
	Guide.Refresh()
	return true
end

function Guide.Skip(index, elementIndex)
	local engine = Engine()
	local step = engine and engine.currentGuide and engine.currentGuide.steps[index]
	if not engine or not active or InCombatLockdown() or not step or not step.active then
		return false
	end
	if elementIndex then
		local element = step.elements[elementIndex]
		if not element or element.textOnly or element.optional then
			return false
		end
		if element.OnComplete and not element.skip then
			element.OnComplete(element)
		end
		element.skip = true
		engine.updateSteps = true
		engine.UpdateMap()
	elseif step.sticky then
		RXPCData.stepSkip[index] = true -- taint-ok: RestedXP owns RXPCData and its stepSkip saved-variable table.
		engine.SetStep((engine.GetGuideProgress()))
	else
		engine.SetStep(index + 1)
	end
	Guide.Refresh()
	return true
end

function Guide.OpenImport()
	local engine = Engine()
	if engine and not InCombatLockdown() and engine.guideImporter then
		engine.guideImporter:Open()
		return true
	end
	return false
end
function Guide.OpenSettings()
	local engine = Engine()
	if engine and engine.settings and not InCombatLockdown() then
		engine.settings.OpenSettings()
		return true
	end
	return false
end
function Guide.UseOriginal()
	ns.SetSetting("restedxpGuide", false)
end

---@return AGFJourney?
function Guide.Journey()
	if not active or snapshot.name == "" then
		return nil
	end
	local name = snapshot.name
	local group = snapshot.group
	local guideKey = GuideKey(group, name)
	local steps = {}
	local log = ns.State.Log()
	local firstMap = 0
	-- Non-sticky steps first, then sticky
	for _, pass in ipairs({ false, true }) do
		for _, row in ipairs(snapshot.steps) do
			if (not not row.sticky) == pass then
				local stepKey = guideKey .. ":step:" .. tostring(row.index)
				local checklist, quests, seen, areas, shapes, objectives = {}, {}, {}, {}, {}, {}
				local radius = 0
				for i, line in ipairs(row.lines) do
					if line.questId and ns.Data.quests[line.questId] then
						if not seen[line.questId] then
							seen[line.questId] = true
							quests[#quests + 1] = line.questId
						end
						local entry = log[line.questId]
						if line.tag == "complete" and not line.done and entry and not areas[line.questId] then
							areas[line.questId] = true
							for _, node in ipairs(ns.Planner.Steps.Nodes(ns.Data, entry)) do
								if node.map == row.map and row.map > 0 then
									shapes[#shapes + 1] = node
									radius = math.max(radius, (ns.Model.Yards(ns.Data, row, node) or 0) + node.r)
									for _, objective in ipairs(node.objectives) do
										objectives[#objectives + 1] = objective
									end
								end
							end
						end
					end
					local elemKey = stepKey
						.. (line.elementIndex and ":elem:" .. tostring(line.elementIndex) or ":line:" .. tostring(i))
					checklist[#checklist + 1] = {
						key = elemKey,
						name = line.text,
						text = line.text,
						pickups = {},
						handins = {},
						done = line.done,
						skipped = false,
						place = { map = 0, x = 0, y = 0, name = "" },
					}
				end
				steps[#steps + 1] = {
					key = stepKey,
					kind = "guide",
					preview = row.preview,
					title = row.sticky and ns.L.RXP_STICKY:format(row.title) or row.title,
					detail = "",
					reason = "",
					quests = quests,
					shapes = shapes,
					objectives = objectives,
					r = radius,
					map = row.map,
					x = row.x,
					y = row.y,
					rxpIndex = row.index,
					rxpSticky = row.sticky,
					rxpGuide = name,
					checklist = checklist,
				}
				if firstMap == 0 and row.map > 0 then
					firstMap = row.map
				end
			end
		end
	end
	local subline = snapshot.total > 0 and ns.L.RXP_PROGRESS:format(snapshot.index, snapshot.total) or ns.L.RXP_NO_GUIDE
	---@type AGFJourney
	return {
		kind = "guide",
		section = "continue",
		key = guideKey,
		title = name,
		subline = subline,
		map = firstMap,
		steps = steps,
	}
end

---@param key string
---@return boolean
function Guide.SkipKey(key)
	if not active or snapshot.name == "" then
		return false
	end
	local name = snapshot.name
	local group = snapshot.group
	local guideKey = GuideKey(group, name)
	local prefix = guideKey .. ":step:"
	if key:sub(1, #prefix) ~= prefix then
		return false
	end
	local suffix = key:sub(#prefix + 1)
	local stepIndex = tonumber(suffix)
	-- Exact integer match only; rejects checklist item keys like ":step:2:elem:1"
	if not stepIndex or tostring(stepIndex) ~= suffix then
		return false
	end
	-- Re-read the current guide to avoid trusting stale rows after chapter changes
	local engine = Engine()
	if not engine or InCombatLockdown() then
		return false
	end
	local currentGuide = engine.currentGuide
	if not currentGuide or currentGuide.name ~= name or currentGuide.group ~= group then
		return false
	end
	return Guide.Skip(stepIndex)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", Guide.Refresh)
EventUtil.ContinueOnAddOnLoaded("RXPGuides", Attach)
EventUtil.ContinueAfterAllEvents(function()
	ready = true
	Attach()
end, "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD")
