local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local ChatRemotes = {}

if RunService:IsServer() then
	local function make(name)
		local e = ReplicatedStorage:FindFirstChild(name)
		if e and e:IsA("RemoteEvent") then return e end
		e = Instance.new("RemoteEvent")
		e.Name   = name
		e.Parent = ReplicatedStorage
		return e
	end

	ChatRemotes.MessageSent     = make("ChatMessageSent")
	ChatRemotes.MessageReceived = make("ChatMessageReceived")
else
	local function get(name)
		local r = ReplicatedStorage:WaitForChild(name, 15)
		if not r then error("ChatRemotes: timed out waiting for " .. name, 2) end
		return r :: RemoteEvent
	end

	ChatRemotes.MessageSent     = get("ChatMessageSent")
	ChatRemotes.MessageReceived = get("ChatMessageReceived")
end

return ChatRemotes
