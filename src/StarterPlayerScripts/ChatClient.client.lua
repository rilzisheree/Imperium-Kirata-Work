local ContextActionService = game:GetService("ContextActionService")
local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local RunService           = game:GetService("RunService")
local StarterGui           = game:GetService("StarterGui")
local TextService          = game:GetService("TextService")
local TweenService         = game:GetService("TweenService")
local UserInputService     = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- kill default chat
local function killCoreChat()
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false) end)
end
killCoreChat()
task.delay(1, killCoreChat)

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

local ChatRemotes = require(ReplicatedStorage:WaitForChild("ChatRemotes"))

-- distance tiers
local FULL_DISTANCE    = 27   -- full message
local MUFFLED_DISTANCE = 33   -- [Inaudible]

local HOLD_DURATION = 7
local MAX_CHARS     = 200

-- bubble visuals
local MAX_BUBBLE_W = 360
local BILLBOARD_H  = 500
local STUD_ABOVE   = 1.4
local PAD_H        = 14
local PAD_V        = 9
local CORNER       = 12
local FONT         = Enum.Font.GothamSemibold
local TEXT_SIZE    = 18
local BG_COLOR     = Color3.fromRGB(240, 240, 240)
local BG_TRANS     = 0.06
local TEXT_COLOR   = Color3.fromRGB(25, 25, 25)

local INAUDIBLE_TEXT = "[ Inaudible ]"
-- pre-measure so we're not calling GetTextSize every frame
local INAUDIBLE_PILL_W = math.min(
	math.ceil(TextService:GetTextSize(INAUDIBLE_TEXT, TEXT_SIZE, FONT,
		Vector2.new(math.huge, math.huge)).X) + PAD_H * 2 + 6,
	MAX_BUBBLE_W
)

-- input bar
local BAR_H_MIN = 36    -- single-line height
local BAR_H_MAX = 110   -- cap at ~5 lines (TextBox scrolls natively beyond this)
local LINE_H    = 18    -- approximate rendered height of one line at TextSize 14 GothamSemibold
local BTN_W     = 34

local inputGui = Instance.new("ScreenGui")
inputGui.Name           = "ChatInput"
inputGui.DisplayOrder   = 20
inputGui.ResetOnSpawn   = false
inputGui.IgnoreGuiInset = true
inputGui.Parent         = PlayerGui

local inputFrame = Instance.new("Frame", inputGui)
inputFrame.AnchorPoint            = Vector2.new(0, 0)
inputFrame.Size                   = UDim2.new(0.20, 0, 0, BAR_H_MIN)
inputFrame.Position               = UDim2.new(0, 8, 0, 62)
inputFrame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
inputFrame.BackgroundTransparency = 0.25
inputFrame.BorderSizePixel        = 0
do
	Instance.new("UICorner", inputFrame).CornerRadius = UDim.new(0, 7)
	local s = Instance.new("UIStroke", inputFrame)
	s.Color = Color3.fromRGB(35, 35, 35); s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local inputBox = Instance.new("TextBox", inputFrame)
inputBox.Size                   = UDim2.new(1, -(BTN_W + 18), 0, LINE_H)
inputBox.Position               = UDim2.new(0, 14, 0, math.floor((BAR_H_MIN - LINE_H) / 2))
inputBox.BackgroundTransparency = 1
inputBox.BorderSizePixel        = 0
inputBox.ClearTextOnFocus       = false
inputBox.MultiLine              = true
inputBox.TextWrapped            = true
inputBox.Font                   = Enum.Font.GothamSemibold
inputBox.TextSize               = 14
inputBox.TextColor3             = Color3.fromRGB(225, 225, 240)
inputBox.PlaceholderText        = "Press / to chat"
inputBox.PlaceholderColor3      = Color3.fromRGB(120, 128, 160)
inputBox.Text                   = ""
inputBox.TextXAlignment         = Enum.TextXAlignment.Left
inputBox.TextYAlignment         = Enum.TextYAlignment.Top

local sendBtn = Instance.new("TextButton", inputFrame)
sendBtn.AnchorPoint            = Vector2.new(1, 0)
sendBtn.Size                   = UDim2.new(0, BTN_W, 0, BAR_H_MIN - 10)
sendBtn.Position               = UDim2.new(1, -5, 0, 5)
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
	s.Color = Color3.fromRGB(35, 35, 35); s.Thickness = 1
	s.Transparency = 0.3; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- ── Measurement proxy ─────────────────────────────────────────────────────────
-- Off-screen TextLabel that mirrors inputBox content.  TextLabel.TextBounds
-- correctly reports wrapped height; TextBox.TextBounds does not.
-- Must NOT be Visible=false: Roblox skips layout (including TextBounds) for
-- invisible elements, so the signal never fires and the bar never grows.
-- Instead we keep it rendered but fully transparent and positioned off-screen,
-- matching the same pattern used by CommandBar.client.lua.
-- inputBox width = parent width - (BTN_W + 18); no extra subtraction for
-- position because position does not reduce the rendered width.
local function measureWidth()
	return math.max(1, inputFrame.AbsoluteSize.X - (BTN_W + 18))
end

local measureLabel = Instance.new("TextLabel", inputGui)
measureLabel.Size                   = UDim2.fromOffset(measureWidth(), 0)
measureLabel.AutomaticSize          = Enum.AutomaticSize.Y
measureLabel.Position               = UDim2.fromOffset(-9999, -9999)
measureLabel.BackgroundTransparency = 1
measureLabel.TextTransparency       = 1
measureLabel.Font                   = Enum.Font.GothamSemibold
measureLabel.TextSize               = 14
measureLabel.TextWrapped            = true
measureLabel.TextXAlignment         = Enum.TextXAlignment.Left
measureLabel.TextYAlignment         = Enum.TextYAlignment.Top
measureLabel.Text                   = ""
measureLabel.ZIndex                 = 1

-- Keep the measurement label's width in sync with the input box's actual width.
inputFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	measureLabel.Size = UDim2.fromOffset(measureWidth(), 0)
end)

-- ── Auto-height logic ─────────────────────────────────────────────────────────
local function updateBarHeight()
	local textH = math.max(measureLabel.TextBounds.Y, LINE_H)
	local newH  = math.clamp(textH + 12, BAR_H_MIN, BAR_H_MAX)

	inputFrame.Size = UDim2.new(0.20, 0, 0, newH)

	-- Vertically center on a single line; top-align when text spans multiple.
	local innerH  = newH - 12
	local yOffset = math.max(0, math.floor((innerH - textH) / 2))
	inputBox.Position = UDim2.new(0, 14, 0, 6 + yOffset)
	inputBox.Size     = UDim2.new(1, -(BTN_W + 18), 0, innerH - yOffset)
end

measureLabel:GetPropertyChangedSignal("TextBounds"):Connect(updateBarHeight)

-- bubble system
local speakers = {}

local function getOrMakeSpeaker(character)
	local head = character:FindFirstChild("Head")
	if not head then return nil end
	local pname = character.Name

	local existing = speakers[pname]
	if existing and existing.gui and existing.gui.Parent == head then
		return existing
	end
	if existing then pcall(function() existing.gui:Destroy() end) end

	local gui = Instance.new("BillboardGui")
	gui.Name                  = "ChatBubbles"
	gui.Size                  = UDim2.fromOffset(MAX_BUBBLE_W, BILLBOARD_H)
	gui.StudsOffsetWorldSpace = Vector3.new(0, STUD_ABOVE, 0)
	gui.AlwaysOnTop           = false
	gui.LightInfluence        = 0
	gui.ClipsDescendants      = false
	gui.Enabled               = true
	gui.Parent                = head

	local container = Instance.new("Frame", gui)
	container.AnchorPoint            = Vector2.new(0.5, 1)
	container.Size                   = UDim2.fromOffset(MAX_BUBBLE_W, BILLBOARD_H / 2)
	container.Position               = UDim2.fromOffset(MAX_BUBBLE_W / 2, BILLBOARD_H / 2)
	container.BackgroundTransparency = 1
	container.BorderSizePixel        = 0
	container.Active                 = false

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

-- real-time distance check: show/hide bubbles and swap to [Inaudible] when out of full range
RunService.Heartbeat:Connect(function()
	local localChar = LocalPlayer.Character
	local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

	for pname, data in pairs(speakers) do
		local gui = data.gui
		if not gui or not gui.Parent then
			speakers[pname] = nil
			continue
		end

		local head    = gui.Parent
		local isLocal = (pname == LocalPlayer.Name)
		local showFull = isLocal

		if not isLocal then
			if not localRoot then
				gui.Enabled = false
				continue
			end
			local char = head and head.Parent
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root.Parent then
				local dist = (localRoot.Position - root.Position).Magnitude
				gui.Enabled = dist <= MUFFLED_DISTANCE
				showFull    = dist <= FULL_DISTANCE
			else
				gui.Enabled = false
				continue
			end
		end

		for _, b in ipairs(data.bubbles) do
			if b.label and b.label.Parent then
				-- once locked inaudible it stays that way, moving closer won't reveal the text
				if not showFull and not b.lockedInaudible then
					b.lockedInaudible = true
					b.bubble.Size = UDim2.fromOffset(INAUDIBLE_PILL_W, 0)
				end
				local want = b.lockedInaudible and INAUDIBLE_TEXT or b.originalText
				if b.label.Text ~= want then b.label.Text = want end
			end
		end
	end
end)

local function createBubble(character, text)
	local data = getOrMakeSpeaker(character)
	if not data then return end

	data.count += 1

	-- lock inaudible state at creation time so latecomers always see [Inaudible]
	local lockedInaudible = false
	if character.Name ~= LocalPlayer.Name then
		local localRoot  = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		local senderRoot = character:FindFirstChild("HumanoidRootPart")
		if localRoot and senderRoot then
			lockedInaudible = (localRoot.Position - senderRoot.Position).Magnitude > FULL_DISTANCE
		end
	end
	local displayText = lockedInaudible and INAUDIBLE_TEXT or text

	local INF2  = Vector2.new(math.huge, math.huge)
	local pillW = math.min(math.ceil(TextService:GetTextSize(displayText, TEXT_SIZE, FONT, INF2).X) + PAD_H * 2 + 6, MAX_BUBBLE_W)

	local bubble = Instance.new("Frame", data.container)
	bubble.LayoutOrder            = data.count
	bubble.AutomaticSize          = Enum.AutomaticSize.Y
	bubble.Size                   = UDim2.fromOffset(pillW, 0)
	bubble.BackgroundColor3       = BG_COLOR
	bubble.BackgroundTransparency = 1
	bubble.BorderSizePixel        = 0
	bubble.Active                 = false
	Instance.new("UICorner", bubble).CornerRadius = UDim.new(0, CORNER)

	local pad = Instance.new("UIPadding", bubble)
	pad.PaddingLeft   = UDim.new(0, PAD_H)
	pad.PaddingRight  = UDim.new(0, PAD_H)
	pad.PaddingTop    = UDim.new(0, PAD_V)
	pad.PaddingBottom = UDim.new(0, PAD_V)

	local label = Instance.new("TextLabel", bubble)
	label.BackgroundTransparency = 1
	label.AutomaticSize          = Enum.AutomaticSize.Y
	label.Size                   = UDim2.new(1, 0, 0, 0)
	label.Font                   = FONT
	label.TextSize               = TEXT_SIZE
	label.TextColor3             = TEXT_COLOR
	label.TextXAlignment         = Enum.TextXAlignment.Center
	label.TextWrapped            = true
	label.RichText               = false
	label.TextTransparency       = 1
	label.TextStrokeTransparency = 1
	label.Text                   = displayText

	local fadeIn = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bubble, fadeIn, { BackgroundTransparency = BG_TRANS }):Play()
	TweenService:Create(label,  fadeIn, { TextTransparency = 0 }):Play()

	local entry = { label = label, bubble = bubble, originalText = text, lockedInaudible = lockedInaudible }
	table.insert(data.bubbles, entry)

	task.delay(HOLD_DURATION, function()
		if bubble.Parent then
			local fadeOut = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local t1 = TweenService:Create(bubble, fadeOut, { BackgroundTransparency = 1 })
			local t2 = TweenService:Create(label,  fadeOut, { TextTransparency = 1 })
			t1:Play(); t2:Play()
			pcall(function() t1.Completed:Wait() end)
		end

		local idx = table.find(data.bubbles, entry)
		if idx then table.remove(data.bubbles, idx) end
		pcall(function() bubble:Destroy() end)
		if #data.bubbles == 0 and speakers[character.Name] == data then
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

-- receive messages from server
ChatRemotes.MessageReceived.OnClientEvent:Connect(function(payload)
	if not payload or not payload.senderName then return end
	local sender = Players:FindFirstChild(payload.senderName)
	if not sender then return end

	local character = sender.Character
	if character then
		createBubble(character, payload.message)
	else
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

-- input handling
local submitting = false

local function submitMessage()
	if submitting then return end
	submitting = true
	task.defer(function() submitting = false end)

	local text = inputBox.Text:match("^%s*(.-)%s*$") or ""
	if text ~= "" then
		ChatRemotes.MessageSent:FireServer(text)
	end
	inputBox.Text     = ""
	measureLabel.Text = ""
	inputBox:ReleaseFocus()
	-- Reset bar to single-line height.
	inputFrame.Size   = UDim2.new(0.20, 0, 0, BAR_H_MIN)
	inputBox.Position = UDim2.new(0, 14, 0, math.floor((BAR_H_MIN - LINE_H) / 2))
	inputBox.Size     = UDim2.new(1, -(BTN_W + 18), 0, LINE_H)
end

inputBox:GetPropertyChangedSignal("Text"):Connect(function()
	-- Strip control characters (newlines inserted by MultiLine on Enter).
	local dirty = inputBox.Text:find("[\n\r]")
	if dirty then
		local c = inputBox.Text:gsub("[\n\r]", "")
		inputBox.Text = c
		inputBox.CursorPosition = #c + 1
		return
	end
	-- Enforce character limit.
	if #inputBox.Text > MAX_CHARS then
		inputBox.Text = inputBox.Text:sub(1, MAX_CHARS)
		return
	end
	-- Mirror into measurement label so TextBounds reflects wrapped height.
	measureLabel.Text = inputBox.Text ~= "" and inputBox.Text or " "
end)

sendBtn.MouseButton1Click:Connect(submitMessage)

inputFrame.InputBegan:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		inputBox:CaptureFocus()
	end
end)

inputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then submitMessage() end
end)

-- slash opens the chat bar (CAS so it beats TextChatService bindings)
ContextActionService:BindAction(
	"ChatOpenSlash",
	function(_, state, _)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if UserInputService:GetFocusedTextBox() == inputBox then
			return Enum.ContextActionResult.Pass
		end
		task.defer(function()
			inputBox.Text = ""
			inputBox:CaptureFocus()
		end)
		return Enum.ContextActionResult.Sink
	end,
	false,
	Enum.KeyCode.Slash
)

-- enter fallback (TextChatService can swallow it and send FocusLost with enterPressed=false)
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
