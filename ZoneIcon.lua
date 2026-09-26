---@type string, AGFNamespace
local _, ns = ...

-- The overview's round zone icons (docs/design.md §2.2): the Suggested Content recipe, the zone's own map cut to a
-- circle (CircleMaskScalable) inside the Adventure Guide's ring, with the card's kind as a badge at its bottom-right.
-- The map is the world map's: the base tiles the client gives (C_Map.GetMapArtLayerTextures) under every overlay
-- Data/ZoneArt.lua has, explored or not, so a zone not yet seen still shows its towns and forests. A window `span`
-- map pixels wide is cut round the zone's next town and kept 20 pixels inside the art's edge. A zone the data has
-- no art for, or whose tiles the client does not give, keeps the plain ring with its kind centred in it.
---@class AGFZoneIconImpl : AGFZoneIconModule
local ZoneIcon = {}
ns.ZoneIcon = ZoneIcon

-- The zone art canvas the generator keeps (tools/gen_zoneart.py): 1002x668 map pixels of 256-pixel tiles, 4 across.
local ART_WIDTH, ART_HEIGHT, TILE, COLUMNS, TILES = 1002, 668, 256, 4, 12
local EDGE = 20
-- The ring is drawn this much larger than the art it frames, as the mock's recipe has it.
local RING_SCALE = 1.4

---@class AGFZoneIcon : Frame
---@field Clip Frame
---@field Art AGFZoneIconArt
---@field Border Frame
---@field Ring Texture
---@field Kind Texture
---@field size number
---@field width number the art's width across, as the size is
---@field badge number
---@field key? string the zone and window drawn, so an unchanged icon builds nothing

---@class AGFZoneIconArt : Frame
---@field Mask MaskTexture
---@field base Texture[]
---@field overlays Texture[]

-- The next unused texture of `pool` on the art, created masked the first time.
---@param art AGFZoneIconArt
---@param pool Texture[]
---@param used integer
---@param layer DrawLayer
---@return Texture
local function Acquire(art, pool, used, layer)
	local texture = pool[used]
	if not texture then
		texture = art:CreateTexture(nil, layer)
		if art.Mask then
			texture:AddMaskTexture(art.Mask)
		end
		pool[used] = texture
	end
	texture:ClearAllPoints()
	texture:Show()
	return texture
end

-- The power of two a map overlay's last tile is stored in, as MapExplorationPinMixin reads it: 16 and up.
---@param pixels integer
---@return integer
local function FileSize(pixels)
	local size = 16
	while size < pixels do
		size = size * 2
	end
	return size
end

-- The art under `icon`'s clip: a window `span` by `tall` map pixels round `x`, `y`, kept EDGE inside the art, drawn
-- `icon.width` across. Only the tiles and overlay pieces the window shows are placed.
---@param icon AGFZoneIcon|AGFZoneBackdrop
---@param map integer
---@param base integer[]
---@param overlays table
---@param x number
---@param y number
---@param span number
---@param tall number
local function Fill(icon, map, base, overlays, x, y, span, tall)
	local left = math.min(math.max(x * ART_WIDTH - span / 2, EDGE), ART_WIDTH - EDGE - span)
	local top = math.min(math.max(y * ART_HEIGHT - tall / 2, EDGE), ART_HEIGHT - EDGE - tall)
	local key = ("%d:%.1f:%.1f:%.1f:%.1f:%.1f"):format(map, left, top, span, tall, icon.width)
	if key == icon.key then
		return
	end
	icon.key = key
	local art, k = icon.Art, icon.width / span
	art:SetSize(ART_WIDTH * k, ART_HEIGHT * k)
	art:ClearAllPoints()
	art:SetPoint("TOPLEFT", icon.Clip, "TOPLEFT", -left * k, top * k)
	local right, bottom = left + span, top + tall
	-- Only what the window shows: a tile or overlay piece at (px, py), w x h map pixels.
	local function Shows(px, py, w, h)
		return px < right and px + w > left and py < bottom and py + h > top
	end
	local used = 0
	for index = 1, TILES do
		local px, py = (index - 1) % COLUMNS * TILE, math.floor((index - 1) / COLUMNS) * TILE
		if Shows(px, py, TILE, TILE) then
			used = used + 1
			local texture = Acquire(art, art.base, used, "BACKGROUND")
			texture:SetTexture(base[index])
			texture:SetSize(TILE * k, TILE * k)
			texture:SetPoint("TOPLEFT", px * k, -py * k)
		end
	end
	for index = used + 1, #art.base do
		art.base[index]:Hide()
	end
	used = 0
	for _, overlay in ipairs(overlays) do
		local ox, oy, width, height = overlay[1], overlay[2], overlay[3], overlay[4]
		local across = math.ceil(width / TILE)
		for tile = 5, #overlay do
			local col, row = (tile - 5) % across, math.floor((tile - 5) / across)
			local tw = col == across - 1 and width - col * TILE or TILE
			local th = row == math.ceil(height / TILE) - 1 and height - row * TILE or TILE
			local px, py = ox + col * TILE, oy + row * TILE
			if Shows(px, py, tw, th) then
				used = used + 1
				local texture = Acquire(art, art.overlays, used, "BORDER")
				texture:SetTexture(overlay[tile] --[[@as integer]])
				texture:SetTexCoord(0, tw / FileSize(tw), 0, th / FileSize(th))
				texture:SetSize(tw * k, th * k)
				texture:SetPoint("TOPLEFT", px * k, -py * k)
			end
		end
	end
	for index = used + 1, #art.overlays do
		art.overlays[index]:Hide()
	end
end

---@param parent Frame
---@param size number the art's width across
---@param badge number the kind icon's size at the bottom-right
---@return AGFZoneIcon
function ZoneIcon.Create(parent, size, badge)
	local icon = CreateFrame("Frame", nil, parent) --[[@as AGFZoneIcon]]
	icon:SetSize(size, size)
	icon.size, icon.width, icon.badge = size, size, badge
	icon.Clip = CreateFrame("Frame", nil, icon)
	icon.Clip:SetAllPoints()
	icon.Clip:SetClipsChildren(true)
	local art = CreateFrame("Frame", nil, icon.Clip) --[[@as AGFZoneIconArt]]
	art.base, art.overlays = {}, {}
	art.Mask = art:CreateMaskTexture()
	art.Mask:SetAtlas("CircleMaskScalable")
	art.Mask:SetAllPoints(icon.Clip)
	icon.Art = art
	-- Over the art, whichever frame level the client gives the clip.
	icon.Border = CreateFrame("Frame", nil, icon)
	icon.Border:SetAllPoints()
	icon.Border:SetFrameLevel(icon:GetFrameLevel() + 3)
	icon.Ring = icon.Border:CreateTexture(nil, "OVERLAY")
	icon.Ring:SetAtlas("adventureguide-ring")
	icon.Ring:SetSize(size * RING_SCALE, size * RING_SCALE)
	icon.Ring:SetPoint("CENTER")
	icon.Kind = icon.Border:CreateTexture(nil, "OVERLAY", nil, 1)
	return icon
end

-- The zone's art round `x`, `y` (0-1 on the map), or the plain ring with `atlas` centred when there is none.
---@param icon AGFZoneIcon
---@param atlas string the card's kind icon
---@param map? integer
---@param x? number
---@param y? number
---@param span number map pixels across the window
function ZoneIcon.Set(icon, atlas, map, x, y, span)
	local overlays = map and ns.Data.zoneArt and ns.Data.zoneArt[map] or nil
	local base = map and overlays and x and y and C_Map.GetMapArtLayerTextures(map, 1) or nil
	local drawn = base ~= nil and #base >= TILES
	icon.Kind:ClearAllPoints()
	if drawn then
		ns.Art.Fit(icon.Kind, atlas, icon.badge, icon.badge)
		icon.Kind:SetPoint("CENTER", icon, "BOTTOMRIGHT", -2, 2)
	else
		local centred = math.floor(icon.size * 0.45)
		ns.Art.Fit(icon.Kind, atlas, centred, centred)
		icon.Kind:SetPoint("CENTER")
	end
	icon.Clip:SetShown(drawn)
	if not drawn then
		icon.key = nil
		return
	end
	---@cast map -?
	---@cast base -?
	---@cast overlays -?
	---@cast x -?
	---@cast y -?
	Fill(icon, map, base, overlays, x, y, span, span)
end

-- A card's backdrop in the Adventure Guide window: the same zone art as a rectangle with no ring, mask or badge, cut
-- round the card's next town. Hidden where the data has no art for the zone, so the card's own fill shows.
---@param parent Frame
---@return AGFZoneBackdrop
function ZoneIcon.CreateBackdrop(parent)
	local backdrop = CreateFrame("Frame", nil, parent) --[[@as AGFZoneBackdrop]]
	backdrop.width = 0
	backdrop.Clip = CreateFrame("Frame", nil, backdrop)
	backdrop.Clip:SetAllPoints()
	backdrop.Clip:SetClipsChildren(true)
	local art = CreateFrame("Frame", nil, backdrop.Clip) --[[@as AGFZoneIconArt]]
	art.base, art.overlays = {}, {}
	backdrop.Art = art
	return backdrop
end

-- The zone's art round `x`, `y` in `width` by `height`, `span` map pixels across; false, and hidden, when there is
-- none.
---@param backdrop AGFZoneBackdrop
---@param width number
---@param height number
---@param map? integer
---@param x? number
---@param y? number
---@param span number
---@return boolean drawn
function ZoneIcon.SetBackdrop(backdrop, width, height, map, x, y, span)
	local overlays = map and ns.Data.zoneArt and ns.Data.zoneArt[map] or nil
	local base = map and overlays and x and y and C_Map.GetMapArtLayerTextures(map, 1) or nil
	local drawn = base ~= nil and #base >= TILES
	backdrop:SetShown(drawn)
	if not drawn then
		backdrop.key = nil
		return false
	end
	---@cast base -?
	---@cast overlays -?
	---@cast x -?
	---@cast y -?
	backdrop:SetSize(width, height)
	backdrop.width = width
	Fill(backdrop, map --[[@as integer]], base, overlays, x, y, span, span * height / width)
	return true
end
