local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer    = Players.LocalPlayer
local PlayerGui      = LocalPlayer:WaitForChild("PlayerGui")
local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local espGui = Instance.new("ScreenGui")
espGui.Name           = "EspGui"
espGui.DisplayOrder   = 98
espGui.ResetOnSpawn   = false
espGui.IgnoreGuiInset = true
espGui.Parent         = PlayerGui

-- tracked[userId] = {
--   player:     Player,
--   billboard:  BillboardGui,
--   highlight:  Highlight,
--   nameLabel:  TextLabel,
--   hpLabel:    TextLabel,
--   teamLabel:  TextLabel,
--   distLabel:  TextLabel,
--   conns:      { RBXScriptConnection },
-- }
local tracked: { [number]: any } = {}

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

local function makeLabel(parent: Instance, yPos: number, height: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, 0, 0, height)
	lbl.Position               = UDim2.new(0, 0, 0, yPos)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = Color3.fromRGB(255, 255, 255)
	lbl.TextSize               = 13
	lbl.Font                   = Enum.Font.Gotham
	lbl.TextXAlignment         = Enum.TextXAlignment.Center
	lbl.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	lbl.TextStrokeTransparency = 0.35
	lbl.Text                   = ""
	lbl.Parent                 = parent
	return lbl
end

local LINE  = 16   -- px per line
local GAP   = 2    -- px between lines
local TOTAL = 4 * LINE + 3 * GAP   -- 70px

local function buildOverlay(player: Player, character: Model?)
	local _, teamColor = getTeamInfo(player)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	local bb = Instance.new("BillboardGui")
	bb.Name                  = "EspBillboard"
	bb.Adornee               = root
	bb.AlwaysOnTop           = true
	bb.Size                  = UDim2.new(0, 160, 0, TOTAL)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0)
	bb.ResetOnSpawn          = false
	bb.Enabled               = root ~= nil
	bb.Parent                = espGui

	local y = 0
	local nameLabel = makeLabel(bb, y, LINE) ; nameLabel.Font = Enum.Font.GothamBold
	y += LINE + GAP
	local hpLabel   = makeLabel(bb, y, LINE)
	y += LINE + GAP
	local teamLabel = makeLabel(bb, y, LINE)
	y += LINE + GAP
	local distLabel = makeLabel(bb, y, LINE)

	nameLabel.Text       = player.Name
	teamLabel.TextColor3 = teamColor

	-- character highlight (local — parented to espGui, not workspace)
	local highlight = Instance.new("Highlight")
	highlight.Adornee             = character
	highlight.FillColor           = teamColor
	highlight.FillTransparency    = 0.85
	highlight.OutlineColor        = teamColor
	highlight.OutlineTransparency = 0.05
	highlight.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled             = character ~= nil
	highlight.Parent              = espGui

	return bb, highlight, nameLabel, hpLabel, teamLabel, distLabel
end

local function removeEsp(userId: number)
	local entry = tracked[userId]
	if not entry then return end
	tracked[userId] = nil
	for _, conn in entry.conns do conn:Disconnect() end
	if entry.billboard and entry.billboard.Parent then entry.billboard:Destroy() end
	if entry.highlight and entry.highlight.Parent then entry.highlight:Destroy() end
end

local function addEsp(player: Player)
	if tracked[player.UserId] then removeEsp(player.UserId) end

	local character = player.Character
	local bb, hl, nameLabel, hpLabel, teamLabel, distLabel =
		buildOverlay(player, character)

	local conns = {}

	table.insert(conns, player.CharacterAdded:Connect(function(newChar)
		local entry = tracked[player.UserId]
		if not entry then return end
		local newRoot = newChar:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		entry.billboard.Adornee = newRoot
		entry.billboard.Enabled = newRoot ~= nil
		entry.highlight.Adornee = newChar
		entry.highlight.Enabled = true
	end))

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
		nameLabel = nameLabel,
		hpLabel   = hpLabel,
		teamLabel = teamLabel,
		distLabel = distLabel,
		conns     = conns,
	}
end

RunService.Heartbeat:Connect(function()
	if next(tracked) == nil then return end

	local adminChar = LocalPlayer.Character
	local adminRoot = adminChar and adminChar:FindFirstChild("HumanoidRootPart") :: BasePart?

	for userId, entry in tracked do
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

		if entry.billboard.Adornee ~= root      then entry.billboard.Adornee = root      end
		if entry.highlight.Adornee ~= character  then entry.highlight.Adornee = character end

		-- health
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local hp    = math.floor(humanoid.Health)
			local maxHp = math.floor(humanoid.MaxHealth)
			entry.hpLabel.Text = hp .. " / " .. maxHp
			local ratio = maxHp > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
			entry.hpLabel.TextColor3 = Color3.fromRGB(
				math.round((1 - ratio) * 225 + 15),
				math.round(ratio       * 215 + 25),
				30
			)
		end

		-- team
		local teamName, teamColor    = getTeamInfo(entry.player)
		entry.teamLabel.Text         = teamName
		entry.teamLabel.TextColor3   = teamColor
		entry.highlight.FillColor    = teamColor
		entry.highlight.OutlineColor = teamColor

		-- distance
		if adminRoot then
			entry.distLabel.Text = formatDist((root.Position - adminRoot.Position).Magnitude)
		else
			entry.distLabel.Text = "..."
		end
	end
end)

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
