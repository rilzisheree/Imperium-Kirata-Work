--[[
ChatRemotes.lua
ModuleScript — ReplicatedStorage

Central module for creating and accessing all RemoteEvents
used by the custom chat system. Both server and client
require this module to ensure they share the exact same
RemoteEvent instances.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChatRemotes = {}

-- Helper: find an existing RemoteEvent or create a new one
local function getOrCreate(name: string): RemoteEvent
local existing = ReplicatedStorage:FindFirstChild(name)
if existing and existing:IsA("RemoteEvent") then
return existing
end
local event = Instance.new("RemoteEvent")
event.Name = name
event.Parent = ReplicatedStorage
return event
end

-- Fired by client → server when a player submits a chat message
ChatRemotes.MessageSent = getOrCreate("ChatMessageSent")

-- Fired by server → all clients to display a player chat message
ChatRemotes.MessageReceived = getOrCreate("ChatMessageReceived")

-- Fired by server → one or all clients for system/status messages
ChatRemotes.SystemMessage = getOrCreate("ChatSystemMessage")

return ChatRemotes
