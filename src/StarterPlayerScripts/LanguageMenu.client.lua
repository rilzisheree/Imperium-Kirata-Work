--[[
	LanguageMenu.client.lua
	LocalScript — StarterPlayerScripts

	Provides two things:

	1. Language Indicator — persistent plain-text label in the top-right corner.
	   Font: Merriweather, matching the existing SM/IM style (CommandEffects).
	   Shows "Language: English" by default; updates whenever the player changes.

	2. Language Menu — small draggable window listing the player's granted
	   languages plus a "None" option that returns them to English.
	   Opened by the `language` command (server fires LanguageOpen remote).
	   Visual palette matches CommandBar / WeatherMenu (dark, consistent).
--]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

-- ── Palette (matches CommandBar / WeatherMenu) ────────────────────────────────
local C_BG   = Color3.fromRGB(12,  12,  18)
local C_BOR  = Color3.fromRGB(90,  90, 120)
local C_TXT  = Color3.fromRGB(235, 235, 252)
local C_DIM  = Color3.fromRGB(80,  80, 100)
local C_ACC  = Color3.fromRGB(160, 160, 210)
local C_HEAD = Color3.fromRGB(16,  16,  26)
local C_BTN  = Color3.fromRGB(20,  20,  34)
local C_SEL  = Color3.fromRGB(28,  28,  50)
local C_HOV  = Color3.fromRGB(255, 255, 255)

-- ── State ─────────────────────────────────────────────────────────────────────
local grantedLanguages = {}   -- { "Korean", "Japanese", ... } from server
local selectedLanguage = nil  -- string or nil (nil = English)

-- ── Root ScreenGui ────────────────────────────────────────────────────────────
local sg = Instance.new("ScreenGui")
sg.Name           = "LanguageGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = false
sg.DisplayOrder   = 102
sg.Parent         = PGui

-- ════════════════════════════════════════════════════════════════════════════
-- 1.  LANGUAGE INDICATOR
--     Plain text, top-right corner, Merriweather to match SM/IM.
-- ════════════════════════════════════════════════════════════════════════════

local indicator = Instance.new("TextLabel", sg)
indicator.Name                   = "LanguageIndicator"
indicator.AnchorPoint            = Vector2.new(1, 0)
indicator.Position               = UDim2.new(1, -14, 0, 14)
indicator.Size                   = UDim2.new(0, 240, 0, 26)
indicator.BackgroundTransparency = 1
indicator.Font                   = Enum.Font.Merriweather
indicator.TextSize               = 18
indicator.TextColor3             = Color3.new(1, 1, 1)
indicator.TextXAlignment         = Enum.TextXAlignment.Right
indicator.TextYAlignment         = Enum.TextYAlignment.Center
indicator.Text                   = "Language: English"
indicator.ZIndex                 = 5

local function updateIndicator()
	indicator.Text = "Language: " .. (selectedLanguage or "English")
end

-- ════════════════════════════════════════════════════════════════════════════
-- 2.  LANGUAGE MENU
-- ════════════════════════════════════════════════════════════════════════════

local MENU_W  = 240
local HDR_H   = 38
local BTN_H   = 34
local LST_PAD = 6   -- vertical padding inside the button list

-- Main window frame
local menuFrame = Instance.new("Frame", sg)
menuFrame.Name             = "LanguageMenuFrame"
menuFrame.AnchorPoint      = Vector2.new(0.5, 0.5)
menuFrame.Position         = UDim2.new(0.5, 0, 0.5, 0)
menuFrame.Size             = UDim2.new(0, MENU_W, 0, 0)
menuFrame.AutomaticSize    = Enum.AutomaticSize.Y
menuFrame.BackgroundColor3 = C_BG
menuFrame.BorderSizePixel  = 0
menuFrame.ClipsDescendants = true   -- clips header bg into the rounded corners
menuFrame.Visible          = false
menuFrame.ZIndex           = 20
Instance.new("UICorner", menuFrame).CornerRadius = UDim.new(0, 10)
do
	local s = Instance.new("UIStroke", menuFrame)
	s.Color = C_BOR; s.Thickness = 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- Header (drag handle + title + close)
local header = Instance.new("Frame", menuFrame)
header.Name             = "Header"
header.Size             = UDim2.new(1, 0, 0, HDR_H)
header.BackgroundColor3 = C_HEAD
header.BorderSizePixel  = 0
header.ZIndex           = 21

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size               = UDim2.new(1, -46, 1, 0)
titleLbl.Position           = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 13
titleLbl.TextColor3         = C_TXT
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.TextYAlignment     = Enum.TextYAlignment.Center
titleLbl.Text               = "Language Selection"
titleLbl.ZIndex             = 22

local closeBtn = Instance.new("TextButton", header)
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
closeBtn.ZIndex                 = 22
closeBtn.MouseEnter:Connect(function() closeBtn.TextColor3 = C_HOV end)
closeBtn.MouseLeave:Connect(function() closeBtn.TextColor3 = C_DIM end)

-- Divider between header and button list
local divider = Instance.new("Frame", menuFrame)
divider.Position               = UDim2.new(0, 0, 0, HDR_H)
divider.Size                   = UDim2.new(1, 0, 0, 1)
divider.BackgroundColor3       = C_BOR
divider.BackgroundTransparency = 0.5
divider.BorderSizePixel        = 0
divider.ZIndex                 = 21

-- Button list container
local listFrame = Instance.new("Frame", menuFrame)
listFrame.Position       = UDim2.new(0, 0, 0, HDR_H + 1)
listFrame.Size           = UDim2.new(1, 0, 0, 0)
listFrame.AutomaticSize  = Enum.AutomaticSize.Y
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.ZIndex          = 21

local listLayout = Instance.new("UIListLayout", listFrame)
listLayout.FillDirection       = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.SortOrder           = Enum.SortOrder.LayoutOrder
listLayout.Padding             = UDim.new(0, 0)

local listPad = Instance.new("UIPadding", listFrame)
listPad.PaddingTop    = UDim.new(0, LST_PAD)
listPad.PaddingBottom = UDim.new(0, LST_PAD)

-- ── Drag logic ────────────────────────────────────────────────────────────────

local isDragging = false
local dragStart  = Vector2.zero
local frameStart = UDim2.new()

header.InputBegan:Connect(function(inp)
	if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	isDragging = true
	dragStart  = Vector2.new(inp.Position.X, inp.Position.Y)
	frameStart = menuFrame.Position
end)

UserInputService.InputChanged:Connect(function(inp)
	if not isDragging then return end
	if inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	local d = Vector2.new(inp.Position.X, inp.Position.Y) - dragStart
	menuFrame.Position = UDim2.new(
		frameStart.X.Scale, frameStart.X.Offset + d.X,
		frameStart.Y.Scale, frameStart.Y.Offset + d.Y
	)
end)

UserInputService.InputEnded:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		isDragging = false
	end
end)

-- ── Open / Close ──────────────────────────────────────────────────────────────

local function closeMenu()
	menuFrame.Visible = false
end

local function openMenu()
	menuFrame.Visible = true
end

closeBtn.MouseButton1Click:Connect(closeMenu)

-- ── Button building ───────────────────────────────────────────────────────────

-- buttonRefs maps a normalised key → TextButton frame:
--   "none"          → the None button
--   langname:lower() → that language's button
local buttonRefs = {}

-- Apply or remove the selected highlight across all buttons.
local function applySelectionHighlight(langName: string?)
	for key, btn in pairs(buttonRefs) do
		local selected = (langName == nil and key == "none")
			or (langName ~= nil and key == langName:lower())
		btn.BackgroundColor3 = selected and C_SEL or C_BTN
		local lbl    = btn:FindFirstChildOfClass("TextLabel")
		local accent = btn:FindFirstChild("SelAccent")
		if lbl    then lbl.TextColor3   = selected and C_ACC or C_TXT end
		if accent then accent.Visible   = selected end
	end
end

-- Fired when the player clicks a language button.
local function selectLanguage(langName: string?)
	selectedLanguage = langName
	updateIndicator()
	applySelectionHighlight(langName)
	CommandRemotes.LanguageSelect:FireServer(langName or "")
	closeMenu()
end

local function makeButton(langName: string?, displayText: string, order: number): Frame
	local key = langName and langName:lower() or "none"

	local btn = Instance.new("TextButton")
	btn.Name                  = "LangBtn_" .. key
	btn.LayoutOrder           = order
	btn.Size                  = UDim2.new(1, 0, 0, BTN_H)
	btn.BackgroundColor3      = C_BTN
	btn.BorderSizePixel       = 0
	btn.Text                  = ""
	btn.AutoButtonColor       = false
	btn.ZIndex                = 22

	-- Left accent bar — visible only when this button is selected
	local accent = Instance.new("Frame", btn)
	accent.Name             = "SelAccent"
	accent.AnchorPoint      = Vector2.new(0, 0.5)
	accent.Size             = UDim2.new(0, 3, 1, -10)
	accent.Position         = UDim2.new(0, 5, 0.5, 0)
	accent.BackgroundColor3 = C_ACC
	accent.BorderSizePixel  = 0
	accent.Visible          = false
	accent.ZIndex           = 23
	Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

	local lbl = Instance.new("TextLabel", btn)
	lbl.Size                  = UDim2.new(1, -20, 1, 0)
	lbl.Position              = UDim2.new(0, 16, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font                  = Enum.Font.Gotham
	lbl.TextSize              = 13
	lbl.TextColor3            = C_TXT
	lbl.TextXAlignment        = Enum.TextXAlignment.Left
	lbl.TextYAlignment        = Enum.TextYAlignment.Center
	lbl.Text                  = displayText
	lbl.ZIndex                = 23

	btn.MouseEnter:Connect(function()
		-- Only tint on hover if this button isn't currently selected
		local isSel = (langName == nil and selectedLanguage == nil)
			or (langName ~= nil and selectedLanguage ~= nil
				and langName:lower() == selectedLanguage:lower())
		if not isSel then
			btn.BackgroundColor3 = Color3.fromRGB(22, 22, 38)
		end
	end)
	btn.MouseLeave:Connect(function()
		local isSel = (langName == nil and selectedLanguage == nil)
			or (langName ~= nil and selectedLanguage ~= nil
				and langName:lower() == selectedLanguage:lower())
		btn.BackgroundColor3 = isSel and C_SEL or C_BTN
	end)
	btn.MouseButton1Click:Connect(function()
		selectLanguage(langName)
	end)

	return btn
end

local function rebuildMenu()
	-- Destroy existing buttons
	for _, btn in pairs(buttonRefs) do
		pcall(function() btn:Destroy() end)
	end
	buttonRefs = {}

	-- "None" always first — deselects language, returns player to English
	local noneBtn = makeButton(nil, "None  (English)", 1)
	noneBtn.Parent      = listFrame
	buttonRefs["none"]  = noneBtn

	-- One button per granted language in grant order
	for i, langName in ipairs(grantedLanguages) do
		local btn = makeButton(langName, langName, i + 1)
		btn.Parent                         = listFrame
		buttonRefs[langName:lower()]       = btn
	end

	-- Reflect current selection immediately
	applySelectionHighlight(selectedLanguage)
end

-- ── Remote listeners ──────────────────────────────────────────────────────────

-- Server pushes the player's complete grant list on join and after each grant.
CommandRemotes.LanguageGrants.OnClientEvent:Connect(function(grants: { string })
	if typeof(grants) ~= "table" then return end
	grantedLanguages = grants

	-- If the player's currently selected language was somehow revoked, reset it.
	if selectedLanguage ~= nil then
		local stillGranted = false
		for _, g in ipairs(grantedLanguages) do
			if g:lower() == selectedLanguage:lower() then
				stillGranted = true; break
			end
		end
		if not stillGranted then
			selectedLanguage = nil
			updateIndicator()
			CommandRemotes.LanguageSelect:FireServer("")
		end
	end

	rebuildMenu()
end)

-- Server fires this when the player runs the `language` command.
CommandRemotes.LanguageOpen.OnClientEvent:Connect(openMenu)
