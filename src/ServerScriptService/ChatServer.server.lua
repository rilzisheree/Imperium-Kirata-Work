local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

ChatRemotes.MessageSent.OnServerEvent:Connect(function(sender: Player, rawText: string)
	if typeof(rawText) ~= "string" then return end
	broadcastProximity(sender, rawText)
end)

-- fallback for legacy .Chatted
Players.PlayerAdded:Connect(function(player: Player)
	player.Chatted:Connect(function(message: string)
		broadcastProximity(player, message)
	end)
end)
