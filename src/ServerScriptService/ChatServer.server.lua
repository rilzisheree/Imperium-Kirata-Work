--[[
        ChatServer.server.lua
        Script — ServerScriptService

        Proximity chat system:
          • Disables Roblox's built-in chat service
          • Validates and filters incoming messages
          • Fires chat events ONLY to players whose characters are
            within MAX_DISTANCE studs of the sender
          • Sender always receives their own message
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Chat              = game:GetService("Chat")
local TextChatService   = game:GetService("TextChatService")

-- Kill Roblox's default chat and bubble chat entirely
pcall(function()
        TextChatService.ChatVersion = Enum.ChatVersion.LegacyChatService
end)
pcall(function()
        local bcc = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
        if bcc then bcc.Enabled = false end
end)

local ChatRemotes = require(ReplicatedStorage:WaitForChild("ChatRemotes"))

-- ─── Configuration ────────────────────────────────────────────────────────────
local FULL_DISTANCE      = 10    -- studs — see the full message
local MUFFLED_DISTANCE   = 30    -- studs — see ". . ." (between FULL and this)
local MAX_MESSAGE_LENGTH = 200   -- character cap
local MAX_LOG_ENTRIES    = 200   -- how many messages to keep in memory

-- ─── Chat log ring buffer ─────────────────────────────────────────────────────
-- Exposed via _G.ChatLog so CommandServer can read it for the chatlogs command.
local chatLog: { { sender: string, text: string, time: string } } = {}
_G.ChatLog = chatLog

local function logMessage(sender: Player, text: string)
        -- Simple HH:MM:SS timestamp
        local now    = os.time()
        local hour   = math.floor(now / 3600) % 24
        local minute = math.floor(now / 60) % 60
        local second = now % 60
        local ts     = string.format("%02d:%02d:%02d", hour, minute, second)

        table.insert(chatLog, {
                sender = sender.DisplayName .. " (@" .. sender.Name .. ")",
                text   = text,
                time   = ts,
        })

        -- Trim to ring buffer size
        while #chatLog > MAX_LOG_ENTRIES do
                table.remove(chatLog, 1)
        end
end

-- Name colours (same palette as default Roblox chat, keyed by UserId)
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

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function getNameColor(player: Player): Color3
        return NAME_COLORS[(player.UserId % #NAME_COLORS) + 1]
end

local function filterMessage(sender: Player, text: string): string
        local ok, result = pcall(function()
                return Chat:FilterStringAsync(text, sender, sender)
        end)
        if ok and type(result) == "string" and result ~= "" then
                return result
        end
        return text
end

-- Returns the HumanoidRootPart position, or nil if character isn't loaded
local function getPosition(player: Player): Vector3?
        local char = player.Character
        if not char then return nil end
        local root = char:FindFirstChild("HumanoidRootPart")
        return root and root.Position or nil
end

-- ─── Proximity broadcast ──────────────────────────────────────────────────────

local function broadcastProximity(sender: Player, rawText: string)
        -- Trim + length cap
        local text = rawText:match("^%s*(.-)%s*$")
        if text == "" then return end
        if #text > MAX_MESSAGE_LENGTH then
                text = text:sub(1, MAX_MESSAGE_LENGTH) .. "…"
        end

        local filtered = filterMessage(sender, text)
        logMessage(sender, filtered)
        local senderPos = getPosition(sender)
        local nameColor = getNameColor(sender)

        local payload = {
                senderName  = sender.Name,           -- used to locate the character on clients
                displayName = sender.DisplayName,
                message     = filtered,
                nameColorR  = nameColor.R,
                nameColorG  = nameColor.G,
                nameColorB  = nameColor.B,
        }

        for _, player in Players:GetPlayers() do
                -- Sender always receives their own message.
                -- Everyone else must be within MUFFLED_DISTANCE to receive anything.
                -- The client handles the full vs ". . ." split in real time, so we
                -- always send the full filtered text here — never a static ". . .".
                local inRange = (player == sender)

                if not inRange and senderPos then
                        local pos = getPosition(player)
                        if pos and (pos - senderPos).Magnitude <= MUFFLED_DISTANCE then
                                inRange = true
                        end
                end

                if inRange then
                        ChatRemotes.MessageReceived:FireClient(player, payload)
                end
        end
end

-- ─── Remote listener ──────────────────────────────────────────────────────────

ChatRemotes.MessageSent.OnServerEvent:Connect(function(sender: Player, rawText: string)
        if typeof(rawText) ~= "string" then return end
        broadcastProximity(sender, rawText)
end)

-- Fallback: catch messages from the legacy .Chatted event too
Players.PlayerAdded:Connect(function(player: Player)
        player.Chatted:Connect(function(message: string)
                broadcastProximity(player, message)
        end)
end)

print("[ChatServer] Proximity chat system active. Full:", FULL_DISTANCE, "studs | Muffled:", MUFFLED_DISTANCE, "studs")
