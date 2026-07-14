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
local CommandRemotes  = require(ReplicatedStorage:WaitForChild("CommandRemotes") :: ModuleScript)
local LanguageManager = require(script.Parent:WaitForChild("LanguageManager") :: ModuleScript)
local LanguageData    = require(ReplicatedStorage:WaitForChild("LanguageData") :: ModuleScript)
local FilterState     = require(script.Parent:WaitForChild("FilterState") :: ModuleScript)

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

-- Phase 1: get a TextFilterResult from Roblox (returns nil on failure).
local function getFilterResult(sender: Player, text: string): any?
	local ok2, result = pcall(function()
		return TextService:FilterStringAsync(text, sender.UserId)
	end)
	return ok2 and result or nil
end

-- Phase 2: get text filtered for one specific recipient (returns nil on failure).
local function getFilteredForRecipient(filterResult: any, recipientUserId: number): string?
	local ok2, result = pcall(function()
		return filterResult:GetChatForUserAsync(recipientUserId)
	end)
	if ok2 and type(result) == "string" then return result end
	return nil
end

-- Notify the sender that their message could not be delivered.
local function notifyFilterFailure(sender: Player)
	CommandRemotes.CommandFeedback:FireClient(sender, false, "Your message could not be delivered.")
end

-- Capitalises the first letter and appends a period when the message has no ending punctuation.
local function formatText(text: string): string
	if text == "" then return text end
	text = text:sub(1, 1):upper() .. text:sub(2)
	local last = text:sub(-1)
	if last ~= "." and last ~= "!" and last ~= "?" and text:sub(-3) ~= "…" then
		text = text .. "."
	end
	return text
end

-- Builds the payload fields shared by all three broadcast paths.
local function makeBase(sender: Player): { [string]: any }
	local nameColor = getNameColor(sender)
	local team      = sender.Team
	local teamColor = team and team.TeamColor.Color or Color3.new(0.8, 0.8, 0.8)
	return {
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
end

local function broadcastProximity(sender: Player, rawText: string)
	local text = rawText:match("^%s*(.-)%s*$")
	if text == "" then return end
	if #text > MAX_MESSAGE_LENGTH then
		text = text:sub(1, MAX_MESSAGE_LENGTH) .. "…"
	end
	text = formatText(text)

	local bypass = FilterState.filterBypass[sender.UserId]
	local filterResult = nil
	if not bypass then
		filterResult = getFilterResult(sender, text)
		if not filterResult then
			notifyFilterFailure(sender)
			return
		end
	end

	local base         = makeBase(sender)
	local selectedLang = LanguageManager.getSelected(sender.UserId)
	local langDef      = selectedLang and LanguageData.BY_NAME[selectedLang:lower()]

	for _, player in Players:GetPlayers() do
		local filteredText
		if bypass then
			filteredText = text
		else
			filteredText = getFilteredForRecipient(filterResult, player.UserId)
			if not filteredText then continue end
		end

		local payload = table.clone(base)
		if not langDef then
			payload.message = filteredText
		else
			local pSel        = LanguageManager.getSelected(player.UserId)
			local understands = (pSel ~= nil and pSel:lower() == selectedLang:lower())
			                    or LanguageManager.hasGrant(player.UserId, selectedLang)
			if understands then
				payload.message = "[" .. langDef.tag .. "] " .. filteredText
			else
				payload.message = LanguageManager.fictionalise(filteredText, langDef.name)
			end
		end
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

	local bypass = FilterState.filterBypass[sender.UserId]
	local filterResult = nil
	if not bypass then
		filterResult = getFilterResult(sender, text)
		if not filterResult then
			notifyFilterFailure(sender)
			return
		end
	end

	local base         = makeBase(sender)
	base.isThought     = true
	local selectedLang = LanguageManager.getSelected(sender.UserId)
	local langDef      = selectedLang and LanguageData.BY_NAME[selectedLang:lower()]

	for _, player in Players:GetPlayers() do
		if player ~= sender and not isAdmin(player) then continue end

		local filteredText
		if bypass then
			filteredText = text
		else
			filteredText = getFilteredForRecipient(filterResult, player.UserId)
			if not filteredText then continue end
		end

		local payload = table.clone(base)
		if not langDef then
			payload.message = filteredText
		else
			local pSel        = LanguageManager.getSelected(player.UserId)
			local understands = (pSel ~= nil and pSel:lower() == selectedLang:lower())
			                    or LanguageManager.hasGrant(player.UserId, selectedLang)
			if understands then
				payload.message = "[" .. langDef.tag .. "] " .. filteredText
			else
				payload.message = LanguageManager.fictionalise(filteredText, langDef.name)
			end
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

	local bypass = FilterState.filterBypass[sender.UserId]
	local filterResult = nil
	if not bypass then
		filterResult = getFilterResult(sender, text)
		if not filterResult then
			notifyFilterFailure(sender)
			return
		end
	end

	local base         = makeBase(sender)
	base.isWhisper     = true
	local selectedLang = LanguageManager.getSelected(sender.UserId)
	local langDef      = selectedLang and LanguageData.BY_NAME[selectedLang:lower()]

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

		local filteredText
		if bypass then
			filteredText = text
		else
			filteredText = getFilteredForRecipient(filterResult, player.UserId)
			if not filteredText then continue end
		end

		local payload = table.clone(base)
		if not langDef then
			payload.message = filteredText
		else
			local pSel        = LanguageManager.getSelected(player.UserId)
			local understands = (pSel ~= nil and pSel:lower() == selectedLang:lower())
			                    or LanguageManager.hasGrant(player.UserId, selectedLang)
			if understands then
				payload.message = "[" .. langDef.tag .. "] " .. filteredText
			else
				payload.message = LanguageManager.fictionalise(filteredText, langDef.name)
			end
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
