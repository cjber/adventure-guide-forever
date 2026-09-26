---@type string, AGFNamespace
local _, ns = ...

--[[ Art at its native aspect (AGENTS.md: never stretch art). Every atlas is sized from C_Texture.GetAtlasInfo: an
     icon fits inside its box, a picture covers its box with the overflow cropped evenly, and fixed-height art whose
     width varies (a row, a bar) is a three-slice whose middle repeats at native scale. Only nine-slice pieces
     stretch, by design. ]]

---@class AGFArt
local Art = {}
ns.Art = Art

-- The atlas's width over its height; square when the client doesn't know it.
---@param atlas string
---@return number
local function Aspect(atlas)
	local info = C_Texture.GetAtlasInfo(atlas)
	if info and info.width > 0 and info.height > 0 then
		return info.width / info.height
	end
	return 1
end

-- `atlas` at the largest size inside `width` by `height` at its own aspect. The caller anchors it by one point.
---@param texture Texture
---@param atlas string
---@param width number
---@param height number
---@return number width
---@return number height
function Art.Fit(texture, atlas, width, height)
	texture:SetAtlas(atlas)
	local aspect = Aspect(atlas)
	local w, h = width, width / aspect
	if h > height then
		w, h = height * aspect, height
	end
	texture:SetSize(w, h)
	return w, h
end

-- `atlas` over the whole of a `width` by `height` box at its own aspect, the overflow cropped evenly from both sides
-- (SetTexCoord within the atlas's own coordinates on its sheet).
---@param texture Texture
---@param atlas string
---@param width number
---@param height number
function Art.Cover(texture, atlas, width, height)
	texture:SetAtlas(atlas)
	local info = C_Texture.GetAtlasInfo(atlas)
	if not (info and info.width > 0 and info.height > 0 and width > 0 and height > 0) then
		return
	end
	local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	local box, native = width / height, info.width / info.height
	if native > box then
		local cut = (right - left) * (1 - box / native) / 2
		left, right = left + cut, right - cut
	else
		local cut = (bottom - top) * (1 - native / box) / 2
		top, bottom = top + cut, bottom - cut
	end
	texture:SetTexCoord(left, right, top, bottom)
end

-- Art.Cover for a texture sized by its anchors: `frame`'s size less `trimWidth` and `trimHeight`, again whenever the
-- frame's size changes. Hooked, so the frame's own OnSizeChanged must be set before this.
---@param frame Frame
---@param texture Texture
---@param atlas string
---@param trimWidth number
---@param trimHeight number
function Art.CoverFrame(frame, texture, atlas, trimWidth, trimHeight)
	local function Lay(width, height)
		Art.Cover(texture, atlas, width - trimWidth, height - trimHeight)
	end
	Lay(frame:GetSize())
	frame:HookScript("OnSizeChanged", function(_, width, height)
		Lay(width, height)
	end)
end

-- `|A:atlas:height:width|a` with the width from the atlas's aspect.
---@param atlas string
---@param height number
---@return string
function Art.Markup(atlas, height)
	return ("|A:%s:%d:%d|a"):format(atlas, height, math.floor(height * Aspect(atlas) + 0.5))
end

---@class AGFArtSlice
---@field frame Frame
---@field atlas string
---@field layer DrawLayer
---@field left number the left cap, in the atlas's pixels
---@field right number the right cap, in the atlas's pixels
---@field pieces Texture[] the caps, then the middle's copies
---@field used integer the pieces the last layout drew
---@field shown boolean

-- One piece: the atlas's sheet cut to pixels `from` to `to` across the atlas, `width` wide at `x` from `point` (the
-- frame's TOPLEFT, or its TOPRIGHT for the right cap, which then needs no width to sit right). The sheet, not
-- SetAtlas: an atlas with slice data (the renown bar's) would nine-slice each piece again.
---@param slice AGFArtSlice
---@param index integer
---@param info AtlasInfo
---@param from number
---@param to number
---@param point "TOPLEFT"|"TOPRIGHT"
---@param x number
---@param width number
---@param height number
local function Piece(slice, index, info, from, to, point, x, width, height)
	local piece = slice.pieces[index]
	if not piece then
		piece = slice.frame:CreateTexture(nil, slice.layer)
		slice.pieces[index] = piece
	end
	local span = info.rightTexCoord - info.leftTexCoord
	piece:SetTexture(info.file or info.filename)
	piece:SetTexCoord(
		info.leftTexCoord + span * from / info.width,
		info.leftTexCoord + span * to / info.width,
		info.topTexCoord,
		info.bottomTexCoord
	)
	piece:ClearAllPoints()
	piece:SetPoint(point, x, 0)
	piece:SetSize(width, height)
	piece:SetShown(slice.shown)
end

-- The caps at the frame's height at native scale, the middle's copies after the left cap until the right, the last
-- cut short; a frame narrower than its caps shows the caps alone, overlapping.
---@param slice AGFArtSlice
local function Lay(slice)
	local info = C_Texture.GetAtlasInfo(slice.atlas)
	local width, height = slice.frame:GetSize()
	if not (info and info.width > 0 and info.height > 0 and height > 0) then
		return
	end
	local scale = height / info.height
	local left, right = slice.left * scale, slice.right * scale
	local strip = info.width - slice.left - slice.right
	Piece(slice, 1, info, 0, slice.left, "TOPLEFT", 0, left, height)
	Piece(slice, 2, info, info.width - slice.right, info.width, "TOPRIGHT", 0, right, height)
	local used, index, x = 2, 3, left
	local room = width - right
	while x < room - 0.01 do
		local drawn = math.min(strip * scale, room - x)
		Piece(slice, index, info, slice.left, slice.left + drawn / scale, "TOPLEFT", x, drawn, height)
		used, index, x = index, index + 1, x + drawn
	end
	slice.used = used
	for rest = used + 1, #slice.pieces do
		slice.pieces[rest]:Hide()
	end
end

-- A horizontal three-slice of `atlas` across `frame` in `layer`: caps `left` and `right` atlas pixels wide, the middle
-- repeated at native scale, never stretched; laid out again whenever the frame's size changes.
---@param frame Frame
---@param atlas string
---@param layer DrawLayer
---@param left number
---@param right number
---@return AGFArtSlice
function Art.Slice(frame, atlas, layer, left, right)
	---@type AGFArtSlice
	local slice =
		{ frame = frame, atlas = atlas, layer = layer, left = left, right = right, pieces = {}, used = 0, shown = true }
	Lay(slice)
	frame:HookScript("OnSizeChanged", function()
		Lay(slice)
	end)
	return slice
end

---@param slice AGFArtSlice
---@param shown boolean
function Art.SetSliceShown(slice, shown)
	slice.shown = shown
	for index = 1, slice.used do
		slice.pieces[index]:SetShown(shown)
	end
end
