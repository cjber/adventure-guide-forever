---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- Waiting for the client's item data. GET_ITEM_INFO_RECEIVED fires for every item any addon asks about, in bursts, so
-- a feature never reacts to the event itself: it names the item it is waiting for, and its callback runs once that
-- item's data arrives, at most once per frame however many of its items land together (#844). This is the one file
-- that names the event (tools/repo_rules.py, item-info-outside-core).
---@class AGFItemInfo
local ItemInfo = {}
ns.ItemInfo = ItemInfo

---@type table<integer, table<function, true>>
local awaited = {}
---@type table<function, true>?
local due

local function RunDue()
	local run = due or {}
	due = nil
	for callback in pairs(run) do
		ns.core.SafeCall("item info", callback)
	end
end

-- Run `callback` on the frame after the client's data for `itemID` arrives. Asking again for an item already
-- awaited adds nothing, and an item whose data never arrives costs one table entry.
---@param itemID integer?
---@param callback function
function ItemInfo.Await(itemID, callback)
	if type(itemID) ~= "number" then
		return
	end
	local callbacks = awaited[itemID]
	if not callbacks then
		callbacks = {}
		awaited[itemID] = callbacks
	end
	callbacks[callback] = true
end

-- Stop waiting with `callback` for every item: what it waited for is gone, or it is about to name its items afresh.
---@param callback function
function ItemInfo.Forget(callback)
	for itemID, callbacks in pairs(awaited) do
		callbacks[callback] = nil
		if next(callbacks) == nil then
			awaited[itemID] = nil
		end
	end
	if due then
		due[callback] = nil
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, _, itemID, success)
	local callbacks = awaited[itemID]
	-- A failed load caches nothing: the wait stays for the arrival that does.
	if not callbacks or success == false then
		return
	end
	awaited[itemID] = nil
	if not due then
		due = {}
		C_Timer.After(0, RunDue)
	end
	for callback in pairs(callbacks) do
		due[callback] = true
	end
end)
