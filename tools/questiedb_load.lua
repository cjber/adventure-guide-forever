-- Loads a QuestieDB release's baked addon offline, as the client would, and returns LibQuestieDB. Run by
-- tools/corpus.lua, which tools/gen_corpus.py drives; never shipped and never loaded by the addon.
--
-- The baked TOC carries its metadata store as zlib-compressed, base64-encoded CBOR, so this reads it with zlib
-- through LuaJIT's FFI and the C_EncodingUtil functions the client would answer with.
local ffi = require("ffi")
local bit = require("bit")
ffi.cdef([[
int uncompress(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen);
]])
local zlib = ffi.load("z")

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local SEXTET = {}
for index = 1, #ALPHABET do
	SEXTET[ALPHABET:byte(index)] = index - 1
end

local function DecodeBase64(text)
	local out, n = {}, 0
	for i = 1, #text - 3, 4 do
		local a, b, c, d = text:byte(i, i + 3)
		local v = SEXTET[a] * 262144 + SEXTET[b] * 4096 + (SEXTET[c] or 0) * 64 + (SEXTET[d] or 0)
		n = n + 1
		if d == 61 then
			out[n] = c == 61 and string.char(bit.rshift(v, 16))
				or string.char(bit.rshift(v, 16), bit.band(bit.rshift(v, 8), 255))
		else
			out[n] = string.char(bit.rshift(v, 16), bit.band(bit.rshift(v, 8), 255), bit.band(v, 255))
		end
	end
	return table.concat(out)
end

local function DecompressString(data)
	local size = #data * 8 + 1024
	while true do
		local buffer, length = ffi.new("uint8_t[?]", size), ffi.new("unsigned long[1]", size)
		local code = zlib.uncompress(buffer, length, data, #data)
		if code == 0 then
			return ffi.string(buffer, length[0])
		end
		assert(code == -5, "zlib error " .. code)
		size = size * 4
	end
end

local function DeserializeCBOR(data)
	local pos = 1
	local Item
	local function UInt(info)
		if info < 24 then
			return info
		end
		local bytes = ({ [24] = 1, [25] = 2, [26] = 4, [27] = 8 })[info]
		local value = 0
		for i = 0, bytes - 1 do
			value = value * 256 + data:byte(pos + i)
		end
		pos = pos + bytes
		return value
	end
	function Item()
		local head = data:byte(pos)
		pos = pos + 1
		local major, info = bit.rshift(head, 5), bit.band(head, 31)
		if major == 0 then
			return UInt(info)
		elseif major == 1 then
			return -1 - UInt(info)
		elseif major == 2 or major == 3 then
			local length = UInt(info)
			local text = data:sub(pos, pos + length - 1)
			pos = pos + length
			return text
		elseif major == 4 then
			local list = {}
			for index = 1, UInt(info) do
				list[index] = Item()
			end
			return list
		elseif major == 5 then
			local map = {}
			for _ = 1, UInt(info) do
				local key = Item()
				map[key] = Item()
			end
			return map
		elseif major == 7 then
			if info == 20 then
				return false
			elseif info == 21 then
				return true
			elseif info == 22 or info == 23 then
				return nil
			elseif info == 26 or info == 27 then
				local bytes = info == 26 and 4 or 8
				local raw = data:sub(pos, pos + bytes - 1):reverse()
				pos = pos + bytes
				return info == 26 and ffi.cast("float*", ffi.cast("const char*", raw))[0]
					or ffi.cast("double*", ffi.cast("const char*", raw))[0]
			elseif info == 25 then
				local h = data:byte(pos) * 256 + data:byte(pos + 1)
				pos = pos + 2
				local sign, exp, frac = bit.rshift(h, 15), bit.band(bit.rshift(h, 10), 31), bit.band(h, 1023)
				local value = exp == 0 and frac * 2 ^ -24
					or (exp == 31 and (frac == 0 and math.huge or 0 / 0))
					or (1 + frac / 1024) * 2 ^ (exp - 15)
				return sign == 1 and -value or value
			end
		end
		error(("unsupported CBOR item %d/%d"):format(major, info))
	end
	return Item()
end

---@param root string the addon directory the release's TOC and files sit in
---@param toc string the TOC file name inside `root`
---@return table lib, table metadata, table env
return function(root, toc)
	local metadata, files = {}, {}
	for line in io.lines(root .. "/" .. toc) do
		line = line:gsub("\r$", "")
		local key, value = line:match("^## ([^:]+): (.*)$")
		if key then
			metadata[key] = value
		elseif line ~= "" and line:sub(1, 1) ~= "#" then
			files[#files + 1] = line:gsub("\\", "/")
		end
	end
	local lib = {}
	local env = setmetatable({
		C_AddOns = {
			GetAddOnMetadata = function(_, key)
				return metadata[key]
			end,
		},
		C_EncodingUtil = {
			DecodeBase64 = DecodeBase64,
			DecompressString = DecompressString,
			DeserializeCBOR = DeserializeCBOR,
		},
		GetLocale = function()
			return "enUS"
		end,
		-- QuestieDB applies some corrections by race, class and faction; the corpus pins one character (Alliance
		-- warrior) so the fixture is one deterministic world, as tests/fixtures/quests.lua's header says.
		UnitFactionGroup = function()
			return "Alliance"
		end,
		UnitClassBase = function()
			return "WARRIOR"
		end,
		CreateFrame = function()
			return setmetatable({}, {
				__index = function()
					return function() end
				end,
			})
		end,
		format = string.format,
		bit = bit,
	}, { __index = _G })
	env._G = env
	for _, file in ipairs(files) do
		local chunk = assert(loadfile(root .. "/" .. file))
		setfenv(chunk, env)
		chunk("QuestieDB", lib)
	end
	return env.LibQuestieDB or lib, metadata, env
end
