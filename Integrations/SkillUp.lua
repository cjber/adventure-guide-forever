---@type string, AGFNamespace
local _, ns = ...
local Integrations = ns.Integrations

-- SkillUp Forever's API (version 1), for the window's Professions tab: "ready" when every call the tab makes is
-- there, "outdated" when SkillUp is loaded without it (an older SkillUp, or a version 0), else "missing".
local SKILLUP_CALLS = { "Professions", "Navigate", "OpenRecipes" }

---@return AGFSUAPI? api
---@return AGFSkillUpState state
local function SkillUp()
	local addon = SkillUpForever
	local api = type(addon) == "table" and addon.API or nil
	if type(api) ~= "table" then
		local loaded = C_AddOns.IsAddOnLoaded("SkillUpForever")
		return nil, (addon ~= nil or loaded) and "outdated" or "missing"
	end
	if type(api.version) ~= "number" or api.version < 1 then
		return nil, "outdated"
	end
	for _, name in ipairs(SKILLUP_CALLS) do
		if type(api[name]) ~= "function" then
			return nil, "outdated"
		end
	end
	---@cast api AGFSUAPI
	return api, "ready"
end

---@return AGFSkillUpState
function Integrations.SkillUpState()
	return (select(2, SkillUp()))
end

-- SkillUp's cached table is read, never written: an entry missing what the tab draws is left out.
---@return AGFSUProfession[]
function Integrations.Professions()
	local api = SkillUp()
	local list = api and api.Professions()
	local professions = {}
	for _, profession in ipairs(type(list) == "table" and list or {}) do
		if
			type(profession) == "table"
			and type(profession.name) == "string"
			and type(profession.skillLineID) == "number"
			and type(profession.rank) == "number"
			and type(profession.maxRank) == "number"
			and type(profession.steps) == "table"
			and type(profession.recipes) == "table"
			and type(profession.reagents) == "table"
		then
			professions[#professions + 1] = profession
		end
	end
	return professions
end

---@param skillLineID integer
---@param stepIndex integer
---@return boolean
function Integrations.SkillUpNavigate(skillLineID, stepIndex)
	local api = SkillUp()
	return api ~= nil and api.Navigate(skillLineID, stepIndex) == true
end

---@param skillLineID integer
---@return boolean
function Integrations.OpenRecipes(skillLineID)
	local api = SkillUp()
	return api ~= nil and api.OpenRecipes(skillLineID) == true
end
