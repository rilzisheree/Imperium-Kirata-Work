local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes") :: ModuleScript)

-- ── Palette (matches CommandBar / CommandNotify) ───────────────────────────────
local C_BG  = Color3.fromRGB(12,  12,  18)
local C_BOR = Color3.fromRGB(90,  90, 120)
local C_ACC = Color3.fromRGB(160, 160, 210)
local C_TXT = Color3.fromRGB(235, 235, 252)
local C_DIM = Color3.fromRGB(130, 130, 160)

-- ── Layout ─────────────────────────────────────────────────────────────────────
local WIDGET_W    = 170
local WIDGET_H    = 105
local MARGIN_LEFT = 18

-- Positions: anchored top-left, Y centres the widget
local POS_IN  = UDim2.new(0, MARGIN_LEFT,          0.5, -WIDGET_H / 2)
local POS_OUT = UDim2.new(0, -(WIDGET_W + 40),     0.5, -WIDGET_H / 2)

local tweenIn  = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local tweenOut = TweenInfo.new(0.40, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

-- ── Sounds ─────────────────────────────────────────────────────────────────────
-- Tick: subtle click each second.  Done: short chime at zero.
-- SoundIds use well-known free Roblox assets — swap if you prefer different sounds.
local tickSound = Instance.new("Sound")
tickSound.SoundId       = "rbxassetid://9118985878"
tickSound.Volume        = 0.28
tickSound.RollOffMaxDistance = 0
tickSound.Parent        = SoundService

local doneSound = Instance.new("Sound")
doneSound.SoundId       = "rbxassetid://4590662766"
doneSound.Volume        = 0.55
doneSound.RollOffMaxDistance = 0
doneSound.Parent        = SoundService

-- ── Active countdown state ─────────────────────────────────────────────────────
local activeGui  = nil   -- current ScreenGui, or nil
local activeTask = nil   -- current coroutine driving the tick loop, or nil

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
local function formatTime(seconds: number): string
        seconds = math.max(0, math.floor(seconds))
        local m = math.floor(seconds / 60)
        local s = seconds % 60
        return string.format("%02d:%02d", m, s)
end

-- ── Core: build the widget, animate it in, run the tick loop ──────────────────
local function startCountdown(endTime: number)
        destroyActive()

        -- ── ScreenGui ──────────────────────────────────────────────────────────
        local sg = Instance.new("ScreenGui")
        sg.Name           = "CountdownGui"
        sg.ResetOnSpawn   = false
        sg.IgnoreGuiInset = true
        sg.DisplayOrder   = 98        -- above AnxietyEffect(97), below CmdBarGui(100)
        sg.Parent         = PGui
        activeGui = sg

        -- ── Card ───────────────────────────────────────────────────────────────
        local card = Instance.new("Frame", sg)
        card.AnchorPoint      = Vector2.new(0, 0)
        card.Size             = UDim2.new(0, WIDGET_W, 0, WIDGET_H)
        card.Position         = POS_OUT               -- starts off-screen left
        card.BackgroundColor3 = C_BG
        card.BorderSizePixel  = 0
        card.ZIndex           = 2
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

        local stroke = Instance.new("UIStroke", card)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color           = C_BOR
        stroke.Thickness       = 1.5

        -- left accent bar (mirrors CommandNotify card style)
        local accent = Instance.new("Frame", card)
        accent.AnchorPoint      = Vector2.new(0, 0.5)
        accent.Size             = UDim2.new(0, 3, 1, -22)
        accent.Position         = UDim2.new(0, 10, 0.5, 0)
        accent.BackgroundColor3 = C_ACC
        accent.BorderSizePixel  = 0
        accent.ZIndex           = 3
        Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

        -- "COUNTDOWN" label
        local titleLbl = Instance.new("TextLabel", card)
        titleLbl.Size               = UDim2.new(1, -30, 0, 18)
        titleLbl.Position           = UDim2.new(0, 22, 0, 11)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font               = Enum.Font.GothamBold
        titleLbl.TextSize           = 11
        titleLbl.TextColor3         = C_DIM
        titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
        titleLbl.TextYAlignment     = Enum.TextYAlignment.Center
        titleLbl.Text               = "COUNTDOWN"
        titleLbl.ZIndex             = 3

        -- large timer display
        local timerLbl = Instance.new("TextLabel", card)
        timerLbl.Size               = UDim2.new(1, -26, 0, 54)
        timerLbl.Position           = UDim2.new(0, 22, 0, 30)
        timerLbl.BackgroundTransparency = 1
        timerLbl.Font               = Enum.Font.Code
        timerLbl.TextSize           = 40
        timerLbl.TextColor3         = C_TXT
        timerLbl.TextXAlignment     = Enum.TextXAlignment.Left
        timerLbl.TextYAlignment     = Enum.TextYAlignment.Center
        timerLbl.Text               = formatTime(endTime - workspace.DistributedGameTime)
        timerLbl.ZIndex             = 3

        -- ── Slide in ───────────────────────────────────────────────────────────
        TweenService:Create(card, tweenIn, { Position = POS_IN }):Play()

        -- ── Tick loop ──────────────────────────────────────────────────────────
        local lastFloor = nil

        activeTask = task.spawn(function()
                while true do
                        local remaining = endTime - workspace.DistributedGameTime
                        local floored   = math.floor(remaining)

                        if floored ~= lastFloor then
                                lastFloor     = floored
                                timerLbl.Text = formatTime(remaining)

                                if floored > 0 then
                                        tickSound:Play()
                                end
                        end

                        if remaining <= 0 then
                                -- Final frame: show 00:00, play done sound, slide out
                                timerLbl.Text = "00:00"
                                doneSound:Play()

                                activeTask = nil   -- prevent destroyActive from cancelling us

                                local slideOut = TweenService:Create(card, tweenOut, { Position = POS_OUT })
                                slideOut:Play()
                                slideOut.Completed:Connect(function()
                                        -- guard: a newer countdown may have already replaced this gui
                                        if activeGui == sg then
                                                activeGui = nil
                                        end
                                        sg:Destroy()
                                end)
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
