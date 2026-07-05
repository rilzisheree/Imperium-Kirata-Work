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

local BUBBLE_W    = 240           -- max bubble pixel width
local BUBBLE_H    = 400           -- billboard height in pixels (room for stacked bubbles)
local HEAD_TOP    = 0.65          -- studs from Head centre to top of head
local HEAD_GAP    = 0.10          -- extra gap above head top (studs)
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
	gui.Name             = "ChatBubbles"
	gui.Size             = UDim2.fromOffset(BUBBLE_W, BUBBLE_H)
	gui.StudsOffset      = Vector3.new(0, 5, 0)  -- sane default; corrected each frame
	gui.AlwaysOnTop      = false
	gui.LightInfluence   = 0
	gui.ClipsDescendants = false
	gui.Enabled          = true
	gui.Parent           = head

	local container = Instance.new("Frame", gui)
	container.Size                   = UDim2.new(1, 0, 1, 0)
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

RunService.Heartbeat:Connect(function()
	local camera    = workspace.CurrentCamera
	if not camera then return end   -- can be nil during camera transitions / respawn

	local localChar = LocalPlayer.Character
	local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

	for pname, data in pairs(speakers) do
		local gui = data.gui
		if not gui or not gui.Parent then
			speakers[pname] = nil
			continue
		end

		local head     = gui.Parent
		local isLocal  = (pname == LocalPlayer.Name)
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

		-- Pin the bubble bottom to just above the head at any zoom level.
		-- Project two world points to measure pixels-per-stud, then solve:
		--   StudsOffset = (BUBBLE_H / 2) / pps + HEAD_TOP + HEAD_GAP
		-- so that the billboard bottom sits exactly at head-top + GAP.
		-- Guards: skip if camera missing, head off-screen, or behind camera.
		if head and head.Parent then
			local vp0, onScreen0 = camera:WorldToViewportPoint(head.Position)
			local vp1, _         = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1, 0))
			-- vp0.Z > 0 means in front of camera; screen Y decreases as world Y rises
			local pps = vp0.Y - vp1.Y   -- pixels per stud (positive when valid)
			if onScreen0 and vp0.Z > 0 and pps > 1 then
				local studOffset = (BUBBLE_H * 0.5) / pps + HEAD_TOP + HEAD_GAP
				gui.StudsOffset  = Vector3.new(0, studOffset, 0)
				-- (if off-screen or behind camera, keep the last good offset)
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

	local bubble = Instance.new("Frame", data.container)
	bubble.LayoutOrder            = data.count
	bubble.AutomaticSize          = Enum.AutomaticSize.XY
	bubble.Size                   = UDim2.new(0, 0, 0, 0)
	bubble.BackgroundColor3       = BG_COLOR
	bubble.BackgroundTransparency = BG_TRANS
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
	label.TextTransparency       = 0
	label.Text                   = text

	local entry = { label = label, originalText = text }
	table.insert(data.bubbles, entry)

	task.delay(HOLD_DURATION, function()
		local idx = table.find(data.bubbles, entry)
		if idx then table.remove(data.bubbles, idx) end
		bubble:Destroy()
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
