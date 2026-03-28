local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse  = player:GetMouse()

local selectedBlock   = nil
local moveStep        = 4.5
local handleButtons   = {}
local isDragging      = false
local dragDir         = nil
local dragStartScreen = nil
local lastMoveSteps   = 0
local DRAG_SENS       = 0.08
local DRAG_THRESHOLD  = 8
local activeHandle    = nil
local activeTouchId   = nil
local previewParts    = {}
local previewOffset   = Vector3.new(0, 0, 0)
local originalTransp  = {}

local PURPLE = Color3.fromRGB(140, 90, 220)
local AXES = {
    {axis="X", dir=Vector3.new( 1, 0, 0)},
    {axis="X", dir=Vector3.new(-1, 0, 0)},
    {axis="Y", dir=Vector3.new( 0, 1, 0)},
    {axis="Y", dir=Vector3.new( 0,-1, 0)},
    {axis="Z", dir=Vector3.new( 0, 0, 1)},
    {axis="Z", dir=Vector3.new( 0, 0,-1)},
}

local function getModelCF(model)
    local ok, pv = pcall(function() return model:GetPivot() end)
    if ok and pv then return pv end
    local mfp = model:FindFirstChild("MouseFilterPart")
    if mfp then return mfp.CFrame end
    local cp = model:FindFirstChild("ColorPart")
    if cp then return cp.CFrame end
    return nil
end

local function getModelSize(model)
    local mfp = model:FindFirstChild("MouseFilterPart")
    if mfp then return mfp.Size end
    local cp = model:FindFirstChild("ColorPart")
    if cp then return cp.Size end
    return Vector3.new(4.5, 4.5, 4.5)
end

local function getBlockUnderMouse()
    local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local params  = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    local bm = workspace:FindFirstChild("BuildModel")
    if not bm then return nil end
    params.FilterDescendantsInstances = {bm}
    local res = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, params)
    if not res then return nil end
    local part = res.Instance
    while part and part.Parent ~= bm do part = part.Parent end
    return part
end

local function hideOriginal(model)
    originalTransp = {}
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            originalTransp[desc] = desc.Transparency
            desc.Transparency = 1
        end
    end
end

local function restoreOriginal()
    for part, tr in pairs(originalTransp) do
        if part and part.Parent then part.Transparency = tr end
    end
    originalTransp = {}
end

local function getVisualParts(model)
    local out = {}
    for _, desc in ipairs(model:GetDescendants()) do
        if not desc:IsA("BasePart") then continue end
        if desc.Name == "MouseFilterPart" then continue end
        local tr = originalTransp[desc] or desc.Transparency
        if tr < 1 then table.insert(out, desc) end
    end
    return out
end

local function destroyPreview()
    for _, p in ipairs(previewParts) do
        if p and p.Parent then p:Destroy() end
    end
    previewParts = {}
    restoreOriginal()
end

local function buildPreview(model)
    destroyPreview()
    if not model then return end
    hideOriginal(model)
    for _, src in ipairs(getVisualParts(model)) do
        local ghost = src:Clone()
        for _, child in ipairs(ghost:GetChildren()) do
            if not (child:IsA("SpecialMesh") or child:IsA("SurfaceAppearance")
                or child:IsA("Decal") or child:IsA("Texture")) then
                child:Destroy()
            end
        end
        ghost.Anchored     = true
        ghost.CanCollide   = false
        ghost.CastShadow   = false
        ghost.Transparency = originalTransp[src] or src.Transparency
        ghost.Name         = "MoveGhost"
        ghost.Parent       = workspace
        table.insert(previewParts, ghost)
    end
end

local multiLiveParts = {}  -- managed separately to avoid M reference before declaration
local multiGhosts    = {}  -- {model, parts[], origTransp} for multi preview

local function destroyMultiGhosts()
    for _, entry in ipairs(multiGhosts) do
        for _, p in ipairs(entry.parts) do
            if p and p.Parent then p:Destroy() end
        end
        for part, tr in pairs(entry.origTransp) do
            if part and part.Parent then part.Transparency = tr end
        end
    end
    multiGhosts = {}
    -- Restore SelectionBox adornees back to liveParts
    for _, lpe in ipairs(multiLiveParts) do
        if lpe.box and lpe.box.Parent and lpe.part and lpe.part.Parent then
            lpe.box.Adornee = lpe.part
        end
    end
end

local function buildPreviewMulti(models)
    destroyPreview(); destroyMultiGhosts()
    for _, model in ipairs(models) do
        local origT = {}
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("BasePart") then
                origT[desc] = desc.Transparency
                desc.Transparency = 1
            end
        end
        local parts = {}
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Name ~= "MouseFilterPart"
               and (origT[desc] or 0) < 1 then
                local ghost = desc:Clone()
                for _, child in ipairs(ghost:GetChildren()) do
                    if not (child:IsA("SpecialMesh") or child:IsA("SurfaceAppearance")
                        or child:IsA("Decal") or child:IsA("Texture")) then
                        child:Destroy()
                    end
                end
                ghost.Anchored=true; ghost.CanCollide=false; ghost.CastShadow=false
                ghost.Transparency=origT[desc]
                ghost.Name="MoveGhost"; ghost.Parent=workspace
                table.insert(parts, ghost)
            end
        end
        table.insert(multiGhosts, {model=model, parts=parts, origTransp=origT})
    end
end

local function updatePreviewMulti(offset)
    for _, entry in ipairs(multiGhosts) do
        local srcs = {}
        for _, desc in ipairs(entry.model:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Name ~= "MouseFilterPart"
               and (entry.origTransp[desc] or 0) < 1 then
                table.insert(srcs, desc)
            end
        end
        for i, ghost in ipairs(entry.parts) do
            if srcs[i] then ghost.CFrame = srcs[i].CFrame + offset end
        end
    end
    -- Update liveParts and re-adorn SelectionBox to first ghost of each model
    if multiLiveParts then
        for _, lpe in ipairs(multiLiveParts) do
            -- Find first ghost for this model
            for _, entry in ipairs(multiGhosts) do
                if entry.model == lpe.model and #entry.parts > 0 then
                    if lpe.box and lpe.box.Parent then
                        lpe.box.Adornee = entry.parts[1]
                    end
                    break
                end
            end
        end
    end
end

local M = {}

local function updatePreview(model, offset)
    if #previewParts == 0 then return end
    local srcs = getVisualParts(model)
    for i, ghost in ipairs(previewParts) do
        if srcs[i] then ghost.CFrame = srcs[i].CFrame + offset end
    end
    if M.onPreviewUpdate then
        local newCF = getModelCF(model) + offset
        M.onPreviewUpdate(newCF, nil)
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "MoveTool"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.AutoLocalize   = false
screenGui.Parent         = player.PlayerGui

local function uiCorner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local function clearHandles()
    for _, h in ipairs(handleButtons) do
        if h.button and h.button.Parent then h.button:Destroy() end
    end
    handleButtons   = {}
    isDragging      = false
    dragDir         = nil
    activeHandle    = nil
    activeTouchId   = nil
    lastMoveSteps   = 0
    previewOffset   = Vector3.new(0, 0, 0)
end

local function spawnHandles(model)
    clearHandles()
    if not model then return end
    for _, axDef in ipairs(AXES) do
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(0, 26, 0, 26)
        btn.AnchorPoint      = Vector2.new(0.5, 0.5)
        btn.Position         = UDim2.new(0, -200, 0, -200)
        btn.BackgroundColor3 = PURPLE
        btn.BackgroundTransparency = 0.2
        btn.Text             = ""
        btn.BorderSizePixel  = 0
        btn.ZIndex           = 10
        btn.Visible          = false
        btn.Parent           = screenGui
        uiCorner(btn, 999)
        local st = Instance.new("UIStroke")
        st.Color       = Color3.fromRGB(255, 255, 255)
        st.Transparency = 0.6
        st.Thickness   = 1.5
        st.Parent      = btn

        local capturedDir = axDef.dir
        btn.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch and
               input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if activeHandle ~= nil then return end
            activeHandle    = btn
            activeTouchId   = input
            isDragging      = true
            dragDir         = capturedDir
            dragStartScreen = Vector2.new(input.Position.X, input.Position.Y)
            lastMoveSteps   = 0
            previewOffset   = Vector3.new(0, 0, 0)
            btn.BackgroundTransparency = 0.0
            buildPreview(selectedBlock)
        end)
        table.insert(handleButtons, {button=btn, dir=axDef.dir, axis=axDef.axis})
    end
end

RunService.RenderStepped:Connect(function()
    if selectedBlock and selectedBlock.Parent and #handleButtons > 0 then
        local cf = getModelCF(selectedBlock)
        local sz = getModelSize(selectedBlock)
        if cf then
            for i, h in ipairs(handleButtons) do
                local d  = AXES[i].dir
                local wp = cf.Position + Vector3.new(
                    d.X*(sz.X*0.5+3), d.Y*(sz.Y*0.5+3), d.Z*(sz.Z*0.5+3))
                local sp, vis = camera:WorldToScreenPoint(wp)
                h.button.Visible = vis and sp.Z > 0
                if h.button.Visible then
                    h.button.Position = UDim2.new(0, sp.X, 0, sp.Y)
                end
            end
        end
    end
end)

UIS.InputChanged:Connect(function(input)
    if not isDragging or not selectedBlock or not dragDir then return end
    if activeTouchId and input ~= activeTouchId then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and
       input.UserInputType ~= Enum.UserInputType.Touch then return end
    local cur   = Vector2.new(input.Position.X, input.Position.Y)
    local delta = cur - dragStartScreen
    if delta.Magnitude < DRAG_THRESHOLD then return end
    local cf = getModelCF(selectedBlock)
    if not cf then return end
    local s0 = camera:WorldToScreenPoint(cf.Position)
    local s1 = camera:WorldToScreenPoint(cf.Position + dragDir * 10)
    local sd  = Vector2.new(s1.X - s0.X, s1.Y - s0.Y)
    if sd.Magnitude < 1 then return end
    local proj  = delta:Dot(sd / sd.Magnitude)
    local total = math.floor(proj * DRAG_SENS / moveStep)
    if total ~= lastMoveSteps then
        lastMoveSteps = total
        previewOffset = dragDir * (total * moveStep)
        if M._multiBlocks then
            if #multiGhosts == 0 then buildPreviewMulti(M._multiBlocks) end
            updatePreviewMulti(previewOffset)
        else
            updatePreview(selectedBlock, previewOffset)
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch and
       input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if activeTouchId ~= nil and input ~= activeTouchId then return end
    if isDragging and selectedBlock and lastMoveSteps ~= 0 then
        if M._multiBlocks then
            for _, block in ipairs(M._multiBlocks) do
                local cf = getModelCF(block)
                if cf then
                    pcall(function() RS.Functions.CommitMove:InvokeServer(block, cf + previewOffset) end)
                end
            end
            if M._multiAnchor then
                M._multiAnchor.CFrame = M._multiAnchor.CFrame + previewOffset
            end
            -- Update livePart positions immediately with offset
            if multiLiveParts then
                for _, lpe in ipairs(multiLiveParts) do
                    if lpe.part and lpe.part.Parent then
                        lpe.part.CFrame = lpe.part.CFrame + previewOffset
                    end
                end
            end
        else
            local newCF = getModelCF(selectedBlock) + previewOffset
            pcall(function() RS.Functions.CommitMove:InvokeServer(selectedBlock, newCF) end)
        end
    end
    destroyPreview(); destroyMultiGhosts()
    if activeHandle and activeHandle.Parent then
        activeHandle.BackgroundTransparency = 0.2
    end
    isDragging=false; dragDir=nil; lastMoveSteps=0
    activeHandle=nil; activeTouchId=nil
    previewOffset=Vector3.new(0,0,0)
end)

function M.activate(model)
    selectedBlock = model
    local mfp = model:FindFirstChild("MouseFilterPart")
    local cp  = model:FindFirstChild("ColorPart")
    local ref = mfp or cp or model:FindFirstChildWhichIsA("BasePart")
    local liveBox, livePart = nil, nil
    if ref and ref:IsA("BasePart") then
        livePart = Instance.new("Part")
        livePart.Size=ref.Size; livePart.CFrame=ref.CFrame
        livePart.Anchored=true; livePart.CanCollide=false
        livePart.Transparency=1; livePart.Parent=workspace
        liveBox=Instance.new("SelectionBox")
        liveBox.Color3=Color3.fromRGB(140,90,220); liveBox.LineThickness=0.06
        liveBox.Adornee=livePart; liveBox.Parent=workspace
    end
    M.onPreviewUpdate=function(newCF)
        if livePart and livePart.Parent then livePart.CFrame=newCF end
    end
    M._liveBox=liveBox; M._livePart=livePart
    M._multiBlocks=nil
    spawnHandles(model)
end

function M.activateMulti(models)
    if not models or #models==0 then return end
    M.deactivate()
    local sumPos = Vector3.new(0,0,0)
    for _, m in ipairs(models) do
        local cf = getModelCF(m); if cf then sumPos=sumPos+cf.Position end
    end
    local center = sumPos / #models
    local anchor = Instance.new("Part")
    anchor.Size=Vector3.new(4.5,4.5,4.5); anchor.CFrame=CFrame.new(center)
    anchor.Anchored=true; anchor.CanCollide=false; anchor.Transparency=1
    anchor.Parent=workspace
    selectedBlock=anchor
    M._multiBlocks=models
    M._multiAnchor=anchor
    -- Create a livePart+liveBox per block
    multiLiveParts = {}
    M._multiLiveBoxes = {}
    for _, m in ipairs(models) do
        local ref = m:FindFirstChild("MouseFilterPart") or m:FindFirstChild("ColorPart")
                    or m:FindFirstChildWhichIsA("BasePart")
        if ref and ref:IsA("BasePart") then
            local lp = Instance.new("Part")
            lp.Size=ref.Size; lp.CFrame=ref.CFrame
            lp.Anchored=true; lp.CanCollide=false; lp.Transparency=1
            lp.Parent=workspace
            local lb = Instance.new("SelectionBox")
            lb.Color3=Color3.fromRGB(140,90,220); lb.LineThickness=0.06
            lb.Adornee=lp; lb.Parent=workspace
            table.insert(multiLiveParts, {part=lp, box=lb, model=m})
        end
    end
    M.onPreviewUpdate = nil
    spawnHandles(anchor)
end

function M.deactivate()
    selectedBlock = nil
    if M._liveBox  and M._liveBox.Parent  then M._liveBox:Destroy()  end
    if M._livePart and M._livePart.Parent then M._livePart:Destroy() end
    if M._multiAnchor and M._multiAnchor.Parent then M._multiAnchor:Destroy() end
    if multiLiveParts then
        for _, entry in ipairs(multiLiveParts) do
            if entry.box and entry.box.Parent then entry.box:Destroy() end
            if entry.part and entry.part.Parent then entry.part:Destroy() end
        end
        multiLiveParts = {}
        M._multiLiveBoxes = {}
    end
    M._liveBox=nil; M._livePart=nil
    M._multiBlocks=nil; M._multiAnchor=nil
    M.onPreviewUpdate=nil
    clearHandles()
    destroyPreview(); destroyMultiGhosts()
end

function M.setStep(step)
    moveStep = step
end

_G.MoveTool = M
