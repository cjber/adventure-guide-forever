-- Headless client for the UI specs. `harness.load(options)` loads AdventureGuideForever.toc in order into a fresh
-- global environment, against stubs of only the client API the addon calls, and returns a handle to drive it.
-- Forked from wow-handoff's scratch/harness2.lua (frame, texture and font-string stubs, visibilityChanged,
-- animationGroup, the tracker module's block stubs), without its Shortest Path parts. Paths are relative to the
-- repository root: run the specs from there.
local harness = {}

local ADDON = "AdventureGuideForever"

local function noop() end

-- IsObjectType walks this chain, as the client's widget hierarchy does.
local SUPER = {
	Frame = "Region",
	Button = "Frame",
	CheckButton = "Button",
	DropdownButton = "Button",
	EditBox = "Frame",
	ScrollFrame = "Frame",
	Texture = "Region",
	MaskTexture = "Region",
	FontString = "Region",
	Line = "Region",
}

local function IsFrame(objectType)
	while objectType and objectType ~= "Frame" do
		objectType = SUPER[objectType]
	end
	return objectType == "Frame"
end

local function animationGroup(owner)
	local group = { owner = owner, animations = {}, plays = 0 }
	function group:CreateAnimation(kind)
		local animation = { kind = kind }
		for _, key in ipairs({ "Duration", "Degrees", "FromAlpha", "ToAlpha", "Smoothing", "Order", "Target" }) do
			animation["Set" .. key] = function(this, value)
				this[key] = value
			end
		end
		self.animations[#self.animations + 1] = animation
		return animation
	end
	function group:SetLooping(value)
		self.looping = value
	end
	function group:Play()
		self.playing = true
		self.plays = self.plays + 1
	end
	function group:Restart()
		self:Play()
	end
	function group:Stop()
		self.playing = false
	end
	function group:IsPlaying()
		return self.playing == true
	end
	return group
end

-- A tiny reader for the addon's own XML: tags and attributes only, which is all Panel.xml uses.
local function ParseXML(text)
	text = text:gsub("<!%-%-.-%-%->", ""):gsub("<%?.-%?>", "")
	local root = { tag = "#root", attrs = {}, children = {} }
	local stack = { root }
	for close, tag, attrs, empty in text:gmatch("<(/?)([%w_:]+)(.-)(/?)>") do
		if close == "/" then
			local open = table.remove(stack)
			assert(open.tag == tag, "unbalanced </" .. tag .. "> after <" .. open.tag .. ">")
		else
			local node = { tag = tag, attrs = {}, children = {} }
			for key, value in attrs:gmatch('([%w_:]+)="(.-)"') do
				node.attrs[key] = value
			end
			local parent = stack[#stack]
			parent.children[#parent.children + 1] = node
			if empty ~= "/" then
				stack[#stack + 1] = node
			end
		end
	end
	assert(#stack == 1, "unclosed <" .. stack[#stack].tag .. ">")
	return root
end

-- options: spf ("v1" or "v1+"; absent by default), db and charDB (saved variables), log ({id, title, level,
-- complete, map, x, y} entries), completed (quest IDs), player (overrides), initialLogin (default true), waypoint
-- (the user waypoint the client kept across a /reload, a UiMapPoint), completedPending (the client has no completed
-- quests to give until the spec sets h.completedPending to false).
function harness.load(options)
	options = options or {}
	local G = setmetatable({}, { __index = _G })
	G._G = G
	local h = {
		G = G,
		ns = {},
		errors = {},
		frames = {},
		prints = {},
		uiErrors = {},
		tooltip = {},
		pins = {},
		providers = {},
		counts = { CreateFrame = 0, displayModeWrites = 0, tickers = 0, AcquirePin = 0, SetMapID = 0 },
		modelCalls = {},
		waypoint = options.waypoint,
		combat = false,
	}
	local player = {
		level = 18,
		faction = "Horde",
		raceID = 2,
		classID = 7,
		map = 1413,
		x = 0.52,
		y = 0.30,
	}
	for key, value in pairs(options.player or {}) do
		player[key] = value
	end
	h.player = player
	h.completedPending = options.completedPending

	-- Errors never stop the run: like the client's error handler they are collected, and specs assert none.
	function h.call(fn, ...)
		local n, args = select("#", ...), { ... }
		local ok, err = xpcall(function()
			return fn(unpack(args, 1, n))
		end, debug.traceback)
		if not ok then
			h.errors[#h.errors + 1] = err
		end
	end

	--[[ Regions ]]

	-- Unlike harness2, an unknown method is an error, not a silent no-op, so a field test such as
	-- `frame.Edge ~= nil` means what it says and each new client call is stubbed on purpose.
	local Methods = {}
	local regionMeta = { __index = Methods }
	-- Client methods whose effect no spec reads: accepted and ignored.
	for _, name in ipairs({
		"EnableMouse",
		"RegisterForClicks",
		"SetMaxLetters",
		"SetShadowOffset",
	}) do
		Methods[name] = noop
	end
	-- Setters no spec reads but tools/screenshots.py draws: each stores its arguments under `field` for h.Describe.
	for name, field in pairs({
		SetHighlightFontObject = "highlightFont",
		SetJustifyH = "justifyH",
		SetTexCoord = "texCoord",
		SetWordWrap = "wordWrap",
	}) do
		Methods[name] = function(self, first, ...)
			self[field] = select("#", ...) > 0 and { first, ... } or first -- multi-value: every argument
		end
	end
	local function visibilityChanged(frame, shown)
		local script = frame.scripts and frame.scripts[shown and "OnShow" or "OnHide"]
		if script then
			h.call(script, frame)
		end
		for _, child in ipairs(frame.childFrames or {}) do
			if child:IsShown() then
				visibilityChanged(child, shown)
			end
		end
	end

	-- `internal` regions belong to a stock template: code can reach them by key, but they are not listed by
	-- GetChildren/GetRegions, so a layout dump shows the stock template itself and none of its innards.
	local function NewRegion(objectType, name, parent, internal)
		local region = setmetatable({ objectType = objectType, name = name, parent = parent, points = {} }, regionMeta)
		if IsFrame(objectType) then
			region.scripts, region.childFrames, region.regions = {}, {}, {}
			h.frames[#h.frames + 1] = region
		end
		if parent and not internal then
			local list = region.childFrames and parent.childFrames or parent.regions
			list[#list + 1] = region
		end
		if name then
			G[name] = region
		end
		return region
	end

	function Methods:GetObjectType()
		return self.objectType
	end
	function Methods:IsObjectType(objectType)
		local current = self.objectType
		while current do
			if current == objectType then
				return true
			end
			current = SUPER[current]
		end
		return false
	end
	function Methods:GetName()
		return self.name
	end
	function Methods:GetParent()
		return self.parent
	end
	function Methods:GetParentKey()
		return self.parentKey
	end
	function Methods:IsShown()
		return not self.hidden
	end
	function Methods:IsVisible()
		return not self.hidden and (not self.parent or self.parent:IsVisible())
	end
	function Methods:Show()
		local wasVisible = self:IsVisible()
		self.hidden = false
		if not wasVisible and self:IsVisible() then
			visibilityChanged(self, true)
		end
	end
	function Methods:Hide()
		if self.hidden then
			return
		end
		local wasVisible = self:IsVisible()
		self.hidden = true
		if wasVisible then
			visibilityChanged(self, false)
		end
	end
	function Methods:SetShown(shown)
		if shown then
			self:Show()
		else
			self:Hide()
		end
	end
	function Methods:SetAlpha(alpha)
		self.alpha = alpha
	end
	function Methods:GetAlpha()
		return self.alpha or 1
	end

	-- Anchors keep every point, normalised to the client's GetPoint form: point, relativeTo, relativePoint, x, y.
	function Methods:SetPoint(point, a, b, c, d)
		local relativeTo, relativePoint, x, y
		if type(a) == "number" then
			x, y = a, b
		elseif a ~= nil then
			relativeTo = a
			if type(b) == "string" then
				relativePoint, x, y = b, c, d
			else
				x, y = b, c
			end
		end
		if type(relativeTo) == "string" then
			relativeTo = G[relativeTo]
		end
		local anchor = { point, relativeTo or self.parent, relativePoint or point, x or 0, y or 0 }
		for index, existing in ipairs(self.points) do
			if existing[1] == point then
				self.points[index] = anchor
				return
			end
		end
		self.points[#self.points + 1] = anchor
	end
	function Methods:SetAllPoints(relativeTo)
		relativeTo = relativeTo or self.parent
		self.points = { { "TOPLEFT", relativeTo, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", relativeTo, "BOTTOMRIGHT", 0, 0 } }
	end
	function Methods:ClearAllPoints()
		self.points = {}
	end
	function Methods:GetNumPoints()
		return #self.points
	end
	function Methods:GetPoint(index)
		local anchor = self.points[index or 1]
		if anchor then
			return anchor[1], anchor[2], anchor[3], anchor[4], anchor[5]
		end
	end

	-- No layout engine: a size is only what was set explicitly, which is what GetSize(true) reports in game. Only
	-- h.SetRects (tools/screenshots.py's layout pass) gives regions a laid-out rect; specs never do, so there the
	-- edges stay nil and a size is the explicit one.
	function Methods:SetSize(width, height)
		self.width, self.height = width, height
	end
	function Methods:SetWidth(width)
		self.width = width
	end
	function Methods:SetHeight(height)
		self.height = height
	end
	function Methods:GetSize(explicit)
		if self.rect and not explicit then
			return self.rect[3], self.rect[4]
		end
		return self.width or 0, self.height or 0
	end
	function Methods:GetWidth()
		return (self:GetSize())
	end
	function Methods:GetHeight()
		return (select(2, self:GetSize()))
	end
	function Methods:GetLeft()
		return self.rect and self.rect[1]
	end
	function Methods:GetBottom()
		return self.rect and self.rect[2]
	end
	function Methods:GetRight()
		return self.rect and self.rect[1] + self.rect[3]
	end
	function Methods:GetTop()
		return self.rect and self.rect[2] + self.rect[4]
	end
	function Methods:GetEffectiveScale()
		return 1
	end

	-- Frames.
	function Methods:SetScript(scriptType, fn)
		self.scripts[scriptType] = fn
	end
	function Methods:GetScript(scriptType)
		return self.scripts[scriptType]
	end
	function Methods:HookScript(scriptType, fn)
		local original = self.scripts[scriptType]
		self.scripts[scriptType] = function(...)
			if original then
				original(...)
			end
			fn(...)
		end
	end
	function Methods:HasScript()
		return true
	end
	function Methods:RegisterEvent(event)
		self.events = self.events or {}
		self.events[event] = true
	end
	function Methods:UnregisterEvent(event)
		if self.events then
			self.events[event] = nil
		end
	end
	function Methods:GetChildren()
		return unpack(self.childFrames) -- multi-value: every child, as the client returns them
	end
	function Methods:GetRegions()
		return unpack(self.regions) -- multi-value: every region, as the client returns them
	end
	function Methods:SetFrameLevel(level)
		self.level = level
	end
	function Methods:GetFrameLevel()
		return self.level or 0
	end
	function Methods:CreateTexture(name, layer)
		local texture = NewRegion("Texture", name, self)
		texture.layer = layer
		return texture
	end
	function Methods:CreateMaskTexture(name, layer)
		local texture = NewRegion("MaskTexture", name, self)
		texture.layer = layer
		return texture
	end
	function Methods:CreateFontString(name, layer, font)
		local text = NewRegion("FontString", name, self)
		text.layer, text.font = layer, font
		return text
	end
	function Methods:CreateLine(name, layer)
		local line = NewRegion("Line", name, self)
		line.layer = layer
		return line
	end
	function Methods:CreateAnimationGroup()
		local group = animationGroup(self)
		self.animationGroups = self.animationGroups or {}
		self.animationGroups[#self.animationGroups + 1] = group
		return group
	end
	function Methods:SetScrollChild(child)
		self.scrollChild = child
	end
	function Methods:SetupMenu(generator)
		self.menuGenerator = generator
	end
	function Methods:SetCustomOnMouseUpHandler(handler)
		self.mouseUpHandler = handler
	end
	function Methods:SetChecked(checked)
		self.checked = checked
	end
	function Methods:GetChecked()
		return self.checked == true
	end

	-- Buttons.
	function Methods:SetEnabled(enabled)
		self.disabled = not enabled
	end
	function Methods:IsEnabled()
		return not self.disabled
	end
	function Methods:SetNormalAtlas(atlas)
		self.normalAtlas = atlas
	end
	function Methods:SetHighlightAtlas(atlas)
		self.highlightAtlas = atlas
	end
	function Methods:SetNormalFontObject(font)
		self.normalFont = font
	end
	function Methods:LockHighlight()
		self.highlightLocked = true
	end
	function Methods:UnlockHighlight()
		self.highlightLocked = false
	end

	-- Textures.
	function Methods:SetAtlas(atlas, useAtlasSize)
		self.atlas, self.useAtlasSize, self.file, self.color = atlas, useAtlasSize == true, nil, nil
	end
	function Methods:GetAtlas()
		return self.atlas
	end
	function Methods:SetTexture(file)
		self.file, self.atlas = file, nil
	end
	function Methods:SetColorTexture(r, g, b, a)
		self.color, self.atlas = { r, g, b, a }, nil
	end

	-- Text: font strings, buttons and edit boxes. An edit box's OnTextChanged fires on every change.
	function Methods:SetText(text)
		self.text = text
		if self.objectType == "EditBox" and self.scripts.OnTextChanged then
			h.call(self.scripts.OnTextChanged, self, self.userInput == true)
		end
	end
	function Methods:SetFormattedText(format, ...)
		self:SetText(format:format(...))
	end
	function Methods:GetText()
		if self.objectType == "EditBox" then
			return self.text or ""
		end
		return self.text
	end
	function Methods:GetStringWidth()
		return #(self.text or "") * 6
	end
	-- A button's label, as wide as a font string's.
	Methods.GetTextWidth = Methods.GetStringWidth
	function Methods:GetStringHeight()
		return 12
	end
	function Methods:SetFontObject(font)
		self.font = font
	end
	function Methods:GetFontObject()
		local name = self.font
		if type(name) == "table" then
			return name
		end
		return name and {
			GetName = function()
				return name
			end,
		}
	end

	--[[ Templates: AGF's own from its XML, stock ones by name ]]

	local templates = {}

	local function Internal(objectType, parent, key)
		local region = NewRegion(objectType, nil, parent, true)
		region.parentKey = key
		parent[key] = region
		parent.internals = parent.internals or {}
		parent.internals[key] = region
		return region
	end

	-- The tracker module's block stubs from harness2: a block records its header and objective lines.
	local function TrackerModule(module)
		module.liveBlocks, module.layoutOrder = {}, {}
		Internal("FontString", Internal("Frame", module, "Header"), "Text")
		function module:SetHeader(text)
			self.Header.Text:SetText(text)
		end
		function module:GetBlock(id)
			local block = self.liveBlocks[id]
			if not block then
				block = { id = id, lines = {}, order = {}, dashes = {} }
				block.SetHeader = function(this, text)
					this.header = text
				end
				block.AddObjective = function(this, key, text, _, _, dashStyle)
					if not this.lines[key] then
						this.order[#this.order + 1] = key
					end
					this.lines[key], this.dashes[key] = text, dashStyle
					return { Text = {
						GetText = function()
							return text
						end,
					} }
				end
				self.liveBlocks[id] = block
			end
			block.used = true
			return block
		end
		function module:LayoutBlock(block)
			self.layoutOrder[#self.layoutOrder + 1] = block.id
			return true
		end
		function module:GetContextMenuParent()
			return self
		end
		function module:MarkDirty()
			self.layoutOrder = {}
			for _, block in pairs(self.liveBlocks) do
				block.used, block.lines, block.order, block.dashes = false, {}, {}, {}
			end
			h.call(self.LayoutContents, self)
		end
	end

	local STOCK = {
		-- Mainline/SharedUIPanelTemplates.xml:1587 and .lua:1763: the highlight is the normal art, or the pushed art
		-- while the mouse is down.
		AlphaHighlightButtonTemplate = function(frame)
			function frame.UpdateHighlightForState(self)
				local art = self.isPressed and self.PushedTexture or self.NormalTexture
				self:SetHighlightAtlas(art:GetAtlas())
			end
			frame.scripts.OnLoad = frame.UpdateHighlightForState
		end,
		InputBoxVisualTemplate = noop,
		UIPanelIconDropdownButtonTemplate = noop,
		QuestLogBorderFrameTemplate = noop,
		UIPanelButtonTemplate = noop,
		SearchBoxTemplate = function(frame)
			Internal("FontString", frame, "Instructions")
		end,
		ScrollFrameTemplate = function(frame)
			Internal("Frame", frame, "ScrollBar")
		end,
		LargeSideTabButtonTemplate = function(frame)
			Internal("Texture", frame, "Icon")
		end,
		ObjectiveTrackerModuleTemplate = TrackerModule,
	}

	local ApplyTemplate

	-- Anchors are applied after the whole template is built, so a relativeKey may name a later sibling.
	local function Anchor(region, node, deferred)
		deferred[#deferred + 1] = function()
			local attrs, relativeTo = node.attrs, nil
			if attrs.relativeKey then
				relativeTo = region
				for part in attrs.relativeKey:gmatch("[^.]+") do
					relativeTo = part == "$parent" and relativeTo:GetParent() or relativeTo[part]
				end
			elseif attrs.relativeTo then
				relativeTo = G[attrs.relativeTo]
			end
			local x, y = tonumber(attrs.x), tonumber(attrs.y)
			for _, child in ipairs(node.children) do
				assert(child.tag == "Offset", "unsupported <" .. child.tag .. "> in <Anchor>")
				x, y = tonumber(child.attrs.x), tonumber(child.attrs.y)
			end
			region:SetPoint(attrs.point, relativeTo or region.parent, attrs.relativePoint or attrs.point, x, y)
		end
	end

	local Build

	local function BuildRegion(frame, node, layer, deferred)
		local attrs = node.attrs
		local region = NewRegion(node.tag, nil, frame)
		region.layer, region.subLevel = layer.level, tonumber(layer.textureSubLevel)
		if attrs.parentKey then
			region.parentKey = attrs.parentKey
			frame[attrs.parentKey] = region
		end
		if attrs.atlas then
			region:SetAtlas(attrs.atlas, attrs.useAtlasSize == "true")
		end
		if attrs.file then
			region:SetTexture(attrs.file)
		end
		if node.tag == "FontString" then
			region.font = attrs.inherits
			region.text = attrs.text
			region.justifyH = attrs.justifyH
			region.wordWrap = attrs.wordwrap and attrs.wordwrap == "true"
		end
		region.alphaMode = attrs.alphaMode
		region.hidden = attrs.hidden == "true"
		if attrs.setAllPoints == "true" then
			region:SetAllPoints()
		end
		Build(region, node, deferred)
	end

	-- Applies one element's children to a region: sizes, anchors, layers, child frames and scripts.
	function Build(region, node, deferred)
		for _, child in ipairs(node.children) do
			local tag, attrs = child.tag, child.attrs
			if tag == "Size" then
				region:SetSize(tonumber(attrs.x), tonumber(attrs.y))
			elseif tag == "Anchors" then
				for _, anchor in ipairs(child.children) do
					Anchor(region, anchor, deferred)
				end
			elseif tag == "Layers" then
				for _, layer in ipairs(child.children) do
					for _, element in ipairs(layer.children) do
						assert(SUPER[element.tag] == "Region", "unsupported layer <" .. element.tag .. ">")
						BuildRegion(region, element, layer.attrs, deferred)
					end
				end
			elseif tag == "Frames" then
				for _, element in ipairs(child.children) do
					local frame = NewRegion(element.tag, element.attrs.name, region)
					if element.attrs.parentKey then
						frame.parentKey = element.attrs.parentKey
						region[element.attrs.parentKey] = frame
					end
					ApplyTemplate(frame, element, deferred)
				end
			elseif tag == "Scripts" then
				for _, script in ipairs(child.children) do
					local method = assert(script.attrs.method, "only method= scripts are supported")
					region.scripts[script.tag] = function(self, ...)
						return self[method](self, ...) -- multi-value: a script returns what its method returns
					end
				end
			elseif tag == "NormalTexture" or tag == "PushedTexture" then
				-- A button's state art fills the button; the pushed art shows only while it is pressed.
				local art = { tag = "Texture", attrs = attrs, children = child.children }
				BuildRegion(region, art, { level = "ARTWORK" }, deferred)
				local texture = region[assert(attrs.parentKey, "a state texture needs a parentKey")]
				texture:SetAllPoints()
				texture.hidden = tag == "PushedTexture"
			elseif tag == "Color" then
				region:SetColorTexture(tonumber(attrs.r), tonumber(attrs.g), tonumber(attrs.b), tonumber(attrs.a))
			elseif tag == "MaskedTextures" then
				-- No spec sees a mask; the masked texture keeps the mask's file for tools/screenshots.py.
				for _, masked in ipairs(child.children) do
					deferred[#deferred + 1] = function()
						region.parent[masked.attrs.childKey].maskFile = region.file
					end
				end
			else
				error("unsupported <" .. tag .. "> in the addon XML")
			end
		end
	end

	-- A frame element or a named template: its inherits, then its mixin, then its own children, then OnLoad.
	function ApplyTemplate(frame, node, deferred)
		local attrs = node.attrs
		for name in (attrs.inherits or ""):gmatch("[^,%s]+") do
			if templates[name] then
				ApplyTemplate(frame, templates[name], deferred)
			else
				local stock = assert(STOCK[name], "unknown template " .. name .. ": add it to the harness's STOCK list")
				frame.stockTemplate = frame.stockTemplate and frame.stockTemplate .. ", " .. name or name
				stock(frame)
			end
		end
		if attrs.mixin then
			for name in attrs.mixin:gmatch("[^,%s]+") do
				G.Mixin(frame, (assert(G[name], "unknown mixin " .. name)))
			end
		end
		frame.hidden = frame.hidden or attrs.hidden == "true"
		if attrs.setAllPoints == "true" then
			frame:SetAllPoints()
		end
		Build(frame, node, deferred)
	end

	local function Instantiate(frame, templateNames)
		local deferred = {}
		ApplyTemplate(frame, { attrs = { inherits = templateNames }, children = {} }, deferred)
		for _, apply in ipairs(deferred) do
			apply()
		end
		if frame.scripts.OnLoad then
			h.call(frame.scripts.OnLoad, frame)
		end
	end

	local function LoadXML(path)
		local file = assert(io.open(path))
		local tree = ParseXML(file:read("*a"))
		file:close()
		for _, ui in ipairs(tree.children) do
			for _, element in ipairs(ui.children) do
				assert(element.attrs.virtual == "true", path .. ": only virtual templates are supported")
				templates[element.attrs.name] = element
			end
		end
	end

	--[[ The client API ]]

	G.CreateFrame = function(objectType, name, parent, template)
		h.counts.CreateFrame = h.counts.CreateFrame + 1
		local frame = NewRegion(objectType, name, parent)
		if template then
			Instantiate(frame, template)
		end
		return frame
	end

	local timers = {}
	G.C_Timer = {
		After = function(_, fn)
			timers[#timers + 1] = fn
		end,
		NewTicker = function()
			h.counts.tickers = h.counts.tickers + 1
			return { Cancel = noop }
		end,
	}
	-- Runs one frame: the timers queued now, not the ones they queue. Returns how many ran.
	function h.tick()
		local due = timers
		timers = {}
		for _, fn in ipairs(due) do
			h.call(fn)
		end
		return #due
	end
	-- Runs queued timers, and any they queue, the way the next frames would.
	function h.flush()
		for _ = 1, 100 do
			if #timers == 0 then
				return
			end
			local due = timers
			timers = {}
			for _, fn in ipairs(due) do
				h.call(fn)
			end
		end
		error("C_Timer.After keeps queueing itself")
	end

	local loaded, onLoaded, afterAll, fired = {}, {}, {}, {}
	function h.fire(event, ...)
		fired[event] = true
		if event == "ADDON_LOADED" then
			local name = ...
			loaded[name] = true
			for _, callback in ipairs(onLoaded[name] or {}) do
				h.call(callback)
			end
			onLoaded[name] = nil
		end
		for _, frame in ipairs(h.frames) do
			if frame.events and frame.events[event] and frame.scripts.OnEvent then
				h.call(frame.scripts.OnEvent, frame, event, ...)
			end
		end
		for index = #afterAll, 1, -1 do
			local waiting = afterAll[index]
			local ready = true
			for _, name in ipairs(waiting.events) do
				ready = ready and fired[name] == true
			end
			if ready then
				table.remove(afterAll, index)
				h.call(waiting.callback)
			end
		end
	end
	G.EventUtil = {
		ContinueOnAddOnLoaded = function(name, callback)
			if loaded[name] then
				callback()
			else
				onLoaded[name] = onLoaded[name] or {}
				table.insert(onLoaded[name], callback)
			end
		end,
		ContinueAfterAllEvents = function(callback, ...)
			afterAll[#afterAll + 1] = { callback = callback, events = { ... } }
		end,
	}
	local registry = {}
	G.EventRegistry = {
		RegisterCallback = function(_, event, callback, owner)
			registry[event] = registry[event] or {}
			table.insert(registry[event], { callback = callback, owner = owner })
		end,
		TriggerEvent = function(_, event, ...)
			for _, entry in ipairs(registry[event] or {}) do
				h.call(entry.callback, entry.owner, ...)
			end
		end,
	}
	function h.TriggerEvent(event, ...)
		G.EventRegistry:TriggerEvent(event, ...)
	end
	G.hooksecurefunc = function(target, name, hook)
		if type(target) == "string" then
			target, name, hook = G, target, name
		end
		local original = assert(target[name], "hooksecurefunc: no " .. tostring(name))
		target[name] = function(...)
			local results = { original(...) }
			hook(...)
			return unpack(results) -- multi-value: a secure hook returns the original's results
		end
	end
	G.CreateFromMixins = function(...)
		return G.Mixin({}, ...)
	end
	G.Mixin = function(object, ...)
		for _, mixin in ipairs({ ... }) do
			for key, value in pairs(mixin) do
				object[key] = value
			end
		end
		return object
	end
	G.InCombatLockdown = function()
		return h.combat
	end
	-- Entering or leaving combat fires the same events the client does.
	function h.SetCombat(on)
		h.combat = on
		h.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
	end
	G.strtrim = function(text)
		return (text:match("^%s*(.-)%s*$"))
	end
	G.GetBuildInfo = function()
		return "1.60.1", "69913", "Sep 1 2026", 16001
	end
	G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, message)
			h.prints[#h.prints + 1] = message
		end,
	}
	-- The red error line; h.uiErrors holds each message in order. MAP_PIN_INVALID_MAP is left unset, so Core's
	-- fallback copy is what the specs read.
	G.UIErrorsFrame = {
		AddExternalErrorMessage = function(_, message)
			h.uiErrors[#h.uiErrors + 1] = message
		end,
	}
	G.SlashCmdList = {}
	function h.Slash(message)
		h.call(G.SlashCmdList.ADVENTUREGUIDEFOREVER, message)
	end

	G.QUESTS_LABEL = "Quests"
	G.UIParent = NewRegion("Frame", "UIParent")

	-- The player.
	G.UnitLevel = function()
		return player.level
	end
	-- WoW: Forever's cap.
	G.GetMaxPlayerLevel = function()
		return 60
	end
	G.UnitFactionGroup = function()
		return player.faction, player.faction
	end
	G.UnitRace = function()
		return "Race", "Race", player.raceID
	end
	G.UnitClass = function()
		return "Class", "CLASS", player.classID
	end
	function h.MovePlayer(map, x, y)
		player.map, player.x, player.y = map, x, y
	end

	-- Quest log and completion: `log` entries are {id, title, level, complete, map, x, y}.
	local log = options.log or {}
	h.titleRequests = {}
	h.watched = options.watched or {}
	G.C_QuestLog = {
		GetAllCompletedQuestIDs = function()
			if h.completedPending then
				return nil
			end
			return options.completed or {}
		end,
		GetNumQuestLogEntries = function()
			return #log
		end,
		GetInfo = function(index)
			local entry = log[index]
			return entry and { questID = entry.id, title = entry.title, level = entry.level, isHeader = false }
		end,
		IsComplete = function(questID)
			for _, entry in ipairs(log) do
				if entry.id == questID then
					return entry.complete == true
				end
			end
			return false
		end,
		GetNextWaypoint = function(questID)
			for _, entry in ipairs(log) do
				if entry.id == questID then
					return entry.map, entry.x, entry.y
				end
			end
		end,
		GetTitleForQuestID = noop,
		-- Tracked quests, in order: options.watched seeds them; the client's limit is 25.
		GetNumQuestWatches = function()
			return #h.watched
		end,
		GetQuestIDForQuestWatchIndex = function(index)
			return h.watched[index]
		end,
		AddQuestWatch = function(questID)
			for _, watched in ipairs(h.watched) do
				if watched == questID then
					return false
				end
			end
			if #h.watched >= 25 then
				return false
			end
			h.watched[#h.watched + 1] = questID
			return true
		end,
		RemoveQuestWatch = function(questID)
			for index, watched in ipairs(h.watched) do
				if watched == questID then
					table.remove(h.watched, index)
					return true
				end
			end
			return false
		end,
		RequestLoadQuestByID = function(questID)
			h.titleRequests[#h.titleRequests + 1] = questID
		end,
	}
	-- No client names for races and classes: Model.Why's English stands in, as on a client that lacks them.
	G.C_CreatureInfo = { GetRaceInfo = noop, GetClassInfo = noop }

	-- Maps and waypoints: the user waypoint is a value store, with every call counted.
	h.counts.SetUserWaypoint, h.counts.ClearUserWaypoint, h.noWaypoint = 0, 0, {}
	G.C_Map = {
		GetBestMapForUnit = function()
			return player.map
		end,
		GetPlayerMapPosition = function(map)
			if map ~= player.map then
				return nil
			end
			return {
				GetXY = function()
					return player.x, player.y
				end,
			}
		end,
		-- h.noWaypoint[map] = true stands for a map the client refuses a user waypoint on.
		CanSetUserWaypointOnMap = function(mapID)
			return not h.noWaypoint[mapID]
		end,
		-- The client's names for the fixture's zones, so the panel reads as in game; "Map <id>" elsewhere, which no
		-- data name matches, so a spec can tell the client's name from the data's.
		GetMapInfo = function(mapID)
			local names = { [1413] = "The Barrens", [1442] = "Stonetalon Mountains" }
			return { mapID = mapID, name = names[mapID] or "Map " .. mapID }
		end,
		SetUserWaypoint = function(point)
			h.counts.SetUserWaypoint = h.counts.SetUserWaypoint + 1
			h.waypoint = point
			return true
		end,
		GetUserWaypoint = function()
			return h.waypoint
		end,
		ClearUserWaypoint = function()
			h.counts.ClearUserWaypoint = h.counts.ClearUserWaypoint + 1
			h.waypoint = nil
		end,
	}
	G.UiMapPoint = {
		CreateFromCoordinates = function(map, x, y)
			return { uiMapID = map, position = { x = x, y = y } }
		end,
	}
	G.C_SuperTrack = {
		SetSuperTrackedUserWaypoint = function(on)
			h.superTracked = on
		end,
	}

	-- Tooltips: every GameTooltip_* line is recorded, reset by SetOwner.
	G.GameTooltip = NewRegion("Frame", "GameTooltip")
	G.GameTooltip:Hide()
	function G.GameTooltip:SetOwner(owner, anchor)
		self.owner, self.anchor = owner, anchor
		h.tooltip = {}
	end
	for kind, name in pairs({
		title = "GameTooltip_SetTitle",
		normal = "GameTooltip_AddNormalLine",
		highlight = "GameTooltip_AddHighlightLine",
		instruction = "GameTooltip_AddInstructionLine",
		error = "GameTooltip_AddErrorLine",
		disabled = "GameTooltip_AddDisabledLine",
	}) do
		G[name] = function(_, text)
			h.tooltip[#h.tooltip + 1] = kind .. ": " .. tostring(text)
		end
	end
	G.GameTooltip_Hide = function()
		G.GameTooltip:Hide()
	end
	h.flashes = 0
	G.UIFrameFlash = function()
		h.flashes = h.flashes + 1
	end

	-- Menus: a recording root. Each entry is {kind, text, onClick?, entries} so submenus nest.
	local descriptionMeta
	local function Description(kind, text)
		return setmetatable({ kind = kind, text = text, entries = {} }, descriptionMeta)
	end
	local DescriptionMethods = {}
	descriptionMeta = { __index = DescriptionMethods }
	local function Add(parent, entry)
		parent.entries[#parent.entries + 1] = entry
		return entry
	end
	function DescriptionMethods:SetTag(tag)
		self.tag = tag
	end
	function DescriptionMethods:CreateTitle(text)
		return Add(self, Description("title", text))
	end
	function DescriptionMethods:CreateButton(text, onClick)
		local entry = Add(self, Description("button", text))
		entry.onClick = onClick
		return entry
	end
	function DescriptionMethods:CreateCheckbox(text, isSelected, setSelected)
		local entry = Add(self, Description("checkbox", text))
		entry.isSelected, entry.onClick = isSelected, setSelected
		return entry
	end
	function DescriptionMethods:SetEnabled(isEnabled)
		self.isEnabled = isEnabled
	end
	-- As Blizzard_Menu's IsEnabled: unset is enabled, a function is asked each time.
	function DescriptionMethods:IsEnabled()
		if type(self.isEnabled) == "function" then
			return self.isEnabled(self)
		end
		return self.isEnabled ~= false
	end
	function DescriptionMethods:CreateDivider()
		return Add(self, Description("divider"))
	end
	G.MenuUtil = {
		CreateContextMenu = function(owner, generator)
			h.menu = Description("root")
			h.call(generator, owner, h.menu)
		end,
	}
	-- Opens a DropdownButton's menu (SetupMenu) into h.menu.
	function h.OpenMenu(dropdown)
		h.menu = Description("root")
		h.call(dropdown.menuGenerator, dropdown, h.menu)
		return h.menu
	end
	-- "kind: text" per entry, a submenu's entries indented under it.
	function h.MenuLines(description, lines, indent)
		lines, indent = lines or {}, indent or ""
		for _, entry in ipairs((description or h.menu).entries) do
			lines[#lines + 1] = indent .. entry.kind .. (entry.text and ": " .. entry.text or "")
			h.MenuLines(entry, lines, indent .. "  ")
		end
		return lines
	end

	-- Settings > AddOns.
	h.settings = {}
	G.Settings = {
		VarType = { Boolean = "boolean" },
		RegisterVerticalLayoutCategory = function(name)
			return {
				name = name,
				GetID = function()
					return 1
				end,
			}
		end,
		RegisterAddOnSetting = function(_, _, key, storage, _, _, default)
			if storage[key] == nil then
				storage[key] = default
			end
			return { key = key, SetValueChangedCallback = noop }
		end,
		CreateCheckbox = function(_, setting, tooltip)
			local entry = { key = setting.key, tooltip = tooltip }
			h.settings[#h.settings + 1] = entry
			return {
				key = setting.key,
				SetParentInitializer = function(_, parent, predicate)
					entry.parent, entry.enabled = parent.key, predicate
				end,
			}
		end,
		RegisterAddOnCategory = noop,
		OpenToCategory = noop,
	}

	-- The world map: a canvas with data providers and pooled pins, counted per template.
	local map = NewRegion("Frame", "WorldMapFrame", G.UIParent)
	map.mapID = player.map
	map:Hide()
	local pools = {}
	function map:AddDataProvider(provider)
		h.providers[#h.providers + 1] = provider
		provider:OnAdded(self)
	end
	function map:RefreshAllDataProviders()
		for _, provider in ipairs(h.providers) do
			h.call(provider.RefreshAllData, provider)
		end
	end
	-- MapCanvasMixin:OnShow and OnMapChanged refresh every provider, before any hook of the addon's runs.
	map:SetScript("OnShow", map.RefreshAllDataProviders)
	function map:SetMapID(mapID)
		h.counts.SetMapID = h.counts.SetMapID + 1
		self.mapID = mapID
		if self:IsShown() then
			self:RefreshAllDataProviders()
		end
	end
	function map:GetMapID()
		return self.mapID
	end
	function map:AcquirePin(template, ...)
		h.counts.AcquirePin = h.counts.AcquirePin + 1
		pools[template] = pools[template] or {}
		h.pins[template] = h.pins[template] or {}
		local pin = table.remove(pools[template])
		if not pin then
			pin = NewRegion("Frame", nil, self)
			Instantiate(pin, template)
			if not pin.scripts.OnLoad then
				pin:OnLoad()
			end
		end
		table.insert(h.pins[template], pin)
		pin:Show()
		pin:OnAcquired(...)
		return pin
	end
	function map:RemoveAllPinsByTemplate(template)
		pools[template] = pools[template] or {}
		for _, pin in ipairs(h.pins[template] or {}) do
			pin:Hide()
			pin:ClearAllPoints()
			pin:OnReleased()
			table.insert(pools[template], pin)
		end
		h.pins[template] = {}
	end
	function map:EnumeratePinsByTemplate(template)
		local index, list = 0, h.pins[template] or {}
		return function()
			index = index + 1
			return list[index]
		end
	end
	G.MapCanvasDataProviderMixin = {
		OnAdded = function(self, owningMap)
			self.owningMap = owningMap
		end,
		GetMap = function(self)
			return self.owningMap
		end,
		RefreshAllData = noop,
		RemoveAllData = noop,
	}
	G.MapCanvasPinMixin = {
		OnLoad = noop,
		OnAcquired = noop,
		OnReleased = noop,
		GetMap = function()
			return map
		end,
		UseFrameLevelType = function(self, frameLevelType)
			self.frameLevelType = frameLevelType
		end,
		SetPosition = function(self, x, y)
			self.x, self.y = x, y
			self:SetPoint("CENTER", map, "TOPLEFT", x * 1000, -y * 700)
		end,
		SetScalingLimits = noop,
		ApplyCurrentScale = noop,
	}
	G.ToggleWorldMap = function()
		map:SetShown(not map:IsShown())
	end

	-- The quest log: every write to displayMode is counted and raises, since AGF must never write it.
	local questMap = NewRegion("Frame", "QuestMapFrame", map)
	questMap.displayMode = "Quests"
	Internal("Frame", questMap, "ContentsAnchor")
	Internal("Frame", questMap, "DetailsFrame")
	Internal("Frame", questMap, "QuestsFrame").displayMode = "Quests"
	Internal("Frame", questMap, "MapLegendFrame").displayMode = "MapLegend"
	Internal("Frame", questMap, "QuestsTab")
	Internal("Frame", questMap, "MapLegendTab")
	questMap.ContentFrames = { questMap.QuestsFrame, questMap.MapLegendFrame }
	questMap.MapLegendFrame:Hide()
	G.QuestMapFrame = setmetatable({}, {
		__index = questMap,
		__newindex = function(_, key, value)
			if key == "displayMode" then
				h.counts.displayModeWrites = h.counts.displayModeWrites + 1
				error("QuestMapFrame.displayMode written")
			end
			questMap[key] = value
		end,
	})
	-- Blizzard_UIPanels_Game/Camelot/QuestMapFrameOverrides.lua.
	G.QuestMapFrameOverrides = {
		questTabHidden = true,
		GetQuestsTabAnchorOffset = function()
			return 5, -28
		end,
	}
	G.OpenQuestLog = function()
		map:Show()
	end
	h.questDetails = {}
	G.QuestMapFrame_ShowQuestDetails = function(questID)
		h.questDetails[#h.questDetails + 1] = questID
	end

	-- The objective tracker (Blizzard_ObjectiveTrackerShared.lua:21-23).
	G.OBJECTIVE_DASH_STYLE_SHOW, G.OBJECTIVE_DASH_STYLE_HIDE, G.OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE = 1, 2, 3
	local containers = {}
	G.ObjectiveTrackerFrame = NewRegion("Frame", "ObjectiveTrackerFrame", G.UIParent)
	G.ObjectiveTrackerManager = {
		SetModuleContainer = function(_, module, container)
			containers[module] = container
		end,
		GetContainerForModule = function(_, module)
			return containers[module]
		end,
		AddContainer = noop,
	}

	-- Shortest Path Forever: absent, v1 (Estimate, Navigate, NavigateRoute, CurrentStop, Cancel) or v1+ (adds
	-- EstimateDetail and Active). Each profile counts its calls per function in h.spf.
	if options.spf then
		local api, guiding = { version = 1 }, {}
		h.spf, h.spfSeconds = {}, 360
		local function Counted(name, fn)
			h.spf[name] = 0
			api[name] = function(...)
				h.spf[name] = h.spf[name] + 1
				return fn(...) -- multi-value: the stub returns what its profile returns
			end
		end
		Counted("Estimate", function()
			return h.spfSeconds
		end)
		Counted("Navigate", function(owner)
			guiding[owner] = 1
			return true
		end)
		-- h.spfDeclines = true makes Shortest Path refuse the route, as it does when it cannot plan one.
		Counted("NavigateRoute", function(owner)
			if h.spfDeclines then
				return false
			end
			guiding[owner] = 1
			return true
		end)
		Counted("CurrentStop", function(owner)
			return guiding[owner]
		end)
		Counted("Cancel", function(owner)
			local was = guiding[owner] ~= nil
			guiding[owner] = nil
			return was
		end)
		if options.spf == "v1+" then
			-- h.spfLegs replaces the one flight leg, and false is no route; seconds add up as Shortest Path's do.
			Counted("EstimateDetail", function()
				if h.spfLegs == false then
					return nil, "unreachable"
				end
				local legs = h.spfLegs or { { mode = "flight", to = "Sentinel Hill", seconds = h.spfSeconds } }
				local seconds = 0
				for _, leg in ipairs(legs) do
					seconds = seconds + leg.seconds
				end
				return { seconds = seconds, legs = legs }
			end)
			Counted("Active", function()
				return next(guiding) ~= nil
			end)
		end
		G.ShortestPathForever = { API = api }
	end

	--[[ Load the addon: the TOC's files in order, each given (addonName, ns) ]]

	G.AdventureGuideForeverDB, G.AdventureGuideForeverCharDB = options.db, options.charDB
	for line in io.lines(ADDON .. ".toc") do
		line = line:gsub("\r", "")
		if line ~= "" and not line:match("^#") then
			local path = line:gsub("\\", "/")
			if path:match("%.xml$") then
				LoadXML(path)
			else
				local chunk = assert(loadfile(path))
				setfenv(chunk, G)
				h.call(chunk, ADDON, h.ns)
			end
		end
	end
	-- Counts the model's entry points, so specs can prove what a rebuild ran.
	for _, name in ipairs({ "Plan", "Journeys" }) do
		local original = h.ns.Model and h.ns.Model[name]
		if original then
			h.modelCalls[name] = 0
			h.ns.Model[name] = function(...)
				h.modelCalls[name] = h.modelCalls[name] + 1
				return original(...) -- multi-value: the wrapper is transparent
			end
		end
	end
	h.fire("ADDON_LOADED", ADDON)
	h.fire("ADDON_LOADED", "Blizzard_WorldMap")
	h.fire("PLAYER_ENTERING_WORLD", options.initialLogin ~= false, options.initialLogin == false)
	h.fire("VARIABLES_LOADED")
	h.flush()
	h.map, h.questMap, h.tracker = map, questMap, G.AdventureGuideForeverObjectiveTracker

	--[[ Driving the UI ]]

	function h.Click(frame, button)
		h.call(assert(frame.scripts.OnClick, "no OnClick"), frame, button or "LeftButton")
	end
	function h.ClickTab(tab)
		h.call(assert(tab.mouseUpHandler, "no tab handler"), tab, "LeftButton", true)
	end
	function h.Hover(frame)
		if frame.OnMouseEnter then
			h.call(frame.OnMouseEnter, frame)
		else
			h.call(assert(frame.scripts.OnEnter, "no OnEnter"), frame)
		end
	end
	function h.Type(editBox, text)
		editBox.userInput = true
		editBox:SetText(text)
		editBox.userInput = false
	end
	-- Every frame in creation order that passes the test.
	function h.Find(test)
		local found = {}
		for _, frame in ipairs(h.frames) do
			if test(frame) then
				found[#found + 1] = frame
			end
		end
		return found
	end
	-- Layout-dump extras only the harness knows, for tools/screenshots.py: the stock template a frame stands in for,
	-- what the client's dump leaves out (layers, colours, button text and fonts) and the
	-- state of the stock innards the addon reached into (an inset's Bg, a search box's instructions).
	local EXTRAS = {
		"activeAtlas",
		"alphaMode",
		"checked",
		"color",
		"disabled",
		"file",
		"highlightAtlas",
		"highlightFont",
		"highlightLocked",
		"inactiveAtlas",
		"justifyH",
		"layer",
		"maskFile",
		"normalAtlas",
		"normalFont",
		"subLevel",
		"texCoord",
		"wordWrap",
	}
	function h.Describe(region, entry)
		entry.stockTemplate = region.stockTemplate
		for _, key in ipairs(EXTRAS) do
			entry[key] = region[key]
		end
		if region:GetAlpha() ~= 1 then
			entry.alpha = region:GetAlpha()
		end
		if entry.type ~= "FontString" and region.text and region.text ~= "" then
			entry.text = region.text
		end
		for key, inner in pairs(region.internals or {}) do
			entry.stock = entry.stock or {}
			local points = {}
			for index, point in ipairs(inner.points) do
				assert(point[2] == region, "a stock innard anchored off its frame")
				points[index] = { point = point[1], relativePoint = point[3], x = point[4], y = point[5] }
			end
			entry.stock[key] = {
				shown = inner:IsShown(),
				text = inner.text,
				atlas = inner.atlas,
				size = inner.width and { inner.width, inner.height } or nil,
				anchors = #points > 0 and points or nil,
			}
		end
	end
	-- tools/screenshots.py's layout pass: each region under `root` whose path `rects` names takes that rect ({left,
	-- bottom, width, height}, y up) and runs OnSizeChanged when its size changed, as the client's layout does.
	function h.SetRects(root, rects)
		h.ns.DumpLayout(root, function(region, entry)
			local rect = rects[entry.path]
			if rect then
				local old = region.rect
				region.rect = rect
				local script = region.scripts and region.scripts.OnSizeChanged
				if script and not (old and old[3] == rect[3] and old[4] == rect[4]) then
					h.call(script, region, rect[3], rect[4])
				end
			end
		end)
	end
	return h
end

return harness
