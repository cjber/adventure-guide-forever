local function Button(each, text)
	for _, frame in
		ipairs(each.Find(function(f)
			return f:IsVisible() and (f:GetText() == text or f.Text and f.Text:GetText() == text)
		end))
	do
		if frame:IsObjectType("Button") then
			return frame
		end
	end
	error("missing button " .. text)
end
local function FindText(frame, text)
	if frame.GetText and frame:GetText() == text then
		return frame
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local found = FindText(child, text)
		if found then
			return found
		end
	end
end
-- Every text a frame shows (the window by default), from its dump: font strings and button labels, each counted.
local function Texts(each, root)
	local texts = {}
	for _, entry in ipairs(each.ns.DumpLayout(root or each.G.AdventureGuideForeverWindow, each.Describe)) do
		if entry.text then
			texts[entry.text] = (texts[entry.text] or 0) + 1
		end
	end
	return texts
end
return { Button = Button, FindText = FindText, Texts = Texts }
