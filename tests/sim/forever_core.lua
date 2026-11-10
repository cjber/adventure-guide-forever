-- ForeverCore as an extra addon for the client simulator: the checkout FOREVER_CORE names, registered next to the
-- addon under test so the TOC's dependency resolves to the real shared modules.
local ForeverCore = dofile("tests/forever_core.lua")

return { { ForeverCore.directory(), "ForeverCore" } }
