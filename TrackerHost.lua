---@type string, { TrackerHost?: ForeverTrackerHostAPI }
local _, ns = ...

---@class ForeverTrackerModule : Frame
---@field parentContainer? Frame
---@field SetContainer fun(self: ForeverTrackerModule, container: Frame)

---@class ForeverTrackerHostAPI
---@field Attach fun(module: Frame)
---@field IsAttached fun(module: Frame?): boolean

-- Sharing the native tracker collection also shares its Edit Mode execution path.
-- Keep our sections and their frame pools entirely outside that collection.
if not ObjectiveTrackerFrame then
	return
end

if ForeverTrackerHost then
	ns.TrackerHost = ForeverTrackerHost
	return
end

local host = CreateFrame("Frame", "ForeverTrackerCompanion", UIParent)
-- Preserve Blizzard's edit-mode placement for the combined column. The
-- private host takes the native frame's original slot; the native frame is
-- placed below it after the private content has laid out. This keeps every
-- section in one column without registering our frames with Blizzard's
-- secure module collection.
local nativeAnchor
local function BelowPoint(point)
	return point:gsub("TOP", "BOTTOM")
end
local function CaptureNativeAnchor()
	local point, relativeTo, relativePoint, x, y = ObjectiveTrackerFrame:GetPoint()
	if nativeAnchor and relativeTo == host then
		return
	end
	nativeAnchor = {
		point = point or "TOPRIGHT",
		relativeTo = relativeTo or UIParent,
		relativePoint = relativePoint or "TOPRIGHT",
		x = x or 0,
		y = y or 0,
	}
end
host:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
host:SetWidth(ObjectiveTrackerFrame:GetWidth())
host:SetHeight(1)
local modules, queued, ready = {}, false, false
local pools = CreateFramePoolCollection()

local function Acquire(parent, template)
	local info = C_XMLUtil.GetTemplateInfo(template)
	local pool = pools:GetOrCreatePool(info and info.type or "Frame", parent, template)
	---@class ForeverTrackerPooledFrame : Frame
	---@field GetLine? function
	---@field FreeLine? function
	---@field OnAnimFinished? function
	local frame, isNew = pool:Acquire(template)
	frame.template = template
	return frame, isNew
end

local function GetLine(block, key, template)
	template = template or block.parentModule.lineTemplate
	local line = block:GetExistingLine(key)
	if line and line.template ~= template then
		block:FreeLine(line)
		line = nil
	end
	if not line then
		line = Acquire(block, template)
		line:SetParent(block)
		line:Show()
	end
	block.usedLines[key] = line
	line.objectiveKey, line.parentBlock, line.used = key, block, true
	return line
end

local function FreeLine(block, line)
	block.usedLines[line.objectiveKey] = nil
	pools:Release(line)
	line:Hide()
	if line.OnFree then
		line:OnFree(block)
	end
end

local function FreeResources(resources, onFree)
	for key, frame in pairs(resources or {}) do
		if not frame.used then
			resources[key] = nil
			if onFree and frame.OnFree then
				frame:OnFree()
			end
			pools:Release(frame)
		end
	end
end

-- Our blocks have no native reward toasts; their animations stay in the private cache.
local function OnAnimFinished(block)
	if block.activeAnim ~= block.AddAnim then
		block.parentModule:RemoveBlockFromCache(block)
		block.parentModule:MarkDirty()
		block:SetAlpha(0)
	end
	block.activeAnim = nil
	if block.pendingAnim then
		local anim = block.pendingAnim
		block.pendingAnim = nil
		block:TryPlayAnim(anim)
	end
end

local Module = {}
function Module:AcquireFrame(template)
	local frame, isNew = Acquire(self, template)
	frame:SetParent(self.ContentsFrame)
	if frame.GetLine then
		frame.GetLine, frame.FreeLine = GetLine, FreeLine
		if frame.OnAnimFinished then
			frame.OnAnimFinished = OnAnimFinished
		end
	end
	return frame, isNew
end
function Module:FreeBlock(block)
	self:RemoveBlockFromCache(block, true)
	block:Free()
	self.usedBlocks[block.template][block.id] = nil
	pools:Release(block)
	self:OnFreeBlock(block)
end
function Module:FreeUnusedTimerBars()
	FreeResources(self.usedTimerBars)
end
function Module:FreeUnusedProgressBars()
	FreeResources(self.usedProgressBars, true)
end
function Module:FreeUnusedRightEdgeFrames()
	FreeResources(self.usedRightEdgeFrames)
end
function Module.GetContextMenuParent(_)
	return host
end

local function Layout()
	queued = false
	if InCombatLockdown() then
		return
	end
	table.sort(modules, function(a, b)
		return a.uiOrder < b.uiOrder
	end)
	local available = math.max(0, (host:GetTop() or UIParent:GetHeight()) - 40)
	-- The native frame may only receive its final Edit Mode anchor after the
	-- player and saved variables are ready. Capture it before our first reflow.
	CaptureNativeAnchor()
	local width = ObjectiveTrackerFrame:GetWidth()
	host:SetWidth(width)
	local height = 0
	for _, module in ipairs(modules) do
		module:SetWidth(width)
		module:ClearAllPoints()
		module:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -height)
		module:Update(math.max(0, available - height))
		local used = module:GetContentsHeight()
		if used > 0 then
			height = height + used + 10
		end
	end
	host:SetHeight(math.max(1, height))
	-- If the combined column would run below the screen, move the whole
	-- column upward from its saved edit-mode slot.  The offset is calculated
	-- from the original point each pass, so repeated refreshes never drift.
	local shift = 0
	host:ClearAllPoints()
	host:SetPoint(
		nativeAnchor.point,
		nativeAnchor.relativeTo,
		nativeAnchor.relativePoint,
		nativeAnchor.x,
		nativeAnchor.y
	)
	local screenHeight = UIParent:GetHeight()
	local top = host:GetTop()
	local nativeHeight = ObjectiveTrackerFrame:GetHeight() or 0
	if screenHeight and top and top - host:GetHeight() - nativeHeight < 24 then
		shift = 24 - (top - host:GetHeight() - nativeHeight)
		shift = math.min(shift, math.max(0, screenHeight - 24 - top))
	end
	host:ClearAllPoints()
	host:SetPoint(
		nativeAnchor.point,
		nativeAnchor.relativeTo,
		nativeAnchor.relativePoint,
		nativeAnchor.x,
		nativeAnchor.y + shift
	)
	ObjectiveTrackerFrame:ClearAllPoints()
	ObjectiveTrackerFrame:SetPoint(nativeAnchor.point, host, BelowPoint(nativeAnchor.point), 0, 0)
end
function host.MarkDirty(_)
	if ready and not queued then
		queued = true
		C_Timer.After(0, Layout)
	end
end
function host.IsCollapsed(_)
	return false
end
function host:ForceExpand()
	self:MarkDirty()
end

---@class ForeverTrackerHostAPI
local api = {}
function api.Attach(module)
	---@cast module ForeverTrackerModule
	if module.parentContainer == host then
		return
	end
	Mixin(module, Module)
	modules[#modules + 1] = module
	module:SetContainer(host)
	host:MarkDirty()
end
function api.IsAttached(module)
	---@cast module ForeverTrackerModule?
	return module ~= nil and module.parentContainer == host
end
host:RegisterEvent("PLAYER_REGEN_ENABLED")
host:RegisterEvent("DISPLAY_SIZE_CHANGED")
host:RegisterEvent("UI_SCALE_CHANGED")
host:SetScript("OnEvent", function()
	host:MarkDirty()
end)
ObjectiveTrackerFrame:HookScript("OnSizeChanged", function()
	host:MarkDirty()
end)
ForeverTrackerHost = api -- taint-ok: addon-owned companion tracker registry
ns.TrackerHost = api

EventUtil.ContinueAfterAllEvents(function()
	ready = true
	host:MarkDirty()
end, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
