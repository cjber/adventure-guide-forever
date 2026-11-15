-- Original example instructions, not redistributed RXP guide content.
-- RestedXP's v2 theme names the mark its guide window draws (#713); the screenshots resolve the exact file from the
-- installed addon (tools/screenshots_art.py), so the fixture carries the real path, never a copied logo.
local PROVIDER_LOGO = [[Interface\AddOns\RXPGuides\Textures\v2\rxp-icon-logo]]
local PROVIDER_LOGO_LEGACY = [[Interface\AddOns\RXPGuides\Textures\rxp_logo-64]]
return function(h, previewCount, fresh, catalogue, legacy)
	if not fresh then
		h.G.AdventureGuideForeverDB = h.G.AdventureGuideForeverDB or {}
		h.G.AdventureGuideForeverDB.restedxpChoiceMade = true
		h.ns.SetSetting("restedxpGuide", true)
	end
	local frame = h.G.CreateFrame("Frame", nil, h.G.UIParent)
	local index = 2
	local sticky = {
		index = 1,
		active = true,
		sticky = true,
		title = "Gather supplies",
		elements = { { text = "Supplies collected: 3/10" } },
	}
	local current = {
		index = 2,
		active = true,
		title = "Speak with the quartermaster",
		elements = {
			{ text = "Return to the crossroads and speak with the quartermaster about the next journey." },
			{ text = "Check your supplies before leaving town.", textOnly = true },
		},
	}
	local guide = { name = "Example: The Barrens", group = "Example guides", steps = { sticky, current } }
	for offset = 1, previewCount or 0 do
		local future = { index = offset + 2, active = false, title = "Continue the journey " .. offset, elements = {} }
		future.elements = {
			{
				text = "Follow the road to the next stop.",
				arrow = true,
				zone = 1413,
				x = 52 + offset,
				y = 31 + offset,
				step = future,
			},
		}
		guide.steps[#guide.steps + 1] = future
	end
	-- Another guide the catalogue offers but nobody follows, for the compact row's mark and its "new" badge.
	local offered = catalogue and { name = catalogue, group = guide.group, steps = {} } or nil
	local list = { Example = { names_ = { { group = guide.group, name = guide.name } } } }
	if offered then
		list.Example.names_[2] = { group = offered.group, name = offered.name }
	end
	frame.activeSteps = { sticky, current }
	local arrow = h.G.CreateFrame("Frame", nil, h.G.UIParent)
	arrow.element = { zone = 1413, x = 52.23, y = 31.01, arrow = true, step = current }
	local engine = {
		RXPFrame = frame,
		currentGuide = guide,
		arrowFrame = arrow,
		activeWaypoints = { true },
		GetGuideProgress = function()
			return index
		end,
		SetStep = function(value)
			index = value
		end,
		UpdateMap = function() end,
		UpdateGotoSteps = function() end,
		GetGuideTable = function(_, _, name)
			if offered and name == offered.name then
				return offered
			end
			return guide
		end,
		IsGuideActive = function()
			return true
		end,
		guideList = list,
		LoadGuideTable = function() end,
		settings = { profile = { showEnabled = true } },
	}
	if legacy then
		-- An older RestedXP with no v2 theme: its legacy guide window asks its theme for the 64-square logo it draws.
		engine.GetV1Texture = function(name)
			if name == "rxp_logo-64" then
				return PROVIDER_LOGO_LEGACY
			end
		end
	else
		-- RestedXP's own v2 theme: the logo its guide window draws, as the installed addon names it.
		engine.v2 = { activeTheme = { guideWindow = { logo = PROVIDER_LOGO } } }
	end
	h.G.RXP = engine
	h.fire("ADDON_LOADED", "RXPGuides")
	h.flush()
	return h.G.RXP
end
