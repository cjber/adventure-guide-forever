-- Run from the repository root: luajit tests/require_spec.lua
-- Core/Require.lua stops the addon when the loaded ForeverCore lacks a member this addon calls. The warning itself is
-- Core/ForeverRequire.lua, the file every Forever addon ships, so core's own tests cover its wording and this checks
-- only that a missing member stops here and a complete core does not.
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %q, got %q"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function Load(core)
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.ForeverCore = core
	local messages = {}
	env.UIErrorsFrame = {
		AddMessage = function(_, text)
			messages[#messages + 1] = text
		end,
	}
	local addons = {
		{
			name = "AdventureGuideForever",
			title = "Adventure Guide Forever",
			core = "v1.5.0",
			deps = { "ForeverCore" },
		},
		{ name = "ForeverCore", title = "Forever Core", core = "v1.5.0", deps = {} },
	}
	local function Find(target)
		if type(target) == "number" then
			return addons[target]
		end
		for _, addon in ipairs(addons) do
			if addon.name == target then
				return addon
			end
		end
	end
	env.C_AddOns = {
		GetNumAddOns = function()
			return #addons
		end,
		GetAddOnInfo = function(index)
			local addon = addons[index]
			return addon and addon.name, addon and addon.title
		end,
		GetAddOnMetadata = function(target, field)
			local addon = Find(target)
			if field == "X-Forever-Icon" then
				return "Interface\\Icons\\INV_Misc_Map_01"
			end
			if not addon then
				return nil
			end
			return field == "Title" and addon.title or addon.core
		end,
		IsAddOnLoaded = function(index)
			return addons[index] ~= nil
		end,
		GetAddOnEnableState = function(index)
			return addons[index] and 2 or 0
		end,
		GetAddOnDependencies = function(index)
			local addon = addons[index]
			if addon then
				return unpack(addon.deps) -- multi-value: the client returns each dependency as its own value
			end
		end,
	}
	local ns = {}
	setfenv(assert(loadfile("Core/ForeverRequire.lua")), env)("AdventureGuideForever", ns)
	setfenv(assert(loadfile("Core/Require.lua")), env)("AdventureGuideForever", ns)
	return ns, messages
end

local function Complete()
	return {
		API = 1,
		APIKit = { Hub = function() end, NotReady = function() end },
		TrackerSection = { Create = function() end, Room = function() end },
		TrackerLine = { SetHeaderTooltip = function() end },
		Art = { Marker = function() end, Ring = function() end },
	}
end

-- A core with everything this addon calls starts it and shows nothing.
do
	local ns, messages = Load(Complete())
	equal(ns.broken, nil, "a complete core starts the addon")
	equal(#messages, 0, "a complete core shows nothing")
end

-- A core missing a post-API-1 member stops the addon and shows one line on the error frame.
do
	local core = Complete()
	core.TrackerLine = nil
	local ns, messages = Load(core)
	equal(ns.broken, true, "a missing tracker line stops the addon")
	equal(#messages, 1, "one line on the error frame")
	equal(
		messages[1],
		"Adventure Guide Forever could not start. Reinstall Adventure Guide Forever to fix this.",
		"the shared warning asks for a reinstall when no other addon is named"
	)
end

-- A core without the shared step markers stops it too: the route's numbers are core's art now.
do
	local core = Complete()
	core.Art = nil
	local ns, messages = Load(core)
	equal(ns.broken, true, "a missing step markers module stops the addon")
	equal(#messages, 1, "one line for the missing markers")
end

-- A core whose API kit lacks the hub this addon's API builds on stops it too.
do
	local core = Complete()
	core.APIKit = {}
	local ns, messages = Load(core)
	equal(ns.broken, true, "a missing API kit hub stops the addon")
	equal(#messages, 1, "one line for the missing kit member")
end

print(("require: %d checks passed"):format(checks))
