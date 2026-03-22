local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local RunService   = game:GetService("RunService")
local player       = Players.LocalPlayer

local OLD = player.PlayerGui:FindFirstChild("ToolSelectorGui")
if OLD then OLD:Destroy() end

local C = {
    btnNormal   = Color3.fromRGB(82,  58,  145),
    btnHover    = Color3.fromRGB(102, 75,  172),
    btnSelected = Color3.fromRGB(125, 90,  205),
    btnBorder   = Color3.fromRGB(42,  28,  78),
    text        = Color3.fromRGB(255, 248, 255),
    panelBg     = Color3.fromRGB(36,  24,  62),
}

local SUBTITLE_COLORS = {
    Move   = Color3.fromRGB(170, 100, 255),
    Resize = Color3.fromRGB(255, 160, 50),
    Rotate = Color3.fromRGB(255, 100, 160),
    None   = Color3.fromRGB(160, 155, 170),
}

local SELECTION_COLORS = {
    Move   = Color3.fromRGB(170, 100, 255),
    Resize = Color3.fromRGB(255, 160, 50),
    Rotate = Color3.fromRGB(255, 100, 160),
    None   = Color3.fromRGB(140, 135, 155),
}

local SPRITE        = "rbxassetid://12365668909"
local SPRITE_ROTATE = "rbxassetid://72311646349060"

local TOOLS = {
    { name="Move",   sprite=SPRITE,        rectOffset=Vector2.new(360,144), rectSize=Vector2.new(72,72) },
    { name="Rotate", sprite=SPRITE_ROTATE, rectOffset=nil, rectSize=nil },
    { name="Resize", sprite=SPRITE,        rectOffset=Vector2.new(288,144), rectSize=Vector2.new(72,72) },
}

local BTN_COUNT  = 4
local BTN_SIZE   = 54
local GAP        = 6
local PAD        = 10
local ANCHOR_TOP = 18

local selectedTool = nil
local panelOpen    = false
local guiVisible   = true

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "ToolSelectorGui"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.AutoLocalize   = false
screenGui.Parent         = player.PlayerGui

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end
local function mkStroke(p, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or C.btnBorder
    s.Thickness = th or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = p
    return s
end
local function sizeCon(p)
    local c = Instance.new("UITextSizeConstraint")
    c.MinTextSize = 12; c.MaxTextSize = 28; c.Parent = p
end
local function grad(p, c0, c1)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c0),
        ColorSequenceKeypoint.new(1, c1),
    })
    g.Rotation = 135; g.Parent = p; return g
end

local anchor = Instance.new("Frame")
anchor.Size                  = UDim2.new(0, BTN_SIZE, 0, BTN_SIZE)
anchor.AnchorPoint           = Vector2.new(0.5, 0)
anchor.Position              = UDim2.new(0.5, 0, 0, ANCHOR_TOP)
anchor.BackgroundTransparency = 1
anchor.ClipsDescendants      = false
anchor.BorderSizePixel       = 0
anchor.Parent                = screenGui

local mainBtn = Instance.new("TextButton")
mainBtn.Size             = UDim2.new(0, BTN_SIZE, 0, BTN_SIZE)
mainBtn.Position         = UDim2.new(0, 0, 0, 0)
mainBtn.BackgroundColor3 = C.btnNormal
mainBtn.BorderSizePixel  = 0
mainBtn.Text             = ""
mainBtn.ZIndex           = 10
mainBtn.Parent           = anchor
corner(mainBtn, 8); mkStroke(mainBtn)
grad(mainBtn, Color3.fromRGB(108,80,188), Color3.fromRGB(68,46,122))

local mainIcon = Instance.new("ImageLabel")
mainIcon.Size                   = UDim2.new(0, 40, 0, 40)
mainIcon.AnchorPoint            = Vector2.new(0.5, 0.5)
mainIcon.Position               = UDim2.new(0.5, 0, 0.5, 0)
mainIcon.BackgroundTransparency = 1
mainIcon.Image                  = ""
mainIcon.ZIndex                 = 11
mainIcon.Visible                = false
mainIcon.Parent                 = mainBtn

local mainDash = Instance.new("TextLabel")
mainDash.Size                   = UDim2.new(1, 0, 1, 0)
mainDash.BackgroundTransparency = 1
mainDash.Text                   = "—"
mainDash.TextColor3             = C.text
mainDash.Font                   = Enum.Font.GothamBold
mainDash.TextSize               = 28
mainDash.ZIndex                 = 11
mainDash.Visible                = true
mainDash.Parent                 = mainBtn
sizeCon(mainDash)

local function setMainIcon(tool)
    if tool then
        mainIcon.Image   = tool.sprite
        if tool.rectOffset then
            mainIcon.ImageRectOffset = tool.rectOffset
            mainIcon.ImageRectSize   = tool.rectSize
        else
            mainIcon.ImageRectOffset = Vector2.new(0, 0)
            mainIcon.ImageRectSize   = Vector2.new(0, 0)
        end
        mainIcon.Visible = true
        mainDash.Visible = false
    else
        mainIcon.Visible = false
        mainDash.Visible = true
    end
end

local PANEL_W = BTN_COUNT * BTN_SIZE + (BTN_COUNT-1)*GAP + PAD*2
local PANEL_H = BTN_SIZE + PAD*2
local SHOWN_POS       = UDim2.new(0.5, 0, 0, ANCHOR_TOP)
local HIDDEN_POS      = UDim2.new(0.5, 0, 0, -(BTN_SIZE + 8))
local TW_SHOW         = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TW_HIDE         = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PANEL_OPEN_POS  = UDim2.new(0.5, 0, 0, BTN_SIZE + GAP)
local PANEL_START_POS = UDim2.new(0.5, 0, 0, BTN_SIZE)

local panel = Instance.new("Frame")
panel.Name                  = "ToolPanel"
panel.Size                  = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.AnchorPoint           = Vector2.new(0.5, 0)
panel.Position              = UDim2.new(0.5, 0, 0, BTN_SIZE + GAP)
panel.BackgroundColor3      = C.panelBg
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel       = 0
panel.ZIndex                = 9
panel.Visible               = false
panel.Parent                = anchor
corner(panel, 12); mkStroke(panel, C.btnBorder, 1.5)
grad(panel, Color3.fromRGB(50,33,82), Color3.fromRGB(28,18,50))

local lo = Instance.new("UIListLayout")
lo.FillDirection       = Enum.FillDirection.Horizontal
lo.HorizontalAlignment = Enum.HorizontalAlignment.Center
lo.VerticalAlignment   = Enum.VerticalAlignment.Center
lo.Padding             = UDim.new(0, GAP)
lo.Parent              = panel

local uipad = Instance.new("UIPadding")
uipad.PaddingLeft   = UDim.new(0, PAD)
uipad.PaddingRight  = UDim.new(0, PAD)
uipad.PaddingTop    = UDim.new(0, PAD)
uipad.PaddingBottom = UDim.new(0, PAD)
uipad.Parent        = panel

local toolButtons = {}

for i, tool in ipairs(TOOLS) do
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(0, BTN_SIZE, 0, BTN_SIZE)
    btn.BackgroundColor3 = C.btnNormal
    btn.BorderSizePixel  = 0
    btn.Text             = ""
    btn.ZIndex           = 10
    btn.Parent           = panel
    corner(btn, 8); mkStroke(btn)
    grad(btn, Color3.fromRGB(100,72,175), Color3.fromRGB(62,42,118))

    if tool.rectSize and tool.rectSize.X > 0 then
        local img = Instance.new("ImageLabel")
        img.Size                   = UDim2.new(0, 40, 0, 40)
        img.AnchorPoint            = Vector2.new(0.5, 0.5)
        img.Position               = UDim2.new(0.5, 0, 0.5, 0)
        img.BackgroundTransparency = 1
        img.Image                  = tool.sprite
        img.ImageRectOffset        = tool.rectOffset
        img.ImageRectSize          = tool.rectSize
        img.ZIndex                 = 11
        img.Parent                 = btn
    else
        local img = Instance.new("ImageLabel")
        img.Size                   = UDim2.new(0, 40, 0, 40)
        img.AnchorPoint            = Vector2.new(0.5, 0.5)
        img.Position               = UDim2.new(0.5, 0, 0.5, 0)
        img.BackgroundTransparency = 1
        img.Image                  = tool.sprite
        img.ZIndex                 = 11
        img.Parent                 = btn
    end

    toolButtons[i] = { btn=btn, tool=tool }
end

local subFrame = Instance.new("Frame")
subFrame.Size                  = UDim2.new(0, 0, 0, 34)
subFrame.AutomaticSize         = Enum.AutomaticSize.X
subFrame.AnchorPoint           = Vector2.new(0.5, 1)
subFrame.Position              = UDim2.new(0.5, 0, 1, -44)
subFrame.BackgroundColor3      = Color3.fromRGB(12, 8, 24)
subFrame.BackgroundTransparency = 1
subFrame.BorderSizePixel       = 0
subFrame.ZIndex                = 20
subFrame.Visible               = false
subFrame.Parent                = screenGui
corner(subFrame, 10)
local subStroke = mkStroke(subFrame, Color3.fromRGB(70, 45, 105), 1)
subStroke.Transparency = 1

local subLayout = Instance.new("UIListLayout")
subLayout.FillDirection       = Enum.FillDirection.Horizontal
subLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
subLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
subLayout.Padding             = UDim.new(0, 5)
subLayout.Parent              = subFrame

local subPad = Instance.new("UIPadding")
subPad.PaddingLeft   = UDim.new(0, 12)
subPad.PaddingRight  = UDim.new(0, 14)
subPad.Parent        = subFrame

local subPrefix = Instance.new("TextLabel")
subPrefix.Size                  = UDim2.new(0, 0, 1, 0)
subPrefix.AutomaticSize         = Enum.AutomaticSize.X
subPrefix.BackgroundTransparency = 1
subPrefix.Text                  = "Selected"
subPrefix.TextColor3            = Color3.fromRGB(225, 215, 245)
subPrefix.Font                  = Enum.Font.GothamBold
subPrefix.TextSize              = 14
subPrefix.TextXAlignment        = Enum.TextXAlignment.Left
subPrefix.TextTransparency      = 1
subPrefix.ZIndex                = 21
subPrefix.Parent                = subFrame

local subName = Instance.new("TextLabel")
subName.Size                   = UDim2.new(0, 0, 1, 0)
subName.AutomaticSize          = Enum.AutomaticSize.X
subName.BackgroundTransparency = 1
subName.Text                   = ""
subName.Font                   = Enum.Font.GothamBold
subName.TextSize               = 14
subName.TextXAlignment         = Enum.TextXAlignment.Left
subName.TextTransparency       = 1
subName.ZIndex                 = 21
subName.Parent                 = subFrame

local subTask = nil

local function showSubtitle(toolName)
    if subTask then task.cancel(subTask) end
    subName.Text       = toolName
    subName.TextColor3 = SUBTITLE_COLORS[toolName] or SUBTITLE_COLORS.None
    subFrame.Visible   = true
    local fi = TweenInfo.new(0.2)
    TweenService:Create(subFrame,  fi, { BackgroundTransparency = 0.3 }):Play()
    TweenService:Create(subStroke, fi, { Transparency = 0 }):Play()
    TweenService:Create(subPrefix, fi, { TextTransparency = 0 }):Play()
    TweenService:Create(subName,   fi, { TextTransparency = 0 }):Play()
    subTask = task.delay(2.5, function()
        local fo = TweenInfo.new(0.4)
        TweenService:Create(subFrame,  fo, { BackgroundTransparency = 1 }):Play()
        TweenService:Create(subStroke, fo, { Transparency = 1 }):Play()
        TweenService:Create(subPrefix, fo, { TextTransparency = 1 }):Play()
        TweenService:Create(subName,   fo, { TextTransparency = 1 }):Play()
        task.delay(0.41, function()
            subFrame.Visible               = false
            subFrame.BackgroundTransparency = 1
            subStroke.Transparency          = 1
            subPrefix.TextTransparency      = 1
            subName.TextTransparency        = 1
        end)
    end)
end

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size             = UDim2.new(0, 30, 0, 20)
toggleBtn.AnchorPoint      = Vector2.new(0.5, 0)
toggleBtn.Position         = UDim2.new(0.5, 0, 0, BTN_SIZE + 5)
toggleBtn.BackgroundColor3 = C.btnNormal
toggleBtn.BorderSizePixel  = 0
toggleBtn.Text             = "^"
toggleBtn.TextColor3       = C.text
toggleBtn.Font             = Enum.Font.GothamBold
toggleBtn.TextSize         = 13
toggleBtn.ZIndex           = 12
toggleBtn.Parent           = anchor
corner(toggleBtn, 8); mkStroke(toggleBtn, C.btnBorder, 1)
sizeCon(toggleBtn)

local cpBtn = Instance.new("TextButton")
cpBtn.Size             = UDim2.new(0, BTN_SIZE, 0, BTN_SIZE)
cpBtn.BackgroundColor3 = C.btnNormal
cpBtn.BorderSizePixel  = 0
cpBtn.Text             = ""
cpBtn.ZIndex           = 10
cpBtn.Parent           = panel
corner(cpBtn, 8); mkStroke(cpBtn)
grad(cpBtn, Color3.fromRGB(100,72,175), Color3.fromRGB(62,42,118))
local cpImg = Instance.new("ImageLabel")
cpImg.Size                   = UDim2.new(0, 40, 0, 40)
cpImg.AnchorPoint            = Vector2.new(0.5, 0.5)
cpImg.Position               = UDim2.new(0.5, 0, 0.5, 0)
cpImg.BackgroundTransparency = 1
cpImg.Image                  = SPRITE
cpImg.ImageRectOffset        = Vector2.new(432, 0)
cpImg.ImageRectSize          = Vector2.new(72, 72)
cpImg.ZIndex                 = 11
cpImg.Parent                 = cpBtn
cpBtn.MouseButton1Click:Connect(function()
    panelOpen = false
    panel.Visible = false
    panel.Position = PANEL_OPEN_POS
    panel.BackgroundTransparency = 0.1
    if guiVisible then toggleBtn.Visible = true end
    TweenService:Create(anchor, TW_HIDE, { Position = HIDDEN_POS }):Play()
    task.delay(0.22, function()
        guiVisible = false
        toggleBtn.Parent      = screenGui
        toggleBtn.AnchorPoint = Vector2.new(0.5, 0)
        toggleBtn.Position    = UDim2.new(0.5, 0, 0, 4)
        toggleBtn.Text        = "V"
    end)
    if not _G.CopyPasteTool then
        task.spawn(function()
            task.wait()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/Neosq/CPT/refs/heads/main/CPT_Loader.lua"))()
        end)
    end
end)

local function openPanel()
    panelOpen = true
    if guiVisible then toggleBtn.Visible = false end
    panel.Visible               = true
    panel.Position              = PANEL_START_POS
    panel.BackgroundTransparency = 0.6
    for _, tb in ipairs(toolButtons) do tb.btn.BackgroundTransparency = 0.5 end
    TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = PANEL_OPEN_POS, BackgroundTransparency = 0.1,
    }):Play()
    for _, tb in ipairs(toolButtons) do
        TweenService:Create(tb.btn, TweenInfo.new(0.18), { BackgroundTransparency = 0 }):Play()
    end
end

local function closePanel()
    panelOpen = false
    TweenService:Create(panel, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = PANEL_START_POS,
    }):Play()
    task.delay(0.15, function()
        panel.Visible               = false
        panel.Position              = PANEL_OPEN_POS
        panel.BackgroundTransparency = 0.1
        for _, tb in ipairs(toolButtons) do
            tb.btn.BackgroundTransparency = 0
        end
        if guiVisible then toggleBtn.Visible = true end
    end)
end

local selectionBox  = nil
local hoveredModel  = nil

local function clearSelectionBox()
    if selectionBox then selectionBox:Destroy(); selectionBox = nil end
end

local gridValue = 4.5

local gridFrame = Instance.new("Frame")
gridFrame.Size                  = UDim2.new(0, 80, 0, 30)
gridFrame.AnchorPoint           = Vector2.new(0, 1)
gridFrame.Position              = UDim2.new(0, 16, 1, -80)
gridFrame.BackgroundTransparency = 1
gridFrame.BorderSizePixel       = 0
gridFrame.ZIndex                = 15
gridFrame.Visible               = false
gridFrame.Parent                = screenGui

local gridBox = Instance.new("TextBox")
gridBox.Size             = UDim2.new(1, 0, 1, 0)
gridBox.BackgroundColor3 = Color3.fromRGB(12, 8, 24)
gridBox.BorderSizePixel  = 0
gridBox.Text             = "4.5"
gridBox.TextColor3       = Color3.fromRGB(255, 248, 255)
gridBox.Font             = Enum.Font.GothamBold
gridBox.TextSize         = 18
gridBox.ClearTextOnFocus = true
gridBox.ZIndex           = 16
gridBox.Parent           = gridFrame
corner(gridBox, 8)
mkStroke(gridBox, C.btnBorder, 1.5)

gridBox.Focused:Connect(function()
    TweenService:Create(gridBox, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(38, 26, 66) }):Play()
end)

gridBox.FocusLost:Connect(function()
    TweenService:Create(gridBox, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(12, 8, 24) }):Play()
    local num = tonumber(gridBox.Text)
    if not num or num < 0.1 then num = 0.1 end
    if num > 100 then num = 100 end
    gridValue = num
    gridBox.Text = tostring(gridValue)
    if _G.PBM then _G.PBM.applyStep(gridValue) end
end)

local function updateUI()
    if not selectedTool then
        clearSelectionBox()
        gridFrame.Visible = false
    else
        gridFrame.Visible = true
    end
end

for i, tb in ipairs(toolButtons) do
    local tool = tb.tool
    tb.btn.MouseEnter:Connect(function()
        if selectedTool ~= tool.name then
            TweenService:Create(tb.btn, TweenInfo.new(0.1), { BackgroundColor3 = C.btnHover }):Play()
        end
    end)
    tb.btn.MouseLeave:Connect(function()
        if selectedTool ~= tool.name then
            TweenService:Create(tb.btn, TweenInfo.new(0.1), { BackgroundColor3 = C.btnNormal }):Play()
        end
    end)
    tb.btn.MouseButton1Click:Connect(function()
        if selectedTool == tool.name then
            selectedTool = nil
            setMainIcon(nil)
            showSubtitle("None")
        else
            selectedTool = tool.name
            setMainIcon(tool)
            showSubtitle(tool.name)
        end
        for _, tb2 in ipairs(toolButtons) do
            TweenService:Create(tb2.btn, TweenInfo.new(0.12), {
                BackgroundColor3 = (tb2.tool.name == selectedTool) and C.btnSelected or C.btnNormal
            }):Play()
        end
        closePanel()
        task.defer(updateUI)
        if _G.PBM then _G.PBM.selectTool(selectedTool) end
    end)
end

mainBtn.MouseButton1Click:Connect(function()
    panelOpen = not panelOpen
    if panelOpen then openPanel() else closePanel() end
end)
mainBtn.MouseEnter:Connect(function()
    TweenService:Create(mainBtn, TweenInfo.new(0.1), { BackgroundColor3 = C.btnHover }):Play()
end)
mainBtn.MouseLeave:Connect(function()
    TweenService:Create(mainBtn, TweenInfo.new(0.1), { BackgroundColor3 = C.btnNormal }):Play()
end)

toggleBtn.MouseButton1Click:Connect(function()
    if guiVisible then
        guiVisible = false
        if panelOpen then closePanel() end
        TweenService:Create(anchor, TW_HIDE, { Position = HIDDEN_POS }):Play()
        task.delay(0.22, function()
            toggleBtn.Parent      = screenGui
            toggleBtn.AnchorPoint = Vector2.new(0.5, 0)
            toggleBtn.Position    = UDim2.new(0.5, 0, 0, 4)
            toggleBtn.Text        = "V"
        end)
    else
        guiVisible = true
        toggleBtn.Text        = "^"
        toggleBtn.Parent      = anchor
        toggleBtn.AnchorPoint = Vector2.new(0.5, 0)
        toggleBtn.Position    = UDim2.new(0.5, 0, 0, BTN_SIZE + 5)
        anchor.Position = HIDDEN_POS
        TweenService:Create(anchor, TW_SHOW, { Position = SHOWN_POS }):Play()
    end
end)

updateUI()

_G.ToolSelectorGui = {
    getGridStep = function() return gridValue end
}
