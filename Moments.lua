---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- "Something new" (docs/design.md §2.13): after a level gained or a zone entered, a journey card or an aside the
-- character has never been offered glows the tracker once, marks its card and puts a pip on the Adventure tab and the
-- addon compartment. Nothing opens by itself; opening the guide clears the pips and the tracker's line, and closing
-- it the marks. What the character has been offered is kept per character (charDB.seen).
---@class AGFMomentsModule : AGFMoments
local Moments = {}
ns.Moments = Moments

-- An aside's key in the seen set, apart from the journeys' (the same prefix Skipped uses).
local ASIDE = "aside:"
-- The addon compartment's pip: the Adventure Guide micro button's alert (CSV:2025) at its top-right corner.
local PIP = "adventureguide-microbutton-alert"

-- The session's first look only learns what is there, so a save file the client never loaded (#34) never floods.
local looked = false
-- A level gained or a zone entered since the last look; armed by the rebuild it brings, which the next look compares.
local pending, armed = false, false
-- The new journeys' keys, marked on their cards until the guide closes.
---@type table<string, boolean>
local fresh = {}
-- The tracker's line: the first new journey, by key, with its text.
---@type {key: string, text: string}?
local moment
-- The guide hasn't been opened since the last new thing: the pips show.
local unseen = false
---@type fun()[]
local listeners = {}
---@type Texture?
local compartmentPip

local function Notify()
	if compartmentPip then
		compartmentPip:SetShown(unseen)
	end
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- The keys this character has been offered: journeys by their key, asides as "aside:<key>" while a provider answers.
---@return table<string, boolean>
local function Seen()
	local prefs = ns.Prefs()
	if type(prefs.seen) ~= "table" then
		prefs.seen = {}
	end
	return prefs.seen
end

-- "Duskwood is now for your level": a zone by the client's name, a dungeon by its card's. Your calling says what it
-- offers ("A task for your class: Call of Water"), since it is no place to be the level for; a battleground is open
-- ("Warsong Gulch is open to you"), from a level on.
---@param journey AGFJourney
---@return string
local function Text(journey)
	if journey.kind == "calling" and journey.reason then
		return journey.reason
	elseif journey.kind == "battleground" then
		return L.BATTLEGROUND_OPEN:format(journey.title)
	end
	local zone = tonumber(journey.key:match("^zone:(%d+)$"))
	local name = zone and (ns.State.MapName(zone) or ns.Data.zones[zone].name) or journey.title
	return L.MOMENT:format(name)
end

-- An aside no provider gives any more leaves the set, so the trainer's next spells are new again; so does anything a
-- hand-edited save file put there that isn't a key. Also on each change of the aside shown: training every spell
-- (SPELLS_CHANGED) brings no rebuild, and the level that follows must still find the next ones new.
---@param seen table<string, boolean>
---@return table<string, boolean> answered the asides' keys in the seen set's form
local function Forget(seen)
	local answered = {}
	for _, aside in ipairs(ns.Asides.Answers()) do
		answered[ASIDE .. aside.key] = true
	end
	for key in pairs(seen) do
		if type(key) ~= "string" or key:sub(1, #ASIDE) == ASIDE and not answered[key] then
			seen[key] = nil
		end
	end
	return answered
end

-- Step 1's travel frame after each rebuild (Core), once the asides have answered: out of combat, once the completed
-- quests have loaded. Everything offered now joins the seen set; only a look armed by a level or a zone compares
-- first, and never against an empty set.
function Moments.Observe()
	if InCombatLockdown() or not ns.State.Ready() then
		return
	end
	local seen = Seen()
	local compare = armed and next(seen) ~= nil
	looked = true
	if armed then
		pending, armed = false, false
	end
	---@type AGFJourney?
	local first
	for _, journey in ipairs(ns.Route().journeys) do
		if journey.kind ~= "carry" then
			if compare and not seen[journey.key] then
				fresh[journey.key] = true
				first = first or journey
			end
			seen[journey.key] = true
		end
	end
	local answered = Forget(seen)
	local aside = ns.Asides.Current()
	local newAside = compare and aside ~= nil and not seen[ASIDE .. aside.key]
	for key in pairs(answered) do
		seen[key] = true
	end
	if not (first or newAside) then
		return
	end
	if first then
		moment = { key = first.key, text = Text(first) }
	end
	-- Already looking at the guide: the marks, and nothing to call the player over.
	unseen = not (ns.PanelShown and ns.PanelShown())
	if unseen and ns.OnMoment then
		ns.OnMoment(first ~= nil, newAside)
	end
	Notify()
end

---@param key string
---@return boolean
function Moments.IsNew(key)
	return fresh[key] == true
end

-- The pips show: something new since the guide was last opened.
---@return boolean
function Moments.Unseen()
	return unseen
end

-- The tracker's line while the guide is unopened and its journey is still offered.
---@return string?
function Moments.Line()
	if not (unseen and moment) then
		return nil
	end
	for _, journey in ipairs(ns.Route().journeys) do
		if journey.key == moment.key then
			return moment.text
		end
	end
end

-- The guide opened: the pips and the tracker's line go; the marks stay while it shows.
function Moments.Opened()
	if unseen then
		unseen = false
		Notify()
	end
end

-- The guide closed: the marks go.
function Moments.Closed()
	if next(fresh) then
		fresh, moment = {}, nil
		Notify()
	end
end

---@param fn fun()
function Moments.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function()
	pending = pending or looked
end)
ns.OnRouteChange(function()
	armed = armed or pending
end)
ns.Asides.OnChange(function()
	Forget(Seen())
end)

-- The compartment's button is Blizzard's (Blizzard_Minimap AddonCompartment.xml); the pip is a texture of AGF's on it.
if AddonCompartmentFrame then
	compartmentPip = AddonCompartmentFrame:CreateTexture(nil, "OVERLAY")
	compartmentPip:SetAtlas(PIP)
	compartmentPip:SetSize(14, 14)
	compartmentPip:SetPoint("CENTER", AddonCompartmentFrame, "TOPRIGHT", -2, -2)
	compartmentPip:Hide()
end
