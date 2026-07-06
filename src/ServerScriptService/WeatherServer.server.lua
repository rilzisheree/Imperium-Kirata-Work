local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

-- ── permissions (mirrors CommandServer exactly) ───────────────────────────────
local IS_STUDIO = RunService:IsStudio()

local STAFF_IDS = {
	[1872507151] = "Owner",
}
local TIER_ORDER = { Helper = 1, Moderator = 2, Admin = 3, Owner = 4 }

local function getTier(player)
	if IS_STUDIO then return "Owner" end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return "Owner"
	end
	return STAFF_IDS[player.UserId]
end

local function hasPermission(player, required)
	local tier = getTier(player)
	if not tier then return false end
	return (TIER_ORDER[tier] or 0) >= (TIER_ORDER[required] or 99)
end

-- ── world instances ────────────────────────────────────────────────────────────
-- Ensure Atmosphere exists in Lighting
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end

-- Ensure Clouds exist in Terrain
local terrain = Workspace:FindFirstChildOfClass("Terrain")
local clouds  = terrain and terrain:FindFirstChildOfClass("Clouds")
if terrain and not clouds then
	clouds = Instance.new("Clouds")
	clouds.Parent = terrain
end

-- Weather FX folder (holds emitter part + ambient sound)
local fxFolder = Workspace:FindFirstChild("WeatherFX")
if not fxFolder then
	fxFolder        = Instance.new("Folder")
	fxFolder.Name   = "WeatherFX"
	fxFolder.Parent = Workspace
end

-- Large invisible part positioned above the play area for particle emitters
local emitterPart = Instance.new("Part")
emitterPart.Name         = "WeatherEmitter"
emitterPart.Size         = Vector3.new(2048, 1, 2048)
emitterPart.CFrame       = CFrame.new(0, 150, 0)
emitterPart.Anchored     = true
emitterPart.CanCollide   = false
emitterPart.Transparency = 1
emitterPart.CastShadow   = false
emitterPart.Parent       = fxFolder

-- Looped ambient sound; parented to Workspace so it replicates to all clients
local weatherSound        = Instance.new("Sound")
weatherSound.Name         = "WeatherAmbient"
weatherSound.Looped       = true
weatherSound.Volume       = 0.5
weatherSound.RollOffMaxDistance = 1e6
weatherSound.Parent       = fxFolder

-- ── presets ────────────────────────────────────────────────────────────────────
--  soundId   = 0 means no sound; replace with a valid rbxassetid number.
--  particles = list of ParticleEmitter property tables; Texture accepts
--              an rbxassetid:// string — swap in owned assets for best visuals.

local PRESETS = {
	Clear = {
		lighting = {
			Ambient        = Color3.fromRGB( 70,  70,  70),
			OutdoorAmbient = Color3.fromRGB(140, 140, 140),
			Brightness     = 2.5,
			FogEnd         = 100000,
			FogStart       = 0,
			FogColor       = Color3.fromRGB(191, 191, 191),
		},
		atmosphere = {
			Density = 0.12,
			Offset  = 0.25,
			Color   = Color3.fromRGB(199, 199, 199),
			Decay   = Color3.fromRGB(106, 127, 139),
			Glare   = 0.2,
			Haze    = 2,
		},
		clouds    = { Cover = 0.2,  Density = 0.3,  Color = Color3.fromRGB(235, 235, 235) },
		soundId   = 0,
		particles = {},
	},

	Rain = {
		lighting = {
			Ambient        = Color3.fromRGB( 50,  58,  72),
			OutdoorAmbient = Color3.fromRGB( 75,  88, 105),
			Brightness     = 0.75,
			FogEnd         = 1400,
			FogStart       = 0,
			FogColor       = Color3.fromRGB(145, 158, 175),
		},
		atmosphere = {
			Density = 0.55,
			Offset  = 0,
			Color   = Color3.fromRGB(110, 128, 155),
			Decay   = Color3.fromRGB( 55,  65,  80),
			Glare   = 0,
			Haze    = 18,
		},
		clouds    = { Cover = 0.9,  Density = 0.75, Color = Color3.fromRGB(140, 148, 165) },
		soundId   = 0,  -- replace: rain ambient
		particles = {
			{
				Color             = ColorSequence.new(Color3.fromRGB(170, 210, 255)),
				Size              = NumberSequence.new(0.06),
				Transparency      = NumberSequence.new(0.4),
				Speed             = NumberRange.new(55, 70),
				Rotation          = NumberRange.new(90, 90),
				RotSpeed          = NumberRange.new(0, 0),
				Rate              = 350,
				Lifetime          = NumberRange.new(1.0, 1.5),
				EmissionDirection = Enum.NormalId.Bottom,
				LightInfluence    = 1,
				LightEmission     = 0,
			},
		},
	},

	Storm = {
		lighting = {
			Ambient        = Color3.fromRGB( 28,  30,  42),
			OutdoorAmbient = Color3.fromRGB( 48,  52,  70),
			Brightness     = 0.4,
			FogEnd         = 700,
			FogStart       = 0,
			FogColor       = Color3.fromRGB( 90,  95, 110),
		},
		atmosphere = {
			Density = 0.70,
			Offset  = 0,
			Color   = Color3.fromRGB( 80,  88, 105),
			Decay   = Color3.fromRGB( 40,  45,  58),
			Glare   = 0,
			Haze    = 25,
		},
		clouds    = { Cover = 1,    Density = 0.9,  Color = Color3.fromRGB( 70,  72,  85) },
		soundId   = 0,  -- replace: thunder/storm
		particles = {
			{
				Color             = ColorSequence.new(Color3.fromRGB(155, 195, 255)),
				Size              = NumberSequence.new(0.07),
				Transparency      = NumberSequence.new(0.35),
				Speed             = NumberRange.new(80, 105),
				Rotation          = NumberRange.new(90, 90),
				RotSpeed          = NumberRange.new(0, 0),
				Rate              = 600,
				Lifetime          = NumberRange.new(0.8, 1.2),
				EmissionDirection = Enum.NormalId.Bottom,
				LightInfluence    = 1,
				LightEmission     = 0,
			},
		},
	},

	Fog = {
		lighting = {
			Ambient        = Color3.fromRGB( 95,  95,  95),
			OutdoorAmbient = Color3.fromRGB(105, 105, 105),
			Brightness     = 0.9,
			FogEnd         = 180,
			FogStart       = 8,
			FogColor       = Color3.fromRGB(185, 185, 185),
		},
		atmosphere = {
			Density = 0.90,
			Offset  = 0,
			Color   = Color3.fromRGB(180, 180, 182),
			Decay   = Color3.fromRGB(130, 130, 132),
			Glare   = 0,
			Haze    = 45,
		},
		clouds    = { Cover = 0.55, Density = 0.5,  Color = Color3.fromRGB(210, 210, 210) },
		soundId   = 0,  -- replace: eerie ambient
		particles = {},
	},

	Snow = {
		lighting = {
			Ambient        = Color3.fromRGB(130, 145, 170),
			OutdoorAmbient = Color3.fromRGB(185, 195, 215),
			Brightness     = 2.0,
			FogEnd         = 900,
			FogStart       = 0,
			FogColor       = Color3.fromRGB(215, 220, 230),
		},
		atmosphere = {
			Density = 0.35,
			Offset  = 0,
			Color   = Color3.fromRGB(195, 205, 225),
			Decay   = Color3.fromRGB(165, 175, 195),
			Glare   = 0.05,
			Haze    = 10,
		},
		clouds    = { Cover = 0.85, Density = 0.65, Color = Color3.fromRGB(225, 228, 238) },
		soundId   = 0,  -- replace: winter wind
		particles = {
			{
				Color             = ColorSequence.new(Color3.fromRGB(240, 245, 255)),
				Size              = NumberSequence.new{
					NumberSequenceKeypoint.new(0,   0.15),
					NumberSequenceKeypoint.new(1,   0.05),
				},
				Transparency      = NumberSequence.new{
					NumberSequenceKeypoint.new(0,   0.1),
					NumberSequenceKeypoint.new(1,   0.8),
				},
				Speed             = NumberRange.new(8, 18),
				Rotation          = NumberRange.new(0, 360),
				RotSpeed          = NumberRange.new(-45, 45),
				Rate              = 80,
				Lifetime          = NumberRange.new(4, 8),
				EmissionDirection = Enum.NormalId.Bottom,
				LightInfluence    = 0.9,
				LightEmission     = 0.1,
			},
		},
	},

	Sandstorm = {
		lighting = {
			Ambient        = Color3.fromRGB(130, 100,  55),
			OutdoorAmbient = Color3.fromRGB(170, 130,  65),
			Brightness     = 0.7,
			FogEnd         = 350,
			FogStart       = 0,
			FogColor       = Color3.fromRGB(190, 148,  80),
		},
		atmosphere = {
			Density = 0.78,
			Offset  = 0,
			Color   = Color3.fromRGB(195, 152,  80),
			Decay   = Color3.fromRGB(120,  88,  40),
			Glare   = 0,
			Haze    = 32,
		},
		clouds    = { Cover = 0.35, Density = 0.3,  Color = Color3.fromRGB(175, 138,  75) },
		soundId   = 0,  -- replace: wind/sand howl
		particles = {
			{
				Color             = ColorSequence.new{
					ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 170,  90)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 140,  65)),
				},
				Size              = NumberSequence.new{
					NumberSequenceKeypoint.new(0,   0.30),
					NumberSequenceKeypoint.new(1,   0.80),
				},
				Transparency      = NumberSequence.new{
					NumberSequenceKeypoint.new(0,   0.50),
					NumberSequenceKeypoint.new(0.5, 0.20),
					NumberSequenceKeypoint.new(1,   0.80),
				},
				Speed             = NumberRange.new(35, 60),
				Rotation          = NumberRange.new(0, 360),
				RotSpeed          = NumberRange.new(-30, 30),
				Rate              = 200,
				Lifetime          = NumberRange.new(2, 4),
				EmissionDirection = Enum.NormalId.Bottom,
				LightInfluence    = 1,
				LightEmission     = 0,
			},
		},
	},

	Wind = {
		lighting = {
			Ambient        = Color3.fromRGB( 80,  80,  80),
			OutdoorAmbient = Color3.fromRGB(130, 132, 130),
			Brightness     = 1.4,
			FogEnd         = 6000,
			FogStart       = 0,
			FogColor       = Color3.fromRGB(185, 185, 185),
		},
		atmosphere = {
			Density = 0.22,
			Offset  = 0.1,
			Color   = Color3.fromRGB(185, 185, 182),
			Decay   = Color3.fromRGB(100, 100,  98),
			Glare   = 0.1,
			Haze    = 6,
		},
		clouds    = { Cover = 0.6,  Density = 0.5,  Color = Color3.fromRGB(205, 205, 208) },
		soundId   = 0,  -- replace: wind sound
		particles = {
			{
				Color             = ColorSequence.new{
					ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 155, 100)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 105,  65)),
				},
				Size              = NumberSequence.new{
					NumberSequenceKeypoint.new(0,   0.20),
					NumberSequenceKeypoint.new(0.5, 0.35),
					NumberSequenceKeypoint.new(1,   0.10),
				},
				Transparency      = NumberSequence.new{
					NumberSequenceKeypoint.new(0,   0.70),
					NumberSequenceKeypoint.new(0.3, 0.20),
					NumberSequenceKeypoint.new(1,   0.90),
				},
				Speed             = NumberRange.new(20, 45),
				Rotation          = NumberRange.new(0, 360),
				RotSpeed          = NumberRange.new(-90, 90),
				Rate              = 50,
				Lifetime          = NumberRange.new(2, 5),
				EmissionDirection = Enum.NormalId.Bottom,
				LightInfluence    = 1,
				LightEmission     = 0,
			},
		},
	},
}

-- ── persistent state value (clients read this on load) ───────────────────────
-- Stored in ReplicatedStorage so any joining client can read the active weather
-- without relying on timing or a broadcast remote.
local activeWeatherValue = Instance.new("StringValue")
activeWeatherValue.Name   = "ActiveWeather"
activeWeatherValue.Value  = ""
activeWeatherValue.Parent = ReplicatedStorage

-- ── internal state ─────────────────────────────────────────────────────────────
local currentWeather = nil
local activeTweens   = {}

local TWEEN_INFO = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local PARTICLE_PROPS = {
	"Color", "Size", "Transparency",
	"Speed", "Rotation", "RotSpeed",
	"Rate", "Lifetime", "EmissionDirection",
	"LightInfluence", "LightEmission",
}

local function cancelActiveTweens()
	for _, t in activeTweens do
		pcall(function() t:Cancel() end)
	end
	activeTweens = {}
end

local function clearParticles()
	for _, v in emitterPart:GetChildren() do
		if v:IsA("ParticleEmitter") then v:Destroy() end
	end
end

local function createParticles(list)
	clearParticles()
	for _, props in ipairs(list or {}) do
		local pe = Instance.new("ParticleEmitter")
		for _, key in PARTICLE_PROPS do
			if props[key] ~= nil then
				pe[key] = props[key]
			end
		end
		if props.Texture then pe.Texture = props.Texture end
		pe.Parent = emitterPart
	end
end

local function applyWeather(weatherName)
	local preset = PRESETS[weatherName]
	if not preset then return end

	cancelActiveTweens()

	-- Tween Lighting
	local lt = TweenService:Create(Lighting, TWEEN_INFO, preset.lighting)
	lt:Play()
	table.insert(activeTweens, lt)

	-- Tween Atmosphere
	if atmosphere then
		local at = TweenService:Create(atmosphere, TWEEN_INFO, preset.atmosphere)
		at:Play()
		table.insert(activeTweens, at)
	end

	-- Tween Clouds
	if clouds and preset.clouds then
		local ct = TweenService:Create(clouds, TWEEN_INFO, preset.clouds)
		ct:Play()
		table.insert(activeTweens, ct)
	end

	-- Particles
	createParticles(preset.particles)

	-- Sound
	if preset.soundId and preset.soundId ~= 0 then
		weatherSound.SoundId = "rbxassetid://" .. tostring(preset.soundId)
		if not weatherSound.IsPlaying then
			weatherSound:Play()
		end
	else
		weatherSound:Stop()
	end

	currentWeather            = weatherName
	activeWeatherValue.Value  = weatherName

	-- Broadcast to all clients so menus update their highlight
	for _, player in Players:GetPlayers() do
		CommandRemotes.WeatherSync:FireClient(player, weatherName)
	end
end

-- ── remote handlers ────────────────────────────────────────────────────────────
CommandRemotes.WeatherApply.OnServerEvent:Connect(function(player, weatherName)
	if not hasPermission(player, "Admin") then return end
	if typeof(weatherName) ~= "string"    then return end
	if not PRESETS[weatherName]            then return end
	applyWeather(weatherName)
end)
