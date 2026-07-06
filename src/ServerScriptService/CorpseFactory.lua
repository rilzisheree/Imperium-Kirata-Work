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

-- swaps every rig joint (Motor6D) for a loose BallSocketConstraint so limbs
-- can flop independently under gravity instead of falling as one rigid slab
local function ragdollize(model: Model)
        for _, joint in model:GetDescendants() do
                if joint:IsA("Motor6D") and joint.Part0 and joint.Part1 then
                        local a0 = Instance.new("Attachment")
                        a0.CFrame  = joint.C0
                        a0.Parent  = joint.Part0

                        local a1 = Instance.new("Attachment")
                        a1.CFrame  = joint.C1
                        a1.Parent  = joint.Part1

                        local socket = Instance.new("BallSocketConstraint")
                        socket.Attachment0    = a0
                        socket.Attachment1    = a1
                        socket.LimitsEnabled  = true
                        socket.TwistLimitsEnabled = true
                        socket.UpperAngle     = 60
                        socket.TwistUpperAngle = 30
                        socket.TwistLowerAngle = -30
                        socket.Parent         = joint.Part0

                        joint.Enabled = false
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

        for _, part in clone:GetDescendants() do
                if part:IsA("BasePart") then
                        part.Anchored = false
                        part.CanQuery = true
                        part.CanTouch = false
                end
        end

        -- replace the rigid rig joints with loose ball sockets so the body
        -- flops apart naturally instead of falling as one stiff slab
        ragdollize(clone)

        clone.Name = target.Name .. "_Corpse"
        clone:SetAttribute("CorpseOwnerUserId", target.UserId)
        clone.Parent = corpsesFolder

        -- keep it standing where the target was, then give it a small random
        -- shove so it topples over convincingly instead of balancing forever
        clone:PivotTo(rootPart.CFrame)
        cloneRoot.AssemblyLinearVelocity  = Vector3.new(math.random(-6, 6) / 2, 1, math.random(-6, 6) / 2)
        cloneRoot.AssemblyAngularVelocity = Vector3.new(
                math.rad(math.random(-180, 180)),
                math.rad(math.random(-180, 180)),
                math.rad(math.random(-180, 180))
        )

        local ttl = lifetime or CorpseFactory.DEFAULT_LIFETIME
        Debris:AddItem(clone, ttl)

        return true, target.DisplayName
end

return CorpseFactory
