---@type string, AGFNamespace
local _, ns = ...

-- One renderer for every step line: the tracker, the guide's rows, the overview and the pin tooltips all call this,
-- so an AGF journey and a RestedXP guide read alike (docs/design.md §2.5). A role says what a word is; the client's
-- colour for that role is chosen once here. RestedXP's own roles are roles too, used only for its steps (#351, #376).
---@class AGFStepStyle
local Style = {}
ns.StepStyle = Style

local function Wrap(color, text)
	return color:WrapTextInColorCode(text)
end

-- The colours of a step line. A role with no colour of the game's own reads as plain text.
---@param role? string
---@param id? integer an item's ID, for the quality of an item role
---@return ColorMixin?
function Style.Color(role, id)
	if role == "enemy" or role == "RXP_ENEMY_" then
		return FACTION_RED_COLOR
	elseif role == "friendly" or role == "npc" or role == "RXP_FRIENDLY_" then
		return FACTION_GREEN_COLOR
	elseif role == "quest" or role == "warn" or role == "RXP_WARN_" then
		return NORMAL_FONT_COLOR
	elseif role == "zone" then
		return HIGHLIGHT_FONT_COLOR
	elseif role == "item" or role == "RXP_LOOT_" or role == "RXP_BUY_" then
		local quality = id and C_Item.GetItemQualityByID(id)
		local colors = quality and ITEM_QUALITY_COLORS[quality]
		return colors and colors.color or HIGHLIGHT_FONT_COLOR
	end
end

-- `text` in `color`, or unchanged when the role has none.
---@param color? ColorMixin
---@param text? string
---@return string
function Style.Wrap(color, text)
	return color and text and text ~= "" and Wrap(color, text) or text or ""
end

-- The colour a quest title takes where it is named inside a step line (#351): the game's own gold.
---@param text? string
---@return string
function Style.Quest(text)
	return Style.Wrap(NORMAL_FONT_COLOR, text)
end

-- A quest's name, from the log where the client has it, else the catalogue.
---@param id integer
---@return string?
local function QuestTitle(id)
	return ns.State.QuestTitle(id) or (ns.Data.quests[id] and ns.Data.quests[id].title)
end

-- The colour of an NPC by its side, as a quest giver's reaction: the player's own side and both sides are friendly,
-- the other side is an enemy, and an NPC the data gives no side stays plain.
---@param side? integer
---@param playerSide? integer
---@return string?
local function SideRole(side, playerSide)
	if side == nil or playerSide == nil then
		return nil
	end
	return (side == 3 or side == playerSide) and "friendly" or "enemy"
end

-- The word as a styled part, once, and only when it is long enough to mean something: a one- or two-letter NPC name
-- would colour half a sentence.
---@param parts {text: string, kind: string, id?: integer}[]
---@param seen table<string, true>
---@param text? string
---@param kind? string
---@param id? integer
local function Add(parts, seen, text, kind, id)
	if type(text) ~= "string" then
		return
	end
	text = text:match("^%s*(.-)%s*$")
	if #text < 3 or not kind then
		return
	end
	local key = kind .. "\0" .. text
	if seen[key] then
		return
	end
	seen[key] = true
	parts[#parts + 1] = { text = text, kind = kind, id = id }
end

-- What AGF's own data names in `step`: its quests in gold, the NPCs they start and end at by their side, the items
-- its objectives name, and its zone.
---@param step? AGFStep|AGFGiver
---@param extra? {text: string, kind: string, id?: integer}[]
---@return {text: string, kind: string, id?: integer}[]
function Style.StepParts(step, extra)
	local parts, seen = {}, {}
	local data = ns.Data
	local player = ns.State.Player()
	for _, part in ipairs(extra or {}) do
		Add(parts, seen, part.text, part.kind, part.id)
	end
	if not step then
		return parts
	end
	for _, id in ipairs(step.quests or {}) do
		local quest = data.quests[id]
		Add(parts, seen, QuestTitle(id), "quest")
		if quest then
			for _, place in ipairs({ quest.start or {}, quest.finish or {} }) do
				---@type AGFNpc?
				local npc = place.npc and data.npcs and data.npcs[place.npc] or nil
				local side = npc and npc.side or quest.side
				Add(parts, seen, place.name, place.npc and SideRole(side, player.side) or nil)
			end
			-- Only an item's name has a role here: its quality. Whether a creature is neutral, friendly or hostile is
			-- not in the data, and guessing "monster" as enemy painted neutral wildlife red.
			for slot, name in pairs(quest.names or {}) do
				if quest.kinds and quest.kinds[slot] == "item" then
					Add(parts, seen, name, "item", quest.items and quest.items[slot] or nil)
				end
			end
		end
	end
	Add(parts, seen, step.questTitle, "quest")
	Add(parts, seen, step.zone, "zone")
	local zone = data.zones and data.zones[step.map]
	Add(parts, seen, zone and zone.name, "zone")
	return parts
end

-- `text` with every word AGF's data names in `step` in its role's colour, longest first so a full name wins over a
-- shorter name inside it. One pass over the line keeps two names from colouring each other's markup.
---@param step? AGFStep|AGFGiver
---@param text? string
---@param extra? {text: string, kind: string, id?: integer}[]
---@return string
function Style.Step(step, text, extra)
	text = text or ""
	if text == "" then
		return text
	end
	local parts = Style.StepParts(step, extra)
	table.sort(parts, function(a, b)
		return #a.text > #b.text
	end)
	local lower, out, index = text:lower(), {}, 1
	while index <= #text do
		local found
		for _, part in ipairs(parts) do
			local size = #part.text
			if lower:sub(index, index + size - 1) == part.text:lower() then
				found = part
				break
			end
		end
		local size = found and #found.text or 1
		out[#out + 1] = found and Style.Wrap(Style.Color(found.kind, found.id), text:sub(index, index + size - 1))
			or text:sub(index, index)
		index = index + size
	end
	return table.concat(out)
end

-- A step's title, styled from its own data: the quest or NPC it names, and its zone.
---@param step? AGFStep|AGFGiver
---@param text? string
---@return string
function Style.StepTitle(step, text)
	return Style.Step(step, text or (step and step.title) or "")
end

-- One line of a step's checklist. A town's giver is a friendly NPC when the data places an NPC there, an object
-- otherwise; the rest of the row keeps its own words. RestedXP rows already carry their guide's colours.
---@param step? AGFStep
---@param row? AGFTownGiver
---@return string
function Style.Checklist(step, row)
	if not row then
		return ""
	end
	if row.rxpTag then
		return row.text
	end
	local npc = false
	for _, list in ipairs({ row.pickups or {}, row.handins or {} }) do
		for _, id in ipairs(list) do
			local place = step and step.spots and step.spots[id]
			npc = npc or (place ~= nil and place.npc ~= nil)
		end
	end
	return Style.Step(step, row.text, row.name and { { text = row.name, kind = npc and "friendly" or nil } } or nil)
end
