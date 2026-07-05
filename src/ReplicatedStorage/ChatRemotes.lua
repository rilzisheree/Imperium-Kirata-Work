--[[
	ChatRemotes.lua
	ModuleScript — ReplicatedStorage

	Central module for creating and accessing all RemoteEvents
	used by the custom chat system. Both server and client
	require this module to ensure they share the exact same
	RemoteEvent instances.

	Server: creates RemoteEvents via getOrCreate.
	Client: waits for server to replicate them via WaitForChild.
	        This matches how CommandRemotes.lua works and prevents
	        the race condition where the client creates orphaned
	        local RemoteEvents before the server has replicated.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local ChatRemotes = {}

-- ── Server side: create RemoteEvents ──────────────────────────────────────────

if RunService:IsServer() then
	local function getOrCreate(name: string): RemoteEvent
		local existing = ReplicatedStorage:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local event = Instance.new("RemoteEvent")
		event.Name   = name
		event.Parent = ReplicatedStorage
		return event
	end

	-- Fired by client → server when a player submits a chat message
	ChatRemotes.MessageSent     = getOrCreate("ChatMessageSent")

	-- Fired by server → all clients to display a player chat message
	ChatRemotes.MessageReceived = getOrCreate("ChatMessageReceived")

	-- Fired by server → one or all clients for system/status messages
	ChatRemotes.SystemMessage   = getOrCreate("ChatSystemMessage")

	print("[ChatRemotes] Ready on server.")

-- ── Client side: wait for server to replicate RemoteEvents ────────────────────

else
	local function waitFor(name: string): RemoteEvent
		local r = ReplicatedStorage:WaitForChild(name, 15)
		if not r then
			error("[ChatRemotes] Timed out waiting for RemoteEvent '" .. name
				.. "'. Ensure ChatServer is running and the server created it.", 2)
		end
		return r :: RemoteEvent
	end

	ChatRemotes.MessageSent     = waitFor("ChatMessageSent")
	ChatRemotes.MessageReceived = waitFor("ChatMessageReceived")
	ChatRemotes.SystemMessage   = waitFor("ChatSystemMessage")

	print("[ChatRemotes] Ready on client.")
end

return ChatRemotes
