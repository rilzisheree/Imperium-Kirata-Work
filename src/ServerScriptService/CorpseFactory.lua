local Workspace = game:GetService("Workspace")
local Debris    = game:GetService("Debris")

local CorpseFactory = {}

CorpseFactory.DEFAULT_LIFETIME = 120 -- seconds
CorpseFactory.MIN_LIFETIME     = 5
CorpseFactory.MAX_LIFETIME     = 600

local function getCorpsesFolder(): Folder
        local folder = Workspace:FindFirstChild("Corpses")
        if not folder then
                folder = Instance.new("Folder")
                folder.Name   = "Corpses"
                folder.Parent = Workspace
        end
        return folder :: Folder
end

-- strips anything that could animate, make noise, or throw errors once
-- the corpse is disconnected from its live player
local function stripLiveBehaviour(model: Model)
        for _, inst in model:GetDescendants() do
                if inst:IsA("Script") or inst:IsA("LocalScript") then
                        inst:Destroy()
                elseif inst:IsA("Sound") then
                        inst:Destroy()
                elseif inst:IsA("ForceField") then
                        inst:Destroy()
                elseif inst:IsA("ParticleEmitter") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Trail") then
                        inst:Destroy()
                end
        end
end

-- creates a static, non-living copy of `target`'s current appearance at
-- their current position. Returns (true, displayName) on success or
-- (false, reason) on failure.
function CorpseFactory.Create(target: Player, lifetime: number?): (boolean, string)
        local character = target.Character
        if not character then
                return false, target.DisplayName .. " has no character"
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not humanoid or not rootPart then
                return false, target.DisplayName .. "'s character isn't fully loaded"
        end

        local corpsesFolder = getCorpsesFolder()

        local wasArchivable = character.Archivable
        character.Archivable = true
        local clone = character:Clone()
        character.Archivable = wasArchivable

        if not clone then
                return false, "couldn't clone " .. target.DisplayName .. "'s character"
        end

        stripLiveBehaviour(clone)

        local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
        if cloneHumanoid then
                cloneHumanoid.DisplayName          = target.DisplayName .. " (corpse)"
                cloneHumanoid.PlatformStand        = true
                cloneHumanoid.WalkSpeed            = 0
                cloneHumanoid.JumpPower            = 0
                cloneHumanoid.AutoRotate           = false
                cloneHumanoid.RequiresNeck         = false
                cloneHumanoid.BreakJointsOnDeath   = false
                cloneHumanoid.EvaluateStateMachine = false
        end

        local cloneRoot = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not cloneRoot then
                clone:Destroy()
                return false, "couldn't build a corpse rig for " .. target.DisplayName
        end

        -- tip the corpse over onto its back right where the target is standing,
        -- keeping their facing, then let gravity carry it the rest of the way down
        local originalCFrame = rootPart.CFrame
        local fallenCFrame    = originalCFrame * CFrame.Angles(math.rad(-90), 0, 0)
        clone:PivotTo(fallenCFrame)

        for _, part in clone:GetDescendants() do
                if part:IsA("BasePart") then
                        part.Anchored = false
                        part.CanQuery = true
                        part.CanTouch = false
                end
        end

        clone.Name = target.Name .. "_Corpse"
        clone:SetAttribute("CorpseOwnerUserId", target.UserId)
        clone.Parent = corpsesFolder

        local ttl = lifetime or CorpseFactory.DEFAULT_LIFETIME
        Debris:AddItem(clone, ttl)

        return true, target.DisplayName
end

return CorpseFactory
