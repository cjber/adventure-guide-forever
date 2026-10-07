-- Original example instructions, not redistributed RXP guide content.
return function(h, previewCount, fresh)
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
	frame.activeSteps = { sticky, current }
	h.G.RXP = {
		RXPFrame = frame,
		currentGuide = guide,
		arrowFrame = { element = { zone = 1413, x = 52.23, y = 31.01, arrow = true, step = current } },
		activeWaypoints = { true },
		GetGuideProgress = function()
			return index
		end,
		SetStep = function(value)
			index = value
		end,
		UpdateMap = function() end,
		UpdateGotoSteps = function() end,
		GetGuideTable = function()
			return guide
		end,
		IsGuideActive = function()
			return true
		end,
		guideList = { Example = { names_ = { { group = guide.group, name = guide.name } } } },
		LoadGuideTable = function() end,
		settings = { profile = { showEnabled = true } },
	}
	h.fire("ADDON_LOADED", "RXPGuides")
	h.flush()
	return h.G.RXP
end
