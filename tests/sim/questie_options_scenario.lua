-- luacheck: read globals scenario ADDON
-- Questie's options the guide sets through Questie's own option and functions (#363, #366), against forever_sim's
-- Questie stand-in: its tracker list is built after login only while Questie's trackerEnabled is on. The stand-in has
-- no first-run question and no loader, so each scenario adds Questie's own pieces the guide calls as Questie's
-- addon load finishes: db.global, QuestieLoader with QuestieOptionsUtils.ExecuteTheme (which sets questPOI as
-- Questie's does) and QuestieTracker.

-- Loads Integrations/QuestieOptions.lua with a namespace holding `settings`; returns the namespace and what Questie
-- was asked to do.
local function Setup(sim, settings, global)
	local calls = { themes = {}, updates = 0, printed = {} }
	local hook = sim.G.CreateFrame("Frame")
	hook:RegisterEvent("ADDON_LOADED")
	hook:SetScript("OnEvent", function(_, _, name)
		if name ~= "Questie" then
			return
		end
		local Questie = sim.G.Questie
		Questie.db.global = global
		local modules = {
			QuestieOptionsUtils = {
				ExecuteTheme = function(_, value)
					calls.themes[#calls.themes + 1] = value
					sim.G.SetCVar("questPOI", value == "blizzard" and "1" or "0")
				end,
			},
			QuestieTracker = {
				Update = function()
					calls.updates = calls.updates + 1
				end,
			},
		}
		sim.G.QuestieLoader = {
			ImportModule = function(_, module)
				return modules[module]
			end,
		}
	end)
	local ns = {
		L = { QUESTIE_TRACKER_RELOAD = "reload" },
		Setting = function(key)
			return settings[key]
		end,
		core = {
			SafeCall = function(_, fn, ...)
				return pcall(fn, ...)
			end,
		},
		Print = function(text)
			calls.printed[#calls.printed + 1] = text
		end,
	}
	assert(
		sim.templates.loadLua("Integrations/QuestieOptions.lua", ADDON .. "/Integrations/QuestieOptions.lua", ADDON, ns)
	)
	ns.QuestieOptions.Load()
	return ns, calls
end

scenario(
	"A new Questie install defaults to Blizzard objectives and leaves its tracker to ours",
	{ addon = false, stubs = { Questie = { delay = 2 } } },
	function(sim)
		local settings = { hideQuestieTracker = true, showTracker = true }
		local global = {}
		local ns, calls = Setup(sim, settings, global)
		sim.cvars.questPOI = "1"
		sim:login()
		assert(global.tutorialObjectiveTypeChosen == true, "Questie's first-run question is answered before it asks")
		assert(sim.G.Questie.db.profile.trackerEnabled == false, "Questie's tracker is off before it builds")
		sim:advance(4)
		assert(calls.themes[1] == "blizzard" and #calls.themes == 1, "Questie's own Blizzard theme, once")
		assert(sim.cvars.questPOI == "1", "the game's quest areas stay on")
		assert(sim.G.Questie_BaseFrame == nil, "Questie never builds its tracker list beside ours")
		-- Turning the setting off hands Questie its own choice back; a tracker that never started needs a /reload.
		settings.hideQuestieTracker = false
		ns.QuestieOptions.ApplyTracker()
		assert(sim.G.Questie.db.profile.trackerEnabled == true, "Questie's own choice is back")
		assert(calls.printed[1] == "reload", "the player is told to /reload")
		-- On again, then logging out: Questie saves its own choice, never ours.
		settings.hideQuestieTracker = true
		ns.QuestieOptions.ApplyTracker()
		assert(sim.G.Questie.db.profile.trackerEnabled == false, "off again while ours shows")
		sim.events.fire("PLAYER_LOGOUT")
		assert(sim.G.Questie.db.profile.trackerEnabled == true, "Questie's saved settings keep its own choice")
		sim:expectNoErrors(ADDON)
	end
)

scenario(
	"A Questie objective type the player chose is never changed",
	{ addon = false, stubs = { Questie = { delay = 2 } } },
	function(sim)
		local settings = { hideQuestieTracker = false, showTracker = true }
		local _, calls = Setup(sim, settings, { tutorialObjectiveTypeChosen = true })
		sim.cvars.questPOI = "0"
		sim:login()
		sim:advance(4)
		assert(#calls.themes == 0, "no theme over the player's choice")
		assert(sim.cvars.questPOI == "0", "the CVar is the player's")
		assert(sim.G.Questie.db.profile.trackerEnabled == true, "with the setting off Questie's tracker is untouched")
		assert(sim.G.Questie_BaseFrame ~= nil, "and Questie builds it")
		sim:expectNoErrors(ADDON)
	end
)
