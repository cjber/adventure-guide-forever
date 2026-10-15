---@type string, AGFNamespace
local _, ns = ...

-- Secret values (docs/design.md §2.23). The client can hand an addon a value it may hold but not read: another unit's
-- GUID, token or name in some combat and instance states. Comparing, indexing, matching or even testing such a value
-- for truth raises an error, so each such read passes through ns.Readable before anything else touches it. A tooltip
-- the client marks forbidden (a secure or protected tooltip) must not be touched at all; ns.Usable says whether one
-- may be. The player's own level, faction and position are never secret and are read directly.
-- Keep this file free of other addon state so the pattern copies across the Forever addons as is.

-- `value` when this code may read it, nil when it is secret. Only nil itself and readable values come back, so a
-- caller's next truth test is always safe. A client without secret values (no canaccessvalue) reads everything.
---@generic T
---@param value T
---@return T?
function ns.Readable(value)
	if value == nil then
		return nil
	end
	if canaccessvalue and not canaccessvalue(value) then
		return nil
	end
	return value
end

-- Whether `frame` (a tooltip, usually) may be read and drawn on: false for nil and for a forbidden frame.
---@param frame? Frame
---@return boolean
function ns.Usable(frame)
	if not frame then
		return false
	end
	return not (frame.IsForbidden and frame:IsForbidden())
end
