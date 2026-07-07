local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

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

-- Emitter part floats above the map centre. 1024×1024 covers a normal play
-- area without spreading particles too thin. y=200 gives enough fall height
-- (~2 seconds at average speed) for rain to look like it comes from the sky.
local emitterPart = Instance.new("Part")
emitterPart.Name         = "WeatherEmitter"
emitterPart.Size         = Vector3.new(1024, 1, 1024)
emitterPart.CFrame       = CFrame.new(0, 200, 0)
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

	Storm = {
		lighting = {
			Ambient        = Color3.fromRGB( 22,  25,  38),
			OutdoorAmbient = Color3.fromRGB( 40,  44,  62),
			Brightness     = 0.30,
			FogEnd         = 550,
			FogStart       = 0,
			FogColor       = Color3.fromRGB( 75,  80,  98),
		},
		atmosphere = {
			Density = 0.74,
			Offset  = 0,
			Color   = Color3.fromRGB( 68,  78,  98),
			Decay   = Color3.fromRGB( 32,  38,  52),
			Glare   = 0,
			Haze    = 30,
		},
		clouds    = { Cover = 1,    Density = 0.95, Color = Color3.fromRGB( 55,  58,  72) },
		soundId   = 1516791621,
		particles = {
			-- Layer 1: Heavy foreground drops — larger, more opaque, driven hard
			{
				Texture           = "rbxassetid://241868005",
				Color             = ColorSequence.new({
					ColorSequenceKeypoint.new(0,    Color3.fromRGB(132, 168, 218)),
					ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(115, 152, 208)),
					ColorSequenceKeypoint.new(1,    Color3.fromRGB( 98, 135, 195)),
				}),
				Size              = NumberSequence.new({
					NumberSequenceKeypoint.new(0,    0.18),
					NumberSequenceKeypoint.new(0.12, 0.15),
					NumberSequenceKeypoint.new(0.85, 0.12),
					NumberSequenceKeypoint.new(1,    0.00),
				}),
				Transparency      = NumberSequence.new({
					NumberSequenceKeypoint.new(0,    0.22),
					NumberSequenceKeypoint.new(0.55, 0.40),
					NumberSequenceKeypoint.new(0.88, 0.75),
					NumberSequenceKeypoint.new(1,    1.00),
				}),
				Squash            = NumberSequence.new(5),
				Orientation       = Enum.ParticleOrientation.VelocityParallel,
				SpreadAngle       = Vector2.new(6, 0),
				Speed             = NumberRange.new(108, 145),
				Rotation          = NumberRange.new(0, 0),
				RotSpeed          = NumberRange.new(0, 0),
				Rate              = 700,
				Lifetime          = NumberRange.new(1.3, 2.0),
				EmissionDirection = Enum.NormalId.Bottom,
				LightInfluence    = 0.68,
				LightEmission     = 0,
			},
			-- Layer 2: Dense torrent curtain — wall-of-rain feel
			{
				Texture           = "rbxassetid://241868005",
				Color             = ColorSequence.new({
					ColorSequenceKeypoint.new(0,   Color3.fromRGB(142, 178, 228)),
					ColorSequenceKeypoint.new(1,   Color3.fromRGB(112, 148, 212)),
				}),
				Size              = NumberSequence.new({
					NumberSequenceKeypoint.new(0,    0.08),
					NumberSequenceKeypoint.new(0.78, 0.06),
					NumberSequenceKeypoint.new(1,    0.00),
				}),
				Transparency      = NumberSequence.new({
					NumberSequenceKeypoint.new(0,    0.40),
					NumberSequenceKeypoint.new(0.62, 0.58),
					NumberSequenceKeypoint.new(1,    1.00),
				}),
				Squash            = NumberSequence.new(8),
				Orientation       = Enum.ParticleOrientation.VelocityParallel,
				SpreadAngle       = Vector2.new(7, 0),
				Speed             = NumberRange.new(122, 162),
				Rotation          = NumberRange.new(0, 0),
				RotSpeed          = NumberRange.new(0, 0),
				Rate              = 3800,
				Lifetime          = NumberRange.new(1.2, 1.8),
				EmissionDirection = Enum.NormalId.Bottom,
				LightInfluence    = 0.38,
				LightEmission     = 0,
			},
			-- Layer 3: Storm mist — thick churning haze
			{
				Texture           = "rbxassetid://241868005",
				Color             = ColorSequence.new({
					ColorSequenceKeypoint.new(0,   Color3.fromRGB(105, 128, 162)),
					ColorSequenceKeypoint.new(1,   Color3.fromRGB( 85, 105, 142)),
				}),
				Size              = NumberSequence.new({
					NumberSequenceKeypoint.new(0,   1.20),
					NumberSequenceKeypoint.new(0.4, 2.80),
					NumberSequenceKeypoint.new(1,   0.90),
				}),
				Transparency      = NumberSequence.new({
					NumberSequenceKeypoint.new(0,   0.74),
					NumberSequenceKeypoint.new(0.5, 0.68),
					NumberSequenceKeypoint.new(1,   1.00),
				}),
				Squash            = NumberSequence.new(1),
				Orientation       = Enum.ParticleOrientation.FacingCamera,
				SpreadAngle       = Vector2.new(0, 0),
				Speed             = NumberRange.new(10, 24),
				Rotation          = NumberRange.new(0, 360),
				RotSpeed          = NumberRange.new(-10, 10),
				Rate              = 55,
				Lifetime          = NumberRange.new(3.0, 5.5),
				EmissionDirection = Enum.NormalId.Bottom,
				LightInfluence    = 0.78,
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

-- Stored in ReplicatedStorage so any joining client can read the active weather
-- without relying on timing or a broadcast remote.
local activeWeatherValue = Instance.new("StringValue")
activeWeatherValue.Name   = "ActiveWeather"
activeWeatherValue.Value  = ""
activeWeatherValue.Parent = ReplicatedStorage

local currentWeather      = nil
local activeTweens        = {}
local clockTimeTween      = nil   -- separate tween so it doesn't cancel weather presets

local TWEEN_INFO = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local PARTICLE_PROPS = {
	"Color", "Size", "Transparency",
	"Speed", "Rotation", "RotSpeed",
	"Rate", "Lifetime", "EmissionDirection",
	"LightInfluence", "LightEmission",
	"Squash", "Orientation", "SpreadAngle",
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

local DEFAULTS = {
	lighting = {
		Brightness           = 2,
		ClockTime            = 14,
		ExposureCompensation = 0,
		ShadowSoftness       = 0.25,
		GeographicLatitude   = 41.7333,
		Ambient              = Color3.fromRGB( 70,  70,  70),
		OutdoorAmbient       = Color3.fromRGB(140, 140, 140),
		FogEnd               = 100000,
		FogStart             = 0,
		FogColor             = Color3.fromRGB(191, 191, 191),
	},
	atmosphere = {
		Density = 0,
		Offset  = 0,
		Color   = Color3.fromRGB(199, 199, 199),
		Decay   = Color3.fromRGB(106, 127, 139),
		Glare   = 0,
		Haze    = 0,
	},
	clouds = {
		Cover   = 0.5,
		Density = 0.5,
		Color   = Color3.fromRGB(235, 235, 235),
	},
}

local LIGHTING_NUM = {
	Brightness           = { min = 0,   max = 10  },
	ClockTime            = { min = 0,   max = 24  },
	ExposureCompensation = { min = -5,  max = 5   },
	ShadowSoftness       = { min = 0,   max = 1   },
	GeographicLatitude   = { min = -90, max = 90  },
	FogEnd               = { min = 0,   max = 1e6 },
	FogStart             = { min = 0,   max = 1e6 },
}
local LIGHTING_COLOR = { Ambient = true, OutdoorAmbient = true, FogColor = true }
local ATM_NUM   = {
	Density = { min = 0, max = 1   },
	Offset  = { min = 0, max = 1   },
	Haze    = { min = 0, max = 100 },
	Glare   = { min = 0, max = 10  },
}
local ATM_COLOR = { Color = true, Decay = true }
local CLD_NUM   = { Cover = { min = 0, max = 1 }, Density = { min = 0, max = 1 } }
local CLD_COLOR = { Color = true }

local savedAtmDensity = atmosphere and atmosphere.Density or 0.12
local savedCloudCover = clouds     and clouds.Cover       or 0.5

local POST_EFFECTS = {
	BloomEffect = true, SunRaysEffect = true,
	ColorCorrectionEffect = true, DepthOfFieldEffect = true,
}

CommandRemotes.WeatherApply.OnServerEvent:Connect(function(player, weatherName)
	if not hasPermission(player, "Admin") then return end
	if typeof(weatherName) ~= "string"    then return end
	if not PRESETS[weatherName]            then return end
	applyWeather(weatherName)
end)

-- Live property edit — client sliders send changes here
CommandRemotes.WeatherSetProp.OnServerEvent:Connect(function(player, target, prop, value)
	if not hasPermission(player, "Admin")    then return end
	if typeof(target) ~= "string"            then return end
	if typeof(prop)   ~= "string"            then return end

	if target == "Lighting" then
		local numInfo = LIGHTING_NUM[prop]
		if numInfo and typeof(value) == "number" then
			local clamped = math.clamp(value, numInfo.min, numInfo.max)
			if prop == "ClockTime" then
				-- Tween smoothly; speed is proportional to distance (up to ~10 s for a full 24-h sweep)
				local dist = math.abs(clamped - Lighting.ClockTime)
				if clockTimeTween then pcall(function() clockTimeTween:Cancel() end) end
				local dur = math.max(0.3, dist / 24 * 10)
				clockTimeTween = TweenService:Create(
					Lighting,
					TweenInfo.new(dur, Enum.EasingStyle.Linear),
					{ ClockTime = clamped }
				)
				clockTimeTween:Play()
			else
				Lighting[prop] = clamped
			end
		elseif LIGHTING_COLOR[prop] and typeof(value) == "Color3" then
			Lighting[prop] = value
		end

	elseif target == "Atmosphere" then
		if not atmosphere then return end
		local numInfo = ATM_NUM[prop]
		if numInfo and typeof(value) == "number" then
			atmosphere[prop] = math.clamp(value, numInfo.min, numInfo.max)
			if prop == "Density" then savedAtmDensity = atmosphere.Density end
		elseif ATM_COLOR[prop] and typeof(value) == "Color3" then
			atmosphere[prop] = value
		end

	elseif target == "Clouds" then
		if not clouds then return end
		local numInfo = CLD_NUM[prop]
		if numInfo and typeof(value) == "number" then
			clouds[prop] = math.clamp(value, numInfo.min, numInfo.max)
			if prop == "Cover" then savedCloudCover = clouds.Cover end
		elseif CLD_COLOR[prop] and typeof(value) == "Color3" then
			clouds[prop] = value
		end

	elseif target == "Particles" then
		if typeof(value) ~= "number" then return end
		if prop == "Rate" then
			local rate = math.clamp(value, 0, 2000)
			for _, e in emitterPart:GetChildren() do
				if e:IsA("ParticleEmitter") then e.Rate = rate end
			end
		elseif prop == "Speed" then
			local spd = math.clamp(value, 0, 200)
			for _, e in emitterPart:GetChildren() do
				if e:IsA("ParticleEmitter") then
					e.Speed = NumberRange.new(spd, spd * 1.3)
				end
			end
		end

	elseif target == "Sound" then
		if prop == "Volume" and typeof(value) == "number" then
			weatherSound.Volume = math.clamp(value, 0, 10)
		end
	end
end)

-- Restore Roblox default environment
CommandRemotes.WeatherReset.OnServerEvent:Connect(function(player)
	if not hasPermission(player, "Admin") then return end

	cancelActiveTweens()

	local t1 = TweenService:Create(Lighting, TWEEN_INFO, DEFAULTS.lighting)
	t1:Play()
	table.insert(activeTweens, t1)

	if atmosphere then
		local t2 = TweenService:Create(atmosphere, TWEEN_INFO, DEFAULTS.atmosphere)
		t2:Play()
		table.insert(activeTweens, t2)
		savedAtmDensity = DEFAULTS.atmosphere.Density
	end

	if clouds then
		local t3 = TweenService:Create(clouds, TWEEN_INFO, DEFAULTS.clouds)
		t3:Play()
		table.insert(activeTweens, t3)
		savedCloudCover = DEFAULTS.clouds.Cover
	end

	clearParticles()
	weatherSound:Stop()

	currentWeather           = nil
	activeWeatherValue.Value = ""

	for _, p in Players:GetPlayers() do
		CommandRemotes.WeatherSync:FireClient(p, "")
	end
end)

-- Toggle post-processing effects and world atmosphere/clouds
CommandRemotes.WeatherToggleEffect.OnServerEvent:Connect(function(player, effectName, enabled)
	if not hasPermission(player, "Admin") then return end
	if typeof(effectName) ~= "string"     then return end
	if typeof(enabled)    ~= "boolean"    then return end

	if effectName == "Atmosphere" then
		if not atmosphere then return end
		if enabled then
			atmosphere.Density = math.max(savedAtmDensity, 0.05)
		else
			savedAtmDensity    = atmosphere.Density
			atmosphere.Density = 0
		end

	elseif effectName == "Clouds" then
		if not clouds then return end
		if enabled then
			clouds.Cover = math.max(savedCloudCover, 0.1)
		else
			savedCloudCover = clouds.Cover
			clouds.Cover    = 0
		end

	elseif POST_EFFECTS[effectName] then
		local effect = Lighting:FindFirstChildOfClass(effectName)
		if enabled and not effect then
			effect        = Instance.new(effectName)
			effect.Parent = Lighting
		end
		if effect then
			effect.Enabled = enabled
		end
	end
end)
