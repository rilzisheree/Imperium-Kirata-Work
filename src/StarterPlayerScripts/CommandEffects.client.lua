local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")

local LocalPlayer    = Players.LocalPlayer
local PlayerGui      = LocalPlayer:WaitForChild("PlayerGui")
local Camera         = workspace.CurrentCamera
local MarkdownParser = require(ReplicatedStorage:WaitForChild("MarkdownParser"))

local COLOR_MAP = {
        red    = Color3.fromRGB(255,  90,  90),
        blue   = Color3.fromRGB(110, 160, 255),
        green  = Color3.fromRGB( 90, 220,  90),
        yellow = Color3.fromRGB(255, 230,  80),
        orange = Color3.fromRGB(255, 160,  60),
        purple = Color3.fromRGB(190, 110, 255),
        pink   = Color3.fromRGB(255, 140, 210),
        white  = Color3.fromRGB(255, 255, 255),
        cyan   = Color3.fromRGB( 90, 225, 255),
        lime   = Color3.fromRGB(140, 255,  90),
}
local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)

local function resolveColor(name: string?): Color3
        if name and COLOR_MAP[name:lower()] then
                return COLOR_MAP[name:lower()]
        end
        return DEFAULT_COLOR
end

local function tw(target, time, props)
        TweenService:Create(target, TweenInfo.new(time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local gui = Instance.new("ScreenGui")
gui.Name           = "CommandEffects"
gui.DisplayOrder   = 96
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = PlayerGui

local blur = Instance.new("BlurEffect")
blur.Size   = 0
blur.Parent = Lighting

local smHeader = Instance.new("TextLabel")
smHeader.Name                   = "SMHeader"
smHeader.AnchorPoint            = Vector2.new(0.5, 1)
smHeader.Position               = UDim2.new(0.5, 0, 0.11, -4)
smHeader.Size                   = UDim2.new(0.75, 0, 0, 38)
smHeader.BackgroundTransparency = 1
smHeader.TextColor3             = DEFAULT_COLOR
smHeader.TextTransparency       = 0
smHeader.TextSize               = 36
smHeader.Font                   = Enum.Font.Merriweather
smHeader.Text                   = "[ Server Message ]"
smHeader.TextXAlignment         = Enum.TextXAlignment.Center
smHeader.TextYAlignment         = Enum.TextYAlignment.Center
smHeader.ZIndex                 = 10
smHeader.Visible                = false
smHeader.Parent                 = gui

local smBody = Instance.new("TextLabel")
smBody.Name                   = "SMBody"
smBody.AnchorPoint            = Vector2.new(0.5, 0)
smBody.Position               = UDim2.new(0.5, 0, 0.11, 4)
smBody.Size                   = UDim2.new(0.70, 0, 0, 0)
smBody.AutomaticSize          = Enum.AutomaticSize.Y
smBody.BackgroundTransparency = 1
smBody.TextColor3             = DEFAULT_COLOR
smBody.TextTransparency       = 0
smBody.TextSize               = 28
smBody.Font                   = Enum.Font.Merriweather
smBody.Text                   = ""
smBody.TextWrapped            = true
smBody.RichText               = true
smBody.TextXAlignment         = Enum.TextXAlignment.Center
smBody.TextYAlignment         = Enum.TextYAlignment.Top
smBody.ZIndex                 = 10
smBody.Visible                = false
smBody.Parent                 = gui

-- IM container lives in its own ScreenGui above the death scatter (DisplayOrder 98)
-- so health IMs are always readable even when the scatter is active.
local imGui = Instance.new("ScreenGui")
imGui.Name           = "CommandEffectsIM"
imGui.DisplayOrder   = 99
imGui.ResetOnSpawn   = false
imGui.IgnoreGuiInset = true
imGui.Parent         = PlayerGui

local imContainer = Instance.new("Frame")
imContainer.Name                   = "IMContainer"
imContainer.AnchorPoint            = Vector2.new(0.5, 0)
imContainer.Position               = UDim2.new(0.5, 0, 0.60, 0)
imContainer.Size                   = UDim2.new(0.50, 0, 0, 0)
imContainer.AutomaticSize          = Enum.AutomaticSize.Y
imContainer.BackgroundTransparency = 1
imContainer.ZIndex                 = 10
imContainer.Parent                 = imGui

local imLayout = Instance.new("UIListLayout")
imLayout.FillDirection       = Enum.FillDirection.Vertical
imLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
imLayout.VerticalAlignment   = Enum.VerticalAlignment.Top
imLayout.Padding             = UDim.new(0, 8)
imLayout.SortOrder           = Enum.SortOrder.LayoutOrder
imLayout.Parent              = imContainer

local imLayoutOrder = 0

local notifMsg = Instance.new("TextLabel")
notifMsg.Name                   = "NotifMsg"
notifMsg.AnchorPoint            = Vector2.new(0.5, 1)
notifMsg.Position               = UDim2.new(0.5, 0, 0.80, -4)
notifMsg.Size                   = UDim2.new(0.55, 0, 0, 0)
notifMsg.AutomaticSize          = Enum.AutomaticSize.Y
notifMsg.BackgroundTransparency = 1
notifMsg.TextColor3             = DEFAULT_COLOR
notifMsg.TextTransparency       = 1
notifMsg.TextSize               = 25
notifMsg.Font                   = Enum.Font.Merriweather
notifMsg.Text                   = ""
notifMsg.TextWrapped            = true
notifMsg.RichText               = true
notifMsg.TextXAlignment         = Enum.TextXAlignment.Center
notifMsg.TextYAlignment         = Enum.TextYAlignment.Center
notifMsg.TextStrokeTransparency = 1
notifMsg.ZIndex                 = 10
notifMsg.Visible                = false
notifMsg.Parent                 = gui

local notifSender = Instance.new("TextLabel")
notifSender.Name                   = "NotifSender"
notifSender.AnchorPoint            = Vector2.new(0.5, 0)
notifSender.Position               = UDim2.new(0.5, 0, 0.80, 4)
notifSender.Size                   = UDim2.new(0.55, 0, 0, 0)
notifSender.AutomaticSize          = Enum.AutomaticSize.Y
notifSender.BackgroundTransparency = 1
notifSender.TextColor3             = DEFAULT_COLOR
notifSender.TextTransparency       = 1
notifSender.TextSize               = 20
notifSender.Font                   = Enum.Font.Merriweather
notifSender.Text                   = ""
notifSender.TextWrapped            = true
notifSender.TextXAlignment         = Enum.TextXAlignment.Center
notifSender.TextYAlignment         = Enum.TextYAlignment.Center
notifSender.TextStrokeTransparency = 1
notifSender.ZIndex                 = 10
notifSender.Visible                = false
notifSender.Parent                 = gui

-- reading time based on word count
local function calcHold(text: string): number
        local words = select(2, text:gsub("%S+", "")) + 1
        return math.clamp(words * 0.45, 4, 10)
end

-- adds a coloured UIStroke to make text glow, returns a cleanup fn
local function applyGlow(color: Color3, labels: { TextLabel }): () -> ()
        local strokes = {}
        for _, lbl in labels do
                local s = Instance.new("UIStroke")
                s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
                s.Color           = color
                s.Thickness       = 1
                s.Transparency    = 0.92
                s.Parent          = lbl
                table.insert(strokes, s)
        end
        return function()
                for _, s in strokes do s:Destroy() end
        end
end

local smQueue: { { text: string, color: Color3, colorName: string? } } = {}
local smBusy = false
local shutdownActive = false
local serverBringToken = nil :: any

local function processSmQueue()
        if smBusy or #smQueue == 0 then return end
        smBusy = true

        local entry     = table.remove(smQueue, 1)
        local text      = entry.text
        local color     = entry.color
        local colorName = entry.colorName
        local hold      = calcHold(text)

        smBody.Text               = MarkdownParser.toRichText(text)
        smBody.TextColor3         = color
        smHeader.TextColor3       = color
        smHeader.TextTransparency = 1
        smBody.TextTransparency   = 1
        smHeader.Visible          = true
        smBody.Visible            = true
        blur.Size                 = 0

        local removeGlow = colorName and applyGlow(color, { smHeader, smBody }) or nil

        tw(blur,     0.6, { Size = 5 })
        tw(smHeader, 0.6, { TextTransparency = 0 })
        tw(smBody,   0.6, { TextTransparency = 0 })

        task.delay(0.6 + hold, function()
                if shutdownActive then return end
                if removeGlow then removeGlow() end
                tw(blur,     0.5, { Size = 0 })
                tw(smHeader, 0.5, { TextTransparency = 1 })
                tw(smBody,   0.5, { TextTransparency = 1 })
                task.delay(0.55, function()
                        if shutdownActive then return end
                        smHeader.Visible          = false
                        smHeader.TextTransparency = 0
                        smBody.Visible            = false
                        smBody.TextTransparency   = 0
                        blur.Size                 = 0
                        smBusy = false
                        processSmQueue()
                end)
        end)
end

local function showSM(text: string, colorName: string?)
        table.insert(smQueue, {
                text      = text,
                color     = resolveColor(colorName),
                colorName = colorName,
        })
        processSmQueue()
end

local function showIM(text: string, colorName: string?)
        local color = resolveColor(colorName)
        local hold  = calcHold(text)

        -- Each call gets its own label; UIListLayout stacks them in arrival order.
        imLayoutOrder += 1
        local lbl = Instance.new("TextLabel")
        lbl.Name                   = "IMLabel"
        lbl.LayoutOrder            = imLayoutOrder
        lbl.Size                   = UDim2.new(1, 0, 0, 0)
        lbl.AutomaticSize          = Enum.AutomaticSize.Y
        lbl.BackgroundTransparency = 1
        lbl.TextColor3             = color
        lbl.TextTransparency       = 1
        lbl.TextSize               = 25
        lbl.Font                   = Enum.Font.Merriweather
        lbl.Text                   = MarkdownParser.toRichText(text)
        lbl.TextWrapped            = true
        lbl.RichText               = true
        lbl.TextXAlignment         = Enum.TextXAlignment.Center
        lbl.TextYAlignment         = Enum.TextYAlignment.Center
        lbl.ZIndex                 = 10
        lbl.Parent                 = imContainer

        local removeGlow = colorName and applyGlow(color, { lbl }) or nil

        tw(lbl, 0.6, { TextTransparency = 0 })

        task.delay(0.6 + hold, function()
                if removeGlow then removeGlow() end
                tw(lbl, 0.5, { TextTransparency = 1 })
                task.delay(0.55, function()
                        lbl:Destroy()
                end)
        end)
end

-- One-shot screen flash: vignette darkening + red tint + brief shake.
-- isCritical = true for the critical HP trigger (stronger), false for the warning.
local function flashHealthEffect(isCritical: boolean)
	local shakeAmp  = isCritical and 0.010 or 0.005
	local vigTarget = isCritical and 0.62  or 0.78
	local tint      = isCritical and Color3.new(1, 0.80, 0.80) or Color3.new(1, 0.90, 0.90)
	local blurSize  = isCritical and 4     or 0
	local fadeIn    = 0.12
	local hold      = isCritical and 0.20  or 0.12
	local fadeOut   = isCritical and 0.50  or 0.35

	-- Temporary GUI that lives only for the duration of this flash
	local flashGui = Instance.new("ScreenGui")
	flashGui.Name           = "LowHealthFlash"
	flashGui.DisplayOrder   = 95
	flashGui.ResetOnSpawn   = false
	flashGui.IgnoreGuiInset = true
	flashGui.Parent         = PlayerGui

	-- Same four-frame vignette layout used by the anxiety system
	local vigFrames = {}
	local vigData = {
		{ UDim2.new(1, 0, 0.42, 0), UDim2.new(0, 0, 0,    0), 90  },
		{ UDim2.new(1, 0, 0.42, 0), UDim2.new(0, 0, 0.58, 0), 270 },
		{ UDim2.new(0.38, 0, 1, 0), UDim2.new(0, 0, 0,    0), 0   },
		{ UDim2.new(0.38, 0, 1, 0), UDim2.new(0.62, 0, 0, 0), 180 },
	}
	for _, data in vigData do
		local f = Instance.new("Frame")
		f.Size                   = data[1]
		f.Position               = data[2]
		f.BackgroundColor3       = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1
		f.BorderSizePixel        = 0
		f.ZIndex                 = 2
		f.Parent                 = flashGui
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,    0),
			NumberSequenceKeypoint.new(0.55, 0.5),
			NumberSequenceKeypoint.new(1,    1),
		})
		g.Rotation = data[3]
		g.Parent   = f
		table.insert(vigFrames, f)
	end

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.TintColor = Color3.new(1, 1, 1)
	colorCorrection.Parent    = Lighting

	local blurEffect = nil
	if blurSize > 0 then
		blurEffect = Instance.new("BlurEffect")
		blurEffect.Size   = 0
		blurEffect.Parent = Lighting
	end

	-- Fade in
	for _, f in vigFrames do tw(f, fadeIn, { BackgroundTransparency = vigTarget }) end
	tw(colorCorrection, fadeIn, { TintColor = tint })
	if blurEffect then tw(blurEffect, fadeIn, { Size = blurSize }) end

	-- Camera shake for the duration
	local shakeActive = true
	local shakeConn = RunService.RenderStepped:Connect(function()
		if not shakeActive then return end
		local rx = (math.random() * 2 - 1) * shakeAmp
		local ry = (math.random() * 2 - 1) * shakeAmp * 0.6
		Camera.CFrame = Camera.CFrame * CFrame.Angles(rx, ry, 0)
	end)

	task.delay(fadeIn + hold, function()
		shakeActive = false
		shakeConn:Disconnect()

		for _, f in vigFrames do tw(f, fadeOut, { BackgroundTransparency = 1 }) end
		tw(colorCorrection, fadeOut, { TintColor = Color3.new(1, 1, 1) })
		if blurEffect then tw(blurEffect, fadeOut, { Size = 0 }) end

		task.delay(fadeOut + 0.1, function()
			flashGui:Destroy()
			colorCorrection:Destroy()
			if blurEffect then blurEffect:Destroy() end
		end)
	end)
end

local notifSound = Instance.new("Sound")
notifSound.SoundId = "rbxassetid://131390520971848"
notifSound.Volume  = 1
notifSound.Parent  = gui

-- Heartbeat sound played alongside automatic low-health IMs (same asset used
-- by the anxiety system).
local imHeartbeatSound = Instance.new("Sound")
imHeartbeatSound.SoundId = "rbxassetid://7188240609"
imHeartbeatSound.Volume  = 0.8
imHeartbeatSound.Parent  = gui

local notifQueue: { { message: string, sender: string } } = {}
local notifBusy = false

local NOTIF_IN_T   = 0.6
local NOTIF_OUT_T  = 0.5
local NOTIF_REST_Y = 0.80 -- bottom of container sits 20% above the bottom edge

local function processNotifQueue()
        if notifBusy or #notifQueue == 0 then return end
        notifBusy = true

        local entry = table.remove(notifQueue, 1)
        local hold  = calcHold(entry.message)

        notifMsg.Text                = MarkdownParser.toRichText(entry.message)
        notifSender.Text             = "-" .. entry.sender
        notifMsg.TextTransparency    = 1
        notifSender.TextTransparency = 1
        notifMsg.Visible             = true
        notifSender.Visible          = true
        notifSound:Play()

        tw(notifMsg,    NOTIF_IN_T, { TextTransparency = 0 })
        tw(notifSender, NOTIF_IN_T, { TextTransparency = 0 })

        task.delay(NOTIF_IN_T + hold, function()
                tw(notifMsg,    NOTIF_OUT_T, { TextTransparency = 1 })
                tw(notifSender, NOTIF_OUT_T, { TextTransparency = 1 })

                task.delay(NOTIF_OUT_T + 0.05, function()
                        notifMsg.Visible    = false
                        notifSender.Visible = false
                        notifMsg.Text       = ""
                        notifSender.Text    = ""
                        notifBusy           = false
                        processNotifQueue()
                end)
        end)
end

local function showNotif(message: string, sender: string)
        table.insert(notifQueue, { message = message, sender = sender })
        processNotifQueue()
end

local DEATH_MESSAGE = "Is this.. The end of me.. The end of my.. Story. .?"
local DEATH_RED     = Color3.fromRGB(255, 80, 80)

local function showDeathScatter()
	-- Regular stacked IM in red so it appears in the normal message flow too.
	showIM(DEATH_MESSAGE, "red")
	imHeartbeatSound:Play()

	local scatterGui = Instance.new("ScreenGui")
	scatterGui.Name           = "DeathScatter"
	scatterGui.DisplayOrder   = 98
	scatterGui.ResetOnSpawn   = false
	scatterGui.IgnoreGuiInset = true
	scatterGui.Parent         = PlayerGui

	-- Four-frame red vignette (BackgroundColor3 is deep red instead of black)
	local vigFrames = {}
	local vigData = {
		{ UDim2.new(1, 0, 0.42, 0), UDim2.new(0, 0, 0,    0), 90  },
		{ UDim2.new(1, 0, 0.42, 0), UDim2.new(0, 0, 0.58, 0), 270 },
		{ UDim2.new(0.38, 0, 1, 0), UDim2.new(0, 0, 0,    0), 0   },
		{ UDim2.new(0.38, 0, 1, 0), UDim2.new(0.62, 0, 0, 0), 180 },
	}
	for _, data in vigData do
		local f = Instance.new("Frame")
		f.Size                   = data[1]
		f.Position               = data[2]
		f.BackgroundColor3       = Color3.fromRGB(160, 0, 0)
		f.BackgroundTransparency = 1
		f.BorderSizePixel        = 0
		f.ZIndex                 = 2
		f.Parent                 = scatterGui
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,    0),
			NumberSequenceKeypoint.new(0.55, 0.5),
			NumberSequenceKeypoint.new(1,    1),
		})
		g.Rotation = data[3]
		g.Parent   = f
		table.insert(vigFrames, f)
	end

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.TintColor = Color3.new(1, 1, 1)
	colorCorrection.Parent    = Lighting

	-- Fade in vignette and deep red tint
	for _, f in vigFrames do
		tw(f, 0.4, { BackgroundTransparency = 0.48 })
	end
	tw(colorCorrection, 0.4, { TintColor = Color3.new(1, 0.66, 0.66) })

	-- Brief strong shake at the moment of death
	local shakeActive = true
	local shakeConn = RunService.RenderStepped:Connect(function()
		if not shakeActive then return end
		local rx = (math.random() * 2 - 1) * 0.018
		local ry = (math.random() * 2 - 1) * 0.010
		Camera.CFrame = Camera.CFrame * CFrame.Angles(rx, ry, 0)
	end)
	task.delay(0.5, function()
		shakeActive = false
		shakeConn:Disconnect()
	end)

	-- Scatter the death message across the screen like anxiety, all in red.
	local labels = {}
	local count  = math.random(10, 14)
	for _ = 1, count do
		task.delay(math.random() * 1.8, function()
			local xPos  = math.random() * 0.62 + 0.03
			local yPos  = math.random() * 0.78 + 0.04
			local fSize = math.random(14, 24)

			local lbl = Instance.new("TextLabel")
			lbl.Text                   = DEATH_MESSAGE
			lbl.Size                   = UDim2.new(0.38, 0, 0, fSize + 10)
			lbl.Position               = UDim2.new(xPos, 0, yPos, 0)
			lbl.BackgroundTransparency = 1
			lbl.TextColor3             = DEATH_RED
			lbl.TextTransparency       = 1
			lbl.TextSize               = fSize
			lbl.Font                   = Enum.Font.Merriweather
			lbl.TextWrapped            = true
			lbl.TextXAlignment         = Enum.TextXAlignment.Left
			lbl.ZIndex                 = 5
			lbl.Parent                 = scatterGui
			table.insert(labels, lbl)
			tw(lbl, 0.5, { TextTransparency = 0.08 })
		end)
	end

	-- Hold then fade everything out
	task.delay(5.0, function()
		for _, f in vigFrames do
			tw(f, 1.5, { BackgroundTransparency = 1 })
		end
		tw(colorCorrection, 1.5, { TintColor = Color3.new(1, 1, 1) })
		for _, lbl in labels do
			if lbl.Parent then
				tw(lbl, 1.2, { TextTransparency = 1 })
			end
		end
		task.delay(1.6, function()
			scatterGui:Destroy()
			colorCorrection:Destroy()
		end)
	end)
end

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

if CommandRemotes.SM then
        CommandRemotes.SM.OnClientEvent:Connect(function(message: string, colorName: string?)
                if typeof(message) == "string" and message ~= "" then
                        showSM(message, colorName)
                end
        end)
end

if CommandRemotes.IM then
        CommandRemotes.IM.OnClientEvent:Connect(function(message: string, colorName: string?)
                if typeof(message) == "string" and message ~= "" then
                        showIM(message, colorName)
                end
        end)
end

if CommandRemotes.LowHealthIM then
        CommandRemotes.LowHealthIM.OnClientEvent:Connect(function(message: string, isCritical: boolean?)
                if typeof(message) == "string" and message ~= "" then
                        showIM(message)
                        imHeartbeatSound:Play()
                        flashHealthEffect(isCritical == true)
                end
        end)
end

if CommandRemotes.DeathIM then
        CommandRemotes.DeathIM.OnClientEvent:Connect(function()
                showDeathScatter()
        end)
end

if CommandRemotes.Notif then
        CommandRemotes.Notif.OnClientEvent:Connect(function(message: string, sender: string)
                if typeof(message) == "string" and message ~= ""
                and typeof(sender) == "string" and sender ~= "" then
                        showNotif(message, sender)
                end
        end)
end

-- ────────────────────────────────────────────────────────────────────────────
-- Local health monitor — runs on the client so HealthChanged is always fired
-- regardless of how the server applies damage.
-- ────────────────────────────────────────────────────────────────────────────

local LOW_HEALTH_MESSAGES = {
	"Shit... I'm hurt...",
	"I don't think I can keep this up...",
	"Everything hurts...",
	"Fuck.. I need to be more careful..",
	"I can't take much more...",
	"I have to survive.. I can't fall here..",
	"This isn't good..",
	"Stay focused...",
	"I'm barely standing...",
}

local LOW_HEALTH_THRESHOLD = 0.30  -- 30 % of max health fires the warning IM
local LOW_CRITICAL_HEALTH  = 8     -- absolute HP at which the critical IM fires

local function setupHealthMonitor(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then return end

	local state = 0  -- 0: healthy, 1: warning fired, 2: critical fired

	humanoid.HealthChanged:Connect(function(health: number)
		local maxHealth = humanoid.MaxHealth
		if maxHealth <= 0 then return end

		if health <= LOW_CRITICAL_HEALTH then
			if state < 2 then
				if state == 0 then
					-- Jumped past warning on the way down — fire warning first.
					showIM(LOW_HEALTH_MESSAGES[math.random(1, #LOW_HEALTH_MESSAGES)])
					imHeartbeatSound:Play()
					flashHealthEffect(false)
				end
				state = 2
				showIM(LOW_HEALTH_MESSAGES[math.random(1, #LOW_HEALTH_MESSAGES)])
				imHeartbeatSound:Play()
				flashHealthEffect(true)
			end
		elseif health / maxHealth < LOW_HEALTH_THRESHOLD then
			if state == 0 then
				state = 1
				showIM(LOW_HEALTH_MESSAGES[math.random(1, #LOW_HEALTH_MESSAGES)])
				imHeartbeatSound:Play()
				flashHealthEffect(false)
			elseif state == 2 then
				state = 1  -- recovered above critical but still in warning zone
			end
		else
			state = 0  -- fully recovered
		end
	end)
end

LocalPlayer.CharacterAdded:Connect(setupHealthMonitor)
if LocalPlayer.Character then
	task.spawn(setupHealthMonitor, LocalPlayer.Character)
end

-- ────────────────────────────────────────────────────────────────────────────

local blindGui = Instance.new("ScreenGui")
blindGui.Name           = "BlindEffect"
blindGui.DisplayOrder   = 95    -- below CmdBarGui (100) and CmdNotifyGui (110); CoreGui chat is always on top
blindGui.ResetOnSpawn   = false -- we handle respawn cleanup ourselves
blindGui.IgnoreGuiInset = true
blindGui.Enabled        = false
blindGui.Parent         = PlayerGui

local blindFrame = Instance.new("Frame", blindGui)
blindFrame.Size                   = UDim2.new(1, 0, 1, 0)
blindFrame.BackgroundColor3       = Color3.new(0, 0, 0)
blindFrame.BackgroundTransparency = 0
blindFrame.BorderSizePixel        = 0

local isBlinded  = false
local blindTween = nil

local function applyBlind(duration: number?)
        if isBlinded then return end
        isBlinded        = true
        blindGui.Enabled = true
        blindFrame.BackgroundTransparency = 1

        local fadeDuration = (duration and duration > 0) and duration or 1.0
        local style        = (duration and duration > 0) and Enum.EasingStyle.Linear or Enum.EasingStyle.Quint

        blindTween = TweenService:Create(
                blindFrame,
                TweenInfo.new(fadeDuration, style, Enum.EasingDirection.Out),
                { BackgroundTransparency = 0 }
        )
        blindTween:Play()
end

local function removeBlind()
        if not isBlinded then return end
        isBlinded = false
        if blindTween then
                blindTween:Cancel()
                blindTween = nil
        end
        local t = TweenService:Create(
                blindFrame,
                TweenInfo.new(1.0, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { BackgroundTransparency = 1 }
        )
        t:Play()
        t.Completed:Connect(function()
                blindGui.Enabled = false
                blindFrame.BackgroundTransparency = 0
        end)
end

LocalPlayer.CharacterAdded:Connect(removeBlind)

if CommandRemotes.Blind then
        CommandRemotes.Blind.OnClientEvent:Connect(applyBlind)
end

if CommandRemotes.Unblind then
        CommandRemotes.Unblind.OnClientEvent:Connect(removeBlind)
end

if CommandRemotes.Shutdown then
        CommandRemotes.Shutdown.OnClientEvent:Connect(function()
                -- freeze the SM queue so no queued/in-flight SM timer can clear the shutdown screen
                shutdownActive = true
                smBusy         = true
                table.clear(smQueue)

                smHeader.Text             = "Server Shutting Down"
                smBody.Text               = "A Staff Member has shut down this server,\nPlease rejoin shortly."
                smHeader.TextColor3       = DEFAULT_COLOR
                smBody.TextColor3         = DEFAULT_COLOR
                smHeader.TextTransparency = 1
                smBody.TextTransparency   = 1
                smHeader.Visible          = true
                smBody.Visible            = true
                blur.Size                 = 0

                tw(blur,     0.6, { Size = 5 })
                tw(smHeader, 0.6, { TextTransparency = 0 })
                tw(smBody,   0.6, { TextTransparency = 0 })

                local char = LocalPlayer.Character
                if char then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then
                                hum.WalkSpeed  = 0
                                hum.JumpHeight = 0
                                hum.JumpPower  = 0
                        end
                end
        end)
end

if CommandRemotes.ServerBringNotice then
        CommandRemotes.ServerBringNotice.OnClientEvent:Connect(function()
                -- freeze the SM queue so no queued/in-flight SM timer can clear this screen;
                -- it normally stays up until the teleport happens and the client leaves the
                -- game, but unlike a real shutdown the teleport can fail, so we use our own
                -- flag (not shutdownActive) plus a safety timeout to release the queue again
                local myToken = {}
                serverBringToken = myToken
                smBusy = true
                table.clear(smQueue)

                smHeader.Text             = "Server Bring"
                smBody.Text               = "You're being brought to another server.."
                smHeader.TextColor3       = DEFAULT_COLOR
                smBody.TextColor3         = DEFAULT_COLOR
                smHeader.TextTransparency = 1
                smBody.TextTransparency   = 1
                smHeader.Visible          = true
                smBody.Visible            = true
                blur.Size                 = 0

                tw(blur,     0.6, { Size = 5 })
                tw(smHeader, 0.6, { TextTransparency = 0 })
                tw(smBody,   0.6, { TextTransparency = 0 })

                -- safety net: if the teleport hasn't happened within 20s (e.g. it failed),
                -- clear the screen and let the SM queue resume instead of staying stuck
                task.delay(20, function()
                        if serverBringToken ~= myToken or shutdownActive then return end
                        serverBringToken = nil
                        tw(blur,     0.5, { Size = 0 })
                        tw(smHeader, 0.5, { TextTransparency = 1 })
                        tw(smBody,   0.5, { TextTransparency = 1 })
                        task.delay(0.55, function()
                                if shutdownActive then return end
                                smHeader.Visible          = false
                                smHeader.TextTransparency = 0
                                smBody.Visible            = false
                                smBody.TextTransparency   = 0
                                blur.Size                 = 0
                                smBusy                    = false
                                processSmQueue()
                        end)
                end)
        end)
end
