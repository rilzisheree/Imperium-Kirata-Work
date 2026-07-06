local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes") :: ModuleScript)

-- ── Layout ─────────────────────────────────────────────────────────────────────
local CARD_W = 290
local CARD_H = 44
local MARGIN = 18

local POS_IN = UDim2.new(0, MARGIN, 0.5, -CARD_H / 2)

-- ── Colours ────────────────────────────────────────────────────────────────────
local C_BG  = Color3.fromRGB(18,  18,  26)
local C_BOR = Color3.fromRGB(70,  70, 100)
local C_TXT = Color3.fromRGB(255, 255, 255)
local C_BTN = Color3.fromRGB(150, 150, 175)
local C_HOV = Color3.fromRGB(255, 255, 255)

-- ── Tick sound ─────────────────────────────────────────────────────────────────
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
        if activeTask then task.cancel(activeTask); activeTask = nil end
        if activeGui  then activeGui:Destroy();     activeGui  = nil end
end

local function labelFor(n: number): string
        n = math.max(0, math.floor(n))
        return "Countdown: " .. n .. (n == 1 and " Second" or " Seconds")
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

        local card = Instance.new("Frame", sg)
        card.AnchorPoint            = Vector2.new(0, 0)
        card.Size                   = UDim2.new(0, CARD_W, 0, CARD_H)
        card.Position               = POS_IN
        card.BackgroundColor3       = C_BG
        card.BackgroundTransparency = 0.35
        card.BorderSizePixel        = 0
        card.ZIndex                 = 2
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

        local stroke = Instance.new("UIStroke", card)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color           = C_BOR
        stroke.Thickness       = 1

        -- Countdown label
        local label = Instance.new("TextLabel", card)
        label.Size                   = UDim2.new(1, -82, 1, 0)
        label.Position               = UDim2.new(0, 14, 0, 0)
        label.BackgroundTransparency = 1
        label.Font                   = Enum.Font.GothamBold
        label.TextSize               = 14
        label.TextColor3             = C_TXT
        label.TextXAlignment         = Enum.TextXAlignment.Left
        label.TextYAlignment         = Enum.TextYAlignment.Center
        label.Text                   = labelFor(endTime - workspace.DistributedGameTime)
        label.ZIndex                 = 3

        -- Mute button
        local muteBtn = Instance.new("TextButton", card)
        muteBtn.Size                   = UDim2.new(0, 38, 0, 28)
        muteBtn.Position               = UDim2.new(1, -74, 0.5, -14)
        muteBtn.BackgroundTransparency = 1
        muteBtn.Font                   = Enum.Font.Gotham
        muteBtn.TextSize               = 12
        muteBtn.TextColor3             = C_BTN
        muteBtn.Text                   = "Mute"
        muteBtn.BorderSizePixel        = 0
        muteBtn.ZIndex                 = 4
        muteBtn.MouseEnter:Connect(function()  muteBtn.TextColor3 = C_HOV end)
        muteBtn.MouseLeave:Connect(function()  muteBtn.TextColor3 = C_BTN end)
        muteBtn.MouseButton1Click:Connect(function()
                muted = not muted
                muteBtn.Text = muted and "Unmute" or "Mute"
        end)

        -- X button
        local xBtn = Instance.new("TextButton", card)
        xBtn.Size                   = UDim2.new(0, 26, 0, 28)
        xBtn.Position               = UDim2.new(1, -32, 0.5, -14)
        xBtn.BackgroundTransparency = 1
        xBtn.Font                   = Enum.Font.GothamBold
        xBtn.TextSize               = 13
        xBtn.TextColor3             = C_BTN
        xBtn.Text                   = "X"
        xBtn.BorderSizePixel        = 0
        xBtn.ZIndex                 = 4
        xBtn.MouseEnter:Connect(function()  xBtn.TextColor3 = C_HOV end)
        xBtn.MouseLeave:Connect(function()  xBtn.TextColor3 = C_BTN end)
        xBtn.MouseButton1Click:Connect(function()
                destroyActive()
        end)

        -- Tick loop
        local lastFloor = nil

        activeTask = task.spawn(function()
                while true do
                        local remaining = endTime - workspace.DistributedGameTime
                        local floored   = math.floor(remaining)

                        if floored ~= lastFloor then
                                lastFloor  = floored
                                label.Text = labelFor(remaining)
                                if floored > 0 and not muted then
                                        tickSound:Play()
                                end
                        end

                        if remaining <= 0 then
                                label.Text = "Countdown: 0 Seconds"
                                activeTask = nil
                                task.wait(0.8)
                                destroyActive()
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
