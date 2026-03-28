local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player     = Players.LocalPlayer
local camera     = workspace.CurrentCamera

local Functions   = RS:WaitForChild("Functions")
local PlaceBlock  = Functions:WaitForChild("PlaceBlock")
local CommitMove  = Functions:WaitForChild("CommitMove")
local CommitResize= Functions:WaitForChild("CommitResize")
local DestroyBlock= Functions:WaitForChild("DestroyBlock")

local function findTemplate(name)
    -- Use CPT_Utils if available (same server)
    if _G.CPT_Utils then return _G.CPT_Utils.findBlockInRS(name) end
    -- Fallback: same logic as findBlockInRS
    local cats = {"Basic","Decoration","Events","Items","Lights","Links"}
    local blocks = RS:FindFirstChild("Blocks")
    if blocks then
        for _, cat in ipairs(cats) do
            local f = blocks:FindFirstChild(cat)
            if f then
                local b = f:FindFirstChild(name)
                if b then return b:FindFirstChild(name) or b end
            end
        end
    end
    local npcs = RS:FindFirstChild("BlocksCutscene")
    npcs = npcs and npcs:FindFirstChild("NPCs")
    if npcs then
        local b = npcs:FindFirstChild(name)
        if b then return b:FindFirstChild(name) or b end
    end
    return nil
end
local M = {}
local CYAN        = Color3.fromRGB(0, 210, 220)
local DRAG_SENS   = 0.08
local DRAG_THRESH = 8
local SAFE_SPAWN  = CFrame.new(0, 10000, 0)
local safeOff     = 0

local moveStep      = 4.5
local handleButtons = {}
local isDragging    = false
local activeHandle  = nil
local activeTouchId = nil
local dragDir       = nil
local dragStart     = nil
local lastSteps     = 0
local previewOffset = Vector3.new(0,0,0)

-- State
local selectedModel = nil  -- block user tapped (just selected, not copied yet)
local copiedBlock   = nil  -- the placed copy
local livePart      = nil
local liveBox       = nil

local AXES = {
    {dir=Vector3.new( 1,0,0)}, {dir=Vector3.new(-1,0,0)},
    {dir=Vector3.new( 0,1,0)}, {dir=Vector3.new( 0,-1,0)},
    {dir=Vector3.new( 0,0, 1)}, {dir=Vector3.new( 0,0,-1)},
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CopyTool"; screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player.PlayerGui

local function uiCorner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=p
end

local function getModelRef(model)
    return model:FindFirstChild("ColorPart")
        or model:FindFirstChild("MouseFilterPart")
        or model:FindFirstChildWhichIsA("BasePart")
end

-- Live part (selection box adornee)
local function destroyLiveBox()
    if liveBox  and liveBox.Parent  then liveBox:Destroy()  end
    if livePart and livePart.Parent then livePart:Destroy() end
    liveBox = nil; livePart = nil
end

local function createLiveBox(model, offset)
    destroyLiveBox()
    local ref = getModelRef(model); if not ref then return end
    livePart = Instance.new("Part")
    livePart.Size=ref.Size; livePart.CFrame=ref.CFrame + (offset or Vector3.new(0,0,0))
    livePart.Anchored=true; livePart.CanCollide=false; livePart.Transparency=1
    livePart.Parent=workspace
    liveBox = Instance.new("SelectionBox")
    liveBox.Color3=CYAN; liveBox.LineThickness=0.06
    liveBox.Adornee=livePart; liveBox.Parent=workspace
end

local function updateLiveBox()
    if not copiedBlock or not livePart then return end
    local ref = getModelRef(copiedBlock); if not ref then return end
    livePart.CFrame = ref.CFrame + previewOffset
    livePart.Size   = ref.Size
end

-- Handles (shown only after Copy is pressed)
local function clearHandles()
    for _, h in ipairs(handleButtons) do
        if h.btn and h.btn.Parent then h.btn:Destroy() end
    end
    handleButtons={}; isDragging=false; activeHandle=nil; activeTouchId=nil
    dragDir=nil; lastSteps=0; previewOffset=Vector3.new(0,0,0)
end

local function spawnHandles()
    clearHandles()
    if not copiedBlock then return end
    for _, axDef in ipairs(AXES) do
        local btn = Instance.new("TextButton")
        btn.Size=UDim2.new(0,26,0,26); btn.AnchorPoint=Vector2.new(0.5,0.5)
        btn.Position=UDim2.new(0,-200,0,-200)
        btn.BackgroundColor3=CYAN; btn.BackgroundTransparency=0.2
        btn.Text=""; btn.BorderSizePixel=0; btn.ZIndex=10; btn.Visible=false
        btn.Parent=screenGui; uiCorner(btn,999)
        local st=Instance.new("UIStroke"); st.Color=Color3.fromRGB(0,180,200)
        st.Thickness=1.5; st.Parent=btn
        local capDir=axDef.dir
        btn.InputBegan:Connect(function(input)
            if input.UserInputType~=Enum.UserInputType.Touch
            and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
            if isDragging then return end
            isDragging=true; activeHandle=btn; activeTouchId=input
            dragDir=capDir; dragStart=Vector2.new(input.Position.X,input.Position.Y)
            lastSteps=0; btn.BackgroundTransparency=0
        end)
        table.insert(handleButtons, {btn=btn, dir=axDef.dir})
    end
end

RunService.RenderStepped:Connect(function()
    if not copiedBlock or #handleButtons==0 then return end
    local ref=getModelRef(copiedBlock); if not ref then return end
    local sz=ref.Size; local pos=ref.CFrame.Position+previewOffset
    for _,h in ipairs(handleButtons) do
        local d=h.dir
        local wp=pos+Vector3.new(d.X*(sz.X*0.5+3),d.Y*(sz.Y*0.5+3),d.Z*(sz.Z*0.5+3))
        local sp,vis=camera:WorldToScreenPoint(wp)
        h.btn.Visible=vis and sp.Z>0
        if h.btn.Visible then h.btn.Position=UDim2.new(0,sp.X,0,sp.Y) end
    end
end)

UIS.InputChanged:Connect(function(input)
    if not isDragging or not dragDir or not copiedBlock then return end
    if activeTouchId and input~=activeTouchId then return end
    if input.UserInputType~=Enum.UserInputType.Touch
    and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local ref=getModelRef(copiedBlock); if not ref then return end
    local cur=Vector2.new(input.Position.X,input.Position.Y)
    local delta=cur-dragStart
    local s0=camera:WorldToScreenPoint(ref.CFrame.Position)
    local s1=camera:WorldToScreenPoint(ref.CFrame.Position+dragDir*10)
    local sd=Vector2.new(s1.X-s0.X,s1.Y-s0.Y)
    if sd.Magnitude<1 then return end
    local proj=delta:Dot(sd/sd.Magnitude)
    local steps=math.floor(proj*DRAG_SENS/moveStep)
    if steps~=lastSteps then
        lastSteps=steps; previewOffset=dragDir*(steps*moveStep)
        updateLiveBox()
    end
end)

UIS.InputEnded:Connect(function(input)
    if not isDragging then return end
    if activeTouchId and input~=activeTouchId then return end
    if input.UserInputType~=Enum.UserInputType.Touch
    and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    isDragging=false
    if activeHandle then activeHandle.BackgroundTransparency=0.2 end
    activeHandle=nil; activeTouchId=nil
end)

-- HUDs
local copyHudGui  = nil
local pasteHudGui = nil

local function destroyCopyHud()
    if copyHudGui and copyHudGui.Parent then copyHudGui:Destroy() end
    copyHudGui=nil
end
local function destroyPasteHud()
    if pasteHudGui and pasteHudGui.Parent then pasteHudGui:Destroy() end
    pasteHudGui=nil
end

local function mkHudBase(w)
    local g=Instance.new("ScreenGui"); g.ResetOnSpawn=false; g.DisplayOrder=60; g.Parent=player.PlayerGui
    local f=Instance.new("Frame"); f.Size=UDim2.new(0,w,0,50)
    f.AnchorPoint=Vector2.new(0.5,1); f.Position=UDim2.new(0.5,0,1,-80)
    f.BackgroundColor3=Color3.fromRGB(12,8,24); f.BackgroundTransparency=0.15
    f.BorderSizePixel=0; f.ZIndex=20; f.Parent=g; uiCorner(f,12)
    local st=Instance.new("UIStroke"); st.Color=CYAN; st.Thickness=1.5; st.Parent=f
    local lo=Instance.new("UIListLayout"); lo.FillDirection=Enum.FillDirection.Horizontal
    lo.VerticalAlignment=Enum.VerticalAlignment.Center
    lo.HorizontalAlignment=Enum.HorizontalAlignment.Center
    lo.Padding=UDim.new(0,8); lo.Parent=f
    local pad=Instance.new("UIPadding")
    pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10); pad.Parent=f
    return g, f
end

local function mkBtn(parent, text, color)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(0,88,0,34)
    b.BackgroundColor3=color; b.BorderSizePixel=0
    b.Text=text; b.TextColor3=Color3.fromRGB(255,255,255)
    b.Font=Enum.Font.GothamBold; b.TextSize=14; b.ZIndex=21; b.Parent=parent
    uiCorner(b,8); return b
end

local function doCopy()
    print("[CopyTool] doCopy called, selectedModel:", selectedModel)
    if not selectedModel then return end
    local ref=getModelRef(selectedModel)
    print("[CopyTool] ref:", ref)
    if not ref then return end
    local t=findTemplate(selectedModel.Name)
    print("[CopyTool] template:", t, "name:", selectedModel.Name)
    if not t then return end
    local cp=selectedModel:FindFirstChild("ColorPart")
    local bc=cp and cp.BrickColor or BrickColor.new("Medium stone grey")
    local mat=cp and cp.Material or Enum.Material.Plastic
    safeOff=safeOff+6
    local nb
    pcall(function() nb=PlaceBlock:InvokeServer(t,SAFE_SPAWN*CFrame.new(safeOff,0,0),bc,mat) end)
    print("[CopyTool] PlaceBlock result:", nb)
    if not nb then return end
    pcall(function() CommitMove:InvokeServer(nb,ref.CFrame) end)
    if cp then
        local sz=cp.Size
        if math.abs(sz.X-4.5)>0.1 or math.abs(sz.Y-4.5)>0.1 or math.abs(sz.Z-4.5)>0.1 then
            task.wait(0.05)
            local newRef=getModelRef(nb)
            if newRef then pcall(function() CommitResize:InvokeServer(nb,{newRef,ref.CFrame,sz}) end) end
        end
    end
    copiedBlock=nb; previewOffset=Vector3.new(0,0,0)
    destroyCopyHud()
    -- Switch liveBox to copiedBlock
    createLiveBox(nb)
    spawnHandles()
    -- Show paste HUD
    local g,f=mkHudBase(220)
    pasteHudGui=g
    local pasteBtn=mkBtn(f,"Paste", Color3.fromRGB(0,175,185))
    local cancelBtn=mkBtn(f,"Cancel",Color3.fromRGB(90,60,130))
    pasteBtn.MouseButton1Click:Connect(function()
        if not copiedBlock then return end
        local r=getModelRef(copiedBlock)
        if r then pcall(function() CommitMove:InvokeServer(copiedBlock,r.CFrame+previewOffset) end) end
        M.deactivate()
    end)
    cancelBtn.MouseButton1Click:Connect(function()
        if copiedBlock then pcall(function() DestroyBlock:InvokeServer(copiedBlock) end) end
        M.deactivate()
    end)
end

function M.activate(model)
    M.deactivate()
    if not model then return end
    selectedModel=model
    -- Show selection box on chosen block
    createLiveBox(model)
    -- Show Copy HUD
    local g,f=mkHudBase(140)
    copyHudGui=g
    local copyBtn=mkBtn(f,"Copy",Color3.fromRGB(0,175,185))
    copyBtn.MouseButton1Click:Connect(function()
        task.spawn(doCopy)
    end)
end

function M.deactivate()
    clearHandles()
    destroyLiveBox()
    destroyCopyHud()
    destroyPasteHud()
    selectedModel=nil; copiedBlock=nil
    previewOffset=Vector3.new(0,0,0)
end

function M.setStep(step)
    moveStep=math.max(0.1,step)
end

_G.CopyTool = M
