local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer    = Players.LocalPlayer
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local DEFAULT_SPEED  = 50   -- studs/s when no speed is specified
local BOOST_MULT     = 3    -- LeftAlt multiplies normal speed by this factor

local BV_P         = 1e4   -- BodyVelocity responsiveness
local BG_P         = 1e4   -- BodyGyro responsiveness
local BG_D         = 100   -- BodyGyro damping (prevents overshoot/wobble)
local MAX_FORCE    = 1e5   -- force cap on all axes

local flyActive     = false   -- true while the player is currently flying
local flyGranted    = false   -- true once the admin has granted flight this session
local grantedSpeed  = nil     -- studs/s set by the admin; nil means use DEFAULT_SPEED
local bodyVelocity  = nil :: BodyVelocity?
local bodyGyro      = nil :: BodyGyro?
local heartbeatConn = nil :: RBXScriptConnection?

local function getCharParts(): (BasePart?, Humanoid?)
	local character = LocalPlayer.Character
	if not character then return nil, nil end
	local root     = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function cleanUp()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	if bodyVelocity  then bodyVelocity:Destroy();     bodyVelocity  = nil end
	if bodyGyro      then bodyGyro:Destroy();          bodyGyro      = nil end
end

local function startFlight(normalSpeed: number?)
	if flyActive then return end
	local root, humanoid = getCharParts()
	if not root or not humanoid then return end

	flyActive = true

	-- Freeze humanoid physics so it doesn't fight BodyVelocity; keeps animations.
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid.AutoRotate = false

	-- BodyVelocity: overrides gravity and drives all movement.
	local bv        = Instance.new("BodyVelocity")
	bv.Name         = "FlyVelocity"
	bv.MaxForce     = Vector3.new(MAX_FORCE, MAX_FORCE, MAX_FORCE)
	bv.Velocity     = Vector3.zero
	bv.P            = BV_P
	bv.Parent       = root
	bodyVelocity    = bv

	-- BodyGyro: keeps character upright and facing the camera's horizontal direction.
	local bg        = Instance.new("BodyGyro")
	bg.Name         = "FlyGyro"
	bg.MaxTorque    = Vector3.new(MAX_FORCE, MAX_FORCE, MAX_FORCE)
	bg.P            = BG_P
	bg.D            = BG_D
	bg.CFrame       = root.CFrame
	bg.Parent       = root
	bodyGyro        = bg

	heartbeatConn = RunService.Heartbeat:Connect(function()
		local r, h = getCharParts()
		if not r or not h then
			-- character was removed mid-flight (e.g. during respawn transition)
			flyActive = false
			cleanUp()
			return
		end

		local UIS    = UserInputService
		local camCF  = Workspace.CurrentCamera.CFrame
		local dir    = Vector3.zero

		-- horizontal: follow camera look/right vectors
		if UIS:IsKeyDown(Enum.KeyCode.W) then dir += camCF.LookVector  end
		if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= camCF.LookVector  end
		if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= camCF.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then dir += camCF.RightVector end

		-- absolute vertical
		if UIS:IsKeyDown(Enum.KeyCode.Space)     then dir += Vector3.yAxis end
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end

		local base  = normalSpeed or DEFAULT_SPEED
		local speed = UIS:IsKeyDown(Enum.KeyCode.LeftAlt) and base * BOOST_MULT or base

		bv.Velocity = dir.Magnitude > 0 and dir.Unit * speed or Vector3.zero

		-- rotate to face camera's horizontal direction
		local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
		if flatLook.Magnitude > 0.1 then
			bg.CFrame = CFrame.lookAt(Vector3.zero, flatLook)
		end
	end)
end

local function stopFlight()
	if not flyActive then return end
	flyActive = false
	cleanUp()

	local _, humanoid = getCharParts()
	if humanoid then
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed                       then return end   -- TextBox / GUI consumed it
	if input.KeyCode ~= Enum.KeyCode.E    then return end
	if not flyGranted                      then return end
	if flyActive then stopFlight() else startFlight(grantedSpeed) end
end)

LocalPlayer.CharacterAdded:Connect(function()
	flyActive = false
	cleanUp()
	-- flyGranted intentionally preserved — admin gave permission for this session.
	-- The player can press E again to resume without the admin re-running the command.
end)

if CommandRemotes.FlyEnable then
	CommandRemotes.FlyEnable.OnClientEvent:Connect(function(speed: number?)
		flyGranted   = true
		grantedSpeed = typeof(speed) == "number" and speed or nil
		startFlight(grantedSpeed)
	end)
end

if CommandRemotes.FlyDisable then
	CommandRemotes.FlyDisable.OnClientEvent:Connect(function()
		flyGranted = false
		stopFlight()
	end)
end
