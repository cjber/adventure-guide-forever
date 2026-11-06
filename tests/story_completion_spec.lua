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
-- The toast's Shield child calls AchievementShield_OnLoad, so the load-on-demand achievement UI comes first (#429).
equal(h.alertSystemUILoads, 1, "achievement UI loaded before the toast subsystem is queued")
equal(h.achievementUILoads, 1, "the achievement UI is loaded once")
equal(h.ns.StoryCompletion.Record(finals[2]), true, "second completion queued")
equal(#h.errors, 0, "queued presentation has no errors")
-- The client's achievement toast, filled with the story: the heading and title, no achievement behind it, no shield.
local firstTitle = h.ns.Prefs().completedStories[key].title
local toast = h.alerts[1]
equal(toast and toast.template, "AchievementAlertFrameTemplate", "first story shows the native achievement toast")
equal(toast.Unlocked:GetText(), "Story complete", "toast heading")
equal(toast.Name:GetText(), firstTitle, "toast names its story")
equal(toast.id, nil, "toast carries no achievement ID")
equal(toast.Shield:IsShown(), false, "toast hides the points shield")
equal(toast.Icon.Texture.file, "Interface\\Icons\\Achievement_Quests_Completed_08", "toast icon")
equal(#h.alerts, 2, "two stories show together, as achievements do")
equal(
	h.alerts[2].Name:GetText(),
	h.ns.Prefs().completedStories["story:" .. h.ns.Model.Story(h.ns.Data, finals[2]).members[1]].title,
	"second toast names its story"
)
equal(#h.sounds, 2, "each toast plays the story sound once")
-- A third waits for a toast to go, then reuses its frame and sounds as it shows.
local third = finals[3]
equal(h.ns.StoryCompletion.Record(third), true, "third completion queued")
equal(#h.alerts, 2, "third waits while two show")
toast:Hide()
equal(#h.alerts, 3, "third shows when a toast goes")
equal(h.alerts[3], toast, "toast frame reused from the pool")
equal(#h.sounds, 3, "third sounds as it shows")
local again = Load({ charDB = h.G.AdventureGuideForeverCharDB })
equal(again.ns.StoryCompletion.Record(last), false, "reload suppresses historical milestone")
equal(#again.errors, 0, "reload has no errors")
print("story_completion_spec: " .. checks .. " checks passed")
