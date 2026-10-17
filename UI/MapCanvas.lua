---@type string, AGFNamespace
local _, ns = ...

-- AGF's marks on the world map, on frames of its own, with nothing written into the map (docs/design.md §2.6).
--
-- Forever's gamepad interface runs the map's Lua from secure code: each frame MapCanvasMixin walks every pin in
-- map.pinPools for the gamepad cursor and keeps the ones it enters, and closing the map leaves each again. A data
-- provider AGF added (map.dataProviders) or a pin it acquired (its template, pool and frame in map.pinPools) put
-- AGF's values on that walk, so the walk ran tainted and the gamepad action bar's next protected call was blocked.
-- So AGF adds no data provider, acquires no pin and calls no map method that writes. It only reads the map:
--   map:GetMapID(), map:GetCanvas(), map:GetCanvasScale(), map:GetCanvasZoomPercent(), map:GetGlobalPinScale()
--   and map:GetPinFrameLevelsManager():GetValidFrameLevel(type)
-- (each returns a field or works one out; Blizzard_MapCanvas.lua, MapCanvas_PinFrameLevelsManager.lua), and the
-- canvas's size. tests/map_canvas_spec.lua drives the addon against a map that fails on any write.
--
-- One view per map: a frame of AGF's on the canvas. The client parents it, in C, so the scroll frame clips it and it
-- shows and hides with the map. It is made with no parent and then moved there, since the gamepad interface follows
-- frames created inside an open window. While the map is shown it runs an OnUpdate (set on show, cleared on hide, so
-- nothing runs per frame with the map closed, WFA-13) that compares a few reads and tells its listeners what changed:
--   "show" the map opened, "map" another map is shown, "size" the canvas was resized, "scale" the zoom or pin scale
-- changed, and "hide" when the map closes. The pins sit on a layer under that frame, so combat hides them all at once.
--
-- Pins are plain frames that take the mouse with OnEnter and OnLeave only: the gamepad interface reads a frame with
-- a click script (OnClick, OnMouseDown, OnMouseUp) as a button of the window it scans, and would read AGF's function
-- back in its secure code. A click is a press and a release of one button over the hovered pin, seen through
-- GLOBAL_MOUSE_DOWN and GLOBAL_MOUSE_UP. The right button passes through to the map (zoom out) unless the pin keeps
-- it. Under the gamepad interface the pin nearest the map cursor shows its tooltip, as the map's own pins do.

---@class AGFMapCanvasModule
local MapCanvas = {}
ns.MapCanvas = MapCanvas

-- How near the gamepad's map cursor comes to a pin to hover it, in UI units (the map's own pins use 12).
local CURSOR_REACH = 12

---@class AGFCanvasView
---@field map AGFWorldMapFrame
---@field canvas Frame
---@field host Frame
---@field layer Frame
---@field shown boolean
---@field mapID? integer
---@field width number
---@field height number
---@field scale number
---@field zoom number
---@field pinScale number
---@field gamepad boolean
---@field listeners fun(view: AGFCanvasView, what: string)[]
---@field pools AGFCanvasPool[]
local View = {}
View.__index = View

---@type table<AGFWorldMapFrame, AGFCanvasView>
local views = {}
---@type AGFCanvasPin?, AGFCanvasPin?, string?
local hovered, pressed, pressedButton
local clicks = CreateFrame("Frame")

-- Forever's gamepad interface style (Options > Gamepad); the client reloads the UI when it changes.
---@return boolean
local function GamepadUI()
	local styles, api = Enum.InputDeviceInterfaceType, C_InputInterfaceStyle
	return styles ~= nil and api ~= nil and api.GetCurrentStyle ~= nil and api.GetCurrentStyle() == styles.Gamepad
end

-- The frame level the map gives pins of `levelType`, as MapCanvasPinMixin:ApplyFrameLevel asks for it.
---@param levelType? string
---@return number
function View:Level(levelType)
	local levels = self.map.GetPinFrameLevelsManager and self.map:GetPinFrameLevelsManager()
	local level = levelType and levels and levels.GetValidFrameLevel and levels:GetValidFrameLevel(levelType)
	return level or self.canvas:GetFrameLevel() + 1
end

---@param value number
---@return number
local function Unit(value)
	return math.min(1, math.max(0, value))
end

---@param view AGFCanvasView
local function Read(view)
	local map, canvas = view.map, view.canvas
	local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
	if not scale or scale <= 0 then
		scale = 1
	end
	local zoom = map.GetCanvasZoomPercent and map:GetCanvasZoomPercent() or 0
	local pinScale = map.GetGlobalPinScale and map:GetGlobalPinScale() or 1
	return map:GetMapID(), canvas:GetWidth() or 0, canvas:GetHeight() or 0, scale, Unit(zoom), pinScale
end

---@param pin AGFCanvasPin?
local function SetHovered(pin)
	if hovered == pin then
		return
	end
	local previous = hovered
	hovered = pin
	if previous then
		ns.SafeCall("map pin leave", previous.OnMouseLeave, previous)
	end
	if pin then
		ns.SafeCall("map pin enter", pin.OnMouseEnter, pin)
	end
end

---@param view AGFCanvasView
---@param what string
local function Fire(view, what)
	-- Pins kept from before follow the view first: a ping set as the map turned, the pins of a map shown again.
	for _, pool in ipairs(view.pools) do
		for _, pin in ipairs(pool.active) do
			pin:ApplyScale()
			pin:ApplyPosition()
		end
	end
	for _, listener in ipairs(view.listeners) do
		ns.SafeCall("map canvas " .. what, listener, view, what)
	end
end

-- The pin nearest the gamepad's map cursor, within reach, among the pins that take the mouse.
---@param view AGFCanvasView
---@return AGFCanvasPin?
local function PinAtCursor(view)
	local cursor = SoftCursor
	if not (cursor and cursor:IsShown()) then
		return nil
	end
	local left, bottom, width, height = cursor:GetRect()
	if not left then
		return nil
	end
	local cursorScale = cursor:GetEffectiveScale()
	local cx, cy = (left + width / 2) * cursorScale, (bottom + height / 2) * cursorScale
	local reach = CURSOR_REACH * cursorScale
	local best, bestDistance = nil, reach * reach
	for _, pool in ipairs(view.pools) do
		for _, pin in ipairs(pool.active) do
			if pin.takesMouse and pin:IsVisible() then
				local x, y = pin:GetCenter()
				if x then
					local scale = pin:GetEffectiveScale()
					local dx, dy = x * scale - cx, y * scale - cy
					if dx * dx + dy * dy <= bestDistance then
						best, bestDistance = pin, dx * dx + dy * dy
					end
				end
			end
		end
	end
	return best
end

---@param view AGFCanvasView
local function Update(view)
	local mapID, width, height, scale, zoom, pinScale = Read(view)
	local first, otherMap = not view.shown, mapID ~= view.mapID
	local sized = width ~= view.width or height ~= view.height
	local scaled = scale ~= view.scale or zoom ~= view.zoom or pinScale ~= view.pinScale
	view.mapID, view.width, view.height, view.scale, view.zoom, view.pinScale =
		mapID, width, height, scale, zoom, pinScale
	if first then
		view.shown = true
		view.gamepad = GamepadUI()
		clicks:RegisterEvent("GLOBAL_MOUSE_DOWN")
		clicks:RegisterEvent("GLOBAL_MOUSE_UP")
		Fire(view, "show")
	elseif otherMap then
		Fire(view, "map")
	else
		if sized then
			Fire(view, "size")
		end
		if scaled then
			Fire(view, "scale")
		end
	end
	if view.gamepad and view.layer:IsShown() then
		local pin = PinAtCursor(view)
		if pin or (hovered and hovered.view == view) then
			SetHovered(pin)
		end
	end
end

---@param view AGFCanvasView
local function Closed(view)
	view.host:SetScript("OnUpdate", nil)
	if hovered and hovered.view == view then
		SetHovered(nil)
	end
	pressed = nil
	local open = false
	for _, other in pairs(views) do
		open = open or (other ~= view and other.shown)
	end
	if not open then
		clicks:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		clicks:UnregisterEvent("GLOBAL_MOUSE_UP")
	end
	if view.shown then
		view.shown = false
		for _, listener in ipairs(view.listeners) do
			ns.SafeCall("map canvas hide", listener, view, "hide")
		end
	end
end

-- A frame made with no parent, then set under `parent`.
---@param frameType string
---@param parent Frame
---@param template? string
---@return Frame
local function FrameUnder(frameType, parent, template)
	local frame = CreateFrame(frameType, nil, nil, template)
	frame:SetParent(parent)
	return frame
end

-- The view of `map`, made the first time it is asked for; `listener`, when given, hears what changes.
---@param map AGFWorldMapFrame
---@param listener? fun(view: AGFCanvasView, what: string)
---@return AGFCanvasView
function MapCanvas.Watch(map, listener)
	local view = views[map]
	if not view then
		local canvas = map:GetCanvas()
		view = setmetatable({
			map = map,
			canvas = canvas,
			shown = false,
			width = 0,
			height = 0,
			scale = 1,
			zoom = 0,
			pinScale = 1,
			gamepad = false,
			listeners = {},
			pools = {},
		}, View)
		local host = FrameUnder("Frame", canvas)
		host:SetAllPoints(canvas)
		host:EnableMouse(false)
		local function OnUpdate()
			Update(view)
		end
		host:SetScript("OnShow", function(self)
			self:SetScript("OnUpdate", OnUpdate)
		end)
		host:SetScript("OnHide", function()
			Closed(view)
		end)
		if host:IsVisible() then
			host:SetScript("OnUpdate", OnUpdate)
		end
		local layer = FrameUnder("Frame", host)
		layer:SetAllPoints(host)
		layer:EnableMouse(false)
		view.host, view.layer = host, layer
		views[map] = view
	end
	if listener then
		view.listeners[#view.listeners + 1] = listener
	end
	return view
end

-- Runs the view's check now, as its next frame would: a map just turned is drawn at once.
---@param map AGFWorldMapFrame
function MapCanvas.Update(map)
	local view = views[map]
	if view and view.host:IsVisible() then
		Update(view)
	end
end

-- AGF's pins on `map`: shown, or hidden through combat.
---@param map AGFWorldMapFrame
---@param shown boolean
function MapCanvas.SetShown(map, shown)
	local view = views[map]
	if view then
		if not shown and hovered and hovered.view == view then
			SetHovered(nil)
		end
		view.layer:SetShown(shown)
	end
end

--[[ Pins ]]

-- What MapCanvasPinMixin does for a pin, worked out from the view instead of asked of the map: a place in map
-- fractions (SetPosition) and a size on screen between startScale zoomed out and endScale zoomed in, times the map's
-- pin scale unless the pin ignores it (ApplyCurrentScale).
---@class AGFCanvasPin : Frame
---@field view AGFCanvasView
---@field mapX? number
---@field mapY? number
---@field scaleFactor? number
---@field startScale? number
---@field endScale? number
---@field ignoreGlobalPinScale? boolean
---@field frameLevelType? string
---@field takesMouse? boolean
---@field keepsRightButton? boolean
---@field OnMouseEnter fun(self: AGFCanvasPin)
---@field OnMouseLeave fun(self: AGFCanvasPin)
---@field OnClick fun(self: AGFCanvasPin, button: string)
---@field OnAcquired fun(self: AGFCanvasPin, ...: any)
---@field OnReleased fun(self: AGFCanvasPin)
local Pin = {}
MapCanvas.PinMixin = Pin

function Pin:OnAcquired() end
function Pin:OnReleased() end
function Pin:OnMouseEnter() end
function Pin:OnMouseLeave() end
function Pin:OnClick() end

---@param x number
---@param y number
function Pin:SetPosition(x, y)
	self.mapX, self.mapY = x, y
	self:ApplyPosition()
end

---@param factor number
---@param startScale number
---@param endScale number
function Pin:SetScalingLimits(factor, startScale, endScale)
	self.scaleFactor, self.startScale, self.endScale = factor, math.max(startScale, 0.01), math.max(endScale, 0.01)
end

---@param ignore boolean
function Pin:SetIgnoreGlobalPinScale(ignore)
	self.ignoreGlobalPinScale = ignore
end

-- The map's level type for the pin; Pool:Acquire applies it.
---@param levelType string
function Pin:UseFrameLevelType(levelType)
	self.frameLevelType = levelType
end

function Pin:ApplyScale()
	local view = self.view
	local scale
	if self.startScale and self.endScale then
		local t = Unit((self.scaleFactor or 1) * view.zoom)
		scale = (self.startScale + (self.endScale - self.startScale) * t) / view.scale
	elseif not self.ignoreGlobalPinScale then
		scale = 1
	end
	if scale then
		if not self.ignoreGlobalPinScale then
			scale = scale * view.pinScale
		end
		self:SetScale(scale)
	end
end

function Pin:ApplyPosition()
	local x, y = self.mapX, self.mapY
	if not (x and y) then
		return
	end
	local view, scale = self.view, self:GetScale()
	self:ClearAllPoints()
	self:SetPoint("CENTER", view.canvas, "TOPLEFT", view.width * x / scale, -view.height * y / scale)
end

--[[ Pools ]]

---@class AGFCanvasPool
---@field view AGFCanvasView
---@field template string
---@field mixin table
---@field marker? string
---@field active AGFCanvasPin[]
---@field free AGFCanvasPin[]
local Pool = {}
Pool.__index = Pool

local function OnEnter(pin)
	SetHovered(pin)
end

local function OnLeave(pin)
	if hovered == pin then
		SetHovered(nil)
	end
end

-- A pin from the pool, shown, laid out with OnAcquired(...). Only out of combat: the right button's pass-through is
-- protected then.
---@return AGFCanvasPin
function Pool:Acquire(...)
	local pin = table.remove(self.free)
	if not pin then
		pin = FrameUnder("Frame", self.view.layer, self.template) --[[@as AGFCanvasPin]]
		Mixin(pin, self.mixin)
		pin.view = self.view
		if pin.takesMouse then
			pin:EnableMouse(true)
			pin:SetScript("OnEnter", OnEnter)
			pin:SetScript("OnLeave", OnLeave)
		else
			pin:EnableMouse(false)
		end
	end
	self.active[#self.active + 1] = pin
	pin:Show()
	pin:OnAcquired(...)
	pin:SetFrameLevel(self.view:Level(pin.frameLevelType))
	pin:ApplyScale()
	pin:ApplyPosition()
	if pin.takesMouse then
		if pin.keepsRightButton then
			pin:SetPassThroughButtons()
		else
			pin:SetPassThroughButtons("RightButton")
		end
	end
	return pin
end

function Pool:ReleaseAll()
	for index = #self.active, 1, -1 do
		local pin = self.active[index]
		self.active[index] = nil
		if hovered == pin then
			SetHovered(nil)
		end
		if pressed == pin then
			pressed = nil
		end
		pin:Hide()
		pin:ClearAllPoints()
		pin:OnReleased()
		pin.mapX, pin.mapY = nil, nil
		self.free[#self.free + 1] = pin
	end
end

-- A pool of pins on `map`, drawn in the order the pools were made: frames from `template` (art only, no mixin, so
-- nothing of the map's own pin code runs on them) wearing `mixin`, which builds on MapCanvas.PinMixin. A pool with a
-- `marker` kind lists its pins for the other Forever addons.
---@param map AGFWorldMapFrame
---@param template string
---@param mixin table
---@param marker? string
---@return AGFCanvasPool
function MapCanvas.Pool(map, template, mixin, marker)
	local view = MapCanvas.Watch(map)
	local pool =
		setmetatable({ view = view, template = template, mixin = mixin, marker = marker, active = {}, free = {} }, Pool)
	view.pools[#view.pools + 1] = pool
	return pool
end

-- The pools on `map`, for the dump and the specs.
---@param map AGFWorldMapFrame
---@return AGFCanvasPool[]
function MapCanvas.Pools(map)
	local view = views[map]
	return view and view.pools or {}
end

--[[ Clicks ]]

clicks:SetScript("OnEvent", function(_, event, button)
	if event == "GLOBAL_MOUSE_DOWN" then
		pressed, pressedButton = nil, button
		if hovered and hovered:IsVisible() and hovered:IsMouseOver() then
			pressed = hovered
		end
		return
	end
	local pin = pressed
	pressed = nil
	if
		pin
		and pin == hovered
		and button == pressedButton
		and pin:IsVisible()
		and pin:IsMouseOver()
		and (button ~= "RightButton" or pin.keepsRightButton)
	then
		ns.SafeCall("map pin click", pin.OnClick, pin, button)
	end
end)

--[[ ForeverMapMarkers ]]

-- The Forever addons' markers on the world map, for each other (Tweaks Forever keeps its dungeon entrances clear of
-- them): with every addon on frames of its own, none finds another's through the map's pin pools. Each sets one
-- function under its folder name: ForeverMapMarkers[addonName](map) -> { { x, y, kind }... }, the shown markers'
-- fractions on map:GetMapID(), in a fresh table; it never errors and is empty for a map it does not draw on.
-- Published as a copy, never a field written into the table another addon made; readers look the global up each time.
local markerRegistry = {}
for name, list in pairs(ForeverMapMarkers or {}) do
	markerRegistry[name] = list
end
markerRegistry.AdventureGuideForever = function(map)
	local markers, view = {}, views[map]
	if not (view and view.shown and view.layer:IsShown()) then
		return markers
	end
	for _, pool in ipairs(view.pools) do
		if pool.marker then
			for _, pin in ipairs(pool.active) do
				if pin.mapX and pin:IsShown() then
					markers[#markers + 1] = { x = pin.mapX, y = pin.mapY, kind = pool.marker }
				end
			end
		end
	end
	return markers
end
ForeverMapMarkers = markerRegistry
