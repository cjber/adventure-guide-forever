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
return { Button = Button, FindText = FindText }
