-- Adventure Guide Forever (#374): a RestedXP step completes from the quest events Adventure Guide already sees.
--
-- RestedXP completes a step element only from the callback bound to that element's frame in its guide window's step
-- list. Adventure Guide keeps that window hidden, so its frames are not a dependable carrier: this spec models the
-- reported state (the step's elements have no frame bound, so nothing hands them the client event) and checks that
-- the step still completes when the quest is turned in or accepted.
local harness = dofile("tests/harness.lua")

local h = harness.load({ db = { restedxpGuide = true, restedxpChoiceMade = true, autoStart = false } })
local ns, G = h.ns, h.G

local guideFrame = G.CreateFrame("Frame", nil, G.UIParent)
local current = G.CreateFrame("Frame", nil, guideFrame)
current.UpdateText = function() end
guideFrame.CurrentStepFrame = current

local turnedIn, accepted = {}, {}
local calls = {}
local step = {
	index = 1,
	active = true,
	title = "Hand in the example quest",
	elements = {
		{ tag = "turnin", questId = 7101, text = "Turn in The Example Quest" },
		{ tag = "accept", questId = 7102, text = "Accept The Other Quest" },
	},
}
local guide = { name = "Example", group = "Example", steps = { step } }
for _, element in ipairs(step.elements) do
	element.step = step
end
guideFrame.activeSteps = { step }
G.RXPCData = { stepSkip = {} }
-- RestedXP's own element layer, as functions.lua has it: which client events each tag reads, and callbacks that
-- complete the element from the quest state they read themselves.
local functions = {
	events = {
		turnin = { "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" },
		accept = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" },
	},
	turnin = function(self, event, questId)
		local element = self.element or self
		if turnedIn[element.questId] or (event == "QUEST_TURNED_IN" and questId == element.questId) then
			element.completed = true
			calls[#calls + 1] = "turnin"
		end
	end,
	accept = function(self)
		local element = self.element or self
		if accepted[element.questId] then
			element.completed = true
			calls[#calls + 1] = "accept"
		end
	end,
}
G.RXP = {
	RXPFrame = guideFrame,
	currentGuide = guide,
	GetGuideProgress = function()
		return 1
	end,
	SetStep = function() end,
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
	functions = functions,
	Call = function(_, callback, ...)
		return pcall(callback, ...)
	end,
}

h.fire("ADDON_LOADED", "RXPGuides")
h.fire("PLAYER_ENTERING_WORLD")
h.flush()
ns.RestedXP.Refresh()
h.flush()
assert(ns.RestedXP.Active(), "the guide is steered by Adventure Guide")
assert(guideFrame:GetAlpha() == 0, "RestedXP's window stays hidden from the player")

-- No frame carries the events: only Adventure Guide's own event frame sees them, as in the reported state.
assert(step.elements[1].frame == nil and not step.elements[1].completed, "the step starts open")
turnedIn[7101] = true
h.fire("QUEST_TURNED_IN", 7101, 120)
h.flush()
assert(step.elements[1].completed, "a turned-in quest completes the step's turn-in element")
assert(calls[1] == "turnin", "through RestedXP's own turn-in callback")

-- An accept completes from the quest the player took, and one they did not leaves the element open.
h.fire("QUEST_ACCEPTED", 7102)
h.flush()
assert(not step.elements[2].completed, "a quest the player has not taken leaves the accept element open")
accepted[7102] = true
h.fire("QUEST_ACCEPTED", 7102)
h.flush()
assert(step.elements[2].completed, "a taken quest completes the step's accept element")

-- With Adventure Guide no longer steering, RestedXP keeps its own window and its own event frames.
ns.SetSetting("restedxpGuide", false)
h.flush()
step.elements[1].completed = nil
step.elements[2].completed = nil
h.fire("QUEST_TURNED_IN", 7101, 120)
h.flush()
assert(not step.elements[1].completed, "no callback runs for a guide Adventure Guide no longer steers")
assert(guideFrame:GetAlpha() == 1, "RestedXP's window comes back")

assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("rxp_step_complete_spec: quest events complete RestedXP steps while Adventure Guide steers them")
