--[[
	CommandRemotes.lua
	ModuleScript — ReplicatedStorage
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local CommandRemotes = {}

local function getOrCreate(name: string): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local event = Instance.new("RemoteEvent")
	event.Name   = name
	event.Parent = ReplicatedStorage
	return event
end

if RunService:IsServer() then
	CommandRemotes.CommandExecuted = getOrCreate("CmdExecuted")
	CommandRemotes.CommandFeedback = getOrCreate("CmdFeedback")
	CommandRemotes.SM              = getOrCreate("CmdSM")
	CommandRemotes.IM              = getOrCreate("CmdIM")
	CommandRemotes.Anxiety         = getOrCreate("CmdAnxiety")
	print("[CommandRemotes] Ready on server.")
else
	local function wait(name: string): RemoteEvent
		local r = ReplicatedStorage:WaitForChild(name, 15)
		if not r then warn("[CommandRemotes] Timed out: " .. name) end
		return r :: RemoteEvent
	end
	CommandRemotes.CommandExecuted = wait("CmdExecuted")
	CommandRemotes.CommandFeedback = wait("CmdFeedback")
	CommandRemotes.SM              = wait("CmdSM")
	CommandRemotes.IM              = wait("CmdIM")
	CommandRemotes.Anxiety         = wait("CmdAnxiety")
	print("[CommandRemotes] Ready on client.")
end

return CommandRemotes
