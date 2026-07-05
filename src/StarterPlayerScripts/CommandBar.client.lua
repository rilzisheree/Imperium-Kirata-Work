--[[
        CommandBar.client.lua  —  LocalScript (StarterPlayerScripts)

        ; or '   — open / close
        Escape    — close
        Enter     — run command
        Tab       — accept highlighted suggestion
        Up / Down — move through suggestions
]]

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

-- ── Command definitions ────────────────────────────────────────────────────────
-- args typed "player" get live player-name autocomplete

local COMMANDS = {
        sm      = { args = { "message" },           description = "Server message to all" },
        im      = { args = { "player", "message" },  description = "Message to one player" },
        anxiety = { args = { "player", "level" },    description = "Anxiety effect (1–5)" },
}

-- ── Colours ────────────────────────────────────────────────────────────────────

local C_BG   = Color3.fromRGB(12,  12,  18)
local C_BOR  = Color3.fromRGB(90,  90, 120)
local C_ACC  = Color3.fromRGB(160, 160, 210)
local C_TXT  = Color3.fromRGB(235, 235, 252)
local C_DIM  = Color3.fromRGB(80,  80, 100)
local C_DESC = Color3.fromRGB(110, 110, 140)

-- ── State (declared first so all closures see them) ────────────────────────────

local isOpen      = false
local suggestions = {}   -- list of {name, description}
local selIdx      = 1    -- currently highlighted row

-- ── Root ScreenGui ─────────────────────────────────────────────────────────────

local sg = Instance.new("ScreenGui")
sg.Name           = "CmdBarGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = false
sg.DisplayOrder   = 100
sg.Parent         = PGui

-- ── Bar frame ──────────────────────────────────────────────────────────────────

local BAR_W = 520
local BAR_H = 46
local BAR_Y = 12

local frame = Instance.new("Frame", sg)
frame.AnchorPoint      = Vector2.new(0.5, 0)
frame.Size             = UDim2.new(0, BAR_W, 0, BAR_H)
frame.Position         = UDim2.new(0.5, 0, 0, BAR_Y)
frame.BackgroundColor3 = C_BG
frame.BorderSizePixel  = 0
frame.Visible          = false
frame.ZIndex           = 10
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
local fStroke = Instance.new("UIStroke", frame)
fStroke.Color = C_BOR  fStroke.Thickness = 1.5
fStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local prompt = Instance.new("TextLabel", frame)
prompt.Size               = UDim2.new(0, 28, 1, 0)
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
box.Size               = UDim2.new(1, -42, 1, -12)
box.Position           = UDim2.new(0, 38, 0, 6)
box.BackgroundTransparency = 1
box.BorderSizePixel    = 0
box.ClearTextOnFocus   = false
box.Font               = Enum.Font.Code
box.TextSize           = 14
box.TextColor3         = C_TXT
box.PlaceholderText    = "Enter command…"
box.PlaceholderColor3  = C_DIM
box.Text               = ""
box.TextXAlignment     = Enum.TextXAlignment.Left
box.TextYAlignment     = Enum.TextYAlignment.Center
box.ZIndex             = 11

-- ── Dropdown ───────────────────────────────────────────────────────────────────

local ROW_H  = 30
local MAX_AC = 6

local drop = Instance.new("Frame", sg)
drop.AnchorPoint      = Vector2.new(0.5, 0)
drop.Size             = UDim2.new(0, BAR_W, 0, 0)
drop.Position         = UDim2.new(0.5, 0, 0, BAR_Y + BAR_H + 3)
drop.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
drop.BorderSizePixel  = 0
drop.Visible          = false
drop.ClipsDescendants = true
drop.ZIndex           = 20
Instance.new("UICorner", drop).CornerRadius = UDim.new(0, 7)
local dStroke = Instance.new("UIStroke", drop)
dStroke.Color = C_BOR  dStroke.Thickness = 1
dStroke.Transparency = 0.4
dStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
Instance.new("UIListLayout", drop).SortOrder = Enum.SortOrder.LayoutOrder

-- Pre-build rows (state is declared above, so closures can reference it safely)
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

        -- Invisible button to catch clicks / hover
        local rb = Instance.new("TextButton", row)
        rb.Size               = UDim2.new(1, 0, 1, 0)
        rb.BackgroundTransparency = 1
        rb.Text               = ""
        rb.ZIndex             = 22

        local ri = i   -- capture loop index
        rb.MouseEnter:Connect(function()
                selIdx = ri
                -- Re-render highlight without rebuilding the list
                for j, r in ipairs(rows) do
                        if r.Visible then
                                r.BackgroundTransparency = (j == selIdx) and 0.55 or 1
                                r:FindFirstChild("Accent").Visible = (j == selIdx)
                                local n = r:FindFirstChild("N")
                                if n then n.TextColor3 = (j == selIdx) and Color3.new(1,1,1) or C_TXT end
                        end
                end
        end)
        rb.MouseButton1Click:Connect(function()
                local s = suggestions[ri]
                if s then
                        -- acceptSuggestion is defined below; safe to call here because
                        -- this callback only fires after the full script has loaded.
                        acceptSuggestion(s.name)
                end
        end)

        rows[i] = row
end

-- ── [CMD] button ───────────────────────────────────────────────────────────────

local btn = Instance.new("TextButton", sg)
btn.AnchorPoint      = Vector2.new(1, 0)
btn.Size             = UDim2.new(0, 54, 0, 22)
btn.Position         = UDim2.new(1, -6, 0, 6)
btn.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
btn.BorderSizePixel  = 0
btn.Text             = "[CMD]"
btn.Font             = Enum.Font.GothamBold
btn.TextSize         = 10
btn.TextColor3       = C_ACC
btn.ZIndex           = 5
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
local bStroke = Instance.new("UIStroke", btn)
bStroke.Color = C_BOR  bStroke.Thickness = 1
bStroke.Transparency = 0.4
bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- ── Suggestion logic ───────────────────────────────────────────────────────────

local function hideDrop()
        suggestions = {}
        selIdx      = 1
        drop.Visible = false
        for _, r in ipairs(rows) do r.Visible = false end
end

local function showDrop()
        local n = math.min(#suggestions, MAX_AC)
        if n == 0 then hideDrop() return end

        drop.Size    = UDim2.new(0, BAR_W, 0, n * ROW_H)
        drop.Visible = true

        for i = 1, MAX_AC do
                local r = rows[i]
                local s = suggestions[i]
                r.Visible = (i <= n)
                if s then
                        local sel = (i == selIdx)
                        r.BackgroundTransparency = sel and 0.55 or 1
                        r:FindFirstChild("Accent").Visible = sel
                        local nl = r:FindFirstChild("N")
                        local dl = r:FindFirstChild("D")
                        local dv = r:FindFirstChild("Div")
                        if nl then nl.Text = s.name;        nl.TextColor3 = sel and Color3.new(1,1,1) or C_TXT end
                        if dl then dl.Text = s.description or "" end
                        if dv then dv.Visible = (i < n) end
                end
        end
end

local function getPlayerMatches(partial)
        local out = {}
        local p   = partial:lower()
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

        local text       = box.Text
        local endsSpace  = #text > 0 and text:sub(-1) == " "
        local words      = {}
        for w in text:gmatch("%S+") do table.insert(words, w) end

        -- partial = what the user is currently typing for the current token
        local partial    = endsSpace and "" or (words[#words] or "")
        -- numComplete = how many tokens are fully finished
        local numComplete = endsSpace and #words or math.max(0, #words - 1)

        if numComplete == 0 then
                -- typing the command name
                suggestions = getCmdMatches(partial)
                selIdx      = 1
                showDrop()
                return
        end

        -- check whether the current argument slot wants a player name
        local cmdName = (words[1] or ""):lower()
        local def     = COMMANDS[cmdName]
        local argSlot = numComplete   -- arg 1 = first arg after command

        if def and def.args[argSlot] == "player" then
                suggestions = getPlayerMatches(partial)
                selIdx      = 1
                showDrop()
                return
        end

        hideDrop()
end

-- ── acceptSuggestion ───────────────────────────────────────────────────────────
-- Replace the last partial token with the chosen name and add a space.

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

-- ── Open / Close ───────────────────────────────────────────────────────────────

local function open()
        if isOpen then return end
        isOpen = true
        frame.Visible = true
        hideDrop()
        box:CaptureFocus()
        print("[CMD] opened")
end

local function close()
        if not isOpen then return end
        isOpen = false
        frame.Visible = false
        hideDrop()
        box.Text = ""
        box:ReleaseFocus()
        print("[CMD] closed")
end

-- ── Execute ────────────────────────────────────────────────────────────────────

local function execute()
        local raw = box.Text:match("^%s*(.-)%s*$") or ""
        if raw == "" then close() return end

        local words = {}
        for w in raw:gmatch("%S+") do table.insert(words, w) end
        local cmd = table.remove(words, 1):lower()

        -- ── Server commands ───────────────────────────────────────────────────
        local remote = ReplicatedStorage:WaitForChild("CmdExecuted", 10)
        if not remote then
                warn("[CMD] CmdExecuted remote not found — is CommandServer running?")
                close()
                return
        end
        remote:FireServer(cmd, words)
        print("[CMD] fired:", cmd, words)
        close()
end

-- ── Wiring ─────────────────────────────────────────────────────────────────────

box:GetPropertyChangedSignal("Text"):Connect(function()
        if not isOpen then return end
        if box.Text:find("\t") then
                local c = box.Text:gsub("\t", "")
                box.Text = c
                box.CursorPosition = #c + 1
                return
        end
        updateSuggestions()
end)

box.FocusLost:Connect(function(enter)
        if enter then execute() end
end)

btn.MouseButton1Click:Connect(function()
        if isOpen then close() else open() end
end)

UserInputService.InputBegan:Connect(function(inp, gp)
        if inp.KeyCode == Enum.KeyCode.Semicolon
        or inp.KeyCode == Enum.KeyCode.Quote then
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

        -- Tab: accept top / highlighted suggestion
        if inp.KeyCode == Enum.KeyCode.Tab then
                local s = suggestions[selIdx] or suggestions[1]
                if s then acceptSuggestion(s.name) end
                return
        end

        -- Up / Down: move highlight
        if inp.KeyCode == Enum.KeyCode.Up and #suggestions > 0 then
                selIdx = ((selIdx - 2) % #suggestions) + 1
                showDrop()
                return
        end
        if inp.KeyCode == Enum.KeyCode.Down and #suggestions > 0 then
                selIdx = (selIdx % #suggestions) + 1
                showDrop()
                return
        end
end)

-- ── Done ───────────────────────────────────────────────────────────────────────

print("[CMD] Command bar ready — press ; or ' to open")
