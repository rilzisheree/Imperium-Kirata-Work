--[[
	RainClient.client.lua
	Personal rain emitter: a small Part follows the local player's camera
	position so raindrops always fall through the player's view, regardless
	of where they are on the map.

	Activates on Rain / Storm weather via WeatherSync remote (same event
	WeatherMenu already uses). Does NOT conflict with the server emitter —
	the server emitter covers the world map; this one covers the player's
	personal view.
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LP             = Players.LocalPlayer
local Camera         = Workspace.CurrentCamera
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))
local activeWeatherValue = ReplicatedStorage:WaitForChild("ActiveWeather", 10) :: StringValue?

-- ── Constants ──────────────────────────────────────────────────────────────
-- Emitter floats EMITTER_HEIGHT studs above the camera. EMITTER_SIZE gives
-- the coverage footprint — wide enough to fill the screen with drops.
local EMITTER_HEIGHT = 50
local EMITTER_SIZE   = 80

-- Which weather names trigger personal rain
local RAIN_WEATHERS = { Rain = true, Storm = true }

-- ── Particle presets (keyed by weather name) ──────────────────────────────
-- Three layers per preset matching WeatherServer, but tuned for close-range
-- personal view: shorter lifetime (drops only need to fall ~50 studs),
-- slightly higher rate so the screen looks dense.

local PARTICLE_DEFS = {

	Rain = {
		-- Layer 1 — visible foreground drops
		{
			Texture           = "rbxassetid://241868005",
			Color             = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   Color3.fromRGB(145, 185, 230)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 168, 218)),
				ColorSequenceKeypoint.new(1,   Color3.fromRGB(110, 150, 205)),
			}),
			Size              = NumberSequence.new({
				NumberSequenceKeypoint.new(0,    0.16),
				NumberSequenceKeypoint.new(0.12, 0.13),
				NumberSequenceKeypoint.new(0.85, 0.10),
				NumberSequenceKeypoint.new(1,    0.00),
			}),
			Transparency      = NumberSequence.new({
				NumberSequenceKeypoint.new(0,    0.28),
				NumberSequenceKeypoint.new(0.55, 0.50),
				NumberSequenceKeypoint.new(0.88, 0.82),
				NumberSequenceKeypoint.new(1,    1.00),
			}),
			Squash            = NumberSequence.new(4),
			Orientation       = Enum.ParticleOrientation.VelocityParallel,
			SpreadAngle       = Vector2.new(3, 0),
			Speed             = NumberRange.new(78, 108),
			Rotation          = NumberRange.new(0, 0),
			RotSpeed          = NumberRange.new(0, 0),
			Rate              = 600,
			Lifetime          = NumberRange.new(0.5, 0.9),
			EmissionDirection = Enum.NormalId.Bottom,
			LightInfluence    = 0.72,
			LightEmission     = 0,
		},
		-- Layer 2 — dense curtain
		{
			Texture           = "rbxassetid://241868005",
			Color             = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   Color3.fromRGB(158, 195, 238)),
				ColorSequenceKeypoint.new(1,   Color3.fromRGB(128, 165, 222)),
			}),
			Size              = NumberSequence.new({
				NumberSequenceKeypoint.new(0,    0.07),
				NumberSequenceKeypoint.new(0.75, 0.05),
				NumberSequenceKeypoint.new(1,    0.00),
			}),
			Transparency      = NumberSequence.new({
				NumberSequenceKeypoint.new(0,    0.46),
				NumberSequenceKeypoint.new(0.60, 0.64),
				NumberSequenceKeypoint.new(1,    1.00),
			}),
			Squash            = NumberSequence.new(7),
			Orientation       = Enum.ParticleOrientation.VelocityParallel,
			SpreadAngle       = Vector2.new(4, 0),
			Speed             = NumberRange.new(92, 128),
			Rotation          = NumberRange.new(0, 0),
			RotSpeed          = NumberRange.new(0, 0),
			Rate              = 2600,
			Lifetime          = NumberRange.new(0.4, 0.75),
			EmissionDirection = Enum.NormalId.Bottom,
			LightInfluence    = 0.42,
			LightEmission     = 0,
		},
		-- Layer 3 — atmospheric mist
		{
			Texture           = "rbxassetid://241868005",
			Color             = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   Color3.fromRGB(130, 158, 195)),
				ColorSequenceKeypoint.new(1,   Color3.fromRGB(108, 135, 172)),
			}),
			Size              = NumberSequence.new({
				NumberSequenceKeypoint.new(0,   0.80),
				NumberSequenceKeypoint.new(0.4, 1.60),
				NumberSequenceKeypoint.new(1,   0.50),
			}),
			Transparency      = NumberSequence.new({
				NumberSequenceKeypoint.new(0,   0.78),
				NumberSequenceKeypoint.new(0.5, 0.72),
				NumberSequenceKeypoint.new(1,   1.00),
			}),
			Squash            = NumberSequence.new(1),
			Orientation       = Enum.ParticleOrientation.FacingCamera,
			SpreadAngle       = Vector2.new(0, 0),
			Speed             = NumberRange.new(5, 14),
			Rotation          = NumberRange.new(0, 360),
			RotSpeed          = NumberRange.new(-6, 6),
			Rate              = 45,
			Lifetime          = NumberRange.new(1.5, 3.0),
			EmissionDirection = Enum.NormalId.Bottom,
			LightInfluence    = 0.82,
			LightEmission     = 0,
		},
	},

	Storm = {
		-- Layer 1 — heavy foreground drops
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
				NumberSequenceKeypoint.new(0,    0.20),
				NumberSequenceKeypoint.new(0.55, 0.38),
				NumberSequenceKeypoint.new(0.88, 0.75),
				NumberSequenceKeypoint.new(1,    1.00),
			}),
			Squash            = NumberSequence.new(5),
			Orientation       = Enum.ParticleOrientation.VelocityParallel,
			SpreadAngle       = Vector2.new(6, 0),
			Speed             = NumberRange.new(108, 145),
			Rotation          = NumberRange.new(0, 0),
			RotSpeed          = NumberRange.new(0, 0),
			Rate              = 900,
			Lifetime          = NumberRange.new(0.4, 0.8),
			EmissionDirection = Enum.NormalId.Bottom,
			LightInfluence    = 0.68,
			LightEmission     = 0,
		},
		-- Layer 2 — torrent curtain
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
				NumberSequenceKeypoint.new(0,    0.38),
				NumberSequenceKeypoint.new(0.62, 0.56),
				NumberSequenceKeypoint.new(1,    1.00),
			}),
			Squash            = NumberSequence.new(8),
			Orientation       = Enum.ParticleOrientation.VelocityParallel,
			SpreadAngle       = Vector2.new(7, 0),
			Speed             = NumberRange.new(122, 162),
			Rotation          = NumberRange.new(0, 0),
			RotSpeed          = NumberRange.new(0, 0),
			Rate              = 4500,
			Lifetime          = NumberRange.new(0.35, 0.65),
			EmissionDirection = Enum.NormalId.Bottom,
			LightInfluence    = 0.38,
			LightEmission     = 0,
		},
		-- Layer 3 — storm mist
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
				NumberSequenceKeypoint.new(0,   0.72),
				NumberSequenceKeypoint.new(0.5, 0.66),
				NumberSequenceKeypoint.new(1,   1.00),
			}),
			Squash            = NumberSequence.new(1),
			Orientation       = Enum.ParticleOrientation.FacingCamera,
			SpreadAngle       = Vector2.new(0, 0),
			Speed             = NumberRange.new(10, 24),
			Rotation          = NumberRange.new(0, 360),
			RotSpeed          = NumberRange.new(-10, 10),
			Rate              = 55,
			Lifetime          = NumberRange.new(1.2, 2.5),
			EmissionDirection = Enum.NormalId.Bottom,
			LightInfluence    = 0.78,
			LightEmission     = 0,
		},
	},
}

-- ── Emitter part (local, not replicated) ─────────────────────────────────
local emitterPart = Instance.new("Part")
emitterPart.Name         = "LocalRainEmitter"
emitterPart.Size         = Vector3.new(EMITTER_SIZE, 1, EMITTER_SIZE)
emitterPart.Anchored     = true
emitterPart.CanCollide   = false
emitterPart.CanQuery     = false
emitterPart.CanTouch     = false
emitterPart.Transparency = 1
emitterPart.CastShadow   = false
emitterPart.Parent       = Workspace

-- ── Emitter management ────────────────────────────────────────────────────
local PARTICLE_PROPS = {
	"Color", "Size", "Transparency",
	"Speed", "Rotation", "RotSpeed",
	"Rate", "Lifetime", "EmissionDirection",
	"LightInfluence", "LightEmission",
	"Squash", "Orientation", "SpreadAngle",
}

local activeEmitters = {}

local function clearEmitters()
	for _, pe in activeEmitters do
		pcall(function() pe:Destroy() end)
	end
	activeEmitters = {}
end

local function buildEmitters(weatherName)
	clearEmitters()
	local defs = PARTICLE_DEFS[weatherName]
	if not defs then return end
	for _, props in ipairs(defs) do
		local pe = Instance.new("ParticleEmitter")
		for _, key in PARTICLE_PROPS do
			if props[key] ~= nil then
				pcall(function() pe[key] = props[key] end)
			end
		end
		if props.Texture then pe.Texture = props.Texture end
		pe.Parent = emitterPart
		table.insert(activeEmitters, pe)
	end
end

local function setRain(weatherName)
	if RAIN_WEATHERS[weatherName] then
		buildEmitters(weatherName)
	else
		clearEmitters()
	end
end

-- ── Follow camera every frame ─────────────────────────────────────────────
RunService.Heartbeat:Connect(function()
	local cf = Camera.CFrame
	emitterPart.CFrame = CFrame.new(cf.Position + Vector3.new(0, EMITTER_HEIGHT, 0))
end)

-- ── Sync with weather state ───────────────────────────────────────────────
-- Apply current weather immediately on load
if activeWeatherValue then
	setRain(activeWeatherValue.Value)
	activeWeatherValue.Changed:Connect(function(val)
		setRain(val)
	end)
end

-- Also respond to live WeatherSync broadcasts
CommandRemotes.WeatherSync:OnClientEvent:Connect(function(weatherName)
	setRain(weatherName)
end)
