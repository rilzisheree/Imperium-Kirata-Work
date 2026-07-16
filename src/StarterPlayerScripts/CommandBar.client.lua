
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local CommandRemotes  = require(ReplicatedStorage:WaitForChild("CommandRemotes"))
local LanguageData    = require(ReplicatedStorage:WaitForChild("LanguageData"))
local CommandRegistry = require(ReplicatedStorage:WaitForChild("CommandRegistry"))

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local COMMANDS = {}

-- Tracks whether Staff Mode is currently active for this client.  Set by the
-- StaffMode remote; used to reapply Staff commands if Permissions fires again.
local staffModeEnabled = false

-- The server is the real authority on what a player can run (see
-- PermissionManager.lua) -- this just mirrors that into the autocomplete
-- list. `allowedCommands` is the explicit list of command names the player's
-- group role unlocks; `isStaff` is true for any staff role at all.
CommandRemotes.Permissions.OnClientEvent:Connect(function(allowedCommands: { string }, isStaff: boolean)
	if typeof(allowedCommands) ~= "table" then return end
	local allowedSet = {}
	for _, name in allowedCommands do allowedSet[name] = true end

	local keepLanguage = COMMANDS["language"]

	for k in pairs(COMMANDS) do COMMANDS[k] = nil end

	if isStaff then
		COMMANDS["chatlogs"] = { args = {}, description = "Open / close chat logs" }
	end

	for name, def in pairs(CommandRegistry.COMMANDS) do
		if name ~= "language" and allowedSet[name] then
			COMMANDS[name] = { args = def.args, description = def.description }
		end
	end

	if keepLanguage then
		COMMANDS["language"] = keepLanguage
	end
end)

CommandRemotes.LanguageGrants.OnClientEvent:Connect(function(grants: { string })
	if typeof(grants) ~= "table" then return end
	if #grants > 0 then
		COMMANDS["language"] = { args = {}, description = "Open language selection menu" }
	else
		COMMANDS["language"] = nil
	end
end)

CommandRemotes.StaffMode.OnClientEvent:Connect(function(enabled: boolean)
	staffModeEnabled = enabled
end)

local toggleChatLogs = Instance.new("BindableEvent")
toggleChatLogs.Name   = "ToggleChatLogs"
toggleChatLogs.Parent = PGui

local C_BG   = Color3.fromRGB(12,  12,  18)
local C_BOR  = Color3.fromRGB(90,  90, 120)
local C_ACC  = Color3.fromRGB(160, 160, 210)
local C_TXT  = Color3.fromRGB(235, 235, 252)
local C_DIM  = Color3.fromRGB(80,  80, 100)
local C_DESC = Color3.fromRGB(110, 110, 140)

local isOpen       = false
local suggestions  = {}
local selIdx       = 1   -- 1-based index into suggestions (can exceed MAX_AC)
local scrollOffset = 0   -- how many suggestions are scrolled past at the top

local sg = Instance.new("ScreenGui")
sg.Name           = "CmdBarGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = false
sg.DisplayOrder   = 100
sg.Parent         = PGui

local BAR_W     = 520
local BAR_H_MIN = 46    -- height with a single line of text
local BAR_H_MAX = 112   -- cap at ~5 lines (beyond this the TextBox scrolls natively)
local BAR_Y     = 12
local LINE_H    = 18    -- approximate rendered height of one line at TextSize 14 Code

local frame = Instance.new("Frame", sg)
frame.AnchorPoint      = Vector2.new(0.5, 0)
frame.Size             = UDim2.new(0, BAR_W, 0, BAR_H_MIN)
frame.Position         = UDim2.new(0.5, 0, 0, BAR_Y)
frame.BackgroundColor3 = C_BG
frame.BorderSizePixel  = 0
frame.Visible          = false
frame.ZIndex           = 10
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
local fStroke = Instance.new("UIStroke", frame)
fStroke.Color = C_BOR; fStroke.Thickness = 1.5
fStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local prompt = Instance.new("TextLabel", frame)
prompt.Size               = UDim2.new(0, 28, 0, BAR_H_MIN)
prompt.Position           = UDim2.new(0, 8, 0, 0)
prompt.BackgroundTransparency = 1
prompt.Font               = Enum.Font.GothamBold
prompt.TextSize           = 18
prompt.TextColor3         = C_ACC
prompt.Text               = "›"
prompt.TextXAlignment     = Enum.TextXAlignment.Center
prompt.TextYAlignment     = Enum.TextYAlignment.Center
prompt.ZIndex             = 11

local box = Instance.new("TextBox", frame)
box.Size                  = UDim2.new(1, -42, 0, LINE_H)
box.Position              = UDim2.new(0, 38, 0, math.floor((BAR_H_MIN - LINE_H) / 2))
box.BackgroundTransparency = 1
box.BorderSizePixel       = 0
box.ClearTextOnFocus      = false
box.MultiLine             = true
box.TextWrapped           = true
box.Font                  = Enum.Font.Code
box.TextSize              = 14
box.TextColor3            = C_TXT
box.PlaceholderText       = "Enter command…"
box.PlaceholderColor3     = C_DIM
box.Text                  = ""
box.TextXAlignment        = Enum.TextXAlignment.Left
box.TextYAlignment        = Enum.TextYAlignment.Top
box.ZIndex                = 11

local ROW_H  = 30
local MAX_AC = 6

local drop = Instance.new("Frame", sg)
drop.AnchorPoint      = Vector2.new(0.5, 0)
drop.Size             = UDim2.new(0, BAR_W, 0, 0)
drop.Position         = UDim2.new(0.5, 0, 0, BAR_Y + BAR_H_MIN + 3)
drop.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
drop.BorderSizePixel  = 0
drop.Visible          = false
drop.ClipsDescendants = true
drop.ZIndex           = 20
Instance.new("UICorner", drop).CornerRadius = UDim.new(0, 7)
local dStroke = Instance.new("UIStroke", drop)
dStroke.Color = C_BOR; dStroke.Thickness = 1
dStroke.Transparency = 0.4
dStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
Instance.new("UIListLayout", drop).SortOrder = Enum.SortOrder.LayoutOrder

-- A hidden TextLabel that mirrors the TextBox content.  TextLabel.TextBounds
-- correctly reports the wrapped height; TextBox.TextBounds does not.
-- Parented to the ScreenGui but positioned off-screen so it is never visible.
local measureLabel = Instance.new("TextLabel", sg)
measureLabel.Size                  = UDim2.fromOffset(BAR_W - 42, 0)
measureLabel.AutomaticSize         = Enum.AutomaticSize.Y
measureLabel.Position              = UDim2.fromOffset(-9999, -9999)
measureLabel.BackgroundTransparency = 1
measureLabel.TextTransparency      = 1
measureLabel.Font                  = Enum.Font.Code
measureLabel.TextSize              = 14
measureLabel.TextWrapped           = true
measureLabel.TextXAlignment        = Enum.TextXAlignment.Left
measureLabel.TextYAlignment        = Enum.TextYAlignment.Top
measureLabel.Text                  = ""
measureLabel.ZIndex                = 1

local function updateBarHeight()
	-- Use the measurement label's reported bounds — reliable for wrapped text.
	local textH = math.max(measureLabel.TextBounds.Y, LINE_H)
	local newH  = math.clamp(textH + 12, BAR_H_MIN, BAR_H_MAX)

	frame.Size   = UDim2.new(0, BAR_W, 0, newH)
	prompt.Size  = UDim2.new(0, 28, 0, newH)

	-- Vertically center on a single line; top-align when text spans multiple.
	local innerH  = newH - 12
	local yOffset = math.max(0, math.floor((innerH - textH) / 2))
	box.Position  = UDim2.new(0, 38, 0, 6 + yOffset)
	box.Size      = UDim2.new(1, -42, 0, innerH - yOffset)

	-- Keep the autocomplete dropdown pinned directly below the bar.
	drop.Position = UDim2.new(0.5, 0, 0, BAR_Y + newH + 3)
end

measureLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
	if isOpen then updateBarHeight() end
end)

local rows = {}
for i = 1, MAX_AC do
	local row = Instance.new("Frame", drop)
	row.LayoutOrder            = i
	row.Size                   = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3       = Color3.fromRGB(28, 28, 42)
	row.BackgroundTransparency = 1
	row.BorderSizePixel        = 0
	row.Visible                = false
	row.ZIndex                 = 20

	local accent = Instance.new("Frame", row)
	accent.Name             = "Accent"
	accent.Size             = UDim2.new(0, 3, 1, -8)
	accent.Position         = UDim2.new(0, 4, 0, 4)
	accent.BackgroundColor3 = C_ACC
	accent.BorderSizePixel  = 0
	accent.Visible          = false
	accent.ZIndex           = 21

	local nLbl = Instance.new("TextLabel", row)
	nLbl.Name              = "N"
	nLbl.Size              = UDim2.new(0, 160, 1, 0)
	nLbl.Position          = UDim2.new(0, 14, 0, 0)
	nLbl.BackgroundTransparency = 1
	nLbl.Font              = Enum.Font.Code
	nLbl.TextSize          = 13
	nLbl.TextColor3        = C_TXT
	nLbl.TextXAlignment    = Enum.TextXAlignment.Left
	nLbl.TextYAlignment    = Enum.TextYAlignment.Center
	nLbl.ZIndex            = 21

	local dLbl = Instance.new("TextLabel", row)
	dLbl.Name              = "D"
	dLbl.Size              = UDim2.new(1, -178, 1, 0)
	dLbl.Position          = UDim2.new(0, 174, 0, 0)
	dLbl.BackgroundTransparency = 1
	dLbl.Font              = Enum.Font.Gotham
	dLbl.TextSize          = 11
	dLbl.TextColor3        = C_DESC
	dLbl.TextXAlignment    = Enum.TextXAlignment.Left
	dLbl.TextYAlignment    = Enum.TextYAlignment.Center
	dLbl.TextTruncate      = Enum.TextTruncate.AtEnd
	dLbl.ZIndex            = 21

	local div = Instance.new("Frame", row)
	div.Name               = "Div"
	div.Size               = UDim2.new(1, -14, 0, 1)
	div.Position           = UDim2.new(0, 14, 1, -1)
	div.BackgroundColor3   = C_BOR
	div.BackgroundTransparency = 0.65
	div.BorderSizePixel    = 0
	div.ZIndex             = 21

	local rb = Instance.new("TextButton", row)
	rb.Size               = UDim2.new(1, 0, 1, 0)
	rb.BackgroundTransparency = 1
	rb.Text               = ""
	rb.ZIndex             = 22

	local ri = i
	rb.MouseEnter:Connect(function()
		-- Map the hovered row back to its position in the full suggestions list.
		selIdx = scrollOffset + ri
		for j, r in ipairs(rows) do
			if r.Visible then
				local isSel = (scrollOffset + j == selIdx)
				r.BackgroundTransparency = isSel and 0.55 or 1
				r:FindFirstChild("Accent").Visible = isSel
				local n = r:FindFirstChild("N")
				if n then n.TextColor3 = isSel and Color3.new(1,1,1) or C_TXT end
			end
		end
	end)
	rb.MouseButton1Click:Connect(function()
		local s = suggestions[scrollOffset + ri]
		if s then acceptSuggestion(s.name) end
	end)

	rows[i] = row
end

local function hideDrop()
	suggestions  = {}
	selIdx       = 1
	scrollOffset = 0
	drop.Visible = false
	for _, r in ipairs(rows) do r.Visible = false end
end

local function showDrop()
	local total   = #suggestions
	local visible = math.min(total, MAX_AC)
	if visible == 0 then hideDrop() return end

	-- Clamp scrollOffset so the window never goes past the last item.
	scrollOffset = math.clamp(scrollOffset, 0, math.max(0, total - MAX_AC))

	drop.Size    = UDim2.new(0, BAR_W, 0, visible * ROW_H)
	drop.Visible = true

	for i = 1, MAX_AC do
		local r = rows[i]
		local s = suggestions[scrollOffset + i]  -- offset into full list
		r.Visible = (i <= visible)
		if s then
			local sel = (scrollOffset + i == selIdx)
			r.BackgroundTransparency = sel and 0.55 or 1
			r:FindFirstChild("Accent").Visible = sel
			local nl = r:FindFirstChild("N")
			local dl = r:FindFirstChild("D")
			local dv = r:FindFirstChild("Div")
			if nl then nl.Text = s.name;        nl.TextColor3 = sel and Color3.new(1,1,1) or C_TXT end
			if dl then dl.Text = s.description or "" end
			if dv then dv.Visible = (i < visible) end
		end
	end
end

local function getLanguageMatches(partial)
	local out = {}
	local p   = partial:lower()
	for _, lang in ipairs(LanguageData.LANGUAGES) do
		if p == "" or lang.name:lower():sub(1, #p) == p then
			table.insert(out, { name = lang.name, description = lang.tag })
		end
	end
	return out
end

local function getPlayerMatches(partial)
	local out = {}
	local p   = partial:lower()
	if p == "" or ("all"):sub(1, #p) == p then
		table.insert(out, { name = "all", description = "everyone in server" })
	end
	if p == "" or ("me"):sub(1, #p) == p then
		table.insert(out, { name = "me", description = "yourself" })
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local nm = plr.Name
			if p == "" or nm:lower():sub(1, #p) == p then
				table.insert(out, { name = nm, description = plr.DisplayName })
			end
		end
	end
	return out
end

local function getCmdMatches(partial)
	local out = {}
	local p   = partial:lower()
	for name, def in pairs(COMMANDS) do
		if p == "" or name:sub(1, #p) == p then
			local hint = name
			for _, a in ipairs(def.args) do hint = hint .. " <" .. a .. ">" end
			table.insert(out, { name = name, description = hint })
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function updateSuggestions()
	if not isOpen then return end

	local text      = box.Text
	local endsSpace = #text > 0 and text:sub(-1) == " "
	local words     = {}
	for w in text:gmatch("%S+") do table.insert(words, w) end

	local partial     = endsSpace and "" or (words[#words] or "")
	local numComplete = endsSpace and #words or math.max(0, #words - 1)

	if numComplete == 0 then
		suggestions = getCmdMatches(partial)
		selIdx      = 1
		showDrop()
		return
	end

	local cmdName = (words[1] or ""):lower()
	local def     = COMMANDS[cmdName]
	local argSlot = numComplete

	local argType = def and def.args[argSlot]
	if argType == "player" or argType == "player|all" then
		suggestions = getPlayerMatches(partial)
		selIdx      = 1
		showDrop()
		return
	end

	if argType == "language" then
		suggestions = getLanguageMatches(partial)
		selIdx      = 1
		showDrop()
		return
	end

	hideDrop()
end

-- replaces the last partial token with the chosen name + space
function acceptSuggestion(name)
	local text      = box.Text
	local endsSpace = #text > 0 and text:sub(-1) == " "
	local base      = endsSpace and text or (text:match("^(.*%s)") or "")
	box.Text        = base .. name .. " "
	task.defer(function()
		box.CursorPosition = #box.Text + 1
		box:CaptureFocus()
	end)
	updateSuggestions()
end

local function open()
	if isOpen then return end
	isOpen = true
	frame.Visible = true
	hideDrop()
	-- Focus is deferred so the InputBegan cycle finishes first.
	-- The OS character-injection event fires AFTER the defer (on the same
	-- frame), so we use task.delay(0) — which waits for the next Heartbeat —
	-- to wipe the ; that was typed after the box gained focus.
	task.defer(function()
		box:CaptureFocus()
	end)
	task.delay(0, function()
		if isOpen then box.Text = "" end
	end)
end

local function close()
	if not isOpen then return end
	isOpen = false
	frame.Visible = false
	hideDrop()
	box.Text = ""
	box:ReleaseFocus()
	-- Reset measurement label and bar back to single-line height for next open.
	measureLabel.Text = ""
	frame.Size    = UDim2.new(0, BAR_W, 0, BAR_H_MIN)
	prompt.Size   = UDim2.new(0, 28, 0, BAR_H_MIN)
	box.Position  = UDim2.new(0, 38, 0, math.floor((BAR_H_MIN - LINE_H) / 2))
	box.Size      = UDim2.new(1, -42, 0, LINE_H)
	drop.Position = UDim2.new(0.5, 0, 0, BAR_Y + BAR_H_MIN + 3)
end

local function execute()
	local raw = box.Text:match("^%s*(.-)%s*$") or ""
	if raw == "" then close() return end

	local words = {}
	for w in raw:gmatch("%S+") do table.insert(words, w) end
	local cmd = table.remove(words, 1):lower()

	if cmd == "chatlogs" then
		toggleChatLogs:Fire()
		close()
		return
	end

	local remote = ReplicatedStorage:WaitForChild("CmdExecuted", 10)
	if not remote then
		warn("CommandBar: CmdExecuted remote not found — is CommandServer running?")
		close()
		return
	end
	remote:FireServer(cmd, words)
	close()
end

box:GetPropertyChangedSignal("Text"):Connect(function()
	if not isOpen then return end
	-- Strip control characters that must not enter the command string.
	local dirty = box.Text:find("[\t\n\r]")
	if dirty then
		local c = box.Text:gsub("[\t\n\r]", "")
		box.Text = c
		box.CursorPosition = #c + 1
		return
	end
	-- Mirror into the measurement label so TextBounds reflects wrapped height.
	measureLabel.Text = box.Text ~= "" and box.Text or " "
	updateSuggestions()
end)

box.FocusLost:Connect(function(enter)
	if enter then execute() end
end)

UserInputService.InputBegan:Connect(function(inp, gp)
	if inp.KeyCode == Enum.KeyCode.Semicolon then
		if not gp then
			if isOpen then close() else open() end
		end
		return
	end

	if not isOpen then return end

	if inp.KeyCode == Enum.KeyCode.Escape then
		close()
		return
	end

	-- MultiLine TextBox suppresses the FocusLost(enter) path, so we
	-- intercept Return here instead.
	if inp.KeyCode == Enum.KeyCode.Return or inp.KeyCode == Enum.KeyCode.KeypadEnter then
		execute()
		return
	end

	if inp.KeyCode == Enum.KeyCode.Tab then
		local s = suggestions[selIdx] or suggestions[1]
		if s then acceptSuggestion(s.name) end
		return
	end

	if inp.KeyCode == Enum.KeyCode.Up and #suggestions > 0 then
		selIdx = ((selIdx - 2) % #suggestions) + 1
		-- If selection scrolled above the visible window, shift the window up.
		if selIdx <= scrollOffset then
			scrollOffset = selIdx - 1
		end
		-- Wrap-around: jumped from top to bottom — show the last page.
		if selIdx > scrollOffset + MAX_AC then
			scrollOffset = math.max(0, #suggestions - MAX_AC)
		end
		showDrop()
		return
	end
	if inp.KeyCode == Enum.KeyCode.Down and #suggestions > 0 then
		selIdx = (selIdx % #suggestions) + 1
		-- If selection scrolled below the visible window, shift the window down.
		if selIdx > scrollOffset + MAX_AC then
			scrollOffset = selIdx - MAX_AC
		end
		-- Wrap-around: jumped from bottom to top — reset to first page.
		if selIdx <= scrollOffset then
			scrollOffset = 0
		end
		showDrop()
		return
	end
end)
