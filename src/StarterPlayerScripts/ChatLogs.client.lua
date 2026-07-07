local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local ChatRemotes    = require(ReplicatedStorage:WaitForChild("ChatRemotes"))
local MarkdownParser = require(ReplicatedStorage:WaitForChild("MarkdownParser"))

local MAX_ENTRIES = 500   -- oldest entry is evicted when this is exceeded

local WIN_W   = 480
local WIN_H   = 480
local TITLE_H = 38
local SRCH_H  = 34

-- Colour palette — dark, matches CommandBar aesthetic
local C_BG      = Color3.fromRGB(12,  12,  18)
local C_TITLE   = Color3.fromRGB(18,  18,  28)
local C_BORDER  = Color3.fromRGB(80,  80, 110)
local C_TXT     = Color3.fromRGB(218, 218, 230)
local C_DIM     = Color3.fromRGB(85,  85, 105)
local C_SRCH    = Color3.fromRGB(20,  20,  32)
local C_ROW     = Color3.fromRGB(16,  16,  24)
local C_SEP     = Color3.fromRGB(45,  45,  65)
-- Thoughts messages are rendered in this purple so they stand out immediately.
local C_THOUGHT  = "#a064ff"
-- Whisper messages are rendered in light gray to distinguish them from normal chat.
local C_WHISPER  = "#b8b8c8"

-- Each entry:  { teamName, teamColor, senderName, message, row }
local logEntries   = {}
local currentQuery = ""
local isOpen       = false
local nextOrder    = 0   -- monotonic counter; never reused, keeps UIListLayout ordering stable

local sg = Instance.new("ScreenGui")
sg.Name           = "ChatLogsGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = false
sg.DisplayOrder   = 50
sg.Enabled        = false
sg.Parent         = PGui

local win = Instance.new("Frame", sg)
win.AnchorPoint          = Vector2.new(0.5, 0.5)
win.Size                 = UDim2.fromOffset(WIN_W, WIN_H)
win.Position             = UDim2.new(0.5, 0, 0.5, 0)
win.BackgroundColor3 = C_BG
win.BorderSizePixel  = 0
win.ClipsDescendants     = true
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 10)
do
	local s = Instance.new("UIStroke", win)
	s.Color           = C_BORDER
	s.Thickness       = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local titleBar = Instance.new("Frame", win)
titleBar.Size                  = UDim2.new(1, 0, 0, TITLE_H)
titleBar.BackgroundColor3 = C_TITLE
titleBar.BorderSizePixel  = 0

local titleLbl = Instance.new("TextLabel", titleBar)
titleLbl.Size                   = UDim2.new(1, -50, 1, 0)
titleLbl.Position               = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font                   = Enum.Font.GothamBold
titleLbl.TextSize               = 14
titleLbl.TextColor3             = C_TXT
titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
titleLbl.TextYAlignment         = Enum.TextYAlignment.Center
titleLbl.Text                   = "Chat Logs"

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.AnchorPoint            = Vector2.new(1, 0.5)
closeBtn.Size                   = UDim2.fromOffset(26, 26)
closeBtn.Position               = UDim2.new(1, -8, 0.5, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.BorderSizePixel        = 0
closeBtn.Font                   = Enum.Font.GothamBold
closeBtn.TextSize               = 13
closeBtn.TextColor3             = C_DIM
closeBtn.Text                   = "X"
closeBtn.AutoButtonColor        = false
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

-- Title / search separator
local sep0 = Instance.new("Frame", win)
sep0.Size             = UDim2.new(1, 0, 0, 1)
sep0.Position         = UDim2.new(0, 0, 0, TITLE_H)
sep0.BackgroundColor3 = C_BORDER
sep0.BackgroundTransparency = 0.5
sep0.BorderSizePixel  = 0

local srchWrap = Instance.new("Frame", win)
srchWrap.Size                  = UDim2.new(1, -16, 0, SRCH_H)
srchWrap.Position               = UDim2.new(0, 8, 0, TITLE_H + 7)
srchWrap.BackgroundColor3 = C_SRCH
srchWrap.BorderSizePixel  = 0
Instance.new("UICorner", srchWrap).CornerRadius = UDim.new(0, 6)
do
	local s = Instance.new("UIStroke", srchWrap)
	s.Color           = C_BORDER
	s.Thickness       = 1
	s.Transparency    = 0.45
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local searchBox = Instance.new("TextBox", srchWrap)
searchBox.Size                = UDim2.new(1, -14, 1, 0)
searchBox.Position            = UDim2.new(0, 14, 0, 0)
searchBox.BackgroundTransparency = 1
searchBox.BorderSizePixel     = 0
searchBox.ClearTextOnFocus    = false
searchBox.Font                = Enum.Font.Gotham
searchBox.TextSize            = 12
searchBox.TextColor3          = C_TXT
searchBox.PlaceholderText     = "Search chatlogs"
searchBox.PlaceholderColor3   = C_DIM
searchBox.Text                = ""
searchBox.TextXAlignment      = Enum.TextXAlignment.Left
searchBox.TextYAlignment      = Enum.TextYAlignment.Center

local SCROLL_TOP = TITLE_H + SRCH_H + 15

local scroll = Instance.new("ScrollingFrame", win)
scroll.Size                  = UDim2.new(1, -8, 1, -(SCROLL_TOP + 6))
scroll.Position              = UDim2.new(0, 4, 0, SCROLL_TOP)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel       = 0
scroll.ScrollBarThickness    = 4
scroll.ScrollBarImageColor3  = C_BORDER
scroll.ScrollingDirection    = Enum.ScrollingDirection.Y
scroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
scroll.CanvasSize            = UDim2.new(0, 0, 0, 0)
scroll.ClipsDescendants      = true

local listLayout = Instance.new("UIListLayout", scroll)
listLayout.FillDirection     = Enum.FillDirection.Vertical
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.SortOrder         = Enum.SortOrder.LayoutOrder
listLayout.Padding           = UDim.new(0, 0)

-- Escape characters that would break RichText parsing.
local XML_ESC = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }
local function escXml(s)
	return (s:gsub('[&<>"]', XML_ESC))
end

-- Convert Color3 (0–1 floats) → "#rrggbb" hex for RichText <font color>.
local function toHex(c)
	return string.format("#%02x%02x%02x",
		math.clamp(math.floor(c.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.B * 255 + 0.5), 0, 255))
end

-- Build the RichText string for one log entry.
-- Normal format:  {TeamName} [Username]: "Message"
-- Thought format: [THOUGHTS] [Username]: "Message"  (whole line in purple)
-- Whisper format: [WHISPER]  [Username]: "Message"  (whole line in light gray)
local function buildText(entry)
	if entry.isThought then
		return string.format(
			'<font color="%s">[THOUGHTS] [%s]: "%s"</font>',
			C_THOUGHT,
			escXml(entry.senderName),
			MarkdownParser.toRichText(entry.message)
		)
	end
	if entry.isWhisper then
		return string.format(
			'<font color="%s">[WHISPER] [%s]: "%s"</font>',
			C_WHISPER,
			escXml(entry.senderName),
			MarkdownParser.toRichText(entry.message)
		)
	end
	return string.format(
		'<font color="%s">{%s}</font> [%s]: "%s"',
		toHex(entry.teamColor),
		escXml(entry.teamName),
		escXml(entry.senderName),
		MarkdownParser.toRichText(entry.message)
	)
end

-- Create a row Frame for one entry and return it (not yet parented).
local function makeRow(entry, layoutOrder)
	local row = Instance.new("Frame")
	row.Name              = "Row"
	row.LayoutOrder       = layoutOrder
	row.Size              = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize     = Enum.AutomaticSize.Y
	row.BackgroundColor3  = C_ROW
	row.BackgroundTransparency = 0.45
	row.BorderSizePixel   = 0

	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft   = UDim.new(0, 10)
	pad.PaddingRight  = UDim.new(0, 10)
	pad.PaddingTop    = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)

	-- Thin separator line at the bottom of every row
	local sep = Instance.new("Frame", row)
	sep.Size             = UDim2.new(1, 0, 0, 1)
	sep.AnchorPoint      = Vector2.new(0, 1)
	sep.Position         = UDim2.new(0, 0, 1, 0)
	sep.BackgroundColor3 = C_SEP
	sep.BackgroundTransparency = 0.35
	sep.BorderSizePixel  = 0

	local lbl = Instance.new("TextLabel", row)
	lbl.Size                  = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize         = Enum.AutomaticSize.Y
	lbl.BackgroundTransparency = 1
	lbl.Font                  = Enum.Font.Code
	lbl.TextSize              = 15
	lbl.TextColor3            = C_TXT
	lbl.TextXAlignment        = Enum.TextXAlignment.Left
	lbl.TextYAlignment        = Enum.TextYAlignment.Top
	lbl.TextWrapped           = true
	lbl.RichText              = true
	lbl.TextStrokeTransparency = 1
	lbl.Text                  = buildText(entry)

	return row
end

local function matchesQuery(entry, q)
	if q == "" then return true end
	return entry.teamName:lower():find(q, 1, true) ~= nil
		or entry.senderName:lower():find(q, 1, true) ~= nil
		or entry.message:lower():find(q, 1, true) ~= nil
end

local function applyFilter(rawQuery)
	currentQuery = rawQuery:lower()
	for _, e in ipairs(logEntries) do
		if e.row then
			e.row.Visible = matchesQuery(e, currentQuery)
		end
	end
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	applyFilter(searchBox.Text)
end)

local function scrollToBottom()
	task.defer(function()
		scroll.CanvasPosition = Vector2.new(0, math.huge)
	end)
end

local function closeWindow()
	if not isOpen then return end
	isOpen = false
	sg.Enabled = false
end

local function openWindow()
	if isOpen then return end
	isOpen = true
	sg.Enabled = true
	scrollToBottom()
end

closeBtn.MouseButton1Click:Connect(closeWindow)

local dragging  = false
local dragStart = Vector2.zero
local winStart  = UDim2.new()

titleBar.InputBegan:Connect(function(inp)
	if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	dragging  = true
	dragStart = Vector2.new(inp.Position.X, inp.Position.Y)
	winStart  = win.Position
end)

UserInputService.InputChanged:Connect(function(inp)
	if not dragging or inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	local d = Vector2.new(inp.Position.X, inp.Position.Y) - dragStart
	win.Position = UDim2.new(
		winStart.X.Scale, winStart.X.Offset + d.X,
		winStart.Y.Scale, winStart.Y.Offset + d.Y
	)
end)

UserInputService.InputEnded:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)

task.spawn(function()
	local toggle = PGui:WaitForChild("ToggleChatLogs", 30)
	if not toggle then
		warn("[ChatLogs] ToggleChatLogs BindableEvent not found — chatlogs command won't work.")
		return
	end
	toggle.Event:Connect(function()
		if isOpen then closeWindow() else openWindow() end
	end)
end)

ChatRemotes.MessageReceived.OnClientEvent:Connect(function(payload)
	if not payload or not payload.senderName then return end

	-- Evict oldest entry if at cap
	if #logEntries >= MAX_ENTRIES then
		local oldest = table.remove(logEntries, 1)
		if oldest.row then oldest.row:Destroy() end
	end

	local teamColor = Color3.new(
		payload.teamColorR or 0.8,
		payload.teamColorG or 0.8,
		payload.teamColorB or 0.8
	)

	local entry = {
		teamName   = payload.teamName   or "No Team",
		teamColor  = teamColor,
		senderName = payload.senderName,
		message    = payload.message    or "",
		isThought  = payload.isThought == true,
		isWhisper  = payload.isWhisper  == true,
		row        = nil,
	}

	table.insert(logEntries, entry)
	nextOrder += 1

	local row = makeRow(entry, nextOrder)
	row.Visible = matchesQuery(entry, currentQuery)
	row.Parent  = scroll
	entry.row   = row

	if isOpen and row.Visible then
		scrollToBottom()
	end
end)

print("[ChatLogs] Ready")
