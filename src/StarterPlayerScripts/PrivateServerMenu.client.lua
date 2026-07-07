--[[
	PrivateServerMenu.client.lua
	Opened by the "privateserver" admin command (via PrivateServerOpen remote).

	Two-column layout:
	  Left  — "Current Server"  (all players not in the send queue)
	  Right — "Send Queue"      (players selected to be sent to the reserved server)

	Players can be moved between columns with the → / ← button on each card,
	or by clicking and dragging a card from one column into the other.

	Footer buttons:
	  Create Server   — fires PrivateServerReserve → server reserves a slot
	  Send Selected   — fires PrivateServerSend with queued userId list
	  Cancel Server   — fires PrivateServerCancel, clears state, closes menu
	  Close           — local-only dismiss
--]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes") :: ModuleScript)

-- ── Palette ────────────────────────────────────────────────────────────────────
local C_BG   = Color3.fromRGB( 12,  12,  18)
local C_BOR  = Color3.fromRGB( 90,  90, 120)
local C_TXT  = Color3.fromRGB(235, 235, 252)
local C_DIM  = Color3.fromRGB( 80,  80, 100)
local C_ACC  = Color3.fromRGB(160, 160, 210)
local C_HEAD = Color3.fromRGB( 16,  16,  26)
local C_FOOT = Color3.fromRGB( 14,  14,  22)
local C_BTN  = Color3.fromRGB( 22,  22,  34)
local C_SEC  = Color3.fromRGB( 20,  20,  32)
local C_OK   = Color3.fromRGB(130, 200, 130)
local C_WARN = Color3.fromRGB(200, 150,  60)
local C_ERR  = Color3.fromRGB(215,  75,  75)
local C_DRAG = Color3.fromRGB(100, 140, 255)

-- ── Layout constants ───────────────────────────────────────────────────────────
local MENU_W      = 480
local HEADER_H    = 44
local STATUS_H    = 30
local COL_LABEL_H = 24
local CONTENT_H   = 272          -- total height of the two-column area
local FOOTER_H    = 52
local DIV         = 1
-- Total: 44+1+30+1+24+248+1+52 = 401  → cleaner than 409
local MENU_H      = HEADER_H + DIV + STATUS_H + DIV + COL_LABEL_H
                  + (CONTENT_H - COL_LABEL_H) + DIV + FOOTER_H

local COL_W    = MENU_W / 2     -- 240
local CARD_H   = 38
local CARD_GAP = 4

-- ── Runtime state ──────────────────────────────────────────────────────────────
local queuedIds    : { [number]: boolean } = {}  -- [userId] = true
local serverStatus : string                = "none"
-- "none" | "reserving" | "active" | "failed" | "cancelled"
local serverCode   : string?               = nil  -- access code returned by ReserveServer

local dragState: {
	userId  : number,
	ghost   : Frame,
	hbConn  : RBXScriptConnection,
	fromQueue: boolean,
}? = nil

-- ── ScreenGui ──────────────────────────────────────────────────────────────────
local sg = Instance.new("ScreenGui")
sg.Name           = "PrivateServerGui"
sg.DisplayOrder   = 106
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.Enabled        = false
sg.Parent         = PGui

-- ── Main frame ─────────────────────────────────────────────────────────────────
local frame = Instance.new("Frame")
frame.Name             = "PSMenu"
frame.AnchorPoint      = Vector2.new(0.5, 0.5)
frame.Position         = UDim2.new(0.5, 0, 0.5, 0)
frame.Size             = UDim2.new(0, MENU_W, 0, MENU_H)
frame.BackgroundColor3 = C_BG
frame.BorderSizePixel  = 0
frame.ClipsDescendants = true
frame.ZIndex           = 10
frame.Parent           = sg

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
local fStroke = Instance.new("UIStroke", frame)
fStroke.Color           = C_BOR
fStroke.Thickness       = 1.5
fStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- ── Helpers ────────────────────────────────────────────────────────────────────
local function makeDivider(yOff: number)
	local d = Instance.new("Frame", frame)
	d.Size             = UDim2.new(1, 0, 0, 1)
	d.Position         = UDim2.new(0, 0, 0, yOff)
	d.BackgroundColor3 = C_BOR
	d.BackgroundTransparency = 0.5
	d.BorderSizePixel  = 0
	d.ZIndex           = 11
end

local function makeStroke(parent: Instance, colour: Color3?, thick: number?, alpha: number?)
	local s = Instance.new("UIStroke", parent)
	s.Color           = colour or C_BOR
	s.Thickness       = thick  or 1
	s.Transparency    = alpha  or 0.4
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return s
end

-- ── Header ─────────────────────────────────────────────────────────────────────
local header = Instance.new("Frame", frame)
header.Name             = "Header"
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_HEAD
header.BorderSizePixel  = 0
header.ZIndex           = 11

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size               = UDim2.new(1, -50, 1, 0)
titleLbl.Position           = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 14
titleLbl.TextColor3         = C_TXT
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.Text               = "Private Server"
titleLbl.ZIndex             = 12

local headerCloseBtn = Instance.new("TextButton", header)
headerCloseBtn.Size             = UDim2.new(0, 28, 0, 28)
headerCloseBtn.Position         = UDim2.new(1, -38, 0.5, -14)
headerCloseBtn.BackgroundColor3 = Color3.fromRGB(44, 22, 22)
headerCloseBtn.BorderSizePixel  = 0
headerCloseBtn.Font             = Enum.Font.GothamBold
headerCloseBtn.TextSize         = 13
headerCloseBtn.TextColor3       = C_ERR
headerCloseBtn.Text             = "✕"
headerCloseBtn.AutoButtonColor  = false
headerCloseBtn.ZIndex           = 13
Instance.new("UICorner", headerCloseBtn).CornerRadius = UDim.new(0, 6)

-- ── Header drag ─────────────────────────────────────────────────────────────────
local menuDragging = false
local menuDragStart: Vector3
local menuStartPos: UDim2

header.InputBegan:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		menuDragging  = true
		menuDragStart = inp.Position
		menuStartPos  = frame.Position
	end
end)

UserInputService.InputChanged:Connect(function(inp)
	if menuDragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
		local d = inp.Position - menuDragStart
		frame.Position = UDim2.new(
			menuStartPos.X.Scale, menuStartPos.X.Offset + d.X,
			menuStartPos.Y.Scale, menuStartPos.Y.Offset + d.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		menuDragging = false
	end
end)

makeDivider(HEADER_H)

-- ── Status bar ─────────────────────────────────────────────────────────────────
local statusBarY = HEADER_H + DIV
local statusBar  = Instance.new("Frame", frame)
statusBar.Size             = UDim2.new(1, 0, 0, STATUS_H)
statusBar.Position         = UDim2.new(0, 0, 0, statusBarY)
statusBar.BackgroundColor3 = C_SEC
statusBar.BorderSizePixel  = 0
statusBar.ZIndex           = 11

local statusLbl = Instance.new("TextLabel", statusBar)
statusLbl.Size               = UDim2.new(0.6, -8, 1, 0)
statusLbl.Position           = UDim2.new(0, 12, 0, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Font               = Enum.Font.Gotham
statusLbl.TextSize           = 11
statusLbl.TextColor3         = C_DIM
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left
statusLbl.Text               = "Status: Not created"
statusLbl.ZIndex             = 12

local queueCountLbl = Instance.new("TextLabel", statusBar)
queueCountLbl.Size               = UDim2.new(0.4, -12, 1, 0)
queueCountLbl.Position           = UDim2.new(0.6, 0, 0, 0)
queueCountLbl.BackgroundTransparency = 1
queueCountLbl.Font               = Enum.Font.Gotham
queueCountLbl.TextSize           = 11
queueCountLbl.TextColor3         = C_DIM
queueCountLbl.TextXAlignment     = Enum.TextXAlignment.Right
queueCountLbl.Text               = "Queue: 0"
queueCountLbl.ZIndex             = 12

-- Code TextBox — selectable, read-only; visible only when a server is active
-- Admins can click it, Ctrl+A, Ctrl+C to copy manually even if the button fails
local codeBox = Instance.new("TextBox", statusBar)
codeBox.Size             = UDim2.new(0, 210, 0, 22)
codeBox.Position         = UDim2.new(0, 106, 0.5, -11)
codeBox.BackgroundColor3 = C_BTN
codeBox.BorderSizePixel  = 0
codeBox.Font             = Enum.Font.Code
codeBox.TextSize         = 10
codeBox.TextColor3       = C_TXT
codeBox.TextXAlignment   = Enum.TextXAlignment.Left
codeBox.Text             = ""
codeBox.TextEditable     = false
codeBox.ClearTextOnFocus = false
codeBox.Visible          = false
codeBox.ZIndex           = 13
Instance.new("UICorner", codeBox).CornerRadius = UDim.new(0, 5)
local cbPad = Instance.new("UIPadding", codeBox)
cbPad.PaddingLeft = UDim.new(0, 6)
makeStroke(codeBox, C_BOR, 1, 0.5)

-- Copy button — fires GuiService:SetClipboard with a pcall so UI never breaks
-- if the API is unavailable; the codeBox above is always the manual fallback
local copyCodeBtn = Instance.new("TextButton", statusBar)
copyCodeBtn.Size             = UDim2.new(0, 72, 0, 22)
copyCodeBtn.Position         = UDim2.new(0, 320, 0.5, -11)
copyCodeBtn.BackgroundColor3 = C_BTN
copyCodeBtn.BorderSizePixel  = 0
copyCodeBtn.Font             = Enum.Font.Gotham
copyCodeBtn.TextSize         = 11
copyCodeBtn.TextColor3       = C_ACC
copyCodeBtn.Text             = "Copy"
copyCodeBtn.AutoButtonColor  = false
copyCodeBtn.Visible          = false
copyCodeBtn.ZIndex           = 13
Instance.new("UICorner", copyCodeBtn).CornerRadius = UDim.new(0, 5)
makeStroke(copyCodeBtn, C_BOR, 1, 0.5)

local copyFeedbackThread: thread? = nil
copyCodeBtn.MouseButton1Click:Connect(function()
	if not serverCode then return end
	local ok_ = pcall(function() GuiService:SetClipboard(serverCode) end)
	-- Cancel any in-flight revert before starting a new one
	if copyFeedbackThread then task.cancel(copyFeedbackThread) copyFeedbackThread = nil end
	if ok_ then
		copyCodeBtn.Text       = "✓ Copied!"
		copyCodeBtn.TextColor3 = C_OK
	else
		copyCodeBtn.Text       = "Select above"
		copyCodeBtn.TextColor3 = C_WARN
	end
	copyFeedbackThread = task.delay(1.5, function()
		copyCodeBtn.Text       = "Copy"
		copyCodeBtn.TextColor3 = C_ACC
		copyFeedbackThread = nil
	end)
end)

makeDivider(statusBarY + STATUS_H)

-- ── Column headers ─────────────────────────────────────────────────────────────
local colLabelY = statusBarY + STATUS_H + DIV

local leftColLabel = Instance.new("TextLabel", frame)
leftColLabel.Size               = UDim2.new(0, COL_W, 0, COL_LABEL_H)
leftColLabel.Position           = UDim2.new(0, 0, 0, colLabelY)
leftColLabel.BackgroundColor3   = C_HEAD
leftColLabel.BorderSizePixel    = 0
leftColLabel.Font               = Enum.Font.GothamBold
leftColLabel.TextSize           = 11
leftColLabel.TextColor3         = C_ACC
leftColLabel.Text               = "   Current Server"
leftColLabel.TextXAlignment     = Enum.TextXAlignment.Left
leftColLabel.ZIndex             = 11

local rightColLabel = Instance.new("TextLabel", frame)
rightColLabel.Size               = UDim2.new(0, COL_W, 0, COL_LABEL_H)
rightColLabel.Position           = UDim2.new(0, COL_W, 0, colLabelY)
rightColLabel.BackgroundColor3   = C_HEAD
rightColLabel.BorderSizePixel    = 0
rightColLabel.Font               = Enum.Font.GothamBold
rightColLabel.TextSize           = 11
rightColLabel.TextColor3         = C_ACC
rightColLabel.Text               = "   Send Queue"
rightColLabel.TextXAlignment     = Enum.TextXAlignment.Left
rightColLabel.ZIndex             = 11

-- ── Scroll columns ─────────────────────────────────────────────────────────────
local scrollY  = colLabelY + COL_LABEL_H
local scrollH  = CONTENT_H - COL_LABEL_H

local function makeScrollColumn(xOffset: number): ScrollingFrame
	local sf = Instance.new("ScrollingFrame", frame)
	sf.Size                  = UDim2.new(0, COL_W - 1, 0, scrollH)
	sf.Position              = UDim2.new(0, xOffset, 0, scrollY)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel        = 0
	sf.ScrollBarThickness     = 3
	sf.ScrollBarImageColor3   = C_BOR
	sf.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	sf.CanvasSize             = UDim2.new(0, 0, 0, 0)
	sf.ZIndex                 = 11

	local layout = Instance.new("UIListLayout", sf)
	layout.Padding   = UDim.new(0, CARD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local pad = Instance.new("UIPadding", sf)
	pad.PaddingLeft   = UDim.new(0, 6)
	pad.PaddingRight  = UDim.new(0, 6)
	pad.PaddingTop    = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)

	return sf
end

local leftScroll  = makeScrollColumn(0)
local rightScroll = makeScrollColumn(COL_W)

-- Center divider (vertical)
local centerDiv = Instance.new("Frame", frame)
centerDiv.Size             = UDim2.new(0, 1, 0, CONTENT_H)
centerDiv.Position         = UDim2.new(0, COL_W - 1, 0, colLabelY)
centerDiv.BackgroundColor3 = C_BOR
centerDiv.BackgroundTransparency = 0.5
centerDiv.BorderSizePixel  = 0
centerDiv.ZIndex           = 12

makeDivider(colLabelY + CONTENT_H)

-- ── Footer ─────────────────────────────────────────────────────────────────────
local footerY = colLabelY + CONTENT_H + DIV
local footer  = Instance.new("Frame", frame)
footer.Size             = UDim2.new(1, 0, 0, FOOTER_H)
footer.Position         = UDim2.new(0, 0, 0, footerY)
footer.BackgroundColor3 = C_FOOT
footer.BorderSizePixel  = 0
footer.ZIndex           = 11

-- (4 equal buttons, 10px outer pad, 6px inner gap)
-- (480 - 20 - 18) / 4 = 110.5 → 110px each; last button gets +2 to fill to edge
local BTN_H = 34
local BTN_Y = (FOOTER_H - BTN_H) / 2   -- 9
local BTN_W = 110
local BTN_STARTS = { 10, 126, 242, 358 }

local function makeFooterBtn(label: string, idx: number): TextButton
	local w   = (idx == 4) and 112 or BTN_W   -- last btn slightly wider to reach edge
	local btn = Instance.new("TextButton", footer)
	btn.Size             = UDim2.new(0, w, 0, BTN_H)
	btn.Position         = UDim2.new(0, BTN_STARTS[idx], 0, BTN_Y)
	btn.BackgroundColor3 = C_BTN
	btn.BorderSizePixel  = 0
	btn.Font             = Enum.Font.Gotham
	btn.TextSize         = 12
	btn.TextColor3       = C_TXT
	btn.Text             = label
	btn.AutoButtonColor  = false
	btn.ZIndex           = 12
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	makeStroke(btn, C_BOR, 1, 0.4)
	return btn
end

local createBtn = makeFooterBtn("Create Server", 1)
local sendBtn   = makeFooterBtn("Send Selected",  2)
local cancelBtn = makeFooterBtn("Cancel Server",  3)
local closeBtn  = makeFooterBtn("Close",          4)

-- ── Status-bar + button-state sync ─────────────────────────────────────────────
local function syncStatus()
	local n = 0
	for _ in queuedIds do n += 1 end
	queueCountLbl.Text = "Queue: " .. n

	-- helpers to show/hide the code row and restore normal layout
	local function showCodeRow()
		statusLbl.Size         = UDim2.new(0, 90, 1, 0)        -- shrink to "✓ Active" only
		codeBox.Text           = serverCode or ""
		codeBox.Visible        = true
		copyCodeBtn.Visible    = true
		queueCountLbl.Position = UDim2.new(0, 396, 0, 0)
		queueCountLbl.Size     = UDim2.new(0, 72, 1, 0)
	end
	local function hideCodeRow()
		statusLbl.Size         = UDim2.new(0.6, -8, 1, 0)      -- restore original width
		codeBox.Visible        = false
		copyCodeBtn.Visible    = false
		queueCountLbl.Position = UDim2.new(0.6, 0, 0, 0)
		queueCountLbl.Size     = UDim2.new(0.4, -12, 1, 0)
	end

	if serverStatus == "none" or serverStatus == "cancelled" then
		statusLbl.Text       = "Status: Not created"
		statusLbl.TextColor3 = C_DIM
		createBtn.Text       = "Create Server"
		createBtn.TextColor3 = C_TXT
		createBtn.BackgroundTransparency = 0
		hideCodeRow()
	elseif serverStatus == "reserving" then
		statusLbl.Text       = "Status: Reserving…"
		statusLbl.TextColor3 = C_WARN
		createBtn.Text       = "Reserving…"
		createBtn.TextColor3 = C_DIM
		createBtn.BackgroundTransparency = 0.3
		hideCodeRow()
	elseif serverStatus == "active" then
		statusLbl.Text       = "✓ Active"
		statusLbl.TextColor3 = C_OK
		createBtn.Text       = "✓ Active"
		createBtn.TextColor3 = C_OK
		createBtn.BackgroundTransparency = 0
		showCodeRow()
	elseif serverStatus == "failed" then
		statusLbl.Text       = "Status: Failed — retry?"
		statusLbl.TextColor3 = C_ERR
		createBtn.Text       = "Retry"
		createBtn.TextColor3 = C_TXT
		createBtn.BackgroundTransparency = 0
		hideCodeRow()
	end

	sendBtn.TextColor3 = (serverStatus == "active" and n > 0) and C_TXT or C_DIM
end

-- ── Card builder ───────────────────────────────────────────────────────────────
-- Forward-declare so makeCard callbacks can reference them
local rebuildLists: () -> ()
local moveToQueue:  (number) -> ()
local removeFromQueue: (number) -> ()

local function makeCard(parent: ScrollingFrame, player: Player, inQueue: boolean): Frame
	local card = Instance.new("Frame", parent)
	card.Name                = "Card_" .. player.UserId
	card.Size                = UDim2.new(1, 0, 0, CARD_H)
	card.BackgroundColor3    = C_BTN
	card.BorderSizePixel     = 0
	card.LayoutOrder         = player.UserId
	card.ZIndex              = 12
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 5)

	-- Drag-hint grip icon
	local grip = Instance.new("TextLabel", card)
	grip.Size               = UDim2.new(0, 12, 1, 0)
	grip.Position           = UDim2.new(0, 3, 0, 0)
	grip.BackgroundTransparency = 1
	grip.Text               = "⋮"
	grip.TextColor3         = C_DIM
	grip.TextSize           = 15
	grip.Font               = Enum.Font.Gotham
	grip.ZIndex             = 13

	-- Username
	local nameLbl = Instance.new("TextLabel", card)
	nameLbl.Size               = UDim2.new(1, -50, 0, 20)
	nameLbl.Position           = UDim2.new(0, 16, 0, 4)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text               = player.Name
	nameLbl.TextColor3         = C_TXT
	nameLbl.TextSize           = 12
	nameLbl.Font               = Enum.Font.GothamBold
	nameLbl.TextXAlignment     = Enum.TextXAlignment.Left
	nameLbl.TextTruncate       = Enum.TextTruncate.AtEnd
	nameLbl.ZIndex             = 13

	-- Team
	local team    = player.Team
	local teamLbl = Instance.new("TextLabel", card)
	teamLbl.Size               = UDim2.new(1, -50, 0, 13)
	teamLbl.Position           = UDim2.new(0, 16, 0, 22)
	teamLbl.BackgroundTransparency = 1
	teamLbl.Text               = team and team.Name or "No Team"
	teamLbl.TextColor3         = team and team.TeamColor.Color or C_DIM
	teamLbl.TextSize           = 10
	teamLbl.Font               = Enum.Font.Gotham
	teamLbl.TextXAlignment     = Enum.TextXAlignment.Left
	teamLbl.ZIndex             = 13

	-- Move button (→ or ←)
	local moveBtn = Instance.new("TextButton", card)
	moveBtn.Size             = UDim2.new(0, 28, 0, 24)
	moveBtn.Position         = UDim2.new(1, -34, 0.5, -12)
	moveBtn.BackgroundColor3 = C_ACC
	moveBtn.BackgroundTransparency = 0.65
	moveBtn.BorderSizePixel  = 0
	moveBtn.Font             = Enum.Font.GothamBold
	moveBtn.TextSize         = 13
	moveBtn.TextColor3       = C_TXT
	moveBtn.Text             = inQueue and "←" or "→"
	moveBtn.AutoButtonColor  = false
	moveBtn.ZIndex           = 14
	Instance.new("UICorner", moveBtn).CornerRadius = UDim.new(0, 4)

	local uid = player.UserId
	moveBtn.MouseButton1Click:Connect(function()
		if inQueue then removeFromQueue(uid) else moveToQueue(uid) end
	end)

	-- Drag initiation (on card body)
	card.InputBegan:Connect(function(inp)
		if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if dragState then return end  -- another drag already in progress

		local mp = UserInputService:GetMouseLocation()

		-- Ghost card that follows the cursor
		local ghost = Instance.new("Frame", sg)
		ghost.AnchorPoint      = Vector2.new(0.5, 0.5)
		ghost.Size             = UDim2.new(0, COL_W - 24, 0, CARD_H)
		ghost.Position         = UDim2.fromOffset(mp.X, mp.Y)
		ghost.BackgroundColor3 = C_BTN
		ghost.BackgroundTransparency = 0.2
		ghost.BorderSizePixel  = 0
		ghost.ZIndex           = 200
		Instance.new("UICorner", ghost).CornerRadius = UDim.new(0, 5)
		local ghostStroke = Instance.new("UIStroke", ghost)
		ghostStroke.Color     = C_DRAG
		ghostStroke.Thickness = 1.5

		local ghostLbl = Instance.new("TextLabel", ghost)
		ghostLbl.Size               = UDim2.new(1, -8, 1, 0)
		ghostLbl.Position           = UDim2.new(0, 8, 0, 0)
		ghostLbl.BackgroundTransparency = 1
		ghostLbl.Text               = player.Name
		ghostLbl.TextColor3         = C_TXT
		ghostLbl.TextSize           = 12
		ghostLbl.Font               = Enum.Font.GothamBold
		ghostLbl.TextXAlignment     = Enum.TextXAlignment.Left
		ghostLbl.ZIndex             = 201

		local hbConn = RunService.Heartbeat:Connect(function()
			local p = UserInputService:GetMouseLocation()
			ghost.Position = UDim2.fromOffset(p.X, p.Y)
		end)

		dragState = { userId = uid, ghost = ghost, hbConn = hbConn, fromQueue = inQueue }
	end)

	return card
end

-- ── Rebuild both columns ────────────────────────────────────────────────────────
rebuildLists = function()
	-- Clear old cards
	for _, child in leftScroll:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	for _, child in rightScroll:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- Populate (include LocalPlayer so admin can send themselves to the private server)
	for _, player in Players:GetPlayers() do
		if queuedIds[player.UserId] then
			makeCard(rightScroll, player, true)
		else
			makeCard(leftScroll, player, false)
		end
	end

	syncStatus()
end

-- ── Queue helpers ───────────────────────────────────────────────────────────────
moveToQueue = function(uid: number)
	queuedIds[uid] = true
	rebuildLists()
end

removeFromQueue = function(uid: number)
	queuedIds[uid] = nil
	rebuildLists()
end

-- ── Drag-drop: resolve drop column on release ───────────────────────────────────
UserInputService.InputEnded:Connect(function(inp)
	if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not dragState then return end

	local state = dragState
	dragState   = nil
	state.hbConn:Disconnect()
	state.ghost:Destroy()

	-- Work out whether the mouse is over the left or right column
	local mp       = UserInputService:GetMouseLocation()
	local fPos     = frame.AbsolutePosition
	local fSize    = frame.AbsoluteSize
	local inX      = mp.X >= fPos.X and mp.X <= fPos.X + fSize.X
	local inColY   = mp.Y >= fPos.Y + scrollY and mp.Y <= fPos.Y + scrollY + scrollH

	if inX and inColY then
		local overRight = mp.X >= fPos.X + COL_W
		if state.fromQueue and not overRight then
			removeFromQueue(state.userId)
		elseif not state.fromQueue and overRight then
			moveToQueue(state.userId)
		end
	end
end)

-- ── Footer button handlers ──────────────────────────────────────────────────────
createBtn.MouseButton1Click:Connect(function()
	if serverStatus == "reserving" then return end
	if serverStatus == "active"    then return end
	serverStatus = "reserving"
	syncStatus()
	CommandRemotes.PrivateServerReserve:FireServer()
end)

sendBtn.MouseButton1Click:Connect(function()
	if serverStatus ~= "active" then return end
	local ids: { number } = {}
	for uid in queuedIds do table.insert(ids, uid) end
	if #ids == 0 then return end
	CommandRemotes.PrivateServerSend:FireServer(ids)
	-- Optimistic clear — server will confirm via CommandFeedback
	queuedIds = {}
	rebuildLists()
end)

cancelBtn.MouseButton1Click:Connect(function()
	if serverStatus ~= "none" and serverStatus ~= "cancelled" then
		CommandRemotes.PrivateServerCancel:FireServer()
	end
	serverStatus = "none"
	queuedIds    = {}
	rebuildLists()
	sg.Enabled = false
end)

closeBtn.MouseButton1Click:Connect(function()
	sg.Enabled = false
end)

headerCloseBtn.MouseButton1Click:Connect(function()
	sg.Enabled = false
end)

-- ── Player join / leave — keep lists fresh while menu is open ───────────────────
Players.PlayerAdded:Connect(function()
	if sg.Enabled then rebuildLists() end
end)

Players.PlayerRemoving:Connect(function(player)
	queuedIds[player.UserId] = nil
	if sg.Enabled then rebuildLists() end
end)

-- ── Remote listeners ────────────────────────────────────────────────────────────
CommandRemotes.PrivateServerOpen.OnClientEvent:Connect(function()
	-- Reset to a clean, centred state each time the command fires
	serverStatus = "none"
	serverCode   = nil
	queuedIds    = {}
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	rebuildLists()
	sg.Enabled = true
end)

CommandRemotes.PrivateServerStatus.OnClientEvent:Connect(function(status: string, code: string?)
	if typeof(status) ~= "string" then return end
	serverStatus = status
	if status == "active" and typeof(code) == "string" then
		serverCode = code
	elseif status ~= "active" then
		serverCode = nil
	end
	syncStatus()
end)
