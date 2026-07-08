local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local LocalPlayer    = Players.LocalPlayer
local PlayerGui      = LocalPlayer:WaitForChild("PlayerGui")
local MarkdownParser = require(ReplicatedStorage:WaitForChild("MarkdownParser"))

local COLOR_MAP = {
        red    = Color3.fromRGB(255,  90,  90),
        blue   = Color3.fromRGB(110, 160, 255),
        green  = Color3.fromRGB( 90, 220,  90),
        yellow = Color3.fromRGB(255, 230,  80),
        orange = Color3.fromRGB(255, 160,  60),
        purple = Color3.fromRGB(190, 110, 255),
        pink   = Color3.fromRGB(255, 140, 210),
        white  = Color3.fromRGB(255, 255, 255),
        cyan   = Color3.fromRGB( 90, 225, 255),
        lime   = Color3.fromRGB(140, 255,  90),
}
local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)

local function resolveColor(name: string?): Color3
        if name and COLOR_MAP[name:lower()] then
                return COLOR_MAP[name:lower()]
        end
        return DEFAULT_COLOR
end

local function tw(target, time, props)
        TweenService:Create(target, TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local gui = Instance.new("ScreenGui")
gui.Name           = "CommandEffects"
gui.DisplayOrder   = 96
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = PlayerGui

local blur = Instance.new("BlurEffect")
blur.Size   = 0
blur.Parent = Lighting

local smHeader = Instance.new("TextLabel")
smHeader.Name                   = "SMHeader"
smHeader.AnchorPoint            = Vector2.new(0.5, 1)
smHeader.Position               = UDim2.new(0.5, 0, 0.11, -4)
smHeader.Size                   = UDim2.new(0.75, 0, 0, 38)
smHeader.BackgroundTransparency = 1
smHeader.TextColor3             = DEFAULT_COLOR
smHeader.TextTransparency       = 0
smHeader.TextSize               = 36
smHeader.Font                   = Enum.Font.Merriweather
smHeader.Text                   = "[ Server Message ]"
smHeader.TextXAlignment         = Enum.TextXAlignment.Center
smHeader.TextYAlignment         = Enum.TextYAlignment.Center
smHeader.ZIndex                 = 10
smHeader.Visible                = false
smHeader.Parent                 = gui

local smBody = Instance.new("TextLabel")
smBody.Name                   = "SMBody"
smBody.AnchorPoint            = Vector2.new(0.5, 0)
smBody.Position               = UDim2.new(0.5, 0, 0.11, 4)
smBody.Size                   = UDim2.new(0.70, 0, 0, 0)
smBody.AutomaticSize          = Enum.AutomaticSize.Y
smBody.BackgroundTransparency = 1
smBody.TextColor3             = DEFAULT_COLOR
smBody.TextTransparency       = 0
smBody.TextSize               = 28
smBody.Font                   = Enum.Font.Merriweather
smBody.Text                   = ""
smBody.TextWrapped            = true
smBody.RichText               = true
smBody.TextXAlignment         = Enum.TextXAlignment.Center
smBody.TextYAlignment         = Enum.TextYAlignment.Top
smBody.ZIndex                 = 10
smBody.Visible                = false
smBody.Parent                 = gui

local imLabel = Instance.new("TextLabel")
imLabel.Name                   = "IMLabel"
imLabel.AnchorPoint            = Vector2.new(0.5, 0.5)
imLabel.Position               = UDim2.new(0.5, 0, 0.66, 0)
imLabel.Size                   = UDim2.new(0.50, 0, 0, 0)
imLabel.AutomaticSize          = Enum.AutomaticSize.Y
imLabel.BackgroundTransparency = 1
imLabel.TextColor3             = DEFAULT_COLOR
imLabel.TextTransparency       = 0
imLabel.TextSize               = 25
imLabel.Font                   = Enum.Font.Merriweather
imLabel.Text                   = ""
imLabel.TextWrapped            = true
imLabel.RichText               = true
imLabel.TextXAlignment         = Enum.TextXAlignment.Center
imLabel.TextYAlignment         = Enum.TextYAlignment.Center
imLabel.ZIndex                 = 10
imLabel.Visible                = false
imLabel.Parent                 = gui

local notifMsg = Instance.new("TextLabel")
notifMsg.Name                   = "NotifMsg"
notifMsg.AnchorPoint            = Vector2.new(0.5, 1)
notifMsg.Position               = UDim2.new(0.5, 0, 0.80, -4)
notifMsg.Size                   = UDim2.new(0.55, 0, 0, 0)
notifMsg.AutomaticSize          = Enum.AutomaticSize.Y
notifMsg.BackgroundTransparency = 1
notifMsg.TextColor3             = DEFAULT_COLOR
notifMsg.TextTransparency       = 1
notifMsg.TextSize               = 25
notifMsg.Font                   = Enum.Font.Merriweather
notifMsg.Text                   = ""
notifMsg.TextWrapped            = true
notifMsg.RichText               = true
notifMsg.TextXAlignment         = Enum.TextXAlignment.Center
notifMsg.TextYAlignment         = Enum.TextYAlignment.Center
notifMsg.TextStrokeTransparency = 1
notifMsg.ZIndex                 = 10
notifMsg.Visible                = false
notifMsg.Parent                 = gui

local notifSender = Instance.new("TextLabel")
notifSender.Name                   = "NotifSender"
notifSender.AnchorPoint            = Vector2.new(0.5, 0)
notifSender.Position               = UDim2.new(0.5, 0, 0.80, 4)
notifSender.Size                   = UDim2.new(0.55, 0, 0, 0)
notifSender.AutomaticSize          = Enum.AutomaticSize.Y
notifSender.BackgroundTransparency = 1
notifSender.TextColor3             = DEFAULT_COLOR
notifSender.TextTransparency       = 1
notifSender.TextSize               = 20
notifSender.Font                   = Enum.Font.Merriweather
notifSender.Text                   = ""
notifSender.TextWrapped            = true
notifSender.TextXAlignment         = Enum.TextXAlignment.Center
notifSender.TextYAlignment         = Enum.TextYAlignment.Center
notifSender.TextStrokeTransparency = 1
notifSender.ZIndex                 = 10
notifSender.Visible                = false
notifSender.Parent                 = gui

-- reading time based on word count
local function calcHold(text: string): number
        local words = select(2, text:gsub("%S+", "")) + 1
        return math.clamp(words * 0.45, 4, 10)
end

-- adds a coloured UIStroke to make text glow, returns a cleanup fn
local function applyGlow(color: Color3, labels: { TextLabel }): () -> ()
        local strokes = {}
        for _, lbl in labels do
                local s = Instance.new("UIStroke")
                s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
                s.Color           = color
                s.Thickness       = 1
                s.Transparency    = 0.92
                s.Parent          = lbl
                table.insert(strokes, s)
        end
        return function()
                for _, s in strokes do s:Destroy() end
        end
end

local smQueue: { { text: string, color: Color3, colorName: string? } } = {}
local smBusy = false
local shutdownActive = false
local serverBringToken = nil :: any

local function processSmQueue()
        if smBusy or #smQueue == 0 then return end
        smBusy = true

        local entry     = table.remove(smQueue, 1)
        local text      = entry.text
        local color     = entry.color
        local colorName = entry.colorName
        local hold      = calcHold(text)

        smBody.Text               = MarkdownParser.toRichText(text)
        smBody.TextColor3         = color
        smHeader.TextColor3       = color
        smHeader.TextTransparency = 1
        smBody.TextTransparency   = 1
        smHeader.Visible          = true
        smBody.Visible            = true
        blur.Size                 = 0

        local removeGlow = colorName and applyGlow(color, { smHeader, smBody }) or nil

        tw(blur,     0.6, { Size = 5 })
        tw(smHeader, 0.6, { TextTransparency = 0 })
        tw(smBody,   0.6, { TextTransparency = 0 })

        task.delay(0.6 + hold, function()
                        if shutdownActive then return end
                if removeGlow then removeGlow() end
                tw(blur,     0.5, { Size = 0 })
                tw(smHeader, 0.5, { TextTransparency = 1 })
                tw(smBody,   0.5, { TextTransparency = 1 })
                task.delay(0.55, function()
                        if shutdownActive then return end
                        smHeader.Visible          = false
                        smHeader.TextTransparency = 0
                        smBody.Visible            = false
                        smBody.TextTransparency   = 0
                        blur.Size                 = 0
                        smBusy = false
                        processSmQueue()
                end)
        end)
end

local function showSM(text: string, colorName: string?)
        table.insert(smQueue, {
                text      = text,
                color     = resolveColor(colorName),
                colorName = colorName,
        })
        processSmQueue()
end

local function showIM(text: string, colorName: string?)
        local color = resolveColor(colorName)
        local hold  = calcHold(text)

        imLabel.Text             = MarkdownParser.toRichText(text)
        imLabel.TextColor3       = color
        imLabel.TextTransparency = 1
        imLabel.Visible          = true

        local removeGlow = colorName and applyGlow(color, { imLabel }) or nil

        tw(imLabel, 0.6, { TextTransparency = 0 })

        task.delay(0.6 + hold, function()
                if removeGlow then removeGlow() end
                tw(imLabel, 0.5, { TextTransparency = 1 })
                task.delay(0.55, function()
                        imLabel.Visible          = false
                        imLabel.TextTransparency = 0
                end)
        end)
end

local notifSound = Instance.new("Sound")
notifSound.SoundId = "rbxassetid://131390520971848"
notifSound.Volume  = 1
notifSound.Parent  = gui

local notifQueue: { { message: string, sender: string } } = {}
local notifBusy = false

local NOTIF_IN_T   = 0.6
local NOTIF_OUT_T  = 0.5
local NOTIF_REST_Y = 0.80 -- bottom of container sits 20% above the bottom edge

local function processNotifQueue()
        if notifBusy or #notifQueue == 0 then return end
        notifBusy = true

        local entry = table.remove(notifQueue, 1)
        local hold  = calcHold(entry.message)

        notifMsg.Text                = MarkdownParser.toRichText(entry.message)
        notifSender.Text             = "-" .. entry.sender
        notifMsg.TextTransparency    = 1
        notifSender.TextTransparency = 1
        notifMsg.Visible             = true
        notifSender.Visible          = true
        notifSound:Play()

        tw(notifMsg,    NOTIF_IN_T, { TextTransparency = 0 })
        tw(notifSender, NOTIF_IN_T, { TextTransparency = 0 })

        task.delay(NOTIF_IN_T + hold, function()
                        tw(notifMsg,    NOTIF_OUT_T, { TextTransparency = 1 })
                tw(notifSender, NOTIF_OUT_T, { TextTransparency = 1 })

                task.delay(NOTIF_OUT_T + 0.05, function()
                        notifMsg.Visible    = false
                        notifSender.Visible = false
                        notifMsg.Text       = ""
                        notifSender.Text    = ""
                        notifBusy           = false
                        processNotifQueue()
                end)
        end)
end

local function showNotif(message: string, sender: string)
        table.insert(notifQueue, { message = message, sender = sender })
        processNotifQueue()
end

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

if CommandRemotes.SM then
        CommandRemotes.SM.OnClientEvent:Connect(function(message: string, colorName: string?)
                if typeof(message) == "string" and message ~= "" then
                        showSM(message, colorName)
                end
        end)
end

if CommandRemotes.IM then
        CommandRemotes.IM.OnClientEvent:Connect(function(message: string, colorName: string?)
                if typeof(message) == "string" and message ~= "" then
                        showIM(message, colorName)
                end
        end)
end

if CommandRemotes.Notif then
        CommandRemotes.Notif.OnClientEvent:Connect(function(message: string, sender: string)
                if typeof(message) == "string" and message ~= ""
                and typeof(sender) == "string" and sender ~= "" then
                        showNotif(message, sender)
                end
        end)
end

local blindGui = Instance.new("ScreenGui")
blindGui.Name           = "BlindEffect"
blindGui.DisplayOrder   = 95    -- below CmdBarGui (100) and CmdNotifyGui (110); CoreGui chat is always on top
blindGui.ResetOnSpawn   = false -- we handle respawn cleanup ourselves
blindGui.IgnoreGuiInset = true
blindGui.Enabled        = false
blindGui.Parent         = PlayerGui

local blindFrame = Instance.new("Frame", blindGui)
blindFrame.Size                   = UDim2.new(1, 0, 1, 0)
blindFrame.BackgroundColor3       = Color3.new(0, 0, 0)
blindFrame.BackgroundTransparency = 0
blindFrame.BorderSizePixel        = 0

local isBlinded  = false
local blindTween = nil

local function applyBlind(duration: number?)
        if isBlinded then return end
        isBlinded        = true
        blindGui.Enabled = true
        blindFrame.BackgroundTransparency = 1

        local fadeDuration = (duration and duration > 0) and duration or 1.0
        local style        = (duration and duration > 0) and Enum.EasingStyle.Linear or Enum.EasingStyle.Quint

        blindTween = TweenService:Create(
                blindFrame,
                TweenInfo.new(fadeDuration, style, Enum.EasingDirection.Out),
                { BackgroundTransparency = 0 }
        )
        blindTween:Play()
end

local function removeBlind()
        if not isBlinded then return end
        isBlinded = false
        if blindTween then
                blindTween:Cancel()
                blindTween = nil
        end
        local t = TweenService:Create(
                blindFrame,
                TweenInfo.new(1.0, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { BackgroundTransparency = 1 }
        )
        t:Play()
        t.Completed:Connect(function()
                blindGui.Enabled = false
                blindFrame.BackgroundTransparency = 0
        end)
end

LocalPlayer.CharacterAdded:Connect(removeBlind)

if CommandRemotes.Blind then
        CommandRemotes.Blind.OnClientEvent:Connect(applyBlind)
end

if CommandRemotes.Unblind then
        CommandRemotes.Unblind.OnClientEvent:Connect(removeBlind)
end

if CommandRemotes.Shutdown then
        CommandRemotes.Shutdown.OnClientEvent:Connect(function()
                -- freeze the SM queue so no queued/in-flight SM timer can clear the shutdown screen
                shutdownActive = true
                smBusy         = true
                table.clear(smQueue)

                        smHeader.Text             = "Server Shutting Down"
                smBody.Text               = "A Staff Member has shut down this server,\nPlease rejoin shortly."
                smHeader.TextColor3       = DEFAULT_COLOR
                smBody.TextColor3         = DEFAULT_COLOR
                smHeader.TextTransparency = 1
                smBody.TextTransparency   = 1
                smHeader.Visible          = true
                smBody.Visible            = true
                blur.Size                 = 0

                tw(blur,     0.6, { Size = 5 })
                tw(smHeader, 0.6, { TextTransparency = 0 })
                tw(smBody,   0.6, { TextTransparency = 0 })

                        local char = LocalPlayer.Character
                if char then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then
                                hum.WalkSpeed  = 0
                                hum.JumpHeight = 0
                                hum.JumpPower  = 0
                        end
                end
        end)
end

if CommandRemotes.ServerBringNotice then
        CommandRemotes.ServerBringNotice.OnClientEvent:Connect(function()
                -- freeze the SM queue so no queued/in-flight SM timer can clear this screen;
                -- it normally stays up until the teleport happens and the client leaves the
                -- game, but unlike a real shutdown the teleport can fail, so we use our own
                -- flag (not shutdownActive) plus a safety timeout to release the queue again
                local myToken = {}
                serverBringToken = myToken
                smBusy = true
                table.clear(smQueue)

                smHeader.Text             = "Server Bring"
                smBody.Text               = "You're being brought to another server.."
                smHeader.TextColor3       = DEFAULT_COLOR
                smBody.TextColor3         = DEFAULT_COLOR
                smHeader.TextTransparency = 1
                smBody.TextTransparency   = 1
                smHeader.Visible          = true
                smBody.Visible            = true
                blur.Size                 = 0

                tw(blur,     0.6, { Size = 5 })
                tw(smHeader, 0.6, { TextTransparency = 0 })
                tw(smBody,   0.6, { TextTransparency = 0 })

                -- safety net: if the teleport hasn't happened within 20s (e.g. it failed),
                -- clear the screen and let the SM queue resume instead of staying stuck
                task.delay(20, function()
                        if serverBringToken ~= myToken or shutdownActive then return end
                        serverBringToken = nil
                        tw(blur,     0.5, { Size = 0 })
                        tw(smHeader, 0.5, { TextTransparency = 1 })
                        tw(smBody,   0.5, { TextTransparency = 1 })
                        task.delay(0.55, function()
                                if shutdownActive then return end
                                smHeader.Visible          = false
                                smHeader.TextTransparency = 0
                                smBody.Visible            = false
                                smBody.TextTransparency   = 0
                                blur.Size                 = 0
                                smBusy                    = false
                                processSmQueue()
                        end)
                end)
        end)
end
