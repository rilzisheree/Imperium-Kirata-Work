--[[
	ChatClient.client.lua
	LocalScript — StarterPlayerScripts

	Proximity chat:
	  • Press /  to open the input bar (ContextActionService intercepts before TextChatService)
	  • Press Enter or click → to send
	  • Press Escape to dismiss without sending
	  • Bubbles pinned above heads via BillboardGui (StudsOffset=0) — zoom-proof at any distance
	  • Distance tiers per frame: full (≤23 studs) / [Inaudible] (≤33) / hidden
--]]

-- ── Services ────────────────────────────────────────────────────────────────
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
local FULL_DISTANCE    = 27     -- studs: full text
local MUFFLED_DISTANCE = 33     -- studs: [Inaudible]
local HOLD_DURATION    = 7      -- seconds bubble stays on screen
local MAX_CHARS        = 200

local MAX_BUBBLE_W = 360   -- max bubble pill width before text wraps
local BILLBOARD_H  = 500   -- BillboardGui pixel height for the bubble stack area
local STUD_ABOVE   = 0.5   -- world-space studs above Head centre; scales with zoom → always glued
local PAD_H        = 14
local PAD_V        = 9
local CORNER       = 12
local FONT         = Enum.Font.GothamSemibold
local TEXT_SIZE    = 18
local BG_COLOR    = Color3.fromRGB(240, 240, 240)
local BG_TRANS    = 0.06
local TEXT_COLOR  = Color3.fromRGB(25, 25, 25)

local INAUDIBLE_TEXT  = "[ Inaudible ]"
-- Pre-measured once so the Heartbeat can resize pills without re-calling GetTextSize every frame.
local INAUDIBLE_PILL_W = math.min(
	math.ceil(TextService:GetTextSize(INAUDIBLE_TEXT, TEXT_SIZE, FONT,
		Vector2.new(math.huge, math.huge)).X) + PAD_H * 2 + 6,
	MAX_BUBBLE_W
)

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
-- 5. BUBBLE SYSTEM  (BillboardGui, StudsOffset = 0 — truly zoom-proof)
--
--  Why this works:
--    Roblox's renderer natively pins a BillboardGui's centre to its adornee's
--    screen position.  With StudsOffset=(0,0,0) the centre is EXACTLY the Head's
--    centre on screen — guaranteed, no frame-by-frame math.
--
--    We then place the content container INSIDE the billboard at a fixed pixel
--    offset above the centre.  That offset is in billboard-local pixels, so it
--    never changes with zoom.  The bubble stack bottom is always HEAD_GAP_PX
--    pixels above the head centre, regardless of camera distance.
--
--  Layout (all values derived from constants above):
--    Y=0              ─── billboard top   (BILLBOARD_H/2 px above head centre)
--    Y=halfH-HEAD_GAP ─── container bottom (HEAD_GAP_PX px above head centre) ✓
--    Y=halfH          ─── head centre     (StudsOffset 0 → BillboardGui centre)
--    Y=BILLBOARD_H    ─── billboard bottom
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
	gui.Name                   = "ChatBubbles"
	gui.Size                   = UDim2.fromOffset(MAX_BUBBLE_W, BILLBOARD_H)
	-- StudsOffsetWorldSpace lifts the billboard centre STUD_ABOVE studs above the
	-- Head in world space.  Because it is a world-space stud value it shrinks and
	-- grows proportionally with zoom — the bubble stays exactly glued to the head.
	gui.StudsOffsetWorldSpace  = Vector3.new(0, STUD_ABOVE, 0)
	gui.AlwaysOnTop            = false
	gui.LightInfluence         = 1
	gui.ClipsDescendants       = false
	gui.Enabled                = true
	gui.Parent                 = head

	-- The billboard centre is already STUD_ABOVE studs above the head, so we place
	-- the container bottom at the billboard centre and let it grow upward.
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

RunService.Heartbeat:Connect(function()
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

		for _, b in ipairs(data.bubbles) do
			if b.label and b.label.Parent then
				-- Once a bubble becomes inaudible for any reason, lock it permanently.
				-- Moving closer afterwards never reveals the original text.
				if not showFull and not b.lockedInaudible then
					b.lockedInaudible = true
					-- Resize the pill to fit "[ Inaudible ]" — it may have been created
					-- narrow for a short message and would otherwise wrap the text.
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

	-- Lock the "inaudible" state at the moment the bubble is created.
	-- If the sender was already out of full-hearing range when the message arrived,
	-- the bubble stays as [Inaudible] for its whole lifetime — moving closer later
	-- will not reveal the original text.
	local lockedInaudible = false
	if character.Name ~= LocalPlayer.Name then
		local localRoot  = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		local senderRoot = character:FindFirstChild("HumanoidRootPart")
		if localRoot and senderRoot then
			lockedInaudible = (localRoot.Position - senderRoot.Position).Magnitude > FULL_DISTANCE
		end
	end
	local displayText = lockedInaudible and "[ Inaudible ]" or text

	-- Size the pill to fit only the text that will actually be shown.
	-- (Previously we forced every pill to be at least as wide as "[ Inaudible ]",
	-- which made single-word bubbles far too wide.)
	local INF2  = Vector2.new(math.huge, math.huge)
	-- Add a small render buffer (6px) so sub-pixel differences never cause a spurious wrap.
	local pillW = math.min(math.ceil(TextService:GetTextSize(displayText, TEXT_SIZE, FONT, INF2).X) + PAD_H * 2 + 6, MAX_BUBBLE_W)

	local bubble = Instance.new("Frame", data.container)
	bubble.LayoutOrder            = data.count
	bubble.AutomaticSize          = Enum.AutomaticSize.Y   -- height grows with wrapped text
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
	label.AutomaticSize          = Enum.AutomaticSize.Y   -- height wraps with text
	label.Size                   = UDim2.new(1, 0, 0, 0)  -- fills pill width minus padding
	label.Font                   = FONT
	label.TextSize               = TEXT_SIZE
	label.TextColor3             = TEXT_COLOR
	label.TextXAlignment         = Enum.TextXAlignment.Center
	label.TextWrapped            = true                    -- always wrap; pill width is pre-measured
	label.RichText               = false
	label.TextTransparency       = 1
	label.TextStrokeTransparency = 1                       -- disable the default glow/outline
	label.Text                   = displayText

	-- Fade in: plain opacity tween, same feel as Roblox's default bubble chat.
	local fadeIn = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bubble, fadeIn, { BackgroundTransparency = BG_TRANS }):Play()
	TweenService:Create(label,  fadeIn, { TextTransparency = 0 }):Play()

	local entry = { label = label, bubble = bubble, originalText = text, lockedInaudible = lockedInaudible }
	table.insert(data.bubbles, entry)

	task.delay(HOLD_DURATION, function()
		-- Fade out before removing.  Guard against the bubble already being
		-- destroyed externally (PlayerRemoving, respawn, etc.).
		if bubble.Parent then
			local fadeOut = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local t1 = TweenService:Create(bubble, fadeOut, { BackgroundTransparency = 1 })
			local t2 = TweenService:Create(label,  fadeOut, { TextTransparency = 1 })
			t1:Play()
			t2:Play()
			-- Wait for the fade to finish; pcall so any mid-destroy signal
			-- doesn't abort the cleanup block below.
			pcall(function() t1.Completed:Wait() end)
		end

		-- Always clean up the entry regardless of what happened above.
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
