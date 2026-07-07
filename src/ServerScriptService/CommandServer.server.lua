local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")

local CommandRemotes  = require(ReplicatedStorage:WaitForChild("CommandRemotes")  :: ModuleScript)
local CommandRegistry = require(ReplicatedStorage:WaitForChild("CommandRegistry") :: ModuleScript)
local CorpseFactory   = require(script.Parent:WaitForChild("CorpseFactory")       :: ModuleScript)
local LanguageManager = require(script.Parent:WaitForChild("LanguageManager")     :: ModuleScript)
local LanguageData    = require(ReplicatedStorage:WaitForChild("LanguageData")    :: ModuleScript)

local Workspace = game:GetService("Workspace")

local IS_STUDIO = RunService:IsStudio()

local STAFF_IDS = {
        [1872507151] = "Owner",
}

local TIER_ORDER = { Helper = 1, Moderator = 2, Admin = 3, Owner = 4 }

local function getTier(player: Player): string?
        if IS_STUDIO then return "Owner" end
        if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
                return "Owner"
        end
        return STAFF_IDS[player.UserId]
end

local function hasPermission(player: Player, required: string): boolean
        if required == "Everyone" then return true end
        local tier = getTier(player)
        if not tier then return false end
        return (TIER_ORDER[tier] or 0) >= (TIER_ORDER[required] or 99)
end

local function ok(player: Player, msg: string)
        CommandRemotes.CommandFeedback:FireClient(player, true, msg)
end

local function fail(player: Player, msg: string)
        CommandRemotes.CommandFeedback:FireClient(player, false, msg)
end

-- per-admin preference: whether they currently want to see help request notifications
local helpUIEnabled = {}

-- active countdown: stores the DistributedGameTime at which the countdown ends, or nil
local countdownEndTime = nil

-- active waypoints: userId -> Vector3 world position
local activeWaypoints = {}

Players.PlayerRemoving:Connect(function(player)
        helpUIEnabled[player.UserId] = nil
        activeWaypoints[player.UserId] = nil
end)

-- push the player's permission tier to their client on join so CommandBar
-- knows which commands to show in autocomplete
local function pushPermissions(player: Player)
        local tier = getTier(player) or "Everyone"
        CommandRemotes.Permissions:FireClient(player, tier)
end

Players.PlayerAdded:Connect(function(player)
        pushPermissions(player)

        -- sync an active countdown to players who join mid-countdown
        if countdownEndTime ~= nil then
                local remaining = countdownEndTime - Workspace.DistributedGameTime
                if remaining > 0.5 then
                        CommandRemotes.CountdownStart:FireClient(player, countdownEndTime)
                end
        end
end)

-- handle players already connected when this script loads (Studio edge case)
for _, player in Players:GetPlayers() do
        task.spawn(pushPermissions, player)
end

-- if the last word of a message is a colour name, strip it and return it separately
local COLOUR_NAMES = {
        red=true, blue=true, green=true, yellow=true, orange=true,
        purple=true, pink=true, white=true, cyan=true, lime=true,
}

local function stripColour(msg: string): (string, string?)
        local lastWord = msg:match("(%S+)%s*$")
        if lastWord and COLOUR_NAMES[lastWord:lower()] then
                local stripped = msg:match("^(.-)%s*%S+%s*$") or ""
                return stripped, lastWord:lower()
        end
        return msg, nil
end

local function resolvePlayer(executor: Player, name: string): Player?
        if name:lower() == "me" then return executor end
        local lower = name:lower()
        for _, p in Players:GetPlayers() do
                if p.Name:lower() == lower or p.DisplayName:lower() == lower then
                        return p
                end
        end
        -- fallback: prefix match
        for _, p in Players:GetPlayers() do
                if p.Name:lower():sub(1, #lower) == lower then return p end
        end
        return nil
end

-- returns a list of players; "all" targets everyone, otherwise resolves by name
local function resolveTargets(executor: Player, name: string): { Player }?
        if name:lower() == "all" then
                return Players:GetPlayers()
        end
        local target = resolvePlayer(executor, name)
        if not target then return nil end
        return { target }
end

local function joinArgs(args: { string }, from: number): string
        local parts = {}
        for i = from, #args do table.insert(parts, args[i]) end
        return table.concat(parts, " ")
end

local HANDLERS = {}

HANDLERS["sm"] = function(executor, args)
        local raw = joinArgs(args, 1)
        if raw == "" then fail(executor, "Usage: sm <message> [colour]") return end
        local msg, colour = stripColour(raw)
        if msg == "" then msg = raw; colour = nil end
        for _, player in Players:GetPlayers() do
                CommandRemotes.SM:FireClient(player, msg, colour)
        end
        ok(executor, 'Server message sent: "' .. msg .. '"' .. (colour and " (" .. colour .. ")" or ""))
end

HANDLERS["im"] = function(executor, args)
        if #args < 2 then fail(executor, "Usage: im <player|all> <message> [colour]") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
        local raw = joinArgs(args, 2)
        if raw == "" then fail(executor, "Usage: im <player|all> <message> [colour]") return end
        local msg, colour = stripColour(raw)
        if msg == "" then msg = raw; colour = nil end
        for _, target in targets do
                CommandRemotes.IM:FireClient(target, msg, colour)
        end
        local recipient = #targets == 1 and targets[1].DisplayName or "everyone"
        ok(executor, 'Message sent to ' .. recipient .. ': "' .. msg .. '"' .. (colour and " (" .. colour .. ")" or ""))
end

HANDLERS["anxiety"] = function(executor, args)
        if #args < 2 then fail(executor, "Usage: anxiety <player|all> <level 1-5>") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
        local level = tonumber(args[2])
        if not level or level < 1 or level > 5 then
                fail(executor, "Level must be 1–5.")
                return
        end
        level = math.round(level)
        for _, target in targets do
                CommandRemotes.Anxiety:FireClient(target, level)
        end
        local recipient = #targets == 1 and targets[1].DisplayName or "everyone"
        ok(executor, "Anxiety level " .. level .. " triggered on " .. recipient .. ".")
end

HANDLERS["blind"] = function(executor, args)
        if #args < 1 then fail(executor, "Usage: blind <player|all> [duration 1-120]") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
        local duration = 0
        if args[2] then
                local d = tonumber(args[2])
                if not d or d < 1 or d > 120 then
                        fail(executor, "Duration must be 1–120 seconds.")
                        return
                end
                duration = math.floor(d)
        end
        for _, target in targets do
                CommandRemotes.Blind:FireClient(target, duration)
        end
        local recipient = #targets == 1 and targets[1].DisplayName or "everyone"
        if duration > 0 then
                ok(executor, "Blinding " .. recipient .. " over " .. duration .. "s.")
        else
                ok(executor, "Blinded " .. recipient .. ".")
        end
end

HANDLERS["unblind"] = function(executor, args)
        if #args < 1 then fail(executor, "Usage: unblind <player|all>") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
        for _, target in targets do
                CommandRemotes.Unblind:FireClient(target)
        end
        local recipient = #targets == 1 and targets[1].DisplayName or "everyone"
        ok(executor, "Unblinded " .. recipient .. ".")
end

HANDLERS["createcorpse"] = function(executor, args)
        if #args < 1 then fail(executor, "Usage: createcorpse <player|all> [lifetime seconds]") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

        local lifetime = nil
        if args[2] then
                local n = tonumber(args[2])
                if not n or n < CorpseFactory.MIN_LIFETIME or n > CorpseFactory.MAX_LIFETIME then
                        fail(executor, "Lifetime must be " .. CorpseFactory.MIN_LIFETIME .. "–" .. CorpseFactory.MAX_LIFETIME .. " seconds.")
                        return
                end
                lifetime = math.floor(n)
        end

        local created, failures = {}, {}
        for _, target in targets do
                local success, result = CorpseFactory.Create(target, lifetime)
                if success then
                        table.insert(created, result)
                else
                        table.insert(failures, result)
                end
        end

        if #created == 0 then
                fail(executor, "No corpses created: " .. table.concat(failures, "; ") .. ".")
                return
        end

        local msg = "Created corpse for " .. table.concat(created, ", ") .. "."
        if #failures > 0 then
                msg = msg .. " (" .. #failures .. " skipped: " .. table.concat(failures, "; ") .. ")"
        end
        ok(executor, msg)
end

-- reloads a single player's character in place, preserving their position,
-- orientation, and health where possible
local function refreshPlayer(target: Player): (boolean, string)
        local character = target.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not rootPart then
                return false, target.DisplayName .. " has no character to refresh"
        end

        local savedCFrame = rootPart.CFrame
        local oldHumanoid  = character:FindFirstChildOfClass("Humanoid")
        local savedHealth  = oldHumanoid and oldHumanoid.Health or nil

        target:LoadCharacter()

        local newCharacter = target.Character
        if not newCharacter then
                return false, target.DisplayName .. "'s character failed to reload"
        end

        local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
        if not newRoot then
                return false, target.DisplayName .. "'s character didn't finish loading in time"
        end

        newCharacter:PivotTo(savedCFrame)

        if savedHealth then
                local newHumanoid = newCharacter:FindFirstChildOfClass("Humanoid")
                if newHumanoid then
                        newHumanoid.Health = math.clamp(savedHealth, 0, newHumanoid.MaxHealth)
                end
        end

        return true, target.DisplayName
end

-- finds the world's default spawn point (first enabled SpawnLocation in the workspace)
local function findSpawnLocation(): BasePart?
        for _, inst in Workspace:GetDescendants() do
                if inst:IsA("SpawnLocation") and inst.Enabled then
                        return inst
                end
        end
        return nil
end

-- reloads a single player's character and places it at the default spawn location
local function respawnPlayer(target: Player, spawn: BasePart?): (boolean, string)
        target:LoadCharacter()

        local newCharacter = target.Character
        if not newCharacter then
                return false, target.DisplayName .. "'s character failed to reload"
        end

        local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?
        if not newRoot then
                return false, target.DisplayName .. "'s character didn't finish loading in time"
        end

        if spawn then
                newCharacter:PivotTo(spawn.CFrame + Vector3.new(0, 5, 0))
        end

        return true, target.DisplayName
end

HANDLERS["respawn"] = function(executor, args)
        if #args < 1 then fail(executor, "Usage: respawn <player|all>") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

        local spawn = findSpawnLocation()

        local respawned, failures = {}, {}
        local remaining = #targets

        for _, target in targets do
                task.spawn(function()
                        local success, result = respawnPlayer(target, spawn)
                        if success then
                                table.insert(respawned, result)
                        else
                                table.insert(failures, result)
                        end
                        remaining -= 1
                end)
        end

        while remaining > 0 do
                task.wait()
        end

        if #respawned == 0 then
                fail(executor, "No players respawned: " .. table.concat(failures, "; ") .. ".")
                return
        end

        local msg = "Respawned " .. table.concat(respawned, ", ") .. "."
        if #failures > 0 then
                msg = msg .. " (" .. #failures .. " skipped: " .. table.concat(failures, "; ") .. ")"
        end
        if not spawn then
                msg = msg .. " (no SpawnLocation found; used default spawn behaviour)"
        end
        ok(executor, msg)
end

HANDLERS["re"] = function(executor, args)
        if #args < 1 then fail(executor, "Usage: re <player|all>") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

        local refreshed, failures = {}, {}
        local remaining = #targets

        for _, target in targets do
                task.spawn(function()
                        local success, result = refreshPlayer(target)
                        if success then
                                table.insert(refreshed, result)
                        else
                                table.insert(failures, result)
                        end
                        remaining -= 1
                end)
        end

        while remaining > 0 do
                task.wait()
        end

        if #refreshed == 0 then
                fail(executor, "No players refreshed: " .. table.concat(failures, "; ") .. ".")
                return
        end

        local msg = "Refreshed " .. table.concat(refreshed, ", ") .. "."
        if #failures > 0 then
                msg = msg .. " (" .. #failures .. " skipped: " .. table.concat(failures, "; ") .. ")"
        end
        ok(executor, msg)
end

HANDLERS["help"] = function(executor, args)
        local message = joinArgs(args, 1)
        if message == "" then
                fail(executor, "Usage: help <message>")
                return
        end

        local team      = executor.Team
        local teamName  = team and team.Name or "No Team"
        local teamColor = team and team.TeamColor.Color or Color3.fromRGB(200, 200, 200)

        local payload = {
                requestId       = HttpService:GenerateGUID(false),
                fromUserId      = executor.UserId,
                fromName        = executor.Name,
                fromDisplayName = executor.DisplayName,
                teamName        = teamName,
                teamColor       = teamColor,
                message         = message,
        }

        for _, player in Players:GetPlayers() do
                if hasPermission(player, "Admin") and helpUIEnabled[player.UserId] ~= false then
                        CommandRemotes.HelpRequest:FireClient(player, payload)
                end
        end

        ok(executor, "Help request sent.")
end

HANDLERS["weather"] = function(executor, args)
        CommandRemotes.WeatherOpen:FireClient(executor)
        ok(executor, "Weather panel toggled.")
end

HANDLERS["notif"] = function(executor, args)
        if #args < 2 then fail(executor, "Usage: notif <player|all> <message>") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
        local msg = joinArgs(args, 2)
        if msg == "" then fail(executor, "Usage: notif <player|all> <message>") return end
        for _, target in targets do
                CommandRemotes.Notif:FireClient(target, msg, executor.Name)
        end
        local recipient = #targets == 1 and targets[1].DisplayName or "everyone"
        ok(executor, 'Notification sent to ' .. recipient .. ': "' .. msg .. '"')
end

HANDLERS["helpui"] = function(executor, args)
        local uid     = executor.UserId
        local current = helpUIEnabled[uid]
        if current == nil then current = true end
        local newState = not current
        helpUIEnabled[uid] = newState

        CommandRemotes.HelpUIToggle:FireClient(executor, newState)
        ok(executor, "Help request notifications " .. (newState and "enabled" or "disabled") .. ".")
end

HANDLERS["countdown"] = function(executor, args)
        if #args < 1 then fail(executor, "Usage: countdown <seconds>") return end
        local seconds = tonumber(args[1])
        if not seconds or seconds < 1 or seconds > 3600 then
                fail(executor, "Seconds must be 1–3600.")
                return
        end
        seconds = math.floor(seconds)

        local myEndTime = Workspace.DistributedGameTime + seconds
        countdownEndTime = myEndTime

        for _, player in Players:GetPlayers() do
                CommandRemotes.CountdownStart:FireClient(player, myEndTime)
        end

        -- clear the server-side record once the countdown has expired
        task.delay(seconds + 1, function()
                if countdownEndTime == myEndTime then
                        countdownEndTime = nil
                end
        end)

        ok(executor, "Countdown of " .. seconds .. "s started.")
end

HANDLERS["stopcountdown"] = function(executor, args)
        if countdownEndTime == nil then
                fail(executor, "No countdown is currently running.")
                return
        end
        countdownEndTime = nil
        for _, player in Players:GetPlayers() do
                CommandRemotes.CountdownStop:FireClient(player)
        end
        ok(executor, "Countdown stopped.")
end

HANDLERS["language"] = function(executor, args)
        local grants = LanguageManager.getGrants(executor.UserId)
        if #grants == 0 then
                fail(executor, "You have not been granted any languages.")
                return
        end
        CommandRemotes.LanguageOpen:FireClient(executor)
        ok(executor, "Language menu opened.")
end

-- computes a safe landing CFrame a few studs in front of anchorRoot,
-- spreading index/total players laterally so they don't overlap.
-- excludeModel is filtered out of the floor raycast (typically the anchor's character).
local FORWARD_DIST = 4   -- studs ahead of the anchor
local LATERAL_STEP = 3   -- studs between players when multiple are placed

local function nearPlayerCFrame(
	anchorRoot:   BasePart,
	excludeModel: Model?,
	index:        number,
	total:        number
): CFrame
	local anchorPos     = anchorRoot.Position
	local anchorCFrame  = anchorRoot.CFrame
	local forward       = anchorCFrame.LookVector
	local right         = anchorCFrame.RightVector

	local lateralOffset = (index - (total + 1) / 2) * LATERAL_STEP
	local flatPos       = anchorPos + forward * FORWARD_DIST + right * lateralOffset

	local rayParams = RaycastParams.new()
	if excludeModel then
		rayParams.FilterDescendantsInstances = { excludeModel }
		rayParams.FilterType                 = Enum.RaycastFilterType.Exclude
	end
	local result  = Workspace:Raycast(flatPos + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0), rayParams)
	local groundY = result and (result.Position.Y + 3) or anchorPos.Y

	local dest = Vector3.new(flatPos.X, groundY, flatPos.Z)
	return CFrame.lookAt(dest, Vector3.new(anchorPos.X, groundY, anchorPos.Z))
end

-- waits for a player's character and HumanoidRootPart (handles mid-spawn),
-- then teleports them to destCFrame. Returns (success, displayName or reason).
local function bringPlayer(target: Player, destCFrame: CFrame): (boolean, string)
	local character = target.Character

	if not character then
		local elapsed = 0
		repeat
			task.wait(0.1)
			elapsed += 0.1
			character = target.Character
		until character or elapsed >= 5
	end
	if not character then
		return false, target.DisplayName .. " has no character"
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	end
	if not root then
		return false, target.DisplayName .. "'s character didn't finish loading in time"
	end

	character:PivotTo(destCFrame)
	return true, target.DisplayName
end

-- waits for a player's character and HumanoidRootPart; returns the root or nil.
local function waitForRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		local elapsed = 0
		repeat
			task.wait(0.1)
			elapsed += 0.1
			character = player.Character
		until character or elapsed >= 5
	end
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	end
	return root :: BasePart?
end

HANDLERS["fly"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: fly <player|all> [speed]") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local speed = nil
	if args[2] then
		local n = tonumber(args[2])
		if not n or n < 1 or n > 500 then
			fail(executor, "Speed must be 1–500.")
			return
		end
		speed = math.floor(n)
	end

	for _, target in targets do
		CommandRemotes.FlyEnable:FireClient(target, speed)
	end
	local recipient  = #targets == 1 and targets[1].DisplayName or "everyone"
	local speedNote  = speed and (" at speed " .. speed) or ""
	ok(executor, "Flight enabled for " .. recipient .. speedNote .. ".")
end

HANDLERS["unfly"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: unfly <player|all>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
	for _, target in targets do
		CommandRemotes.FlyDisable:FireClient(target)
	end
	local recipient = #targets == 1 and targets[1].DisplayName or "everyone"
	ok(executor, "Flight disabled for " .. recipient .. ".")
end

HANDLERS["to"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: to <player>") return end
	local target = resolvePlayer(executor, args[1])
	if not target then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
	if target == executor then fail(executor, "You are already there.") return end

	-- ensure executor's character is ready
	local adminChar = executor.Character
	local adminRoot = adminChar and adminChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not adminRoot then
		fail(executor, "Your character is not available.")
		return
	end

	-- wait for the target's character/root if mid-spawn
	local targetRoot = waitForRoot(target)
	if not targetRoot then
		fail(executor, target.DisplayName .. "'s character is not available.")
		return
	end

	local destCFrame = nearPlayerCFrame(targetRoot, targetRoot.Parent :: Model, 1, 1)
	adminChar:PivotTo(destCFrame)
	ok(executor, "Teleported to " .. target.DisplayName .. ".")
end

HANDLERS["tp"] = function(executor, args)
	if #args < 2 then fail(executor, "Usage: tp <player|all> <player>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
	local dest = resolvePlayer(executor, args[2])
	if not dest then fail(executor, 'Player "' .. args[2] .. '" not found.') return end

	-- cannot teleport a player to themselves
	local actualTargets = {}
	for _, t in targets do
		if t ~= dest then table.insert(actualTargets, t) end
	end
	if #actualTargets == 0 then
		fail(executor, "Cannot teleport a player to themselves.")
		return
	end

	-- resolve destination root once and snapshot it
	local destRoot = waitForRoot(dest)
	if not destRoot then
		fail(executor, dest.DisplayName .. "'s character is not available.")
		return
	end
	local destChar = destRoot.Parent :: Model

	-- pre-calculate all landing CFrames from the snapshot
	local destCFrames = {}
	for i in actualTargets do
		destCFrames[i] = nearPlayerCFrame(destRoot, destChar, i, #actualTargets)
	end

	local brought, failures = {}, {}
	local remaining = #actualTargets

	for i, target in actualTargets do
		task.spawn(function()
			local success, result = bringPlayer(target, destCFrames[i])
			if success then
				table.insert(brought, result)
			else
				table.insert(failures, result)
			end
			remaining -= 1
		end)
	end

	while remaining > 0 do task.wait() end

	if #brought == 0 then
		fail(executor, "No players teleported: " .. table.concat(failures, "; ") .. ".")
		return
	end

	local msg = "Teleported " .. table.concat(brought, ", ") .. " to " .. dest.DisplayName .. "."
	if #failures > 0 then
		msg = msg .. " (" .. #failures .. " skipped: " .. table.concat(failures, "; ") .. ")"
	end
	ok(executor, msg)
end

HANDLERS["bring"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: bring <player|all>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	-- executor cannot bring themselves
	local actualTargets = {}
	for _, t in targets do
		if t ~= executor then table.insert(actualTargets, t) end
	end
	if #actualTargets == 0 then
		fail(executor, "You cannot bring yourself.")
		return
	end

	local adminChar = executor.Character
	local adminRoot = adminChar and adminChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not adminRoot then
		fail(executor, "Your character is not available.")
		return
	end

	-- pre-calculate all landing CFrames from a snapshot of the admin's position
	local destCFrames = {}
	for i in actualTargets do
		destCFrames[i] = nearPlayerCFrame(adminRoot, adminChar, i, #actualTargets)
	end

	local brought, failures = {}, {}
	local remaining = #actualTargets

	for i, target in actualTargets do
		task.spawn(function()
			local success, result = bringPlayer(target, destCFrames[i])
			if success then
				table.insert(brought, result)
			else
				table.insert(failures, result)
			end
			remaining -= 1
		end)
	end

	while remaining > 0 do task.wait() end

	if #brought == 0 then
		fail(executor, "No players brought: " .. table.concat(failures, "; ") .. ".")
		return
	end

	local msg = "Brought " .. table.concat(brought, ", ") .. "."
	if #failures > 0 then
		msg = msg .. " (" .. #failures .. " skipped: " .. table.concat(failures, "; ") .. ")"
	end
	ok(executor, msg)
end

HANDLERS["setwaypoint"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: setwaypoint <player|all> [title]") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local character = executor.Character
	local rootPart  = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		fail(executor, "Could not determine your position.")
		return
	end
	local pos   = rootPart.Position
	local title = joinArgs(args, 2)  -- empty string if no title given

	for _, target in targets do
		activeWaypoints[target.UserId] = pos
		CommandRemotes.WaypointSet:FireClient(target, pos, title)
	end

	local recipient = #targets == 1 and targets[1].DisplayName or "everyone"
	local titleNote = title ~= "" and ' ("' .. title .. '")' or ""
	ok(executor, "Waypoint set for " .. recipient .. titleNote .. ".")
end

HANDLERS["clearwaypoints"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: clearwaypoints <player|all>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local cleared = {}
	for _, target in targets do
		if activeWaypoints[target.UserId] then
			activeWaypoints[target.UserId] = nil
			CommandRemotes.WaypointClear:FireClient(target)
			table.insert(cleared, target.DisplayName)
		end
	end

	if #cleared == 0 then
		local recipient = #targets == 1 and targets[1].DisplayName or "the targeted players"
		ok(executor, recipient .. " had no active waypoint.")
		return
	end

	ok(executor, "Waypoint cleared for " .. table.concat(cleared, ", ") .. ".")
end

HANDLERS["accesslanguage"] = function(executor, args)
        if #args < 2 then fail(executor, "Usage: accesslanguage <player|all> <language>") return end
        local targets = resolveTargets(executor, args[1])
        if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
        local langName = joinArgs(args, 2)
        if langName == "" then fail(executor, "Usage: accesslanguage <player|all> <language>") return end

        -- Validate the language up front (same result for every target)
        local lower = langName:lower()
        if lower == "english" then
                fail(executor, "English is available to all players by default.")
                return
        end
        local langDef = LanguageData.BY_NAME[lower]
        if not langDef then
                fail(executor, 'Unknown language "' .. langName .. '".')
                return
        end

        local granted, alreadyHad = {}, {}
        for _, target in targets do
                local success, msg = LanguageManager.grantLanguage(target.UserId, langDef.name)
                if success then
                        table.insert(granted, target.DisplayName)
                        -- Push the updated grant list to the player immediately
                        local grants = LanguageManager.getGrants(target.UserId)
                        CommandRemotes.LanguageGrants:FireClient(target, grants)
                else
                        -- msg is "already_granted" here (language validation passed above)
                        table.insert(alreadyHad, target.DisplayName)
                end
        end

        if #granted == 0 then
                if #alreadyHad == 1 then
                        fail(executor, alreadyHad[1] .. " already has " .. langDef.name .. ".")
                else
                        fail(executor, "All targets already have " .. langDef.name .. ".")
                end
                return
        end

        local msg = "Granted " .. langDef.name .. " to " .. table.concat(granted, ", ") .. "."
        if #alreadyHad > 0 then
                msg = msg .. " (" .. table.concat(alreadyHad, ", ") .. " already had it)"
        end
        ok(executor, msg)
end

CommandRemotes.CommandExecuted.OnServerEvent:Connect(function(executor: Player, cmdName: string, args: { string })
        if typeof(cmdName) ~= "string" then return end
        if typeof(args) ~= "table" then args = {} end

        cmdName = cmdName:lower():match("^%s*(.-)%s*$") or ""
        if cmdName == "" then return end

        local safeArgs = {}
        for _, v in args do
                if typeof(v) == "string" then table.insert(safeArgs, v) end
        end

        local definition = CommandRegistry.COMMANDS[cmdName]
        if not definition then
                fail(executor, 'Unknown command: "' .. cmdName .. '".')
                return
        end

        if not hasPermission(executor, definition.permission) then
                fail(executor, 'No permission for "' .. cmdName .. '" (requires ' .. definition.permission .. ').')
                return
        end

        local handler = HANDLERS[cmdName]
        if not handler then
                fail(executor, '"' .. cmdName .. '" has no handler.')
                return
        end

        local success, err = pcall(handler, executor, safeArgs)
        if not success then
                fail(executor, "Error: " .. tostring(err))
                warn("[CommandServer] error in '" .. cmdName .. "': " .. tostring(err))
        end
end)
