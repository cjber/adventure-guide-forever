-- Run from the repository root: luajit tests/art_spec.lua
-- Art.lua on its own, with a stub C_Texture.GetAtlasInfo and stub textures and frames: an atlas fits its box at its
-- own aspect, covers a box with the overflow cropped evenly, and a row's art is scaled uniformly to the row.
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual, expected, label)
	equal(math.abs(actual - expected) < 1e-6, true, ("%s (%s ~ %s)"):format(label, actual, expected))
end

-- Within 2% of the atlas's own aspect.
local function aspect(width, height, native, label)
	equal(math.abs((width / height) / native - 1) <= 0.02, true, label .. ": at its own aspect")
end

-- A sheet 1024x512 with each atlas somewhere on it, as the client keeps them.
local ATLASES = {
	wide = { width = 209, height = 46, left = 0.25, top = 0.5 },
	tall = { width = 108, height = 155, left = 0, top = 0 },
}
local C_Texture = {
	GetAtlasInfo = function(name)
		local atlas = ATLASES[name]
		if not atlas then
			return nil
		end
		return {
			width = atlas.width,
			height = atlas.height,
			leftTexCoord = atlas.left,
			rightTexCoord = atlas.left + atlas.width / 1024,
			topTexCoord = atlas.top,
			bottomTexCoord = atlas.top + atlas.height / 512,
			file = 12345,
		}
	end,
}

local Texture = {}
Texture.__index = Texture
function Texture:SetAtlas(atlas)
	self.atlas, self.file, self.coords = atlas, nil, nil
end
function Texture:SetTexture(file)
	self.file, self.atlas = file, nil
end
function Texture:SetTexCoord(left, right, top, bottom)
	self.coords = { left, right, top, bottom }
end
function Texture:SetSize(width, height)
	self.width, self.height = width, height
end
function Texture:SetScale(scale)
	self.scale = scale
end
function Texture:GetScale()
	return self.scale or 1
end
function Texture:ClearAllPoints()
	self.point = nil
end
function Texture:SetPoint(point, relative, relativePoint, x, y)
	self.point = { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y }
end
function Texture:SetShown(shown)
	self.shown = shown
end
function Texture:Hide()
	self.shown = false
end

local Frame = {}
Frame.__index = Frame
function Frame:GetSize()
	return self.width, self.height
end
function Frame:HookScript(script, fn)
	self.hooks[script] = fn
end
function Frame:CreateTexture(_, layer)
	local texture = setmetatable({ layer = layer }, Texture)
	self.textures[#self.textures + 1] = texture
	return texture
end
-- The client's layout gives the frame a new size.
function Frame:Resize(width, height)
	self.width, self.height = width, height
	self.hooks.OnSizeChanged(self, width, height)
end
local function NewFrame(width, height)
	return setmetatable({ width = width, height = height, hooks = {}, textures = {} }, Frame)
end

local ns = {}
local chunk = assert(loadfile("UI/Art.lua"))
setfenv(chunk, setmetatable({ C_Texture = C_Texture }, { __index = _G }))
chunk("AdventureGuideForever", ns)
local Art = ns.Art

-- Fit: the largest size in the box at the atlas's aspect.
do
	local texture = setmetatable({}, Texture)
	local width, height = Art.Fit(texture, "tall", 20, 20)
	equal(texture.atlas, "tall", "fit: the atlas")
	near(height, 20, "fit: a tall atlas fills the box's height")
	aspect(width, height, 108 / 155, "fit tall")
	equal(texture.width, width, "fit: sized")
	width, height = Art.Fit(texture, "wide", 22, 25)
	near(width, 22, "fit: a wide atlas fills the box's width")
	aspect(width, height, 209 / 46, "fit wide")
	width, height = Art.Fit(texture, "unknown", 14, 18)
	equal(width, 14, "fit: an unknown atlas is square")
	equal(height, 14, "fit: an unknown atlas is square, inside the box")
end

-- Cover: the box filled, the overflow cropped evenly within the atlas's own coordinates.
do
	local texture = setmetatable({}, Texture)
	local info = C_Texture.GetAtlasInfo("wide")
	Art.Cover(texture, "wide", 100, 100)
	local left, right, top, bottom = unpack(texture.coords)
	near(top, info.topTexCoord, "cover: a wide atlas in a square keeps its height")
	near(bottom, info.bottomTexCoord, "cover: to its bottom")
	near(left - info.leftTexCoord, info.rightTexCoord - right, "cover: cropped evenly from both sides")
	aspect((right - left) * 1024, (bottom - top) * 512, 1, "cover: the square crop")
	Art.Cover(texture, "tall", 300, 100)
	left, right, top, bottom = unpack(texture.coords)
	info = C_Texture.GetAtlasInfo("tall")
	near(left, info.leftTexCoord, "cover: a tall atlas in a wide box keeps its width")
	near(right, info.rightTexCoord, "cover: to its right")
	near(top - info.topTexCoord, info.bottomTexCoord - bottom, "cover: cropped evenly top and bottom")
	aspect((right - left) * 1024, (bottom - top) * 512, 3, "cover: the wide crop")
	Art.Cover(texture, "unknown", 300, 100)
	equal(texture.coords, nil, "cover: an unknown atlas is left whole")
end

-- CoverFrame: the crop follows the frame's size, less the trim.
do
	local frame = NewFrame(0, 0)
	local texture = frame:CreateTexture()
	Art.CoverFrame(frame, texture, "tall", 0, 20)
	equal(texture.coords, nil, "cover frame: nothing to crop before the layout")
	frame:Resize(300, 120)
	local left, right, top, bottom = unpack(texture.coords)
	aspect((right - left) * 1024, (bottom - top) * 512, 3, "cover frame: the frame's size less its trim")
end

-- RowTexture: the atlas at its native 69 height, scaled uniformly to the row's height, laid out again when the row
-- resizes, its offsets in its own units.
do
	local frame = NewFrame(120, 44)
	local texture = Art.RowTexture(frame, "wide", "BACKGROUND")
	equal(texture.atlas, "wide", "row: the atlas")
	equal(texture.layer, "BACKGROUND", "row: the layer")
	near(texture:GetScale(), 44 / 69, "row: the row's height over the atlas's")
	equal(texture.height, 69, "row: the atlas's native height")
	near(texture.width * texture:GetScale(), 120, "row: the width spans the row at that scale")
	equal(texture.point.point, "TOPLEFT", "row: anchored at the row's top left")
	equal(texture.point.relative, frame, "row: to the row")
	equal(texture.point.relativePoint, "TOPLEFT", "row: at its top left")
	frame:Resize(300, 26)
	near(texture:GetScale(), 26 / 69, "row: a resize rescales")
	equal(texture.height, 69, "row: still at the native height")
	near(texture.width * texture:GetScale(), 300, "row: and the width follows")
	local offset = Art.RowTexture(frame, "wide", "HIGHLIGHT", 7, -3)
	near(offset.point.x, 7 / (26 / 69), "row: offsets are in the texture's own units")
	near(offset.point.y, -3 / (26 / 69), "row: vertically too")
end

-- Step markers: our own numbered art, square, and the empty ring for a repeated visit.
do
	local texture = setmetatable({}, Texture)
	Art.SetStepMarker(texture, 3, 26)
	equal(
		texture.file,
		"Interface\\AddOns\\AdventureGuideForever\\media\\Numbers\\3.tga",
		"marker: the step's own numbered art"
	)
	equal(texture.atlas, nil, "marker: no atlas")
	for index = 1, 4 do
		equal(texture.coords[index], index % 2 == 1 and 0 or 1, "marker: whole")
	end
	equal(texture.width, 26, "marker: square")
	equal(texture.height, 26, "marker: square")
	Art.SetStepMarker(texture, 10, 24)
	equal(
		texture.file,
		"Interface\\AddOns\\AdventureGuideForever\\media\\Numbers\\10.tga",
		"marker: ten is a texture of its own"
	)
	Art.SetStepMarker(texture, 99, 24)
	equal(
		texture.file,
		"Interface\\AddOns\\AdventureGuideForever\\media\\Numbers\\10.tga",
		"marker: a step past the route's ten keeps the last art"
	)
	Art.SetStepRing(texture, 24)
	equal(texture.file, Art.STEP_RING, "ring: the empty ring")
	equal(texture.width, 24, "ring: square")
end

-- Markup: the height given, the width from the aspect.
do
	equal(Art.Markup("tall", 31), "|A:tall:31:22|a", "markup: the width from the aspect")
	equal(Art.Markup("unknown", 14), "|A:unknown:14:14|a", "markup: an unknown atlas is square")
end

print(("art_spec: %d checks passed"):format(checks))
