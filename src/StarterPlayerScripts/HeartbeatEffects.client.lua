local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local SoundService      = game:GetService("SoundService")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local Camera      = workspace.CurrentCamera

local rng = Random.new()

local FADE_IN_TIME    = 1.0
local FADE_OUT_TIME   = 1.2

-- red vignette transparency levels
local VIG_BASE_TRANS  = 0.78   -- resting state after fade-in
local VIG_BEAT_TRANS  = 0.52   -- strong beat flash
local VIG_ECHO_TRANS  = 0.67   -- echo beat flash

local ACTIVE_BRIGHTNESS = -0.07
local ACTIVE_TINT       = Color3.new(1, 0.88, 0.88)

local BEAT_VOLUME_STRONG = 0.70
local BEAT_VOLUME_ECHO   = 0.38
local BEAT_REST_MIN      = 0.60   -- seconds between full lub-dub cycles
local BEAT_REST_MAX      = 0.90

local SHAKE_AMP = 0.004   -- small camera shake on the strong beat only

local function tw(obj, t, props, style, dir)
	style = style or Enum.EasingStyle.Quad
	dir   = dir   or Enum.EasingDirection.Out
	TweenService:Create(obj, TweenInfo.new(t, style, dir), props):Play()
end

-- only one instance can be alive at a time; re-applying refreshes the timer
local state = nil :: {
	gui:             ScreenGui,
	vigFrames:       { Frame },
	colorCorrection: ColorCorrectionEffect,
	sound:           Sound,
	token:           number,
}?

local function buildEffect(): typeof(state)
	local gui = Instance.new("ScreenGui")
	gui.Name           = "HeartbeatEffect"
	gui.DisplayOrder   = 96
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.Parent         = PlayerGui

	-- four red gradient frames radiating inward from each screen edge
	local vigFrames = {}
	local vigData = {
		{ UDim2.new(1, 0, 0.42, 0), UDim2.new(0, 0, 0,    0), 90  },
		{ UDim2.new(1, 0, 0.42, 0), UDim2.new(0, 0, 0.58, 0), 270 },
		{ UDim2.new(0.38, 0, 1, 0), UDim2.new(0, 0, 0,    0), 0   },
		{ UDim2.new(0.38, 0, 1, 0), UDim2.new(0.62, 0, 0, 0), 180 },
	}
	for _, data in vigData do
		local f = Instance.new("Frame")
		f.Size                   = data[1]
		f.Position               = data[2]
		f.BackgroundColor3       = Color3.fromRGB(180, 0, 0)
		f.BackgroundTransparency = 1
		f.BorderSizePixel        = 0
		f.ZIndex                 = 3
		f.Parent                 = gui

		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,    0),
			NumberSequenceKeypoint.new(0.50, 0.55),
			NumberSequenceKeypoint.new(1,    1),
		})
		g.Rotation = data[3]
		g.Parent   = f

		table.insert(vigFrames, f)
	end

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Brightness = 0
	colorCorrection.TintColor  = Color3.new(1, 1, 1)
	colorCorrection.Parent     = Lighting

	-- reuse the same heartbeat SFX asset used by AnxietyEffects
	local sound = Instance.new("Sound")
	sound.Name               = "HeartbeatSound"
	sound.SoundId            = "rbxassetid://7188240609"
	sound.Looped             = false
	sound.Volume             = 0
	sound.RollOffMaxDistance = 0
	sound.Parent             = SoundService

	return {
		gui             = gui,
		vigFrames       = vigFrames,
		colorCorrection = colorCorrection,
		sound           = sound,
		token           = 0,
	} :: any
end

local function teardown(myState, animated: boolean)
	if animated then
		for _, f in myState.vigFrames do
			tw(f, FADE_OUT_TIME, { BackgroundTransparency = 1 })
		end
		tw(myState.colorCorrection, FADE_OUT_TIME, {
			Brightness = 0,
			TintColor  = Color3.new(1, 1, 1),
		})
		tw(myState.sound, FADE_OUT_TIME, { Volume = 0 }, Enum.EasingStyle.Linear)
		task.delay(FADE_OUT_TIME + 0.1, function()
			myState.gui:Destroy()
			myState.colorCorrection:Destroy()
			myState.sound:Destroy()
		end)
	else
		myState.gui:Destroy()
		myState.colorCorrection:Destroy()
		myState.sound:Destroy()
	end
end

-- loops key off object identity (state == myState) so a token refresh never
-- restarts them — only the end-timer is bumped
local function runLoops(myState)
	-- lub-dub heartbeat loop
	task.spawn(function()
		while state == myState do
			-- strong beat (LUB)
			for _, f in myState.vigFrames do
				tw(f, 0.07, { BackgroundTransparency = VIG_BEAT_TRANS }, Enum.EasingStyle.Quad)
			end
			myState.sound.Volume = BEAT_VOLUME_STRONG
			myState.sound:Play()

			task.spawn(function()
				if state ~= myState then return end
				local rx = (rng:NextNumber() * 2 - 1) * SHAKE_AMP
				local ry = (rng:NextNumber() * 2 - 1) * SHAKE_AMP * 0.5
				Camera.CFrame = Camera.CFrame * CFrame.Angles(rx, ry, 0)
			end)

			task.wait(0.09)
			for _, f in myState.vigFrames do
				tw(f, 0.25, { BackgroundTransparency = VIG_BASE_TRANS }, Enum.EasingStyle.Quad)
			end
			task.wait(0.48 + rng:NextNumber() * 0.10)

			if state ~= myState then break end

			-- echo beat (DUB)
			for _, f in myState.vigFrames do
				tw(f, 0.06, { BackgroundTransparency = VIG_ECHO_TRANS }, Enum.EasingStyle.Quad)
			end
			myState.sound.Volume = BEAT_VOLUME_ECHO
			myState.sound:Play()

			task.wait(0.07)
			for _, f in myState.vigFrames do
				tw(f, 0.30, { BackgroundTransparency = VIG_BASE_TRANS }, Enum.EasingStyle.Quad)
			end

			task.wait(BEAT_REST_MIN + rng:NextNumber() * (BEAT_REST_MAX - BEAT_REST_MIN))
		end
	end)
end

local function applyHeartbeat(duration: number)
	if state then
		-- already active: bump token so the previous end-timer becomes a no-op,
		-- then start a fresh one — loops keep running uninterrupted
		state.token += 1
		local myToken = state.token
		task.delay(duration, function()
			if state and state.token == myToken then
				teardown(state, true)
				state = nil
			end
		end)
		return
	end

	local myState = buildEffect()
	state = myState

	for _, f in myState.vigFrames do
		tw(f, FADE_IN_TIME, { BackgroundTransparency = VIG_BASE_TRANS })
	end
	tw(myState.colorCorrection, FADE_IN_TIME, {
		Brightness = ACTIVE_BRIGHTNESS,
		TintColor  = ACTIVE_TINT,
	})

	runLoops(myState)

	local myToken = myState.token
	task.delay(duration, function()
		if state == myState and myState.token == myToken then
			teardown(myState, true)
			state = nil
		end
	end)
end

-- instant stop with no fade — used on respawn so tint and vignette don't
-- bleed into the new life
local function hardStopHeartbeat()
	if not state then return end
	local myState = state
	state = nil
	teardown(myState, false)
end

LocalPlayer.CharacterAdded:Connect(hardStopHeartbeat)

if CommandRemotes.Heartbeat then
	CommandRemotes.Heartbeat.OnClientEvent:Connect(function(duration: number)
		if typeof(duration) ~= "number" or duration <= 0 then return end
		applyHeartbeat(duration)
	end)
end
