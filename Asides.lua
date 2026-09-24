---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- Asides (docs/design.md §2.11): one-line hints beside the journeys, never a route. Each domain registers a provider
-- that gives at most one; the first provider's the player has neither skipped this session nor turned down is the
-- aside, drawn above the cards and as the tracker's line. Providers are asked in step 1's travel frame (Core), never
-- in a rebuild's, and not in combat, when the last answers stand.
---@class AGFAsidesModule : AGFAsides
local Asides = {}
ns.Asides = Asides

---@type (fun(): AGFAside?)[]
local providers = {}
-- Every provider's last answer, in registration order.
---@type AGFAside[]
local answers = {}
-- Skip for now: until the next session, or until its provider renews the aside (a new talent point): each skipped key
-- and the `renew` it had then, `true` for none.
---@type table<string, integer|true>
local skipped = {}
---@type fun()[]
local listeners = {}
-- The events a provider asks again on (RefreshOn).
---@type Frame?
local events

local function Notify()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- "Not interested", per character: each turned-down key and the text it had, which Show again names.
---@return table<string, string>
local function Declined()
	local prefs = ns.Prefs()
	if type(prefs.asides) ~= "table" then
		prefs.asides = {}
	end
	return prefs.asides
end

---@param fn fun(): AGFAside?
function Asides.Register(fn)
	providers[#providers + 1] = fn
end

---@param fn fun()
function Asides.OnChange(fn)
	listeners[#listeners + 1] = fn
end

---@return AGFAside?
function Asides.Current()
	local declined = Declined()
	for _, aside in ipairs(answers) do
		if not (skipped[aside.key] == (aside.renew or true) or declined[aside.key]) then
			return aside
		end
	end
end

-- Every provider's last answer, skipped or not, in registration order (Moments.lua's seen set).
---@return AGFAside[]
function Asides.Answers()
	return answers
end

-- What the player sees of an aside, so an unchanged answer redraws nothing.
---@param aside? AGFAside
---@return string
local function Seen(aside)
	local place = aside and aside.place
	return aside
			and table.concat({
				aside.key,
				aside.text,
				aside.icon,
				aside.texture or "",
				place and ("%d:%.4f:%.4f"):format(place.map, place.x, place.y) or "",
			}, "\n")
		or ""
end

function Asides.Refresh()
	if InCombatLockdown() then
		return
	end
	local before = Seen(Asides.Current())
	answers = {}
	for _, provider in ipairs(providers) do
		answers[#answers + 1] = provider()
	end
	if Seen(Asides.Current()) ~= before then
		Notify()
	end
end

---@param key string
function Asides.Skip(key)
	local renew = true
	for _, aside in ipairs(answers) do
		renew = aside.key == key and aside.renew or renew
	end
	skipped[key] = renew
	Notify()
end

-- Asks the providers again on `event`, when the client has it: an unknown event is an error on RegisterEvent, and an
-- API the probe did not confirm may come with none.
---@param event string
function Asides.RefreshOn(event)
	events = events or CreateFrame("Frame")
	events:SetScript("OnEvent", Asides.Refresh)
	pcall(events.RegisterEvent, events, event)
end

---@param aside AGFAside
function Asides.Decline(aside)
	Declined()[aside.key] = aside.text
	Notify()
end

-- The turned-down asides, by text, for Show again: its provider's answer now, else the text it had when turned down.
---@return {key: string, text: string}[]
function Asides.Declined()
	local now = {}
	for _, aside in ipairs(answers) do
		now[aside.key] = aside.text
	end
	local list = {}
	for key, text in pairs(Declined()) do
		list[#list + 1] = { key = key, text = now[key] or text }
	end
	table.sort(list, function(a, b)
		return a.text < b.text
	end)
	return list
end

---@param key string
function Asides.Restore(key)
	Declined()[key] = nil
	Notify()
end

-- Go: to the aside's place, as a step's Go goes (Integrations.Navigate). Only a place from the data has one.
---@param aside AGFAside
---@return boolean
function Asides.Go(aside)
	local place = aside.place
	return place ~= nil
		and ns.Integrations.Navigate({ map = place.map, x = place.x, y = place.y, title = place.name, quests = {} })
end

-- The aside's menu, for its line in the guide and in the tracker.
---@param owner Region
---@param tag string
---@param aside AGFAside
function Asides.Open(owner, tag, aside)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag(tag)
		root:CreateTitle(aside.text)
		if aside.place then
			root:CreateButton(L.GO, function()
				Asides.Go(aside)
			end)
		end
		root:CreateButton(L.SKIP, function()
			Asides.Skip(aside.key)
		end)
		root:CreateButton(L.NOT_INTERESTED, function()
			Asides.Decline(aside)
		end)
	end)
end

--[[ The first provider: the class trainer (docs/plan.md F16), from Tweaks Forever's spells to train, at the nearest
     trainer who teaches them (roadmap #5, Model.Trainer); text only when the data places none. ]]

Asides.Register(function()
	local training = ns.Integrations.Training()
	if not training then
		return nil
	end
	local count = training.count
	local spellCount = count == 1 and L.TRAINER_SPELL or L.TRAINER_SPELLS:format(count)
	local npc = ns.Model.Trainer(ns.Data, ns.State.Player(), training.level)
	local who = npc and L.TRAINER_IN:format(ns.Model.TownName(ns.Data, npc.place, ns.State.MapName)) or L.TRAINER
	-- The minimap's class trainer mark (CSV:1321).
	return { key = "trainer", text = L.TRAINER_LINE:format(who, spellCount), icon = "class", place = npc and npc.place }
end)

-- A spell learned at the trainer shortens the line at once.
Asides.RefreshOn("SPELLS_CHANGED")

--[[ Unspent talent points (roadmap #25): "You have 2 talent points to spend", while any are. The probe found
     GetNumUnspentTalents on Forever and UnitCharacterPoints missing; without the former there is no line. A point
     gained brings it back after a Skip for now, once per new point; spending them all ends it at once. ]]

-- The count at the last answer, and how many times it has risen this session (the aside's `renew`).
local talentPoints, talentRises = 0, 0

Asides.Register(function()
	local points = GetNumUnspentTalents and GetNumUnspentTalents() or 0
	talentRises = points > talentPoints and talentRises + 1 or talentRises
	talentPoints = points
	if points <= 0 then
		return nil
	end
	local text = points == 1 and L.TALENT_POINT or L.TALENT_POINTS:format(points)
	-- The Legion minor-talents book (CSV:388), the one square talent mark the atlas has.
	return { key = "talents", text = text, icon = "minortalents-icon-book", renew = talentRises }
end)
Asides.RefreshOn("CHARACTER_POINTS_CHANGED")
