local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes") :: ModuleScript)

-- exact palette from CommandBar
local C_BG   = Color3.fromRGB(12,  12,  18)
local C_BOR  = Color3.fromRGB(90,  90, 120)
local C_DIM  = Color3.fromRGB(80,  80, 100)
local C_OK   = Color3.fromRGB(130, 160, 255)
local C_FAIL = Color3.fromRGB(215,  75,  75)

local CARD_W    = 290
local CARD_H    = 66
local MARGIN_R  = 14
local GAP       = 7
local HOLD      = 2.5
local MAX_STACK = 5

local sg = Instance.new("ScreenGui")
sg.Name           = "CmdNotifyGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.DisplayOrder   = 110
sg.Parent         = PGui

local tweenIn     = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local tweenOut    = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local tweenReflow = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- stack[i] = { card = Frame, activeTween = Tween? }
-- a card is removed from the stack the moment its dismiss begins,
-- so reflow never races with the slide-out tween
local stack = {}

local REST_X_SCALE  = 1
local REST_X_OFFSET = -MARGIN_R
local OFF_X_SCALE   = 1
local OFF_X_OFFSET  = CARD_W + MARGIN_R + 20

-- Y for a 0-based slot index, centred vertically
local function yFor(slot)
	return 0.5, -CARD_H / 2 + slot * (CARD_H + GAP)
end

local function restPos(slot)
	local ys, yo = yFor(slot)
	return UDim2.new(REST_X_SCALE, REST_X_OFFSET, ys, yo)
end

local function offPos(slot)
	local ys, yo = yFor(slot)
	return UDim2.new(OFF_X_SCALE, OFF_X_OFFSET, ys, yo)
end

-- cancel the current reflow tween (if any) and start a new one to the correct slot
local function reflowStack()
	for i, entry in ipairs(stack) do
		local slot = i - 1
		if entry.activeTween then entry.activeTween:Cancel() end
		local t = TweenService:Create(entry.card, tweenReflow, { Position = restPos(slot) })
		entry.activeTween = t
		t:Play()
	end
end

local function notify(success, msg)
	if #stack >= MAX_STACK then return end

	local card = Instance.new("Frame", sg)
	card.AnchorPoint      = Vector2.new(1, 0)
	card.Size             = UDim2.new(0, CARD_W, 0, CARD_H)
	card.BackgroundColor3 = C_BG
	card.BorderSizePixel  = 0
	card.ClipsDescendants = false

	local entry = { card = card, activeTween = nil }
	table.insert(stack, entry)

	-- start off-screen at the slot it will animate into
	local slot = #stack - 1
	card.Position = offPos(slot)

	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke", card)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color           = C_BOR
	stroke.Thickness       = 1.5

	-- coloured left accent bar
	local accent = Instance.new("Frame", card)
	accent.AnchorPoint      = Vector2.new(0, 0.5)
	accent.Size             = UDim2.new(0, 3, 1, -18)
	accent.Position         = UDim2.new(0, 10, 0.5, 0)
	accent.BackgroundColor3 = success and C_OK or C_FAIL
	accent.BorderSizePixel  = 0
	Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

	-- title
	local title = Instance.new("TextLabel", card)
	title.Size               = UDim2.new(1, -28, 0, 20)
	title.Position           = UDim2.new(0, 22, 0, 11)
	title.BackgroundTransparency = 1
	title.Font               = Enum.Font.GothamBold
	title.TextSize           = 13
	title.TextColor3         = success and C_OK or C_FAIL
	title.TextXAlignment     = Enum.TextXAlignment.Left
	title.TextYAlignment     = Enum.TextYAlignment.Center
	title.Text               = success and "Command Executed" or "Command Failed"

	-- subtitle (server feedback message)
	local sub = Instance.new("TextLabel", card)
	sub.Size               = UDim2.new(1, -28, 0, 16)
	sub.Position           = UDim2.new(0, 22, 0, 34)
	sub.BackgroundTransparency = 1
	sub.Font               = Enum.Font.Gotham
	sub.TextSize           = 11
	sub.TextColor3         = C_DIM
	sub.TextXAlignment     = Enum.TextXAlignment.Left
	sub.TextYAlignment     = Enum.TextYAlignment.Center
	sub.TextWrapped        = false
	sub.TextTruncate       = Enum.TextTruncate.AtEnd
	sub.Text               = msg

	-- subtle top-edge highlight for depth
	local shine = Instance.new("Frame", card)
	shine.Size               = UDim2.new(1, -20, 0, 1)
	shine.Position           = UDim2.new(0, 10, 0, 1)
	shine.BackgroundColor3   = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.88
	shine.BorderSizePixel    = 0
	Instance.new("UICorner", shine).CornerRadius = UDim.new(0, 1)

	-- slide in (reflow also moves any cards that were already present)
	reflowStack()

	-- hold, then remove from stack immediately and slide out independently
	task.delay(HOLD, function()
		-- find and remove from stack now so reflow won't touch this card
		local dismissSlot = 0
		for i, e in ipairs(stack) do
			if e == entry then
				dismissSlot = i - 1
				table.remove(stack, i)
				break
			end
		end

		-- cancel any reflow tween that was running on this card
		if entry.activeTween then entry.activeTween:Cancel() end

		-- slide out from its current visual slot
		local tween = TweenService:Create(card, tweenOut, { Position = offPos(dismissSlot) })
		tween:Play()
		tween.Completed:Connect(function() card:Destroy() end)

		-- repack the remaining cards
		reflowStack()
	end)
end

CommandRemotes.CommandFeedback.OnClientEvent:Connect(notify)
