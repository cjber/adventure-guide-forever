-- Screenshot-only runtime adapter fixture, never shipped. Names, ranks, objectives and drop/reward
-- relations: CMaNGOS classic-db 22b51464; icons: wago.tools 1.60.1.69913. Instance spawn coordinates are
-- synthetic and used only for membership; no Questie data is copied or bundled.
return {
	npcs = {
		[3653] = { name = "Kresh", rank = 1, minLevel = 20, maxLevel = 20, spawns = { [100043] = { { 50, 50 } } } },
		[3670] = {
			name = "Lord Pythas",
			rank = 1,
			minLevel = 21,
			maxLevel = 21,
			spawns = { [100043] = { { 50, 50 } } },
		},
		[3671] = {
			name = "Lady Anacondra",
			rank = 1,
			minLevel = 20,
			maxLevel = 20,
			spawns = { [100043] = { { 50, 50 } } },
		},
		[3673] = {
			name = "Lord Serpentis",
			rank = 1,
			minLevel = 21,
			maxLevel = 21,
			spawns = { [100043] = { { 50, 50 } } },
		},
		[3674] = { name = "Skum", rank = 1, minLevel = 21, maxLevel = 21, spawns = { [100043] = { { 50, 50 } } } },
	},
	items = {
		[918] = { name = "Deviate Hide Pack", npcDrops = {}, questRewards = { 1486 } },
		[5970] = { name = "Serpent Gloves", npcDrops = { 3673 }, questRewards = {} },
		[6448] = { name = "Tail Spike", npcDrops = { 3674 }, questRewards = {} },
		[6449] = { name = "Glowing Lizardscale Cloak", npcDrops = { 3674 }, questRewards = {} },
		[6459] = { name = "Savage Trodders", npcDrops = { 3673 }, questRewards = {} },
		[6469] = { name = "Venomstrike", npcDrops = { 3673 }, questRewards = {} },
		[6472] = { name = "Stinging Viper", npcDrops = { 3670 }, questRewards = {} },
		[6473] = { name = "Armor of the Fang", npcDrops = { 3670 }, questRewards = {} },
		[6480] = { name = "Slick Deviate Leggings", npcDrops = {}, questRewards = { 1486 } },
		[10411] = { name = "Footpads of the Fang", npcDrops = { 3673 }, questRewards = {} },
		[10412] = { name = "Belt of the Fang", npcDrops = { 3671 }, questRewards = {} },
		[13245] = { name = "Kresh's Back", npcDrops = { 3653 }, questRewards = {} },
	},
	client = {
		[918] = { name = "Deviate Hide Pack", quality = 3, icon = 133629, itemType = "Container", itemSubType = "Bag" },
		[5970] = { name = "Serpent Gloves", quality = 3, icon = 132953, itemType = "Armor", itemSubType = "Cloth" },
		[6448] = { name = "Tail Spike", quality = 3, icon = 135646, itemType = "Weapon", itemSubType = "Daggers" },
		[6449] = {
			name = "Glowing Lizardscale Cloak",
			quality = 3,
			icon = 132656,
			itemType = "Armor",
			itemSubType = "Cloth",
		},
		[6459] = { name = "Savage Trodders", quality = 3, icon = 132535, itemType = "Armor", itemSubType = "Mail" },
		[6469] = { name = "Venomstrike", quality = 3, icon = 135498, itemType = "Weapon", itemSubType = "Bows" },
		[6472] = {
			name = "Stinging Viper",
			quality = 3,
			icon = 135472,
			itemType = "Weapon",
			itemSubType = "One-Handed Maces",
		},
		[6473] = { name = "Armor of the Fang", quality = 3, icon = 135020, itemType = "Armor", itemSubType = "Leather" },
		[6480] = {
			name = "Slick Deviate Leggings",
			quality = 3,
			icon = 134582,
			itemType = "Armor",
			itemSubType = "Leather",
		},
		[10411] = {
			name = "Footpads of the Fang",
			quality = 3,
			icon = 132538,
			itemType = "Armor",
			itemSubType = "Leather",
		},
		[10412] = { name = "Belt of the Fang", quality = 3, icon = 132519, itemType = "Armor", itemSubType = "Leather" },
		[13245] = { name = "Kresh's Back", quality = 3, icon = 134964, itemType = "Armor", itemSubType = "Shields" },
	},
	-- Forever spell ids these bosses cast (Data/Abilities.lua), with the client's own name and icon (SpellName and
	-- SpellMisc at 1.60.1.70205). Screenshot-only: the game reads the same fields at runtime.
	abilities = {
		[700] = { name = "Sleep", icon = 136090 },
		[5187] = { name = "Healing Touch", icon = 136041 },
		[6254] = { name = "Chained Bolt", icon = 136015 },
		[6778] = { name = "Healing Touch", icon = 136041 },
		[8147] = { name = "Thunderclap", icon = 136105 },
		[9532] = { name = "Lightning Bolt", icon = 136048 },
	},
	objectives = {
		[1486] = "Nalpak in the Wailing Caverns wants 20 Deviate Hides.",
		[1487] = "Ebru in the Wailing Caverns wants you to kill 7 Deviate Ravagers, 7 Deviate Vipers, "
			.. "7 Deviate Shamblers and 7 Deviate Dreadfangs.",
		[914] = "Bring the Gems of Cobrahn, Anacondra, Pythas and Serpentis to Nara Wildmane in Thunder Bluff.",
	},
}
