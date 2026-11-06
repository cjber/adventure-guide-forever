---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
---@class AGFStoryCompletion
local Stories = {}
ns.StoryCompletion = Stories

-- The toast is the client's own achievement alert (Mainline/AlertFrameSystems.xml:173), queued through AlertFrame
-- like the achievement system's (two on screen, six waiting). It carries no achievement ID, so a left click opens
-- nothing (AchievementAlertFrame_OnClick returns without one) and a right click dismisses it.
local TEMPLATE = "AchievementAlertFrameTemplate"
local ICON = "Interface\\Icons\\Achievement_Quests_Completed_08"

---@class AGFStoryAlert : Button
---@field Unlocked FontString
---@field Name FontString
---@field Icon Frame|{Texture: Texture}
---@field Shield Frame
---@field id integer?

-- Fills a pooled toast: the shield's points hide and the heading centres as an achievement already earned does
-- (AchievementAlertFrame_SetUp); the sound plays as it shows, so a queued story sounds when its turn comes.
---@param frame AGFStoryAlert
---@param record {key: string, title: string}
local function SetUp(frame, record)
	frame.id = nil
	frame.Shield:Hide()
	frame.Unlocked:SetPoint("TOP", 27, -23)
	frame.Unlocked:SetText(L.STORY_COMPLETE)
	frame.Name:SetText(record.title)
	ns.Art.Icon(frame.Icon.Texture, ICON, 52)
	ns.Sound.Complete(record.key, true)
end

---@type AGFAlertSubSystem?
local system
-- Registered at the first story finished, so a session that finishes none adds nothing to AlertFrame. The
-- achievement system's own global stands for its template being loaded.
local function System()
	if not system and AlertFrame and AchievementAlertSystem then
		-- The template's Shield child calls AchievementShield_OnLoad, which lives in the load-on-demand
		-- Blizzard_AchievementUI; the client loads it before queueing its own toasts (AlertFrames.lua:544).
		if AchievementFrame_LoadUI then
			AchievementFrame_LoadUI()
		end
		system = AlertFrame:AddQueuedAlertFrameSubSystem(TEMPLATE, SetUp, 2, 6)
	end
	return system
end

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
	local alerts = System()
	if alerts then
		alerts:AddAlert(record)
	else
		ns.Sound.Complete(key, true)
	end
	return true
end
