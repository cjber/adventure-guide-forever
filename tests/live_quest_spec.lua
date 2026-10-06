-- A Forever quest missing from QuestieDB must still use the client's map POI end to end.
local fixture = dofile("tests/fixtures/dun_morogh_live.lua")
fixture.setup = function(h)
	local quests = h.ns.Data.quests
	-- Limit the provider to the known pickups and hand-ins offered in this live route.
	local available = {}
	for _, id in ipairs({ 419, 432, 310, 320 }) do
		available[id] = quests[id]
	end
	h.ns.Data.quests = available
end
local h = dofile("tests/harness.lua").load(fixture)
local positions, dawn = {}, nil
for index, step in ipairs(h.ns.Route().steps) do
	for _, id in ipairs(step.quests) do
		positions[id] = positions[id] or index
	end
	if step.key == "turnin:99158" then
		dawn = step
	end
end
assert(dawn, "Dawn in the Mountains survives client state, zone selection and lap planning")
assert(dawn.map == 1426 and math.abs(dawn.x - 0.57727587223053) < 0.000001, "uses the native map location")
assert(positions[310] < positions[99158] and positions[320] < positions[99158], "nearer ready hand-ins come first")
assert(not positions[419], "the bounded preview keeps carried waypoints ahead of the farther Lost Pilot pickup")
assert(positions[99158] < positions[432], "hand in Dawn before the eastern trogg pickup")
for _, id in ipairs({ 412, 287, 98326, 315 }) do
	assert(positions[id], "carried client waypoint survives without database objective slots: " .. id)
end
assert(#h.errors == 0, "live-log replay raises no errors")
print("live_quest_spec: 10 checks passed")
