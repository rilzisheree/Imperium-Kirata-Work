--[[
        ChatClient.client.lua
        LocalScript — StarterPlayerScripts

        Proximity chat system — client side:
          • Disables the default Roblox CoreGui chat
          • Minimal top-left input bar (press / or Enter to focus)
          • When a message is received, creates a bubble above the sender's
            character — positioned each frame via Camera:WorldToViewportPoint()
            so the bubble stays locked above the head at every zoom level
            with no jitter.
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local ChatRemotes = require(ReplicatedStorage:WaitForChild("ChatRemotes"))

-- ─── Disable default Roblox chat CoreGui ─────────────────────────────────────
local function disableDefaultChat()
        pcall(function()
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
        end)
end
disableDefaultChat()
task.spawn(function()
        while true do
                task.wait(2)
                disableDefaultChat()
        end
end)

-- ─── Configuration ────────────────────────────────────────────────────────────
local CFG = {
        -- Bubble appearance
        BUBBLE_BG_COLOR     = Color3.fromRGB(240, 240, 240),
        BUBBLE_BG_TRANS     = 0.06,
        BUBBLE_TEXT_COLOR   = Color3.fromRGB(25, 25, 25),
        BUBBLE_FONT         = Enum.Font.GothamSemibold,
        BUBBLE_TEXT_SIZE    = 16,
        BUBBLE_MAX_WIDTH    = 200,
        BUBBLE_PADDING_H    = 12,
        BUBBLE_PADDING_V    = 7,
        BUBBLE_CORNER       = 10,

        -- Timing
        HOLD_DURATION       = 7,
        FADE_IN_TIME        = 0.2,
        FADE_OUT_TIME       = 0.5,
}

-- ─── Input bar (top-left, below Roblox icon buttons) ─────────────────────────
local BAR_H   = 36
local BTN_W   = 34

local inputGui = Instance.new("ScreenGui")
inputGui.Name           = "ChatInput"
inputGui.DisplayOrder   = 20
inputGui.ResetOnSpawn   = false
inputGui.IgnoreGuiInset = true
inputGui.Parent         = PlayerGui

local inputFrame = Instance.new("Frame")
inputFrame.Name                   = "InputFrame"
inputFrame.AnchorPoint            = Vector2.new(0, 0)
inputFrame.Size                   = UDim2.new(0.20, 0, 0, BAR_H)
inputFrame.Position               = UDim2.new(0, 8, 0, 62)
inputFrame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
inputFrame.BackgroundTransparency = 0.25
inputFrame.BorderSizePixel        = 0
inputFrame.Parent                 = inputGui

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 7)
inputCorner.Parent = inputFrame

local inputStroke = Instance.new("UIStroke")
inputStroke.Color           = Color3.fromRGB(35, 35, 35)
inputStroke.Thickness       = 1.5
inputStroke.Transparency    = 0
inputStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
inputStroke.Parent          = inputFrame

local inputBox = Instance.new("TextBox")
inputBox.Name                   = "InputBox"
inputBox.Size                   = UDim2.new(1, -(BTN_W + 18), 1, 0)
inputBox.Position               = UDim2.new(0, 14, 0, 0)
inputBox.BackgroundTransparency = 1
inputBox.BorderSizePixel        = 0
inputBox.ClearTextOnFocus       = false
inputBox.Font                   = Enum.Font.GothamSemibold
inputBox.TextSize               = 14
inputBox.TextColor3             = Color3.fromRGB(225, 225, 240)
inputBox.PlaceholderText        = "To chat click here or press / key"
inputBox.PlaceholderColor3      = Color3.fromRGB(120, 128, 160)
inputBox.Text                   = ""
inputBox.TextXAlignment         = Enum.TextXAlignment.Left
inputBox.TextYAlignment         = Enum.TextYAlignment.Center
inputBox.MultiLine              = false
inputBox.Parent                 = inputFrame

local sendBtn = Instance.new("TextButton")
sendBtn.Name                   = "SendBtn"
sendBtn.AnchorPoint            = Vector2.new(1, 0.5)
sendBtn.Size                   = UDim2.new(0, BTN_W, 1, -10)
sendBtn.Position               = UDim2.new(1, -5, 0.5, 0)
sendBtn.BackgroundColor3       = Color3.fromRGB(18, 18, 18)
sendBtn.BackgroundTransparency = 0
sendBtn.BorderSizePixel        = 0
sendBtn.Text                   = "→"
sendBtn.Font                   = Enum.Font.GothamBlack
sendBtn.TextSize               = 22
sendBtn.TextColor3             = Color3.fromRGB(210, 210, 210)
sendBtn.AutoButtonColor        = false
sendBtn.Parent                 = inputFrame

local sendCorner = Instance.new("UICorner")
sendCorner.CornerRadius = UDim.new(0, 5)
sendCorner.Parent = sendBtn

local sendStroke = Instance.new("UIStroke")
sendStroke.Color           = Color3.fromRGB(35, 35, 35)
sendStroke.Thickness       = 1
sendStroke.Transparency    = 0.3
sendStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
sendStroke.Parent          = sendBtn

-- ─── Bubble system — ScreenGui + WorldToViewportPoint (zoom-proof) ───────────
--
-- Every RenderStepped we convert each active speaker's head world position
-- to a viewport (screen) position and move their bubble container there.
-- This means zoom level, camera angle, and character movement all stay
-- perfectly tracked with no BillboardGui stud-scaling artifacts.
--
-- Layout:
--   bubbleGui (ScreenGui)
--     └─ SpeakerBubbles_<name> (Frame, AnchorPoint 0.5,1 → bottom-center)
--           └─ UIListLayout (VerticalAlignment.Bottom → newest on top)
--           └─ Bubble frames...

-- How many studs above the Head center the bottom of the bubble stack sits.
-- 0.8 puts the bubble just above the top of the head (head radius ≈ 0.5 studs).
local WORLD_Y_OFFSET = 1.5   -- studs

local bubbleGui = Instance.new("ScreenGui")
bubbleGui.Name           = "ChatBubbles"
bubbleGui.DisplayOrder   = 15
bubbleGui.ResetOnSpawn   = false
bubbleGui.IgnoreGuiInset = true
bubbleGui.Parent         = PlayerGui

-- activeSpeakers[charName] = { frame = Frame, head = BasePart }
local activeSpeakers = {}
local bubbleCounts   = {}

-- ── RenderStepped: reposition every bubble container each frame ───────────────
RunService.RenderStepped:Connect(function()
        -- Re-read CurrentCamera each frame — it can be replaced (e.g. cutscenes).
        local cam = workspace.CurrentCamera
        if not cam then return end

        for charName, data in pairs(activeSpeakers) do
                local head = data.head
                if not head or not head.Parent then
                        data.frame.Visible = false
                        continue
                end

                -- Project world point to viewport pixels
                local worldPos = head.Position + Vector3.new(0, WORLD_Y_OFFSET, 0)
                local screenPos, onScreen = cam:WorldToViewportPoint(worldPos)

                if onScreen and screenPos.Z > 0 then
                        -- AnchorPoint (0.5, 1) means Position is the bottom-center of the frame.
                        -- No lerp needed — WorldToViewportPoint is already smooth because it
                        -- reads the interpolated camera + character state at render time.
                        data.frame.Visible  = true
                        data.frame.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
                else
                        data.frame.Visible = false
                end
        end
end)

-- ── Create or fetch the container frame for a character ───────────────────────
local function getOrCreateSpeaker(character: Model): Frame?
        local head = character:FindFirstChild("Head")
        if not head then return nil end

        local charName = character.Name

        if activeSpeakers[charName] then
                activeSpeakers[charName].head = head   -- refresh on respawn
                return activeSpeakers[charName].frame
        end

        -- Container: wide enough for the longest bubble, tall enough for a stack.
        -- AnchorPoint (0.5, 1) → Position drives the bottom-center pixel.
        local frame = Instance.new("Frame")
        frame.Name                   = "SpeakerBubbles_" .. charName
        frame.AnchorPoint            = Vector2.new(0.5, 1)
        frame.Size                   = UDim2.fromOffset(
                CFG.BUBBLE_MAX_WIDTH + CFG.BUBBLE_PADDING_H * 2 + 16,
                400   -- tall enough for several stacked bubbles; content clips nothing
        )
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel        = 0
        frame.ClipsDescendants       = false
        frame.Parent                 = bubbleGui

        local layout = Instance.new("UIListLayout")
        layout.FillDirection       = Enum.FillDirection.Vertical
        layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom   -- stack grows upward
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.SortOrder           = Enum.SortOrder.LayoutOrder
        layout.Padding             = UDim.new(0, 3)
        layout.Parent              = frame

        activeSpeakers[charName] = { frame = frame, head = head }
        return frame
end

-- ── Spawn a single chat bubble ────────────────────────────────────────────────
local function createBubble(character: Model, text: string)
        local stack = getOrCreateSpeaker(character)
        if not stack then return end

        local charName = character.Name
        bubbleCounts[charName] = (bubbleCounts[charName] or 0) + 1
        local myOrder = bubbleCounts[charName]

        local bubble = Instance.new("Frame")
        bubble.Name                   = "Bubble"
        bubble.LayoutOrder            = myOrder
        bubble.AutomaticSize          = Enum.AutomaticSize.XY
        bubble.Size                   = UDim2.new(0, 0, 0, 0)
        bubble.BackgroundColor3       = CFG.BUBBLE_BG_COLOR
        bubble.BackgroundTransparency = 1
        bubble.BorderSizePixel        = 0
        bubble.Parent                 = stack

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, CFG.BUBBLE_CORNER)
        corner.Parent = bubble

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft   = UDim.new(0, CFG.BUBBLE_PADDING_H)
        pad.PaddingRight  = UDim.new(0, CFG.BUBBLE_PADDING_H)
        pad.PaddingTop    = UDim.new(0, CFG.BUBBLE_PADDING_V)
        pad.PaddingBottom = UDim.new(0, CFG.BUBBLE_PADDING_V)
        pad.Parent = bubble

        local label = Instance.new("TextLabel")
        label.Name                   = "ChatText"
        label.BackgroundTransparency = 1
        label.AutomaticSize          = Enum.AutomaticSize.XY
        label.Size                   = UDim2.new(0, 0, 0, 0)
        label.MaxVisibleGraphemes    = 0
        label.Font                   = CFG.BUBBLE_FONT
        label.TextSize               = CFG.BUBBLE_TEXT_SIZE
        label.TextColor3             = CFG.BUBBLE_TEXT_COLOR
        label.TextXAlignment         = Enum.TextXAlignment.Left
        label.TextWrapped            = true
        label.RichText               = false
        label.TextTransparency       = 1
        label.Text                   = text
        label.Parent                 = bubble

        task.spawn(function()
                -- Fade in pill + text instantly
                label.MaxVisibleGraphemes = -1
                local inInfo = TweenInfo.new(CFG.FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                TweenService:Create(bubble, inInfo, { BackgroundTransparency = CFG.BUBBLE_BG_TRANS }):Play()
                TweenService:Create(label,  inInfo, { TextTransparency = 0 }):Play()

                task.wait(CFG.HOLD_DURATION)

                -- Fade out
                local outInfo = TweenInfo.new(CFG.FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                TweenService:Create(bubble, outInfo, { BackgroundTransparency = 1 }):Play()
                TweenService:Create(label,  outInfo, { TextTransparency = 1 }):Play()
                task.wait(CFG.FADE_OUT_TIME)

                bubble:Destroy()
                bubbleCounts[charName] = math.max(0, (bubbleCounts[charName] or 1) - 1)

                -- Clean up the speaker container once all its bubbles are gone
                if bubbleCounts[charName] == 0 then
                        bubbleCounts[charName] = nil
                        local data = activeSpeakers[charName]
                        if data then
                                data.frame:Destroy()
                                activeSpeakers[charName] = nil
                        end
                end
        end)
end

-- ─── Player cleanup — remove stale speaker frames when a player leaves ────────
Players.PlayerRemoving:Connect(function(player: Player)
        local data = activeSpeakers[player.Name]
        if data then
                pcall(function() data.frame:Destroy() end)
                activeSpeakers[player.Name] = nil
                bubbleCounts[player.Name]   = nil
        end
end)

-- ─── Receive chat message ─────────────────────────────────────────────────────
local function onMessageReceived(payload: table)
        local senderName = payload.senderName
        if not senderName then return end

        local sender = Players:FindFirstChild(senderName)
        if not sender then return end

        -- Use Character if already loaded; otherwise wait up to 3 s then bail.
        -- Avoids an unbounded yield if the sender disconnects before respawning.
        local character = sender.Character
        if not character then
                local ok = false
                task.spawn(function()
                        local conn
                        conn = sender.CharacterAdded:Connect(function(char)
                                conn:Disconnect()
                                ok = true
                                createBubble(char, payload.message)
                        end)
                        task.wait(3)
                        if not ok then
                                pcall(function() conn:Disconnect() end)
                        end
                end)
                return   -- bubble will be created inside the spawned task above
        end

        createBubble(character, payload.message)
end

ChatRemotes.MessageReceived.OnClientEvent:Connect(onMessageReceived)

-- ─── Input handling ───────────────────────────────────────────────────────────
local MAX_CHARS = 200

inputBox:GetPropertyChangedSignal("Text"):Connect(function()
        if #inputBox.Text > MAX_CHARS then
                inputBox.Text = inputBox.Text:sub(1, MAX_CHARS)
        end
end)

local function submitMessage()
        local text = inputBox.Text:match("^%s*(.-)%s*$")
        if text ~= "" then
                ChatRemotes.MessageSent:FireServer(text)
        end
        inputBox.Text = ""
        inputBox:ReleaseFocus()
end

sendBtn.MouseButton1Click:Connect(submitMessage)

inputFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
                inputBox:CaptureFocus()
        end
end)

inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
                submitMessage()
        end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.Slash then
                inputBox:CaptureFocus()
        elseif input.KeyCode == Enum.KeyCode.Escape then
                inputBox.Text = ""
                inputBox:ReleaseFocus()
        end
end)

print("[ChatClient] Proximity chat bubbles active.")
