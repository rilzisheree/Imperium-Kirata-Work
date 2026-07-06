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
                elseif inst:IsA("ParticleEmitter") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Trail") then
                        inst:Destroy()
                end
        end
end

local function findGroundY(position: Vector3, ignoreInstance: Instance): number
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { ignoreInstance }
        local result = Workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -100, 0), params)
        if result then
                return result.Position.Y
        end
        return position.Y
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

        local clone = character:Clone()
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

        -- lay the corpse down where the target is standing, keeping their facing
        local originalCFrame = rootPart.CFrame
        local groundY         = findGroundY(originalCFrame.Position, character)
        local fallenCFrame    = CFrame.new(originalCFrame.Position + Vector3.new(0, 10, 0))
                * originalCFrame.Rotation
                * CFrame.Angles(math.rad(-90), 0, 0)

        clone:PivotTo(fallenCFrame)

        -- settle the corpse flush against the ground using its real bounding box
        -- so it never clips through or floats above the floor
        local boundsCFrame, boundsSize = clone:GetBoundingBox()
        local lowestY = boundsCFrame.Position.Y - boundsSize.Y / 2
        clone:PivotTo(fallenCFrame + Vector3.new(0, (groundY - lowestY) + 0.05, 0))

        for _, part in clone:GetDescendants() do
                if part:IsA("BasePart") then
                        part.Anchored   = true
                        part.CanCollide = true
                        part.CanQuery   = true
                        part.CanTouch   = false
                        part.Massless   = true
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
