--[[
	WeatherMenu.client.lua
	Full Weather & Environment editor. Toggled by the `weather` admin command.
	Tabs: Weather | Lighting | Atmosphere | Clouds | Environment
	All property changes are sent to WeatherServer via remotes; server validates
	and applies so every player sees the result.
]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local Workspace        = game:GetService("Workspace")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local CommandRemotes     = require(ReplicatedStorage:WaitForChild("CommandRemotes"))
local activeWeatherValue = ReplicatedStorage:WaitForChild("ActiveWeather", 10) :: StringValue?

-- Replicated world instances (server creates these; available via replication)
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local terrain    = Workspace:FindFirstChildOfClass("Terrain")
local clouds     = terrain and terrain:FindFirstChildOfClass("Clouds")

-- ── Palette (matches CommandBar / CommandNotify) ──────────────────────────────
local C_BG   = Color3.fromRGB( 12,  12,  18)
local C_BOR  = Color3.fromRGB( 90,  90, 120)
local C_TXT  = Color3.fromRGB(235, 235, 252)
local C_DIM  = Color3.fromRGB( 80,  80, 100)
local C_ACC  = Color3.fromRGB(160, 160, 210)
local C_ACT  = Color3.fromRGB(100, 140, 255)
local C_HEAD = Color3.fromRGB( 16,  16,  26)
local C_FOOT = Color3.fromRGB( 14,  14,  22)
local C_BTN  = Color3.fromRGB( 22,  22,  34)
local C_TAB  = Color3.fromRGB( 18,  18,  28)
local C_SEC  = Color3.fromRGB( 20,  20,  34)

local WEATHER_ORDER = { "Clear", "Rain", "Storm", "Fog", "Snow", "Sandstorm", "Wind" }
local TABS          = { "Weather", "Lighting", "Atmosphere", "Clouds", "Environment" }

-- ── Layout constants ──────────────────────────────────────────────────────────
local MENU_W    = 600
local PAD       = 12
local HEADER_H  = 44
local TAB_H     = 34
local CONTENT_H = 360
local FOOTER_H  = 50
local DIV_H     = 1
local MENU_H    = HEADER_H + DIV_H + TAB_H + DIV_H + CONTENT_H + DIV_H + FOOTER_H

local BTN_H   = 38
local BTN_GAP = 4
local SLI_H   = 48
local SEC_H   = 28
local TOG_H   = 36
local CH_H    = 24  -- per-channel row height inside color picker
local THUMB_S = 14

-- ── Runtime state ─────────────────────────────────────────────────────────────
local isOpen         = false
local currentWeather = nil
local activeTab      = nil
local weatherButtons = {}  -- [name] = {frame, accent, label}
local tabBtns        = {}  -- [tabName] = TextButton
local tabContent     = {}  -- [tabName] = ScrollingFrame
local activeSliderFn = nil -- position handler for the slider currently dragged
local refreshFns     = {}  -- called on open to sync sliders → world state

-- ── ScreenGui ─────────────────────────────────────────────────────────────────
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

local uiScale = Instance.new("UIScale", frame)
uiScale.Scale = 1

-- ── Header (drag handle + title + close) ──────────────────────────────────────
local header = Instance.new("Frame", frame)
header.Name             = "Header"
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.Position         = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = C_HEAD
header.BorderSizePixel  = 0
header.ZIndex           = 11

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size               = UDim2.new(1, -PAD, 1, 0)
titleLbl.Position           = UDim2.new(0, PAD, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 14
titleLbl.TextColor3         = C_TXT
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.TextYAlignment     = Enum.TextYAlignment.Center
titleLbl.Text               = "Weather & Environment"
titleLbl.ZIndex             = 12

-- ── Divider helper ────────────────────────────────────────────────────────────
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

makeDivider(frame, HEADER_H)

-- ── Tab bar ───────────────────────────────────────────────────────────────────
local tabBarY = HEADER_H + DIV_H
local tabBar  = Instance.new("Frame", frame)
tabBar.Name             = "TabBar"
tabBar.Size             = UDim2.new(1, 0, 0, TAB_H)
tabBar.Position         = UDim2.new(0, 0, 0, tabBarY)
tabBar.BackgroundColor3 = C_TAB
tabBar.BorderSizePixel  = 0
tabBar.ZIndex           = 11

local TAB_W = math.floor(MENU_W / #TABS)

for i, tabName in ipairs(TABS) do
	local btn = Instance.new("TextButton", tabBar)
	btn.Name                  = tabName
	btn.Size                  = UDim2.new(0, TAB_W, 1, 0)
	btn.Position              = UDim2.new(0, (i - 1) * TAB_W, 0, 0)
	btn.BackgroundTransparency = 1
	btn.Font                  = Enum.Font.Gotham
	btn.TextSize              = 12
	btn.TextColor3            = C_DIM
	btn.Text                  = tabName
	btn.AutoButtonColor       = false
	btn.ZIndex                = 12
	tabBtns[tabName] = btn
end

makeDivider(frame, tabBarY + TAB_H)

-- ── Content ScrollingFrames (one per tab, hidden until tab selected) ──────────
local contentY = tabBarY + TAB_H + DIV_H

for _, tabName in ipairs(TABS) do
	local sf = Instance.new("ScrollingFrame", frame)
	sf.Name                  = tabName .. "Content"
	sf.Size                  = UDim2.new(1, 0, 0, CONTENT_H)
	sf.Position              = UDim2.new(0, 0, 0, contentY)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel       = 0
	sf.ScrollBarThickness    = 4
	sf.ScrollBarImageColor3  = C_ACC
	sf.CanvasSize            = UDim2.new(0, 0, 0, 0)
	sf.AutomaticCanvasSize   = Enum.AutomaticSize.Y
	sf.Visible               = false
	sf.ZIndex                = 11

	local ll = Instance.new("UIListLayout", sf)
	ll.FillDirection       = Enum.FillDirection.Vertical
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Left
	ll.SortOrder           = Enum.SortOrder.LayoutOrder
	ll.Padding             = UDim.new(0, 6)

	local padInset = Instance.new("UIPadding", sf)
	padInset.PaddingLeft   = UDim.new(0, PAD)
	padInset.PaddingRight  = UDim.new(0, PAD)
	padInset.PaddingTop    = UDim.new(0, 8)
	padInset.PaddingBottom = UDim.new(0, 8)

	tabContent[tabName] = sf
end

makeDivider(frame, contentY + CONTENT_H)

-- ── Footer ────────────────────────────────────────────────────────────────────
local footerY = contentY + CONTENT_H + DIV_H
local footer  = Instance.new("Frame", frame)
footer.Size             = UDim2.new(1, 0, 0, FOOTER_H)
footer.Position         = UDim2.new(0, 0, 0, footerY)
footer.BackgroundColor3 = C_FOOT
footer.BorderSizePixel  = 0
footer.ZIndex           = 11

local dot = Instance.new("Frame", footer)
dot.AnchorPoint      = Vector2.new(0, 0.5)
dot.Position         = UDim2.new(0, PAD, 0.5, 0)
dot.Size             = UDim2.new(0, 8, 0, 8)
dot.BackgroundColor3 = C_DIM
dot.BorderSizePixel  = 0
dot.ZIndex           = 12
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

local statusLabel = Instance.new("TextLabel", footer)
statusLabel.Size               = UDim2.new(0, 200, 1, 0)
statusLabel.Position           = UDim2.new(0, PAD + 14, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Font               = Enum.Font.Gotham
statusLabel.TextSize           = 12
statusLabel.TextColor3         = C_DIM
statusLabel.TextXAlignment     = Enum.TextXAlignment.Left
statusLabel.TextYAlignment     = Enum.TextYAlignment.Center
statusLabel.Text               = "Active: None"
statusLabel.ZIndex             = 12

local BW = 88

local resetBtn = Instance.new("TextButton", footer)
resetBtn.AnchorPoint        = Vector2.new(1, 0.5)
resetBtn.Position           = UDim2.new(1, -(PAD + BW + 6), 0.5, 0)
resetBtn.Size               = UDim2.new(0, BW, 0, 30)
resetBtn.BackgroundColor3   = Color3.fromRGB(25, 35, 58)
resetBtn.BackgroundTransparency = 0.25
resetBtn.Font               = Enum.Font.Gotham
resetBtn.TextSize           = 11
resetBtn.TextColor3         = C_ACC
resetBtn.Text               = "Reset"
resetBtn.AutoButtonColor    = false
resetBtn.ZIndex             = 12
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)
do
	local s = Instance.new("UIStroke", resetBtn)
	s.Color = C_BOR; s.Thickness = 1; s.Transparency = 0.45
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local closeFooter = Instance.new("TextButton", footer)
closeFooter.AnchorPoint        = Vector2.new(1, 0.5)
closeFooter.Position           = UDim2.new(1, -PAD, 0.5, 0)
closeFooter.Size               = UDim2.new(0, BW, 0, 30)
closeFooter.BackgroundColor3   = Color3.fromRGB(42, 18, 18)
closeFooter.BackgroundTransparency = 0.25
closeFooter.Font               = Enum.Font.Gotham
closeFooter.TextSize           = 11
closeFooter.TextColor3         = Color3.fromRGB(210, 85, 85)
closeFooter.Text               = "Close"
closeFooter.AutoButtonColor    = false
closeFooter.ZIndex             = 12
Instance.new("UICorner", closeFooter).CornerRadius = UDim.new(0, 6)
do
	local s = Instance.new("UIStroke", closeFooter)
	s.Color = Color3.fromRGB(110, 50, 50); s.Thickness = 1; s.Transparency = 0.45
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- ── Global drag handler (one connection shared by all sliders) ────────────────
UserInputService.InputChanged:Connect(function(input)
	if not activeSliderFn then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		activeSliderFn(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		activeSliderFn = nil
	end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function makeThrottle(interval)
	local last = 0
	return function(fn, ...)
		local now = tick()
		if now - last >= interval then
			last = now
			fn(...)
		end
	end
end

-- Monotonically increasing LayoutOrder so UIListLayout stacks correctly
local layoutOrder = 0
local function nextOrder()
	layoutOrder += 1
	return layoutOrder
end

-- Section header row
local function makeSection(parent, title)
	local f = Instance.new("Frame", parent)
	f.Name             = "Sec_" .. title
	f.Size             = UDim2.new(1, 0, 0, SEC_H)
	f.BackgroundColor3 = C_SEC
	f.BackgroundTransparency = 0.3
	f.BorderSizePixel  = 0
	f.LayoutOrder      = nextOrder()
	f.ZIndex           = 12
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)

	local lbl = Instance.new("TextLabel", f)
	lbl.Size               = UDim2.new(1, -PAD, 1, 0)
	lbl.Position           = UDim2.new(0, PAD, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font               = Enum.Font.GothamBold
	lbl.TextSize           = 11
	lbl.TextColor3         = C_ACC
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.TextYAlignment     = Enum.TextYAlignment.Center
	lbl.Text               = string.upper(title)
	lbl.ZIndex             = 13
end

-- Horizontal slider.  Returns setValue(number) to update the thumb externally.
-- onChanged(value) is throttled to 60ms while dragging.
local function makeSlider(parent, label, minVal, maxVal, default, decimals, onChanged)
	decimals = decimals or 2
	local fmt = "%." .. decimals .. "f"

	local row = Instance.new("Frame", parent)
	row.Name             = "Slider_" .. label
	row.Size             = UDim2.new(1, 0, 0, SLI_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel  = 0
	row.LayoutOrder      = nextOrder()
	row.ZIndex           = 12

	local lbl = Instance.new("TextLabel", row)
	lbl.Size               = UDim2.new(0.62, 0, 0, 20)
	lbl.Position           = UDim2.new(0, 0, 0, 2)
	lbl.BackgroundTransparency = 1
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 12
	lbl.TextColor3         = C_TXT
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.Text               = label
	lbl.ZIndex             = 13

	local valLbl = Instance.new("TextLabel", row)
	valLbl.Size               = UDim2.new(0.38, 0, 0, 20)
	valLbl.Position           = UDim2.new(0.62, 0, 0, 2)
	valLbl.BackgroundTransparency = 1
	valLbl.Font               = Enum.Font.GothamMedium
	valLbl.TextSize           = 12
	valLbl.TextColor3         = C_ACC
	valLbl.TextXAlignment     = Enum.TextXAlignment.Right
	valLbl.Text               = string.format(fmt, default)
	valLbl.ZIndex             = 13

	local track = Instance.new("Frame", row)
	track.Size             = UDim2.new(1, 0, 0, 4)
	track.Position         = UDim2.new(0, 0, 0, 30)
	track.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
	track.BorderSizePixel  = 0
	track.ZIndex           = 12
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame", track)
	fill.Size             = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = C_ACT
	fill.BorderSizePixel  = 0
	fill.ZIndex           = 13
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local thumb = Instance.new("TextButton", track)
	thumb.Size             = UDim2.new(0, THUMB_S, 0, THUMB_S)
	thumb.AnchorPoint      = Vector2.new(0.5, 0.5)
	thumb.Position         = UDim2.new(0, 0, 0.5, 0)
	thumb.BackgroundColor3 = Color3.new(1, 1, 1)
	thumb.Text             = ""
	thumb.AutoButtonColor  = false
	thumb.BorderSizePixel  = 0
	thumb.ZIndex           = 14
	Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

	local throttle = makeThrottle(0.06)

	local function applyPosX(posX)
		local abs = track.AbsolutePosition
		local sz  = track.AbsoluteSize
		if sz.X == 0 then return end
		local ratio = math.clamp((posX - abs.X) / sz.X, 0, 1)
		local raw   = minVal + ratio * (maxVal - minVal)
		local mult  = 10 ^ decimals
		local val   = math.round(raw * mult) / mult
		fill.Size      = UDim2.new(ratio, 0, 1, 0)
		thumb.Position = UDim2.new(ratio, 0, 0.5, 0)
		valLbl.Text    = string.format(fmt, val)
		throttle(onChanged, val)
	end

	thumb.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeSliderFn = applyPosX
		end
	end)

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeSliderFn = applyPosX
			applyPosX(input.Position.X)
		end
	end)

	-- Set initial thumb position
	local initRatio = math.clamp((default - minVal) / (maxVal - minVal), 0, 1)
	fill.Size      = UDim2.new(initRatio, 0, 1, 0)
	thumb.Position = UDim2.new(initRatio, 0, 0.5, 0)

	local function setValue(val)
		local ratio = math.clamp((val - minVal) / (maxVal - minVal), 0, 1)
		fill.Size      = UDim2.new(ratio, 0, 1, 0)
		thumb.Position = UDim2.new(ratio, 0, 0.5, 0)
		valLbl.Text    = string.format(fmt, val)
	end

	return row, setValue
end

-- Pill toggle.  Returns setState(bool) to set externally.
local PILL_W, PILL_H = 40, 20

local function makeToggle(parent, label, default, onChanged)
	local row = Instance.new("Frame", parent)
	row.Name             = "Toggle_" .. label
	row.Size             = UDim2.new(1, 0, 0, TOG_H)
	row.BackgroundTransparency = 1
	row.BorderSizePixel  = 0
	row.LayoutOrder      = nextOrder()
	row.ZIndex           = 12

	local lbl = Instance.new("TextLabel", row)
	lbl.Size               = UDim2.new(1, -(PILL_W + 8), 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 12
	lbl.TextColor3         = C_TXT
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.TextYAlignment     = Enum.TextYAlignment.Center
	lbl.Text               = label
	lbl.ZIndex             = 13

	local pill = Instance.new("TextButton", row)
	pill.AnchorPoint      = Vector2.new(1, 0.5)
	pill.Position         = UDim2.new(1, 0, 0.5, 0)
	pill.Size             = UDim2.new(0, PILL_W, 0, PILL_H)
	pill.BackgroundColor3 = default and C_ACT or Color3.fromRGB(35, 35, 55)
	pill.BorderSizePixel  = 0
	pill.Text             = ""
	pill.AutoButtonColor  = false
	pill.ZIndex           = 13
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame", pill)
	knob.Size             = UDim2.new(0, PILL_H - 4, 0, PILL_H - 4)
	knob.AnchorPoint      = Vector2.new(0.5, 0.5)
	knob.Position         = default
		and UDim2.new(1, -(PILL_H / 2), 0.5, 0)
		or  UDim2.new(0,  PILL_H / 2,  0.5, 0)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel  = 0
	knob.ZIndex           = 14
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local state  = default
	local tweenI = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function setState(val)
		state = val
		TweenService:Create(pill, tweenI, {
			BackgroundColor3 = val and C_ACT or Color3.fromRGB(35, 35, 55),
		}):Play()
		TweenService:Create(knob, tweenI, {
			Position = val
				and UDim2.new(1, -(PILL_H / 2), 0.5, 0)
				or  UDim2.new(0,  PILL_H / 2,  0.5, 0),
		}):Play()
	end

	pill.MouseButton1Click:Connect(function()
		setState(not state)
		onChanged(state)
	end)

	return row, setState
end

-- Compact RGB color picker (label row + three channel slider rows).
-- Returns setValue(Color3) to update from outside.
local function makeColorPicker(parent, label, defaultColor, onChanged)
	local totalH = 22 + 3 * CH_H + 6

	local container = Instance.new("Frame", parent)
	container.Name             = "Color_" .. label
	container.Size             = UDim2.new(1, 0, 0, totalH)
	container.BackgroundTransparency = 1
	container.BorderSizePixel  = 0
	container.LayoutOrder      = nextOrder()
	container.ZIndex           = 12

	-- header: label + preview swatch
	local hRow = Instance.new("Frame", container)
	hRow.Size             = UDim2.new(1, 0, 0, 22)
	hRow.Position         = UDim2.new(0, 0, 0, 0)
	hRow.BackgroundTransparency = 1
	hRow.ZIndex           = 12

	local hLbl = Instance.new("TextLabel", hRow)
	hLbl.Size               = UDim2.new(1, -34, 1, 0)
	hLbl.BackgroundTransparency = 1
	hLbl.Font               = Enum.Font.Gotham
	hLbl.TextSize           = 12
	hLbl.TextColor3         = C_TXT
	hLbl.TextXAlignment     = Enum.TextXAlignment.Left
	hLbl.TextYAlignment     = Enum.TextYAlignment.Center
	hLbl.Text               = label
	hLbl.ZIndex             = 13

	local swatch = Instance.new("Frame", hRow)
	swatch.AnchorPoint      = Vector2.new(1, 0.5)
	swatch.Position         = UDim2.new(1, 0, 0.5, 0)
	swatch.Size             = UDim2.new(0, 28, 0, 16)
	swatch.BackgroundColor3 = defaultColor
	swatch.BorderSizePixel  = 0
	swatch.ZIndex           = 13
	Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 4)
	do
		local ss = Instance.new("UIStroke", swatch)
		ss.Color = C_BOR; ss.Thickness = 1; ss.Transparency = 0.4
		ss.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end

	-- mutable channel values (0–255)
	local rv = defaultColor.R * 255
	local gv = defaultColor.G * 255
	local bv = defaultColor.B * 255

	local function rebuild()
		local col = Color3.fromRGB(math.round(rv), math.round(gv), math.round(bv))
		swatch.BackgroundColor3 = col
		onChanged(col)
	end

	local channelDefs = {
		{ key = "R", barColor = Color3.fromRGB(220,  75,  75), getVal = function() return rv end, setVal = function(v) rv = v end },
		{ key = "G", barColor = Color3.fromRGB( 70, 200,  70), getVal = function() return gv end, setVal = function(v) gv = v end },
		{ key = "B", barColor = Color3.fromRGB( 80, 130, 255), getVal = function() return bv end, setVal = function(v) bv = v end },
	}

	local channelSetters = {}

	for i, ch in ipairs(channelDefs) do
		-- Defensively localize per iteration so closures below capture the
		-- correct channel (not a shared upvalue that may shift in future Luau).
		local channel = ch
		local yOff = 22 + (i - 1) * CH_H + 2

		local cRow = Instance.new("Frame", container)
		cRow.Size             = UDim2.new(1, 0, 0, CH_H - 2)
		cRow.Position         = UDim2.new(0, 0, 0, yOff)
		cRow.BackgroundTransparency = 1
		cRow.ZIndex           = 12

		local cLbl = Instance.new("TextLabel", cRow)
		cLbl.Size               = UDim2.new(0, 14, 1, 0)
		cLbl.BackgroundTransparency = 1
		cLbl.Font               = Enum.Font.GothamBold
		cLbl.TextSize           = 10
		cLbl.TextColor3         = channel.barColor
		cLbl.TextXAlignment     = Enum.TextXAlignment.Center
		cLbl.Text               = channel.key
		cLbl.ZIndex             = 13

		local cTrack = Instance.new("Frame", cRow)
		cTrack.Size             = UDim2.new(1, -58, 0, 4)
		cTrack.Position         = UDim2.new(0, 18, 0.5, -2)
		cTrack.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
		cTrack.BorderSizePixel  = 0
		cTrack.ZIndex           = 13
		Instance.new("UICorner", cTrack).CornerRadius = UDim.new(1, 0)

		local initR = channel.getVal() / 255
		local cFill = Instance.new("Frame", cTrack)
		cFill.Size             = UDim2.new(initR, 0, 1, 0)
		cFill.BackgroundColor3 = channel.barColor
		cFill.BorderSizePixel  = 0
		cFill.ZIndex           = 14
		Instance.new("UICorner", cFill).CornerRadius = UDim.new(1, 0)

		local cThumb = Instance.new("TextButton", cTrack)
		cThumb.Size             = UDim2.new(0, 12, 0, 12)
		cThumb.AnchorPoint      = Vector2.new(0.5, 0.5)
		cThumb.Position         = UDim2.new(initR, 0, 0.5, 0)
		cThumb.BackgroundColor3 = Color3.new(1, 1, 1)
		cThumb.Text             = ""
		cThumb.AutoButtonColor  = false
		cThumb.BorderSizePixel  = 0
		cThumb.ZIndex           = 15
		Instance.new("UICorner", cThumb).CornerRadius = UDim.new(1, 0)

		local cValLbl = Instance.new("TextLabel", cRow)
		cValLbl.AnchorPoint      = Vector2.new(1, 0.5)
		cValLbl.Position         = UDim2.new(1, 0, 0.5, 0)
		cValLbl.Size             = UDim2.new(0, 34, 1, 0)
		cValLbl.BackgroundTransparency = 1
		cValLbl.Font             = Enum.Font.GothamMedium
		cValLbl.TextSize         = 10
		cValLbl.TextColor3       = C_ACC
		cValLbl.TextXAlignment   = Enum.TextXAlignment.Right
		cValLbl.Text             = tostring(math.round(channel.getVal()))
		cValLbl.ZIndex           = 13

		local throttleC = makeThrottle(0.06)

		local function applyChannelX(posX)
			local abs = cTrack.AbsolutePosition
			local sz  = cTrack.AbsoluteSize
			if sz.X == 0 then return end
			local ratio = math.clamp((posX - abs.X) / sz.X, 0, 1)
			local val   = math.round(ratio * 255)
			cFill.Size      = UDim2.new(ratio, 0, 1, 0)
			cThumb.Position = UDim2.new(ratio, 0, 0.5, 0)
			cValLbl.Text    = tostring(val)
			channel.setVal(val)
			throttleC(rebuild)
		end

		cThumb.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				activeSliderFn = applyChannelX
			end
		end)

		cTrack.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				activeSliderFn = applyChannelX
				applyChannelX(input.Position.X)
			end
		end)

		-- External setter for this channel
		channelSetters[i] = function(val)
			local ratio = math.clamp(val / 255, 0, 1)
			cFill.Size      = UDim2.new(ratio, 0, 1, 0)
			cThumb.Position = UDim2.new(ratio, 0, 0.5, 0)
			cValLbl.Text    = tostring(math.round(val))
			channel.setVal(val)
		end
	end

	-- External setter: update all channels + swatch from a Color3
	local function setValue(color)
		channelSetters[1](color.R * 255)
		channelSetters[2](color.G * 255)
		channelSetters[3](color.B * 255)
		swatch.BackgroundColor3 = color
	end

	return container, setValue
end

-- ── Tab: Weather ──────────────────────────────────────────────────────────────
local function buildWeatherTab()
	local sf = tabContent["Weather"]

	makeSection(sf, "Presets")

	for _, name in ipairs(WEATHER_ORDER) do
		local btn = Instance.new("TextButton", sf)
		btn.Name                  = name
		btn.LayoutOrder           = nextOrder()
		btn.Size                  = UDim2.new(1, 0, 0, BTN_H)
		btn.BackgroundColor3      = C_BTN
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel       = 0
		btn.AutoButtonColor       = false
		btn.Text                  = ""
		btn.ZIndex                = 12
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

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

		local n = name  -- capture for closure
		btn.MouseEnter:Connect(function()
			if n ~= currentWeather then btn.BackgroundTransparency = 0.78 end
		end)
		btn.MouseLeave:Connect(function()
			if n ~= currentWeather then btn.BackgroundTransparency = 1 end
		end)
		btn.MouseButton1Click:Connect(function()
			CommandRemotes.WeatherApply:FireServer(n)
		end)
	end

	makeSection(sf, "Live Adjustments")

	-- These sliders tune the currently active weather in real time.
	makeSlider(sf, "Particle Intensity (Rate)", 0, 1000, 350, 0, function(v)
		CommandRemotes.WeatherSetProp:FireServer("Particles", "Rate", v)
	end)

	makeSlider(sf, "Particle Speed", 0, 120, 55, 0, function(v)
		CommandRemotes.WeatherSetProp:FireServer("Particles", "Speed", v)
	end)

	makeSlider(sf, "Ambient Sound Volume", 0, 1, 0.5, 2, function(v)
		CommandRemotes.WeatherSetProp:FireServer("Sound", "Volume", v)
	end)

	makeSlider(sf, "Atmosphere Density", 0, 1, 0.3, 2, function(v)
		CommandRemotes.WeatherSetProp:FireServer("Atmosphere", "Density", v)
	end)

	makeSection(sf, "Particles")

	makeToggle(sf, "Rain Particles", false, function(enabled)
		CommandRemotes.WeatherToggleEffect:FireServer("RainParticles", enabled)
	end)

	makeSlider(sf, "Rain Amount", 100, 5000, 1500, 0, function(v)
		CommandRemotes.WeatherSetProp:FireServer("RainLocal", "Rate", v)
	end)
end

-- ── Tab: Lighting ─────────────────────────────────────────────────────────────
local function buildLightingTab()
	local sf = tabContent["Lighting"]

	makeSection(sf, "Time & Brightness")

	local _, setClockTime = makeSlider(sf, "Clock Time (0–24 h)", 0, 24,
		Lighting.ClockTime, 1, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Lighting", "ClockTime", v)
		end)
	table.insert(refreshFns, function() setClockTime(Lighting.ClockTime) end)

	local _, setBrightness = makeSlider(sf, "Brightness", 0, 10,
		Lighting.Brightness, 2, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Lighting", "Brightness", v)
		end)
	table.insert(refreshFns, function() setBrightness(Lighting.Brightness) end)

	local _, setExposure = makeSlider(sf, "Exposure Compensation", -5, 5,
		Lighting.ExposureCompensation, 2, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Lighting", "ExposureCompensation", v)
		end)
	table.insert(refreshFns, function() setExposure(Lighting.ExposureCompensation) end)

	local _, setShadow = makeSlider(sf, "Shadow Softness", 0, 1,
		Lighting.ShadowSoftness, 2, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Lighting", "ShadowSoftness", v)
		end)
	table.insert(refreshFns, function() setShadow(Lighting.ShadowSoftness) end)

	local _, setLat = makeSlider(sf, "Geographic Latitude", -90, 90,
		Lighting.GeographicLatitude, 1, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Lighting", "GeographicLatitude", v)
		end)
	table.insert(refreshFns, function() setLat(Lighting.GeographicLatitude) end)

	local _, setFogEnd = makeSlider(sf, "Fog End Distance", 0, 100000,
		Lighting.FogEnd, 0, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Lighting", "FogEnd", v)
		end)
	table.insert(refreshFns, function() setFogEnd(Lighting.FogEnd) end)

	local _, setFogStart = makeSlider(sf, "Fog Start Distance", 0, 10000,
		Lighting.FogStart, 0, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Lighting", "FogStart", v)
		end)
	table.insert(refreshFns, function() setFogStart(Lighting.FogStart) end)

	makeSection(sf, "Ambient Colors")

	local _, setAmbient = makeColorPicker(sf, "Ambient", Lighting.Ambient, function(c)
		CommandRemotes.WeatherSetProp:FireServer("Lighting", "Ambient", c)
	end)
	table.insert(refreshFns, function() setAmbient(Lighting.Ambient) end)

	local _, setOutdoor = makeColorPicker(sf, "Outdoor Ambient", Lighting.OutdoorAmbient, function(c)
		CommandRemotes.WeatherSetProp:FireServer("Lighting", "OutdoorAmbient", c)
	end)
	table.insert(refreshFns, function() setOutdoor(Lighting.OutdoorAmbient) end)

	local _, setFogColor = makeColorPicker(sf, "Fog Color", Lighting.FogColor, function(c)
		CommandRemotes.WeatherSetProp:FireServer("Lighting", "FogColor", c)
	end)
	table.insert(refreshFns, function() setFogColor(Lighting.FogColor) end)
end

-- ── Tab: Atmosphere ───────────────────────────────────────────────────────────
local function buildAtmosphereTab()
	local sf  = tabContent["Atmosphere"]
	local atm = atmosphere

	makeSection(sf, "Scattering")

	local _, setDens = makeSlider(sf, "Density", 0, 1,
		atm and atm.Density or 0.3, 2, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Atmosphere", "Density", v)
		end)
	table.insert(refreshFns, function()
		if atmosphere then setDens(atmosphere.Density) end
	end)

	local _, setOffset = makeSlider(sf, "Offset", 0, 1,
		atm and atm.Offset or 0.25, 2, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Atmosphere", "Offset", v)
		end)
	table.insert(refreshFns, function()
		if atmosphere then setOffset(atmosphere.Offset) end
	end)

	local _, setHaze = makeSlider(sf, "Haze", 0, 100,
		atm and atm.Haze or 0, 1, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Atmosphere", "Haze", v)
		end)
	table.insert(refreshFns, function()
		if atmosphere then setHaze(atmosphere.Haze) end
	end)

	local _, setGlare = makeSlider(sf, "Glare", 0, 10,
		atm and atm.Glare or 0, 2, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Atmosphere", "Glare", v)
		end)
	table.insert(refreshFns, function()
		if atmosphere then setGlare(atmosphere.Glare) end
	end)

	makeSection(sf, "Colors")

	local _, setAtmColor = makeColorPicker(sf, "Color",
		atm and atm.Color or Color3.fromRGB(199, 199, 199), function(c)
			CommandRemotes.WeatherSetProp:FireServer("Atmosphere", "Color", c)
		end)
	table.insert(refreshFns, function()
		if atmosphere then setAtmColor(atmosphere.Color) end
	end)

	local _, setAtmDecay = makeColorPicker(sf, "Decay",
		atm and atm.Decay or Color3.fromRGB(106, 127, 139), function(c)
			CommandRemotes.WeatherSetProp:FireServer("Atmosphere", "Decay", c)
		end)
	table.insert(refreshFns, function()
		if atmosphere then setAtmDecay(atmosphere.Decay) end
	end)
end

-- ── Tab: Clouds ───────────────────────────────────────────────────────────────
local function buildCloudsTab()
	local sf = tabContent["Clouds"]

	makeSection(sf, "Cloud Settings")

	local _, setCover = makeSlider(sf, "Cover", 0, 1,
		clouds and clouds.Cover or 0.5, 2, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Clouds", "Cover", v)
		end)
	table.insert(refreshFns, function()
		if clouds then setCover(clouds.Cover) end
	end)

	local _, setClDens = makeSlider(sf, "Density", 0, 1,
		clouds and clouds.Density or 0.5, 2, function(v)
			CommandRemotes.WeatherSetProp:FireServer("Clouds", "Density", v)
		end)
	table.insert(refreshFns, function()
		if clouds then setClDens(clouds.Density) end
	end)

	makeSection(sf, "Cloud Color")

	local _, setClColor = makeColorPicker(sf, "Color",
		clouds and clouds.Color or Color3.fromRGB(235, 235, 235), function(c)
			CommandRemotes.WeatherSetProp:FireServer("Clouds", "Color", c)
		end)
	table.insert(refreshFns, function()
		if clouds then setClColor(clouds.Color) end
	end)
end

-- ── Tab: Environment ──────────────────────────────────────────────────────────
local function buildEnvironmentTab()
	local sf = tabContent["Environment"]

	makeSection(sf, "Post-Processing Effects")

	local effectDefs = {
		{ label = "Sun Rays",         class = "SunRaysEffect"        },
		{ label = "Bloom",            class = "BloomEffect"           },
		{ label = "Color Correction", class = "ColorCorrectionEffect" },
		{ label = "Depth of Field",   class = "DepthOfFieldEffect"    },
	}

	for _, eff in ipairs(effectDefs) do
		local existing = Lighting:FindFirstChildOfClass(eff.class)
		local isOn = existing ~= nil and existing.Enabled ~= false
		local cls  = eff.class
		local _, setToggle = makeToggle(sf, eff.label, isOn, function(enabled)
			CommandRemotes.WeatherToggleEffect:FireServer(cls, enabled)
		end)
		table.insert(refreshFns, function()
			local e = Lighting:FindFirstChildOfClass(cls)
			setToggle(e ~= nil and e.Enabled ~= false)
		end)
	end

	makeSection(sf, "World")

	local atmOn = atmosphere ~= nil and (atmosphere.Density or 0) > 0.001
	local _, setAtmToggle = makeToggle(sf, "Atmosphere Scattering", atmOn, function(enabled)
		CommandRemotes.WeatherToggleEffect:FireServer("Atmosphere", enabled)
	end)
	table.insert(refreshFns, function()
		setAtmToggle(atmosphere ~= nil and (atmosphere.Density or 0) > 0.001)
	end)

	local cloudsOn = clouds ~= nil and (clouds.Cover or 0) > 0.001
	local _, setCloudsToggle = makeToggle(sf, "Clouds", cloudsOn, function(enabled)
		CommandRemotes.WeatherToggleEffect:FireServer("Clouds", enabled)
	end)
	table.insert(refreshFns, function()
		setCloudsToggle(clouds ~= nil and (clouds.Cover or 0) > 0.001)
	end)
end

-- ── Build all tab content ─────────────────────────────────────────────────────
buildWeatherTab()
buildLightingTab()
buildAtmosphereTab()
buildCloudsTab()
buildEnvironmentTab()

-- ── Tab switching ─────────────────────────────────────────────────────────────
local function switchTab(name)
	activeTab = name
	for tName, btn in pairs(tabBtns) do
		local on = (tName == name)
		btn.TextColor3 = on and C_TXT or C_DIM
		btn.Font       = on and Enum.Font.GothamBold or Enum.Font.Gotham
	end
	for tName, sf in pairs(tabContent) do
		sf.Visible = (tName == name)
	end
end

for _, tabName in ipairs(TABS) do
	local n = tabName
	tabBtns[tabName].MouseButton1Click:Connect(function()
		switchTab(n)
	end)
end

-- ── Draggable header ──────────────────────────────────────────────────────────
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
	isOpen         = true
	activeSliderFn = nil  -- clear any stale drag state from before close
	sg.Enabled     = true
	uiScale.Scale  = 0.90
	TweenService:Create(uiScale, openInfo, { Scale = 1 }):Play()
	-- Sync all sliders to current world state so values are accurate on open
	for _, fn in ipairs(refreshFns) do pcall(fn) end
	-- Default to Weather tab on first open
	if not activeTab then switchTab("Weather") end
end

local function closeMenu()
	if not isOpen then return end
	isOpen         = false
	activeSliderFn = nil  -- release any in-progress drag immediately
	local t = TweenService:Create(uiScale, closeInfo, { Scale = 0.90 })
	t:Play()
	t.Completed:Connect(function()
		if not isOpen then sg.Enabled = false end
	end)
end

-- ── Active weather highlight ──────────────────────────────────────────────────
local function updateHighlight(name)
	currentWeather       = (name ~= "" and name) or nil
	statusLabel.Text     = "Active: " .. (currentWeather or "None")
	dot.BackgroundColor3 = currentWeather and C_ACT or C_DIM

	for wName, refs in pairs(weatherButtons) do
		local active = (wName == currentWeather)
		refs.frame.BackgroundTransparency = active and 0.60 or 1
		refs.frame.BackgroundColor3       = active and Color3.fromRGB(22, 32, 58) or C_BTN
		refs.accent.BackgroundColor3      = active and C_ACT or C_DIM
		refs.label.TextColor3             = active and Color3.new(1, 1, 1) or C_TXT
	end
end

-- ── Quote key toggles the weather menu ───────────────────────────────────────
UserInputService.InputBegan:Connect(function(inp, gp)
	if inp.KeyCode == Enum.KeyCode.Quote and not gp then
		if isOpen then closeMenu() else openMenu() end
	end
end)

-- ── Button connections ────────────────────────────────────────────────────────
closeFooter.MouseButton1Click:Connect(closeMenu)

resetBtn.MouseButton1Click:Connect(function()
	CommandRemotes.WeatherReset:FireServer()
end)

-- ── Client-side rain particles (anchored part that tracks the camera) ─────────
-- Follows the camera via RenderStepped — no welds, no character dependency.
local rainEnabled  = false
local rainRate     = 1500
local rainPart     = nil   -- the anchored emitter Part in Workspace
local rainStepConn = nil   -- RenderStepped connection

local function detachRain()
	if rainStepConn then rainStepConn:Disconnect(); rainStepConn = nil end
	if rainPart     then rainPart:Destroy();        rainPart     = nil end
end

local function attachRain()
	detachRain()
	if not rainEnabled then return end

	local part = Instance.new("Part")
	part.Name         = "RainEmitter"
	part.Size         = Vector3.new(40, 1, 40)
	part.Anchored     = true
	part.CanCollide   = false
	part.Transparency = 1
	part.CastShadow   = false
	part.Parent       = Workspace

	local pe = Instance.new("ParticleEmitter")
	pe.Color             = ColorSequence.new(Color3.fromRGB(170, 210, 255))
	pe.Size              = NumberSequence.new(0.06)
	pe.Transparency      = NumberSequence.new(0.4)
	pe.Speed             = NumberRange.new(40, 55)
	pe.Rotation          = NumberRange.new(90, 90)
	pe.RotSpeed          = NumberRange.new(0, 0)
	pe.Rate              = rainRate
	pe.Lifetime          = NumberRange.new(0.8, 1.2)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.LightInfluence    = 1
	pe.LightEmission     = 0
	pe.Parent            = part

	rainPart = part

	-- Move the part directly above the camera every frame
	rainStepConn = RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			local p = cam.CFrame.Position
			part.CFrame = CFrame.new(p.X, p.Y + 20, p.Z)
		end
	end)
end

-- ── Remote connections ────────────────────────────────────────────────────────
CommandRemotes.WeatherOpen.OnClientEvent:Connect(function()
	if isOpen then closeMenu() else openMenu() end
end)

CommandRemotes.WeatherSync.OnClientEvent:Connect(function(weatherName)
	if typeof(weatherName) == "string" then
		updateHighlight(weatherName)
	end
end)

CommandRemotes.WeatherClientEffect.OnClientEvent:Connect(function(effectName, value)
	if effectName == "RainParticles" then
		rainEnabled = value
		if value then attachRain() else detachRain() end
	elseif effectName == "RainRate" then
		rainRate = value
		if rainPart then
			local pe = rainPart:FindFirstChildOfClass("ParticleEmitter")
			if pe then pe.Rate = rainRate end
		end
	end
end)

-- ── Init: seed highlight + tab from authoritative StringValue ─────────────────
if activeWeatherValue then
	local initial = activeWeatherValue.Value
	if initial ~= "" then updateHighlight(initial) end
end
