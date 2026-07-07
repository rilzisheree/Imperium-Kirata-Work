local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService      = game:GetService("RunService")
local TextService     = game:GetService("TextService")
local TextChatService = game:GetService("TextChatService")

-- kill default chat stuff
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

-- ── Admin detection ───────────────────────────────────────────────────────────
-- Mirrors the STAFF_IDS table in CommandServer.  Both must be kept in sync
-- when adding or removing staff members.

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

local function broadcastProximity(sender: Player, rawText: string)
	local text = rawText:match("^%s*(.-)%s*$")
	if text == "" then return end
	if #text > MAX_MESSAGE_LENGTH then
		text = text:sub(1, MAX_MESSAGE_LENGTH) .. "…"
	end

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

	-- Convert the filtered message into fictional text using the sender's
	-- chosen script.  fictionalise is synchronous (no HTTP) so it never
	-- yields — the same call that looked up the language def produces the
	-- result immediately.
	local fictionalised  = LanguageManager.fictionalise(filtered, langDef.name)
	local originalTagged = "[" .. langDef.tag .. "] " .. filtered

	-- Broadcast to everyone — client handles distance show/hide in real time
	for _, player in Players:GetPlayers() do
		-- A player "understands" the language if their currently selected language
		-- matches the sender's.  Only granted languages can be selected, so no
		-- separate grant check is needed here.
		local pSel        = LanguageManager.getSelected(player.UserId)
		local understands = pSel ~= nil and pSel:lower() == selectedLang:lower()

		local payload   = table.clone(base)
		payload.message = understands and originalTagged or fictionalised
		ChatRemotes.MessageReceived:FireClient(player, payload)
	end
end

-- ── Thoughts broadcast ────────────────────────────────────────────────────────
-- Sends a private "Thoughts" message.  Only the sender and online admins
-- receive the payload; no one else knows the message was sent.
-- Language rules mirror broadcastProximity: non-English language players still
-- see the selected-language version, understanders see the tagged original.

local function broadcastThought(sender: Player, rawText: string)
	local text = rawText:match("^%s*(.-)%s*$")
	if text == "" then return end
	if #text > MAX_MESSAGE_LENGTH then
		text = text:sub(1, MAX_MESSAGE_LENGTH) .. "…"
	end

	local filtered  = filterMessage(sender, text)
	local nameColor = getNameColor(sender)
	local team      = sender.Team
	local teamColor = team and team.TeamColor.Color or Color3.new(0.8, 0.8, 0.8)

	-- Base payload — same shape as broadcastProximity; isThought tells clients
	-- to suppress the speech bubble and render the log entry in purple.
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

	-- Apply language system exactly as in broadcastProximity.
	local selectedLang = LanguageManager.getSelected(sender.UserId)
	local langDef      = selectedLang and LanguageData.BY_NAME[selectedLang:lower()]

	-- Pre-compute the fictionalised text once so every non-understanding
	-- admin receives the same output (consistent with proximity chat behaviour).
	local fictionalised: string?
	local originalTagged: string?
	if langDef then
		fictionalised  = LanguageManager.fictionalise(filtered, langDef.name)
		originalTagged = "[" .. langDef.tag .. "] " .. filtered
	end

	-- Deliver only to the sender and every online admin.
	for _, player in Players:GetPlayers() do
		if player ~= sender and not isAdmin(player) then continue end

		local payload = table.clone(base)

		if not langDef then
			payload.message = filtered
		else
			local pSel        = LanguageManager.getSelected(player.UserId)
			local understands = pSel ~= nil and pSel:lower() == selectedLang:lower()
			payload.message   = understands and originalTagged or fictionalised
		end

		ChatRemotes.MessageReceived:FireClient(player, payload)
	end
end

-- ── Incoming message router ───────────────────────────────────────────────────
-- Single entry point for all incoming chat text, regardless of source.
-- Keeps /t routing consistent whether the message arrives via the custom
-- RemoteEvent or the legacy player.Chatted fallback.

local function routeMessage(sender: Player, rawText: string)
	-- /t <message> — Thoughts: private to sender + admins only.
	--
	-- Detect any /t invocation first (bare "/t" OR "/t" followed by a space).
	-- Once matched, the route is ALWAYS terminal — we never fall through to
	-- broadcastProximity, so a whitespace-only body like "/t   " can never
	-- be emitted as public proximity chat.
	-- "/table", "/test", etc. don't match because they have a non-space
	-- character immediately after the "t".
	if rawText:match("^%s*/t$") or rawText:match("^%s*/t%s") then
		local thoughtBody = rawText:match("^%s*/t%s+(.-)%s*$") or ""
		if thoughtBody ~= "" then
			broadcastThought(sender, thoughtBody)
		end
		-- Empty body: silently discard — never proximate-broadcast.
		return
	end
	broadcastProximity(sender, rawText)
end

ChatRemotes.MessageSent.OnServerEvent:Connect(function(sender: Player, rawText: string)
	if typeof(rawText) ~= "string" then return end
	routeMessage(sender, rawText)
end)

-- Fallback for legacy player.Chatted (e.g. older Roblox clients or Studio
-- tests that bypass the custom RemoteEvent).  Routed through the same parser
-- so /t is never accidentally broadcast as proximity chat.
Players.PlayerAdded:Connect(function(player: Player)
	player.Chatted:Connect(function(message: string)
		routeMessage(player, message)
	end)
end)
