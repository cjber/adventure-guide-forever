-- Initialization must tolerate either native event order and an addon loaded after login. The section is created with
-- the files through ForeverCore's TrackerSection and attaches to its column only after the addon's saved variables
-- load.
local ForeverCore = dofile("tests/forever_core.lua")
local checks = 0
local function noop() end
for _, readyAtLoad in ipairs({ false, true }) do
	local callbacks, timers, modules, owners = {}, {}, {}, {}
	local native = {}
	local function region()
		return {
			Hide = noop,
			SetHeader = function(self, text)
				self.headerText = text
			end,
			RegisterEvent = noop,
			SetScript = noop,
		}
	end
	local env = setmetatable({
		ObjectiveTrackerFrame = {},
		ObjectiveTrackerManager = setmetatable({}, {
			__index = function()
				error("must not register with native manager")
			end,
		}),
		CreateFrame = function(_, name)
			local frame = region()
			if name then
				modules[#modules + 1] = frame
			end
			return frame
		end,
		Mixin = function(target, source)
			for key, value in pairs(source) do
				target[key] = value
			end
		end,
		EventUtil = {
			ContinueAfterAllEvents = function(fn, first, second)
				assert(first == "PLAYER_ENTERING_WORLD" and second == "VARIABLES_LOADED")
				if readyAtLoad then
					fn()
				else
					callbacks[#callbacks + 1] = fn
				end
			end,
		},
		C_Timer = {
			After = function(delay, fn)
				if delay == 0 then
					timers[#timers + 1] = fn
				end
			end,
		},
		hooksecurefunc = function()
			error("native methods must stay unhooked")
		end,
	}, { __index = _G })
	local ns = {
		core = {
			SafeCall = function(_, fn, ...)
				return true, fn(...)
			end,
		},
		L = setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		}),
		Menu = { Step = noop },
		Integrations = { OnTravelChange = noop },
		Guidance = { OnChange = noop },
		Asides = { OnChange = noop },
		Moments = { OnChange = noop },
		OnRouteChange = noop,
	}
	env.ForeverCore = {
		TrackerHost = {
			Attach = function(module, show)
				module.show = show
				owners[module] = native
			end,
			IsAttached = function(module)
				return owners[module] == native
			end,
		},
	}
	-- The real section API, as ForeverCore loads it: the spec asserts the addon through the calls core publishes.
	local core = { TrackerHost = env.ForeverCore.TrackerHost, SafeCall = ns.core.SafeCall }
	local chunk = assert(loadfile(ForeverCore.directory() .. "/UI/TrackerSection.lua"))
	setfenv(chunk, env)
	chunk("ForeverCore", core)
	env.ForeverCore.TrackerSection = core.TrackerSection
	env.ForeverCore.TrackerLine = core.TrackerLine
	local saved = { trackerHost = { scale = 0.8 } }
	local old = saved.trackerHost
	env.AdventureGuideForeverDB = saved
	setfenv(assert(loadfile("UI/Tracker.lua")), env)("Addon", ns)
	assert(modules[1] ~= nil, "the section is made with the files")
	assert(owners[modules[1]] == nil, "and waits for the saved variables before attaching")
	assert(modules[1].uiOrder == -4, "at the addon's place in the column")
	assert(modules[1].lineTemplate == "ObjectiveTrackerAnimLineTemplate", "with the fanfare block's own line")
	assert(modules[1].headerText == "TITLE", "under the addon's header")
	for _, fn in ipairs(callbacks) do
		fn()
	end
	for _, fn in ipairs(timers) do
		fn()
	end
	assert(owners[modules[1]] == native, "then attaches to ForeverCore's column")
	assert(modules[1].safeCall == ns.core.SafeCall, "and carries the addon's SafeCall")
	assert(modules[1].legacySettings == old, "and offers the old tracker table once")
	assert(saved.trackerHost == nil, "which is then cleared")
	assert(modules[1].show.where == "TRACKER_SHOW_WHERE", "the header menu offers the addon's show switch")
	checks = checks + 1
end
print("tracker_lifecycle_spec: " .. checks .. " load-order cases passed")
