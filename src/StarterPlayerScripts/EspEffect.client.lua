local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer    = Players.LocalPlayer
local PlayerGui      = LocalPlayer:WaitForChild("PlayerGui")
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

-- ── container ──────────────────────────────────────────────────────────────────

-- ResetOnSpawn = false: ESP persists through admin death/respawn
local espGui = Instance.new("ScreenGui")
espGui.Name           = "EspGui"
espGui.DisplayOrder   = 98
espGui.ResetOnSpawn   = false
espGui.IgnoreGuiInset = true
espGui.Parent         = PlayerGui

-- ── state ──────────────────────────────────────────────────────────────────────

-- tracked[userId] = {
--   player:    Player,
--   billboard: BillboardGui,   -- parented to espGui (local, doesn't replicate)
--   highlight: Highlight,      -- parented to espGui, Adornee = character
--   stroke:    UIStroke,
--   nameLabel: TextLabel,
--   hpLabel:   TextLabel,
--   teamLabel: TextLabel,
--   distLabel: TextLabel,
--   conns:     { RBXScriptConnection },
-- }
local tracked: { [number]: any } = {}

-- ── helpers ────────────────────────────────────────────────────────────────────

local function formatDist(studs: number): string
	local m = math.round(studs)
	if m >= 1000 then return string.format("%.1fkm", m / 1000) end
	return m .. "m"
end

local function getTeamInfo(player: Player): (string, Color3)
	local team = player.Team
	if team then return team.Name, team.TeamColor.Color end
	return "No Team", Color3.fromRGB(180, 180, 180)
end

-- ── build overlay ──────────────────────────────────────────────────────────────

local function buildOverlay(player: Player, character: Model?)
	local teamName, teamColor = getTeamInfo(player)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- BillboardGui: AlwaysOnTop so it shows through walls
	local bb = Instance.new("BillboardGui")
	bb.Name                  = "EspBillboard"
	bb.Adornee               = root
	bb.AlwaysOnTop           = true
	bb.Size                  = UDim2.new(0, 192, 0, 64)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	bb.ResetOnSpawn          = false
	bb.Enabled               = root ~= nil
	bb.Parent                = espGui

	-- Dark translucent background
	local bg = Instance.new("Frame")
	bg.Name                   = "Bg"
	bg.Size                   = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3       = Color3.fromRGB(10, 10, 16)
	bg.BackgroundTransparency = 0.28
	bg.BorderSizePixel        = 0
	bg.Parent                 = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent       = bg

	-- Coloured outline that updates with team colour
	local stroke = Instance.new("UIStroke")
	stroke.Color        = teamColor
	stroke.Thickness    = 1.5
	stroke.Transparency = 0
	stroke.Parent       = bg

	-- Row 1: @Username (left) + distance (right)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name                   = "NameLabel"
	nameLabel.Size                   = UDim2.new(0.65, -8, 0, 20)
	nameLabel.Position               = UDim2.new(0, 7, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text                   = "@" .. player.Name
	nameLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize               = 13
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
	nameLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.45
	nameLabel.Parent                 = bg

	local distLabel = Instance.new("TextLabel")
	distLabel.Name                   = "DistLabel"
	distLabel.Size                   = UDim2.new(0.35, -7, 0, 20)
	distLabel.Position               = UDim2.new(0.65, 0, 0, 5)
	distLabel.BackgroundTransparency = 1
	distLabel.Text                   = "..."
	distLabel.TextColor3             = Color3.fromRGB(190, 190, 190)
	distLabel.TextSize               = 12
	distLabel.Font                   = Enum.Font.Gotham
	distLabel.TextXAlignment         = Enum.TextXAlignment.Right
	distLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	distLabel.TextStrokeTransparency = 0.45
	distLabel.Parent                 = bg

	-- Row 2: health bar label
	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name                   = "HpLabel"
	hpLabel.Size                   = UDim2.new(1, -14, 0, 17)
	hpLabel.Position               = UDim2.new(0, 7, 0, 27)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Text                   = "HP: —"
	hpLabel.TextColor3             = Color3.fromRGB(100, 240, 120)
	hpLabel.TextSize               = 11
	hpLabel.Font                   = Enum.Font.Gotham
	hpLabel.TextXAlignment         = Enum.TextXAlignment.Left
	hpLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	hpLabel.TextStrokeTransparency = 0.45
	hpLabel.Parent                 = bg

	-- Row 3: team name (left) + location (right)
	local teamLabel = Instance.new("TextLabel")
	teamLabel.Name                   = "TeamLabel"
	teamLabel.Size                   = UDim2.new(0.6, -7, 0, 15)
	teamLabel.Position               = UDim2.new(0, 7, 0, 46)
	teamLabel.BackgroundTransparency = 1
	teamLabel.Text                   = teamName
	teamLabel.TextColor3             = teamColor
	teamLabel.TextSize               = 10
	teamLabel.Font                   = Enum.Font.Gotham
	teamLabel.TextXAlignment         = Enum.TextXAlignment.Left
	teamLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	teamLabel.TextStrokeTransparency = 0.45
	teamLabel.Parent                 = bg

	local locLabel = Instance.new("TextLabel")
	locLabel.Name                   = "LocLabel"
	locLabel.Size                   = UDim2.new(0.4, -7, 0, 15)
	locLabel.Position               = UDim2.new(0.6, 0, 0, 46)
	locLabel.BackgroundTransparency = 1
	locLabel.Text                   = "Unknown"
	locLabel.TextColor3             = Color3.fromRGB(155, 155, 155)
	locLabel.TextSize               = 10
	locLabel.Font                   = Enum.Font.Gotham
	locLabel.TextXAlignment         = Enum.TextXAlignment.Right
	locLabel.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	locLabel.TextStrokeTransparency = 0.45
	locLabel.Parent                 = bg

	-- Character highlight (AlwaysOnTop, local to this client via espGui parent)
	local highlight = Instance.new("Highlight")
	highlight.Adornee             = character
	highlight.FillColor           = teamColor
	highlight.FillTransparency    = 0.85
	highlight.OutlineColor        = teamColor
	highlight.OutlineTransparency = 0.05
	highlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled             = character ~= nil
	highlight.Parent              = espGui

	return bb, highlight, stroke, nameLabel, hpLabel, teamLabel, distLabel
end

-- ── add / remove ───────────────────────────────────────────────────────────────

local function removeEsp(userId: number)
	local entry = tracked[userId]
	if not entry then return end
	tracked[userId] = nil

	for _, conn in entry.conns do
		conn:Disconnect()
	end
	if entry.billboard and entry.billboard.Parent then
		entry.billboard:Destroy()
	end
	if entry.highlight and entry.highlight.Parent then
		entry.highlight:Destroy()
	end
end

local function addEsp(player: Player)
	-- idempotent: removing first prevents duplicate overlays
	if tracked[player.UserId] then removeEsp(player.UserId) end

	local character = player.Character
	local bb, hl, stroke, nameLabel, hpLabel, teamLabel, distLabel =
		buildOverlay(player, character)

	local conns = {}

	-- re-attach adornees when the target respawns
	table.insert(conns, player.CharacterAdded:Connect(function(newChar)
		local entry = tracked[player.UserId]
		if not entry then return end

		local newRoot = newChar:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		entry.billboard.Adornee = newRoot
		entry.billboard.Enabled = newRoot ~= nil
		entry.highlight.Adornee = newChar
		entry.highlight.Enabled = true
	end))

	-- auto-remove when the target leaves
	local removingConn
	removingConn = Players.PlayerRemoving:Connect(function(leaving)
		if leaving.UserId ~= player.UserId then return end
		removingConn:Disconnect()
		removeEsp(player.UserId)
	end)
	table.insert(conns, removingConn)

	tracked[player.UserId] = {
		player    = player,
		billboard = bb,
		highlight = hl,
		stroke    = stroke,
		nameLabel = nameLabel,
		hpLabel   = hpLabel,
		teamLabel = teamLabel,
		distLabel = distLabel,
		conns     = conns,
	}
end

-- ── per-frame update ───────────────────────────────────────────────────────────

-- single shared heartbeat: one connection for all tracked players
RunService.Heartbeat:Connect(function()
	if next(tracked) == nil then return end  -- nothing tracked; skip entirely

	local adminChar = LocalPlayer.Character
	local adminRoot = adminChar and adminChar:FindFirstChild("HumanoidRootPart") :: BasePart?

	for userId, entry in tracked do
		-- player left but PlayerRemoving fired before cleanup completed
		if not entry.player.Parent then
			removeEsp(userId)
			continue
		end

		local character = entry.player.Character

		if not character then
			entry.billboard.Enabled = false
			entry.highlight.Enabled = false
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			entry.billboard.Enabled = false
			entry.highlight.Enabled = false
			continue
		end

		entry.billboard.Enabled = true
		entry.highlight.Enabled = true

		-- keep adornees in sync (CharacterAdded may have fired before the loop runs)
		if entry.billboard.Adornee ~= root     then entry.billboard.Adornee = root      end
		if entry.highlight.Adornee ~= character then entry.highlight.Adornee = character end

		-- health
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local hp    = math.floor(humanoid.Health)
			local maxHp = math.floor(humanoid.MaxHealth)
			entry.hpLabel.Text = "HP: " .. hp .. " / " .. maxHp
			-- interpolate green → red as HP drops
			local ratio = maxHp > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
			entry.hpLabel.TextColor3 = Color3.fromRGB(
				math.round((1 - ratio) * 225 + 15),
				math.round(ratio       * 215 + 25),
				30
			)
		end

		-- team (can change at runtime)
		local teamName, teamColor = getTeamInfo(entry.player)
		entry.teamLabel.Text              = teamName
		entry.teamLabel.TextColor3        = teamColor
		entry.stroke.Color                = teamColor
		entry.highlight.FillColor         = teamColor
		entry.highlight.OutlineColor      = teamColor

		-- distance from admin
		if adminRoot then
			local dist = (root.Position - adminRoot.Position).Magnitude
			entry.distLabel.Text = formatDist(dist)
		else
			entry.distLabel.Text = "..."
		end
	end
end)

-- ── remote listener ────────────────────────────────────────────────────────────

if CommandRemotes.EspToggle then
	CommandRemotes.EspToggle.OnClientEvent:Connect(function(target: Player, enabled: boolean)
		if typeof(target) ~= "Instance" or not target:IsA("Player") then return end
		if enabled then
			addEsp(target)
		else
			removeEsp(target.UserId)
		end
	end)
end
