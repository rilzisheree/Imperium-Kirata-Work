local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local SOUND_NAME = "AdminMusicTrack"

local localCycleEnabled = false
local localCurrentId    = nil   -- ID of the track this client is currently playing

local function getSound(): Sound?
	local s = SoundService:FindFirstChild(SOUND_NAME)
	return (s and s:IsA("Sound")) and s or nil
end

local function stopMusic()
	local s = getSound()
	if s then s:Stop(); s:Destroy() end
	localCurrentId = nil
end

-- Create a new Sound, hook its Ended event for auto-cycle, and play it.
local function playMusic(id: string, volume: number)
	stopMusic()
	localCurrentId = id
	local s = Instance.new("Sound")
	s.Name               = SOUND_NAME
	s.SoundId            = "rbxassetid://" .. id
	s.Volume             = math.clamp(volume, 0, 1)
	s.Looped             = not localCycleEnabled  -- loop when cycle is off; end naturally when cycle is on
	s.RollOffMaxDistance = 0
	s.Parent             = SoundService
	s:Play()

	-- When the track finishes naturally (cycle on, so Looped = false), report to
	-- the server so it can pick the next track in the same genre.
	s.Ended:Connect(function()
		if localCycleEnabled and localCurrentId == id then
			CommandRemotes.MusicCommand:FireServer("ended", id)
		end
	end)
end

-- Server broadcasts a new track (from the `music <id>` command or menu click).
CommandRemotes.MusicPlay.OnClientEvent:Connect(function(id: string, volume: number)
	if typeof(id) ~= "string" or id == "" then return end
	volume = typeof(volume) == "number" and volume or 1
	playMusic(id, volume)
end)

-- Server broadcasts a stop (Stop Music button or `stop` action).
CommandRemotes.MusicStop.OnClientEvent:Connect(function()
	stopMusic()
end)

-- Server sends current track to players who join while music is playing.
CommandRemotes.MusicSync.OnClientEvent:Connect(function(id: string, volume: number, cycleState: boolean)
	if typeof(id) ~= "string" or id == "" then return end
	volume = typeof(volume) == "number" and volume or 1
	-- Only start if we aren't already playing the same track.
	local s = getSound()
	if s and s.IsPlaying and localCurrentId == id then return end
	if typeof(cycleState) == "boolean" then
		localCycleEnabled = cycleState
	end
	playMusic(id, volume)
end)

-- Server broadcasts a volume change (slider in menu).
-- Updates .Volume on the existing sound without restarting the track.
CommandRemotes.MusicVolume.OnClientEvent:Connect(function(volume: number)
	if typeof(volume) ~= "number" then return end
	local s = getSound()
	if s then s.Volume = math.clamp(volume, 0, 1) end
end)

-- Server broadcasts a seek position in seconds.
CommandRemotes.MusicSeek.OnClientEvent:Connect(function(position: number)
	if typeof(position) ~= "number" then return end
	local s = getSound()
	if s then s.TimePosition = math.max(0, position) end
end)

-- Server broadcasts cycle state changes (toggle in menu).
-- Also flips Looped on the active sound so the behaviour takes effect immediately.
CommandRemotes.MusicCycleState.OnClientEvent:Connect(function(state: boolean)
	if typeof(state) == "boolean" then
		localCycleEnabled = state
		local s = getSound()
		if s then
			s.Looped = not state
		end
	end
end)
