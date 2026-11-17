-- luacheck: read globals scenario ADDON
-- With the gamepad interface on, the settings page is the client's own vertical rows under its headings, so the
-- Options navigation can enter it (cjber/tweaks-forever#382).
local core = dofile("tests/sim/forever_core.lua")

scenario("the settings page can be entered with a gamepad", { addons = core }, function(sim)
	local G = sim.G
	-- The client opens the panel itself: a C function that calls SettingsPanel:OpenToCategory.
	sim.impl["C_SettingsUtil.OpenSettingsPanel"] = function(categoryID, scrollTo)
		G.SettingsPanel:OpenToCategory(categoryID, scrollTo)
	end
	sim:setGamepad(true)
	sim:login()
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "the addon namespace loaded")
	local category
	for _, c in ipairs(G.SettingsPanel:GetAllCategories()) do
		if c:GetName() == ns.TITLE then
			category = c
		end
	end
	assert(category, ns.TITLE .. " is under Options > AddOns")
	assert(#category:GetSubcategories() == 0, "one page, no subpages")
	assert(
		G.SettingsPanel:GetLayout(category):IsVerticalLayout(),
		"the page is a vertical list, which the gamepad cursor can enter (cjber/tweaks-forever#382)"
	)
	sim:input(function()
		G.Settings.OpenToCategory(category:GetID())
	end)
	sim:advance(0.1)
	local first = G.SettingsPanel:GetFirstSmartNavFocusableSettingFrame()
	assert(first, "the gamepad cursor has a row to land on")
	assert(first:IsVisible(), "the first row the cursor lands on is visible")
	sim:expectNoErrors(ADDON)
end)
