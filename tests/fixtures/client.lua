-- Hand-written client facts for the test corpus (tests/fixtures/quests.lua), keyed by quest id. QuestieDB carries
-- only objective icon overrides, so the count a quest log would show, the timed flag and the elite tag come from
-- the client at runtime. The harness serves them (C_QuestLog.GetQuestTagInfo and the quest log's objectives), and
-- overlays the entries here on the corpus; a spec names only the quests it needs.
-- stylua: ignore
return {
	-- Deathknell: Night Web's Hollow's ten spiders and eight webs, Scavenging Deathknell's six corpses and
	-- Marla's Last Wish's one grave. tests/objective_area_spec.lua names these, so their objective counts decide
	-- where the route leads while they are under way.
	[380] = { need = { [0] = 10, [1] = 8 } },
	[6395] = { need = { [0] = 1 } },
	[3902] = { need = { [4] = 6 } },
}
