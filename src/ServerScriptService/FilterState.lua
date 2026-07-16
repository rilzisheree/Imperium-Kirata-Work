-- Shared between ChatServer and CommandServer.
-- filterBypass[userId] = true means the chat filter is OFF for that player.
-- Both modules require this same table reference — never replace it.
local FilterState = {}
FilterState.filterBypass = {}
return FilterState
