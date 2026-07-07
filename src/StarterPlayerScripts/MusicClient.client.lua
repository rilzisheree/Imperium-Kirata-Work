--[[
	MusicClient.client.lua
	Manages the single global music Sound instance for this player.
	Responds to server remotes: MusicPlay, MusicStop, MusicSync, MusicVolume.
	No UI — see MusicMenu.client.lua for the admin control panel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local SOUND_NAME = "AdminMusicTrack"

-- Remove any existing sound instance cleanly before creating a new one.
local function stopMusic()
	local s = SoundService:FindFirstChild(SOUND_NAME)
	if s and s:IsA("Sound") then
		s:Stop()
		s:Destroy()
	end
end

-- Stop current track (if any) and start the new one at the given volume.
local function playMusic(id: string, volume: number)
	stopMusic()
	local s = Instance.new("Sound")
	s.Name               = SOUND_NAME
	s.SoundId            = "rbxassetid://" .. id
	s.Volume             = math.clamp(volume, 0, 1)
	s.Looped             = true
	s.RollOffMaxDistance = 0
	s.Parent             = SoundService
	s:Play()
end

-- Server broadcasts a new track (from the `music <id>` command or menu click).
CommandRemotes.MusicPlay.OnClientEvent:Connect(function(id: string, volume: number)
	if typeof(id) ~= "string" or id == "" then return end
	volume = typeof(volume) == "number" and volume or 1
	playMusic(id, volume)
end)

-- Server broadcasts a stop (Stop Music button in menu).
CommandRemotes.MusicStop.OnClientEvent:Connect(function()
	stopMusic()
end)

-- Server sends current track to players who join while music is playing.
CommandRemotes.MusicSync.OnClientEvent:Connect(function(id: string, volume: number)
	if typeof(id) ~= "string" or id == "" then return end
	volume = typeof(volume) == "number" and volume or 1
	-- Only apply if we aren't already playing (avoids restarting mid-track on edge cases).
	local existing = SoundService:FindFirstChild(SOUND_NAME)
	if existing and existing:IsA("Sound") and existing.IsPlaying then return end
	playMusic(id, volume)
end)

-- Server broadcasts a volume change (from the menu slider).
-- Updates the existing sound's volume without restarting the track.
CommandRemotes.MusicVolume.OnClientEvent:Connect(function(volume: number)
	if typeof(volume) ~= "number" then return end
	local s = SoundService:FindFirstChild(SOUND_NAME)
	if s and s:IsA("Sound") then
		s.Volume = math.clamp(volume, 0, 1)
	end
end)
