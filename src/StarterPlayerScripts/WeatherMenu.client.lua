local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

-- Read the authoritative weather state the server wrote on last change.
-- This is a StringValue in ReplicatedStorage — always present and immediately
-- readable without any timing dependency on RemoteEvent delivery order.
local activeWeatherValue = ReplicatedStorage:WaitForChild("ActiveWeather", 10) :: StringValue?

-- ── palette (same as CommandBar / CommandNotify) ───────────────────────────────
local C_BG   = Color3.fromRGB(12,  12,  18)
local C_BOR  = Color3.fromRGB(90,  90, 120)
local C_TXT  = Color3.fromRGB(235, 235, 252)
local C_DIM  = Color3.fromRGB(80,  80, 100)
local C_ACC  = Color3.fromRGB(160, 160, 210)
local C_ACT  = Color3.fromRGB(100, 140, 255)
local C_HEAD = Color3.fromRGB(16,  16,  26)
local C_FOOT = Color3.fromRGB(14,  14,  22)
local C_BTN  = Color3.fromRGB(22,  22,  34)

local WEATHER_ORDER = { "Clear", "Rain", "Storm", "Fog", "Snow", "Sandstorm", "Wind" }

-- ── layout constants ───────────────────────────────────────────────────────────
local MENU_W   = 272
local PAD      = 12
local HEADER_H = 44
local STATUS_H = 36
local BTN_H    = 38
local BTN_GAP  = 4
local FOOTER_H = 50
local DIV_H    = 1

-- total button area (no extra padding; UIListLayout handles gaps)
local SCROLL_H = #WEATHER_ORDER * BTN_H + (#WEATHER_ORDER - 1) * BTN_GAP
local MENU_H   = HEADER_H + DIV_H + STATUS_H + DIV_H + SCROLL_H + DIV_H + FOOTER_H

local isOpen         = false
local currentWeather = nil

-- ── ScreenGui ──────────────────────────────────────────────────────────────────
local sg = Instance.new("ScreenGui")
sg.Name           = "WeatherMenuGui"
sg.DisplayOrder   = 105
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = false
sg.Enabled        = false
sg.Parent         = PGui

-- ── Main frame ────────────────────────────────────────────────────────────────
local frame = Instance.new("Frame")
frame.Name             = "WeatherMenu"
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

-- UIScale used for the open/close pop animation
local uiScale = Instance.new("UIScale", frame)
uiScale.Scale = 1

-- ── Header (drag handle) ──────────────────────────────────────────────────────
local header = Instance.new("Frame", frame)
header.Name             = "Header"
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.Position         = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = C_HEAD
header.BorderSizePixel  = 0
header.ZIndex           = 11

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size               = UDim2.new(1, -44, 1, 0)
titleLbl.Position           = UDim2.new(0, PAD, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 14
titleLbl.TextColor3         = C_TXT
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.TextYAlignment     = Enum.TextYAlignment.Center
titleLbl.Text               = "Weather Control"
titleLbl.ZIndex             = 12

local headerClose = Instance.new("TextButton", header)
headerClose.AnchorPoint        = Vector2.new(1, 0.5)
headerClose.Position           = UDim2.new(1, -8, 0.5, 0)
headerClose.Size               = UDim2.new(0, 28, 0, 28)
headerClose.BackgroundColor3   = Color3.fromRGB(55, 25, 25)
headerClose.BackgroundTransparency = 0.35
headerClose.Font               = Enum.Font.GothamBold
headerClose.TextSize           = 14
headerClose.TextColor3         = Color3.fromRGB(220, 90, 90)
headerClose.Text               = "✕"
headerClose.AutoButtonColor    = false
headerClose.ZIndex             = 12
Instance.new("UICorner", headerClose).CornerRadius = UDim.new(0, 6)

-- ── Divider 1 ─────────────────────────────────────────────────────────────────
local function makeDivider(parent, yPos)
	local d = Instance.new("Frame", parent)
	d.Size             = UDim2.new(1, 0, 0, DIV_H)
	d.Position         = UDim2.new(0, 0, 0, yPos)
	d.BackgroundColor3 = C_BOR
	d.BackgroundTransparency = 0.55
	d.BorderSizePixel  = 0
	d.ZIndex           = 11
	return d
end

local div1Y = HEADER_H
makeDivider(frame, div1Y)

-- ── Active weather status bar ─────────────────────────────────────────────────
local statusY     = div1Y + DIV_H
local statusFrame = Instance.new("Frame", frame)
statusFrame.Size             = UDim2.new(1, 0, 0, STATUS_H)
statusFrame.Position         = UDim2.new(0, 0, 0, statusY)
statusFrame.BackgroundTransparency = 1
statusFrame.BorderSizePixel  = 0
statusFrame.ZIndex           = 11

local statusLabel = Instance.new("TextLabel", statusFrame)
statusLabel.Size               = UDim2.new(1, -(PAD * 2 + 16), 1, 0)
statusLabel.Position           = UDim2.new(0, PAD, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font               = Enum.Font.Gotham
statusLabel.TextSize           = 12
statusLabel.TextColor3         = C_DIM
statusLabel.TextXAlignment     = Enum.TextXAlignment.Left
statusLabel.TextYAlignment     = Enum.TextYAlignment.Center
statusLabel.Text               = "Active: None"
statusLabel.ZIndex             = 12

-- small coloured indicator dot on the right of the status bar
local dot = Instance.new("Frame", statusFrame)
dot.AnchorPoint      = Vector2.new(1, 0.5)
dot.Position         = UDim2.new(1, -PAD, 0.5, 0)
dot.Size             = UDim2.new(0, 8, 0, 8)
dot.BackgroundColor3 = C_DIM
dot.BorderSizePixel  = 0
dot.ZIndex           = 12
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

-- ── Divider 2 ─────────────────────────────────────────────────────────────────
local div2Y = statusY + STATUS_H
makeDivider(frame, div2Y)

-- ── Scrolling button list ─────────────────────────────────────────────────────
local scrollY     = div2Y + DIV_H
local scrollFrame = Instance.new("ScrollingFrame", frame)
scrollFrame.Size                  = UDim2.new(1, 0, 0, SCROLL_H)
scrollFrame.Position              = UDim2.new(0, 0, 0, scrollY)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel       = 0
scrollFrame.ScrollBarThickness    = 4
scrollFrame.ScrollBarImageColor3  = C_ACC
scrollFrame.CanvasSize            = UDim2.new(0, 0, 0, SCROLL_H)
scrollFrame.AutomaticCanvasSize   = Enum.AutomaticSize.Y
scrollFrame.ZIndex                = 11

local listLayout = Instance.new("UIListLayout", scrollFrame)
listLayout.FillDirection       = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.SortOrder           = Enum.SortOrder.LayoutOrder
listLayout.Padding             = UDim.new(0, BTN_GAP)

-- ── Weather buttons ────────────────────────────────────────────────────────────
local weatherButtons = {}  -- [weatherName] = { frame, accent, label }

for i, name in ipairs(WEATHER_ORDER) do
	local btn = Instance.new("TextButton", scrollFrame)
	btn.Name                = name
	btn.LayoutOrder         = i
	btn.Size                = UDim2.new(1, -(PAD * 2), 0, BTN_H)
	btn.BackgroundColor3    = C_BTN
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel     = 0
	btn.AutoButtonColor     = false
	btn.Text                = ""
	btn.ZIndex              = 12
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

	-- left accent bar (highlighted when active)
	local accent = Instance.new("Frame", btn)
	accent.Name             = "Accent"
	accent.AnchorPoint      = Vector2.new(0, 0.5)
	accent.Size             = UDim2.new(0, 3, 1, -10)
	accent.Position         = UDim2.new(0, 6, 0.5, 0)
	accent.BackgroundColor3 = C_DIM
	accent.BorderSizePixel  = 0
	accent.ZIndex           = 13
	Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

	local lbl = Instance.new("TextLabel", btn)
	lbl.Size               = UDim2.new(1, -22, 1, 0)
	lbl.Position           = UDim2.new(0, 18, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 13
	lbl.TextColor3         = C_TXT
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.TextYAlignment     = Enum.TextYAlignment.Center
	lbl.Text               = name
	lbl.ZIndex             = 13

	weatherButtons[name] = { frame = btn, accent = accent, label = lbl }

	btn.MouseEnter:Connect(function()
		if name ~= currentWeather then
			btn.BackgroundTransparency = 0.78
		end
	end)
	btn.MouseLeave:Connect(function()
		if name ~= currentWeather then
			btn.BackgroundTransparency = 1
		end
	end)
	btn.MouseButton1Click:Connect(function()
		CommandRemotes.WeatherApply:FireServer(name)
	end)
end

-- ── Divider 3 ─────────────────────────────────────────────────────────────────
local div3Y = scrollY + SCROLL_H
makeDivider(frame, div3Y)

-- ── Footer ────────────────────────────────────────────────────────────────────
local footerY = div3Y + DIV_H
local footer  = Instance.new("Frame", frame)
footer.Size             = UDim2.new(1, 0, 0, FOOTER_H)
footer.Position         = UDim2.new(0, 0, 0, footerY)
footer.BackgroundColor3 = C_FOOT
footer.BorderSizePixel  = 0
footer.ZIndex           = 11

local BW = math.floor((MENU_W - PAD * 3) / 2)

local refreshBtn = Instance.new("TextButton", footer)
refreshBtn.AnchorPoint        = Vector2.new(0, 0.5)
refreshBtn.Position           = UDim2.new(0, PAD, 0.5, 0)
refreshBtn.Size               = UDim2.new(0, BW, 0, 30)
refreshBtn.BackgroundColor3   = Color3.fromRGB(25, 35, 58)
refreshBtn.BackgroundTransparency = 0.25
refreshBtn.Font               = Enum.Font.Gotham
refreshBtn.TextSize           = 12
refreshBtn.TextColor3         = C_ACC
refreshBtn.Text               = "↺  Refresh"
refreshBtn.AutoButtonColor    = false
refreshBtn.ZIndex             = 12
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 6)
local rStroke = Instance.new("UIStroke", refreshBtn)
rStroke.Color = C_BOR; rStroke.Thickness = 1; rStroke.Transparency = 0.45
rStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local closeFooter = Instance.new("TextButton", footer)
closeFooter.AnchorPoint        = Vector2.new(1, 0.5)
closeFooter.Position           = UDim2.new(1, -PAD, 0.5, 0)
closeFooter.Size               = UDim2.new(0, BW, 0, 30)
closeFooter.BackgroundColor3   = Color3.fromRGB(42, 18, 18)
closeFooter.BackgroundTransparency = 0.25
closeFooter.Font               = Enum.Font.Gotham
closeFooter.TextSize           = 12
closeFooter.TextColor3         = Color3.fromRGB(210, 85, 85)
closeFooter.Text               = "Close"
closeFooter.AutoButtonColor    = false
closeFooter.ZIndex             = 12
Instance.new("UICorner", closeFooter).CornerRadius = UDim.new(0, 6)
local cStroke = Instance.new("UIStroke", closeFooter)
cStroke.Color = Color3.fromRGB(110, 50, 50); cStroke.Thickness = 1; cStroke.Transparency = 0.45
cStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- ── Draggable ─────────────────────────────────────────────────────────────────
local dragging  = false
local dragStart = nil
local framePos  = nil

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging  = true
		dragStart = input.Position
		framePos  = frame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	local delta = input.Position - dragStart
	frame.Position = UDim2.new(
		framePos.X.Scale, framePos.X.Offset + delta.X,
		framePos.Y.Scale, framePos.Y.Offset + delta.Y
	)
end)

-- ── Open / Close animation ────────────────────────────────────────────────────
local openInfo  = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local closeInfo = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function openMenu()
	if isOpen then return end
	isOpen        = true
	sg.Enabled    = true
	uiScale.Scale = 0.90
	TweenService:Create(uiScale, openInfo, { Scale = 1 }):Play()
end

local function closeMenu()
	if not isOpen then return end
	isOpen = false
	local t = TweenService:Create(uiScale, closeInfo, { Scale = 0.90 })
	t:Play()
	t.Completed:Connect(function()
		if not isOpen then sg.Enabled = false end
	end)
end

-- ── Highlight helpers ─────────────────────────────────────────────────────────
local function updateHighlight(name)
	currentWeather    = name
	statusLabel.Text  = "Active: " .. (name or "None")
	dot.BackgroundColor3 = name and C_ACT or C_DIM

	for wName, refs in pairs(weatherButtons) do
		local active = (wName == name)
		refs.frame.BackgroundTransparency = active and 0.60 or 1
		refs.frame.BackgroundColor3       = active and Color3.fromRGB(22, 32, 58) or C_BTN
		refs.accent.BackgroundColor3      = active and C_ACT or C_DIM
		refs.label.TextColor3             = active and Color3.new(1, 1, 1) or C_TXT
	end
end

-- ── Button connections ────────────────────────────────────────────────────────
headerClose.MouseButton1Click:Connect(closeMenu)
closeFooter.MouseButton1Click:Connect(closeMenu)

refreshBtn.MouseButton1Click:Connect(function()
	if currentWeather then
		CommandRemotes.WeatherApply:FireServer(currentWeather)
	end
end)

-- ── Remote connections ────────────────────────────────────────────────────────
CommandRemotes.WeatherOpen.OnClientEvent:Connect(function()
	if isOpen then closeMenu() else openMenu() end
end)

CommandRemotes.WeatherSync.OnClientEvent:Connect(function(weatherName)
	if typeof(weatherName) == "string" then
		updateHighlight(weatherName)
	end
end)

-- Seed the highlight from the StringValue immediately on load so a joining
-- admin sees the correct active weather without waiting for a remote fire.
if activeWeatherValue then
	local initial = activeWeatherValue.Value
	if initial ~= "" then updateHighlight(initial) end
end
