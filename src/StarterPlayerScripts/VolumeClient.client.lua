local SoundService     = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

-- All client-side game audio (music, weather ambience, IM/notification pops,
-- anxiety heartbeat, etc.) is routed through this single SoundGroup so one
-- personal volume setting scales everything uniformly. Assigning a Sound to
-- a SoundGroup from a LocalScript only affects this client's own playback —
-- it never replicates to the server or other players, which is what keeps
-- each player's volume fully independent.
local GROUP_NAME = "MasterVolumeGroup"

local masterGroup = SoundService:FindFirstChild(GROUP_NAME)
if not masterGroup then
	masterGroup = Instance.new("SoundGroup")
	masterGroup.Name   = GROUP_NAME
	masterGroup.Volume = 1
	masterGroup.Parent = SoundService
end

-- Default to full volume until the server confirms the saved/default value.
local currentVolume01 = 1

local function claim(sound: Sound)
	if sound.SoundGroup ~= masterGroup then
		sound.SoundGroup = masterGroup
	end
end

-- Catch every Sound instance that currently exists anywhere in the game...
for _, descendant in game:GetDescendants() do
	if descendant:IsA("Sound") then
		claim(descendant)
	end
end

-- ...and every one created afterwards (music tracks, weather ambience,
-- notification pops, etc. are all created dynamically at runtime).
game.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Sound") then
		claim(descendant)
	end
end)

-- Server tells us our saved (or default) volume on join, on respawn, and
-- whenever the `volume` command is run. Percent (0-100) -> Sound.Volume scale (0.0-1.0).
CommandRemotes.VolumeSet.OnClientEvent:Connect(function(volumePercent: number)
	if typeof(volumePercent) ~= "number" then return end
	currentVolume01   = math.clamp(volumePercent, 0, 100) / 100
	masterGroup.Volume = currentVolume01
end)
