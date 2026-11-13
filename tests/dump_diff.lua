-- Usage, from the repository root: luajit tests/dump_diff.lua <WTF/.../SavedVariables/AdventureGuideForever.lua>
-- Compares the layout /agf dump saved in game with tests/golden/layout.json: the region paths, atlases and
-- explicitly set sizes (a scaled region's height, since its width comes from the layout). Font metrics and
-- stock-template sizes legitimately differ, so they are not compared (a font string's set width is measured from its
-- text, Panel.lua's row detail), and the regions only the game draws (stock-template chrome the harness stubs) are
-- counted, not failed.
local diff = {}

local function Size(entry)
	return entry.size and ("%.2fx%.2f"):format(entry.size[1], entry.size[2]) or "none"
end

-- A region's horizontal position as `c + w * W`, W the header's width: an anchor on the header's right edge moves
-- with it, everything inside the header keeps its offset.
local POINT_X = {
	TOPLEFT = 0,
	LEFT = 0,
	BOTTOMLEFT = 0,
	TOP = 0.5,
	CENTER = 0.5,
	BOTTOM = 0.5,
	TOPRIGHT = 1,
	RIGHT = 1,
	BOTTOMRIGHT = 1,
}

local function Plus(expr, offset)
	return { c = expr.c + offset, w = expr.w }
end

local function Same(left, right)
	return left.c == right.c and left.w == right.w
end

-- The header's lines (the guide's title and the line under it) sit in one span, from the guide icon's right edge to
-- the header's right inset. Returns a line per header line that is not anchored on both horizontal edges in that
-- span, or that starts over the header's leading art (the back arrow and the compass). The dump is compared from the
-- anchors alone, so it holds for every view: a line anchored by a bare centre or one edge can grow back over the
-- arrow and the icon, which is how the synced line once did (#617).
function diff.HeaderLines(layout, title)
	local byPath, problems = {}, {}
	for _, entry in ipairs(layout) do
		byPath[entry.path] = entry
	end
	local titlePath
	for _, entry in ipairs(layout) do
		if entry.type == "FontString" and entry.text == title then
			titlePath = entry.path
		end
	end
	if not titlePath then
		return { "header: no line reads " .. tostring(title) }
	end
	local header = titlePath:match("^(.*)%.[^.]+$")
	-- Resolves a region inside the header to its left and right edges, and whether each edge is anchored rather than
	-- inferred from an explicit width.
	local resolved = {}
	local function Resolve(path)
		if resolved[path] ~= nil then
			return resolved[path]
		end
		if path == header then
			resolved[path] =
				{ left = { c = 0, w = 0 }, right = { c = 0, w = 1 }, leftAnchored = true, rightAnchored = true }
			return resolved[path]
		end
		local entry = byPath[path]
		if not entry or (path ~= header and path:match("^(.*)%.[^.]+$") ~= header) then
			resolved[path] = false
			return false
		end
		local left, right, leftAnchored, rightAnchored
		for _, anchor in ipairs(entry.anchors or {}) do
			local other = anchor.relativeTo and Resolve(anchor.relativeTo)
			if not other then
				resolved[path] = false
				return false
			end
			local fraction = POINT_X[anchor.relativePoint]
			local base
			if fraction == 0 then
				base = other.left
			elseif fraction == 1 then
				base = other.right
			else
				base = {
					c = other.left.c + (other.right.c - other.left.c) / 2,
					w = other.left.w + (other.right.w - other.left.w) / 2,
				}
			end
			local x = Plus(base, anchor.x or 0)
			local own = POINT_X[anchor.point]
			if own == 0 then
				left, leftAnchored = x, true
			elseif own == 1 then
				right, rightAnchored = x, true
			end
		end
		local width = entry.size and entry.size[1] or 0
		if width > 0 then
			if not left and right then
				left = Plus(right, -width)
			elseif not right and left then
				right = Plus(left, width)
			end
		end
		if not left or not right then
			resolved[path] = false
			return false
		end
		resolved[path] = { left = left, right = right, leftAnchored = leftAnchored, rightAnchored = rightAnchored }
		return resolved[path]
	end
	-- The leading art: every control the header draws before its text. A line must start clear of the rightmost.
	local leading
	for _, entry in ipairs(layout) do
		if entry.path ~= header and entry.path:match("^(.*)%.[^.]+$") == header and entry.type ~= "FontString" then
			local rect = Resolve(entry.path)
			if rect and rect.right.w == 0 and (not leading or rect.right.c > leading) then
				leading = rect.right.c
			end
		end
	end
	local span
	for _, entry in ipairs(layout) do
		if entry.type == "FontString" and entry.path:match("^(.*)%.[^.]+$") == header and entry.path ~= titlePath then
			local rect = Resolve(entry.path)
			if not (rect and rect.leftAnchored and rect.rightAnchored) then
				problems[#problems + 1] = entry.path
					.. ": a header line must be anchored on both edges of the text span"
			else
				if leading and rect.left.c <= leading then
					problems[#problems + 1] = ("%s: starts at %.2f, over the header's art (right edge %.2f)"):format(
						entry.path,
						rect.left.c,
						leading
					)
				end
				if rect.right.w ~= 1 then
					problems[#problems + 1] = entry.path .. ": its right edge is not the panel's right inset"
				end
				if span then
					if not Same(rect.left, span.left) or not Same(rect.right, span.right) then
						problems[#problems + 1] = entry.path .. ": not in the title's text span"
					end
				else
					span = rect
				end
			end
		end
	end
	local titleRect = Resolve(titlePath)
	if not (titleRect and titleRect.leftAnchored and titleRect.rightAnchored) then
		problems[#problems + 1] = titlePath .. ": the title must be anchored on both edges of its text span"
	else
		if leading and titleRect.left.c <= leading then
			problems[#problems + 1] = ("%s: starts at %.2f, over the header's art (right edge %.2f)"):format(
				titlePath,
				titleRect.left.c,
				leading
			)
		end
		if titleRect.right.w ~= 1 then
			problems[#problems + 1] = titlePath .. ": its right edge is not the panel's right inset"
		end
		if span and (not Same(titleRect.left, span.left) or not Same(titleRect.right, span.right)) then
			problems[#problems + 1] = titlePath .. ": not in the same text span as the line under it"
		end
	end
	return problems
end

-- Returns the differences as lines, and how many regions only the game has.
function diff.Compare(golden, game)
	local byPath, differences, onlyInGame = {}, {}, 0
	for _, entry in ipairs(game) do
		byPath[entry.path] = entry
	end
	local seen = {}
	for _, entry in ipairs(golden) do
		seen[entry.path] = true
		local other = byPath[entry.path]
		if not other then
			differences[#differences + 1] = entry.path .. ": missing in game"
		else
			if entry.atlas ~= other.atlas then
				differences[#differences + 1] = ("%s: atlas %s in golden, %s in game"):format(
					entry.path,
					tostring(entry.atlas),
					tostring(other.atlas)
				)
			end
			-- A stock template sizes itself in game only (UIPanelIconDropdownButtonTemplate is 15x16).
			local sameSize = Size(entry) == Size(other)
			-- A scaled region's width is the frame it is laid across, over its scale: the headless golden has no
			-- layout to resolve that in, so only the height (the art's native) is compared there.
			if entry.scale and entry.size and other.size then
				sameSize = ("%.2f"):format(entry.size[2]) == ("%.2f"):format(other.size[2])
			end
			if not entry.stockTemplate and entry.type ~= "FontString" and not sameSize then
				differences[#differences + 1] = ("%s: size %s in golden, %s in game"):format(
					entry.path,
					Size(entry),
					Size(other)
				)
			end
		end
	end
	for _, entry in ipairs(game) do
		onlyInGame = onlyInGame + (seen[entry.path] and 0 or 1)
	end
	return differences, onlyInGame
end

local function Main(savedVariables)
	local json = dofile("tests/json.lua")
	local handle = assert(io.open("tests/golden/layout.json"))
	local golden = json.decode(handle:read("*a"))
	handle:close()
	local env = {}
	setfenv(assert(loadfile(savedVariables)), env)()
	local dump = assert(env.AdventureGuideForeverDB and env.AdventureGuideForeverDB.dump, "no dump: run /agf dump")
	local differences, onlyInGame = diff.Compare(golden.layout, dump.layout or {})
	print(("build %s; %d regions only in game"):format(tostring(dump.build), onlyInGame))
	for _, line in ipairs(differences) do
		print(line)
	end
	print(("%d differences"):format(#differences))
	os.exit(#differences == 0 and 0 or 1)
end

-- Run as a script only: ui_spec loads this file for Compare.
if arg and arg[0] and arg[0]:match("dump_diff%.lua$") then
	Main(assert(arg[1], "usage: luajit tests/dump_diff.lua <AdventureGuideForever.lua>"))
end

return diff
