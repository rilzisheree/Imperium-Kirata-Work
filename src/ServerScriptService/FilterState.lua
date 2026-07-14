-- Shared chat-filter state required by both ChatServer and CommandServer.
-- filterBypass[userId] = true  →  chat filter is OFF for that player.
-- The table is the shared mutable reference; never replace it with a new table.
local FilterState = {}
FilterState.filterBypass = {}  -- [userId] = true when filter is bypassed
return FilterState
