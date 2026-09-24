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
-- Skip for now: until the next session.
---@type table<string, boolean>
local skipped = {}
---@type fun()[]
local listeners = {}

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
		if not (skipped[aside.key] or declined[aside.key]) then
			return aside
		end
	end
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
	skipped[key] = true
	Notify()
end

---@param aside AGFAside
function Asides.Decline(aside)
	Declined()[aside.key] = aside.text
	Notify()
end

-- The turned-down asides, by text, for Show again.
---@return {key: string, text: string}[]
function Asides.Declined()
	local list = {}
	for key, text in pairs(Declined()) do
		list[#list + 1] = { key = key, text = text }
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

--[[ The first provider: the class trainer (docs/plan.md F16), from Tweaks Forever's spells to train. Text only: the
     data has no trainer's place. ]]

Asides.Register(function()
	local spells = ns.Integrations.Trainable()
	local count = spells and #spells or 0
	if count == 0 then
		return nil
	end
	local spellCount = count == 1 and L.TRAINER_SPELL or L.TRAINER_SPELLS:format(count)
	-- The minimap's class trainer mark (CSV:1321).
	return { key = "trainer", text = L.TRAINER_LINE:format(L.TRAINER, spellCount), icon = "class" }
end)

-- A spell learned at the trainer shortens the line at once.
local spellbook = CreateFrame("Frame")
spellbook:RegisterEvent("SPELLS_CHANGED")
spellbook:SetScript("OnEvent", Asides.Refresh)
