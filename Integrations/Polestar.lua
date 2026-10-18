---@type string, AGFNamespace
local _, ns = ...

-- Stepping aside for Polestar (docs/design.md, "Alongside Polestar"): while Polestar, a separate leveling guide, has a
-- guide running, Adventure Guide stops pushing its own route. Nothing starts or restores it, the route it was running
-- stops, the map marks go, and the tracker shows one line that takes over again. The reads are
-- `Polestar.Engine.GetGuide()` and `GetStepIndex()`, each checked before it is called, again on Polestar's
-- GUIDE_CHANGED and GUIDE_COMPLETED messages, or on a slow timer when Polestar has no message bus. Nothing of
-- Polestar's is written or hooked.
---@class AGFPolestarModule
local Aside = {}
ns.Polestar = Aside

local POLL = 5
-- The guide Polestar runs now: its id, true for one without an id, nil for none (or no Polestar).
---@type string|true|nil
local current
local stepping = false

-- The guide Polestar is running: none when it has no guide loaded, or the loaded one is finished (no step left).
---@return string|true|nil
local function Running()
	local addon = Polestar
	local engine = type(addon) == "table" and addon.Engine
	if type(engine) ~= "table" or type(engine.GetGuide) ~= "function" then
		return nil
	end
	local ok, guide = pcall(engine.GetGuide)
	if not ok or type(guide) ~= "table" then
		return nil
	end
	if type(engine.GetStepIndex) == "function" then
		local read, step = pcall(engine.GetStepIndex)
		if read and step == nil then
			return nil
		end
	end
	return type(guide.id) == "string" and guide.id or true
end

-- One of Polestar's settings, read through its own `Polestar.Get(path)`: nil without Polestar, without that reader, or
-- when the read fails. A feature Polestar does too asks this before doing it twice (Closes.lua).
---@param path string
---@return any
function Aside.Setting(path)
	local addon = Polestar
	if type(addon) ~= "table" or type(addon.Get) ~= "function" then
		return nil
	end
	local ok, value = pcall(addon.Get, path)
	return ok and value or nil
end

-- True while Adventure Guide stands aside: the setting is on, Polestar runs a guide, and it is not the one this
-- character took over from (kept across reloads, so Polestar reopening its saved guide does not undo it).
---@return boolean
function Aside.Active()
	return current ~= nil and current ~= ns.Prefs().polestarTakenFrom and ns.Setting("polestarAside") == true
end

-- Reads Polestar again. Stepping aside stops only what Go started (Guidance.StepAside); the views redraw either way.
function Aside.Check()
	current = Running()
	if current == nil then
		ns.Prefs().polestarTakenFrom = nil
	end
	local active = Aside.Active()
	if active == stepping then
		return
	end
	stepping = active
	if active then
		ns.Guidance.StepAside()
	end
	ns.Invalidate()
end

-- The player takes over: Adventure Guide leads again until Polestar runs a different guide.
function Aside.TakeOver()
	current = Running()
	if Aside.Active() then
		ns.Prefs().polestarTakenFrom = current
	end
	Aside.Check()
end

EventUtil.ContinueAfterAllEvents(function()
	local addon = Polestar
	if type(addon) ~= "table" then
		return
	end
	local function Later()
		C_Timer.After(0, Aside.Check)
	end
	local subscribed = type(addon.On) == "function"
		and pcall(addon.On, "GUIDE_CHANGED", Later)
		and pcall(addon.On, "GUIDE_COMPLETED", Later)
	if not subscribed then
		C_Timer.NewTicker(POLL, Aside.Check)
	end
	Later()
end, "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD")
