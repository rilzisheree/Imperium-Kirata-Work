local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local GROUP_NAME = "MasterVolumeGroup"

-- Every Sound in the game gets parked in this group so one slider scales
-- music, weather, IMs, and notification pops together. Assigning SoundGroup
-- from a LocalScript is a local-only property change, so it never touches
-- other players' volume.
local masterGroup = SoundService:FindFirstChild(GROUP_NAME)
if not masterGroup then
	masterGroup = Instance.new("SoundGroup")
	masterGroup.Name   = GROUP_NAME
	masterGroup.Volume = 1
	masterGroup.Parent = SoundService
end

local function claimSound(sound: Sound)
	sound.SoundGroup = masterGroup
end

for _, descendant in game:GetDescendants() do
	if descendant:IsA("Sound") then
		claimSound(descendant)
	end
end

-- Music tracks, weather ambience, and notification pops are all created
-- on the fly, so keep claiming new Sounds as they show up.
game.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Sound") then
		claimSound(descendant)
	end
end)

-- Server pushes this on join, on respawn, and whenever `volume` is run.
CommandRemotes.VolumeSet.OnClientEvent:Connect(function(volumePercent: number)
	masterGroup.Volume = math.clamp(volumePercent, 0, 100) / 100
end)
