---@type string, AGFNamespace
local _, ns = ...

-- The NPC tooltip line (docs/design.md §2.9): a giver or ender the shown journey's steps visit says so on its unit
-- tooltip. The NPCs are gathered on each route change, so a hover only reads; the line is the tooltip's own, added
-- after the client's (TooltipDataProcessor), and touches no secure frame, in combat or out.

-- The shown journey's title (the chosen one, otherwise accepted quests or the first available card), and the creature
-- entries its steps visit; nil and empty with no card.
---@type string?
local journey
---@type table<integer, true>
local npcs = {}

-- A town's quests stand where its spots are; a turn-in is handed to the quest's finish NPC. An area or dungeon step
-- visits no NPC.
local function Gather()
	local route = ns.Route()
	local card = ns.CurrentJourney()
	journey, npcs = card and card.title, {}
	for _, step in ipairs(route.steps) do
		for _, id in ipairs(step.quests) do
			local quest = ns.Data.quests[id]
			local place = step.spots and step.spots[id] or (step.kind == "turnin" and quest and quest.finish)
			if place and place.npc then
				npcs[place.npc] = true
			end
		end
	end
end
ns.OnRouteChange(Gather)

-- A creature's GUID is "Creature-0-server-instance-zone-entry-spawn" ("Vehicle-..." for one that carries a rider);
-- players, pets and objects have none here. A secret or missing GUID reads as no entry (docs/design.md §2.23).
---@param guid? string
---@return integer?
local function Entry(guid)
	guid = ns.Readable(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, entry = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
	return (kind == "Creature" or kind == "Vehicle") and tonumber(entry) or nil
end

-- The unit's GUID: the tooltip data's own, else the GUID of the unit the tooltip shows. Either may be secret.
---@param tooltip GameTooltip
---@param data? {guid?: string}
---@return string?
local function Guid(tooltip, data)
	local guid = ns.Readable(data and data.guid)
	if guid then
		return guid
	end
	local unit = ns.Readable((select(2, tooltip:GetUnit())))
	return unit and UnitGUID(unit)
end

-- A forbidden tooltip is never read or drawn on, and a unit or GUID the client keeps secret reads as no unit: the hover
-- shows nothing of ours rather than raising an error.
---@param tooltip GameTooltip
---@param data? {guid?: string}
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
	if not journey or not ns.Usable(tooltip) then
		return
	end
	local entry = Entry(Guid(tooltip, data))
	if entry and npcs[entry] then
		GameTooltip_AddNormalLine(tooltip, ns.L.NPC_JOURNEY:format(journey))
	end
end)
