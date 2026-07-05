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
local WORLD_Y_OFFSET = 1.5   -- studs

-- Distance thresholds — must match FULL_DISTANCE / MUFFLED_DISTANCE on the server.
-- The server only fires events to players within MUFFLED_DISTANCE, so the client
-- only needs to decide between "full text" and ". . ." for each active bubble.
local FULL_DISTANCE    = 23   -- studs: show the real message
local MUFFLED_DISTANCE = 33   -- studs: show [ Inaudible ] beyond this → hidden

local bubbleGui = Instance.new("ScreenGui")
bubbleGui.Name           = "ChatBubbles"
bubbleGui.DisplayOrder   = 15
bubbleGui.ResetOnSpawn   = false
bubbleGui.IgnoreGuiInset = true
bubbleGui.Parent         = PlayerGui

-- activeSpeakers[charName] = {
--   frame     = Frame,
--   head      = BasePart,
--   character = Model,
--   bubbles   = { [TextLabel] = originalText }   ← tracked for live text updates
-- }
local activeSpeakers = {}
local bubbleCounts   = {}

-- ── Local-player root cache (updated on character load/respawn) ───────────────
local localRoot = nil
local function refreshLocalRoot(char)
        char = char or LocalPlayer.Character
        localRoot = char and char:FindFirstChild("HumanoidRootPart")
end
refreshLocalRoot()
LocalPlayer.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart", 10)
        refreshLocalRoot(char)
end)

-- ── RenderStepped: reposition + live distance-text update every frame ────────
RunService.RenderStepped:Connect(function()
        -- Re-read CurrentCamera each frame — it can be replaced (e.g. cutscenes).
        local cam = workspace.CurrentCamera
        if not cam then return end

        -- Lazily refresh local root if it went stale (e.g. mid-respawn).
        if not localRoot or not localRoot.Parent then
                refreshLocalRoot()
        end

        for charName, data in pairs(activeSpeakers) do
                local head = data.head
                if not head or not head.Parent then
                        data.frame.Visible = false
                        continue
                end

                -- ── 1. Screen position ────────────────────────────────────────
                local worldPos = head.Position + Vector3.new(0, WORLD_Y_OFFSET, 0)
                local screenPos, onScreen = cam:WorldToViewportPoint(worldPos)

                if not (onScreen and screenPos.Z > 0) then
                        data.frame.Visible = false
                        continue
                end

                data.frame.Visible  = true
                data.frame.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)

                -- ── 2. Distance-based text (runs every frame while visible) ──
                -- Sender always sees their own full text.
                local showFull = (charName == LocalPlayer.Name)

                if not showFull and localRoot then
                        local senderRoot = data.character
                                and data.character:FindFirstChild("HumanoidRootPart")
                        if senderRoot and senderRoot.Parent then
                                local dist = (localRoot.Position - senderRoot.Position).Magnitude
                                if dist > MUFFLED_DISTANCE then
                                        -- Shouldn't normally happen (server filters these out),
                                        -- but hide cleanly if it does.
                                        data.frame.Visible = false
                                        continue
                                end
                                showFull = dist <= FULL_DISTANCE
                        end
                end

                -- Apply correct text to every live label for this speaker.
                for label, originalText in pairs(data.bubbles) do
                        if label.Parent then
                                local want = showFull and originalText or "[ Inaudible ]"
                                if label.Text ~= want then   -- skip write if already correct
                                        label.Text = want
                                end
                        end
                end
        end
end)

-- ── Create or fetch the container frame for a character ───────────────────────
local function getOrCreateSpeaker(character: Model): Frame?
        local head = character:FindFirstChild("Head")
        if not head then return nil end

        local charName = character.Name

        if activeSpeakers[charName] then
                activeSpeakers[charName].head      = head        -- refresh on respawn
                activeSpeakers[charName].character = character
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

        activeSpeakers[charName] = {
                frame     = frame,
                head      = head,
                character = character,
                bubbles   = {},   -- [TextLabel] = originalText, for live text updates
        }
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

        -- Register this label so the RenderStepped loop can update its text live.
        local speakerData = activeSpeakers[charName]
        if speakerData then
                speakerData.bubbles[label] = text   -- originalText
        end

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

                -- Deregister label before destroying so RenderStepped stops touching it.
                local data = activeSpeakers[charName]
                if data then
                        data.bubbles[label] = nil
                end

                bubble:Destroy()
                bubbleCounts[charName] = math.max(0, (bubbleCounts[charName] or 1) - 1)

                -- Clean up the speaker container once all its bubbles are gone.
                if bubbleCounts[charName] == 0 then
                        bubbleCounts[charName] = nil
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

-- ─── Chat Log storage + Window ───────────────────────────────────────────────

local MAX_LOG_ENTRIES = 500
local chatLogEntries  = {}   -- { teamName, teamColor, username, message }

local LOG_C = {
        BG        = Color3.fromRGB(12,  12,  18),
        TITLE_BG  = Color3.fromRGB(20,  20,  32),
        BORDER    = Color3.fromRGB(70,  70, 100),
        TEXT      = Color3.fromRGB(220, 220, 235),
        DIM       = Color3.fromRGB(90,  90, 110),
        ROW_ALT   = Color3.fromRGB(18,  18,  28),
        SEARCH_BG = Color3.fromRGB(8,    8,  14),
}

local WIN_W, WIN_H = 520, 420
local TITLE_H      = 36
local SEARCH_H     = 34
local SCROLL_TOP   = TITLE_H + SEARCH_H + 14

local logsGui = Instance.new("ScreenGui")
logsGui.Name           = "ChatLogsGui"
logsGui.DisplayOrder   = 50
logsGui.ResetOnSpawn   = false
logsGui.IgnoreGuiInset = false
logsGui.Parent         = PlayerGui

local logsWindow = Instance.new("Frame")
logsWindow.Name             = "Window"
logsWindow.AnchorPoint      = Vector2.new(0.5, 0.5)
logsWindow.Position         = UDim2.new(0.5, 0, 0.5, 0)
logsWindow.Size             = UDim2.fromOffset(WIN_W, WIN_H)
logsWindow.BackgroundColor3 = LOG_C.BG
logsWindow.BorderSizePixel  = 0
logsWindow.Visible          = false
logsWindow.ClipsDescendants = false
logsWindow.ZIndex           = 30
logsWindow.Parent           = logsGui
Instance.new("UICorner", logsWindow).CornerRadius = UDim.new(0, 8)
do
        local s = Instance.new("UIStroke", logsWindow)
        s.Color = LOG_C.BORDER  s.Thickness = 1.5
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- Title bar (drag handle)
local titleBar = Instance.new("Frame")
titleBar.Name             = "TitleBar"
titleBar.Size             = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundColor3 = LOG_C.TITLE_BG
titleBar.BorderSizePixel  = 0
titleBar.ZIndex           = 31
titleBar.Parent           = logsWindow
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)
do  -- square off the bottom corners with a cover patch
        local p = Instance.new("Frame", titleBar)
        p.Size = UDim2.new(1, 0, 0, 8)  p.Position = UDim2.new(0, 0, 1, -8)
        p.BackgroundColor3 = LOG_C.TITLE_BG  p.BorderSizePixel = 0  p.ZIndex = 31
end

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size               = UDim2.new(1, -50, 1, 0)
titleLabel.Position           = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font               = Enum.Font.GothamBold
titleLabel.TextSize           = 14
titleLabel.TextColor3         = LOG_C.TEXT
titleLabel.Text               = "Chat Logs"
titleLabel.TextXAlignment     = Enum.TextXAlignment.Left
titleLabel.TextYAlignment     = Enum.TextYAlignment.Center
titleLabel.ZIndex             = 32

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Size                   = UDim2.fromOffset(26, 26)
closeBtn.Position               = UDim2.new(1, -8, 0.5, 0)
closeBtn.BackgroundColor3       = Color3.fromRGB(55, 20, 20)
closeBtn.BackgroundTransparency = 0.3
closeBtn.BorderSizePixel        = 0
closeBtn.Text                   = "✕"
closeBtn.Font                   = Enum.Font.GothamBold
closeBtn.TextSize               = 12
closeBtn.TextColor3             = Color3.fromRGB(220, 90, 90)
closeBtn.AutoButtonColor        = false
closeBtn.ZIndex                 = 32
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

-- Search bar
local searchFrame = Instance.new("Frame", logsWindow)
searchFrame.Name             = "SearchFrame"
searchFrame.Size             = UDim2.new(1, -16, 0, SEARCH_H)
searchFrame.Position         = UDim2.new(0, 8, 0, TITLE_H + 6)
searchFrame.BackgroundColor3 = LOG_C.SEARCH_BG
searchFrame.BorderSizePixel  = 0
searchFrame.ZIndex           = 31
Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 6)
do
        local s = Instance.new("UIStroke", searchFrame)
        s.Color = LOG_C.BORDER  s.Thickness = 1  s.Transparency = 0.4
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local searchBox = Instance.new("TextBox", searchFrame)
searchBox.Size               = UDim2.new(1, -14, 1, 0)
searchBox.Position           = UDim2.new(0, 14, 0, 0)
searchBox.BackgroundTransparency = 1
searchBox.BorderSizePixel    = 0
searchBox.ClearTextOnFocus   = false
searchBox.Font               = Enum.Font.Gotham
searchBox.TextSize           = 13
searchBox.TextColor3         = LOG_C.TEXT
searchBox.PlaceholderText    = "Search chatlogs"
searchBox.PlaceholderColor3  = LOG_C.DIM
searchBox.Text               = ""
searchBox.TextXAlignment     = Enum.TextXAlignment.Left
searchBox.TextYAlignment     = Enum.TextYAlignment.Center
searchBox.ZIndex             = 32

-- Scroll frame
local scrollFrame = Instance.new("ScrollingFrame", logsWindow)
scrollFrame.Name                   = "LogScroll"
scrollFrame.Size                   = UDim2.new(1, -8, 1, -(SCROLL_TOP + 8))
scrollFrame.Position               = UDim2.new(0, 4, 0, SCROLL_TOP)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel        = 0
scrollFrame.ScrollBarThickness     = 4
scrollFrame.ScrollBarImageColor3   = LOG_C.BORDER
scrollFrame.AutomaticCanvasSize    = Enum.AutomaticCanvasSize.Y
scrollFrame.CanvasSize             = UDim2.new(0, 0, 0, 0)
scrollFrame.ScrollingDirection     = Enum.ScrollingDirection.Y
scrollFrame.ClipsDescendants       = true
scrollFrame.ZIndex                 = 31
do
        local l = Instance.new("UIListLayout", scrollFrame)
        l.SortOrder = Enum.SortOrder.LayoutOrder
        l.FillDirection = Enum.FillDirection.Vertical
        l.HorizontalAlignment = Enum.HorizontalAlignment.Left
        l.Padding = UDim.new(0, 1)
        local p = Instance.new("UIPadding", scrollFrame)
        p.PaddingLeft = UDim.new(0, 4)  p.PaddingRight = UDim.new(0, 4)  p.PaddingTop = UDim.new(0, 3)
end

-- ── Log helpers ───────────────────────────────────────────────────────────────

local function toHex(c: Color3): string
        return string.format("#%02X%02X%02X",
                math.clamp(math.round(c.R * 255), 0, 255),
                math.clamp(math.round(c.G * 255), 0, 255),
                math.clamp(math.round(c.B * 255), 0, 255))
end

local function entryMatchesFilter(entry: table, filter: string): boolean
        if filter == "" then return true end
        local f = filter:lower()
        return (entry.teamName:lower():find(f, 1, true) ~= nil)
            or (entry.username:lower():find(f, 1, true) ~= nil)
            or (entry.message:lower():find(f, 1, true) ~= nil)
end

local function buildLogRow(entry: table, order: number): TextLabel
        local lbl = Instance.new("TextLabel")
        lbl.LayoutOrder            = order
        lbl.Size                   = UDim2.new(1, 0, 0, 0)
        lbl.AutomaticSize          = Enum.AutomaticSize.Y
        lbl.BackgroundColor3       = LOG_C.ROW_ALT
        lbl.BackgroundTransparency = (order % 2 == 0) and 0.85 or 1
        lbl.BorderSizePixel        = 0
        lbl.Font                   = Enum.Font.Gotham
        lbl.TextSize               = 12
        lbl.TextColor3             = LOG_C.TEXT
        lbl.RichText               = true
        lbl.TextXAlignment         = Enum.TextXAlignment.Left
        lbl.TextYAlignment         = Enum.TextYAlignment.Top
        lbl.TextWrapped            = true
        lbl.ZIndex                 = 32
        lbl.Text = string.format(
                '<font color="%s">{%s}</font> [%s]: "%s"',
                toHex(entry.teamColor), entry.teamName,
                entry.username, entry.message
        )
        local pad = Instance.new("UIPadding", lbl)
        pad.PaddingLeft   = UDim.new(0, 6)
        pad.PaddingRight  = UDim.new(0, 6)
        pad.PaddingTop    = UDim.new(0, 4)
        pad.PaddingBottom = UDim.new(0, 4)
        return lbl
end

local function scrollToBottom()
        task.defer(function()
                scrollFrame.CanvasPosition = Vector2.new(0, math.huge)
        end)
end

local function rebuildLogDisplay()
        local filter = searchBox.Text:lower()
        for _, child in scrollFrame:GetChildren() do
                if child:IsA("TextLabel") then child:Destroy() end
        end
        local order = 0
        for _, entry in ipairs(chatLogEntries) do
                if entryMatchesFilter(entry, filter) then
                        order += 1
                        buildLogRow(entry, order).Parent = scrollFrame
                end
        end
        scrollToBottom()
end

-- Called when a new message arrives while the window is open.
-- Appends one row without rebuilding the whole list.
function appendLogRow(entry: table)
        local filter = searchBox.Text:lower()
        if not entryMatchesFilter(entry, filter) then return end
        local order = 0
        for _, child in scrollFrame:GetChildren() do
                if child:IsA("TextLabel") then order += 1 end
        end
        buildLogRow(entry, order + 1).Parent = scrollFrame
        scrollToBottom()
end

-- ── Open / Close ──────────────────────────────────────────────────────────────

local function closeChatLogs()
        logsWindow.Visible = false
        searchBox.Text     = ""
end

local function openChatLogs()
        logsWindow.Visible = true
        rebuildLogDisplay()
end

_G.OpenChatLogsWindow = openChatLogs   -- CommandBar calls this

closeBtn.MouseButton1Click:Connect(closeChatLogs)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        if logsWindow.Visible then rebuildLogDisplay() end
end)

-- ── Drag logic (titleBar as handle) ──────────────────────────────────────────
do
        local dragging  = false
        local dragStart = Vector3.new()
        local winStart  = UDim2.new()

        local dragBtn = Instance.new("TextButton", titleBar)
        dragBtn.Size               = UDim2.new(1, -44, 1, 0)
        dragBtn.BackgroundTransparency = 1
        dragBtn.Text               = ""
        dragBtn.ZIndex             = 33

        dragBtn.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                        dragging  = true
                        dragStart = inp.Position
                        winStart  = logsWindow.Position
                end
        end)

        UserInputService.InputChanged:Connect(function(inp)
                if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
                        local d = inp.Position - dragStart
                        logsWindow.Position = UDim2.new(
                                winStart.X.Scale, winStart.X.Offset + d.X,
                                winStart.Y.Scale, winStart.Y.Offset + d.Y
                        )
                end
        end)

        UserInputService.InputEnded:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                        dragging = false
                end
        end)
end

-- ─── Receive chat message ─────────────────────────────────────────────────────
local function onMessageReceived(payload: table)
        local senderName = payload.senderName
        if not senderName then return end

        local sender = Players:FindFirstChild(senderName)
        if not sender then return end

        -- ── Always log the message (regardless of distance / bubble) ──────────
        local entry = {
                teamName  = payload.teamName or "No Team",
                teamColor = Color3.new(
                        payload.teamColorR or 0.8,
                        payload.teamColorG or 0.8,
                        payload.teamColorB or 0.8
                ),
                username = payload.displayName or senderName,
                message  = payload.message,
        }
        table.insert(chatLogEntries, entry)
        if #chatLogEntries > MAX_LOG_ENTRIES then
                table.remove(chatLogEntries, 1)
        end
        if logsWindow.Visible then
                appendLogRow(entry)
        end

        -- ── Chat bubble ───────────────────────────────────────────────────────
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
                return
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
