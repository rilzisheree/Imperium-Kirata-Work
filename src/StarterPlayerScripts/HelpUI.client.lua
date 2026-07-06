local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local CARD_W    = 300
local PAD       = 12
local CORNER    = 10
local BG_COLOR  = Color3.fromRGB(15, 15, 20)
local BG_TRANS  = 0.18
local NAME_CLR  = Color3.fromRGB(240, 240, 250)
local USER_CLR  = Color3.fromRGB(150, 150, 175)
local MSG_CLR   = Color3.fromRGB(220, 220, 235)

local gui = Instance.new("ScreenGui")
gui.Name           = "CmdNotifyGui"
gui.DisplayOrder   = 110
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Parent         = PlayerGui

local holder = Instance.new("Frame", gui)
holder.Name                   = "HelpNotifications"
holder.AnchorPoint            = Vector2.new(0, 1)
holder.Position               = UDim2.new(0, 20, 1, -20)
holder.Size                   = UDim2.new(0, CARD_W, 0, 0)
holder.AutomaticSize          = Enum.AutomaticSize.Y
holder.BackgroundTransparency = 1
holder.Visible                = true

local layout = Instance.new("UIListLayout", holder)
layout.FillDirection       = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.VerticalAlignment   = Enum.VerticalAlignment.Bottom
layout.SortOrder           = Enum.SortOrder.LayoutOrder
layout.Padding             = UDim.new(0, 8)

local orderCounter = 0
local cardsByRequest = {}   -- requestId -> card frame
local cardsByUser     = {}  -- fromUserId -> { [requestId] = card frame }

local uiEnabled = true

-- camera hover-follow state
local Camera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Camera = workspace.CurrentCamera
end)

local savedCameraType    = nil
local savedCameraSubject = nil
local hoveredCard         = nil

local function restoreCamera()
        if savedCameraType == nil and savedCameraSubject == nil then return end
        if Camera then
                Camera.CameraType    = savedCameraType
                Camera.CameraSubject = savedCameraSubject
        end
        savedCameraType    = nil
        savedCameraSubject = nil
end

local function focusCameraOn(userId: number)
        local target = Players:GetPlayerByUserId(userId)
        local character = target and target.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid or not Camera then return end

        if savedCameraType == nil and savedCameraSubject == nil then
                savedCameraType    = Camera.CameraType
                savedCameraSubject = Camera.CameraSubject
        end
        Camera.CameraType    = Enum.CameraType.Custom
        Camera.CameraSubject = humanoid
end

local function removeCard(requestId: string)
        local card = cardsByRequest[requestId]
        if not card then return end

        if hoveredCard == card then
                hoveredCard = nil
                restoreCamera()
        end

        cardsByRequest[requestId] = nil
        local uid = card:GetAttribute("FromUserId")
        if uid and cardsByUser[uid] then
                cardsByUser[uid][requestId] = nil
                if next(cardsByUser[uid]) == nil then
                        cardsByUser[uid] = nil
                end
        end

        local fadeOut = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        local t = TweenService:Create(card, fadeOut, { BackgroundTransparency = 1 })
        t:Play()
        t.Completed:Connect(function()
                pcall(function() card:Destroy() end)
        end)
        for _, child in card:GetDescendants() do
                if child:IsA("TextLabel") then
                        TweenService:Create(child, fadeOut, { TextTransparency = 1 }):Play()
                elseif child:IsA("UIStroke") then
                        TweenService:Create(child, fadeOut, { Transparency = 1 }):Play()
                end
        end
end

local function createCard(payload)
        orderCounter += 1

        local card = Instance.new("TextButton")
        card.Name                   = "HelpCard"
        card.LayoutOrder            = orderCounter
        card.Size                   = UDim2.new(1, 0, 0, 0)
        card.AutomaticSize          = Enum.AutomaticSize.Y
        card.BackgroundColor3       = BG_COLOR
        card.BackgroundTransparency = 1
        card.BorderSizePixel        = 0
        card.Text                   = ""
        card.AutoButtonColor        = false
        card:SetAttribute("FromUserId", payload.fromUserId)
        card:SetAttribute("RequestId", payload.requestId)
        card.Parent = holder

        Instance.new("UICorner", card).CornerRadius = UDim.new(0, CORNER)
        local stroke = Instance.new("UIStroke", card)
        stroke.Color       = Color3.fromRGB(90, 90, 120)
        stroke.Thickness   = 1
        stroke.Transparency = 1
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

        local pad = Instance.new("UIPadding", card)
        pad.PaddingLeft   = UDim.new(0, PAD)
        pad.PaddingRight  = UDim.new(0, PAD)
        pad.PaddingTop    = UDim.new(0, PAD)
        pad.PaddingBottom = UDim.new(0, PAD)

        local listLayout = Instance.new("UIListLayout", card)
        listLayout.FillDirection = Enum.FillDirection.Vertical
        listLayout.SortOrder     = Enum.SortOrder.LayoutOrder
        listLayout.Padding       = UDim.new(0, 2)

        local nameLbl = Instance.new("TextLabel", card)
        nameLbl.LayoutOrder            = 1
        nameLbl.BackgroundTransparency = 1
        nameLbl.Size                   = UDim2.new(1, 0, 0, 22)
        nameLbl.Font                   = Enum.Font.GothamBold
        nameLbl.TextSize               = 18
        nameLbl.TextColor3             = NAME_CLR
        nameLbl.TextTransparency       = 1
        nameLbl.TextXAlignment         = Enum.TextXAlignment.Left
        nameLbl.TextTruncate           = Enum.TextTruncate.AtEnd
        nameLbl.Text                   = payload.fromDisplayName

        local userLbl = Instance.new("TextLabel", card)
        userLbl.LayoutOrder            = 2
        userLbl.BackgroundTransparency = 1
        userLbl.Size                   = UDim2.new(1, 0, 0, 16)
        userLbl.Font                   = Enum.Font.Gotham
        userLbl.TextSize               = 13
        userLbl.TextColor3             = USER_CLR
        userLbl.TextTransparency       = 1
        userLbl.TextXAlignment         = Enum.TextXAlignment.Left
        userLbl.TextTruncate           = Enum.TextTruncate.AtEnd
        userLbl.Text                   = "@" .. payload.fromName

        local teamLbl = Instance.new("TextLabel", card)
        teamLbl.LayoutOrder            = 3
        teamLbl.BackgroundTransparency = 1
        teamLbl.Size                   = UDim2.new(1, 0, 0, 16)
        teamLbl.Font                   = Enum.Font.GothamSemibold
        teamLbl.TextSize               = 13
        teamLbl.TextColor3             = payload.teamColor or Color3.fromRGB(200, 200, 200)
        teamLbl.TextTransparency       = 1
        teamLbl.TextXAlignment         = Enum.TextXAlignment.Left
        teamLbl.TextTruncate           = Enum.TextTruncate.AtEnd
        teamLbl.Text                   = payload.teamName or "No Team"

        local msgLbl = Instance.new("TextLabel", card)
        msgLbl.LayoutOrder            = 4
        msgLbl.BackgroundTransparency = 1
        msgLbl.Size                   = UDim2.new(1, 0, 0, 0)
        msgLbl.AutomaticSize          = Enum.AutomaticSize.Y
        msgLbl.Font                   = Enum.Font.Gotham
        msgLbl.TextSize               = 14
        msgLbl.TextColor3             = MSG_CLR
        msgLbl.TextTransparency       = 1
        msgLbl.TextWrapped            = true
        msgLbl.TextXAlignment         = Enum.TextXAlignment.Left
        msgLbl.TextYAlignment         = Enum.TextYAlignment.Top
        msgLbl.Text                   = payload.message

        local pad2 = Instance.new("UIPadding", msgLbl)
        pad2.PaddingTop = UDim.new(0, 4)

        card.MouseEnter:Connect(function()
                hoveredCard = card
                focusCameraOn(payload.fromUserId)
        end)
        card.MouseLeave:Connect(function()
                if hoveredCard == card then
                        hoveredCard = nil
                        restoreCamera()
                end
        end)
        card.MouseButton1Click:Connect(function()
                removeCard(payload.requestId)
        end)

        local fadeIn = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(card,   fadeIn, { BackgroundTransparency = BG_TRANS }):Play()
        TweenService:Create(stroke, fadeIn, { Transparency = 0.35 }):Play()
        TweenService:Create(nameLbl, fadeIn, { TextTransparency = 0 }):Play()
        TweenService:Create(userLbl, fadeIn, { TextTransparency = 0.15 }):Play()
        TweenService:Create(teamLbl, fadeIn, { TextTransparency = 0 }):Play()
        TweenService:Create(msgLbl,  fadeIn, { TextTransparency = 0.05 }):Play()

        cardsByRequest[payload.requestId] = card
        cardsByUser[payload.fromUserId] = cardsByUser[payload.fromUserId] or {}
        cardsByUser[payload.fromUserId][payload.requestId] = card
end

CommandRemotes.HelpRequest.OnClientEvent:Connect(function(payload)
        if typeof(payload) ~= "table" then return end
        if typeof(payload.requestId) ~= "string" then return end
        if typeof(payload.message) ~= "string" or payload.message == "" then return end
        if not uiEnabled then return end
        if cardsByRequest[payload.requestId] then return end

        createCard(payload)
end)

CommandRemotes.HelpUIToggle.OnClientEvent:Connect(function(enabled: boolean)
        uiEnabled       = enabled and true or false
        holder.Visible  = uiEnabled
end)

Players.PlayerRemoving:Connect(function(player)
        local requests = cardsByUser[player.UserId]
        if not requests then return end
        for requestId in pairs(requests) do
                removeCard(requestId)
        end
end)
