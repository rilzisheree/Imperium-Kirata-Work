local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")

local CommandRemotes  = require(ReplicatedStorage:WaitForChild("CommandRemotes")  :: ModuleScript)
local CommandRegistry = require(ReplicatedStorage:WaitForChild("CommandRegistry") :: ModuleScript)
local CorpseFactory   = require(script.Parent:WaitForChild("CorpseFactory")       :: ModuleScript)
local LanguageManager = require(script.Parent:WaitForChild("LanguageManager")     :: ModuleScript)
local LanguageData    = require(ReplicatedStorage:WaitForChild("LanguageData")    :: ModuleScript)

local Workspace          = game:GetService("Workspace")
local TeleportService    = game:GetService("TeleportService")
local MessagingService   = game:GetService("MessagingService")

local IS_STUDIO = RunService:IsStudio()

local SERVERBRING_TOPIC      = "ImperiumServerbring_" .. game.PlaceId
local SERVERJOIN_QUERY_TOPIC = "ImperiumServerjoinQ_" .. game.PlaceId
local SERVERJOIN_REPLY_TOPIC = "ImperiumServerjoinR_" .. game.PlaceId

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

-- invisibility: userId -> { [instance] = originalTransparency }
-- cleared on PlayerRemoving and on CharacterAdded (respawn)
local invisData = {}

-- world spawn override: set by setworldspawn; nil = use default Roblox spawn
local worldSpawnCFrame = nil :: CFrame?

-- shutdown guard: prevents the command running twice
local shutdownInProgress = false

-- esp state: [adminUserId][targetUserId] = true when ESP is active
local espActive = {}

-- private server state: [adminUserId] = { code = string?, reserving = boolean }
local privateServerState = {}

-- serverbring cooldown: [adminUserId] = DistributedGameTime of last publish (5 s limit)
local serverbringCooldowns = {}

-- serverjoin cooldown: [adminUserId] = DistributedGameTime of last request (5 s limit)
local serverjoinCooldowns = {}

-- serverjoin in-flight guard: [adminUserId] = requestId string while a query is pending
local serverjoinPending = {}

-- serverjoin reply callbacks: [requestId] = function(jobId, psCode?) called by the reply subscriber
local serverjoinCallbacks = {}

-- if this server instance is a reserved private server, stores the access code so
-- serverbring can broadcast it and receiving servers can use TeleportToPrivateServer
local activePrivateServerCode: string? = nil

-- music state: the currently playing audio ID (or nil) and volume (0–1)
local currentMusicId     = nil
local currentMusicVolume = 1
local cycleEnabled       = false

-- catalogue of audio IDs eligible for auto-cycle (keep in sync with MusicMenu SECTIONS)
local MUSIC_TRACK_IDS = {
	"7029031068","1836102253","1847107549","9046651755","1839806128",
	"1838853198","1841831379","76350635489391","1847854017","118028992848427",
	"1839661340","9048339210","1837065029","1844272332","9042437001",
	"1838635121","9047885144","9041904416","1846115874","1840524246",
	"847732158","114213622974713","1844634063","9046435309","1840435172",
	"1846486437","1846503445","9039953638","1848090455",
}

local function pickRandomTrack(): string?
	if #MUSIC_TRACK_IDS == 0 then return nil end
	if #MUSIC_TRACK_IDS == 1 then return MUSIC_TRACK_IDS[1] end
	local newId
	repeat
		newId = MUSIC_TRACK_IDS[math.random(1, #MUSIC_TRACK_IDS)]
	until newId ~= currentMusicId
	return newId
end

-- prevents the CharacterAdded world-spawn hook from fighting re/respawn
-- command placements; set true before LoadCharacter, cleared on first use
local skipWorldSpawnNext = {}  -- [userId] = true

Players.PlayerRemoving:Connect(function(player)
        helpUIEnabled[player.UserId] = nil
        activeWaypoints[player.UserId] = nil
        invisData[player.UserId]      = nil
        -- remove as an admin (all their active ESP sessions go away with them)
        espActive[player.UserId] = nil
        -- remove as a target from every admin's ESP table
        for _, adminEsp in espActive do
                adminEsp[player.UserId] = nil
        end
        -- clear private server reservation, serverbring cooldown, and serverjoin state
        privateServerState[player.UserId]    = nil
        serverbringCooldowns[player.UserId]  = nil
        serverjoinCooldowns[player.UserId]   = nil
        -- cancel any in-flight serverjoin so the callback never fires for a gone admin
        local pendingId = serverjoinPending[player.UserId]
        if pendingId then
                serverjoinCallbacks[pendingId]  = nil
                serverjoinPending[player.UserId] = nil
        end
end)

-- push the player's permission tier to their client on join so CommandBar
-- knows which commands to show in autocomplete
local function pushPermissions(player: Player)
        local tier = getTier(player) or "Everyone"
        CommandRemotes.Permissions:FireClient(player, tier)
end

Players.PlayerAdded:Connect(function(player)
        pushPermissions(player)

        -- detect whether this server instance is a reserved private server by reading
        -- the teleport data stamped by PrivateServerSend; only needs to happen once
        if not activePrivateServerCode then
                local ok_, joinData = pcall(function() return player:GetJoinData() end)
                if ok_ and joinData then
                        local td = joinData.TeleportData
                        if typeof(td) == "table" and typeof(td.psCode) == "string" then
                                activePrivateServerCode = td.psCode
                        end
                end
        end

        -- sync an active countdown to players who join mid-countdown
        if countdownEndTime ~= nil then
                local remaining = countdownEndTime - Workspace.DistributedGameTime
                if remaining > 0.5 then
                        CommandRemotes.CountdownStart:FireClient(player, countdownEndTime)
                end
        end

        -- sync music + cycle state to players who join mid-session
        if currentMusicId ~= nil then
                CommandRemotes.MusicSync:FireClient(player, currentMusicId, currentMusicVolume, cycleEnabled)
        elseif cycleEnabled then
                CommandRemotes.MusicCycleState:FireClient(player, cycleEnabled)
        end

        -- when a player respawns their new character is visible by default,
        -- so stale invisibility data for the old character must be discarded
        player.CharacterAdded:Connect(function()
                invisData[player.UserId] = nil
        end)

        -- if a world spawn has been set, override respawn position for this player;
        -- re/respawn commands skip this by setting skipWorldSpawnNext before LoadCharacter
        player.CharacterAdded:Connect(function(character)
                if skipWorldSpawnNext[player.UserId] then
                        skipWorldSpawnNext[player.UserId] = nil
                        return
                end
                if not worldSpawnCFrame then return end
                local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
                if root and worldSpawnCFrame then
                        -- yield one heartbeat so Roblox's built-in SpawnLocation
                        -- positioning runs first; without this it overrides our PivotTo
                        local savedCFrame = worldSpawnCFrame
                        task.wait()
                        if character.Parent and player.Character == character and savedCFrame then
                                character:PivotTo(savedCFrame)
                        end
                end
        end)
end)

-- handle players already connected when this script loads (Studio edge case)
for _, player in Players:GetPlayers() do
        task.spawn(pushPermissions, player)
        -- attach world-spawn hook for any player already in the server
        player.CharacterAdded:Connect(function(character)
                if skipWorldSpawnNext[player.UserId] then
                        skipWorldSpawnNext[player.UserId] = nil
                        return
                end
                if not worldSpawnCFrame then return end
                local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
                if root and worldSpawnCFrame then
                        -- yield one heartbeat so Roblox's built-in SpawnLocation
                        -- positioning runs first; without this it overrides our PivotTo
                        local savedCFrame = worldSpawnCFrame
                        task.wait()
                        if character.Parent and player.Character == character and savedCFrame then
                                character:PivotTo(savedCFrame)
                        end
                end
        end)
end

-- Subscribe to serverbring requests from admins in other server instances.
-- When a bring request arrives, find the matching player(s) and teleport them
-- to the requesting admin's server instance. Skipped entirely in Studio because
-- MessagingService is unavailable there.
if not IS_STUDIO then
	task.spawn(function()
		local subOk, subErr = pcall(function()
			MessagingService:SubscribeAsync(SERVERBRING_TOPIC, function(message)
				local data = message.Data
				if typeof(data) ~= "table" then return end
				local target    = data.target
				local destJobId = data.jobId
				if typeof(target) ~= "string" or typeof(destJobId) ~= "string" then return end
				-- Ignore our own broadcasts
				if destJobId == game.JobId then return end

				-- If the broadcasting server is a reserved private server it includes
				-- its access code; use TeleportToPrivateServer in that case so we are
				-- not blocked by the "restricted place" error that TeleportAsync gives
				-- when targeting a private server instance via ServerInstanceId
				local destPsCode = typeof(data.psCode) == "string" and data.psCode or nil

				local function tryBring(player: Player)
					task.spawn(function()
						local ok_, err_ = pcall(function()
							if destPsCode then
								TeleportService:TeleportToPrivateServer(game.PlaceId, destPsCode, { player })
							else
								local options = Instance.new("TeleportOptions")
								options.ServerInstanceId = destJobId
								TeleportService:TeleportAsync(game.PlaceId, { player }, options)
							end
						end)
						if not ok_ then
							warn("[CommandServer] serverbring teleport failed for "
								.. player.Name .. ": " .. tostring(err_))
						end
					end)
				end

				if target == "all" then
					for _, player in Players:GetPlayers() do
						tryBring(player)
					end
				else
					-- Mirrors resolvePlayer: exact match first, then name-prefix fallback
					local found: Player? = nil
					for _, player in Players:GetPlayers() do
						if player.Name:lower() == target
							or player.DisplayName:lower() == target
						then
							found = player
							break
						end
					end
					if not found then
						for _, player in Players:GetPlayers() do
							if player.Name:lower():sub(1, #target) == target then
								found = player
								break
							end
						end
					end
					if found then tryBring(found) end
				end
			end)
		end)
		if not subOk then
			warn("[CommandServer] MessagingService subscribe failed: " .. tostring(subErr))
		end
	end)
end

-- Subscribe to serverjoin query messages from admins in other servers.
-- When a query arrives asking "who has player X?", check locally and reply
-- with this server's JobId (and private-server code if applicable).
if not IS_STUDIO then
	task.spawn(function()
		local subOk, subErr = pcall(function()
			MessagingService:SubscribeAsync(SERVERJOIN_QUERY_TOPIC, function(message)
				local data = message.Data
				if typeof(data) ~= "table" then return end
				local target    = data.target
				local requestId = data.requestId
				local replyTo   = data.replyTo
				if typeof(target) ~= "string"
					or typeof(requestId) ~= "string"
					or typeof(replyTo) ~= "string" then return end
				-- Ignore queries that originated from this server
				if replyTo == game.JobId then return end

				-- Find the player locally (exact match first, then name-prefix fallback,
				-- mirroring resolvePlayer for consistency across the codebase)
				local found: Player? = nil
				for _, p in Players:GetPlayers() do
					if p.Name:lower() == target or p.DisplayName:lower() == target then
						found = p; break
					end
				end
				if not found then
					for _, p in Players:GetPlayers() do
						if p.Name:lower():sub(1, #target) == target then
							found = p; break
						end
					end
				end
				if not found then return end

				-- Player is here; publish a reply back to all servers.
				-- Only the server whose requestId matches an entry in serverjoinCallbacks
				-- will act on it; all others discard it immediately.
				pcall(function()
					MessagingService:PublishAsync(SERVERJOIN_REPLY_TOPIC, {
						requestId = requestId,
						jobId     = game.JobId,
						psCode    = activePrivateServerCode,
					})
				end)
			end)
		end)
		if not subOk then
			warn("[CommandServer] serverjoin query subscribe failed: " .. tostring(subErr))
		end
	end)
end

-- Subscribe to serverjoin reply messages.
-- Replies are broadcast to all servers; only the server holding the matching
-- pending callback (keyed by requestId) will act on it.
if not IS_STUDIO then
	task.spawn(function()
		local subOk, subErr = pcall(function()
			MessagingService:SubscribeAsync(SERVERJOIN_REPLY_TOPIC, function(message)
				local data = message.Data
				if typeof(data) ~= "table" then return end
				local requestId = data.requestId
				local jobId     = data.jobId
				if typeof(requestId) ~= "string" or typeof(jobId) ~= "string" then return end
				local cb = serverjoinCallbacks[requestId]
				if cb then
					serverjoinCallbacks[requestId] = nil
					cb(jobId, typeof(data.psCode) == "string" and data.psCode or nil)
				end
			end)
		end)
		if not subOk then
			warn("[CommandServer] serverjoin reply subscribe failed: " .. tostring(subErr))
		end
	end)
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

HANDLERS["setworldspawn"] = function(executor, args)
	local adminChar = executor.Character
	local adminRoot = adminChar and adminChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not adminRoot then
		fail(executor, "Your character is not available.")
		return
	end

	local rootPos = adminRoot.Position

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { adminChar }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	-- probe downward up to 50 studs to find a solid floor
	local floorHit = Workspace:Raycast(rootPos + Vector3.new(0, 2, 0), Vector3.new(0, -50, 0), rayParams)
	if not floorHit then
		fail(executor, "No floor detected below your position. Move to a valid location.")
		return
	end
	local floorY     = floorHit.Position.Y
	local spawnY     = floorY + 3        -- HumanoidRootPart rests ~3 studs above floor

	-- clearance check: character needs at least 6 studs of vertical space
	local clearHit = Workspace:Raycast(
		Vector3.new(rootPos.X, floorY + 0.5, rootPos.Z),
		Vector3.new(0, 6, 0),
		rayParams
	)
	if clearHit then
		fail(executor, "Spawn location is obstructed above. Move to a more open area.")
		return
	end

	-- preserve the admin's facing direction so spawners arrive oriented sensibly
	local look   = adminRoot.CFrame.LookVector
	local yAngle = math.atan2(-look.X, -look.Z)
	worldSpawnCFrame = CFrame.new(Vector3.new(rootPos.X, spawnY, rootPos.Z))
		* CFrame.fromEulerAnglesYXZ(0, yAngle, 0)

	ok(executor, "World spawn set to your current position.")
end

HANDLERS["shutdown"] = function(executor, args)
	if shutdownInProgress then
		fail(executor, "A shutdown is already in progress.")
		return
	end
	shutdownInProgress = true

	local customMsg = joinArgs(args, 1)
	local kickMsg = (customMsg ~= "") and customMsg or "This server has been shut down by Staff."

	ok(executor, "Initiating server shutdown in 5 seconds.")
	CommandRemotes.Shutdown:FireAllClients()

	task.delay(5, function()
		for _, player in Players:GetPlayers() do
			player:Kick(kickMsg)
		end
	end)
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

        -- skip world-spawn override; re manages placement itself
        skipWorldSpawnNext[target.UserId] = true
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
        -- skip world-spawn override; respawn manages placement itself
        skipWorldSpawnNext[target.UserId] = true
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

HANDLERS["watch"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: watch <player>") return end
	local target = resolvePlayer(executor, args[1])
	if not target then fail(executor, 'Player "' .. args[1] .. '" not found.') return end
	if target == executor then fail(executor, "You cannot watch yourself.") return end
	CommandRemotes.WatchStart:FireClient(executor, target)
	ok(executor, "Now watching " .. target.DisplayName .. ".")
end

HANDLERS["unwatch"] = function(executor, args)
	CommandRemotes.WatchStop:FireClient(executor)
	ok(executor, "Stopped watching.")
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

-- iterates a character's descendants and sets all visual transparencies to 1,
-- saving each original value so uninvis can restore them exactly.
local function applyInvis(target: Player): (boolean, string)
	if invisData[target.UserId] then
		return false, target.DisplayName .. " is already invisible"
	end

	local character = target.Character
	if not character then
		return false, target.DisplayName .. " has no character"
	end

	local saved = {}
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			saved[desc] = desc.Transparency
			desc.Transparency = 1
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			saved[desc] = desc.Transparency
			desc.Transparency = 1
		end
	end

	invisData[target.UserId] = saved
	return true, target.DisplayName
end

-- restores every part/decal/texture in a character to its saved transparency.
local function removeInvis(target: Player): (boolean, string)
	local saved = invisData[target.UserId]
	if not saved then
		return false, target.DisplayName .. " is not invisible"
	end

	invisData[target.UserId] = nil

	local character = target.Character
	if not character then
		-- player respawned; CharacterAdded already cleared invisData, new character is visible
		return true, target.DisplayName
	end

	for inst, transparency in saved do
		if inst and inst.Parent then   -- guard against parts removed since invis was applied
			inst.Transparency = transparency
		end
	end

	return true, target.DisplayName
end

HANDLERS["invis"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: invis <player|all>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local made, failures = {}, {}
	for _, target in targets do
		local success, result = applyInvis(target)
		if success then
			table.insert(made, result)
		else
			table.insert(failures, result)
		end
	end

	if #made == 0 then
		fail(executor, "No players made invisible: " .. table.concat(failures, "; ") .. ".")
		return
	end

	local msg = "Made invisible: " .. table.concat(made, ", ") .. "."
	if #failures > 0 then
		msg = msg .. " (" .. table.concat(failures, "; ") .. ")"
	end
	ok(executor, msg)
end

HANDLERS["uninvis"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: uninvis <player|all>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local restored, failures = {}, {}
	for _, target in targets do
		local success, result = removeInvis(target)
		if success then
			table.insert(restored, result)
		else
			table.insert(failures, result)
		end
	end

	if #restored == 0 then
		fail(executor, "No players visible: " .. table.concat(failures, "; ") .. ".")
		return
	end

	local msg = "Restored visibility: " .. table.concat(restored, ", ") .. "."
	if #failures > 0 then
		msg = msg .. " (" .. table.concat(failures, "; ") .. ")"
	end
	ok(executor, msg)
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

HANDLERS["music"] = function(executor, args)
	local rawId = args[1]
	if not rawId or rawId == "" then
		CommandRemotes.MusicOpen:FireClient(executor)
		return
	end
	-- accept only positive integer strings (Roblox audio asset IDs)
	if not rawId:match("^%d+$") then
		fail(executor, 'Invalid audio ID "' .. rawId .. '". Must be a positive numeric Roblox asset ID.')
		return
	end
	currentMusicId = rawId
	CommandRemotes.MusicPlay:FireAllClients(currentMusicId, currentMusicVolume)
end

-- MusicCommand: fired by MusicMenu or MusicClient when the user interacts with music controls.
-- "ended" is allowed from any player (cycle needs reports from all clients) but validated
-- strictly against the current track ID to prevent spoofing.
-- All other actions require Admin permission.
CommandRemotes.MusicCommand.OnServerEvent:Connect(function(player: Player, action: string, data: any)
	if typeof(action) ~= "string" then return end

	-- Handle "ended" before the admin gate so non-admin clients can drive cycle.
	if action == "ended" then
		if typeof(data) ~= "string" then return end
		if cycleEnabled and data == currentMusicId then
			local nextId = pickRandomTrack()
			if nextId then
				currentMusicId = nextId
				CommandRemotes.MusicPlay:FireAllClients(currentMusicId, currentMusicVolume)
			end
		end
		return
	end

	if not hasPermission(player, "Admin") then return end

	if action == "play" then
		if typeof(data) ~= "string" or not data:match("^%d+$") then return end
		currentMusicId = data
		CommandRemotes.MusicPlay:FireAllClients(currentMusicId, currentMusicVolume)
	elseif action == "stop" then
		currentMusicId = nil
		CommandRemotes.MusicStop:FireAllClients()
	elseif action == "volume" then
		if typeof(data) ~= "number" then return end
		currentMusicVolume = math.clamp(data, 0, 1)
		if currentMusicId then
			CommandRemotes.MusicVolume:FireAllClients(currentMusicVolume)
		end
	elseif action == "seek" then
		-- seek all clients to a position in seconds
		if typeof(data) ~= "number" then return end
		CommandRemotes.MusicSeek:FireAllClients(math.max(0, data))
	elseif action == "cycle" then
		if typeof(data) ~= "boolean" then return end
		cycleEnabled = data
		CommandRemotes.MusicCycleState:FireAllClients(cycleEnabled)
	end
end)

HANDLERS["esp"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: esp <player|all>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local uid = executor.UserId
	if not espActive[uid] then espActive[uid] = {} end

	local enabled, disabled = {}, {}
	for _, target in targets do
		local tid = target.UserId
		if espActive[uid][tid] then
			espActive[uid][tid] = nil
			CommandRemotes.EspToggle:FireClient(executor, target, false)
			table.insert(disabled, target.DisplayName)
		else
			espActive[uid][tid] = true
			CommandRemotes.EspToggle:FireClient(executor, target, true)
			table.insert(enabled, target.DisplayName)
		end
	end

	-- discard empty admin table
	if next(espActive[uid]) == nil then espActive[uid] = nil end

	local parts = {}
	if #enabled  > 0 then table.insert(parts, "ESP on: "  .. table.concat(enabled,  ", ")) end
	if #disabled > 0 then table.insert(parts, "ESP off: " .. table.concat(disabled, ", ")) end
	ok(executor, table.concat(parts, " | ") .. ".")
end

HANDLERS["place"] = function(executor, args)
	if #args < 2 then fail(executor, "Usage: place <player|all> <placeId>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local placeId = tonumber(args[2])
	if not placeId or placeId ~= math.floor(placeId) or placeId < 1 then
		fail(executor, "Invalid Place ID — must be a positive whole number.")
		return
	end
	placeId = math.floor(placeId)

	local sent, failures = {}, {}
	local remaining = #targets
	for _, target in targets do
		task.spawn(function()
			local teleOk, teleErr = pcall(function()
				TeleportService:TeleportAsync(placeId, { target })
			end)
			if teleOk then
				table.insert(sent, target.DisplayName)
			else
				table.insert(failures, target.DisplayName)
				warn("[CommandServer] place: teleport failed for "
					.. target.Name .. ": " .. tostring(teleErr))
			end
			remaining -= 1
		end)
	end
	while remaining > 0 do task.wait() end

	if #sent == 0 then
		fail(executor, "Teleport failed for all targets. Verify the Place ID and that the place is public.")
		return
	end
	local msg = "Teleporting " .. table.concat(sent, ", ") .. " to place " .. placeId .. "."
	if #failures > 0 then msg ..= " (" .. #failures .. " failed)" end
	ok(executor, msg)
end

HANDLERS["privateserver"] = function(executor, args)
	-- Pass the current reservation state so the menu can restore it on reopen
	local state  = privateServerState[executor.UserId]
	local status = "none"
	local code: string? = nil
	if state then
		if state.reserving then
			status = "reserving"
		elseif state.code then
			status = "active"
			code   = state.code
		end
	end
	CommandRemotes.PrivateServerOpen:FireClient(executor, status, code)
	ok(executor, "Private Server menu opened.")
end

HANDLERS["serverbring"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: serverbring <player|all>") return end
	local rawTarget = args[1]:lower()

	if rawTarget == "me" then
		fail(executor, "You are already in this server.")
		return
	end

	-- Rate-limit: 5-second cooldown per admin to prevent broadcast flooding
	local now      = Workspace.DistributedGameTime
	local lastSent = serverbringCooldowns[executor.UserId] or 0
	if now - lastSent < 5 then
		fail(executor, ("serverbring is on cooldown — wait %.0f more second(s)."):format(
			5 - (now - lastSent)))
		return
	end

	-- Reject if the target is already here (mirrors resolvePlayer: exact then prefix)
	if rawTarget ~= "all" then
		local foundHere: Player? = nil
		for _, p in Players:GetPlayers() do
			if p.Name:lower() == rawTarget or p.DisplayName:lower() == rawTarget then
				foundHere = p; break
			end
		end
		if not foundHere then
			for _, p in Players:GetPlayers() do
				if p.Name:lower():sub(1, #rawTarget) == rawTarget then
					foundHere = p; break
				end
			end
		end
		if foundHere then
			fail(executor, foundHere.DisplayName .. " is already in this server.")
			return
		end
	end

	if IS_STUDIO then
		fail(executor, "serverbring requires a live server — MessagingService is unavailable in Studio.")
		return
	end

	local broadcastOk, broadcastErr = pcall(function()
		MessagingService:PublishAsync(SERVERBRING_TOPIC, {
			target  = rawTarget,
			jobId   = game.JobId,
			-- include the private-server access code when serverbring is called from
			-- within a reserved server; receivers use TeleportToPrivateServer instead
			-- of TeleportAsync so they aren't blocked by the "restricted place" error
			psCode  = activePrivateServerCode,
		})
	end)

	if not broadcastOk then
		fail(executor, "Broadcast failed: " .. tostring(broadcastErr))
		return
	end

	serverbringCooldowns[executor.UserId] = now
	local desc = rawTarget == "all" and "all players" or '"' .. args[1] .. '"'
	ok(executor, "Serverbring request sent for " .. desc .. ". Matching players will be teleported shortly.")
end

HANDLERS["serverjoin"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: serverjoin <player>") return end
	local rawTarget = args[1]:lower()

	if rawTarget == "me" then
		fail(executor, "You are already in this server.")
		return
	end

	-- Reject if the target is already in this server (exact match then prefix fallback,
	-- mirroring resolvePlayer for consistency)
	local foundHere: Player? = nil
	for _, p in Players:GetPlayers() do
		if p.Name:lower() == rawTarget or p.DisplayName:lower() == rawTarget then
			foundHere = p; break
		end
	end
	if not foundHere then
		for _, p in Players:GetPlayers() do
			if p.Name:lower():sub(1, #rawTarget) == rawTarget then
				foundHere = p; break
			end
		end
	end
	if foundHere then
		fail(executor, foundHere.DisplayName .. " is already in this server.")
		return
	end

	if IS_STUDIO then
		fail(executor, "serverjoin requires a live server — MessagingService is unavailable in Studio.")
		return
	end

	-- Prevent duplicate in-flight requests from the same admin
	if serverjoinPending[executor.UserId] then
		fail(executor, "A serverjoin request is already in progress. Please wait.")
		return
	end

	-- Rate-limit: 5-second cooldown per admin to prevent broadcast flooding
	local now      = Workspace.DistributedGameTime
	local lastSent = serverjoinCooldowns[executor.UserId] or 0
	if now - lastSent < 5 then
		fail(executor, ("serverjoin is on cooldown — wait %.0f more second(s)."):format(
			5 - (now - lastSent)))
		return
	end

	local requestId = HttpService:GenerateGUID(false)
	serverjoinPending[executor.UserId]   = requestId
	serverjoinCooldowns[executor.UserId] = now

	-- Register the callback BEFORE publishing so a fast reply from a remote server
	-- cannot arrive and be dropped between PublishAsync and the assignment below.
	local replied    = false
	local destJobId  = nil
	local destPsCode = nil

	serverjoinCallbacks[requestId] = function(jobId, psCode)
		replied     = true
		destJobId   = jobId
		destPsCode  = psCode
	end

	-- Notify the admin before the async wait so they see immediate feedback
	ok(executor, 'Locating "' .. args[1] .. '" across servers…')

	local broadcastOk, broadcastErr = pcall(function()
		MessagingService:PublishAsync(SERVERJOIN_QUERY_TOPIC, {
			target    = rawTarget,
			requestId = requestId,
			replyTo   = game.JobId,
		})
	end)

	if not broadcastOk then
		serverjoinCallbacks[requestId]       = nil
		serverjoinPending[executor.UserId]   = nil
		if executor.Parent then
			fail(executor, "Broadcast failed: " .. tostring(broadcastErr))
		end
		return
	end

	-- Yield for up to 8 seconds waiting for any server to reply
	local waited = 0
	while not replied and waited < 8 do
		task.wait(0.25)
		waited += 0.25
	end

	-- Clean up pending state regardless of outcome
	serverjoinCallbacks[requestId]       = nil
	serverjoinPending[executor.UserId]   = nil

	-- Guard all feedback paths: admin may have left or been kicked while waiting
	if not executor.Parent then return end

	if not replied then
		fail(executor, '"' .. args[1] .. '" could not be found in any server. They may be offline or in a different experience.')
		return
	end

	ok(executor, 'Found "' .. args[1] .. '". Teleporting you now…')

	task.spawn(function()
		local teleOk, teleErr = pcall(function()
			if destPsCode then
				-- Target is in a reserved private server; TeleportAsync cannot reach
				-- private servers by ServerInstanceId, so use TeleportToPrivateServer
				TeleportService:TeleportToPrivateServer(game.PlaceId, destPsCode, { executor })
			else
				local options = Instance.new("TeleportOptions")
				options.ServerInstanceId = destJobId
				TeleportService:TeleportAsync(game.PlaceId, { executor }, options)
			end
		end)
		if not teleOk then
			warn("[CommandServer] serverjoin teleport failed for "
				.. executor.Name .. ": " .. tostring(teleErr))
			if executor.Parent then
				fail(executor, "Teleport failed: " .. tostring(teleErr))
			end
		end
	end)
end

HANDLERS["heal"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: heal <player|all> [amount]") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local amount = nil
	if args[2] then
		local n = tonumber(args[2])
		if not n or n <= 0 then
			fail(executor, "Amount must be a positive number.")
			return
		end
		amount = n
	end

	local healed, failures = {}, {}
	for _, target in targets do
		local character = target.Character
		local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			table.insert(failures, target.DisplayName .. " has no character")
		elseif humanoid.Health <= 0 then
			table.insert(failures, target.DisplayName .. " is dead")
		else
			if amount then
				humanoid.Health = math.min(humanoid.Health + amount, humanoid.MaxHealth)
			else
				humanoid.Health = humanoid.MaxHealth
			end
			table.insert(healed, target.DisplayName)
		end
	end

	if #healed == 0 then
		fail(executor, "No players healed: " .. table.concat(failures, "; ") .. ".")
		return
	end

	local amountNote = amount and (" by " .. amount) or " fully"
	local msg = "Healed" .. amountNote .. ": " .. table.concat(healed, ", ") .. "."
	if #failures > 0 then
		msg = msg .. " (" .. #failures .. " skipped: " .. table.concat(failures, "; ") .. ")"
	end
	ok(executor, msg)
end

HANDLERS["damage"] = function(executor, args)
	if #args < 2 then fail(executor, "Usage: damage <player|all> <amount>") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local amount = tonumber(args[2])
	if not amount or amount <= 0 then
		fail(executor, "Amount must be a positive number.")
		return
	end

	local damaged, failures = {}, {}
	for _, target in targets do
		local character = target.Character
		local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			table.insert(failures, target.DisplayName .. " has no character")
		elseif humanoid.Health <= 0 then
			table.insert(failures, target.DisplayName .. " is already dead")
		else
			humanoid.Health = math.max(humanoid.Health - amount, 0)
			table.insert(damaged, target.DisplayName)
		end
	end

	if #damaged == 0 then
		fail(executor, "No players damaged: " .. table.concat(failures, "; ") .. ".")
		return
	end

	local msg = "Dealt " .. amount .. " damage to: " .. table.concat(damaged, ", ") .. "."
	if #failures > 0 then
		msg = msg .. " (" .. #failures .. " skipped: " .. table.concat(failures, "; ") .. ")"
	end
	ok(executor, msg)
end

HANDLERS["kick"] = function(executor, args)
	if #args < 1 then fail(executor, "Usage: kick <player|all> [reason]") return end
	local targets = resolveTargets(executor, args[1])
	if not targets then fail(executor, 'Player "' .. args[1] .. '" not found.') return end

	local reason = joinArgs(args, 2)
	local kickMsg
	if reason ~= "" then
		kickMsg = "You have been kicked by an administrator.\n\nReason:\n" .. reason
	else
		kickMsg = "You have been kicked by an administrator."
	end

	local kicked, failures = {}, {}
	for _, target in targets do
		if target.Parent then
			local pcallOk, pcallErr = pcall(function() target:Kick(kickMsg) end)
			if pcallOk then
				table.insert(kicked, target.DisplayName)
			else
				table.insert(failures, target.DisplayName .. " (error: " .. tostring(pcallErr) .. ")")
			end
		else
			table.insert(failures, target.DisplayName .. " already left")
		end
	end

	if #kicked == 0 then
		fail(executor, "No players kicked: " .. table.concat(failures, "; ") .. ".")
		return
	end

	local msg = "Kicked: " .. table.concat(kicked, ", ") .. "."
	if reason ~= "" then msg = msg .. ' Reason: "' .. reason .. '".' end
	if #failures > 0 then
		msg = msg .. " (" .. #failures .. " skipped: " .. table.concat(failures, "; ") .. ")"
	end
	ok(executor, msg)
end

-- PrivateServerReserve: admin requests a new reserved server slot
CommandRemotes.PrivateServerReserve.OnServerEvent:Connect(function(player: Player)
	if not hasPermission(player, "Admin") then return end
	local uid = player.UserId

	-- Block while a reservation is in-flight, or if one is already active
	if privateServerState[uid] then
		if privateServerState[uid].reserving then return end
		if privateServerState[uid].code then
			fail(player, "A private server is already active. Cancel it before creating a new one.")
			return
		end
	end
	privateServerState[uid] = { code = nil, reserving = true }

	CommandRemotes.PrivateServerStatus:FireClient(player, "reserving")

	task.spawn(function()
		local resOk, result = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)
		if resOk and result then
			privateServerState[uid] = { code = result, reserving = false }
			CommandRemotes.PrivateServerStatus:FireClient(player, "active", result)
		else
			privateServerState[uid] = nil
			CommandRemotes.PrivateServerStatus:FireClient(player, "failed")
			warn("[CommandServer] ReserveServer failed: " .. tostring(result))
		end
	end)
end)

-- PrivateServerSend: admin sends queued players to the reserved server
CommandRemotes.PrivateServerSend.OnServerEvent:Connect(function(player: Player, userIds: { number })
	if not hasPermission(player, "Admin") then return end
	if typeof(userIds) ~= "table" then return end

	local state = privateServerState[player.UserId]
	if not state or not state.code then
		fail(player, "No active private server — create one first.")
		return
	end

	local targets = {}
	for _, uid in userIds do
		if typeof(uid) == "number" then
			local target = Players:GetPlayerByUserId(uid)
			if target then table.insert(targets, target) end
		end
	end

	if #targets == 0 then
		fail(player, "No valid players in the queue.")
		return
	end

	local code = state.code
	task.spawn(function()
		local sendOk, sendErr = pcall(function()
			-- Stamp the access code into teleport data so the private server instance
			-- can read it on PlayerAdded and enable serverbring from within that server
			TeleportService:TeleportToPrivateServer(game.PlaceId, code, targets, nil, { psCode = code })
		end)
		if sendOk then
			ok(player, "Sent " .. #targets .. " player(s) to the private server.")
		else
			fail(player, "Teleport failed: " .. tostring(sendErr))
		end
	end)
end)

-- PrivateServerCancel: admin cancels their reserved server
CommandRemotes.PrivateServerCancel.OnServerEvent:Connect(function(player: Player)
	if not hasPermission(player, "Admin") then return end
	privateServerState[player.UserId] = nil
	CommandRemotes.PrivateServerStatus:FireClient(player, "cancelled")
end)

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
