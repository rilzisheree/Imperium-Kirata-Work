local DataStoreService = game:GetService("DataStoreService")

local VolumeManager = {}

local DS_KEY_PREFIX = "player_"
local DEFAULT_VOLUME = 100
local ds = DataStoreService:GetDataStore("PlayerVolumes_v1")

-- In-memory table keyed by userId (number) -> volume percent (0-100)
local playerVolumes = {}   -- [userId] = 0-100

local function loadVolume(userId: number): number
	local ok, result = pcall(function()
		return ds:GetAsync(DS_KEY_PREFIX .. userId)
	end)
	if ok and type(result) == "number" then
		return math.clamp(math.round(result), 0, 100)
	end
	return DEFAULT_VOLUME
end

local function saveVolume(userId: number, volume: number)
	pcall(function()
		ds:SetAsync(DS_KEY_PREFIX .. userId, volume)
	end)
end

function VolumeManager.onPlayerAdded(player: Player)
	playerVolumes[player.UserId] = loadVolume(player.UserId)
end

function VolumeManager.onPlayerRemoving(player: Player)
	playerVolumes[player.UserId] = nil
end

function VolumeManager.getVolume(userId: number): number
	return playerVolumes[userId] or DEFAULT_VOLUME
end

-- Command handler already checks the range; this clamp/round is just the
-- same safety net loadVolume applies to whatever DataStore hands back.
function VolumeManager.setVolume(userId: number, rawVolume: number): number
	local volume = math.clamp(math.round(rawVolume), 0, 100)
	playerVolumes[userId] = volume
	task.spawn(saveVolume, userId, volume)
	return volume
end

return VolumeManager
