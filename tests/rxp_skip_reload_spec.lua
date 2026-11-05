-- Adventure Guide Forever (#374): a RestedXP step skipped ahead stays skipped after a /reload.
--
-- RestedXP keeps some current steps out of its window, so the step Adventure Guide leads with can be one RestedXP has
-- not reached (its own progress is the hidden step). Skipping that step only sets `step.completed`, which RestedXP
-- never saves, so the guide came back to the same step after a reload. Adventure Guide now keeps the skip on the
-- character and marks the step again whenever RestedXP rebuilds the guide.
local harness = dofile("tests/harness.lua")

local h = harness.load({ db = { restedxpGuide = true, restedxpChoiceMade = true, autoStart = false } })
local ns, G = h.ns, h.G

local guideFrame = G.CreateFrame("Frame", nil, G.UIParent)
local current = G.CreateFrame("Frame", nil, guideFrame)
current.UpdateText = function() end
guideFrame.CurrentStepFrame = current

local progress = 1

-- The guide RestedXP builds: step 1 is under way but hidden from its window, steps 2 to 4 are ahead.
local function Guide()
	local steps = {}
	for index = 1, 4 do
		steps[index] = {
			index = index,
			active = index == 1 or nil,
			hidewindow = index == 1 or nil,
			title = "Step " .. index,
			elements = { { text = "Do the thing on step " .. index } },
		}
	end
	return { name = "Example", group = "Example", steps = steps }
end

local guide = Guide()
guideFrame.activeSteps = { guide.steps[1] }
G.RXPCData = { stepSkip = {}, currentStep = 1 }
G.RXP = {
	RXPFrame = guideFrame,
	currentGuide = guide,
	GetGuideProgress = function()
		return progress
	end,
	SetStep = function(index)
		progress = index
	end,
	UpdateMap = function() end,
	settings = { profile = { showEnabled = true }, OpenSettings = function() end },
	guideList = {},
	GetGuideTable = function()
		return guide
	end,
	IsGuideActive = function()
		return true
	end,
	LoadGuideTable = function() end,
}

h.fire("ADDON_LOADED", "RXPGuides")
h.fire("PLAYER_ENTERING_WORLD")
h.flush()
ns.RestedXP.Refresh()
h.flush()
assert(ns.RestedXP.Active(), "the guide is steered by Adventure Guide")

-- RestedXP's own step is the hidden step 1: Adventure Guide leads with step 2, as its own window would show it.
local journey = ns.RestedXP.Journey()
assert(journey and journey.steps[1].rxpIndex == 2, "the guide leads with the step RestedXP shows next")
assert(ns.RestedXP.Snapshot().steps[2].preview, "step 2 is a preview until RestedXP reaches it")
assert(ns.RestedXP.SkipKey(journey.steps[1].key), "Skip for now takes the step the guide leads with")
h.flush()
assert(guide.steps[2].completed, "the skipped step is passed over in this session")
assert(progress == 1, "RestedXP's own progress is untouched: it has not reached step 2")
assert(G.RXPCData.currentStep == 1 and not G.RXPCData.stepSkip[2], "nothing is written into RestedXP's saved data")
assert(ns.RestedXP.Journey().steps[1].rxpIndex == 3, "the guide moves on to step 3")

-- /reload: RestedXP rebuilds the guide from its guide text and starts from its own saved step again.
guide = Guide()
G.RXP.currentGuide = guide
guideFrame.activeSteps = { guide.steps[1] }
ns.RestedXP.Refresh()
h.flush()
assert(guide.steps[2].completed, "the skipped step is passed over again after a reload")
assert(ns.RestedXP.Journey().steps[1].rxpIndex == 3, "the guide does not go back to the step that was skipped")

-- A reload that lands RestedXP on the skipped step itself hands it on, as RestedXP's own skip does.
guide = Guide()
guide.steps[2].active = true
guide.steps[2].hidewindow = nil
progress = 2
G.RXP.currentGuide = guide
guideFrame.activeSteps = { guide.steps[1], guide.steps[2] }
ns.RestedXP.Refresh()
h.flush()
assert(progress == 3, "RestedXP is handed past the step the player skipped")
assert(not G.RXPCData.stepSkip[3], "and past it the way it passes a step of its own")

-- Once RestedXP's own progress is past a skipped step the record is dropped, so a later replay shows it again.
progress = 4
guideFrame.activeSteps = { guide.steps[4] }
ns.RestedXP.Refresh()
h.flush()
assert(not ns.Prefs().guideSkips["guide:7:Example:7:Example"], "a passed step is forgotten")

-- Another guide's steps are not affected by this guide's skips.
progress = 1
guide = { name = "Other", group = "Example", steps = Guide().steps }
G.RXP.currentGuide = guide
guideFrame.activeSteps = { guide.steps[1] }
ns.RestedXP.Refresh()
h.flush()
assert(not guide.steps[2].completed, "skips belong to the guide they were made in")

assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("rxp_skip_reload_spec: a RestedXP step skipped ahead stays skipped after a /reload")
