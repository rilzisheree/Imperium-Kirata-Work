-- Permission authority for all admin commands and staff-only chat features.
-- Driven by the player's role NAME in the configured Roblox group, not rank
-- numbers — several roles share rank 1 in the group's settings so rank
-- thresholds can't tell them apart. Role names map to explicit command sets,
-- so promotions/demotions take effect on next join without a republish.
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local PermissionManager = {}

local GROUP_ID  = 33351111
local IS_STUDIO = RunService:IsStudio()

-- Bypass for e.g. the game creator testing outside the group, or a safety
-- net if the group API goes down.
local OVERRIDE_USER_IDS: { [number]: boolean } = {
	[1872507151] = true,
}

-- Sentinel meaning "every command" — used for top-tier roles so newly added
-- commands are automatically covered without touching this file.
local ALL = "ALL"

local function newSet(list: { string }): { [string]: boolean }
	local set = {}
	for _, v in list do set[v] = true end
	return set
end

local function addAll(set: { [string]: boolean }, list: { string })
	for _, v in list do set[v] = true end
end

local TRIAL_MODERATOR_COMMANDS = {
	"sm", "notif", "helpui", "blind", "unblind", "re", "respawn", "heal",
	"damage", "freeze", "unfreeze", "kick", "esp", "staffmode", "to", "bring",
	"tp", "watch", "unwatch", "fly",
}

local MODERATOR_ADDITIONS = {
	"unfly", "invis", "uninvis", "anxiety", "createcorpse", "music",
	"setworldspawn", "countdown", "stopcountdown", "setwaypoint", "clearwaypoints",
}

local ADMINISTRATOR_ADDITIONS = {
	"place", "privateserver", "serverbring", "serverjoin", "shutdown",
}

local TRIAL_MODERATOR = newSet(TRIAL_MODERATOR_COMMANDS)

local MODERATOR = newSet(TRIAL_MODERATOR_COMMANDS)
addAll(MODERATOR, MODERATOR_ADDITIONS)

local ADMINISTRATOR = newSet(TRIAL_MODERATOR_COMMANDS)
addAll(ADMINISTRATOR, MODERATOR_ADDITIONS)
addAll(ADMINISTRATOR, ADMINISTRATOR_ADDITIONS)

-- Roles not listed here (Guest, Member, Tester, etc.) get no staff commands.
-- "im", "accesslanguage", and anything else not listed under a tier above are
-- intentionally reserved for the ALL tier — confirmed with the dev, not an oversight.
local ROLE_COMMANDS: { [string]: { [string]: boolean } | string } = {
	["Trial Moderator"]     = TRIAL_MODERATOR,
	["Moderator"]            = MODERATOR,
	["Administrator"]        = ADMINISTRATOR,
	["Senior Administrator"] = ALL,
	["Lore Team"]            = ALL,
	["Senior Lore Team"]     = ALL,
	["Executive"]            = ALL,
	["Owner"]                = ALL,
}

local cache: { [number]: { [string]: boolean } | string | false } = {}

local function resolve(player: Player): { [string]: boolean } | string | false
	if IS_STUDIO then return ALL end
	if OVERRIDE_USER_IDS[player.UserId] then return ALL end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return ALL
	end

	local ok, roleName = pcall(function()
		return player:GetRoleInGroup(GROUP_ID)
	end)
	if not ok then
		warn("[PermissionManager] GetRoleInGroup failed for", player.Name, "| error:", tostring(roleName))
		return false
	end

	return ROLE_COMMANDS[roleName] or false
end

function PermissionManager.refresh(player: Player)
	cache[player.UserId] = resolve(player)
end

local function getAllowed(player: Player): { [string]: boolean } | string | false
	local cached = cache[player.UserId]
	if cached == nil then
		-- not cached yet (checked before the async join-time refresh finished)
		cached = resolve(player)
		cache[player.UserId] = cached
	end
	return cached
end

function PermissionManager.canUseCommand(player: Player, commandName: string): boolean
	local allowed = getAllowed(player)
	if allowed == ALL then return true end
	if allowed == false then return false end
	return (allowed :: { [string]: boolean })[commandName] == true
end

-- true if the player has any staff role at all — used for staff-only chat
-- features that aren't tied to a specific command
function PermissionManager.isStaff(player: Player): boolean
	local allowed = getAllowed(player)
	if allowed == false then return false end
	if allowed == ALL then return true end
	for _ in allowed do return true end
	return false
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(PermissionManager.refresh, player)
end)

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

-- handles players already in-game when this module loads (Studio / hot-reload)
for _, player in Players:GetPlayers() do
	if cache[player.UserId] == nil then
		task.spawn(PermissionManager.refresh, player)
	end
end

return PermissionManager
