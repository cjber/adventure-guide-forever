---@type string, AGFNamespace
local _, ns = ...

-- Companion hints: where another Forever addon fills a tab or a route step, one quiet line says so while that addon
-- isn't loaded: "Install" when it isn't there, "Enable" when it is but is turned off, nothing once it runs. The
-- "Suggest companion addons" setting hides them all.
---@class AGFCompanionsModule : AGFCompanions
local Companions = {}
ns.Companions = Companions

local L = ns.L

---@type table<string, {missing: string, disabled: string}>
local HINTS = {
	ShortestPathForever = { missing = L.SPF_MISSING, disabled = L.SPF_DISABLED },
	SkillUpForever = { missing = L.SKILLUP_MISSING, disabled = L.SKILLUP_DISABLED },
	LegacyForever = { missing = L.LEGACY_MISSING, disabled = L.LEGACY_DISABLED },
}

---@param addon string the companion's folder name
---@return AGFCompanionState
function Companions.State(addon)
	if C_AddOns.IsAddOnLoaded(addon) then
		return "loaded"
	end
	return C_AddOns.DoesAddOnExist(addon) and "disabled" or "missing"
end

-- The hint for `addon`, or nil while it runs or the player turned hints off.
---@param addon string a key of HINTS
---@return string?
function Companions.Hint(addon)
	if not ns.Setting("suggestCompanions") then
		return nil
	end
	local state = Companions.State(addon)
	return state ~= "loaded" and HINTS[addon][state] or nil
end
