-- Run from the repository root: luajit tests/tracker_story_beat_spec.lua
-- The tracker names the chosen story's chapter under the section heading (#394, #395): one muted line, before the
-- current step, that follows the chapter as it advances.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function Barrens(extra)
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	extra = extra or {}
	extra.charDB = extra.charDB or { journey = "zone:1413" }
	extra.completed = { 844 }
	extra.log = log
	return harness.load(extra)
end

-- The journey the route shows, by the same lookup the tracker uses.
local function Shown(ns)
	local route = ns.Route()
	for _, journey in ipairs(route.journeys) do
		if journey.key == route.journey then
			return journey
		end
	end
end

-- The line the tracker should draw for `story`: its chapter and the title of the quest that chapter is on.
local function Expected(ns, story)
	local id = story.members[story.chapter]
	local title = ns.Data.quests[id] and ns.Data.quests[id].title
	local chapter = story.total and ns.L.CHAPTER_OF:format(story.chapter, story.total)
		or ns.L.CHAPTER:format(story.chapter)
	return ns.L.CHAPTER_QUEST:format(chapter, title)
end

local function Beat(h)
	local block = h.tracker.liveBlocks["story-beat"]
	return block and block.used and block.header or nil
end

-- A story journey: one muted chapter line, directly under the section heading and before the current step.
do
	local h = Barrens({ spf = "v1", db = { autoStart = false } })
	local ns, journey = h.ns, Shown(h.ns)
	local story = journey.story
	check(story ~= nil and story.chapter == 1 and story.total == 8, "the fixture starts a proven story")
	local beat = Beat(h)
	check(beat ~= nil, "the tracker shows the story's chapter")
	check(beat:find("|cff7f7f7f", 1, true) ~= nil, "the chapter line is muted")
	check(beat:find(Expected(ns, story), 1, true) ~= nil, "it names the chapter and the chapter's quest")
	check(beat:find("Samophlange", 1, true) ~= nil, "the quest's title is there")
	check(h.tracker.layoutOrder[1] == "story-beat", "it follows the section heading")
	check(h.tracker.layoutOrder[2] == h.ns.Route().steps[1].key, "the current step follows it")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The carry journey has no story, so it shows no chapter line.
do
	local h = Barrens({ charDB = { journey = "carry" }, db = { autoStart = false } })
	local ns = h.ns
	check(ns.CurrentJourney().kind == "carry", "the carry journey is shown")
	check(ns.CurrentJourney().story == nil, "and has no story")
	check(Beat(h) == nil, "no chapter line is drawn")
	check(h.tracker.layoutOrder[1] == ns.Guidance.CurrentStep().key, "the current step is first")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A turn-in advances the chapter, and the line follows it in the same rebuild.
do
	local h = Barrens({ spf = "v1", db = { autoStart = false } })
	local ns = h.ns
	local before = Shown(ns).story
	check(Beat(h):find(Expected(ns, before), 1, true) ~= nil, "the line starts the story")
	local turnedIn = before.members[before.chapter]
	h.fire("QUEST_TURNED_IN", turnedIn)
	h.flush()
	local after = Shown(ns).story
	check(after.chapter == before.chapter + 1, "the turn-in advances the chapter")
	local beat = Beat(h)
	check(beat ~= nil, "the line is still there")
	check(beat:find(Expected(ns, after), 1, true) ~= nil, "it names the new chapter")
	check(beat:find(Expected(ns, before), 1, true) == nil, "the old chapter is gone")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("tracker_story_beat_spec: " .. checks .. " checks passed")
