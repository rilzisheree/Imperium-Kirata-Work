local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommandRemotes  = require(ReplicatedStorage:WaitForChild("CommandRemotes"))
local LanguageManager = require(script.Parent:WaitForChild("LanguageManager") :: ModuleScript)

local function onPlayerAdded(player: Player)
	LanguageManager.onPlayerAdded(player)
	local grants = LanguageManager.getGrants(player.UserId)
	CommandRemotes.LanguageGrants:FireClient(player, grants)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player: Player)
	LanguageManager.onPlayerRemoving(player)
end)

-- catch anyone who joined before this script loaded
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

CommandRemotes.LanguageSelect.OnServerEvent:Connect(function(player: Player, langName: string)
	if typeof(langName) ~= "string" then return end
	langName = langName:match("^%s*(.-)%s*$") or ""

	if langName == "" then
		-- "None" — return player to English
		LanguageManager.setSelected(player.UserId, nil)
		return
	end

	local grants = LanguageManager.getGrants(player.UserId)
	local canonical
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
