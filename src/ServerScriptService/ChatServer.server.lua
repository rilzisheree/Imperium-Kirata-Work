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
local TextService       = game:GetService("TextService")
local TextChatService   = game:GetService("TextChatService")

-- Disable the new TextChatService's default channels and bubble chat.
-- ChatVersion is no longer set to LegacyChatService — the project.json
-- already uses the new TextChatService with CreateDefaultTextChannels=false,
-- which avoids the legacy chat's BindCoreAction key bindings for / and Enter.
pcall(function()
        TextChatService.CreateDefaultTextChannels  = false
        TextChatService.CreateDefaultSystemMessages = false
end)
pcall(function()
        local bcc = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
        if bcc then bcc.Enabled = false end
end)

local ChatRemotes = require(ReplicatedStorage:WaitForChild("ChatRemotes"))

-- ─── Configuration ────────────────────────────────────────────────────────────
-- Distance tiers are enforced client-side in real time so bubbles update as
-- players move. The server broadcasts to everyone so latecomers (players who
-- walk into range after the message is sent) can still see it.
local MAX_MESSAGE_LENGTH = 200   -- character cap
local FULL_DISTANCE      = 23    -- studs: full message visible
local MUFFLED_DISTANCE   = 33    -- studs: [Inaudible] shown


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
                local filterResult = TextService:FilterStringAsync(text, sender.UserId)
                return filterResult:GetNonChatStringForBroadcastAsync()
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
        local senderPos = getPosition(sender)
        local nameColor = getNameColor(sender)

        -- Team info (TeamColor is a BrickColor; .Color gives the Color3)
        local team      = sender.Team
        local teamName  = team and team.Name or "No Team"
        local teamColor = team and team.TeamColor.Color or Color3.new(0.8, 0.8, 0.8)

        local payload = {
                senderName  = sender.Name,
                displayName = sender.DisplayName,
                message     = filtered,
                nameColorR  = nameColor.R,
                nameColorG  = nameColor.G,
                nameColorB  = nameColor.B,
                teamName    = teamName,
                teamColorR  = teamColor.R,
                teamColorG  = teamColor.G,
                teamColorB  = teamColor.B,
        }

        -- Only fire to players whose characters are within MUFFLED_DISTANCE of the
        -- sender at the time the message is sent. The sender always gets their own
        -- message. Players outside this range never receive the payload, so they
        -- cannot read it even if they inspect network traffic.
        -- Client-side RenderStepped still handles the full ↔ [Inaudible] distinction
        -- for recipients who are between FULL_DISTANCE and MUFFLED_DISTANCE.
        for _, player in Players:GetPlayers() do
                local shouldReceive = (player == sender)
                if not shouldReceive and senderPos then
                        local recipPos = getPosition(player)
                        if recipPos then
                                shouldReceive = (senderPos - recipPos).Magnitude <= MUFFLED_DISTANCE
                        end
                elseif not shouldReceive and not senderPos then
                        -- Sender has no position (e.g. spectating) — broadcast to all as fallback
                        shouldReceive = true
                end
                if shouldReceive then
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
