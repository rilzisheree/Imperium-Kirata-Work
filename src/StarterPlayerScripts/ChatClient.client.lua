--[[
	ChatClient.client.lua
	LocalScript — StarterPlayerScripts

	Proximity chat:
	  • Press /  to open the input bar (ContextActionService intercepts before TextChatService)
	  • Press Enter or click → to send
	  • Press Escape to dismiss without sending
	  • Bubbles pinned above heads via WorldToViewportPoint — correct at every zoom level
	  • Distance tiers per frame: full (≤23 studs) / [Inaudible] (≤33) / hidden
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
local MAX_CHARS        = 200

local BUBBLE_W      = 240   -- max bubble pixel width
local BUBBLE_MAX_H  = 400   -- pixel height of the bubble stack area
local HEAD_TOP      = 0.65  -- world studs from Head centre to top of head
local BUBBLE_ABOVE  = 50    -- extra pixels above head top (increase to move text higher)
local PAD_H         = 12
local PAD_V         = 7
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
-- 5. BUBBLE SYSTEM  (ScreenGui + WorldToViewportPoint — zoom-proof positioning)
--
--  Each speaker gets a Frame inside one shared ScreenGui.
--  AnchorPoint (0.5, 1) means Position controls the BOTTOM-CENTRE of the stack.
--  Every Heartbeat we project the head-top world point to viewport pixels and
--  set Position directly — no stud math, no drift at any zoom level.
-- ══════════════════════════════════════════════════════════════════════════════

local bubbleGui = Instance.new("ScreenGui")
bubbleGui.Name           = "ChatBubbles"
bubbleGui.DisplayOrder   = 15
bubbleGui.ResetOnSpawn   = false
bubbleGui.IgnoreGuiInset = true   -- coordinates = raw viewport pixels
bubbleGui.Parent         = PlayerGui

local speakers = {}

local function getOrMakeSpeaker(character)
	local head = character:FindFirstChild("Head")
	if not head then return nil end
	local pname = character.Name

	local existing = speakers[pname]
	if existing and existing.frame and existing.frame.Parent == bubbleGui then
		-- still valid — just update head reference in case of respawn
		existing.head = head
		return existing
	end
	if existing then pcall(function() existing.frame:Destroy() end) end

	-- Bottom-centre-anchored frame: its Position is the anchor of the bottom edge.
	local frame = Instance.new("Frame", bubbleGui)
	frame.Name                   = "Bubbles_" .. pname
	frame.AnchorPoint            = Vector2.new(0.5, 1)
	frame.Size                   = UDim2.fromOffset(BUBBLE_W, BUBBLE_MAX_H)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel        = 0
	frame.ClipsDescendants       = false
	frame.Visible                = false   -- hidden until first Heartbeat positions it

	local layout = Instance.new("UIListLayout", frame)
	layout.FillDirection       = Enum.FillDirection.Vertical
	layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder           = Enum.SortOrder.LayoutOrder
	layout.Padding             = UDim.new(0, 3)

	local data = { frame = frame, head = head, count = 0, bubbles = {} }
	speakers[pname] = data
	return data
end

-- Bind AFTER the camera module updates the camera each frame so positions
-- are never one frame behind when the player zooms or pans.
RunService:BindToRenderStep(
	"ChatBubbleUpdate",
	Enum.RenderPriority.Camera.Value + 1,
	function()
	local camera = workspace.CurrentCamera
	if not camera then return end

	local localChar = LocalPlayer.Character
	local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

	for pname, data in pairs(speakers) do
		local frame = data.frame
		if not frame or not frame.Parent then
			speakers[pname] = nil
			continue
		end

		local head     = data.head
		local isLocal  = (pname == LocalPlayer.Name)
		local showFull = isLocal
		local visible  = false

		if isLocal then
			visible  = true
			showFull = true
		else
			if localRoot and head and head.Parent then
				local char = head.Parent
				local root = char:FindFirstChild("HumanoidRootPart")
				if root and root.Parent then
					local dist = (localRoot.Position - root.Position).Magnitude
					visible  = dist <= MUFFLED_DISTANCE
					showFull = dist <= FULL_DISTANCE
				end
			end
		end

		-- Project the top of the head to viewport pixels.
		-- BUBBLE_ABOVE extra pixels of gap push the stack further above the head.
		if visible and head and head.Parent then
			local topWorld = head.Position + Vector3.new(0, HEAD_TOP, 0)
			local vp, onScreen = camera:WorldToViewportPoint(topWorld)
			if onScreen and vp.Z > 0 then
				-- vp.X / vp.Y are already in raw viewport pixels (IgnoreGuiInset = true)
				frame.Position = UDim2.fromOffset(vp.X, vp.Y - BUBBLE_ABOVE)
				frame.Visible  = true
			else
				frame.Visible = false
			end
		else
			frame.Visible = false
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

	local bubble = Instance.new("Frame", data.frame)
	bubble.LayoutOrder            = data.count
	bubble.AutomaticSize          = Enum.AutomaticSize.XY
	bubble.Size                   = UDim2.new(0, 0, 0, 0)
	bubble.BackgroundColor3       = BG_COLOR
	bubble.BackgroundTransparency = 1      -- starts transparent; tweened in
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

	-- UIScale drives the pop: starts small, springs to full size
	local uiScale = Instance.new("UIScale", bubble)
	uiScale.Scale = 0.5

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
	label.TextTransparency       = 1      -- starts invisible; tweened in
	label.Text                   = text

	-- Pop-in: scale springs from 0.5 → 1 with a slight overshoot (Back easing),
	-- background and text fade in simultaneously.
	local popInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(uiScale, popInfo, { Scale = 1 }):Play()
	TweenService:Create(bubble, popInfo, { BackgroundTransparency = BG_TRANS }):Play()
	TweenService:Create(label,  popInfo, { TextTransparency = 0 }):Play()

	local entry = { label = label, originalText = text }
	table.insert(data.bubbles, entry)

	task.delay(HOLD_DURATION, function()
		local idx = table.find(data.bubbles, entry)
		if idx then table.remove(data.bubbles, idx) end
		bubble:Destroy()
		if #data.bubbles == 0 and speakers[character.Name] == data then
			pcall(function() data.frame:Destroy() end)
			speakers[character.Name] = nil
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local data = speakers[player.Name]
	if data then
		pcall(function() data.frame:Destroy() end)
		speakers[player.Name] = nil
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- 6. RECEIVE MESSAGES
-- ══════════════════════════════════════════════════════════════════════════════

ChatRemotes.MessageReceived.OnClientEvent:Connect(function(payload)
	if not payload or not payload.senderName then return end

	local sender = Players:FindFirstChild(payload.senderName)
	if not sender then return end

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
