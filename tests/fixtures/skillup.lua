-- SkillUp Forever's Professions() for a level-18 leatherworker who also tailors, shaped as its API.lua gives it
-- (cjber/skillup-forever 84422ed): tests/window_spec.lua and tests/scenes.lua share it. Item names and icons are the
-- DB2's, for harness.load's options.items.
local LEATHERWORKING = {
	name = "Leatherworking",
	skillLineID = 165,
	icon = 136247,
	rank = 142,
	maxRank = 150,
	title = "Journeyman",
	steps = {
		{ kind = "buy", text = "Buy 26 Fine Thread", detail = "Vendor", itemID = 2321, count = 26, nav = true },
		{ kind = "craft", text = "Craft 3 Toughened Leather Gloves", detail = "142 to 145", nav = false },
		{ kind = "train", text = "Train Hillman's Leather Gloves", nav = true, cost = 1800 },
	},
	recipes = {
		{
			spellID = 3770,
			itemID = 4253,
			name = "Toughened Leather Gloves",
			count = 3,
			fromRank = 142,
			toRank = 145,
			learned = true,
			color = "yellow",
		},
		{
			spellID = 3764,
			itemID = 4247,
			name = "Hillman's Leather Gloves",
			count = 5,
			fromRank = 145,
			toRank = 150,
			learned = false,
			color = "orange",
			trainAt = 145,
			cost = 1800,
		},
	},
	reagents = {
		{ itemID = 2321, need = 26, have = 0, source = "vendor" },
		{ itemID = 2319, need = 82, have = 40, source = "gather" },
		{ itemID = 4233, need = 6, have = 0 },
	},
}

local TAILORING = {
	name = "Tailoring",
	skillLineID = 197,
	icon = 136249,
	rank = 60,
	maxRank = 75,
	steps = {},
	recipes = {},
	reagents = {},
}

return {
	LEATHERWORKING = LEATHERWORKING,
	TAILORING = TAILORING,
	ITEMS = {
		[2321] = { name = "Fine Thread", icon = 132912 },
		[2319] = { name = "Medium Leather", icon = 134254 },
		[4233] = { name = "Cured Medium Hide", icon = 134354 },
		[4253] = { name = "Toughened Leather Gloves", icon = 132958 },
		[4247] = { name = "Hillman's Leather Gloves", icon = 132939 },
	},
}
