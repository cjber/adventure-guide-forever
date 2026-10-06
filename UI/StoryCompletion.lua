---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
---@class AGFStoryCompletion
local Stories = {}
ns.StoryCompletion = Stories
---@type {key: string, title: string, quest: integer}[]
local queue = {}
---@type AGFWindowCard?
local popup
---@type FontString
local title
local ready, showing = false, false
local ShowNext

---@param questID integer
---@return boolean
function Stories.Record(questID)
	local story = ns.Data.quests[questID] and ns.Model.Story(ns.Data, questID)
	if not (story and story.total and story.chapter == story.total) then
		return false
	end
	local key = "story:" .. story.members[1]
	local records = ns.Prefs().completedStories
	if records[key] then
		return false
	end
	local head = ns.Data.quests[story.members[1]]
	local record = { key = key, title = head.title, quest = questID }
	records[key] = record
	queue[#queue + 1] = record
	ShowNext()
	return true
end

ShowNext = function()
	if showing or not ready or not queue[1] then
		return
	end
	if not popup then
		popup = ns.Widgets.CreateCard(UIParent, false)
		ns.Widgets.SizeCard(popup, 360, 82, 0.95)
		popup:SetPoint("TOP", UIParent, "TOP", 0, -180)
		popup:SetFrameStrata("DIALOG")
		popup:EnableMouse(false)
		local inner = CreateFrame("Frame", nil, popup)
		inner:SetAllPoints()
		inner:SetFrameLevel(popup:GetFrameLevel() + 6)
		local icon = ns.Widgets.CreateRingIcon(inner, 42)
		icon:SetPoint("LEFT", 18, 0)
		ns.Widgets.SetRingIcon(icon, "QuestNormal")
		local heading = ns.Widgets.Heading(inner, L.STORY_COMPLETE)
		heading:SetPoint("TOPLEFT", 76, -18)
		title = inner:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		title:SetPoint("TOPLEFT", 76, -38)
		title:SetWidth(264)
		title:SetJustifyH("LEFT")
		title:SetWordWrap(true)
		title:SetMaxLines(2)
		popup.Highlight:Hide()
	end
	local record = table.remove(queue, 1)
	showing = true
	title:SetText(record.title)
	popup:SetAlpha(1)
	popup:Show()
	popup.Highlight:Show()
	C_Timer.After(0.8, function()
		popup.Highlight:Hide()
	end)
	ns.Sound.Complete(record.key, true)
	C_Timer.After(6, function()
		for index = 1, 4 do
			C_Timer.After(index * 0.1, function()
				popup:SetAlpha(1 - index / 4)
				if index == 4 then
					popup:Hide()
					showing = false
					ShowNext()
				end
			end)
		end
	end)
end

EventUtil.ContinueAfterAllEvents(function()
	C_Timer.After(0, function()
		ready = true
		ShowNext()
	end)
end, "VARIABLES_LOADED", "PLAYER_ENTERING_WORLD")
