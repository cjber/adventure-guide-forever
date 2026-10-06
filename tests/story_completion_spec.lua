local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(a, b, label)
	checks = checks + 1
	assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function Load(extra)
	local options = { db = { showTracker = false, autoStart = false } }
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	local h = harness.load(options)
	h.flush()
	return h
end
local h = Load()
local finals = {}
for id in pairs(h.ns.Data.quests) do
	local story = h.ns.Model.Story(h.ns.Data, id)
	if story and story.total and story.chapter == story.total then
		finals[#finals + 1] = id
	end
end
table.sort(finals)
local last = finals[1]
local story = h.ns.Model.Story(h.ns.Data, last)
equal(h.ns.StoryCompletion.Record(story.members[1]), false, "intermediate chapter is not complete")
h.fire("QUEST_TURNED_IN", last)
equal(
	h.ns.Prefs().completedStories["story:" .. story.members[1]].quest,
	last,
	"final hand-in event records with tracker hidden"
)
equal(h.ns.StoryCompletion.Record(last), false, "repeat hand-in suppressed")
local key = "story:" .. story.members[1]
equal(h.ns.Prefs().completedStories[key].quest, last, "stable head identity persists final quest")
equal(h.ns.StoryCompletion.Record(finals[2]), true, "second completion queued")
equal(#h.errors, 0, "queued presentation has no errors")
local Texts = dofile("tests/ui_helpers.lua").Texts
local firstTitle = h.ns.Prefs().completedStories[key].title
equal(Texts(h, h.G.UIParent)[firstTitle], 1, "first popup names its story")
local soundCount = #h.sounds
h.tick()
h.tick()
equal(#h.sounds, soundCount + 1, "second queued story gets one sound")
h.flush()
equal(#h.sounds, soundCount + 1, "queue drain does not replay sound")
local again = Load({ charDB = h.G.AdventureGuideForeverCharDB })
equal(again.ns.StoryCompletion.Record(last), false, "reload suppresses historical milestone")
equal(#again.errors, 0, "reload has no errors")
print("story_completion_spec: " .. checks .. " checks passed")
