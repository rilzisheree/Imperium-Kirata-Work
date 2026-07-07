--[[
	MusicMenu.client.lua
	Draggable Music Control panel. Toggled by the `music` admin command.
	Styling matches WeatherMenu exactly: same palette, drag, open/close animation.
]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CommandRemotes = require(ReplicatedStorage:WaitForChild("CommandRemotes"))

local LP   = Players.LocalPlayer
local PGui = LP:WaitForChild("PlayerGui")

-- ── Song catalogue ─────────────────────────────────────────────────────────────
-- Add new sections / tracks here; the menu builds itself from this table.
local SECTIONS = {
	{
		name   = "Calm",
		tracks = {
			{ id = "7029031068",      title = "Holy Eerie / Still Holy"              },
			{ id = "1836102253",      title = "Calm Song"                            },
			{ id = "1847107549",      title = "Fast Piano"                           },
			{ id = "9046651755",      title = "Sort of Loud, Fast, Deep"             },
			{ id = "1839806128",      title = "Calm Night Vibes"                     },
			{ id = "1838853198",      title = "Night Calm Harry Potter Vibes"        },
			{ id = "1841831379",      title = "Warm Atmosphere"                      },
			{ id = "76350635489391",  title = "Calm Waves | Goated"                  },
			{ id = "1847854017",      title = "Chill Flute Build Up"                 },
			{ id = "118028992848427", title = "Chill Beat"                           },
			{ id = "1839661340",      title = "Emotional Singing, Short String Guitar"},
			{ id = "9048339210",      title = "Radio Vibes, Very Jumpy"              },
			{ id = "1837065029",      title = "Female Speaking, Emotional"           },
			{ id = "1844272332",      title = "Concentrated Calm"                    },
			{ id = "9042437001",      title = "Reflection"                           },
			{ id = "1838635121",      title = "SoL / Marriage / Funeral"             },
			{ id = "9047885144",      title = "SoL / Marriage / Funeral 2"           },
			{ id = "9041904416",      title = "Fantasy SoL Music"                    },
			{ id = "1846115874",      title = "Angelic Voices"                       },
			{ id = "1840524246",      title = "SoL / Funeral / Marriage PD Music"    },
			{ id = "847732158",       title = "Eerie SoL Music"                      },
			{ id = "114213622974713", title = "The Loneliest Hour"                   },
			{ id = "1844634063",      title = "Sad Violin"                           },
			{ id = "9046435309",      title = "Sad, Yet Calming (Favorite)"          },
			{ id = "1840435172",      title = "Gamezone (A)"                         },
			{ id = "1846486437",      title = "Japanese Breeze 1"                    },
			{ id = "1846503445",      title = "Japanese Breeze 2"                    },
			{ id = "9039953638",      title = "SoL | Elevator Music"                 },
			{ id = "1848090455",      title = "Calm Set The Mood Music"              },
		},
	},
	{ name = "Intense",  tracks = {} },
	{ name = "Fighting", tracks = {} },
}

-- ── Palette (matches WeatherMenu / CommandBar exactly) ─────────────────────────
local C_BG   = Color3.fromRGB( 12,  12,  18)
local C_BOR  = Color3.fromRGB( 90,  90, 120)
local C_TXT  = Color3.fromRGB(235, 235, 252)
local C_DIM  = Color3.fromRGB( 80,  80, 100)
local C_ACC  = Color3.fromRGB(160, 160, 210)
local C_ACT  = Color3.fromRGB(100, 140, 255)
local C_HEAD = Color3.fromRGB( 16,  16,  26)
local C_FOOT = Color3.fromRGB( 14,  14,  22)
local C_BTN  = Color3.fromRGB( 22,  22,  34)

-- ── Layout ─────────────────────────────────────────────────────────────────────
local MENU_W   = 620
local PAD      = 12
local HEADER_H = 44
local NOW_H    = 34
local SEARCH_H = 38
local SLIDER_H = 44
local DIV_H    = 1
local LIST_H   = 245
local FOOTER_H = 44
local THUMB_S  = 14
local ROW_H    = 34
local SEC_H    = 26

local MENU_H = HEADER_H + DIV_H + NOW_H + DIV_H + SEARCH_H + DIV_H
             + SLIDER_H + DIV_H + LIST_H + DIV_H + FOOTER_H

-- ── Runtime state ──────────────────────────────────────────────────────────────
local isOpen         = false
local currentId      = nil   -- currently playing audio ID string (or nil)
local currentVolume  = 1     -- 0–1, preserved across track changes
local activeSliderFn = nil   -- position handler for volume slider drag
local dragging       = false
local dragStart      = nil
local framePos       = nil

-- ── ScreenGui ──────────────────────────────────────────────────────────────────
local sg = Instance.new("ScreenGui")
sg.Name           = "MusicMenuGui"
sg.DisplayOrder   = 104
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = false
sg.Enabled        = false
sg.Parent         = PGui

-- ── Main frame ─────────────────────────────────────────────────────────────────
local frame = Instance.new("Frame")
frame.Name             = "MusicMenu"
frame.AnchorPoint      = Vector2.new(0.5, 0.5)
frame.Position         = UDim2.new(0.5, 0, 0.5, 0)
frame.Size             = UDim2.new(0, MENU_W, 0, MENU_H)
frame.BackgroundColor3 = C_BG
frame.BorderSizePixel  = 0
frame.ClipsDescendants = true
frame.ZIndex           = 10
frame.Parent           = sg

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local fStroke = Instance.new("UIStroke", frame)
fStroke.Color           = C_BOR
fStroke.Thickness       = 1.5
fStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local uiScale = Instance.new("UIScale", frame)
uiScale.Scale = 1

-- ── Divider helper ─────────────────────────────────────────────────────────────
local function makeDivider(parent, yPos)
	local d = Instance.new("Frame", parent)
	d.Size                   = UDim2.new(1, 0, 0, DIV_H)
	d.Position               = UDim2.new(0, 0, 0, yPos)
	d.BackgroundColor3       = C_BOR
	d.BackgroundTransparency = 0.55
	d.BorderSizePixel        = 0
	d.ZIndex                 = 11
	return d
end

-- ── Header (drag handle + title + close) ───────────────────────────────────────
local header = Instance.new("Frame", frame)
header.Name             = "Header"
header.Size             = UDim2.new(1, 0, 0, HEADER_H)
header.Position         = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = C_HEAD
header.BorderSizePixel  = 0
header.ZIndex           = 11

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size               = UDim2.new(1, -PAD, 1, 0)
titleLbl.Position           = UDim2.new(0, PAD, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 14
titleLbl.TextColor3         = C_TXT
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.TextYAlignment     = Enum.TextYAlignment.Center
titleLbl.Text               = "Music Control"
titleLbl.ZIndex             = 12

local closeBtn = Instance.new("TextButton", header)
closeBtn.AnchorPoint        = Vector2.new(1, 0.5)
closeBtn.Position           = UDim2.new(1, -PAD, 0.5, 0)
closeBtn.Size               = UDim2.new(0, 28, 0, 28)
closeBtn.BackgroundTransparency = 1
closeBtn.Font               = Enum.Font.GothamBold
closeBtn.TextSize           = 16
closeBtn.TextColor3         = C_DIM
closeBtn.Text               = "✕"
closeBtn.AutoButtonColor    = false
closeBtn.ZIndex             = 12
closeBtn.MouseEnter:Connect(function() closeBtn.TextColor3 = C_TXT end)
closeBtn.MouseLeave:Connect(function() closeBtn.TextColor3 = C_DIM end)

makeDivider(frame, HEADER_H)

-- ── Now-Playing bar ────────────────────────────────────────────────────────────
local nowY   = HEADER_H + DIV_H
local nowRow = Instance.new("Frame", frame)
nowRow.Name                   = "NowPlaying"
nowRow.Size                   = UDim2.new(1, 0, 0, NOW_H)
nowRow.Position               = UDim2.new(0, 0, 0, nowY)
nowRow.BackgroundColor3       = C_HEAD
nowRow.BackgroundTransparency = 0.4
nowRow.BorderSizePixel        = 0
nowRow.ZIndex                 = 11

local nowDot = Instance.new("Frame", nowRow)
nowDot.AnchorPoint      = Vector2.new(0, 0.5)
nowDot.Position         = UDim2.new(0, PAD, 0.5, 0)
nowDot.Size             = UDim2.new(0, 7, 0, 7)
nowDot.BackgroundColor3 = C_DIM
nowDot.BorderSizePixel  = 0
nowDot.ZIndex           = 12
Instance.new("UICorner", nowDot).CornerRadius = UDim.new(1, 0)

local nowLabel = Instance.new("TextLabel", nowRow)
nowLabel.Size               = UDim2.new(1, -(PAD * 2 + 14), 1, 0)
nowLabel.Position           = UDim2.new(0, PAD + 14, 0, 0)
nowLabel.BackgroundTransparency = 1
nowLabel.Font               = Enum.Font.Gotham
nowLabel.TextSize           = 12
nowLabel.TextColor3         = C_DIM
nowLabel.TextXAlignment     = Enum.TextXAlignment.Left
nowLabel.TextYAlignment     = Enum.TextYAlignment.Center
nowLabel.TextTruncate       = Enum.TextTruncate.AtEnd
nowLabel.Text               = "Nothing playing"
nowLabel.ZIndex             = 12

makeDivider(frame, nowY + NOW_H)

-- ── Search bar ─────────────────────────────────────────────────────────────────
local searchY     = nowY + NOW_H + DIV_H
local searchFrame = Instance.new("Frame", frame)
searchFrame.Name                   = "SearchRow"
searchFrame.Size                   = UDim2.new(1, 0, 0, SEARCH_H)
searchFrame.Position               = UDim2.new(0, 0, 0, searchY)
searchFrame.BackgroundTransparency = 1
searchFrame.BorderSizePixel        = 0
searchFrame.ZIndex                 = 11

local searchBox = Instance.new("TextBox", searchFrame)
searchBox.AnchorPoint       = Vector2.new(0.5, 0.5)
searchBox.Position          = UDim2.new(0.5, 0, 0.5, 0)
searchBox.Size              = UDim2.new(1, -(PAD * 2), 0, 26)
searchBox.BackgroundColor3  = Color3.fromRGB(20, 20, 32)
searchBox.BorderSizePixel   = 0
searchBox.ClearTextOnFocus  = false
searchBox.Font              = Enum.Font.Gotham
searchBox.TextSize          = 12
searchBox.TextColor3        = C_TXT
searchBox.PlaceholderText   = "Search by title or ID…"
searchBox.PlaceholderColor3 = C_DIM
searchBox.Text              = ""
searchBox.TextXAlignment    = Enum.TextXAlignment.Left
searchBox.ZIndex            = 12
Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 5)
do
	local ss = Instance.new("UIStroke", searchBox)
	ss.Color = C_BOR; ss.Thickness = 1; ss.Transparency = 0.5
	ss.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end
local sPad = Instance.new("UIPadding", searchBox)
sPad.PaddingLeft  = UDim.new(0, 8)
sPad.PaddingRight = UDim.new(0, 8)

makeDivider(frame, searchY + SEARCH_H)

-- ── Volume slider ──────────────────────────────────────────────────────────────
local sliderY   = searchY + SEARCH_H + DIV_H
local sliderRow = Instance.new("Frame", frame)
sliderRow.Name                   = "VolumeRow"
sliderRow.Size                   = UDim2.new(1, 0, 0, SLIDER_H)
sliderRow.Position               = UDim2.new(0, 0, 0, sliderY)
sliderRow.BackgroundTransparency = 1
sliderRow.BorderSizePixel        = 0
sliderRow.ZIndex                 = 11

local volLabel = Instance.new("TextLabel", sliderRow)
volLabel.Size               = UDim2.new(0, 80, 0, 20)
volLabel.Position           = UDim2.new(0, PAD, 0, 4)
volLabel.BackgroundTransparency = 1
volLabel.Font               = Enum.Font.Gotham
volLabel.TextSize           = 12
volLabel.TextColor3         = C_TXT
volLabel.TextXAlignment     = Enum.TextXAlignment.Left
volLabel.Text               = "Volume"
volLabel.ZIndex             = 12

local volValLbl = Instance.new("TextLabel", sliderRow)
volValLbl.AnchorPoint      = Vector2.new(1, 0)
volValLbl.Position         = UDim2.new(1, -PAD, 0, 4)
volValLbl.Size             = UDim2.new(0, 44, 0, 20)
volValLbl.BackgroundTransparency = 1
volValLbl.Font             = Enum.Font.GothamMedium
volValLbl.TextSize         = 12
volValLbl.TextColor3       = C_ACC
volValLbl.TextXAlignment   = Enum.TextXAlignment.Right
volValLbl.Text             = "100%"
volValLbl.ZIndex           = 12

local volTrack = Instance.new("Frame", sliderRow)
volTrack.Size             = UDim2.new(1, -(PAD * 2), 0, 4)
volTrack.Position         = UDim2.new(0, PAD, 0, 32)
volTrack.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
volTrack.BorderSizePixel  = 0
volTrack.ZIndex           = 12
Instance.new("UICorner", volTrack).CornerRadius = UDim.new(1, 0)

local volFill = Instance.new("Frame", volTrack)
volFill.Size             = UDim2.new(1, 0, 1, 0)
volFill.BackgroundColor3 = C_ACT
volFill.BorderSizePixel  = 0
volFill.ZIndex           = 13
Instance.new("UICorner", volFill).CornerRadius = UDim.new(1, 0)

local volThumb = Instance.new("TextButton", volTrack)
volThumb.Size             = UDim2.new(0, THUMB_S, 0, THUMB_S)
volThumb.AnchorPoint      = Vector2.new(0.5, 0.5)
volThumb.Position         = UDim2.new(1, 0, 0.5, 0)
volThumb.BackgroundColor3 = Color3.new(1, 1, 1)
volThumb.Text             = ""
volThumb.AutoButtonColor  = false
volThumb.BorderSizePixel  = 0
volThumb.ZIndex           = 14
Instance.new("UICorner", volThumb).CornerRadius = UDim.new(1, 0)

local volThrottle = 0
local VOL_THROTTLE_INTERVAL = 0.06

local function applyVolX(posX)
	local abs = volTrack.AbsolutePosition
	local sz  = volTrack.AbsoluteSize
	if sz.X == 0 then return end
	local ratio = math.clamp((posX - abs.X) / sz.X, 0, 1)
	local pct   = math.round(ratio * 100)
	volFill.Size      = UDim2.new(ratio, 0, 1, 0)
	volThumb.Position = UDim2.new(ratio, 0, 0.5, 0)
	volValLbl.Text    = pct .. "%"
	currentVolume     = ratio
	local now = tick()
	if now - volThrottle >= VOL_THROTTLE_INTERVAL then
		volThrottle = now
		CommandRemotes.MusicCommand:FireServer("volume", ratio)
	end
end

volThumb.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		activeSliderFn = applyVolX
	end
end)
volTrack.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		activeSliderFn = applyVolX
		applyVolX(input.Position.X)
	end
end)

makeDivider(frame, sliderY + SLIDER_H)

-- ── Song list (ScrollingFrame) ─────────────────────────────────────────────────
local listY   = sliderY + SLIDER_H + DIV_H
local songList = Instance.new("ScrollingFrame", frame)
songList.Name                  = "SongList"
songList.Size                  = UDim2.new(1, 0, 0, LIST_H)
songList.Position              = UDim2.new(0, 0, 0, listY)
songList.BackgroundTransparency = 1
songList.BorderSizePixel       = 0
songList.ScrollBarThickness    = 4
songList.ScrollBarImageColor3  = C_ACC
songList.CanvasSize            = UDim2.new(0, 0, 0, 0)
songList.AutomaticCanvasSize   = Enum.AutomaticSize.Y
songList.ZIndex                = 11

local listLayout = Instance.new("UIListLayout", songList)
listLayout.FillDirection       = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
listLayout.SortOrder           = Enum.SortOrder.LayoutOrder
listLayout.Padding             = UDim.new(0, 0)

local listPad = Instance.new("UIPadding", songList)
listPad.PaddingLeft   = UDim.new(0, PAD)
listPad.PaddingRight  = UDim.new(0, PAD)
listPad.PaddingTop    = UDim.new(0, 6)
listPad.PaddingBottom = UDim.new(0, 6)

makeDivider(frame, listY + LIST_H)

-- ── Footer ─────────────────────────────────────────────────────────────────────
local footerY = listY + LIST_H + DIV_H
local footer  = Instance.new("Frame", frame)
footer.Size             = UDim2.new(1, 0, 0, FOOTER_H)
footer.Position         = UDim2.new(0, 0, 0, footerY)
footer.BackgroundColor3 = C_FOOT
footer.BorderSizePixel  = 0
footer.ZIndex           = 11

local footDot = Instance.new("Frame", footer)
footDot.AnchorPoint      = Vector2.new(0, 0.5)
footDot.Position         = UDim2.new(0, PAD, 0.5, 0)
footDot.Size             = UDim2.new(0, 8, 0, 8)
footDot.BackgroundColor3 = C_DIM
footDot.BorderSizePixel  = 0
footDot.ZIndex           = 12
Instance.new("UICorner", footDot).CornerRadius = UDim.new(1, 0)

local footStatus = Instance.new("TextLabel", footer)
footStatus.Size               = UDim2.new(0.55, 0, 1, 0)
footStatus.Position           = UDim2.new(0, PAD + 14, 0, 0)
footStatus.BackgroundTransparency = 1
footStatus.Font               = Enum.Font.Gotham
footStatus.TextSize           = 12
footStatus.TextColor3         = C_DIM
footStatus.TextXAlignment     = Enum.TextXAlignment.Left
footStatus.TextYAlignment     = Enum.TextYAlignment.Center
footStatus.TextTruncate       = Enum.TextTruncate.AtEnd
footStatus.Text               = "Stopped"
footStatus.ZIndex             = 12

local BW = 88

local stopBtn = Instance.new("TextButton", footer)
stopBtn.AnchorPoint        = Vector2.new(1, 0.5)
stopBtn.Position           = UDim2.new(1, -(PAD + BW + 6), 0.5, 0)
stopBtn.Size               = UDim2.new(0, BW, 0, 28)
stopBtn.BackgroundTransparency = 1
stopBtn.Font               = Enum.Font.Gotham
stopBtn.TextSize           = 11
stopBtn.TextColor3         = Color3.fromRGB(210, 85, 85)
stopBtn.Text               = "Stop Music"
stopBtn.AutoButtonColor    = false
stopBtn.ZIndex             = 12

local closeFooter = Instance.new("TextButton", footer)
closeFooter.AnchorPoint        = Vector2.new(1, 0.5)
closeFooter.Position           = UDim2.new(1, -PAD, 0.5, 0)
closeFooter.Size               = UDim2.new(0, BW, 0, 28)
closeFooter.BackgroundTransparency = 1
closeFooter.Font               = Enum.Font.Gotham
closeFooter.TextSize           = 11
closeFooter.TextColor3         = C_ACC
closeFooter.Text               = "Close"
closeFooter.AutoButtonColor    = false
closeFooter.ZIndex             = 12

-- ── Build song rows ────────────────────────────────────────────────────────────
local layoutOrder = 0
local function nextOrder()
	layoutOrder += 1
	return layoutOrder
end

-- allRows: flat list of { id, title, frame, accent, nameLbl } for highlight + search
local allRows = {}

-- sectionMeta: { header, arrowLbl, rows, collapsed }
-- rows are the track row frames belonging to a section, in order
local sectionMeta = {}

-- Quick lookup: id → title (for now-playing display)
local idToTitle = {}
for _, sec in ipairs(SECTIONS) do
	for _, t in ipairs(sec.tracks) do
		idToTitle[t.id] = t.title
	end
end

-- refreshVisibility: reconcile row visibility from search query + collapse state
local searchQuery = ""

local function refreshVisibility()
	local q = searchQuery:lower()
	for si, meta in ipairs(sectionMeta) do
		local sec = SECTIONS[si]
		local anyVisible = false
		for ri, rowFrame in ipairs(meta.rows) do
			local track = sec.tracks[ri]
			local matches = (q == "")
				or track.id:lower():find(q, 1, true)
				or track.title:lower():find(q, 1, true)
			-- when searching, ignore collapse so results always show
			local visible = matches and (q ~= "" or not meta.collapsed)
			rowFrame.Visible = visible
			if matches then anyVisible = true end
		end
		-- always show section header; hide only when search active and no matches
		meta.header.Visible = (q == "") or anyVisible
	end
end

for si, sec in ipairs(SECTIONS) do
	-- Section header (collapsible button)
	local secBtn = Instance.new("TextButton", songList)
	secBtn.Name             = "Sec_" .. sec.name
	secBtn.LayoutOrder      = nextOrder()
	secBtn.Size             = UDim2.new(1, 0, 0, SEC_H)
	secBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 34)
	secBtn.BackgroundTransparency = 0.3
	secBtn.BorderSizePixel  = 0
	secBtn.AutoButtonColor  = false
	secBtn.Text             = ""
	secBtn.ZIndex           = 12
	Instance.new("UICorner", secBtn).CornerRadius = UDim.new(0, 5)

	local arrowLbl = Instance.new("TextLabel", secBtn)
	arrowLbl.Size               = UDim2.new(0, 18, 1, 0)
	arrowLbl.Position           = UDim2.new(0, PAD - 4, 0, 0)
	arrowLbl.BackgroundTransparency = 1
	arrowLbl.Font               = Enum.Font.GothamBold
	arrowLbl.TextSize           = 10
	arrowLbl.TextColor3         = C_ACC
	arrowLbl.TextXAlignment     = Enum.TextXAlignment.Left
	arrowLbl.TextYAlignment     = Enum.TextYAlignment.Center
	arrowLbl.Text               = "▾"
	arrowLbl.ZIndex             = 13

	local secLbl = Instance.new("TextLabel", secBtn)
	secLbl.Size               = UDim2.new(1, -(PAD + 14), 1, 0)
	secLbl.Position           = UDim2.new(0, PAD + 14, 0, 0)
	secLbl.BackgroundTransparency = 1
	secLbl.Font               = Enum.Font.GothamBold
	secLbl.TextSize           = 11
	secLbl.TextColor3         = C_ACC
	secLbl.TextXAlignment     = Enum.TextXAlignment.Left
	secLbl.TextYAlignment     = Enum.TextYAlignment.Center
	secLbl.Text               = string.upper(sec.name)
	secLbl.ZIndex             = 13

	local meta = { header = secBtn, arrowLbl = arrowLbl, rows = {}, collapsed = false }
	sectionMeta[si] = meta

	-- Track rows
	for _, track in ipairs(sec.tracks) do
		local trackId    = track.id
		local trackTitle = track.title

		local row = Instance.new("TextButton", songList)
		row.Name             = "Row_" .. trackId
		row.LayoutOrder      = nextOrder()
		row.Size             = UDim2.new(1, 0, 0, ROW_H)
		row.BackgroundColor3 = C_BTN
		row.BackgroundTransparency = 1
		row.BorderSizePixel  = 0
		row.AutoButtonColor  = false
		row.Text             = ""
		row.ZIndex           = 12
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

		local accent = Instance.new("Frame", row)
		accent.Name             = "Accent"
		accent.AnchorPoint      = Vector2.new(0, 0.5)
		accent.Size             = UDim2.new(0, 3, 1, -10)
		accent.Position         = UDim2.new(0, 6, 0.5, 0)
		accent.BackgroundColor3 = C_DIM
		accent.BorderSizePixel  = 0
		accent.ZIndex           = 13
		Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 2)

		-- Title (left ~55%)
		local nameLbl = Instance.new("TextLabel", row)
		nameLbl.Size               = UDim2.new(0.55, -22, 1, 0)
		nameLbl.Position           = UDim2.new(0, 18, 0, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font               = Enum.Font.Gotham
		nameLbl.TextSize           = 13
		nameLbl.TextColor3         = C_TXT
		nameLbl.TextXAlignment     = Enum.TextXAlignment.Left
		nameLbl.TextYAlignment     = Enum.TextYAlignment.Center
		nameLbl.TextTruncate       = Enum.TextTruncate.AtEnd
		nameLbl.Text               = trackTitle
		nameLbl.ZIndex             = 13

		-- ID (right ~45%, dimmed)
		local idLbl = Instance.new("TextLabel", row)
		idLbl.Size               = UDim2.new(0.45, -PAD, 1, 0)
		idLbl.Position           = UDim2.new(0.55, 0, 0, 0)
		idLbl.BackgroundTransparency = 1
		idLbl.Font               = Enum.Font.Code
		idLbl.TextSize           = 11
		idLbl.TextColor3         = C_DIM
		idLbl.TextXAlignment     = Enum.TextXAlignment.Right
		idLbl.TextYAlignment     = Enum.TextYAlignment.Center
		idLbl.TextTruncate       = Enum.TextTruncate.AtEnd
		idLbl.Text               = trackId
		idLbl.ZIndex             = 13

		table.insert(allRows, { id = trackId, title = trackTitle,
		                        frame = row, accent = accent, nameLbl = nameLbl })
		table.insert(meta.rows, row)

		row.MouseEnter:Connect(function()
			if trackId ~= currentId then row.BackgroundTransparency = 0.78 end
		end)
		row.MouseLeave:Connect(function()
			if trackId ~= currentId then row.BackgroundTransparency = 1 end
		end)
		row.MouseButton1Click:Connect(function()
			CommandRemotes.MusicCommand:FireServer("play", trackId)
		end)
	end

	-- Collapse toggle
	local sIdx = si  -- capture
	secBtn.MouseButton1Click:Connect(function()
		sectionMeta[sIdx].collapsed = not sectionMeta[sIdx].collapsed
		sectionMeta[sIdx].arrowLbl.Text = sectionMeta[sIdx].collapsed and "▸" or "▾"
		refreshVisibility()
	end)
end

-- ── Highlight + now-playing update ────────────────────────────────────────────
local function updateHighlight(id: string?)
	currentId = id
	for _, row in ipairs(allRows) do
		local active = (row.id == id)
		row.frame.BackgroundTransparency = active and 0.60 or 1
		row.frame.BackgroundColor3       = active and Color3.fromRGB(22, 32, 58) or C_BTN
		row.accent.BackgroundColor3      = active and C_ACT or C_DIM
		row.nameLbl.TextColor3           = active and Color3.new(1, 1, 1) or C_TXT
	end

	if id then
		local title = idToTitle[id] or id
		nowDot.BackgroundColor3  = C_ACT
		nowLabel.TextColor3      = C_TXT
		nowLabel.Text            = title
		footDot.BackgroundColor3 = C_ACT
		footStatus.TextColor3    = C_TXT
		footStatus.Text          = title
	else
		nowDot.BackgroundColor3  = C_DIM
		nowLabel.TextColor3      = C_DIM
		nowLabel.Text            = "Nothing playing"
		footDot.BackgroundColor3 = C_DIM
		footStatus.TextColor3    = C_DIM
		footStatus.Text          = "Stopped"
	end
end

-- ── Global input handlers (slider drag + window drag) ─────────────────────────
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		-- Volume slider drag
		if activeSliderFn then
			activeSliderFn(input.Position.X)
		end
		-- Window drag
		if dragging and dragStart and framePos then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				framePos.X.Scale, framePos.X.Offset + delta.X,
				framePos.Y.Scale, framePos.Y.Offset + delta.Y
			)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- if the volume slider was being dragged, commit the final value
		if activeSliderFn == applyVolX then
			CommandRemotes.MusicCommand:FireServer("volume", currentVolume)
		end
		activeSliderFn = nil
		dragging       = false
	end
end)

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging  = true
		dragStart = input.Position
		framePos  = frame.Position
	end
end)

-- ── Search ────────────────────────────────────────────────────────────────────
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchQuery = searchBox.Text
	refreshVisibility()
end)

-- ── Open / Close animation ────────────────────────────────────────────────────
local openInfo  = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local closeInfo = TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function openMenu()
	if isOpen then return end
	isOpen         = true
	activeSliderFn = nil
	sg.Enabled     = true
	uiScale.Scale  = 0.90
	TweenService:Create(uiScale, openInfo, { Scale = 1 }):Play()
end

local function closeMenu()
	if not isOpen then return end
	isOpen         = false
	activeSliderFn = nil
	local t = TweenService:Create(uiScale, closeInfo, { Scale = 0.90 })
	t:Play()
	t.Completed:Connect(function()
		if not isOpen then sg.Enabled = false end
	end)
end

-- ── Button connections ────────────────────────────────────────────────────────
closeBtn.MouseButton1Click:Connect(closeMenu)
closeFooter.MouseButton1Click:Connect(closeMenu)

stopBtn.MouseButton1Click:Connect(function()
	CommandRemotes.MusicCommand:FireServer("stop")
end)

-- ── Remote connections ────────────────────────────────────────────────────────
CommandRemotes.MusicOpen.OnClientEvent:Connect(function()
	if isOpen then closeMenu() else openMenu() end
end)

-- Keep the menu's highlight in sync when a track is played (from command or another menu)
CommandRemotes.MusicPlay.OnClientEvent:Connect(function(id: string)
	if typeof(id) == "string" and id ~= "" then
		updateHighlight(id)
	end
end)

CommandRemotes.MusicStop.OnClientEvent:Connect(function()
	updateHighlight(nil)
end)

-- Sync volume thumb when another client's volume change comes back
CommandRemotes.MusicVolume.OnClientEvent:Connect(function(volume: number)
	if typeof(volume) ~= "number" then return end
	local ratio = math.clamp(volume, 0, 1)
	currentVolume     = ratio
	volFill.Size      = UDim2.new(ratio, 0, 1, 0)
	volThumb.Position = UDim2.new(ratio, 0, 0.5, 0)
	volValLbl.Text    = math.round(ratio * 100) .. "%"
end)

-- MusicSync tells us what was already playing when we joined
CommandRemotes.MusicSync.OnClientEvent:Connect(function(id: string, volume: number)
	if typeof(id) == "string" and id ~= "" then
		updateHighlight(id)
	end
	if typeof(volume) == "number" then
		local ratio = math.clamp(volume, 0, 1)
		currentVolume     = ratio
		volFill.Size      = UDim2.new(ratio, 0, 1, 0)
		volThumb.Position = UDim2.new(ratio, 0, 0.5, 0)
		volValLbl.Text    = math.round(ratio * 100) .. "%"
	end
end)
