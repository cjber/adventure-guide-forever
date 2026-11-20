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

-- Run `callbacks` on the next frame, each once, with whatever else is due then.
---@param callbacks table<function, true>
local function Due(callbacks)
	if not due then
		due = {}
		C_Timer.After(0, RunDue)
	end
	for callback in pairs(callbacks) do
		due[callback] = true
	end
end

-- Run `callback` on the frame after the client answers for `itemID`: at once (next frame) for an item already
-- cached, otherwise once its load ends. Asking again for an item already awaited adds nothing.
---@param itemID integer?
---@param callback function
function ItemInfo.Await(itemID, callback)
	if type(itemID) ~= "number" then
		return
	end
	if C_Item.IsItemDataCachedByID(itemID) then
		Due({ [callback] = true })
		return
	end
	local callbacks = awaited[itemID]
	if not callbacks then
		callbacks = {}
		awaited[itemID] = callbacks
	end
	callbacks[callback] = true
	C_Item.RequestLoadItemDataByID(itemID)
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
events:SetScript("OnEvent", function(_, _, itemID)
	local callbacks = awaited[itemID]
	if not callbacks then
		return
	end
	-- A failed load is handed back too (`success` false): the client sends no second answer for a request it has
	-- ended, so a wait kept here would never end. The callback reads again, and that read asks for the item afresh.
	awaited[itemID] = nil
	Due(callbacks)
end)
