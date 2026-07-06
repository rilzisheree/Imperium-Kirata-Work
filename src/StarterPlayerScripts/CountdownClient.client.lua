local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes") :: ModuleScript)

-- ── Constants ──────────────────────────────────────────────────────────────────
local BAR_H      = 52
local BG_COLOR   = Color3.fromRGB(14, 14, 18)
local BG_TRANS   = 0.08          -- nearly opaque dark bar
local TXT_COLOR  = Color3.fromRGB(255, 255, 255)
local BTN_COLOR  = Color3.fromRGB(190, 190, 200)
local BTN_HOV    = Color3.fromRGB(255, 255, 255)

-- Slide positions (bar sits at the bottom of the screen)
local POS_IN  = UDim2.new(0, 0, 1, -BAR_H)      -- resting: anchored to bottom
local POS_OUT = UDim2.new(0, 0, 1,  BAR_H + 4)  -- hidden: below the screen

local tweenIn  = TweenInfo.new(0.40, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local tweenOut = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

-- ── Sounds ─────────────────────────────────────────────────────────────────────
local tickSound = Instance.new("Sound")
tickSound.SoundId            = "rbxassetid://129348077985519"
tickSound.Volume             = 0.7
tickSound.RollOffMaxDistance = 0
tickSound.Parent             = SoundService

-- ── Active state ───────────────────────────────────────────────────────────────
local activeGui  = nil
local activeTask = nil
local muted      = false

local function destroyActive()
        if activeTask then
                task.cancel(activeTask)
                activeTask = nil
        end
        if activeGui then
                activeGui:Destroy()
                activeGui = nil
        end
end

-- ── Helpers ────────────────────────────────────────────────────────────────────
local function labelFor(n: number): string
        n = math.max(0, math.floor(n))
        return "Countdown: " .. n .. (n == 1 and " Second" or " Seconds")
end

local function slideOut(bar: Frame, sg: ScreenGui)
        local t = TweenService:Create(bar, tweenOut, { Position = POS_OUT })
        t:Play()
        t.Completed:Connect(function()
                if activeGui == sg then activeGui = nil end
                sg:Destroy()
        end)
end

-- ── Build and run ──────────────────────────────────────────────────────────────
local function startCountdown(endTime: number)
        destroyActive()

        -- ScreenGui
        local sg = Instance.new("ScreenGui")
        sg.Name           = "CountdownGui"
        sg.ResetOnSpawn   = false
        sg.IgnoreGuiInset = true
        sg.DisplayOrder   = 98
        sg.Parent         = PGui
        activeGui = sg

        -- Full-width bar, starts below screen
        local bar = Instance.new("Frame", sg)
        bar.Size             = UDim2.new(1, 0, 0, BAR_H)
        bar.Position         = POS_OUT
        bar.BackgroundColor3 = BG_COLOR
        bar.BackgroundTransparency = BG_TRANS
        bar.BorderSizePixel  = 0
        bar.ZIndex           = 2

        -- Thin top border line for definition
        local topLine = Instance.new("Frame", bar)
        topLine.Size             = UDim2.new(1, 0, 0, 1)
        topLine.Position         = UDim2.new(0, 0, 0, 0)
        topLine.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
        topLine.BackgroundTransparency = 0.5
        topLine.BorderSizePixel  = 0
        topLine.ZIndex           = 3

        -- Main countdown text (left side)
        local remaining0 = endTime - workspace.DistributedGameTime
        local timerLbl = Instance.new("TextLabel", bar)
        timerLbl.Size               = UDim2.new(1, -140, 1, 0)
        timerLbl.Position           = UDim2.new(0, 20, 0, 0)
        timerLbl.BackgroundTransparency = 1
        timerLbl.Font               = Enum.Font.GothamBold
        timerLbl.TextSize           = 26
        timerLbl.TextColor3         = TXT_COLOR
        timerLbl.TextXAlignment     = Enum.TextXAlignment.Left
        timerLbl.TextYAlignment     = Enum.TextYAlignment.Center
        timerLbl.Text               = labelFor(remaining0)
        timerLbl.ZIndex             = 3

        -- ── Right-side buttons ─────────────────────────────────────────────────
        local BTN_W = 52
        local BTN_H = 28

        local function makeBtn(labelText: string, offsetX: number): TextButton
                local btn = Instance.new("TextButton", bar)
                btn.Size               = UDim2.new(0, BTN_W, 0, BTN_H)
                btn.Position           = UDim2.new(1, offsetX, 0.5, -BTN_H / 2)
                btn.BackgroundTransparency = 1
                btn.Font               = Enum.Font.Gotham
                btn.TextSize           = 13
                btn.TextColor3         = BTN_COLOR
                btn.Text               = labelText
                btn.BorderSizePixel    = 0
                btn.ZIndex             = 4
                btn.MouseEnter:Connect(function() btn.TextColor3 = BTN_HOV end)
                btn.MouseLeave:Connect(function() btn.TextColor3 = BTN_COLOR end)
                return btn
        end

        -- X button — dismiss for this player only
        local xBtn   = makeBtn("X",    -(12))
        -- Mute button — to its left
        local muteBtn = makeBtn(muted and "Unmute" or "Mute", -(12 + BTN_W + 6))

        xBtn.MouseButton1Click:Connect(function()
                if activeTask then task.cancel(activeTask); activeTask = nil end
                slideOut(bar, sg)
        end)

        muteBtn.MouseButton1Click:Connect(function()
                muted = not muted
                muteBtn.Text = muted and "Unmute" or "Mute"
        end)

        -- ── Slide in ───────────────────────────────────────────────────────────
        TweenService:Create(bar, tweenIn, { Position = POS_IN }):Play()

        -- ── Tick loop ──────────────────────────────────────────────────────────
        local lastFloor = nil

        activeTask = task.spawn(function()
                while true do
                        local remaining = endTime - workspace.DistributedGameTime
                        local floored   = math.floor(remaining)

                        if floored ~= lastFloor then
                                lastFloor     = floored
                                timerLbl.Text = labelFor(remaining)
                                if floored > 0 and not muted then
                                        tickSound:Play()
                                end
                        end

                        if remaining <= 0 then
                                timerLbl.Text = "Countdown: 0 Seconds"
                                activeTask    = nil
                                slideOut(bar, sg)
                                break
                        end

                        task.wait(0.05)
                end
        end)
end

-- ── Remote listener ────────────────────────────────────────────────────────────
CommandRemotes.CountdownStart.OnClientEvent:Connect(function(endTime: number)
        if typeof(endTime) ~= "number" then return end
        startCountdown(endTime)
end)
