local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes") :: ModuleScript)

-- ── Layout ─────────────────────────────────────────────────────────────────────
local CARD_W  = 295
local CARD_H  = 52
local MARGIN  = 18    -- gap from the left edge of the screen

-- Anchored top-left; Y offset centres the card vertically
local POS_IN  = UDim2.new(0,  MARGIN,          0.5, -CARD_H / 2)
local POS_OUT = UDim2.new(0, -(CARD_W + 40),   0.5, -CARD_H / 2)

local tweenIn  = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local tweenOut = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

-- ── Colours (matches rest of admin UI) ────────────────────────────────────────
local C_BG   = Color3.fromRGB(14,  14,  20)
local C_BOR  = Color3.fromRGB(80,  80, 110)
local C_TXT  = Color3.fromRGB(255, 255, 255)
local C_BTN  = Color3.fromRGB(170, 170, 190)
local C_HOV  = Color3.fromRGB(255, 255, 255)

-- ── Tick sound ─────────────────────────────────────────────────────────────────
local tickSound = Instance.new("Sound")
tickSound.SoundId            = "rbxassetid://129348077985519"
tickSound.Volume             = 0.7
tickSound.RollOffMaxDistance = 0
tickSound.Parent             = SoundService

-- ── Active state ───────────────────────────────────────────────────────────────
local activeGui  = nil
local activeTask = nil

local function destroyActive()
        if activeTask then task.cancel(activeTask); activeTask = nil end
        if activeGui  then activeGui:Destroy();     activeGui  = nil end
end

-- ── Helpers ────────────────────────────────────────────────────────────────────
local function labelFor(n: number): string
        n = math.max(0, math.floor(n))
        return "Countdown: " .. n .. (n == 1 and " Second" or " Seconds")
end

local function doSlideOut(bar: Frame, sg: ScreenGui)
        local t = TweenService:Create(bar, tweenOut, { Position = POS_OUT })
        t:Play()
        t.Completed:Connect(function()
                if activeGui == sg then activeGui = nil end
                sg:Destroy()
        end)
end

-- ── Build widget and run tick loop ─────────────────────────────────────────────
local function startCountdown(endTime: number)
        destroyActive()

        local sg = Instance.new("ScreenGui")
        sg.Name           = "CountdownGui"
        sg.ResetOnSpawn   = false
        sg.IgnoreGuiInset = true
        sg.DisplayOrder   = 98
        sg.Parent         = PGui
        activeGui = sg

        -- Card
        local card = Instance.new("Frame", sg)
        card.AnchorPoint      = Vector2.new(0, 0)
        card.Size             = UDim2.new(0, CARD_W, 0, CARD_H)
        card.Position         = POS_OUT
        card.BackgroundColor3 = C_BG
        card.BackgroundTransparency = 0.10
        card.BorderSizePixel  = 0
        card.ZIndex           = 2
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

        local stroke = Instance.new("UIStroke", card)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color           = C_BOR
        stroke.Thickness       = 1.5

        -- Countdown text
        local label = Instance.new("TextLabel", card)
        label.Size               = UDim2.new(1, -50, 1, 0)
        label.Position           = UDim2.new(0, 16, 0, 0)
        label.BackgroundTransparency = 1
        label.Font               = Enum.Font.GothamBold
        label.TextSize           = 20
        label.TextColor3         = C_TXT
        label.TextXAlignment     = Enum.TextXAlignment.Left
        label.TextYAlignment     = Enum.TextYAlignment.Center
        label.Text               = labelFor(endTime - workspace.DistributedGameTime)
        label.ZIndex             = 3

        -- X button
        local xBtn = Instance.new("TextButton", card)
        xBtn.Size               = UDim2.new(0, 30, 0, 30)
        xBtn.Position           = UDim2.new(1, -38, 0.5, -15)
        xBtn.BackgroundTransparency = 1
        xBtn.Font               = Enum.Font.GothamBold
        xBtn.TextSize           = 16
        xBtn.TextColor3         = C_BTN
        xBtn.Text               = "✕"
        xBtn.BorderSizePixel    = 0
        xBtn.ZIndex             = 4
        xBtn.MouseEnter:Connect(function()  xBtn.TextColor3 = C_HOV end)
        xBtn.MouseLeave:Connect(function()  xBtn.TextColor3 = C_BTN end)
        xBtn.MouseButton1Click:Connect(function()
                if activeTask then task.cancel(activeTask); activeTask = nil end
                doSlideOut(card, sg)
        end)

        -- Slide in
        TweenService:Create(card, tweenIn, { Position = POS_IN }):Play()

        -- Tick loop (polls every 50 ms, only re-renders on whole-second change)
        local lastFloor = nil

        activeTask = task.spawn(function()
                while true do
                        local remaining = endTime - workspace.DistributedGameTime
                        local floored   = math.floor(remaining)

                        if floored ~= lastFloor then
                                lastFloor  = floored
                                label.Text = labelFor(remaining)
                                if floored > 0 then
                                        tickSound:Play()
                                end
                        end

                        if remaining <= 0 then
                                label.Text = "Countdown: 0 Seconds"
                                activeTask = nil
                                doSlideOut(card, sg)
                                break
                        end

                        task.wait(0.05)
                end
        end)
end

-- ── Remote ─────────────────────────────────────────────────────────────────────
CommandRemotes.CountdownStart.OnClientEvent:Connect(function(endTime: number)
        if typeof(endTime) ~= "number" then return end
        startCountdown(endTime)
end)
