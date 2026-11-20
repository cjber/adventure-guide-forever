-- Run from the repository root: luajit tests/startup_spec.lua
-- The settings page goes in right after the saved tables load, so an error in a later startup step (an integration,
-- the state listeners) still leaves /agf's settings working.
local harness = dofile("tests/harness.lua")
local ADDON = "AdventureGuideForever"

-- The model load brings in ForeverCore's shared files and the route data Core/Core.lua reads at file load.
local ns = {}
harness.model(ns)

local startup
local core = assert(loadfile("Core/Core.lua"))
setfenv(
	core,
	setmetatable({
		EventUtil = {
			ContinueOnAddOnLoaded = function(name, callback)
				if name == ADDON then
					startup = callback
				end
			end,
			ContinueAfterAllEvents = function() end,
		},
		SlashCmdList = {},
		CreateFrame = function()
			return { SetScript = function() end, RegisterEvent = function() end }
		end,
	}, { __index = _G })
)
core(ADDON, ns)
assert(type(startup) == "function", "Core/Core.lua starts at its own ADDON_LOADED")

local registered = false
ns.RegisterSettings = function()
	registered = true
end
ns.QuestieOptions = {
	Load = function()
		error("an integration failed at startup")
	end,
}
assert(not pcall(startup), "the startup error reaches the client")
assert(registered, "the settings page is registered before the failing step")
print("startup_spec: the settings page survives a later startup error")
