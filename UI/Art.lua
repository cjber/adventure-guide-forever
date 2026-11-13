---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

--[[ Art at its native aspect (AGENTS.md: never stretch art). Every atlas is sized from C_Texture.GetAtlasInfo: an
     icon fits inside its box, a picture covers its box with the overflow cropped evenly, and art whose atlas carries
     its own nine-slice margins (the rows) is drawn by SetAtlas at the box the client gives it. Only nine-slice
     pieces, bars and tiles stretch, by design. ]]

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

-- A file icon, square as every one is, `size` across and whole: a texture that drew an atlas before keeps that
-- atlas's crop until it is reset.
---@param texture Texture
---@param file string|integer
---@param size number
function Art.Icon(texture, file, size)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetTexture(file)
	texture:SetSize(size, size)
end

-- A button's hover glow: `atlas` again, added over itself, fitted in `width` by `height` as Art.Fit draws the icon
-- under it. Button:SetHighlightAtlas would pull it to the button's own shape.
---@param button Button
---@param atlas string
---@param width number
---@param height number
---@return Texture
function Art.Highlight(button, atlas, width, height)
	local glow = button:CreateTexture(nil, "HIGHLIGHT")
	Art.Fit(glow, atlas, width, height)
	glow:SetPoint("CENTER")
	glow:SetBlendMode("ADD")
	return glow
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

-- File icons use their whole square image, like Art.Icon.
---@param file string
---@param size number
---@return string
function Art.FileMarkup(file, size)
	return ("|T%s:%d:%d|t"):format(file, size, size)
end

-- The Who list's row atlases are 169x69 (WhoList.xml:8, 9 and 59) with 14-pixel horizontal slice margins and none
-- top or bottom: the client draws them at that height on its 69-high rows.
local ROW_ART = 69

-- `atlas` across `row` at the atlas's native 69 height, scaled uniformly to the row's height the way the client scales
-- art (Texture:SetScale, as ActionButtonComponentTemplate.xml's scale="0.8"): the texture keeps the art's own shape,
-- and its width follows so the row is still spanned. SetAllPoints would squash it. The offsets are in the texture's
-- own units too, hence over the scale; it is laid out again whenever the row's size changes.
---@param row Button
---@param atlas string
---@param layer DrawLayer
---@param x? number
---@param y? number
---@return Texture
function Art.RowTexture(row, atlas, layer, x, y)
	local texture = row:CreateTexture(nil, layer)
	texture:SetAtlas(atlas) -- art-ok: at the atlas's native height, scaled uniformly to the row below
	local offsetX, offsetY = x or 0, y or 0
	local function Lay(width, height)
		if height <= 0 then
			return
		end
		local scale = height / ROW_ART
		texture:SetScale(scale)
		texture:SetSize(width / scale, ROW_ART)
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", row, "TOPLEFT", offsetX / scale, offsetY / scale)
	end
	Lay(row:GetSize())
	row:HookScript("OnSizeChanged", function(_, width, height)
		Lay(width, height)
	end)
	return texture
end

-- The route rows' art: the Who list's row (Blizzard_GroupFinder_VanillaStyle WhoList.xml:8, 9 and 59), its hover
-- added over it in the HIGHLIGHT layer a button shows under the mouse, and with `withSelected`, the selected art over
-- the background. Here rather than in Panel.lua because the shared rows in Widgets.lua build theirs too.
---@param row Button
---@param withSelected? boolean
---@return Texture? selected
function Art.RowArt(row, withSelected)
	Art.RowTexture(row, "common-button-list-large", "BACKGROUND")
	local hover = Art.RowTexture(row, "common-button-list-large-hover", "HIGHLIGHT")
	hover:SetBlendMode("ADD")
	if not withSelected then
		return nil
	end
	local selected = Art.RowTexture(row, "common-button-list-large-selected", "BACKGROUND")
	selected:Hide()
	return selected
end

-- The route's gold numbered markers and the empty ring a place visited twice stacks behind its marker: ForeverCore's
-- shared art, so one Forever addon's step looks like the next (ForeverCore.Art, minor 2). Core names each marker for
-- the step's number and answers nil past its own 1 to 25.
Art.STEP_RING = ForeverCore.Art.Ring()

-- A marker's own square, with the crop cleared first so a texture that drew an atlas does not keep its corner.
---@param texture Texture
---@param file string
---@param size? number
local function SetMarker(texture, file, size)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetTexture(file)
	if size then
		texture:SetSize(size, size)
	end
end

-- The gold marker for route step `index`, its number in the art, in this addon's own range: a route is at most
-- Model.MAX_STEPS long, so a step past it keeps the last marker's art rather than core's wider 1 to 25.
---@param texture Texture
---@param index integer
---@param size? number
function Art.SetStepMarker(texture, index, size)
	local last = ns.Model and ns.Model.MAX_STEPS or 10
	local file = ForeverCore.Art.Marker(math.max(1, math.min(index, last)))
	if file then
		SetMarker(texture, file, size)
	end
end

-- The empty ring behind a marker for a place the route visits twice.
---@param texture Texture
---@param size? number
function Art.SetStepRing(texture, size)
	SetMarker(texture, Art.STEP_RING, size)
end

-- The Suggested Content ring icon: art masked to a circle (CircleMaskScalable) inside the Adventure Guide's ring,
-- which is drawn this much larger than the art it frames.
local RING_SCALE = 1.4

-- The circle mask for a ring icon's art, over `anchor` (the frame itself by default).
---@param frame Frame
---@param anchor? Frame
---@return MaskTexture
function Art.RingMask(frame, anchor)
	local mask = frame:CreateMaskTexture()
	mask:SetAtlas("CircleMaskScalable")
	mask:SetAllPoints(anchor or frame)
	return mask
end

-- The ring round a `size`-wide ring icon, centred on `frame` and over its art.
---@param frame Frame
---@param size number
---@return Texture
function Art.Ring(frame, size)
	local ring = frame:CreateTexture(nil, "OVERLAY")
	Art.Fit(ring, "adventureguide-ring", size * RING_SCALE, size * RING_SCALE)
	ring:SetPoint("CENTER")
	return ring
end
