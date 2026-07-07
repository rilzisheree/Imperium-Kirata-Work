local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer    = Players.LocalPlayer
local PlayerGui      = LocalPlayer:WaitForChild("PlayerGui")
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

-- ── indicator UI ───────────────────────────────────────────────────────────────

local watchGui = Instance.new("ScreenGui")
watchGui.Name           = "WatchIndicator"
watchGui.DisplayOrder   = 105
watchGui.ResetOnSpawn   = false
watchGui.IgnoreGuiInset = true
watchGui.Enabled        = false
watchGui.Parent         = PlayerGui

local watchLabel = Instance.new("TextLabel")
watchLabel.Name                   = "Label"
watchLabel.AnchorPoint            = Vector2.new(0.5, 0)
watchLabel.Position               = UDim2.new(0.5, 0, 0, 10)
watchLabel.Size                   = UDim2.new(0, 0, 0, 24)
watchLabel.AutomaticSize          = Enum.AutomaticSize.X
watchLabel.BackgroundTransparency = 1
watchLabel.TextColor3             = Color3.new(1, 1, 1)
watchLabel.TextSize               = 17
watchLabel.Font                   = Enum.Font.Gotham
watchLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
watchLabel.TextStrokeTransparency = 0.4
watchLabel.ZIndex                 = 10
watchLabel.Parent                 = watchGui

-- ── state ──────────────────────────────────────────────────────────────────────

local watchedPlayer      = nil :: Player?
local savedCameraType    = nil :: Enum.CameraType?
local savedCameraSubject = nil :: Instance?

local charAddedConn      = nil :: RBXScriptConnection?
local playerRemovingConn = nil :: RBXScriptConnection?
local adminRespawnConn   = nil :: RBXScriptConnection?

-- ── helpers ────────────────────────────────────────────────────────────────────

local function getCamera(): Camera
	return Workspace.CurrentCamera
end

local function setSubject(character: Model?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		getCamera().CameraSubject = humanoid
	end
end

-- ── core logic ─────────────────────────────────────────────────────────────────

local function stopWatch(leftMsg: string?)
	if not watchedPlayer then return end
	watchedPlayer = nil

	-- disconnect all event connections
	if charAddedConn      then charAddedConn:Disconnect();      charAddedConn      = nil end
	if playerRemovingConn then playerRemovingConn:Disconnect(); playerRemovingConn = nil end
	if adminRespawnConn   then adminRespawnConn:Disconnect();   adminRespawnConn   = nil end

	-- restore camera — prefer the admin's current humanoid over the stale saved subject
	local cam           = getCamera()
	cam.CameraType      = savedCameraType or Enum.CameraType.Custom
	local adminChar     = LocalPlayer.Character
	local adminHumanoid = adminChar and adminChar:FindFirstChildOfClass("Humanoid")
	cam.CameraSubject   = adminHumanoid or savedCameraSubject

	savedCameraType    = nil
	savedCameraSubject = nil

	-- hide indicator, or briefly show the reason the session ended
	if leftMsg then
		watchLabel.Text  = leftMsg
		watchGui.Enabled = true
		task.delay(4, function()
			-- only hide if a new session hasn't started in the meantime
			if not watchedPlayer then
				watchGui.Enabled = false
				watchLabel.Text  = ""
			end
		end)
	else
		watchGui.Enabled = false
		watchLabel.Text  = ""
	end
end

local function startWatch(target: Player)
	-- switching targets: cleanly tear down any existing session first
	stopWatch()

	watchedPlayer = target

	local cam            = getCamera()
	savedCameraType      = cam.CameraType
	savedCameraSubject   = cam.CameraSubject

	cam.CameraType = Enum.CameraType.Custom
	setSubject(target.Character)

	-- follow the target through respawns
	charAddedConn = target.CharacterAdded:Connect(function(newCharacter)
		if watchedPlayer ~= target then return end
		-- wait one frame so the humanoid is fully initialised
		task.defer(function()
			setSubject(newCharacter)
		end)
	end)

	-- stop automatically if the target leaves
	playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
		if player ~= watchedPlayer then return end
		stopWatch(target.DisplayName .. " (@" .. target.Name .. ") left the game.")
	end)

	-- stop if the admin dies / resets (their new character needs its own camera)
	adminRespawnConn = LocalPlayer.CharacterAdded:Connect(function()
		stopWatch()
	end)

	-- show indicator
	watchLabel.Text  = "Watching: " .. target.DisplayName .. " (@" .. target.Name .. ")"
	watchGui.Enabled = true
end

-- ── remote listeners ───────────────────────────────────────────────────────────

if CommandRemotes.WatchStart then
	CommandRemotes.WatchStart.OnClientEvent:Connect(function(target: Player)
		if typeof(target) == "Instance" and target:IsA("Player") then
			startWatch(target)
		end
	end)
end

if CommandRemotes.WatchStop then
	CommandRemotes.WatchStop.OnClientEvent:Connect(function()
		stopWatch()
	end)
end
