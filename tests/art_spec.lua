-- Run from the repository root: luajit tests/art_spec.lua
-- Art.lua on its own, with a stub C_Texture.GetAtlasInfo and stub textures and frames: an atlas fits its box at its
-- own aspect, covers a box with the overflow cropped evenly, and a three-slice repeats its middle at native scale.
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
function Texture:ClearAllPoints()
	self.point = nil
end
function Texture:SetPoint(point, x)
	self.point, self.x = point, x
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
local chunk = assert(loadfile("Art.lua"))
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

-- Markup: the height given, the width from the aspect.
do
	equal(Art.Markup("tall", 31), "|A:tall:31:22|a", "markup: the width from the aspect")
	equal(Art.Markup("unknown", 14), "|A:unknown:14:14|a", "markup: an unknown atlas is square")
end

-- Slice: caps at native scale for the frame's height, the middle repeated at native scale and the last copy cut.
do
	local frame = NewFrame(440, 44)
	local slice = Art.Slice(frame, "wide", "BACKGROUND", 12, 12)
	local info = C_Texture.GetAtlasInfo("wide")
	local scale, pixel = 44 / 46, (info.rightTexCoord - info.leftTexCoord) / 209
	local strip = (209 - 24) * scale
	local copies = math.ceil((440 - 24 * scale) / strip)
	equal(copies, 3, "slice: 440 wide takes three copies of the middle")
	equal(slice.used, 2 + copies, "slice: two caps and the copies")
	local covered = 0
	for index = 1, slice.used do
		local piece = slice.pieces[index]
		local left, right, top, bottom = unpack(piece.coords)
		equal(piece.file, 12345, "slice: the atlas's sheet")
		equal(piece.layer, "BACKGROUND", "slice: in its layer")
		equal(piece.height, 44, "slice: the frame's height")
		near(top, info.topTexCoord, "slice: the atlas's top")
		near(bottom, info.bottomTexCoord, "slice: the atlas's bottom")
		-- Each piece at native scale: its width is its pixels across the atlas at the height's scale.
		near(piece.width, (right - left) / pixel * scale, "slice: piece " .. index .. " at native scale")
		covered = covered + piece.width
	end
	near(covered, 440, "slice: the pieces cover the frame")
	equal(slice.pieces[1].point, "TOPLEFT", "slice: the left cap at the left")
	equal(slice.pieces[2].point, "TOPRIGHT", "slice: the right cap at the right")
	near(slice.pieces[2].coords[2], info.rightTexCoord, "slice: the right cap ends the atlas")
	local last = slice.pieces[slice.used]
	equal(last.width < strip, true, "slice: the last copy cut short")
	near(last.x + last.width, 440 - 12 * scale, "slice: the last copy meets the right cap")

	frame:Resize(230, 44)
	equal(slice.used, 4, "slice: narrower, two copies")
	equal(slice.pieces[5].shown, false, "slice: the copy no longer needed hides")
	Art.SetSliceShown(slice, false)
	equal(slice.pieces[1].shown, false, "slice: hidden")
	Art.SetSliceShown(slice, true)
	equal(slice.pieces[4].shown, true, "slice: shown again")
	equal(slice.pieces[5].shown, false, "slice: the spare copy stays hidden")
end

print(("art_spec: %d checks passed"):format(checks))
