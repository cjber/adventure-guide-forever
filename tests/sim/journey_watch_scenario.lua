-- luacheck: read globals scenario ADDON
-- #682: the tracker lists only the leading journey's quests, a small grey count says how many of the player's own are
-- hidden, and the count, the tooltip, the right-click menu and combat all drive the real tracker section. The old
-- "Stop tracking other quests" save carries over to the new setting.
local core = dofile("tests/sim/forever_core.lua")

scenario(
	"a leading journey hides other tracked quests under the tracker header's count",
	{ addons = core },
	function(sim)
		local watches = { 900010, 900011 }
		local function Watched(questID)
			for _, id in ipairs(watches) do
				if id == questID then
					return true
				end
			end
			return false
		end
		sim.impl["C_QuestLog.GetNumQuestWatches"] = function()
			return #watches
		end
		sim.impl["C_QuestLog.GetQuestIDForQuestWatchIndex"] = function(index)
			return watches[index]
		end
		sim.impl["C_QuestLog.GetQuestWatchType"] = function(questID)
			return Watched(questID) and 1 or nil
		end
		sim.impl["C_QuestLog.AddQuestWatch"] = function(questID)
			if not Watched(questID) then
				watches[#watches + 1] = questID
			end
			return true
		end
		sim.impl["C_QuestLog.RemoveQuestWatch"] = function(questID)
			for index, id in ipairs(watches) do
				if id == questID then
					table.remove(watches, index)
					return true
				end
			end
			return false
		end
		sim:login({
			savedVariables = {
				AdventureGuideForeverDB = { untrackOthers = true, autoStart = false },
				AdventureGuideForeverCharDB = { journey = "zone:1413" },
			},
		})
		local ns
		for _, entry in ipairs(sim.loader.addons) do
			if entry.name == ADDON then
				ns = entry.ns
			end
		end
		assert(ns, "the addon namespace loaded")
		sim:advance(0.3)
		-- The old key carries into the new setting and is gone.
		assert(ns.Setting("journeyWatch") == true, "a saved untrackOthers true turns journey watching on")
		assert(ns.Setting("untrackOthers") == nil, "the old setting is removed")
		-- This scenario's route is injected below rather than planned from the client's log, so start its watch state
		-- from the same watches a login would see.
		watches = { 900010, 900011 }

		-- A chosen journey whose steps work on two quests in the log, with a real route card for the tracker heading.
		local log = {
			[900001] = { id = 900001, title = "First journey quest", level = 12, complete = false, objectives = {} },
			[900002] = { id = 900002, title = "Second journey quest", level = 12, complete = false, objectives = {} },
			[900010] = { id = 900010, title = "Player's first quest", level = 12, complete = false, objectives = {} },
			[900011] = { id = 900011, title = "Player's second quest", level = 12, complete = false, objectives = {} },
		}
		local step = {
			kind = "area",
			key = "area:900001:0",
			title = "Journey quest",
			quests = { 900001, 900002 },
			objectives = {},
			checklist = {},
			map = 1413,
			x = 0.5,
			y = 0.5,
			zone = "Northern Barrens",
		}
		local route = {
			chosen = true,
			journey = "zone:1413",
			journeys = { { key = "zone:1413", title = "The Barrens story" } },
			steps = { step },
		}
		sim:runAs(
			ADDON,
			[[
		local ns, log, route = ...
		ns.State.Log = function()
			return log
		end
		ns.State.Ready = function()
			return true
		end
		ns.State.Completed = function()
			return {}
		end
		ns.Snapshot = function()
			return { log = log }
		end
		ns.QuestieBuilding = function()
			return false
		end
		ns.Route = function()
			return route
		end
		ns.Prefs().journey = "zone:1413"
		ns.Prefs().guideWatch = nil
		ns.QuestWatch.Sync()
	]],
			ns,
			log,
			route
		)
		sim:advance(0.2)
		assert(
			ns.QuestWatch.Source() == "journey",
			"the chosen journey leads, hidden " .. tostring(ns.QuestWatch.Hidden())
		)
		assert(Watched(900001) and Watched(900002), "the journey's quests are tracked")
		assert(not Watched(900010) and not Watched(900011), "the player's other tracked quests leave the tracker")
		local module = assert(ns.TrackerModule(), "the real tracker section is there")
		assert(
			module.Header.Text:GetText() == "The Barrens story",
			"the header names the journey, got "
				.. tostring(module.Header.Text:GetText())
				.. " ("
				.. tostring(module.headerText)
				.. ")"
		)
		assert(module.hiddenText and module.hiddenText:IsShown(), "a grey count sits beside the header")
		assert(module.hiddenText:GetText() == ns.L.TRACKER_HIDDEN_COUNT:format(2), "and says how many are hidden")

		-- Hovering the header explains the count; leaving hides the tooltip.
		sim:hover(module.Header)
		assert(sim.G.GameTooltip:IsShown(), "the header tooltip shows")
		sim:leave()
		assert(not sim.G.GameTooltip:IsShown(), "and goes on leave")

		-- The player tracks one of their own quests by hand: it stays, and the count follows.
		watches[#watches + 1] = 900010
		sim:event("QUEST_WATCH_LIST_CHANGED", 900010, true)
		sim:advance(0.1)
		assert(Watched(900010), "a manual watch stays")
		assert(module.hiddenText:GetText() == ns.L.TRACKER_HIDDEN_COUNT:format(1), "the count drops")

		-- A quest the client tracked on accept, which the journey does not name, is the addon's and goes.
		watches[#watches + 1] = 900012
		sim:event("QUEST_ACCEPTED", 900012)
		sim:advance(0.1)
		assert(not Watched(900012), "the accepted quest is untracked")

		-- The gamepad interface walks the column without taint or an error.
		sim:setGamepad(true)
		sim:gamepadNavigate()
		sim:setGamepad(false)

		-- In combat the setting change waits: the player's quest does not come back until combat ends.
		sim:enterCombat()
		sim:runAs(ADDON, "local ns = ...; ns.SetSetting('journeyWatch', false)", ns)
		sim:advance(0.1)
		assert(not Watched(900011), "nothing changes in combat")
		sim:leaveCombat()
		sim:advance(0.2)
		assert(Watched(900011), "the player's hidden quest comes back after combat")
		assert(not Watched(900001), "and the journey's quest leaves")
		assert(not module.hiddenText:IsShown(), "the count goes with it")
		sim:expectNoErrors(ADDON)
		sim:expectNoGamepadTaint(ADDON)
	end
)
