-- Central permission authority for admin commands and staff-only chat
-- features (e.g. the /t "Thoughts" channel in ChatServer.server.lua).
--
-- Permissions are driven by the player's ROLE NAME in the configured Roblox
-- group, not a hardcoded per-user list. Promotions/demotions inside the
-- group take effect on a player's next join without republishing the game.
--
-- This is deliberately NOT a numeric rank hierarchy ("rank >= N"): several of
-- this group's roles (Administrator, Moderator, Trial Moderator, etc.) all
-- happen to share rank 1 in the group's settings, so rank thresholds can't
-- tell them apart. Role *names* are the source of truth instead, and each
-- name maps to an explicit set of commands it unlocks.
local Players    = game:GetService("Players")
local RunService  = game:GetService("RunService")

local PermissionManager = {}

local GROUP_ID   = 33351111
local IS_STUDIO  = RunService:IsStudio()

-- Always grants full access regardless of group standing. Use sparingly --
-- e.g. the game creator testing outside the group, or a safety net if the
-- group API is ever unavailable.
local OVERRIDE_USER_IDS: { [number]: boolean } = {
	[1872507151] = true,
}

-- Sentinel meaning "every command" -- used instead of enumerating every
-- command key, so newly added commands are automatically covered for
-- top-tier roles without updating this module.
local ALL = "ALL"

local function newSet(list: { string }): { [string]: boolean }
	local set = {}
	for _, v in list do
		set[v] = true
	end
	return set
end

local function addAll(set: { [string]: boolean }, list: { string })
	for _, v in list do
		set[v] = true
	end
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

-- Maps a Roblox group role NAME to the command set that role unlocks.
-- Roles not listed here (Guest, Member, Tester, or anything renamed in the
-- group later) get no staff commands at all.
--
-- "im" (private message) and "accesslanguage" (grant language access), and
-- anything else not listed under Trial Moderator / Moderator / Administrator
-- above, are intentionally reserved for the ALL tier below -- confirmed with
-- the dev, not an oversight.
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

-- [userId] = command set / ALL / false (no staff commands)
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

-- Populates (or repopulates) the cache for a player. Safe to call again
-- later if you add a way to force a refresh without a rejoin.
function PermissionManager.refresh(player: Player)
	cache[player.UserId] = resolve(player)
end

local function getAllowed(player: Player): { [string]: boolean } | string | false
	local cached = cache[player.UserId]
	if cached == nil then
		-- Not cached yet (e.g. checked before the async join-time refresh
		-- finished) -- resolve synchronously this one time.
		cached = resolve(player)
		cache[player.UserId] = cached
	end
	return cached
end

-- True if `player` is allowed to run `commandName`.
function PermissionManager.canUseCommand(player: Player, commandName: string): boolean
	local allowed = getAllowed(player)
	if allowed == ALL then return true end
	if allowed == false then return false end
	return (allowed :: { [string]: boolean })[commandName] == true
end

-- True if `player` has ANY staff role at all. Used for staff-only chat
-- features (like the /t Thoughts channel) that aren't tied to one specific
-- command.
function PermissionManager.isStaff(player: Player): boolean
	local allowed = getAllowed(player)
	if allowed == false then return false end
	if allowed == ALL then return true end
	for _ in allowed do
		return true
	end
	return false
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(PermissionManager.refresh, player)
end)

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

-- Handles players already connected when this module first loads (Studio
-- edge case, or a hot-reload during development).
for _, player in Players:GetPlayers() do
	if cache[player.UserId] == nil then
		task.spawn(PermissionManager.refresh, player)
	end
end

return PermissionManager
