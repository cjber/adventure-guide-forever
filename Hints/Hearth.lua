---@type string, AGFNamespace
local _, ns = ...
---@class AGFHearth
local Hearth = {}
ns.Hearth = Hearth

function Hearth.Advice(data, player, steps, bind, locale)
	-- Bundled hub names are English; another locale cannot establish the bind's identity.
	if (locale ~= "enUS" and locale ~= "enGB") or not bind or bind == "" then
		return nil
	end
	local bound
	for id, hub in pairs(data.hubs or {}) do
		if (hub.name:match("^(.-),") or hub.name) == bind then
			if bound then
				return nil
			end
			bound = id
		end
	end
	if not bound then
		return nil
	end
	local target
	for _, step in ipairs(steps) do
		if step.hub and data.hubs[step.hub] then
			target = step
			break
		end
	end
	if not target or target.hub == bound then
		return nil
	end
	local best, bestID, distance
	for id, npc in pairs(data.npcs or {}) do
		if
			npc.inn
			and npc.place.hub == target.hub
			and (not npc.side or npc.side == 0 or math.floor(npc.side / player.side) % 2 == 1)
		then
			local yards = ns.Model.Yards(data, player, npc.place) or ns.Model.Yards(data, target, npc.place)
			if yards and (not best or yards < distance or (yards == distance and id < bestID)) then
				best, bestID, distance = npc, id, yards
			end
		end
	end
	if not best then
		return nil
	end
	return {
		key = "hearth:" .. target.hub,
		text = ns.L.SET_HEARTH:format(ns.Model.TownName(data, best.place)),
		icon = "innkeeper",
		place = best.place,
	}
end

ns.Asides.Register(function()
	local route = ns.Route()
	if not route.chosen then
		return nil
	end
	return Hearth.Advice(ns.Data, ns.State.Player(), route.steps, GetBindLocation and GetBindLocation(), GetLocale())
end)
ns.Asides.RefreshOn("HEARTHSTONE_BOUND")
