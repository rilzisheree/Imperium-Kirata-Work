--[[
	ChatClient.client.lua
	LocalScript — StarterPlayerScripts

	Proximity chat system:
	  • Disables default Roblox chat (CoreGui + TextChatService input bar)
	  • Input bar: press / to open, Enter or → to send, Escape to dismiss
	  • Chat bubbles rendered via WorldToViewportPoint (zoom-independent)
	  • Distance tiers updated every frame: full (≤23 studs) / [Inaudible] (≤33) / hidden
	  • Chat logs window: open with the `chatlogs` command
--]]

-- ── Services ───────────────────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local StarterGui       = game:GetService("StarterGui")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ── Disable Roblox default chat UI ────────────────────────────────────────────
-- CoreGui chat panel (legacy + bubble):
local function disableDefaultChat()
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false) end)
end
disableDefaultChat()
task.delay(1, disableDefaultChat)   -- retry in case CoreGui isn't ready yet

-- ── Wait for chat remotes (created by ChatServer) ──────────────────────────────
local ChatRemotes = require(ReplicatedStorage:WaitForChild("ChatRemotes"))

-- ── Config ────────────────────────────────────────────────────────────────────
local BUBBLE_BG_COLOR  = Color3.fromRGB(240, 240, 240)
local BUBBLE_BG_TRANS  = 0.06
local BUBBLE_TEXT_COLOR = Color3.fromRGB(25, 25, 25)
local BUBBLE_FONT      = Enum.Font.GothamSemibold
local BUBBLE_TEXT_SIZE = 16
local BUBBLE_MAX_WIDTH = 200
local BUBBLE_PAD_H     = 12
local BUBBLE_PAD_V     = 7
local BUBBLE_CORNER    = 10
local HOLD_DURATION    = 7
local FADE_IN          = 0.2
local FADE_OUT         = 0.5
local WORLD_Y_OFFSET   = 1.5   -- studs above head centre
local FULL_DISTANCE    = 23    -- studs: full text visible
local MUFFLED_DISTANCE = 33    -- studs: [Inaudible] shown

-- ══════════════════════════════════════════════════════════════════════════════
-- INPUT BAR
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
	s.Color           = Color3.fromRGB(35, 35, 35)
	s.Thickness       = 1.5
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
	s.Color           = Color3.fromRGB(35, 35, 35)
	s.Thickness       = 1
	s.Transparency    = 0.3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- ══════════════════════════════════════════════════════════════════════════════
-- BUBBLE SYSTEM
-- ══════════════════════════════════════════════════════════════════════════════

local bubbleGui = Instance.new("ScreenGui")
bubbleGui.Name           = "ChatBubbles"
bubbleGui.DisplayOrder   = 15
bubbleGui.ResetOnSpawn   = false
bubbleGui.IgnoreGuiInset = true
bubbleGui.Parent         = PlayerGui

-- activeSpeakers[charName] = { frame, head, character, bubbles={[label]=originalText} }
local activeSpeakers = {}
local bubbleCounts   = {}

-- Local player root cache
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

-- RenderStepped: reposition bubble containers + update text per distance tier
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end

	if not localRoot or not localRoot.Parent then
		refreshLocalRoot()
	end

	for charName, data in pairs(activeSpeakers) do
		local head = data.head
		if not head or not head.Parent then
			data.frame.Visible = false
			continue
		end

		local worldPos              = head.Position + Vector3.new(0, WORLD_Y_OFFSET, 0)
		local screenPos, onScreen   = cam:WorldToViewportPoint(worldPos)

		if not (onScreen and screenPos.Z > 0) then
			data.frame.Visible = false
			continue
		end

		data.frame.Visible  = true
		data.frame.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)

		-- Distance-based text tier
		local showFull = (charName == LocalPlayer.Name)
		if not showFull and localRoot then
			local senderRoot = data.character and data.character:FindFirstChild("HumanoidRootPart")
			if senderRoot and senderRoot.Parent then
				local dist = (localRoot.Position - senderRoot.Position).Magnitude
				if dist > MUFFLED_DISTANCE then
					data.frame.Visible = false
					continue
				end
				showFull = dist <= FULL_DISTANCE
			end
		end

		for label, originalText in pairs(data.bubbles) do
			if label.Parent then
				local want = showFull and originalText or "[ Inaudible ]"
				if label.Text ~= want then label.Text = want end
			end
		end
	end
end)

local function getOrCreateSpeaker(character)
	local head = character:FindFirstChild("Head")
	if not head then return nil end
	local charName = character.Name

	if activeSpeakers[charName] then
		activeSpeakers[charName].head      = head
		activeSpeakers[charName].character = character
		return activeSpeakers[charName].frame
	end

	local frame = Instance.new("Frame", bubbleGui)
	frame.AnchorPoint            = Vector2.new(0.5, 1)
	frame.Size                   = UDim2.fromOffset(BUBBLE_MAX_WIDTH + BUBBLE_PAD_H * 2 + 16, 400)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel        = 0
	frame.ClipsDescendants       = false
	frame.Active                 = false   -- never intercept mouse / touch

	local layout = Instance.new("UIListLayout", frame)
	layout.FillDirection       = Enum.FillDirection.Vertical
	layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder           = Enum.SortOrder.LayoutOrder
	layout.Padding             = UDim.new(0, 3)

	activeSpeakers[charName] = { frame = frame, head = head, character = character, bubbles = {} }
	return frame
end

local function createBubble(character, text)
	local stack = getOrCreateSpeaker(character)
	if not stack then return end
	local charName = character.Name

	bubbleCounts[charName] = (bubbleCounts[charName] or 0) + 1
	local myOrder = bubbleCounts[charName]

	local bubble = Instance.new("Frame", stack)
	bubble.LayoutOrder            = myOrder
	bubble.AutomaticSize          = Enum.AutomaticSize.XY
	bubble.Size                   = UDim2.new(0, 0, 0, 0)
	bubble.BackgroundColor3       = BUBBLE_BG_COLOR
	bubble.BackgroundTransparency = 1
	bubble.BorderSizePixel        = 0
	bubble.Active                 = false   -- never intercept mouse / touch

	Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, BUBBLE_CORNER)

	local pad = Instance.new("UIPadding", bubble)
	pad.PaddingLeft   = UDim.new(0, BUBBLE_PAD_H)
	pad.PaddingRight  = UDim.new(0, BUBBLE_PAD_H)
	pad.PaddingTop    = UDim.new(0, BUBBLE_PAD_V)
	pad.PaddingBottom = UDim.new(0, BUBBLE_PAD_V)

	local sizeConstraint = Instance.new("UISizeConstraint", bubble)
	sizeConstraint.MaxSize = Vector2.new(BUBBLE_MAX_WIDTH + BUBBLE_PAD_H * 2, math.huge)

	local label = Instance.new("TextLabel", bubble)
	label.BackgroundTransparency = 1
	label.AutomaticSize          = Enum.AutomaticSize.XY
	label.Size                   = UDim2.new(0, 0, 0, 0)
	label.MaxVisibleGraphemes    = -1
	label.Font                   = BUBBLE_FONT
	label.TextSize               = BUBBLE_TEXT_SIZE
	label.TextColor3             = BUBBLE_TEXT_COLOR
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.TextWrapped            = true
	label.RichText               = false
	label.TextTransparency       = 1
	label.Text                   = text

	local speakerData = activeSpeakers[charName]
	if speakerData then
		speakerData.bubbles[label] = text
	end

	task.spawn(function()
		local inInfo = TweenInfo.new(FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(bubble, inInfo, { BackgroundTransparency = BUBBLE_BG_TRANS }):Play()
		TweenService:Create(label,  inInfo, { TextTransparency = 0 }):Play()

		task.wait(HOLD_DURATION)

		local outInfo = TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(bubble, outInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label,  outInfo, { TextTransparency = 1 }):Play()
		task.wait(FADE_OUT)

		local data = activeSpeakers[charName]
		if data then data.bubbles[label] = nil end
		bubble:Destroy()

		bubbleCounts[charName] = math.max(0, (bubbleCounts[charName] or 1) - 1)
		if bubbleCounts[charName] == 0 then
			bubbleCounts[charName] = nil
			local d = activeSpeakers[charName]
			if d then
				d.frame:Destroy()
				activeSpeakers[charName] = nil
			end
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local data = activeSpeakers[player.Name]
	if data then
		pcall(function() data.frame:Destroy() end)
		activeSpeakers[player.Name] = nil
		bubbleCounts[player.Name]   = nil
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- CHAT LOG STORAGE
-- ══════════════════════════════════════════════════════════════════════════════

local MAX_LOG  = 500
local logEntries = {}  -- { teamName, teamColor, username, message }

-- ══════════════════════════════════════════════════════════════════════════════
-- CHAT LOGS WINDOW
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
	s.Color           = LC.BORDER
	s.Thickness       = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- Title bar
local TITLE_H  = 36
local SEARCH_H = 34

local titleBar = Instance.new("Frame", logsWindow)
titleBar.Size             = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundColor3 = LC.TITLE_BG
titleBar.BorderSizePixel  = 0
do
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)
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

-- Search bar
local searchFrame = Instance.new("Frame", logsWindow)
searchFrame.Size             = UDim2.new(1, -16, 0, SEARCH_H)
searchFrame.Position         = UDim2.new(0, 8, 0, TITLE_H + 6)
searchFrame.BackgroundColor3 = LC.SEARCH_BG
searchFrame.BorderSizePixel  = 0
do
	Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 6)
	local s = Instance.new("UIStroke", searchFrame)
	s.Color           = LC.BORDER
	s.Thickness       = 1
	s.Transparency    = 0.4
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
searchBox.PlaceholderText    = "Search chatlogs"
searchBox.PlaceholderColor3  = LC.DIM
searchBox.Text               = ""
searchBox.TextXAlignment     = Enum.TextXAlignment.Left
searchBox.TextYAlignment     = Enum.TextYAlignment.Center
searchBox.TextEditable       = false   -- only editable while window is open

-- Scroll frame
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
	l.SortOrder           = Enum.SortOrder.LayoutOrder
	l.FillDirection       = Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Left
	l.Padding             = UDim.new(0, 1)

	local p = Instance.new("UIPadding", scrollFrame)
	p.PaddingLeft  = UDim.new(0, 4)
	p.PaddingRight = UDim.new(0, 4)
	p.PaddingTop   = UDim.new(0, 3)
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
	pad.PaddingLeft   = UDim.new(0, 6)
	pad.PaddingRight  = UDim.new(0, 6)
	pad.PaddingTop    = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
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
	local filter = searchBox.Text:lower()
	if not entryMatchesFilter(entry, filter) then return end
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

-- Exposed for CommandBar via the shared table
shared.OpenChatLogsWindow = openChatLogs

closeBtn.MouseButton1Click:Connect(closeChatLogs)
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if logsWindow.Visible then rebuildLogDisplay() end
end)

-- Drag (title bar)
do
	local dragging  = false
	local dragStart = Vector3.new()
	local winStart  = UDim2.new()

	local dragBtn = Instance.new("TextButton", titleBar)
	dragBtn.Size               = UDim2.new(1, -44, 1, 0)
	dragBtn.BackgroundTransparency = 1
	dragBtn.Text               = ""
	dragBtn.ZIndex             = 5

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
				winStart.Y.Scale, winStart.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- RECEIVE CHAT MESSAGE
-- ══════════════════════════════════════════════════════════════════════════════

ChatRemotes.MessageReceived.OnClientEvent:Connect(function(payload)
	if not payload or not payload.senderName then return end

	local sender = Players:FindFirstChild(payload.senderName)
	if not sender then return end

	-- Store in log
	local entry = {
		teamName  = payload.teamName or "No Team",
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

	-- Create bubble
	local character = sender.Character
	if not character then
		task.spawn(function()
			local conn
			local done = false
			conn = sender.CharacterAdded:Connect(function(char)
				conn:Disconnect()
				done = true
				createBubble(char, payload.message)
			end)
			task.wait(3)
			if not done then pcall(function() conn:Disconnect() end) end
		end)
		return
	end
	createBubble(character, payload.message)
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- INPUT HANDLING
-- ══════════════════════════════════════════════════════════════════════════════

local MAX_CHARS = 200

-- One-tick lock prevents duplicate FireServer from FocusLost + Enter
-- firing in the same frame. Resets next frame via task.defer.
local submitting = false

local function submitMessage()
	if submitting then return end
	submitting = true
	task.defer(function() submitting = false end)

	local text = inputBox.Text:match("^%s*(.-)%s*$")
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

-- Click anywhere on the bar to focus
inputFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		inputBox:CaptureFocus()
	end
end)

-- Enter / FocusLost primary submit path
inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then submitMessage() end
end)

-- ── Keyboard shortcuts ─────────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gameProcessed)

	-- SLASH — open our chat bar.
	-- Checked before gameProcessed because TextChatService (even with no
	-- default channels) may still mark "/" as processed and focus an internal
	-- hidden TextBox.  We always redirect to our inputBox unless it is already
	-- the active TextBox (so the user can type "/" in a message they're composing).
	if input.KeyCode == Enum.KeyCode.Slash then
		local focused = UserInputService:GetFocusedTextBox()
		if focused ~= inputBox then
			task.defer(function()
				inputBox.Text = ""   -- clear any "/" that snuck in before focus
				inputBox:CaptureFocus()
			end)
		end
		-- If inputBox IS already focused, let "/" type normally.
		return
	end

	-- ENTER — fallback submit.
	-- TextChatService can intercept Enter and fire FocusLost(enterPressed=false).
	-- This explicit handler catches that edge-case; the submitting flag deduplicates.
	if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		if UserInputService:GetFocusedTextBox() == inputBox then
			submitMessage()
		end
		return
	end

	if gameProcessed then return end

	-- ESCAPE — dismiss without sending
	if input.KeyCode == Enum.KeyCode.Escape then
		inputBox.Text = ""
		inputBox:ReleaseFocus()
	end
end)

print("[ChatClient] Ready.")
