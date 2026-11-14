-- #758: a full visible log plus hidden client quests must still advertise a selectable peer.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	checks = checks + 1
	assert(value, label)
end
local function Client(name, other)
	local sent = {}
	local h = harness.load({
		db = { autoStart = false },
		locale = "frFR",
		setup = function(this)
			local G = this.G
			G.LE_PARTY_CATEGORY_HOME = 1
			G.IsInGroup = function()
				return true
			end
			G.IsInRaid = function()
				return false
			end
			G.GetNormalizedRealmName = function()
				return "Realm"
			end
			G.UnitExists = function(unit)
				return unit == "party1"
			end
			G.UnitName = function(unit)
				return unit == "player" and name or other
			end
			G.C_ChatInfo = {
				RegisterAddonMessagePrefix = function()
					return 0
				end,
				SendAddonMessage = function(prefix, text, channel)
					sent[#sent + 1] = { prefix, text, channel }
					return 0
				end,
			}
		end,
	})
	-- The actual client read can include hidden quests in addition to the 40 visible log entries.
	h.G.C_QuestLog.GetNumQuestLogEntries = function()
		return 41
	end
	h.G.C_QuestLog.GetInfo = function(index)
		return { questID = index, isHeader = false, isHidden = index == 41 }
	end
	for index = #sent, 1, -1 do
		sent[index] = nil
	end
	h.time = h.time + 30
	h.fire("GROUP_ROSTER_UPDATE")
	h.ns.Party.Send(true, true)
	h.flush()
	return h, sent
end
local ana, fromAna = Client("Ana", "Bo")
local bo, fromBo = Client("Bo", "Ana")
check(#fromAna > 0, "Ana advertises despite hidden client quests beyond the visible log limit")
check(#fromBo > 0, "Bo advertises despite hidden client quests beyond the visible log limit")
local decoded = assert(ana.ns.Party.Decode(fromAna[1][2]))
check(decoded.log[40] == true and decoded.log[41] == nil, "only visible quest IDs occupy the log payload")
local function Deliver(target, sent, sender)
	for _, page in ipairs(sent) do
		target.fire("CHAT_MSG_ADDON", page[1], page[2], page[3], sender)
	end
	target.flush()
end
Deliver(bo, fromAna, "Ana-Realm")
Deliver(ana, fromBo, "Bo-Realm")
for _, h in ipairs({ ana, bo }) do
	local members = h.ns.Party.Members()
	check(#members == 1, "each client discovers its peer")
	local owner = h.G.CreateFrame("Button", nil, h.G.UIParent)
	h.G.ForeverCore.ContextMenu(owner, h.ns.Menu.Settings)
	local sync
	for _, entry in ipairs(h.menu.entries) do
		if entry.text == h.ns.L.SYNC_WITH then
			sync = entry
		end
	end
	check(sync ~= nil, "French sync menu exists")
	local member
	for _, entry in ipairs(sync.entries) do
		if entry.text == members[1].name then
			member = entry
		end
	end
	check(member ~= nil, "the peer is an interactive menu entry")
	check(member.kind == "checkbox", "the peer is selectable rather than a status title")
	h.call(member.onClick)
	h.flush()
	check(h.ns.Party.IsSynced(members[1].key), "the peer can be selected")
	check(#h.ns.Party.Synced() == 1, "the selected peer reaches the planner")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end
print(("sync_interaction_spec: %d checks passed"):format(checks))
