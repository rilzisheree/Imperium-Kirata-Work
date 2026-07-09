local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService      = game:GetService("RunService")
local TextService     = game:GetService("TextService")
local TextChatService = game:GetService("TextChatService")

pcall(function()
        TextChatService.CreateDefaultTextChannels   = false
        TextChatService.CreateDefaultSystemMessages = false
end)
pcall(function()
        local bcc = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
        if bcc then bcc.Enabled = false end
end)

local ChatRemotes     = require(ReplicatedStorage:WaitForChild("ChatRemotes"))
local LanguageManager = require(script.Parent:WaitForChild("LanguageManager") :: ModuleScript)
local LanguageData    = require(ReplicatedStorage:WaitForChild("LanguageData") :: ModuleScript)

local MAX_MESSAGE_LENGTH = 200

local IS_STUDIO = RunService:IsStudio()

local STAFF_IDS = {
        [1872507151] = "Owner",
}

local function getTier(player: Player): string?
        if IS_STUDIO then return "Owner" end
        if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
                return "Owner"
        end
        return STAFF_IDS[player.UserId]
end

-- Returns true for any player with a staff tier (Helper or above).
local function isAdmin(player: Player): boolean
        return getTier(player) ~= nil
end

local NAME_COLORS = {
        Color3.fromRGB(253,  41,  67),
        Color3.fromRGB(  1, 162, 255),
        Color3.fromRGB(  2, 184,  87),
        Color3.fromRGB(255, 214,  74),
        Color3.fromRGB(255, 127,  36),
        Color3.fromRGB(255, 101, 197),
        Color3.fromRGB(155, 117, 230),
        Color3.fromRGB(  0, 187, 209),
}

local function getNameColor(player: Player): Color3
        return NAME_COLORS[(player.UserId % #NAME_COLORS) + 1]
end

local function filterMessage(sender: Player, text: string): string
        local ok, result = pcall(function()
                local filterResult = TextService:FilterStringAsync(text, sender.UserId)
                return filterResult:GetNonChatStringForBroadcastAsync()
        end)
        if ok and type(result) == "string" and result ~= "" then
                return result
        end
        return text
end

-- capitalize first letter + auto-period if needed
local function formatText(text: string): string
        if text == "" then return text end
        text = text:sub(1, 1):upper() .. text:sub(2)
        local last = text:sub(-1)
        if last ~= "." and last ~= "!" and last ~= "?" and text:sub(-3) ~= "…" then
                text = text .. "."
        end
        return text
end

local function broadcastProximity(sender: Player, rawText: string)
        local text = rawText:match("^%s*(.-)%s*$")
        if text == "" then return end
        if #text > MAX_MESSAGE_LENGTH then
                text = text:sub(1, MAX_MESSAGE_LENGTH) .. "…"
        end
        text = formatText(text)

        local filtered  = filterMessage(sender, text)
        local nameColor = getNameColor(sender)
        local team      = sender.Team
        local teamColor = team and team.TeamColor.Color or Color3.new(0.8, 0.8, 0.8)

        -- Base payload shared by all players (message field set per-player below)
        local base = {
                senderName  = sender.Name,
                displayName = sender.DisplayName,
                nameColorR  = nameColor.R,
                nameColorG  = nameColor.G,
                nameColorB  = nameColor.B,
                teamName    = team and team.Name or "No Team",
                teamColorR  = teamColor.R,
                teamColorG  = teamColor.G,
                teamColorB  = teamColor.B,
        }

        -- Check if the sender is currently speaking a non-English language
        local selectedLang = LanguageManager.getSelected(sender.UserId)
        local langDef      = selectedLang and LanguageData.BY_NAME[selectedLang:lower()]

        if not langDef then
                -- Plain English — one payload for everyone
                base.message = filtered
                for _, player in Players:GetPlayers() do
                        ChatRemotes.MessageReceived:FireClient(player, base)
                end
                return
        end

        local fictionalised  = LanguageManager.fictionalise(filtered, langDef.name)
        local originalTagged = "[" .. langDef.tag .. "] " .. filtered

        -- Broadcast to everyone — client handles distance show/hide in real time
        for _, player in Players:GetPlayers() do
                -- A player "understands" the language if their currently selected language
                -- matches the sender's, OR they've simply been granted that language —
                -- granted languages can be read passively without switching to speak them.
                local pSel        = LanguageManager.getSelected(player.UserId)
                local understands = (pSel ~= nil and pSel:lower() == selectedLang:lower())
                                        or LanguageManager.hasGrant(player.UserId, selectedLang)

                local payload   = table.clone(base)
                payload.message = understands and originalTagged or fictionalised
                ChatRemotes.MessageReceived:FireClient(player, payload)
        end
end

-- /t command: sender + admins only, no one else hears it
local function broadcastThought(sender: Player, rawText: string)
        local text = rawText:match("^%s*(.-)%s*$")
        if text == "" then return end
        if #text > MAX_MESSAGE_LENGTH then
                text = text:sub(1, MAX_MESSAGE_LENGTH) .. "…"
        end
        text = formatText(text)

        local filtered  = filterMessage(sender, text)
        local nameColor = getNameColor(sender)
        local team      = sender.Team
        local teamColor = team and team.TeamColor.Color or Color3.new(0.8, 0.8, 0.8)

        local base = {
                senderName  = sender.Name,
                displayName = sender.DisplayName,
                nameColorR  = nameColor.R,
                nameColorG  = nameColor.G,
                nameColorB  = nameColor.B,
                teamName    = team and team.Name or "No Team",
                teamColorR  = teamColor.R,
                teamColorG  = teamColor.G,
                teamColorB  = teamColor.B,
                isThought   = true,
        }

        local selectedLang = LanguageManager.getSelected(sender.UserId)
        local langDef      = selectedLang and LanguageData.BY_NAME[selectedLang:lower()]

        local fictionalised: string?
        local originalTagged: string?
        if langDef then
                fictionalised  = LanguageManager.fictionalise(filtered, langDef.name)
                originalTagged = "[" .. langDef.tag .. "] " .. filtered
        end

        for _, player in Players:GetPlayers() do
                if player ~= sender and not isAdmin(player) then continue end

                local payload = table.clone(base)

                if not langDef then
                        payload.message = filtered
                else
                        local pSel        = LanguageManager.getSelected(player.UserId)
                        local understands = (pSel ~= nil and pSel:lower() == selectedLang:lower())
                                        or LanguageManager.hasGrant(player.UserId, selectedLang)
                        payload.message   = understands and originalTagged or fictionalised
                end

                ChatRemotes.MessageReceived:FireClient(player, payload)
        end
end

-- /w command: sender + anyone within WHISPER_DISTANCE studs
local WHISPER_DISTANCE = 6

local function broadcastWhisper(sender: Player, rawText: string)
        local text = rawText:match("^%s*(.-)%s*$")
        if text == "" then return end
        if #text > MAX_MESSAGE_LENGTH then
                text = text:sub(1, MAX_MESSAGE_LENGTH) .. "…"
        end
        text = formatText(text)

        local filtered  = filterMessage(sender, text)
        local nameColor = getNameColor(sender)
        local team      = sender.Team
        local teamColor = team and team.TeamColor.Color or Color3.new(0.8, 0.8, 0.8)

        local base = {
                senderName  = sender.Name,
                displayName = sender.DisplayName,
                nameColorR  = nameColor.R,
                nameColorG  = nameColor.G,
                nameColorB  = nameColor.B,
                teamName    = team and team.Name or "No Team",
                teamColorR  = teamColor.R,
                teamColorG  = teamColor.G,
                teamColorB  = teamColor.B,
                isWhisper   = true,
        }

        local selectedLang = LanguageManager.getSelected(sender.UserId)
        local langDef      = selectedLang and LanguageData.BY_NAME[selectedLang:lower()]

        local fictionalised: string?
        local originalTagged: string?
        if langDef then
                fictionalised  = LanguageManager.fictionalise(filtered, langDef.name)
                originalTagged = "[" .. langDef.tag .. "] " .. filtered
        end

        local senderChar = sender.Character
        local senderRoot = senderChar and senderChar:FindFirstChild("HumanoidRootPart") :: BasePart?

        for _, player in Players:GetPlayers() do
                if player ~= sender then
                        if not senderRoot then continue end
                        local pChar = player.Character
                        local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
                        if not pRoot then continue end
                        if (senderRoot.Position - pRoot.Position).Magnitude > WHISPER_DISTANCE then continue end
                end

                local payload = table.clone(base)

                if not langDef then
                        payload.message = filtered
                else
                        local pSel        = LanguageManager.getSelected(player.UserId)
                        local understands = (pSel ~= nil and pSel:lower() == selectedLang:lower())
                                        or LanguageManager.hasGrant(player.UserId, selectedLang)
                        payload.message   = understands and originalTagged or fictionalised
                end

                ChatRemotes.MessageReceived:FireClient(player, payload)
        end
end

local function routeMessage(sender: Player, rawText: string)
        -- /t <message> — Thoughts: private to sender + admins only.
        if rawText:match("^%s*/t$") or rawText:match("^%s*/t%s") then
                local body = rawText:match("^%s*/t%s+(.-)%s*$") or ""
                if body ~= "" then broadcastThought(sender, body) end
                return
        end

        -- /w <message> — Whisper: sender + players within WHISPER_DISTANCE studs.
        if rawText:match("^%s*/w$") or rawText:match("^%s*/w%s") then
                local body = rawText:match("^%s*/w%s+(.-)%s*$") or ""
                if body ~= "" then broadcastWhisper(sender, body) end
                return
        end

        broadcastProximity(sender, rawText)
end

ChatRemotes.MessageSent.OnServerEvent:Connect(function(sender: Player, rawText: string)
        if typeof(rawText) ~= "string" then return end
        routeMessage(sender, rawText)
end)

Players.PlayerAdded:Connect(function(player: Player)
        player.Chatted:Connect(function(message: string)
                routeMessage(player, message)
        end)
end)
