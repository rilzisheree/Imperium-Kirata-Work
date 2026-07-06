local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer    = Players.LocalPlayer
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

-- ── active waypoint state ──────────────────────────────────────────────────────

local waypointPart    = nil   -- Part anchored in Workspace (client-local)
local heartbeatConn   = nil   -- RunService.Heartbeat connection for distance updates

-- ── helpers ────────────────────────────────────────────────────────────────────

local function formatDist(studs: number): string
	local m = math.round(studs)
	if m >= 1000 then
		return string.format("%.1fkm", m / 1000)
	end
	return m .. "m"
end

-- ── clear ──────────────────────────────────────────────────────────────────────

local function clearWaypoint()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	if waypointPart then
		waypointPart:Destroy()
		waypointPart = nil
	end
end

-- ── create ─────────────────────────────────────────────────────────────────────

local function createWaypoint(pos: Vector3)
	clearWaypoint()
	waypointPos = pos

	-- Invisible anchor part, client-local (never replicates to other players)
	local part = Instance.new("Part")
	part.Name         = "WaypointMarker"
	part.Anchored     = true
	part.CanCollide   = false
	part.CanQuery     = false
	part.CanTouch     = false
	part.Size         = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.CFrame       = CFrame.new(pos)
	part.Parent       = Workspace

	-- BillboardGui: always visible through terrain/objects, stacked above marker
	local billboard = Instance.new("BillboardGui")
	billboard.Name                    = "WaypointBillboard"
	billboard.Adornee                 = part
	billboard.AlwaysOnTop             = true
	billboard.Size                    = UDim2.new(0, 64, 0, 88)
	billboard.StudsOffsetWorldSpace   = Vector3.new(0, 4, 0)
	billboard.ResetOnSpawn            = false
	billboard.Parent                  = part

	-- White upward-pointing triangle
	local triangle = Instance.new("TextLabel")
	triangle.Name                   = "Triangle"
	triangle.Size                   = UDim2.new(1, 0, 0.65, 0)
	triangle.Position               = UDim2.new(0, 0, 0, 0)
	triangle.BackgroundTransparency = 1
	triangle.Text                   = "▲"
	triangle.TextColor3             = Color3.new(1, 1, 1)
	triangle.TextScaled             = true
	triangle.Font                   = Enum.Font.GothamBold
	triangle.TextStrokeColor3       = Color3.new(0, 0, 0)
	triangle.TextStrokeTransparency = 0.4
	triangle.ZIndex                 = 5
	triangle.Parent                 = billboard

	-- Distance label beneath the triangle
	local distLabel = Instance.new("TextLabel")
	distLabel.Name                   = "DistLabel"
	distLabel.Size                   = UDim2.new(1, 0, 0.35, 0)
	distLabel.Position               = UDim2.new(0, 0, 0.65, 0)
	distLabel.BackgroundTransparency = 1
	distLabel.Text                   = "..."
	distLabel.TextColor3             = Color3.new(1, 1, 1)
	distLabel.TextScaled             = true
	distLabel.Font                   = Enum.Font.GothamBold
	distLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
	distLabel.TextStrokeTransparency = 0.4
	distLabel.ZIndex                 = 5
	distLabel.Parent                 = billboard

	waypointPart = part

	-- Update the distance label every frame as the player moves
	heartbeatConn = RunService.Heartbeat:Connect(function()
		local character = LocalPlayer.Character
		local root      = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dist     = (root.Position - pos).Magnitude
			distLabel.Text = formatDist(dist)
		end
	end)
end

-- ── remote listeners ───────────────────────────────────────────────────────────

if CommandRemotes.WaypointSet then
	CommandRemotes.WaypointSet.OnClientEvent:Connect(function(pos: Vector3)
		if typeof(pos) == "Vector3" then
			createWaypoint(pos)
		end
	end)
end

if CommandRemotes.WaypointClear then
	CommandRemotes.WaypointClear.OnClientEvent:Connect(function()
		clearWaypoint()
	end)
end
-- Note: script lives in StarterPlayerScripts, so it runs once per session and
-- is never restarted on character respawn — waypoints persist through death
-- automatically until an admin explicitly calls clearwaypoints.
