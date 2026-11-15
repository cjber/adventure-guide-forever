---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end
---@class AGFRestedXPModule : AGFRestedXPAdapter
local Guide = {}
ns.RestedXP = Guide
---@type fun()[]
local listeners = {}
local active, ready, queued = false, false, false
-- Whether AGF currently hides or suppresses any RestedXP frame, map line or arrow. Information mode gives those back
-- only when this is true, so a session that starts in the mode never restores what it did not take.
local suppressing = false
---@type AGFRXPSnapshot
local snapshot = { name = "", group = "", index = 0, total = 0, steps = {} }
local signature = ""
local autoSelected
---@type table<Frame, {alpha: number, mouse: boolean}>
local mapLines = {}
local PREVIEW_STEPS = 10
-- The mark a guide card carries (UI/Panel.lua): RestedXP's guide window names the logo it draws, so the card reads the
-- exact installed path, custom themes included, and never guesses at its folder. Without that path the card keeps its
-- kind icon and only the tooltip names the provider (#713).
local PROVIDER = "RestedXP"

---@type AGFRXPEngine?
local registered
local receiver = {}
---@type table<AGFRXPWindow, {alpha: number, points: table[], dontSave: boolean, savePosition?: boolean}>
local windows = {}
---@type table<Frame, boolean>
local clamps = {}
-- RestedXP's own item and target windows, hidden while AGF draws native-styled replacements: whether each was shown
-- before AGF hid it, so stopping AGF gives the native frontend back rather than leaving two silent frames off.
---@type table<AGFRXPWindow, boolean>
local actionFrames = {}
-- A skip asked for in combat, made once it ends: RestedXP moves its secure item buttons with the step.
---@type {group: string, name: string, index: integer, elementIndex?: integer}?
local pendingSkip

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

-- The companion addon behind a guide card, and the mark it draws: the card names both, so Adventure Guide's own cards
-- stay told apart from an imported guide's (#713).
---@return string
function Guide.Provider()
	return PROVIDER
end

-- The mark RestedXP draws in its own guide window, so a guide card uses the provider's own installed art. The current
-- v2 interface names a 256-square logo in its theme; the legacy guide window asks its theme for the 64-square logo it
-- draws, which a legacy theme must carry. The file is read, never copied, and a client that can name neither keeps the
-- card's kind icon (#713).
---@return string?
function Guide.ProviderIcon()
	local engine = Engine()
	if not engine then
		return nil
	end
	local v2 = engine.v2
	if v2 then
		local theme = v2.activeTheme
		if not theme and type(v2.GetTheme) == "function" then
			theme = v2:GetTheme()
		end
		local logo = theme and theme.guideWindow and theme.guideWindow.logo
		if type(logo) == "string" and logo ~= "" then
			return logo
		end
	end
	if type(engine.GetV1Texture) == "function" then
		-- The legacy guide window itself requests the 64-square logo, so that is the one a legacy theme must carry.
		local icon = engine.GetV1Texture("rxp_logo-64")
		if type(icon) == "string" and icon ~= "" then
			return icon
		end
	end
end

-- The role each colour RestedXP drew with stands for: its defaults and the player's own.
---@param engine AGFRXPEngine
---@return table<string, string>
local function Roles(engine)
	local roles = {}
	local colors = engine.guideTextColors
	local default = colors and colors.default
	for _, set in ipairs({ type(default) == "table" and default or {}, colors or {} }) do
		for role, hex in pairs(set) do
			if type(role) == "string" and role:find("^RXP_%u+_$") and type(hex) == "string" then
				roles[hex:upper()] = role
			end
		end
	end
	return roles
end

-- The words RestedXP drew, in the client's colours, and the first friendly NPC they name (the step's target).
---@param engine AGFRXPEngine
---@param value string?
---@param element? AGFRXPElement
---@return string text
---@return string? npc
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
	value = value:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	-- Each coloured span (by RestedXP's token or the colour it put there) is set aside by its role, every other colour
	-- code goes, then the spans take the client's colours.
	local roles = Roles(engine)
	value = value:gsub("|c(RXP_%u+_)(.-)|r", "\001%1\002%2\003"):gsub("|c(%x%x%x%x%x%x%x%x)(.-)|r", function(hex, inner)
		local role = roles[hex:upper()]
		return role and ("\001" .. role .. "\002" .. inner .. "\003") or inner
	end)
	value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	local npc
	value = value:gsub("\001(.-)\002(.-)\003", function(role, inner)
		npc = npc or (role == "RXP_FRIENDLY_" and inner ~= "" and inner or nil)
		local item = (role == "RXP_LOOT_" or role == "RXP_BUY_")
				and element
				and element.tag
				and element.tag:find("^collect")
				and tonumber(element.id)
			or nil
		return ns.StepStyle.Wrap(ns.StepStyle.Color(role, item), inner)
	end)
	-- A quest the line takes or hands in is named in the quest title's gold.
	local quest = element and (element.tag == "accept" or element.tag == "turnin") and element.questId
	local title = quest and (ns.State.QuestTitle(quest) or (ns.Data.quests[quest] and ns.Data.quests[quest].title))
	local at = title and value:find(title, 1, true)
	if title and at then
		value = value:sub(1, at - 1) .. ns.StepStyle.Quest(title) .. value:sub(at + #title)
	end
	-- Progress as the game's tracker writes it: "3/7 Small Spider Leg", not "Small Spider Leg: 3/7" (#353).
	return (value:gsub("^(.-):%s*(%d+/%d+)$", "%2 %1")), npc
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

---@param frame Frame
local function Reclamp(frame)
	if clamps[frame] ~= nil then
		frame:SetClampedToScreen(clamps[frame])
		clamps[frame] = nil
	end
	for _, child in ipairs({ frame:GetChildren() }) do -- multi-value: Unclamp went through every descendant.
		Reclamp(child)
	end
end

---@param frame AGFRXPWindow?
local function Unwindow(frame)
	local saved = frame and windows[frame]
	if not frame or not saved then
		return
	end
	frame.savePosition = saved.savePosition
	frame:SetDontSavePosition(saved.dontSave)
	frame:SetAlpha(saved.alpha)
	frame:ClearAllPoints()
	for _, point in ipairs(saved.points) do
		frame:SetPoint(unpack(point))
	end
	windows[frame] = nil
	Reclamp(frame)
end

local function Restore()
	for frame, saved in pairs(mapLines) do
		frame:SetAlpha(saved.alpha)
		frame:EnableMouse(saved.mouse)
	end
	mapLines = {}
	for frame in pairs(windows) do
		Unwindow(frame)
	end
	for frame, clamped in pairs(clamps) do
		frame:SetClampedToScreen(clamped)
	end
	windows, clamps = {}, {}
end

-- AGF's replacements are secure buttons: showing, hiding or reparenting their native counterparts waits for combat's
-- end, which Sync already does. RestedXP's own updates decide its windows' contents, so restoring then asks the engine
-- to lay them out again instead of guessing what it would have shown.
---@param frame? AGFRXPWindow
local function SuppressAction(frame)
	if not frame then
		return
	end
	if actionFrames[frame] == nil then
		actionFrames[frame] = frame:IsShown()
	end
	frame:Hide()
end

---@param engine? AGFRXPEngine
local function RestoreActions(engine)
	if not next(actionFrames) then
		return
	end
	for frame, shown in pairs(actionFrames) do
		frame:SetShown(shown)
	end
	actionFrames = {}
	if not engine then
		return
	end
	if type(engine.UpdateItemFrame) == "function" then
		engine.UpdateItemFrame()
	end
	if engine.targeting and type(engine.targeting.UpdateTargetFrame) == "function" then
		engine.targeting:UpdateTargetFrame()
	end
end

local function GuideKey(group, name)
	return "guide:" .. tostring(#group) .. ":" .. group .. ":" .. tostring(#name) .. ":" .. name
end

-- Guide steps the player skipped while RestedXP had not reached them, kept on the character: RestedXP marks such a
-- step only in memory (`step.completed`), so without this the guide is back at the same step after a /reload (#374).
-- RestedXP passes over a completed step when it reaches it; entries go once RestedXP's own progress is past them.
---@param engine AGFRXPEngine
local function ApplySkips(engine)
	local guide = engine.currentGuide
	if not guide or guide.empty then
		return
	end
	local prefs = ns.Prefs()
	local key = GuideKey(guide.group or "", guide.name or "")
	local skips = prefs.guideSkips and prefs.guideSkips[key]
	if not skips then
		return
	end
	local progress = engine.GetGuideProgress()
	local current = guide.steps[progress]
	-- After a reload RestedXP starts from its own saved step, which can be one the player skipped: hand it on, as its
	-- own skip of the step under way does.
	if current and not current.sticky and skips[progress] then
		engine.SetStep(progress + 1)
		return
	end
	for index in pairs(skips) do
		local step = guide.steps[index]
		if not step or index < progress then
			skips[index] = nil
		elseif not step.active and not step.completed then
			step.completed = true
		end
	end
	if not next(skips) then
		prefs.guideSkips[key] = nil
	end
end

---@param group string
---@param name string
---@param index integer
local function RememberSkip(group, name, index)
	local prefs = ns.Prefs()
	prefs.guideSkips = prefs.guideSkips or {}
	local key = GuideKey(group, name)
	prefs.guideSkips[key] = prefs.guideSkips[key] or {}
	prefs.guideSkips[key][index] = true
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

-- The step's usable items as data: the guide says which IDs it wants; whether the bags hold one and whether the
-- player can use it now is the client's answer, read where the button is drawn.
---@param step AGFRXPStep
---@return AGFRXPItem[]
local function StepItems(step)
	local items, seen = {}, {}
	for id, wanted in pairs(step.activeItems or {}) do
		if wanted ~= false and type(id) == "number" and id > 0 and not seen[id] then
			seen[id] = true
			items[#items + 1] = { id = id }
		end
	end
	table.sort(items, function(a, b)
		return a.id < b.id
	end)
	return items
end

-- The step's talk and kill targets, once each, friendly first. RestedXP resolves its elements' NPC IDs to names before
-- they reach this snapshot; an unresolved number has no name a macro could use.
---@param step AGFRXPStep
---@return AGFRXPTarget[]
local function StepTargets(step)
	local targets, seen = {}, {}
	local order = { target = 1, mob = 2, unitscan = 3 }
	local function Add(list, kind)
		for _, name in ipairs(list or {}) do
			if type(name) == "string" and name ~= "" and not seen[name] then
				seen[name] = true
				targets[#targets + 1] = { name = name, kind = kind }
			end
		end
	end
	for _, element in ipairs(step.elements or {}) do
		Add(element.targets, "target")
		Add(element.mobs, "mob")
		Add(element.unitscan, "unitscan")
	end
	table.sort(targets, function(a, b)
		return order[a.kind] == order[b.kind] and a.name < b.name or order[a.kind] < order[b.kind]
	end)
	return targets
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
		if not step.index or seen[step.index] or step.hidewindow or step.hidetip or (preview and step.completed) then
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
			title = (Text(engine, step.title or ns.L.RXP_STEP:format(step.index))),
			titled = type(step.title) == "string",
			sticky = not preview and not not step.sticky,
			preview = not not preview,
			lines = {},
			items = StepItems(step),
			targets = StepTargets(step),
			map = map,
			x = sx,
			y = sy,
		}
		for index, element in ipairs(step.elements or {}) do
			local text, npc = Text(engine, element.text or element.tooltipText or element.rawtext, element)
			if text ~= "" and not element.hideTooltip and not element.hidden then
				local done = not preview and not element.textOnly and not not (element.completed or element.skip)
				-- Who the step is for: the first NPC an open line names, else any line's.
				if npc and (not row.target or not (done or row.targetOpen)) then
					row.target, row.targetOpen = npc, not done
				end
				row.lines[#row.lines + 1] = {
					text = text,
					done = done,
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

-- `key` is a RestedXP guide's and RestedXP has no guide loaded yet, with its guide mode on: its empty guide while
-- purchased guides import at login, or the frames between two guide loads. A chosen guide waits through this rather
-- than ending, and nothing starts or untracks over it (#368).
---@param key? string
---@return boolean
function Guide.Awaits(key)
	return key ~= nil and key:find("^guide:") ~= nil and snapshot.name == "" and Guide.Enabled()
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
		local browsing = ns.Setting("informationOnly") == true
		if browsing then
			-- Information mode keeps the guide readable, but gives back anything AGF suppressed and runs none of its
			-- automatic workflow: no hide/show, no map-line removal, no skips, no arrow, no guide selection.
			if suppressing then
				Restore()
				RestoreActions(engine)
				if engine.UpdateMap then
					engine.UpdateMap(true)
				end
				suppressing = false
			end
			pendingSkip = nil
			snapshot = Snapshot(engine)
		else
			suppressing = true
			Window(engine.RXPFrame)
			Window(LibDBIcon10_RXPGuides)
			SuppressMap(engine)
			Window(engine.v2 and engine.v2.state and engine.v2.state.guideWindow and engine.v2.state.guideWindow.frame)
			-- AGF's tracker draws native-styled item and target buttons in its own section (#334): RestedXP's own windows
			-- are hidden only while those buttons are actually shown, and come back when the tracker setting, a collapsed
			-- section or a step without actions leaves them off.
			if ns.RXPActions and ns.RXPActions.Shown() then
				SuppressAction(engine.activeItemFrame)
				SuppressAction(engine.targeting and engine.targeting.activeTargetFrame)
			else
				RestoreActions(engine)
			end
			-- A step the player skipped ahead of RestedXP stays skipped, after a /reload too (#374).
			ApplySkips(engine)
			snapshot = Snapshot(engine)
			-- With Shortest Path loaded, its arrow points at the step handed to it, so RXP's arrow never shows as a second
			-- one. Without it, RXP's arrow is the guide's only arrow: it goes only while another journey is chosen, so it
			-- never points somewhere other than the route being followed.
			local chosen = ns.Prefs().journey
			if
				ns.Integrations.Provider() ~= nil
				or (snapshot.name ~= "" and chosen ~= nil and chosen ~= GuideKey(snapshot.group, snapshot.name))
			then
				Window(engine.arrowFrame)
			else
				Unwindow(engine.arrowFrame)
			end
			local skip = pendingSkip
			pendingSkip = nil
			if skip and skip.group == snapshot.group and skip.name == snapshot.name then
				Guide.Skip(skip.index, skip.elementIndex)
			end
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
		end
	else
		suppressing = false
		Restore()
		RestoreActions(engine)
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
		for _, item in ipairs(step.items or {}) do
			parts[#parts + 1] = "item:" .. tostring(item.id)
		end
		for _, target in ipairs(step.targets or {}) do
			parts[#parts + 1] = "target:" .. target.kind .. ":" .. target.name
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
		-- ResetArrowPosition moves RestedXP's arrow back on screen: Sync hides it again while Shortest Path leads.
		for _, method in ipairs({ "UpdateItemFrame", "ResetItemPosition", "ResetArrowPosition" }) do
			if type(engine[method]) == "function" then
				hooksecurefunc(engine, method, Guide.Refresh) -- taint-ok: RestedXP owns its item and arrow controllers.
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
	local providerIcon = Guide.ProviderIcon()
	-- RestedXP ships one zone's guide in more than one group (the speedrun and dungeon routes both have "06-11
	-- Teldrassil"): the running guide's card stands for every guide of its name, so it is never offered twice (#364).
	local running = current and snapshot.name ~= "" and snapshot.name or nil
	local level = ns.State.Player().level
	for _, entry in ipairs(Guide.Guides()) do
		local key = GuideKey(entry.group, entry.name)
		if not seen[key] and entry.name ~= running and not ns.Prefs().notInterested[key] then
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
					provider = Guide.Provider(),
					providerIcon = providerIcon,
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
---@return boolean selected false when the engine refused the guide (none loaded, or in combat)
function Guide.Choose(group, name, start)
	if not Guide.Select(group, name) then
		return false
	end
	C_Timer.After(0, function()
		local current = Guide.Snapshot()
		local journey = Guide.Journey()
		if journey and current.name == name and current.group == group then
			ns.Choose(journey.key, start)
		end
	end)
	return true
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
	local guide = engine and engine.currentGuide
	local step = guide and guide.steps[index]
	if not engine or not guide or not active or not step then
		return false
	end
	if InCombatLockdown() then
		pendingSkip = { group = guide.group or "", name = guide.name or "", index = index, elementIndex = elementIndex }
		return true
	end
	if not step.active then
		-- A step still ahead: RXP passes over a completed step when the guide reaches it, as with its own skips. That
		-- mark lives in memory only, so it is kept on the character and put back at every build and after a /reload.
		if elementIndex or step.sticky or index <= (engine.GetGuideProgress()) then
			return false
		end
		step.completed = true
		RememberSkip(guide.group or "", guide.name or "", index)
	elseif elementIndex then
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
							local nodes = ns.Planner.Steps.Nodes(ns.Data, entry, ns.State.Player().level)
							for _, node in ipairs(nodes) do
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
						rxpTag = line.tag,
						rxpQuest = line.questId,
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
					-- What a walk there is to (Integrations' travel line, Shortest Path's stop): the NPC the step
					-- names, else for a step RestedXP left untitled ("Step 96") the zone it is in (#361).
					place = row.target or (not row.titled and row.map > 0 and ns.State.ZoneName(row.map)) or nil,
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
	-- RestedXP hides some current steps from its window (a step only it acts on), so the step it shows next leads,
	-- as in its own window: the step under way is never a read-only preview, or nothing would hand it on (#361).
	local lead = steps[1]
	if lead and lead.preview then
		lead.preview = false
	end
	local subline = snapshot.total > 0 and ns.L.RXP_PROGRESS:format(snapshot.index, snapshot.total) or ns.L.RXP_NO_GUIDE
	---@type AGFJourney
	return {
		kind = "guide",
		section = "continue",
		key = guideKey,
		title = name,
		subline = subline,
		provider = Guide.Provider(),
		providerIcon = Guide.ProviderIcon(),
		map = firstMap,
		steps = steps,
		guideStep = snapshot.total > 0 and snapshot.index or nil,
		guideSteps = snapshot.total > 0 and snapshot.total or nil,
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
	if not engine then
		return false
	end
	local currentGuide = engine.currentGuide
	if not currentGuide or currentGuide.name ~= name or currentGuide.group ~= group then
		return false
	end
	return Guide.Skip(stepIndex)
end

-- Whether a RestedXP element's event list carries `event`: the element's own (`element.event`) or its tag's.
---@param list string|string[]?
---@param event string
---@return boolean
local function Listens(list, event)
	if type(list) == "string" then
		return list == event
	elseif type(list) == "table" then
		for _, name in ipairs(list) do
			if name == event then
				return true
			end
		end
	end
	return false
end

-- RestedXP completes a step element only from a callback bound to a frame in its guide window's step list, which
-- Adventure Guide keeps hidden, so a turned-in or accepted quest does not always reach the step (#374). Its own
-- callbacks read the quest and item state themselves, so running them again for the steps under way completes a step
-- whose event they missed, and changes nothing when they already saw it.
---@param engine AGFRXPEngine
---@param event string
local function Recount(engine, event, ...)
	local functions = engine.functions
	local set = type(functions) == "table" and functions.events
	if not active or InCombatLockdown() or type(functions) ~= "table" or type(set) ~= "table" then
		return
	end
	for _, step in ipairs(engine.RXPFrame.activeSteps or {}) do
		if step.active then
			for _, element in ipairs(step.elements or {}) do
				local tag = element.tag
				local callback = tag and functions[tag]
				if
					not element.completed
					and type(callback) == "function"
					and Listens(element.event or set[tag], event)
				then
					local carrier = { element = element, step = step, button = element.frame and element.frame.button }
					if type(engine.Call) == "function" then
						engine.Call(tag, callback, carrier, event, ...) -- multi-value: the event's arguments reach RXP's callback.
					else
						pcall(callback, carrier, event, ...) -- multi-value: the event's arguments reach RXP's callback.
					end
				end
			end
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, ...)
	local engine = Engine()
	if engine then
		Recount(engine, event, ...) -- multi-value: QUEST_TURNED_IN names its quest and its experience.
	end
	Guide.Refresh()
end)
EventUtil.ContinueOnAddOnLoaded("RXPGuides", Attach)
EventUtil.ContinueAfterAllEvents(function()
	ready = true
	-- Choosing another journey, or the guide again, decides whether RXP's arrow shows without Shortest Path.
	hooksecurefunc(ns, "Choose", Guide.Refresh) -- taint-ok: Adventure Guide owns this addon table.
	Attach()
end, "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD")
