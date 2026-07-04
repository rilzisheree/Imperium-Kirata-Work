--[[
        ChatClient.client.lua
        LocalScript — StarterPlayerScripts

        Proximity chat system — client side:
          • Disables the default Roblox CoreGui chat
          • Minimal top-left input bar (press / or Enter to focus)
          • When a message is received, creates a BillboardGui bubble
            above the sender's character — styled exactly like the
            screenshot (white rounded pill, dark text, smooth fade)
          • Only players within MAX_DISTANCE on the server receive
            the event, so bubbles never appear for out-of-range players
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

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

-- ─── Input bar (bottom-center, matches reference design) ─────────────────────
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
inputFrame.Position               = UDim2.new(0, 8, 0, 62)   -- top-left, just below Roblox icon buttons
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

-- Text box (leaves room on the right for the send button)
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

-- Send button (►) on the right
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

-- ─── Bubble system — BillboardGui attached to Head (smooth, no jitter) ────────

local bubbleCounts = {}

local function getOrCreateBillboard(character: Model)
        local head = character:FindFirstChild("Head")
        if not head then return nil, nil end

        local existing = head:FindFirstChild("ImperiumBubbleGui")
        if existing then
                return existing, existing:FindFirstChild("BubbleStack")
        end

        local billboard = Instance.new("BillboardGui")
        billboard.Name             = "ImperiumBubbleGui"
        billboard.Adornee          = head
        -- Height in STUDS (Y scale) so the bottom of the frame is pinned to the
        -- same world-space point above the head regardless of camera zoom.
        -- Bottom = StudsOffsetWorldSpace.Y - (height/2) = 3 - 2 = 1 stud above head.
        billboard.Size                  = UDim2.new(0, CFG.BUBBLE_MAX_WIDTH + CFG.BUBBLE_PADDING_H * 2 + 16, 4, 0)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop           = false
        billboard.ResetOnSpawn          = false
        billboard.ClipsDescendants      = false
        billboard.Parent                = head

        local stack = Instance.new("Frame")
        stack.Name                   = "BubbleStack"
        stack.BackgroundTransparency = 1
        stack.Size                   = UDim2.new(1, 0, 1, 0)
        stack.BorderSizePixel        = 0
        stack.ClipsDescendants       = false
        stack.Parent                 = billboard

        local layout = Instance.new("UIListLayout")
        layout.FillDirection       = Enum.FillDirection.Vertical
        layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.SortOrder           = Enum.SortOrder.LayoutOrder
        layout.Padding             = UDim.new(0, 3)
        layout.Parent              = stack

        return billboard, stack
end

local function createBubble(character: Model, text: string)
        local billboard, stack = getOrCreateBillboard(character)
        if not billboard or not stack then return end

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
                -- Smooth typewriter-style reveal then fade in pill
                local inInfo = TweenInfo.new(CFG.FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                TweenService:Create(bubble, inInfo, { BackgroundTransparency = CFG.BUBBLE_BG_TRANS }):Play()
                TweenService:Create(label,  inInfo, { TextTransparency = 0 }):Play()

                -- Reveal text character by character
                local totalChars = utf8.len(text) or #text
                for i = 1, totalChars do
                        label.MaxVisibleGraphemes = i
                        task.wait(0.03)
                end
                label.MaxVisibleGraphemes = -1

                task.wait(CFG.HOLD_DURATION)

                local outInfo = TweenInfo.new(CFG.FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                TweenService:Create(bubble, outInfo, { BackgroundTransparency = 1 }):Play()
                TweenService:Create(label,  outInfo, { TextTransparency = 1 }):Play()
                task.wait(CFG.FADE_OUT_TIME)

                bubble:Destroy()
                bubbleCounts[charName] = math.max(0, (bubbleCounts[charName] or 1) - 1)

                if bubbleCounts[charName] == 0 then
                        bubbleCounts[charName] = nil
                        if billboard and billboard.Parent then
                                billboard:Destroy()
                        end
                end
        end)
end

-- ─── Receive chat message ─────────────────────────────────────────────────────

local function onMessageReceived(payload: table)
        local senderName = payload.senderName
        if not senderName then return end

        -- Find the sender in the Players list
        local sender = Players:FindFirstChild(senderName)
        if not sender then return end

        local character = sender.Character
        if not character then
                -- Wait briefly in case they just spawned
                character = sender.CharacterAdded:Wait()
        end

        createBubble(character, payload.message)
end

ChatRemotes.MessageReceived.OnClientEvent:Connect(onMessageReceived)

-- ─── Input handling ───────────────────────────────────────────────────────────

local MAX_CHARS = 200

inputBox:GetPropertyChangedSignal("Text"):Connect(function()
        local len = #inputBox.Text
        if len > MAX_CHARS then
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

-- Send button click
sendBtn.MouseButton1Click:Connect(submitMessage)

-- Clicking anywhere on the bar focuses the text box
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

-- Press / to focus input
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
