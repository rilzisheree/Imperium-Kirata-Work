local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local CommandRemotes  = require(ReplicatedStorage:WaitForChild("CommandRemotes")  :: ModuleScript)
local CommandRegistry = require(ReplicatedStorage:WaitForChild("CommandRegistry") :: ModuleScript)
local CorpseFactory   = require(script.Parent:WaitForChild("CorpseFactory")       :: ModuleScript)

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
