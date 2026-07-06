--[[
        AnxietyEffects.client.lua
        LocalScript — StarterPlayerScripts
        Handles anxiety command visual + audio effects on the targeted player.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
local Camera      = workspace.CurrentCamera

local isRunning = false
local rng       = Random.new()

-- ── Level configuration ────────────────────────────────────────────────────────
--
-- vigTarget      : BackgroundTransparency the vignette frames tween TO
-- tint           : ColorCorrectionEffect.TintColor at full intensity
-- blur           : BlurEffect.Size at full intensity
-- shakeAmp       : Max camera rotation offset in radians per frame
-- msgCount       : {min, max} number of messages to show
-- msgInterval    : {min, max} seconds between messages
-- flickerChance  : Probability per flicker check that a screen dim flash occurs
-- blackFlash     : Whether to fire brief near-black screen moments (level 4+)
-- heartbeat      : Intensity of the vignette pulse (0–1 scale)
-- sfxVolume      : Heartbeat sound volume (0–1)
-- sfxPitch       : Heartbeat playback speed (higher = faster/higher-pitched)
-- beatRestMin/Max: Random rest range (seconds) between heartbeat double-pulses

local LEVEL = {
        [1] = {
                duration      = 1.5,
                vigTarget     = 0.82,
                tint          = Color3.new(1, 0.94, 0.94),
                blur          = 0,
                shakeAmp      = 0.002,
                msgCount      = { 4, 6 },
                msgInterval   = { 2.0, 3.5 },
                flickerChance = 0,
                blackFlash    = false,
                heartbeat     = 0.25,
                sfxVolume     = 0.25,
                sfxPitch      = 0.78,
                beatRestMin   = 1.4,
                beatRestMax   = 2.0,
        },
        [2] = {
                duration      = 2.5,
                vigTarget     = 0.72,
                tint          = Color3.new(1, 0.88, 0.88),
                blur          = 4,
                shakeAmp      = 0.005,
                msgCount      = { 8, 10 },
                msgInterval   = { 1.4, 2.5 },
                flickerChance = 0.08,
                blackFlash    = false,
                heartbeat     = 0.45,
                sfxVolume     = 0.45,
                sfxPitch      = 0.92,
                beatRestMin   = 1.1,
                beatRestMax   = 1.6,
        },
        [3] = {
                duration      = 3.5,
                vigTarget     = 0.62,
                tint          = Color3.new(1, 0.80, 0.80),
                blur          = 9,
                shakeAmp      = 0.009,
                msgCount      = { 12, 15 },
                msgInterval   = { 1.0, 2.0 },
                flickerChance = 0.15,
                blackFlash    = false,
                heartbeat     = 0.60,
                sfxVolume     = 0.62,
                sfxPitch      = 1.08,
                beatRestMin   = 0.80,
                beatRestMax   = 1.20,
        },
        [4] = {
                duration      = 4,
                vigTarget     = 0.50,
                tint          = Color3.new(1, 0.70, 0.70),
                blur          = 15,
                shakeAmp      = 0.014,
                msgCount      = { 18, 22 },
                msgInterval   = { 0.7, 1.5 },
                flickerChance = 0.25,
                blackFlash    = true,
                heartbeat     = 0.75,
                sfxVolume     = 0.80,
                sfxPitch      = 1.25,
                beatRestMin   = 0.55,
                beatRestMax   = 0.85,
        },
        [5] = {
                duration      = 4.5,
                vigTarget     = 0.38,
                tint          = Color3.new(1, 0.60, 0.60),
                blur          = 22,
                shakeAmp      = 0.020,
                msgCount      = { 30, 35 },
                msgInterval   = { 0.4, 0.9 },
                flickerChance = 0.40,
                blackFlash    = true,
                heartbeat     = 0.90,
                sfxVolume     = 1.0,
                sfxPitch      = 1.55,
                beatRestMin   = 0.35,
                beatRestMax   = 0.55,
        },
}

local MESSAGES = {
        "I'm scared...",
        "What is happening?",
        "Why can't I breathe?",
        "Something isn't right.",
        "I don't feel safe.",
        "Don't look behind you.",
        "They're watching.",
        "Why is everyone staring?",
        "Make it stop...",
        "I can't think.",
        "My heart...",
        "I need to leave.",
        "Why won't it end?",
        "Someone help me.",
        "I don't want to be here.",
        "Everything feels wrong.",
        "I hear something.",
        "It's getting closer.",
        "I can't move.",
        "Please wake up.",
        "Am I losing my mind?",
        "They're here.",
        "It's behind you.",
        "Don't turn around.",
        "You aren't alone.",
        "It's too late.",
}

-- ── Helpers ────────────────────────────────────────────────────────────────────

-- NOTE: Enum.EasingStyle.Expo does NOT exist in Roblox — use Exponential.
local function tw(obj, t, props, style, dir)
        style = style or Enum.EasingStyle.Exponential
        dir   = dir   or Enum.EasingDirection.Out
        TweenService:Create(obj, TweenInfo.new(t, style, dir), props):Play()
end

local function shuffle(t: { any }): { any }
        local copy = table.clone(t)
        local n    = #copy
        for i = n, 2, -1 do
                local j     = rng:NextInteger(1, i)
                copy[i], copy[j] = copy[j], copy[i]
        end
        return copy
end

-- ── Main effect ────────────────────────────────────────────────────────────────

local function runAnxiety(level: number)
        if isRunning then return end
        local cfg = LEVEL[level]
        if not cfg then return end
        isRunning = true

        -- ── Heartbeat sound ──────────────────────────────────────────────────
        -- Free Roblox heartbeat asset (change ID if you want a different sound)
        local heartSound = Instance.new("Sound")
        heartSound.SoundId       = "rbxassetid://7188240609"
        heartSound.Volume        = 0
        heartSound.PlaybackSpeed = cfg.sfxPitch
        heartSound.RollOffMaxDistance = 0
        heartSound.Parent        = SoundService

        -- ── ScreenGui ────────────────────────────────────────────────────────

        local gui = Instance.new("ScreenGui")
        gui.Name           = "AnxietyEffect"
        gui.DisplayOrder   = 97
        gui.ResetOnSpawn   = false
        gui.IgnoreGuiInset = true
        gui.Parent         = PlayerGui

        -- ── Vignette (4 gradient frames: top, bottom, left, right) ──────────

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
                f.BackgroundColor3       = Color3.new(0, 0, 0)
                f.BackgroundTransparency = 1
                f.BorderSizePixel        = 0
                f.ZIndex                 = 2
                f.Parent                 = gui

                local g = Instance.new("UIGradient")
                g.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0,    0),
                        NumberSequenceKeypoint.new(0.55, 0.5),
                        NumberSequenceKeypoint.new(1,    1),
                })
                g.Rotation = data[3]
                g.Parent   = f

                table.insert(vigFrames, f)
        end

        -- ── Black flash overlay (level 4+) ───────────────────────────────────

        local blackFrame = Instance.new("Frame")
        blackFrame.Size                   = UDim2.new(1, 0, 1, 0)
        blackFrame.BackgroundColor3       = Color3.new(0, 0, 0)
        blackFrame.BackgroundTransparency = 1
        blackFrame.BorderSizePixel        = 0
        blackFrame.ZIndex                 = 8
        blackFrame.Parent                 = gui

        -- ── Lighting effects ─────────────────────────────────────────────────

        local colorCorrection = Instance.new("ColorCorrectionEffect")
        colorCorrection.TintColor  = Color3.new(1, 1, 1)
        colorCorrection.Brightness = 0
        colorCorrection.Parent     = Lighting

        local blurEffect = Instance.new("BlurEffect")
        blurEffect.Size   = 0
        blurEffect.Parent = Lighting

        -- ── Fade IN ──────────────────────────────────────────────────────────

        local FADE_IN = math.min(0.45, cfg.duration * 0.10)

        for _, f in vigFrames do
                tw(f, FADE_IN, { BackgroundTransparency = cfg.vigTarget })
        end
        tw(colorCorrection, FADE_IN, { TintColor = cfg.tint })
        if cfg.blur > 0 then
                tw(blurEffect, FADE_IN, { Size = cfg.blur })
        end

        -- ── Camera shake ─────────────────────────────────────────────────────

        local shakeAmplitude = cfg.shakeAmp
        local shakeActive    = true
        local shakeConn = RunService.RenderStepped:Connect(function()
                if not shakeActive then return end
                local amp = shakeAmplitude
                local rx  = (rng:NextNumber() * 2 - 1) * amp
                local ry  = (rng:NextNumber() * 2 - 1) * amp * 0.6
                Camera.CFrame = Camera.CFrame * CFrame.Angles(rx, ry, 0)
        end)

        -- ── Heartbeat visual + SFX ───────────────────────────────────────────
        --
        -- Double-beat pattern synced between vignette pulse and sound:
        --   THUMP … thump … (rest) … THUMP … thump … (rest) …
        -- sfxVolume and sfxPitch scale with level (louder + faster = higher level).

        local heartbeatActive = true
        task.spawn(function()
                while heartbeatActive do
                        local intensity  = cfg.heartbeat
                        local darkTarget = math.max(0, cfg.vigTarget - intensity * 0.14)

                        -- Beat 1 (strong)
                        for _, f in vigFrames do
                                tw(f, 0.07, { BackgroundTransparency = darkTarget }, Enum.EasingStyle.Quad)
                        end
                        heartSound.Volume = cfg.sfxVolume
                        heartSound:Play()
                        task.wait(0.09)
                        for _, f in vigFrames do
                                tw(f, 0.22, { BackgroundTransparency = cfg.vigTarget }, Enum.EasingStyle.Quad)
                        end
                        task.wait(0.55 + rng:NextNumber() * 0.15)

                        -- Beat 2 (weaker echo)
                        local darkTarget2 = math.max(0, cfg.vigTarget - intensity * 0.08)
                        for _, f in vigFrames do
                                tw(f, 0.06, { BackgroundTransparency = darkTarget2 }, Enum.EasingStyle.Quad)
                        end
                        heartSound.Volume = cfg.sfxVolume * 0.55
                        heartSound:Play()
                        task.wait(0.07)
                        for _, f in vigFrames do
                                tw(f, 0.28, { BackgroundTransparency = cfg.vigTarget }, Enum.EasingStyle.Quad)
                        end

                        -- Rest between cycles — shorter at higher levels
                        task.wait(cfg.beatRestMin + rng:NextNumber() * (cfg.beatRestMax - cfg.beatRestMin))
                end
        end)

        -- ── Screen flicker ───────────────────────────────────────────────────

        local flickerActive = true
        if cfg.flickerChance > 0 then
                task.spawn(function()
                        while flickerActive do
                                task.wait(rng:NextNumber() * 2.2 + 0.6)
                                if not flickerActive then break end
                                if rng:NextNumber() < cfg.flickerChance then
                                        tw(colorCorrection, 0.04, { Brightness = -0.28 }, Enum.EasingStyle.Linear)
                                        task.wait(0.05 + rng:NextNumber() * 0.07)
                                        tw(colorCorrection, 0.07, { Brightness = 0 }, Enum.EasingStyle.Linear)
                                end
                        end
                end)
        end

        -- ── Black flashes (level 4+) ─────────────────────────────────────────

        local flashActive = true
        if cfg.blackFlash then
                task.spawn(function()
                        task.wait(4)
                        while flashActive do
                                task.wait(rng:NextNumber() * 9 + 5)
                                if not flashActive then break end
                                blackFrame.BackgroundTransparency = 0.35
                                tw(blackFrame, 0.08, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
                        end
                end)
        end

        -- ── Floating messages ─────────────────────────────────────────────────

        local activeLabels: { TextLabel } = {}
        local totalMessages = rng:NextInteger(cfg.msgCount[1], cfg.msgCount[2])
        local pool          = shuffle(MESSAGES)
        local msgIndex      = 0
        local messagesActive = true

        task.spawn(function()
                task.wait(math.min(0.2, cfg.duration * 0.1))
                while messagesActive and msgIndex < totalMessages do
                        msgIndex += 1
                        local text  = pool[(msgIndex - 1) % #pool + 1]
                        local xPos  = rng:NextNumber() * 0.68 + 0.04
                        local yPos  = rng:NextNumber() * 0.75 + 0.06
                        local fSize = rng:NextInteger(15, 23)
                        local holdT = rng:NextNumber() * 1.6 + 0.9

                        local label = Instance.new("TextLabel")
                        label.Text                   = text
                        label.Size                   = UDim2.new(0.32, 0, 0, fSize + 10)
                        label.Position               = UDim2.new(xPos, 0, yPos, 0)
                        label.BackgroundTransparency = 1
                        label.TextColor3             = Color3.new(
                                1,
                                rng:NextNumber() * 0.12 + 0.82,
                                rng:NextNumber() * 0.12 + 0.82
                        )
                        label.TextTransparency       = 1
                        label.TextSize               = fSize
                        label.Font                   = Enum.Font.GothamSemibold
                        label.TextWrapped            = true
                        label.TextXAlignment         = Enum.TextXAlignment.Left
                        label.ZIndex                 = 5
                        label.Parent                 = gui

                        table.insert(activeLabels, label)

                        tw(label, 0.45, { TextTransparency = 0.05 })
                        task.delay(holdT, function()
                                if not label.Parent then return end
                                tw(label, 0.55, { TextTransparency = 1 })
                                task.delay(0.6, function()
                                        if label.Parent then label:Destroy() end
                                        local idx = table.find(activeLabels, label)
                                        if idx then table.remove(activeLabels, idx) end
                                end)
                        end)

                        local interval = rng:NextNumber() * (cfg.msgInterval[2] - cfg.msgInterval[1]) + cfg.msgInterval[1]
                        task.wait(interval)
                end
        end)

        -- ── Fade OUT and cleanup ──────────────────────────────────────────────

        task.delay(cfg.duration, function()
                local FADE_OUT = math.min(0.55, cfg.duration * 0.10)

                shakeActive     = false
                heartbeatActive = false
                flickerActive   = false
                flashActive     = false
                messagesActive  = false

                -- Fade out sound
                tw(heartSound, FADE_OUT, { Volume = 0 }, Enum.EasingStyle.Linear)

                -- Smoothly ramp shake amplitude to zero
                task.spawn(function()
                        local steps = 20
                        local start = shakeAmplitude
                        for i = 1, steps do
                                task.wait(FADE_OUT / steps)
                                shakeAmplitude = start * (1 - i / steps)
                        end
                        shakeAmplitude = 0
                        shakeConn:Disconnect()
                end)

                -- Immediately fade out any visible message labels
                for _, label in activeLabels do
                        if label.Parent then
                                tw(label, FADE_OUT * 0.8, { TextTransparency = 1 })
                        end
                end

                for _, f in vigFrames do
                        tw(f, FADE_OUT, { BackgroundTransparency = 1 })
                end
                tw(colorCorrection, FADE_OUT, { TintColor = Color3.new(1, 1, 1), Brightness = 0 })
                tw(blurEffect,      FADE_OUT, { Size = 0 })

                task.delay(FADE_OUT + 0.25, function()
                        gui:Destroy()
                        colorCorrection:Destroy()
                        blurEffect:Destroy()
                        heartSound:Destroy()
                        isRunning = false
                end)
        end)
end

-- ── Remote listener ────────────────────────────────────────────────────────────

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

if CommandRemotes.Anxiety then
        CommandRemotes.Anxiety.OnClientEvent:Connect(function(level: number)
                if typeof(level) ~= "number" then return end
                level = math.clamp(math.round(level), 1, 5)
                runAnxiety(level)
        end)
        print("[AnxietyEffects] Ready.")
end
