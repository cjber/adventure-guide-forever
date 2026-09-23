-- JSON for the test tools (not shipped): sorted keys and "%.2f" numbers, so the output is a stable, reviewable diff.
local json = {}

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function IsArray(value)
	local count = 0
	for _ in pairs(value) do
		count = count + 1
	end
	return count == #value
end

local function Encode(value, indent, out)
	local kind = type(value)
	if kind == "table" then
		local inner = indent .. "  "
		if IsArray(value) then
			if #value == 0 then
				out[#out + 1] = "[]"
				return
			end
			out[#out + 1] = "[\n"
			for index, item in ipairs(value) do
				out[#out + 1] = inner
				Encode(item, inner, out)
				out[#out + 1] = index < #value and ",\n" or "\n"
			end
			out[#out + 1] = indent .. "]"
		else
			local keys = {}
			for key in pairs(value) do
				keys[#keys + 1] = tostring(key)
			end
			table.sort(keys)
			out[#out + 1] = "{\n"
			for index, key in ipairs(keys) do
				out[#out + 1] = inner .. ('"%s": '):format(key)
				Encode(value[key], inner, out)
				out[#out + 1] = index < #keys and ",\n" or "\n"
			end
			out[#out + 1] = indent .. "}"
		end
	elseif kind == "string" then
		out[#out + 1] = '"'
			.. value:gsub('[%c"\\]', function(char)
				return escapes[char] or ("\\u%04x"):format(char:byte())
			end)
			.. '"'
	elseif kind == "number" then
		out[#out + 1] = ("%.2f"):format(value)
	elseif kind == "boolean" then
		out[#out + 1] = tostring(value)
	else
		error("json: cannot encode a " .. kind)
	end
end

function json.encode(value)
	local out = {}
	Encode(value, "", out)
	out[#out + 1] = "\n"
	return table.concat(out)
end

local unescapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" }

function json.decode(text)
	local position = 1
	local function Skip()
		position = text:find("[^ \t\r\n]", position) or #text + 1
	end
	local Value
	function Value()
		Skip()
		local char = text:sub(position, position)
		if char == "{" then
			local object = {}
			position = position + 1
			Skip()
			if text:sub(position, position) == "}" then
				position = position + 1
				return object
			end
			repeat
				Skip()
				local key = Value()
				Skip()
				assert(text:sub(position, position) == ":", "json: expected ':' at " .. position)
				position = position + 1
				object[key] = Value()
				Skip()
				char = text:sub(position, position)
				position = position + 1
			until char ~= ","
			assert(char == "}", "json: expected '}' at " .. position)
			return object
		elseif char == "[" then
			local array = {}
			position = position + 1
			Skip()
			if text:sub(position, position) == "]" then
				position = position + 1
				return array
			end
			repeat
				array[#array + 1] = Value()
				Skip()
				char = text:sub(position, position)
				position = position + 1
			until char ~= ","
			assert(char == "]", "json: expected ']' at " .. position)
			return array
		elseif char == '"' then
			local parts = {}
			position = position + 1
			while true do
				local stop = assert(text:find('["\\]', position), "json: unterminated string")
				parts[#parts + 1] = text:sub(position, stop - 1)
				if text:sub(stop, stop) == '"' then
					position = stop + 1
					return table.concat(parts)
				end
				local escape = text:sub(stop + 1, stop + 1)
				if escape == "u" then
					parts[#parts + 1] = string.char(tonumber(text:sub(stop + 2, stop + 5), 16) % 256)
					position = stop + 6
				else
					parts[#parts + 1] = assert(unescapes[escape], "json: bad escape at " .. stop)
					position = stop + 2
				end
			end
		end
		for literal, result in pairs({ ["true"] = true, ["false"] = false }) do
			if text:sub(position, position + #literal - 1) == literal then
				position = position + #literal
				return result
			end
		end
		local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
		assert(number and #number > 0, "json: unexpected '" .. char .. "' at " .. position)
		position = position + #number
		return (tonumber(number))
	end
	return (Value())
end

return json
