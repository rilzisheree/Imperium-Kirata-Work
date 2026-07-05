--[[
	ChatClient.client.lua
	LocalScript — StarterPlayerScripts

	Proximity chat:
	  • Press /  to open the input bar (ContextActionService intercepts before TextChatService)
	  • Press Enter or click → to send
	  • Press Escape to dismiss without sending
	  • BillboardGui bubbles rendered on each speaker's Head (zoom-independent)
	  • Distance tiers per frame: full (≤23 studs) / [Inaudible] (≤33) / hidden
	  • `chatlogs` command opens the log window
--]]

-- ── Services ────────────────────────────────────────────────────────────────
local ContextActionService = game:GetService("ContextActionService")
local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local RunService           = game:GetService("RunService")
local StarterGui           = game:GetService("StarterGui")
local TweenService         = game:GetService("TweenService")
local UserInputService     = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ── 1. Kill every Roblox default chat surface ────────────────────────────────

-- CoreGui chat (legacy bubble chat panel)
local function killCoreChat()
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false) end)
end
killCoreChat()
task.delay(1, killCoreChat)

-- TextChatService chat bar + window + bubble chat
-- (default.project.json already sets them, but do it in code too as belt-and-suspenders)
task.spawn(function()
	local TCS = game:GetService("TextChatService")
	local function off(className)
		local obj = TCS:FindFirstChildOfClass(className)
		if not obj then obj = TCS:WaitForChild(className, 5) end
		if obj then pcall(function() obj.Enabled = false end) end
	end
	off("ChatInputBarConfiguration")
	off("ChatWindowConfiguration")
	off("BubbleChatConfiguration")
end)

-- ── 2. Load remotes (server creates them; we wait) ───────────────────────────
local ChatRemotes = require(ReplicatedStorage:WaitForChild("ChatRemotes"))

-- ── 3. Constants ─────────────────────────────────────────────────────────────
local FULL_DISTANCE    = 23     -- studs: full text
local MUFFLED_DISTANCE = 33     -- studs: [Inaudible]
local HOLD_DURATION    = 7      -- seconds bubble stays on screen
local FADE_IN          = 0.18
local FADE_OUT         = 0.45
local MAX_CHARS        = 200

local BUBBLE_W    = 240         -- BillboardGui pixel width
local BUBBLE_H    = 300         -- BillboardGui pixel height (enough for a stack)
local BUBBLE_YOFF = 2.5         -- studs above Head centre
local PAD_H       = 12
local PAD_V       = 7
local CORNER      = 10
local FONT        = Enum.Font.GothamSemibold
local TEXT_SIZE   = 15
local BG_COLOR    = Color3.fromRGB(240, 240, 240)
local BG_TRANS    = 0.06
local TEXT_COLOR  = Color3.fromRGB(25, 25, 25)

-- ══════════════════════════════════════════════════════════════════════════════
-- 4. INPUT BAR
-- ══════════════════════════════════════════════════════════════════════════════

local BAR_H = 36
local BTN_W = 34

local inputGui = Instance.new("ScreenGui")
inputGui.Name           = "ChatInput"
inputGui.DisplayOrder   = 20
inputGui.ResetOnSpawn   = false
inputGui.IgnoreGuiInset = true
inputGui.Parent         = PlayerGui

local inputFrame = Instance.new("Frame", inputGui)
inputFrame.AnchorPoint            = Vector2.new(0, 0)
inputFrame.Size                   = UDim2.new(0.20, 0, 0, BAR_H)
inputFrame.Position               = UDim2.new(0, 8, 0, 62)
inputFrame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
inputFrame.BackgroundTransparency = 0.25
inputFrame.BorderSizePixel        = 0
do
	Instance.new("UICorner", inputFrame).CornerRadius = UDim.new(0, 7)
	local s = Instance.new("UIStroke", inputFrame)
	s.Color = Color3.fromRGB(35, 35, 35)  s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local inputBox = Instance.new("TextBox", inputFrame)
inputBox.Size                   = UDim2.new(1, -(BTN_W + 18), 1, 0)
inputBox.Position               = UDim2.new(0, 14, 0, 0)
inputBox.BackgroundTransparency = 1
inputBox.BorderSizePixel        = 0
inputBox.ClearTextOnFocus       = false
inputBox.Font                   = Enum.Font.GothamSemibold
inputBox.TextSize               = 14
inputBox.TextColor3             = Color3.fromRGB(225, 225, 240)
inputBox.PlaceholderText        = "Press / to chat"
inputBox.PlaceholderColor3      = Color3.fromRGB(120, 128, 160)
inputBox.Text                   = ""
inputBox.TextXAlignment         = Enum.TextXAlignment.Left
inputBox.TextYAlignment         = Enum.TextYAlignment.Center
inputBox.MultiLine              = false

local sendBtn = Instance.new("TextButton", inputFrame)
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
do
	Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 5)
	local s = Instance.new("UIStroke", sendBtn)
	s.Color = Color3.fromRGB(35, 35, 35)  s.Thickness = 1
	s.Transparency = 0.3  s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 5. BUBBLE SYSTEM  (BillboardGui parented directly to each speaker's Head)
-- ══════════════════════════════════════════════════════════════════════════════
--
-- speakers[playerName] = {
--     gui       = BillboardGui   (child of Head),
--     container = Frame          (fills gui, UIListLayout bottom-aligned),
--     count     = number         (monotonic LayoutOrder counter),
--     bubbles   = { { label=TextLabel, originalText=string } ... }
-- }
--
-- On Heartbeat we check distance to each speaker and update text tier or hide.
-- BillboardGui handles all camera-facing + world-space positioning automatically.

local speakers = {}

local function getOrMakeSpeaker(character)
	local head = character:FindFirstChild("Head")
	if not head then return nil end
	local pname = character.Name

	-- Re-use existing if still alive
	local existing = speakers[pname]
	if existing and existing.gui and existing.gui.Parent == head then
		return existing
	end

	-- Destroy stale gui if the head changed (respawn)
	if existing then pcall(function() existing.gui:Destroy() end) end

	local gui = Instance.new("BillboardGui")
	gui.Name             = "ChatBubbles"
	gui.Size             = UDim2.fromOffset(BUBBLE_W, BUBBLE_H)
	gui.StudsOffset      = Vector3.new(0, BUBBLE_YOFF, 0)
	gui.AlwaysOnTop      = false
	gui.LightInfluence   = 0
	gui.ClipsDescendants = false
	gui.Enabled          = true
	gui.Parent           = head

	local container = Instance.new("Frame", gui)
	container.Size                   = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.BorderSizePixel        = 0
	container.Active                 = false   -- never consume input

	local layout = Instance.new("UIListLayout", container)
	layout.FillDirection       = Enum.FillDirection.Vertical
	layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder           = Enum.SortOrder.LayoutOrder
	layout.Padding             = UDim.new(0, 3)

	local data = { gui = gui, container = container, count = 0, bubbles = {} }
	speakers[pname] = data
	return data
end

-- Per-frame: update distance-based text tier for every active speaker
RunService.Heartbeat:Connect(function()
	local localChar = LocalPlayer.Character
	local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

	for pname, data in pairs(speakers) do
		local gui = data.gui
		if not gui or not gui.Parent then
			speakers[pname] = nil
			continue
		end

		local isLocalPlayer = (pname == LocalPlayer.Name)
		local showFull      = isLocalPlayer

		if not isLocalPlayer then
			if localRoot then
				local head  = gui.Parent  -- BillboardGui is parented to Head
				local char  = head and head.Parent
				local root  = char and char:FindFirstChild("HumanoidRootPart")
				if root and root.Parent then
					local dist = (localRoot.Position - root.Position).Magnitude
					gui.Enabled = (dist <= MUFFLED_DISTANCE)
					showFull    = (dist <= FULL_DISTANCE)
				else
					gui.Enabled = false
				end
			else
				gui.Enabled = false
			end
		end

		for _, b in ipairs(data.bubbles) do
			if b.label and b.label.Parent then
				local want = showFull and b.originalText or "[ Inaudible ]"
				if b.label.Text ~= want then b.label.Text = want end
			end
		end
	end
end)

local function createBubble(character, text)
	local data = getOrMakeSpeaker(character)
	if not data then return end

	data.count += 1
	local order = data.count

	local bubble = Instance.new("Frame", data.container)
	bubble.LayoutOrder            = order
	bubble.AutomaticSize          = Enum.AutomaticSize.XY
	bubble.Size                   = UDim2.new(0, 0, 0, 0)
	bubble.BackgroundColor3       = BG_COLOR
	bubble.BackgroundTransparency = 1
	bubble.BorderSizePixel        = 0
	bubble.Active                 = false

	Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, CORNER)

	local sizeLimit = Instance.new("UISizeConstraint", bubble)
	sizeLimit.MaxSize = Vector2.new(BUBBLE_W - 16, math.huge)

	local pad = Instance.new("UIPadding", bubble)
	pad.PaddingLeft   = UDim.new(0, PAD_H)
	pad.PaddingRight  = UDim.new(0, PAD_H)
	pad.PaddingTop    = UDim.new(0, PAD_V)
	pad.PaddingBottom = UDim.new(0, PAD_V)

	local label = Instance.new("TextLabel", bubble)
	label.BackgroundTransparency = 1
	label.AutomaticSize          = Enum.AutomaticSize.XY
	label.Size                   = UDim2.new(0, 0, 0, 0)
	label.Font                   = FONT
	label.TextSize               = TEXT_SIZE
	label.TextColor3             = TEXT_COLOR
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.TextWrapped            = true
	label.RichText               = false
	label.TextTransparency       = 1
	label.Text                   = text

	-- Track for distance-based text updates
	local entry = { label = label, originalText = text }
	table.insert(data.bubbles, entry)

	-- Fade in → hold → fade out → destroy
	task.spawn(function()
		local inTI  = TweenInfo.new(FADE_IN,  Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local outTI = TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		TweenService:Create(bubble, inTI, { BackgroundTransparency = BG_TRANS }):Play()
		TweenService:Create(label,  inTI, { TextTransparency = 0 }):Play()

		task.wait(HOLD_DURATION)

		TweenService:Create(bubble, outTI, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label,  outTI, { TextTransparency = 1 }):Play()
		task.wait(FADE_OUT)

		-- Remove entry from bubbles list
		local idx = table.find(data.bubbles, entry)
		if idx then table.remove(data.bubbles, idx) end

		bubble:Destroy()

		-- If no more bubbles, clean up the whole speaker slot
		if #data.bubbles == 0 then
			pcall(function() data.gui:Destroy() end)
			speakers[character.Name] = nil
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local data = speakers[player.Name]
	if data then
		pcall(function() data.gui:Destroy() end)
		speakers[player.Name] = nil
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- 6. CHAT LOG STORAGE
-- ══════════════════════════════════════════════════════════════════════════════

local MAX_LOG    = 500
local logEntries = {}   -- { teamName, teamColor, username, message }

-- ══════════════════════════════════════════════════════════════════════════════
-- 7. CHAT LOGS WINDOW
-- ══════════════════════════════════════════════════════════════════════════════

local LC = {
	BG        = Color3.fromRGB(12,  12,  18),
	TITLE_BG  = Color3.fromRGB(20,  20,  32),
	BORDER    = Color3.fromRGB(70,  70, 100),
	TEXT      = Color3.fromRGB(220, 220, 235),
	DIM       = Color3.fromRGB(90,  90, 110),
	ROW_ALT   = Color3.fromRGB(18,  18,  28),
	SEARCH_BG = Color3.fromRGB(8,    8,  14),
}

local logsGui = Instance.new("ScreenGui")
logsGui.Name           = "ChatLogsGui"
logsGui.DisplayOrder   = 50
logsGui.ResetOnSpawn   = false
logsGui.IgnoreGuiInset = true
logsGui.Parent         = PlayerGui

local logsWindow = Instance.new("Frame", logsGui)
logsWindow.AnchorPoint      = Vector2.new(0.5, 0.5)
logsWindow.Position         = UDim2.new(0.5, 0, 0.5, 0)
logsWindow.Size             = UDim2.fromOffset(520, 420)
logsWindow.BackgroundColor3 = LC.BG
logsWindow.BorderSizePixel  = 0
logsWindow.Visible          = false
logsWindow.ClipsDescendants = false
do
	Instance.new("UICorner", logsWindow).CornerRadius = UDim.new(0, 8)
	local s = Instance.new("UIStroke", logsWindow)
	s.Color = LC.BORDER  s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local TITLE_H  = 36
local SEARCH_H = 34

local titleBar = Instance.new("Frame", logsWindow)
titleBar.Size             = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundColor3 = LC.TITLE_BG
titleBar.BorderSizePixel  = 0
do
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)
	-- Cover the bottom rounded corners so the title bar joins cleanly
	local cover = Instance.new("Frame", titleBar)
	cover.Size             = UDim2.new(1, 0, 0, 8)
	cover.Position         = UDim2.new(0, 0, 1, -8)
	cover.BackgroundColor3 = LC.TITLE_BG
	cover.BorderSizePixel  = 0
end

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size               = UDim2.new(1, -50, 1, 0)
titleLabel.Position           = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font               = Enum.Font.GothamBold
titleLabel.TextSize           = 14
titleLabel.TextColor3         = LC.TEXT
titleLabel.Text               = "Chat Logs"
titleLabel.TextXAlignment     = Enum.TextXAlignment.Left
titleLabel.TextYAlignment     = Enum.TextYAlignment.Center

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
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

local searchFrame = Instance.new("Frame", logsWindow)
searchFrame.Size             = UDim2.new(1, -16, 0, SEARCH_H)
searchFrame.Position         = UDim2.new(0, 8, 0, TITLE_H + 6)
searchFrame.BackgroundColor3 = LC.SEARCH_BG
searchFrame.BorderSizePixel  = 0
do
	Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 6)
	local s = Instance.new("UIStroke", searchFrame)
	s.Color = LC.BORDER  s.Thickness = 1  s.Transparency = 0.4
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
searchBox.TextColor3         = LC.TEXT
searchBox.PlaceholderText    = "Search chatlogs…"
searchBox.PlaceholderColor3  = LC.DIM
searchBox.Text               = ""
searchBox.TextXAlignment     = Enum.TextXAlignment.Left
searchBox.TextYAlignment     = Enum.TextYAlignment.Center
searchBox.TextEditable       = false   -- enabled only while the window is open

local SCROLL_TOP = TITLE_H + SEARCH_H + 14

local scrollFrame = Instance.new("ScrollingFrame", logsWindow)
scrollFrame.Size                   = UDim2.new(1, -8, 1, -(SCROLL_TOP + 8))
scrollFrame.Position               = UDim2.new(0, 4, 0, SCROLL_TOP)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel        = 0
scrollFrame.ScrollBarThickness     = 4
scrollFrame.ScrollBarImageColor3   = LC.BORDER
scrollFrame.AutomaticCanvasSize    = Enum.AutomaticCanvasSize.Y
scrollFrame.CanvasSize             = UDim2.new(0, 0, 0, 0)
scrollFrame.ScrollingDirection     = Enum.ScrollingDirection.Y
scrollFrame.ClipsDescendants       = true
do
	local l = Instance.new("UIListLayout", scrollFrame)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Left
	l.Padding = UDim.new(0, 1)

	local p = Instance.new("UIPadding", scrollFrame)
	p.PaddingLeft = UDim.new(0, 4)  p.PaddingRight = UDim.new(0, 4)
	p.PaddingTop  = UDim.new(0, 3)
end

-- Log helpers
local function toHex(c)
	return string.format("#%02X%02X%02X",
		math.clamp(math.round(c.R * 255), 0, 255),
		math.clamp(math.round(c.G * 255), 0, 255),
		math.clamp(math.round(c.B * 255), 0, 255))
end

local function entryMatchesFilter(entry, filter)
	if filter == "" then return true end
	local f = filter:lower()
	return entry.teamName:lower():find(f, 1, true) ~= nil
		or entry.username:lower():find(f, 1, true)  ~= nil
		or entry.message:lower():find(f, 1, true)   ~= nil
end

local function buildLogRow(entry, order)
	local lbl = Instance.new("TextLabel", scrollFrame)
	lbl.LayoutOrder            = order
	lbl.Size                   = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize          = Enum.AutomaticSize.Y
	lbl.BackgroundColor3       = LC.ROW_ALT
	lbl.BackgroundTransparency = (order % 2 == 0) and 0.85 or 1
	lbl.BorderSizePixel        = 0
	lbl.Font                   = Enum.Font.Gotham
	lbl.TextSize               = 12
	lbl.TextColor3             = LC.TEXT
	lbl.RichText               = true
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.TextYAlignment         = Enum.TextYAlignment.Top
	lbl.TextWrapped            = true
	lbl.Text = string.format(
		'<font color="%s">{%s}</font> [%s]: "%s"',
		toHex(entry.teamColor), entry.teamName, entry.username, entry.message)
	local pad = Instance.new("UIPadding", lbl)
	pad.PaddingLeft = UDim.new(0, 6)  pad.PaddingRight  = UDim.new(0, 6)
	pad.PaddingTop  = UDim.new(0, 4)  pad.PaddingBottom = UDim.new(0, 4)
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
	for _, entry in ipairs(logEntries) do
		if entryMatchesFilter(entry, filter) then
			order += 1
			buildLogRow(entry, order)
		end
	end
	scrollToBottom()
end

local function appendOneLogRow(entry)
	if not entryMatchesFilter(entry, searchBox.Text:lower()) then return end
	local order = 0
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("TextLabel") then order += 1 end
	end
	buildLogRow(entry, order + 1)
	scrollToBottom()
end

local function closeChatLogs()
	logsWindow.Visible     = false
	searchBox.TextEditable = false
	searchBox.Text         = ""
end

local function openChatLogs()
	logsWindow.Visible     = true
	searchBox.TextEditable = true
	rebuildLogDisplay()
end

shared.OpenChatLogsWindow = openChatLogs   -- CommandBar reads this

closeBtn.MouseButton1Click:Connect(closeChatLogs)
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if logsWindow.Visible then rebuildLogDisplay() end
end)

-- Drag via title bar
do
	local dragging = false
	local dragStart, winStart = Vector3.new(), UDim2.new()

	local dragBtn = Instance.new("TextButton", titleBar)
	dragBtn.Size               = UDim2.new(1, -44, 1, 0)
	dragBtn.BackgroundTransparency = 1
	dragBtn.Text               = ""
	dragBtn.ZIndex             = 5

	dragBtn.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true  dragStart = inp.Position  winStart = logsWindow.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
			local d = inp.Position - dragStart
			logsWindow.Position = UDim2.new(
				winStart.X.Scale, winStart.X.Offset + d.X,
				winStart.Y.Scale, winStart.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 8. RECEIVE MESSAGES
-- ══════════════════════════════════════════════════════════════════════════════

ChatRemotes.MessageReceived.OnClientEvent:Connect(function(payload)
	if not payload or not payload.senderName then return end

	local sender = Players:FindFirstChild(payload.senderName)
	if not sender then return end

	-- Log entry
	local entry = {
		teamName  = payload.teamName  or "No Team",
		teamColor = Color3.new(
			payload.teamColorR or 0.8,
			payload.teamColorG or 0.8,
			payload.teamColorB or 0.8),
		username  = payload.displayName or payload.senderName,
		message   = payload.message,
	}
	table.insert(logEntries, entry)
	if #logEntries > MAX_LOG then table.remove(logEntries, 1) end
	if logsWindow.Visible then appendOneLogRow(entry) end

	-- Bubble
	local character = sender.Character
	if character then
		createBubble(character, payload.message)
	else
		-- Wait briefly for the character to load (e.g. during respawn)
		task.spawn(function()
			local done, conn = false, nil
			conn = sender.CharacterAdded:Connect(function(char)
				conn:Disconnect()
				done = true
				createBubble(char, payload.message)
			end)
			task.wait(3)
			if not done then pcall(function() conn:Disconnect() end) end
		end)
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- 9. INPUT HANDLING
-- ══════════════════════════════════════════════════════════════════════════════

-- One-tick submit lock: prevents double-sends when FocusLost(enterPressed=true)
-- and our explicit Enter handler both fire in the same frame.
local submitting = false

local function submitMessage()
	if submitting then return end
	submitting = true
	task.defer(function() submitting = false end)

	local text = inputBox.Text:match("^%s*(.-)%s*$") or ""
	if text ~= "" then
		ChatRemotes.MessageSent:FireServer(text)
	end
	inputBox.Text = ""
	inputBox:ReleaseFocus()
end

-- Character limit
inputBox:GetPropertyChangedSignal("Text"):Connect(function()
	if #inputBox.Text > MAX_CHARS then
		inputBox.Text = inputBox.Text:sub(1, MAX_CHARS)
	end
end)

-- Send button
sendBtn.MouseButton1Click:Connect(submitMessage)

-- Click anywhere on the bar → focus the textbox
inputFrame.InputBegan:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		inputBox:CaptureFocus()
	end
end)

-- Enter via FocusLost (primary path)
inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then submitMessage() end
end)

-- ── SLASH key — ContextActionService (highest priority) ─────────────────────
--
-- CAS runs BEFORE UserInputService.InputBegan and BEFORE TextChatService
-- bindings. Returning Sink prevents any other system from seeing the event.
--
-- When inputBox is already focused we return Pass so "/" types normally.
-- When something else (or nothing) has focus we steal focus for our chat bar.
-- We defer CaptureFocus so the "/" character input (which fires after the key
-- event) finds no focused TextBox and is discarded — the box opens clean.

ContextActionService:BindAction(
	"ChatOpenSlash",
	function(_, state, _)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if UserInputService:GetFocusedTextBox() == inputBox then
			-- Already typing in our box — let "/" through as a normal character
			return Enum.ContextActionResult.Pass
		end
		-- Redirect to our chat bar. Defer so "/" isn't typed into the box.
		task.defer(function()
			inputBox.Text = ""
			inputBox:CaptureFocus()
		end)
		return Enum.ContextActionResult.Sink
	end,
	false,                  -- no touch button
	Enum.KeyCode.Slash
)

-- ── ENTER key fallback ───────────────────────────────────────────────────────
-- TextChatService can intercept Enter and deliver FocusLost(enterPressed=false).
-- This catches that case. submitting flag deduplicates with FocusLost path.
UserInputService.InputBegan:Connect(function(inp, _gameProcessed)
	if inp.KeyCode == Enum.KeyCode.Return or inp.KeyCode == Enum.KeyCode.KeypadEnter then
		if UserInputService:GetFocusedTextBox() == inputBox then
			submitMessage()
		end
		return
	end

	if inp.KeyCode == Enum.KeyCode.Escape then
		if UserInputService:GetFocusedTextBox() == inputBox then
			inputBox.Text = ""
			inputBox:ReleaseFocus()
		end
	end
end)

print("[ChatClient] Ready — press / to chat")
