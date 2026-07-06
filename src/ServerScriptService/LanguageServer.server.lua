--[[
	LanguageServer.server.lua
	Script — ServerScriptService

	Handles player lifecycle for the language system and the LanguageSelect
	remote (client notifying the server of a language change).

	Responsibilities:
	  • Load each player's granted languages from DataStore on join.
	  • Push the grants list to the player's client so the CommandBar and
	    LanguageMenu stay in sync.
	  • Accept LanguageSelect events from clients and update the in-memory
	    selected language (validated against the player's grants).
	  • Clean up state when a player leaves.
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommandRemotes  = require(ReplicatedStorage:WaitForChild("CommandRemotes"))
local LanguageManager = require(script.Parent:WaitForChild("LanguageManager") :: ModuleScript)

-- ── Player lifecycle ───────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	-- Yields until the DataStore load completes; grants are ready after this.
	LanguageManager.onPlayerAdded(player)
	local grants = LanguageManager.getGrants(player.UserId)
	CommandRemotes.LanguageGrants:FireClient(player, grants)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player: Player)
	LanguageManager.onPlayerRemoving(player)
end)

-- Handle players who joined before this script finished loading (edge case in
-- Studio testing when scripts run out of order).
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- ── LanguageSelect remote ──────────────────────────────────────────────────────
-- Client fires this when the player picks a language (or "None") in the menu.

CommandRemotes.LanguageSelect.OnServerEvent:Connect(function(player: Player, langName: string)
	if typeof(langName) ~= "string" then return end
	langName = langName:match("^%s*(.-)%s*$") or ""

	if langName == "" then
		-- "None" — return player to English
		LanguageManager.setSelected(player.UserId, nil)
		return
	end

	-- Validate: only allow selecting a language the player has been granted.
	-- (Guards against exploits; the client should never send an ungranted language.)
	local grants = LanguageManager.getGrants(player.UserId)
	local canonical = nil
	for _, g in ipairs(grants) do
		if g:lower() == langName:lower() then
			canonical = g
			break
		end
	end
	if canonical then
		LanguageManager.setSelected(player.UserId, canonical)
	end
end)
