local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local Camera      = workspace.CurrentCamera

local rng = Random.new()

-- Tuning knobs — kept moderate per the design brief ("do not completely
-- blind the player").
local FADE_IN_TIME    = 1.0
local FADE_OUT_TIME   = 1.2
local BLUR_SIZE       = 9
local DESATURATION    = -0.35   -- ColorCorrectionEffect.Saturation, -1 = grayscale
local SHAKE_AMPLITUDE = 0.006   -- constant subtle shake
local SWAY_AMPLITUDE  = 0.028   -- occasional bigger sway on top of the shake
local SWAY_INTERVAL   = { 2.5, 5.0 }
local SWAY_TIME        = 0.9
local DARK_FLASH_INTERVAL = { 4, 9 }
local DARK_FLASH_TRANSPARENCY = 0.55  -- how dark the split-second flash gets
local TINNITUS_VOLUME = 0.35

local function tw(obj, t, props, style, dir)
	style = style or Enum.EasingStyle.Quad
	dir   = dir   or Enum.EasingDirection.Out
	TweenService:Create(obj, TweenInfo.new(t, style, dir), props):Play()
end

-- Only one concussion effect instance can ever be alive at a time for this
-- client (state below). Re-applying while active just refreshes the timer
-- instead of building a second copy — see applyConcussion.
local state = nil :: {
	gui: ScreenGui,
	blur: BlurEffect,
	colorCorrection: ColorCorrectionEffect,
	sound: Sound,
	swayOffset: CFrame,
	token: number,
}?

-- Smoothly walks `state.swayOffset` toward `target` over `time` seconds
-- without blocking, so the constant shake loop can keep layering on top of it.
local function swayTo(myState, target: CFrame, time: number)
	task.spawn(function()
		local start = myState.swayOffset
		local steps = math.max(1, math.floor(time * 30))
		for i = 1, steps do
			if state ~= myState then return end
			myState.swayOffset = start:Lerp(target, i / steps)
			task.wait(time / steps)
		end
	end)
end

local function buildEffect(): typeof(state)
	local gui = Instance.new("ScreenGui")
	gui.Name           = "ConcussionEffect"
	gui.DisplayOrder   = 95
	gui.ResetOnSpawn   = false  -- respawn cleanup is handled explicitly below
	gui.IgnoreGuiInset = true
	gui.Parent         = PlayerGui

	local darkFrame = Instance.new("Frame")
	darkFrame.Name                   = "DarkFlash"
	darkFrame.Size                   = UDim2.new(1, 0, 1, 0)
	darkFrame.BackgroundColor3       = Color3.new(0, 0, 0)
	darkFrame.BackgroundTransparency = 1
	darkFrame.BorderSizePixel        = 0
	darkFrame.ZIndex                 = 5
	darkFrame.Parent                 = gui

	local blur = Instance.new("BlurEffect")
	blur.Size   = 0
	blur.Parent = Lighting

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Saturation = 0
	colorCorrection.Parent    = Lighting

	local sound = Instance.new("Sound")
	sound.Name              = "ConcussionTinnitus"
	sound.SoundId            = "rbxassetid://9069161602"
	sound.Looped             = true
	sound.Volume             = 0
	sound.RollOffMaxDistance = 0
	sound.Parent             = SoundService
	sound:Play()

	return {
		gui             = gui,
		blur            = blur,
		colorCorrection = colorCorrection,
		sound           = sound,
		darkFrame       = darkFrame,
		swayOffset      = CFrame.new(),
		token           = 0,
		shakeConn       = nil :: RBXScriptConnection?,
	} :: any
end

-- Tears down every effect resource, including the RenderStepped shake
-- connection — always routed through here so no path can leak it, whether
-- teardown happens via the normal end-of-duration timer or a hard respawn
-- stop. `animated` controls whether we tween out first or cut instantly.
local function teardown(myState, animated: boolean)
	if myState.shakeConn then
		myState.shakeConn:Disconnect()
		myState.shakeConn = nil
	end

	if animated then
		tw(myState.blur,            FADE_OUT_TIME, { Size = 0 })
		tw(myState.colorCorrection, FADE_OUT_TIME, { Saturation = 0 })
		tw(myState.sound,           FADE_OUT_TIME, { Volume = 0 }, Enum.EasingStyle.Linear)
		tw(myState.darkFrame,       FADE_OUT_TIME, { BackgroundTransparency = 1 })
		task.delay(FADE_OUT_TIME + 0.1, function()
			myState.gui:Destroy()
			myState.blur:Destroy()
			myState.colorCorrection:Destroy()
			myState.sound:Destroy()
		end)
	else
		myState.gui:Destroy()
		myState.blur:Destroy()
		myState.colorCorrection:Destroy()
		myState.sound:Destroy()
	end
end

-- All three loops below key off object identity (`state == myState`), NOT
-- the refresh token — a duration refresh (concussion re-applied while
-- already active) only bumps the token so the *end* timer restarts; these
-- ambient loops should keep running uninterrupted across a refresh.
local function runLoops(myState)
	-- Constant subtle shake + whatever sway offset is currently active.
	-- Stored on myState so teardown() can always find and disconnect it,
	-- regardless of which code path (duration end vs. respawn) tears down.
	myState.shakeConn = RunService.RenderStepped:Connect(function()
		if state ~= myState then return end
		local rx = (rng:NextNumber() * 2 - 1) * SHAKE_AMPLITUDE
		local ry = (rng:NextNumber() * 2 - 1) * SHAKE_AMPLITUDE * 0.6
		Camera.CFrame = Camera.CFrame * myState.swayOffset * CFrame.Angles(rx, ry, 0)
	end)

	-- Occasional bigger sway, simulating a dizzy lean to one side and back.
	task.spawn(function()
		while state == myState do
			task.wait(rng:NextNumber() * (SWAY_INTERVAL[2] - SWAY_INTERVAL[1]) + SWAY_INTERVAL[1])
			if state ~= myState then break end
			local rx = (rng:NextNumber() * 2 - 1) * SWAY_AMPLITUDE
			local ry = (rng:NextNumber() * 2 - 1) * SWAY_AMPLITUDE
			swayTo(myState, CFrame.Angles(rx, ry, 0), SWAY_TIME)
			task.wait(SWAY_TIME)
			if state ~= myState then break end
			swayTo(myState, CFrame.new(), SWAY_TIME)
		end
	end)

	-- Occasional split-second darkening to simulate disorientation.
	task.spawn(function()
		while state == myState do
			task.wait(rng:NextNumber() * (DARK_FLASH_INTERVAL[2] - DARK_FLASH_INTERVAL[1]) + DARK_FLASH_INTERVAL[1])
			if state ~= myState then break end
			myState.darkFrame.BackgroundTransparency = 1 - DARK_FLASH_TRANSPARENCY
			tw(myState.darkFrame, 0.35, { BackgroundTransparency = 1 })
		end
	end)

end

-- Applies (or refreshes) the concussion effect for `duration` seconds. The
-- server drives the actual WalkSpeed reduction; this is the visual/audio side
-- only, and it is entirely local so nothing here is visible to other players.
local function applyConcussion(duration: number)
	if state then
		-- Already concussed: bump the token so the previous end-timer becomes
		-- a no-op, then start a fresh one — this is the "refresh" behaviour,
		-- no rebuilding of the GUI/sound/camera hooks needed.
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

	tw(myState.blur,            FADE_IN_TIME, { Size = BLUR_SIZE })
	tw(myState.colorCorrection, FADE_IN_TIME, { Saturation = DESATURATION })
	tw(myState.sound,           FADE_IN_TIME, { Volume = TINNITUS_VOLUME }, Enum.EasingStyle.Linear)

	runLoops(myState)

	local myToken = myState.token
	task.delay(duration, function()
		if state == myState and myState.token == myToken then
			teardown(myState, true)
			state = nil
		end
	end)
end

-- Hard-stops everything immediately (no fade) — used on respawn, where the
-- lingering camera offset / GUI would otherwise carry over to the new life.
local function hardStopConcussion()
	if not state then return end
	local myState = state
	state = nil
	teardown(myState, false)
end

LocalPlayer.CharacterAdded:Connect(hardStopConcussion)

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

if CommandRemotes.Concussion then
	CommandRemotes.Concussion.OnClientEvent:Connect(function(duration: number)
		if typeof(duration) ~= "number" or duration <= 0 then return end
		applyConcussion(duration)
	end)
end
