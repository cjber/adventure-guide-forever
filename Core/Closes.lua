---@type string, AGFNamespace
local _, ns = ...

-- Quests that taking another closes for good (docs/design.md §2.26). When a giver's detail window offers a quest
-- whose taking would close another quest of its exclusive group that this character could still do, one chat line
-- names what would be lost, before the player clicks Accept. Said once per quest a session; a quest the game took
-- itself (auto-accept) says nothing, and nor does anything while the setting is off or Polestar's own warning is on.

local L = ns.L
---@class AGFClosesModule
local Closes = {}
ns.Closes = Closes

---@type table<integer, true>
local warned = {}

-- The chat line for taking `questID`, or nil when it closes nothing the character could still do.
---@param questID integer
---@return string?
function Closes.Line(questID)
	local data, state = ns.Data, ns.State
	local quest = data.quests[questID]
	if not quest then
		return nil
	end
	local lost = ns.Model.Closes(data, state.Player(), state.Completed(), state.Log(), questID)
	if not lost[1] then
		return nil
	end
	local names = {}
	for index, id in ipairs(lost) do
		names[index] = state.QuestTitle(id) or data.quests[id].title
	end
	return L.CLOSES_WARNING:format(state.QuestTitle(questID) or quest.title, table.concat(names, L.LIST_SEPARATOR))
end

local function Offered()
	if not ns.Setting("warnClosing") or ns.Polestar.Setting("behavior.warnClosing") then
		return
	end
	if QuestGetAutoAccept and ns.Readable(QuestGetAutoAccept()) then
		return
	end
	local id = GetQuestID and ns.Readable(GetQuestID())
	if type(id) ~= "number" or id <= 0 or warned[id] then
		return
	end
	local line = Closes.Line(id)
	if line then
		warned[id] = true
		ns.Print(line)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_DETAIL")
events:SetScript("OnEvent", function()
	ns.SafeCall("quest window", Offered)
end)
