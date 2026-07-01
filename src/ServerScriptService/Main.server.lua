--[[
Main.server.lua
Script — ServerScriptService

Entry point for the Imperium game server.
The custom chat system is handled by ChatServer.server.lua.
--]]

-- Disable Roblox's legacy chat bar entirely so only the custom chat is used
game:GetService("Players").ChatEnabled = false

print("[Imperium] Server started.")
print("[Imperium] Server Here.")
