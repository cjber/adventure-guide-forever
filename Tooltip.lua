---@type string, AGFNamespace
local _, ns = ...

-- The NPC tooltip line (docs/design.md §2.9): a giver or ender the shown journey's steps visit says so on its unit
-- tooltip. The NPCs are gathered on each route change, so a hover only reads; the line is the tooltip's own, added
-- after the client's (TooltipDataProcessor), and touches no secure frame, in combat or out.

-- The shown journey's title (the chosen one, else the first card, which the guide draws on its own), and the creature
-- entries its steps visit; nil and empty with no card.
---@type string?
local journey
---@type table<integer, true>
local npcs = {}

-- A town's quests stand where its spots are; a turn-in is handed to the quest's finish NPC. An area or dungeon step
-- visits no NPC.
local function Gather()
	local route = ns.Route()
	journey, npcs = nil, {}
	for _, card in ipairs(route.journeys) do
		journey = card.key == route.journey and card.title or journey
	end
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

-- A creature's GUID is "Creature-0-server-instance-zone-entry-spawn"; players, pets and objects have none here.
---@param guid? string
---@return integer?
local function Entry(guid)
	return guid and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$"))
end

---@param tooltip GameTooltip
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
	if not journey then
		return
	end
	local _, unit = tooltip:GetUnit()
	local entry = unit and Entry(UnitGUID(unit))
	if entry and npcs[entry] then
		GameTooltip_AddNormalLine(tooltip, ns.L.NPC_JOURNEY:format(journey))
	end
end)
