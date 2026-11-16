-- #774 investigation: the cog belongs to the panel, independently of its journey and locale.
-- This verifies creation and access in the harness, not clipping or another addon's effects in the client.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end
for _, options in ipairs({
	{},
	{ charDB = { journey = "zone:1413" } },
	{
		charDB = { journey = "tracked" },
		setup = function(h)
			h.watched = { 845 }
		end,
	},
	{ locale = "frFR" },
}) do
	options.db = { autoStart = false }
	options.log = { { id = 845, title = "The Zhevra", level = 13, complete = true } }
	local h = harness.load(options)
	h.ns.OpenPanel()
	h.flush()
	local cog = h.Find(function(frame)
		return frame.name == "AdventureGuideForeverSettingsButton"
	end)[1]
	check(cog ~= nil, "cog created")
	check(cog:IsVisible(), "cog visible with panel")
	h.OpenMenu(cog)
	local sync, settings
	for _, entry in ipairs(h.menu.entries) do
		sync = sync or entry.text == h.ns.L.SYNC_WITH
		settings = settings or entry.text == h.ns.L.MENU_MORE_SETTINGS
	end
	check(sync, "sync menu accessible")
	check(settings, "AddOns settings fallback accessible")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end
print(("settings_access_spec: %d checks passed"):format(checks))
