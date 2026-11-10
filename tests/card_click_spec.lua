-- Run from the repository root: luajit tests/card_click_spec.lua
-- Choosing a journey from its card never depends on the map opening: the choice is made first and only the map turn
-- is protected, so a build without CreateSecureDelegate (#590, #592, #599) still selects the journey.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- The ui_spec fixture with no card chosen yet, so the overview draws every journey card.
local function Load()
	return harness.load({
		planned = true,
		panelHeight = 1200,
		db = { autoStart = false },
		charDB = false,
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
	})
end

local function Cards(h)
	return h.Find(function(f)
		return f:IsVisible() and f.journey ~= nil and (f.IconFrame ~= nil or (f.Icon ~= nil and f.Icon.Clip ~= nil))
	end)
end

local function Card(h)
	for _, card in ipairs(Cards(h)) do
		if card.state ~= "chosen" then
			return card
		end
	end
end

-- The reported build: the map is already up and CreateSecureDelegate is nil before the panel opens, so ns.OpenMap
-- cannot turn it.
do
	local h = Load()
	h.G.WorldMapFrame:Show()
	h.G.CreateSecureDelegate = nil
	h.ns.OpenPanel()
	h.flush()
	equal(#h.errors, 0, "nil delegate: the panel opens")
	local card = Card(h)
	assert(card, "nil delegate: the overview draws a journey card")
	h.Click(card)
	h.flush()
	equal(#h.errors, 0, "nil delegate: the click does not error")
	equal(h.ns.Prefs().journey, card.journey.key, "nil delegate: the click selects the journey")
	equal(h.ns.CurrentJourney().key, card.journey.key, "nil delegate: the route shows the selected journey")
end

-- The control: with the client's delegate present the same click selects the journey.
do
	local h = Load()
	equal(type(h.G.CreateSecureDelegate), "function", "delegate: the client has CreateSecureDelegate")
	h.ns.OpenPanel()
	h.flush()
	equal(#h.errors, 0, "delegate: the panel opens")
	local card = Card(h)
	assert(card, "delegate: the overview draws a journey card")
	h.Click(card)
	h.flush()
	equal(#h.errors, 0, "delegate: the click does not error")
	equal(h.ns.Prefs().journey, card.journey.key, "delegate: the click selects the journey")
	equal(h.ns.CurrentJourney().key, card.journey.key, "delegate: the route shows the selected journey")
end

-- And an error inside the map turn is contained: the card is still chosen.
do
	local h = Load()
	h.ns.OpenPanel()
	h.flush()
	h.G.WorldMapFrame:Show()
	local card = Card(h)
	assert(card, "map error: the overview draws a journey card")
	local opened = h.ns.OpenMap
	local calls = 0
	h.ns.OpenMap = function()
		calls = calls + 1
		error("the map refuses to open")
	end
	h.Click(card)
	h.flush()
	h.ns.OpenMap = opened
	equal(calls, 1, "map error: the click tries to turn the map")
	equal(#h.errors, 0, "map error: the error does not leave the click handler")
	equal(h.ns.Prefs().journey, card.journey.key, "map error: the click still selects the journey")
end

print(("card_click_spec: %d checks passed"):format(checks))
