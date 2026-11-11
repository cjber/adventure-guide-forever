-- Run from the repository root: luajit tests/wetlands_chain_spec.lua
-- "Daily Delivery" (469) is Einar Stonegrip's errand to James Halloran, who starts "Young Crocolisk Skins" (484). The
-- game stops offering 469 once 484 is taken or done, but QuestieDB's Forever record carries no breadcrumb link, so the
-- guide still offered it to a player who had finished the chain (#629).
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local ns = {}
ns.Data = harness.data()
harness.model(ns)
local Model, data = ns.Model, ns.Data

-- The missing link: Daily Delivery leads to Young Crocolisk Skins.
equal(data.quests[469].breadcrumb, 484, "Daily Delivery leads to Young Crocolisk Skins")
equal(data.quests[469].pre, nil, "the errand itself needs no quest first")

local player = {
	level = 27,
	maxLevel = 60,
	side = 1,
	raceBit = 1, -- Human
	classBit = 1, -- Warrior
	map = 1437,
	x = 0.4992, -- at Einar Stonegrip, where Daily Delivery starts
	y = 0.3937,
	logMax = 20,
}

-- Offered while Young Crocolisk Skins is neither taken nor done.
equal(Model.Eligible(data, player, {}, {}, 469), true, "before the chain: the errand is open")
-- Taken, it closes.
equal(
	Model.Eligible(data, player, {}, { [484] = { complete = false } }, 469),
	false,
	"in the log: the errand is closed"
)
-- Done, it stays closed.
equal(Model.Eligible(data, player, { [484] = true }, {}, 469), false, "completed: the errand is closed")

print(("wetlands_chain_spec: %d checks passed"):format(checks))
