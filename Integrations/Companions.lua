---@type string, AGFNamespace
local _, ns = ...

-- Where another Forever addon would fill a route step or a stop, one quiet line says so, through the shared rules in
-- UI/ForeverFamily.lua: a grey line (and a grey menu entry that shows its address) only while that addon isn't
-- installed, the Forever addons page's "Suggest my other Forever addons" is on and the player hasn't chosen "Don't
-- suggest this again". An addon that is installed but turned off gets its "Enable" line instead, while suggestions are
-- on: it explains a missing feature rather than suggesting an addon. Nothing once the addon runs.
---@class AGFCompanionsModule : AGFCompanions
local Companions = {}
ns.Companions = Companions

local L = ns.L

---@class AGFCompanionHint
---@field key string the hint's key for "Don't suggest this again", shared by every Forever addon so it starts with ours
---@field missing string the line while the addon isn't installed
---@field menu? string the menu entry that shows its address, while it isn't installed
---@field disabled? string the line while it is installed but turned off

---@type table<string, AGFCompanionHint>
local HINTS = {
	ShortestPathForever = {
		key = "AdventureGuideForever.step",
		missing = L.SPF_MISSING,
		menu = L.SPF_FAMILY_MENU,
		disabled = L.SPF_DISABLED,
	},
	SkillUpForever = {
		key = "AdventureGuideForever.professionTrainer",
		missing = L.SKILLUP_FAMILY,
		menu = L.SKILLUP_FAMILY_MENU,
	},
	TweaksForever = {
		key = "AdventureGuideForever.entrance",
		missing = L.TWEAKS_MISSING,
		disabled = L.TWEAKS_DISABLED,
	},
}

-- The shared module (UI/ForeverFamily.lua) looks its words up by their English phrase; ours are keyed by name, so this
-- maps each phrase (Locales/enUS.lua's FAMILY_ lines, as written) to our line, translated when a translation has it.
-- Built here, after every Locales file has loaded.
---@type table<string, string>
Companions.L = {}
for key, phrase in pairs(ns.FamilyPhrases) do
	Companions.L[phrase] = L[key]
end

-- The line for `addon` and whether it suggests installing it (grey), or nil while it runs, suggestions are off or
-- the player dismissed it.
---@param addon string a key of HINTS
---@return string? line
---@return boolean? suggestion
function Companions.Line(addon)
	local hint, db = HINTS[addon], ns.FamilyDB()
	if ns.Family.Hint(db, hint.key, addon) then
		return hint.missing, true
	elseif hint.disabled and db and db.suggestFamily ~= false and ns.Family.State(addon) == "off" then
		return hint.disabled, false
	end
end

-- The line at the foot of a tooltip: a suggestion in grey, an "Enable" line as an instruction.
---@param tooltip GameTooltip
---@param addon string a key of HINTS
function Companions.AddLine(tooltip, addon)
	local line, suggestion = Companions.Line(addon)
	if line and suggestion then
		GameTooltip_AddColoredLine(tooltip, line, GRAY_FONT_COLOR)
	elseif line then
		GameTooltip_AddInstructionLine(tooltip, line)
	end
end

-- The grey menu entry for `addon`, while its hint may show: it opens the window with the addon's address, which also
-- offers "Don't suggest this again".
---@param root AGFMenuDescription
---@param addon string a key of HINTS with a menu entry
function Companions.AddMenu(root, addon)
	local hint, db = HINTS[addon], ns.FamilyDB()
	if hint.menu and ns.Family.Hint(db, hint.key, addon) then
		root:CreateButton(GRAY_FONT_COLOR:WrapTextInColorCode(hint.menu), function()
			ns.Family.ShowLink(db, hint.key, addon, nil, Companions.L)
		end)
	end
end
