local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer    = Players.LocalPlayer
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local waypointPart  = nil   -- Part anchored in Workspace (client-local)
local heartbeatConn = nil   -- RunService.Heartbeat connection for distance updates

local function formatDist(studs: number): string
	local m = math.round(studs)
	if m >= 1000 then
		return string.format("%.1fkm", m / 1000)
	end
	return m .. "m"
end

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

local function createWaypoint(pos: Vector3, title: string?)
	clearWaypoint()

	local hasTitle = title and title ~= ""

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

	-- BillboardGui: always visible through terrain/objects, floats above marker
	local billboard = Instance.new("BillboardGui")
	billboard.Name                  = "WaypointBillboard"
	billboard.Adornee               = part
	billboard.AlwaysOnTop           = true
	billboard.Size                  = UDim2.new(0, 52, 0, 76)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.ResetOnSpawn          = false
	billboard.Parent                = part

	-- Optional title label (top slot)
	if hasTitle then
		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name                   = "TitleLabel"
		titleLabel.Size                   = UDim2.new(1, 0, 0.26, 0)
		titleLabel.Position               = UDim2.new(0, 0, 0, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text                   = title :: string
		titleLabel.TextColor3             = Color3.new(1, 1, 1)
		titleLabel.TextScaled             = true
		titleLabel.Font                   = Enum.Font.Gotham
		titleLabel.TextStrokeColor3       = Color3.new(0, 0, 0)
		titleLabel.TextStrokeTransparency = 0.4
		titleLabel.ZIndex                 = 5
		titleLabel.Parent                 = billboard
	end

	-- Triangle — offset down when a title is present
	local triY  = hasTitle and 0.26 or 0
	local triH  = hasTitle and 0.47 or 0.65

	local triangle = Instance.new("TextLabel")
	triangle.Name                   = "Triangle"
	triangle.Size                   = UDim2.new(1, 0, triH, 0)
	triangle.Position               = UDim2.new(0, 0, triY, 0)
	triangle.BackgroundTransparency = 1
	triangle.Text                   = "▲"
	triangle.TextColor3             = Color3.new(1, 1, 1)
	triangle.TextScaled             = true
	triangle.Font                   = Enum.Font.GothamBold
	triangle.TextStrokeColor3       = Color3.new(0, 0, 0)
	triangle.TextStrokeTransparency = 0.4
	triangle.ZIndex                 = 5
	triangle.Parent                 = billboard

	-- Distance label (always at the bottom)
	local distY = hasTitle and 0.73 or 0.65
	local distH = hasTitle and 0.27 or 0.35

	local distLabel = Instance.new("TextLabel")
	distLabel.Name                   = "DistLabel"
	distLabel.Size                   = UDim2.new(1, 0, distH, 0)
	distLabel.Position               = UDim2.new(0, 0, distY, 0)
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
			distLabel.Text = formatDist((root.Position - pos).Magnitude)
		end
	end)
end

if CommandRemotes.WaypointSet then
	CommandRemotes.WaypointSet.OnClientEvent:Connect(function(pos: Vector3, title: string?)
		if typeof(pos) == "Vector3" then
			createWaypoint(pos, title)
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
