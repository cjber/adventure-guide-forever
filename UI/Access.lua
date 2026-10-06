-- Retire only keys assigned to the removed window action.
local bindingCleanup = CreateFrame("Frame")
local function ClearWindowBinding()
	if InCombatLockdown() then
		bindingCleanup:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	bindingCleanup:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local changed = false
	for _, key in ipairs({ GetBindingKey("ADVENTUREGUIDEFOREVER_WINDOW") }) do
		changed = SetBinding(key) or changed
	end
	if changed then
		SaveBindings(GetCurrentBindingSet())
	end
end
bindingCleanup:SetScript("OnEvent", ClearWindowBinding)
EventUtil.ContinueAfterAllEvents(ClearWindowBinding, "VARIABLES_LOADED", "PLAYER_LOGIN")
