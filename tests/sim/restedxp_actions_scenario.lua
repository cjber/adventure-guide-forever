-- luacheck: read globals scenario ADDON
-- Focused adapter test with real Blizzard frames and our own example RXP action controls.
-- Full-addon map-provider ownership is tracked separately in #304.
scenario("RestedXP action windows survive guide suppression", { addon = false, stubs = { Questie = {} } }, function(sim)
	sim:loadBlizzard("Blizzard_FrameXML/SecureTemplates.lua")
	sim:loadBlizzard("Blizzard_FrameXML/SecureTemplates.xml")
	local enabled = true
	local ns = {
		Setting = function(key)
			return key == "restedxpChoiceMade" or (key == "restedxpGuide" and enabled)
		end,
		Invalidate = function() end,
		Prefs = function()
			return {}
		end,
		Choose = function() end,
		Integrations = {
			Provider = function()
				return nil
			end,
		},
	}
	local guide = sim.G.CreateFrame("Frame", nil, sim.G.UIParent)
	local item = sim.G.CreateFrame("Button", nil, sim.G.UIParent, "SecureActionButtonTemplate")
	local target = sim.G.CreateFrame("Button", nil, sim.G.UIParent, "SecureActionButtonTemplate")
	for _, frame in ipairs({ guide, item, target }) do
		frame:SetSize(40, 40)
		frame:SetPoint("CENTER", sim.G.UIParent, "CENTER", 12, 18)
		frame:SetAlpha(0.8)
		frame:Show()
	end
	item:SetAttribute("type", "item")
	item:SetAttribute("item", "item:6948")
	target:SetAttribute("type", "macro")
	target:SetAttribute("macrotext", "/targetexact Example target")
	sim.G.RXP = {
		RXPFrame = guide,
		activeItemFrame = item,
		targeting = { activeTargetFrame = target },
		SetStep = function() end,
		UpdateMap = function() end,
		GetGuideProgress = function()
			return 1
		end,
		currentGuide = { name = "Example", group = "Example", steps = {} },
	}
	assert(sim.templates.loadLua("Integrations/RestedXP.lua", ADDON .. "/Integrations/RestedXP.lua", ADDON, ns))
	sim:login()
	sim:advance(0.1)
	local function check()
		assert(guide:GetAlpha() == 0, "guide stays suppressed")
		for _, frame in ipairs({ item, target }) do
			assert(frame:GetAlpha() == 0.8, "action control keeps opacity")
			local point, _, _, x, y = frame:GetPoint()
			assert(point == "CENTER" and x == 12 and y == 18, "action control keeps anchor")
		end
		assert(item:GetAttribute("item") == "item:6948", "item action remains owned by RXP")
		assert(target:GetAttribute("macrotext") == "/targetexact Example target", "target action remains owned by RXP")
	end
	check()
	sim:setGamepad(true)
	sim:enterCombat()
	ns.RestedXP.Refresh()
	sim:advance(0.1)
	check()
	sim:gamepadNavigate()
	sim:leaveCombat()
	sim:advance(0.1)
	check()
	item:Hide()
	target:Hide()
	ns.RestedXP.Refresh()
	sim:advance(0.1)
	assert(not item:IsShown() and not target:IsShown(), "RXP can hide its own controls")
	enabled = false
	ns.RestedXP.Refresh()
	sim:advance(0.1)
	assert(guide:GetAlpha() == 0.8, "turning integration off restores guide")
	sim:expectNoErrors(ADDON)
end)
