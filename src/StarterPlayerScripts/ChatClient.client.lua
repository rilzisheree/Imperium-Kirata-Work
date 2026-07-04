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
local RunService        = game:GetService("RunService")

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
        -- Bubble appearance (matches the screenshot)
        BUBBLE_BG_COLOR     = Color3.fromRGB(246, 244, 233), -- warm white/cream
        BUBBLE_BG_TRANS     = 0.08,
        BUBBLE_TEXT_COLOR   = Color3.fromRGB(30, 30, 30),    -- near-black
        BUBBLE_FONT         = Enum.Font.GothamSemibold,
        BUBBLE_TEXT_SIZE    = 19,
        BUBBLE_MAX_WIDTH    = 240,   -- px — wraps beyond this
        BUBBLE_PADDING_H    = 20,    -- horizontal inner padding
        BUBBLE_PADDING_V    = 10,    -- vertical inner padding
        BUBBLE_CORNER       = 12,    -- UICorner radius (px)

        -- BillboardGui sizing & offset
        BILLBOARD_SIZE_Y    = 0.5,   -- studs above head (StudsOffsetWorldSpace)
        BILLBOARD_HEAD_OFFSET = 2.4, -- studs above HumanoidRootPart

        -- Timing
        HOLD_DURATION       = 7,     -- seconds bubble stays fully visible
        FADE_IN_TIME        = 0.35,  -- slower fade so it feels smooth
        FADE_OUT_TIME       = 0.8,
        SLIDE_DISTANCE      = 0.5,   -- studs the bubble rises during entrance

}

-- ─── Input bar (bottom-center, matches reference design) ─────────────────────
local BAR_H   = 44
local BTN_W   = 40

local inputGui = Instance.new("ScreenGui")
inputGui.Name           = "ChatInput"
inputGui.DisplayOrder   = 20
inputGui.ResetOnSpawn   = false
inputGui.IgnoreGuiInset = true
inputGui.Parent         = PlayerGui

local inputFrame = Instance.new("Frame")
inputFrame.Name                   = "InputFrame"
inputFrame.AnchorPoint            = Vector2.new(1, 0)
inputFrame.Size                   = UDim2.new(0.52, 0, 0, BAR_H)
inputFrame.Position               = UDim2.new(1, -8, 0, 8)
inputFrame.BackgroundColor3       = Color3.fromRGB(10, 12, 22)
inputFrame.BackgroundTransparency = 0.18
inputFrame.BorderSizePixel        = 0
inputFrame.Parent                 = inputGui

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 7)
inputCorner.Parent = inputFrame

local inputStroke = Instance.new("UIStroke")
inputStroke.Color           = Color3.fromRGB(48, 58, 95)
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
sendBtn.BackgroundColor3       = Color3.fromRGB(22, 26, 45)
sendBtn.BackgroundTransparency = 0
sendBtn.BorderSizePixel        = 0
sendBtn.Text                   = "▶"
sendBtn.Font                   = Enum.Font.GothamBold
sendBtn.TextSize               = 14
sendBtn.TextColor3             = Color3.fromRGB(180, 188, 220)
sendBtn.AutoButtonColor        = false
sendBtn.Parent                 = inputFrame

local sendCorner = Instance.new("UICorner")
sendCorner.CornerRadius = UDim.new(0, 5)
sendCorner.Parent = sendBtn

local sendStroke = Instance.new("UIStroke")
sendStroke.Color           = Color3.fromRGB(48, 58, 95)
sendStroke.Thickness       = 1
sendStroke.Transparency    = 0.3
sendStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
sendStroke.Parent          = sendBtn

-- ─── Bubble system — ScreenGui + Camera:WorldToScreenPoint ────────────────────
--
-- BillboardGui mixes world-space anchors with pixel sizes, so stacking always
-- breaks at some zoom level. Instead we use a plain ScreenGui: every
-- RenderStepped we project the character's head to screen coordinates and move
-- the bubble stack Frame to be exactly PIXELS_ABOVE_HEAD pixels above it.
-- Stacking is pure pixel math — perfectly consistent at every zoom level.

local PIXELS_ABOVE_HEAD = 20   -- gap between head top and the bottom of the stack
local REFERENCE_DIST    = 15   -- studs at which UIScale = 1.0 (bubbles look "normal")
local Camera            = workspace.CurrentCamera

-- ScreenGui that holds all bubble stacks
local bubbleGui = Instance.new("ScreenGui")
bubbleGui.Name           = "ChatBubbles"
bubbleGui.DisplayOrder   = 5
bubbleGui.ResetOnSpawn   = false
bubbleGui.IgnoreGuiInset = true
bubbleGui.Parent         = PlayerGui

-- Per-character state: { stackFrame, count, headRef }
local characterContainers = {}

local function tween(target, info, props)
        TweenService:Create(target, info, props):Play()
end

local function getOrCreateContainer(character: Model)
        local existing = characterContainers[character.Name]
        if existing and existing.stackFrame and existing.stackFrame.Parent == bubbleGui then
                return existing
        end

        -- Large invisible frame — UIListLayout stacks bubbles from its bottom upward
        local stackFrame = Instance.new("Frame")
        stackFrame.Name                 = "Stack_" .. character.Name
        stackFrame.BackgroundTransparency = 1
        stackFrame.Size                 = UDim2.new(0, CFG.BUBBLE_MAX_WIDTH + CFG.BUBBLE_PADDING_H * 2 + 20, 0, 400)
        stackFrame.AnchorPoint          = Vector2.new(0.5, 1)  -- anchor at bottom-centre
        stackFrame.Position             = UDim2.new(0, 0, 0, 0)
        stackFrame.ClipsDescendants     = false
        stackFrame.Parent               = bubbleGui

        local layout = Instance.new("UIListLayout")
        layout.FillDirection        = Enum.FillDirection.Vertical
        layout.VerticalAlignment    = Enum.VerticalAlignment.Bottom
        layout.HorizontalAlignment  = Enum.HorizontalAlignment.Center
        layout.SortOrder            = Enum.SortOrder.LayoutOrder
        layout.Padding              = UDim.new(0, 4)
        layout.Parent               = stackFrame

        -- UIScale drives proportional shrink/grow with camera distance
        local uiScale = Instance.new("UIScale")
        uiScale.Scale  = 1
        uiScale.Parent = stackFrame

        local head = character:FindFirstChild("Head")
        local container = {
                stackFrame = stackFrame,
                uiScale    = uiScale,
                character  = character,
                headRef    = head,
                count      = 0,
                order      = 0,
        }
        characterContainers[character.Name] = container
        return container
end

-- RenderStepped: lock every stack frame above the character's head on screen
RunService.RenderStepped:Connect(function()
        for name, container in characterContainers do
                local char = container.character
                if not char or not char.Parent then
                        if container.stackFrame then container.stackFrame:Destroy() end
                        characterContainers[name] = nil
                        continue
                end

                local head = char:FindFirstChild("Head")
                if not head then continue end

                -- Top of head in screen space (head.Position is the centre, +1 stud = top)
                local topOfHead = head.Position + Vector3.new(0, 0.6, 0)
                local screenPos, onScreen = Camera:WorldToScreenPoint(topOfHead)

                -- Scale proportionally to camera distance so bubble shrinks with character
                local dist  = (Camera.CFrame.Position - head.Position).Magnitude
                local scale = math.clamp(REFERENCE_DIST / dist, 0.3, 1.2)
                container.uiScale.Scale = scale

                if onScreen and screenPos.Z > 0 then
                        container.stackFrame.Visible = true
                        -- AnchorPoint is (0.5, 1) so Position.X/Y is the bottom-centre
                        container.stackFrame.Position = UDim2.new(
                                0, screenPos.X,
                                0, screenPos.Y - PIXELS_ABOVE_HEAD * scale
                        )
                else
                        container.stackFrame.Visible = false
                end
        end
end)

local function createBubble(character: Model, text: string)
        local container = getOrCreateContainer(character)
        container.count += 1
        container.order += 1
        local myOrder = container.order

        -- ── Bubble pill ───────────────────────────────────────────────────────────
        local bubble = Instance.new("Frame")
        bubble.Name                   = "Bubble"
        bubble.LayoutOrder            = myOrder
        bubble.Size                   = UDim2.new(0, CFG.BUBBLE_MAX_WIDTH, 0, 0)
        bubble.AutomaticSize          = Enum.AutomaticSize.Y
        bubble.BackgroundColor3       = CFG.BUBBLE_BG_COLOR
        bubble.BackgroundTransparency = 1
        bubble.BorderSizePixel        = 0
        bubble.Parent                 = container.stackFrame

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
        label.Size                   = UDim2.new(1, 0, 0, 0)
        label.AutomaticSize          = Enum.AutomaticSize.Y
        label.Font                   = CFG.BUBBLE_FONT
        label.TextSize               = CFG.BUBBLE_TEXT_SIZE
        label.TextColor3             = CFG.BUBBLE_TEXT_COLOR
        label.TextXAlignment         = Enum.TextXAlignment.Center
        label.TextYAlignment         = Enum.TextYAlignment.Center
        label.TextWrapped            = true
        label.TextTransparency       = 1
        label.Text                   = text
        label.Parent                 = bubble

        -- ── Lifecycle ─────────────────────────────────────────────────────────────
        task.spawn(function()
                local inInfo = TweenInfo.new(CFG.FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                tween(bubble, inInfo, { BackgroundTransparency = CFG.BUBBLE_BG_TRANS })
                tween(label,  inInfo, { TextTransparency = 0 })
                task.wait(CFG.FADE_IN_TIME)

                task.wait(CFG.HOLD_DURATION)

                local outInfo = TweenInfo.new(CFG.FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                tween(bubble, outInfo, { BackgroundTransparency = 1 })
                tween(label,  outInfo, { TextTransparency = 1 })
                task.wait(CFG.FADE_OUT_TIME)

                bubble:Destroy()
                container.count -= 1

                if container.count <= 0 then
                        if container.stackFrame and container.stackFrame.Parent then
                                container.stackFrame:Destroy()
                        end
                        characterContainers[character.Name] = nil
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
