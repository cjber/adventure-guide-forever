---@type string, AGFNamespace
local _, ns = ...

-- The translations people make on the CurseForge project's Localization page. The packager replaces each
-- @localization line with that locale's L["KEY"] = "text" lines when it builds a release, leaving out any line
-- nobody has translated, so those stay in English. In a git checkout they stay comments, so every branch is empty
-- and L goes unused. The keyword syntax: https://github.com/BigWigsMods/packager/wiki/Localization-Substitution
-- luacheck: ignore 542 211/L
---@diagnostic disable-next-line: unused-local
local L, locale = ns.L, GetLocale()
if locale == "deDE" then
	--@localization(locale="deDE", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "esES" then
	--@localization(locale="esES", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "esMX" then
	--@localization(locale="esMX", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "frFR" then
	--@localization(locale="frFR", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "itIT" then
	--@localization(locale="itIT", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "koKR" then
	--@localization(locale="koKR", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "ptBR" then
	--@localization(locale="ptBR", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "ruRU" then
	--@localization(locale="ruRU", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "zhCN" then
	--@localization(locale="zhCN", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
elseif locale == "zhTW" then
	--@localization(locale="zhTW", format="lua_additive_table", handle-unlocalized="ignore", handle-subnamespaces="none")@
end
