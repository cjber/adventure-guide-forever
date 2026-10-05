-- Screenshot-only runtime adapter fixture, never shipped. Names, objectives and reward relations:
-- CMaNGOS classic-db 22b51464; item icons: wago.tools 1.60.1.69913. No Questie data is copied or bundled.
return {
	items = {
		[918] = { name = "Deviate Hide Pack", questRewards = { 1486 } },
		[5970] = { name = "Serpent Gloves", questRewards = {} },
		[6448] = { name = "Tail Spike", questRewards = {} },
		[6449] = { name = "Glowing Lizardscale Cloak", questRewards = {} },
		[6459] = { name = "Savage Trodders", questRewards = {} },
		[6469] = { name = "Venomstrike", questRewards = {} },
		[6472] = { name = "Stinging Viper", questRewards = {} },
		[6473] = { name = "Armor of the Fang", questRewards = {} },
		[6480] = { name = "Slick Deviate Leggings", questRewards = { 1486 } },
		[10411] = { name = "Footpads of the Fang", questRewards = {} },
		[10412] = { name = "Belt of the Fang", questRewards = {} },
		[13245] = { name = "Kresh's Back", questRewards = {} },
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
	objectives = {
		[1486] = "Nalpak in the Wailing Caverns wants 20 Deviate Hides.",
		[1487] = "Ebru in the Wailing Caverns wants you to kill 7 Deviate Ravagers, 7 Deviate Vipers, "
			.. "7 Deviate Shamblers and 7 Deviate Dreadfangs.",
		[914] = "Bring the Gems of Cobrahn, Anacondra, Pythas and Serpentis to Nara Wildmane in Thunder Bluff.",
	},
}
