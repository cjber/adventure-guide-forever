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
		[918] = { name = "Deviate Hide Pack", icon = 133629 },
		[5970] = { name = "Serpent Gloves", icon = 132953 },
		[6448] = { name = "Tail Spike", icon = 135646 },
		[6449] = { name = "Glowing Lizardscale Cloak", icon = 132656 },
		[6459] = { name = "Savage Trodders", icon = 132535 },
		[6469] = { name = "Venomstrike", icon = 135498 },
		[6472] = { name = "Stinging Viper", icon = 135472 },
		[6473] = { name = "Armor of the Fang", icon = 135020 },
		[6480] = { name = "Slick Deviate Leggings", icon = 134582 },
		[10411] = { name = "Footpads of the Fang", icon = 132538 },
		[10412] = { name = "Belt of the Fang", icon = 132519 },
		[13245] = { name = "Kresh's Back", icon = 134964 },
	},
	objectives = {
		[1486] = "Nalpak in the Wailing Caverns wants 20 Deviate Hides.",
		[1487] = "Ebru in the Wailing Caverns wants you to kill 7 Deviate Ravagers, 7 Deviate Vipers, "
			.. "7 Deviate Shamblers and 7 Deviate Dreadfangs.",
		[914] = "Bring the Gems of Cobrahn, Anacondra, Pythas and Serpentis to Nara Wildmane in Thunder Bluff.",
	},
}
