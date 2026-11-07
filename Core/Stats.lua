---@type string, AGFNamespace
local addonName, ns = ...

-- Adventure Guide's side of the shared peer statistics (Core/PeerStats.lua, vendored from Forever Core): it names the
-- one metric this addon reports, keeps the saved peer table, and registers the addon's board with the shared Forever
-- Leaderboards window. The protocol, the bounds, the send queue, the window and the game events behind them belong to
-- the shared modules; nothing here reimplements them.
---@class AGFStats
local Stats = {}
ns.Stats = Stats

local METRIC = "quest_turn_ins"
local SUBJECT = "all"
local DEFAULT_LIMIT, MAX_LIMIT = 10, 25
local MAX_VALUE, MAX_UNIX = 1e9, 2 ^ 31 - 1
local ICON = "Interface\\AddOns\\" .. addonName .. "\\media\\Icon"

---@param value any
---@param low number
---@param high number
---@return boolean
local function WholeNumber(value, low, high)
	return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

-- The pre-leaderboard layout was sharedStats[sender][addon][metric][subject]. Copy only this addon's validated
-- cumulative total into the canonical sender -> metric -> subject table and leave the old table as it was, so a
-- downgrade still finds its history. Another addon's rows are not ours to interpret.
local function MigratedPeers(old)
	local peers = {}
	if type(old) ~= "table" then
		return peers
	end
	for sender, addons in pairs(old) do
		local record = type(sender) == "string" and type(addons) == "table" and type(addons.agf) == "table"
		record = record and type(addons.agf[METRIC]) == "table" and addons.agf[METRIC][SUBJECT]
		if
			type(record) == "table"
			and WholeNumber(record.value, 0, MAX_VALUE)
			and WholeNumber(record.eventUnix, 1, MAX_UNIX)
		then
			peers[sender] = { [METRIC] = { [SUBJECT] = { value = record.value, eventUnix = record.eventUnix } } }
		end
	end
	return peers
end

-- The saved peer table, built from the old layout once. nil before the saved variables load.
local function Peers()
	local db = AdventureGuideForeverDB
	if type(db) ~= "table" then
		return nil
	end
	if type(db.peerStats) ~= "table" then
		db.peerStats = MigratedPeers(db.sharedStats)
	end
	return db.peerStats
end

local function Enabled()
	return ns.Setting("statsShare") ~= false
end

-- This character's cumulative turn-in total and its latest event, from Core/Activity.lua.
local function LocalTotal()
	for _, row in ipairs(ns.ActivityStats()) do
		if row.metric == METRIC and row.subject == SUBJECT then
			return row.value, row.eventUnix
		end
	end
	return 0, nil
end

local peerStats = ns.PeerStats.New({
	addon = "agf",
	enabled = Enabled,
	db = Peers,
	-- A character with no turn-in yet has nothing to report; unknown stays unknown.
	snapshot = function()
		local value, eventUnix = LocalTotal()
		return value > 0 and { { metric = METRIC, subject = SUBJECT, value = value, eventUnix = eventUnix } } or {}
	end,
	metrics = { [METRIC] = { subject = "all" } },
})

-- One row per ranked player, in the shape the shared window draws. Rows leave class nil: the shared window fills it
-- through ForeverLeaderboards.ClassOf, which knows the player, group and guild roster better than a name match here.
-- The all-time board keeps the cumulative total in the value column; the weekly board draws the progress since the
-- reset there and the cumulative total in grey.
---@param scope ForeverLeaderboardsScope
---@return ForeverLeaderboardsRow[]
local function Board(scope)
	local value, eventUnix = LocalTotal()
	local weekly = scope == "week"
	local ranked
	local totals
	if weekly then
		ranked = peerStats:WeekBoard(METRIC, SUBJECT, value, eventUnix)
		totals = {}
		for _, row in ipairs(peerStats:Board(METRIC, SUBJECT, value, eventUnix)) do
			totals[row.identity] = row.value
			totals[row.name:lower()] = row.value
		end
	else
		ranked = peerStats:Board(METRIC, SUBJECT, value, eventUnix)
	end
	local rows = {}
	for _, row in ipairs(ranked) do
		local total = totals and (totals[row.identity] or totals[row.name:lower()])
		rows[#rows + 1] = {
			name = row.name,
			value = row.value,
			extra = total and (total .. " " .. ns.L.LEADERBOARD_TOTAL) or nil,
			you = row.self == true,
		}
	end
	return rows
end

--- Open the shared Forever Leaderboards window on this addon's tab.
function Stats.Open()
	if ns.Leaderboards then
		ns.Leaderboards:Open("agf")
	end
end

if ns.Leaderboards then
	ns.Leaderboards:Register("agf", {
		title = ns.L.TITLE,
		icon = ICON,
		metric = ns.L.LEADERBOARD_METRIC,
		board = Board,
		revision = function()
			return peerStats:Revision()
		end,
		sharing = Enabled,
		setSharing = function(shared)
			ns.SetSetting("statsShare", shared == true)
		end,
	})
end

--- Offer this character's total to the guild and group channels again.
function Stats.Sync()
	peerStats:Sync()
end

--- Rows heard from other players: sender -> metric -> subject -> { value, eventUnix }. Empty while sharing is off.
function Stats.Shared()
	return peerStats:Shared()
end

--- The sharing switch changed (the setting is already saved): stop and forget what waited, or offer the total again.
---@param enabled boolean
function Stats.SetEnabled(enabled)
	peerStats:SetEnabled(enabled == true)
end

---@param limit? integer
---@return AGFLeaderboard?
function Stats.Leaderboard(limit)
	if limit == nil then
		limit = DEFAULT_LIMIT
	elseif type(limit) ~= "number" or limit < 0 or limit % 1 ~= 0 then
		return nil
	end
	limit = math.min(limit, MAX_LIMIT)
	local value, eventUnix = LocalTotal()
	local ranked = peerStats:Board(METRIC, SUBJECT, value, eventUnix)
	local rows = {}
	for _, row in ipairs(ranked) do
		if row.rank <= limit or row.self then
			rows[#rows + 1] = {
				rank = row.rank,
				name = row.name,
				value = row.value,
				eventUnix = row.eventUnix,
				self = row.self == true or nil,
			}
		end
	end
	return { metric = METRIC, scope = "guild_group", sharing = Enabled(), total = #ranked, rows = rows }
end

-- The shared module owns the chat and roster events. Here only this addon's own change: a turn-in, and the first
-- offer once the saved variables are in.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_TURNED_IN")
events:SetScript("OnEvent", function(_, event)
	if C_Timer and C_Timer.After then
		C_Timer.After(event == "PLAYER_LOGIN" and 1 or 0, Stats.Sync)
	end
end)

return Stats
