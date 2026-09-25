---@type string, AGFNamespace
local _, ns = ...

--[[ /agf dump: a plain-table snapshot of what the guide drew, kept in AdventureGuideForeverDB so a /reload
     writes it to disk for tests/dump_diff.lua to compare with the headless layout. It runs only on the
     command, and the snapshot is dropped at the next login so it never lingers in the save file. ]]

local PIN_TEMPLATES = {
	"AdventureGuideForeverPinTemplate",
	"AdventureGuideForeverGiverPinTemplate",
}

-- The key a parent holds a region under: its XML parentKey, else the first field (by name) that holds it.
---@param parent table
---@param region Region
---@return string?
local function KeyIn(parent, region)
	local found = region:GetParentKey()
	if found then
		return found
	end
	for key, value in pairs(parent) do
		if value == region and type(key) == "string" and (not found or key < found) then
			found = key
		end
	end
	return found
end

-- A region's global name; else its parent's path and the key it is held under; else its type and position
-- among the parent's unkeyed children of that type. Built the same way in game and headless, so paths match.
---@param region Region?
---@param paths table<Region, string>
---@return string?
local function Path(region, paths)
	if not region then
		return nil
	end
	if paths[region] then
		return paths[region]
	end
	local path = region:GetName()
	local parent = region:GetParent() --[[@as Frame?]]
	if not path and not parent then
		path = "?"
	elseif not path then
		---@cast parent -?
		local key = KeyIn(parent, region)
		if key then
			path = Path(parent, paths) .. "." .. key
		else
			local kind, index = region:GetObjectType(), 0
			---@type Region[]
			local siblings = { parent:GetChildren() } -- multi-value: every child frame
			for _, other in ipairs({ parent:GetRegions() }) do -- multi-value: every region
				siblings[#siblings + 1] = other
			end
			for _, sibling in ipairs(siblings) do
				if sibling:GetObjectType() == kind and not KeyIn(parent, sibling) then
					index = index + 1
				end
				if sibling == region then
					break
				end
			end
			path = ("%s.%s[%d]"):format(Path(parent, paths), kind, index)
		end
	end
	paths[region] = path
	return path
end

-- Depth-first over `root` and every shown descendant: path, anchors, explicitly set size, atlas, font and text,
-- and whether a frame runs an OnUpdate. `describe` lets the headless harness add what only it knows.
---@param root Frame
---@param describe? fun(region: Region, entry: AGFDumpEntry)
---@return AGFDumpEntry[]
function ns.DumpLayout(root, describe)
	local paths, entries = {}, {}
	---@param region Region
	local function Visit(region)
		---@type AGFDumpEntry
		local entry = { path = Path(region, paths) or "?", type = region:GetObjectType(), anchors = {} }
		for index = 1, region:GetNumPoints() do
			local point, relativeTo, relativePoint, x, y = region:GetPoint(index)
			entry.anchors[index] = {
				point = point,
				relativeTo = Path(relativeTo --[[@as Region?]], paths),
				relativePoint = relativePoint,
				x = x,
				y = y,
			}
		end
		-- GetSize(true) is the size set with SetSize/SetWidth/SetHeight, not the one anchors produce.
		local width, height = region:GetSize(true)
		if width > 0 or height > 0 then
			entry.size = { width, height }
		end
		if region:IsObjectType("Texture") then
			entry.atlas = (region --[[@as Texture]]):GetAtlas()
		elseif region:IsObjectType("FontString") then
			local text = region --[[@as FontString]]
			local font = text:GetFontObject()
			entry.font, entry.text = font and font:GetName(), text:GetText()
		end
		local frame = region:IsObjectType("Frame") and region --[[@as Frame]] or nil
		if frame then
			entry.onUpdate = frame:GetScript("OnUpdate") ~= nil
		end
		if describe then
			describe(region, entry)
		end
		entries[#entries + 1] = entry
		if frame then
			for _, child in ipairs({ frame:GetRegions() }) do -- multi-value: every region
				if child:IsShown() then
					Visit(child)
				end
			end
			for _, child in ipairs({ frame:GetChildren() }) do -- multi-value: every child frame
				if child:IsShown() then
					Visit(child)
				end
			end
		end
	end
	Visit(root)
	return entries
end

-- Every frame under the guide's named roots, and its map pins, shown or not: the /reload check for idle work.
---@return {name: string, onUpdate: boolean}[]
local function Frames()
	local frames, paths = {}, {}
	---@param frame Frame
	local function Visit(frame)
		frames[#frames + 1] = { name = Path(frame, paths) or "?", onUpdate = frame:GetScript("OnUpdate") ~= nil }
		for _, child in ipairs({ frame:GetChildren() }) do -- multi-value: every child frame
			Visit(child --[[@as Frame]])
		end
	end
	for _, root in ipairs({
		AdventureGuideForeverPanel or false,
		AdventureGuideForeverTab or false,
		AdventureGuideForeverQuestsTab or false,
		AdventureGuideForeverObjectiveTracker or false,
	}) do
		if root then
			Visit(root)
		end
	end
	if WorldMapFrame then
		for _, template in ipairs(PIN_TEMPLATES) do
			for pin in WorldMapFrame:EnumeratePinsByTemplate(template) do
				Visit(pin)
			end
		end
	end
	return frames
end

function ns.Dump()
	local route = {}
	for index, step in ipairs(ns.Route().steps) do
		route[index] = step.key
	end
	local version, build = GetBuildInfo()
	AdventureGuideForeverDB.dump = {
		build = version .. "." .. build,
		layout = AdventureGuideForeverPanel and ns.DumpLayout(AdventureGuideForeverPanel),
		tracker = AdventureGuideForeverObjectiveTracker and ns.DumpLayout(AdventureGuideForeverObjectiveTracker),
		route = route,
		frames = Frames(),
	}
	ns.Print(ns.L.DUMP_SAVED)
end

-- isInitialLogin is true only on a session's first PLAYER_ENTERING_WORLD, so one event is enough.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, _, isInitialLogin)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	if isInitialLogin and type(AdventureGuideForeverDB) == "table" then
		AdventureGuideForeverDB.dump = nil
	end
end)
