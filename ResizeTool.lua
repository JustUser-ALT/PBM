local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse  = player:GetMouse()

local resizeBlock     = nil
local resizeBox       = nil
local resizeStep      = 4.5
local handleButtons   = {}
local isDragging      = false
local activeHandle    = nil
local activeTouchId   = nil
local dragStartScreen = nil
local lastDragSteps   = 0
local lastHandleData  = nil
local DRAG_SENS       = 0.08
local DRAG_THRESHOLD  = 8
local cachedScreenDir = nil
local previewParts    = {}
local previewSize     = nil
local previewCF       = nil
local originalTransp  = {}

local ORANGE = Color3.fromRGB(255, 150, 40)
local AXES = {
    {axis="X", dir=Vector3.new( 1, 0, 0), sign= 1},
    {axis="X", dir=Vector3.new(-1, 0, 0), sign=-1},
    {axis="Y", dir=Vector3.new( 0, 1, 0), sign= 1},
    {axis="Y", dir=Vector3.new( 0,-1, 0), sign=-1},
    {axis="Z", dir=Vector3.new( 0, 0, 1), sign= 1},
    {axis="Z", dir=Vector3.new( 0, 0,-1), sign=-1},
}

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

local multiOrigTransp = {}

local function restoreMultiOriginal()
    for part, tr in pairs(multiOrigTransp) do
        if part and part.Parent then part.Transparency = tr end
    end
    multiOrigTransp = {}
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
    previewSize  = nil
    previewCF    = nil
    restoreOriginal()
    restoreMultiOriginal()
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
        ghost.Name         = "ResizeGhost"
        ghost.Parent       = workspace
        table.insert(previewParts, ghost)
    end
end

local function buildPreviewMulti(models)
    destroyPreview()
    multiOrigTransp = {}
    for _, model in ipairs(models) do
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("BasePart") then
                multiOrigTransp[desc] = desc.Transparency
                desc.Transparency = 1
            end
        end
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Name ~= "MouseFilterPart"
               and (multiOrigTransp[desc] or 0) < 1 then
                local ghost = desc:Clone()
                for _, child in ipairs(ghost:GetChildren()) do
                    if not (child:IsA("SpecialMesh") or child:IsA("SurfaceAppearance")
                        or child:IsA("Decal") or child:IsA("Texture")) then
                        child:Destroy()
                    end
                end
                ghost.Anchored=true; ghost.CanCollide=false; ghost.CastShadow=false
                ghost.Transparency=multiOrigTransp[desc]
                ghost.Name="ResizeGhost"; ghost.Parent=workspace
                table.insert(previewParts, ghost)
            end
        end
    end
end

local function restoreMultiOriginal()
    for part, tr in pairs(multiOrigTransp) do
        if part and part.Parent then part.Transparency = tr end
    end
    multiOrigTransp = {}
end

local M = {}

local function updatePreview(handleData, totalSteps)
    if not resizeBlock or #previewParts == 0 then return end
    local axis   = handleData.axis
    local change = totalSteps * resizeStep
    if M._multiBlocks then
        -- Update preview for all multi blocks
        local ghostIdx = 1
        for _, block in ipairs(M._multiBlocks) do
            local bcp = block:FindFirstChild("ColorPart")
            if not bcp then continue end
            local bOrigSize = bcp.Size
            local bNewSize = Vector3.new(
                axis=="X" and math.max(0.1, bOrigSize.X+change) or bOrigSize.X,
                axis=="Y" and math.max(0.1, bOrigSize.Y+change) or bOrigSize.Y,
                axis=="Z" and math.max(0.1, bOrigSize.Z+change) or bOrigSize.Z
            )
            local bActual = axis=="X" and (bNewSize.X-bOrigSize.X)
                         or axis=="Y" and (bNewSize.Y-bOrigSize.Y)
                         or (bNewSize.Z-bOrigSize.Z)
            local bNewCF = bcp.CFrame * CFrame.new(handleData.dir * (bActual*0.5))
            -- Update ghosts for this block
            local srcs = {}
            for _, desc in ipairs(block:GetDescendants()) do
                if desc:IsA("BasePart") and desc.Name ~= "MouseFilterPart"
                   and (multiOrigTransp[desc] or 0) < 1 then
                    table.insert(srcs, desc)
                end
            end
            for i, src in ipairs(srcs) do
                local ghost = previewParts[ghostIdx]
                if not ghost then break end
                if src == bcp then
                    ghost.Size   = bNewSize
                    ghost.CFrame = bNewCF
                else
                    ghost.CFrame = bNewCF * bcp.CFrame:ToObjectSpace(src.CFrame)
                end
                ghostIdx = ghostIdx + 1
            end
            -- Store last block's preview for commit
            if block == resizeBlock then
                previewSize = bNewSize
                previewCF   = bNewCF
            end
        end
    else
        local cp = resizeBlock:FindFirstChild("ColorPart")
        if not cp then return end
        local origSize = cp.Size
        local newSize  = Vector3.new(
            axis=="X" and math.max(0.1, origSize.X+change) or origSize.X,
            axis=="Y" and math.max(0.1, origSize.Y+change) or origSize.Y,
            axis=="Z" and math.max(0.1, origSize.Z+change) or origSize.Z
        )
        local actualChange
        if axis=="X" then actualChange=newSize.X-origSize.X
        elseif axis=="Y" then actualChange=newSize.Y-origSize.Y
        else actualChange=newSize.Z-origSize.Z end
        local newCF = cp.CFrame * CFrame.new(handleData.dir * (actualChange*0.5))
        previewSize = newSize
        previewCF   = newCF
        local srcs = getVisualParts(resizeBlock)
        for i, ghost in ipairs(previewParts) do
            local src = srcs[i]; if not src then continue end
            if src == cp then ghost.Size=newSize; ghost.CFrame=newCF
            else ghost.CFrame=newCF*cp.CFrame:ToObjectSpace(src.CFrame) end
        end
        if M.onPreviewUpdate then M.onPreviewUpdate(newCF, newSize) end
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "ResizeTool"
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
    activeHandle    = nil
    activeTouchId   = nil
    lastDragSteps   = 0
    cachedScreenDir = nil
end

local function spawnHandles(model)
    clearHandles()
    if not model then return end
    for _, axDef in ipairs(AXES) do
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(0, 26, 0, 26)
        btn.AnchorPoint      = Vector2.new(0.5, 0.5)
        btn.Position         = UDim2.new(0, -300, 0, -300)
        btn.BackgroundColor3 = ORANGE
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

        local captured = axDef
        btn.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch and
               input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if activeHandle ~= nil then return end
            activeHandle    = btn
            activeTouchId   = input
            isDragging      = true
            dragStartScreen = Vector2.new(input.Position.X, input.Position.Y)
            lastDragSteps   = 0
            cachedScreenDir = nil
            local cp = resizeBlock:FindFirstChild("ColorPart")
            if cp then
                local worldDir = cp.CFrame:VectorToWorldSpace(captured.dir)
                local s0 = camera:WorldToScreenPoint(cp.CFrame.Position)
                local s1 = camera:WorldToScreenPoint(cp.CFrame.Position + worldDir * 10)
                local sd  = Vector2.new(s1.X - s0.X, s1.Y - s0.Y)
                if sd.Magnitude > 1 then cachedScreenDir = sd / sd.Magnitude end
            end
            btn.BackgroundTransparency = 0.0
            if M._multiBlocks then
                buildPreviewMulti(M._multiBlocks)
            else
                buildPreview(resizeBlock)
            end
        end)
        table.insert(handleButtons, {button=btn, axis=axDef.axis, sign=axDef.sign, dir=axDef.dir})
    end
end

RunService.RenderStepped:Connect(function()
    if resizeBlock and #handleButtons > 0 then
        local cp = resizeBlock:FindFirstChild("ColorPart")
        if cp then
            local cf = cp.CFrame
            local sz = cp.Size
            for _, h in ipairs(handleButtons) do
                local half = h.axis == "X" and sz.X * 0.5
                    or h.axis == "Y" and sz.Y * 0.5
                    or sz.Z * 0.5
                local wp = cf:PointToWorldSpace(h.dir * (half + 2.5))
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
    if not isDragging or not activeHandle or not cachedScreenDir then return end
    if activeTouchId and input ~= activeTouchId then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and
       input.UserInputType ~= Enum.UserInputType.Touch then return end
    local cur   = Vector2.new(input.Position.X, input.Position.Y)
    local delta = cur - dragStartScreen
    if delta.Magnitude < DRAG_THRESHOLD then return end
    local proj  = delta:Dot(cachedScreenDir)
    local total = math.floor(proj * DRAG_SENS / resizeStep)
    if total ~= lastDragSteps then
        lastDragSteps = total
        for _, h in ipairs(handleButtons) do
            if h.button == activeHandle then
                lastHandleData = h
                updatePreview(h, total)
                break
            end
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch and
       input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if activeTouchId ~= nil and input ~= activeTouchId then return end
    if isDragging and lastDragSteps ~= 0 and resizeBlock and previewSize and previewCF then
        local cp = resizeBlock:FindFirstChild("ColorPart")
        if cp then
            pcall(function()
                RS.Functions.CommitResize:InvokeServer(resizeBlock, {cp, previewCF, previewSize})
            end)
        end
        if M._multiBlocks and lastHandleData then
            for _, block in ipairs(M._multiBlocks) do
                if block == resizeBlock then continue end
                local bcp = block:FindFirstChild("ColorPart")
                if bcp then
                    local axis = lastHandleData.axis
                    local bNewSize = Vector3.new(
                        axis=="X" and math.max(0.1, bcp.Size.X + lastDragSteps*resizeStep) or bcp.Size.X,
                        axis=="Y" and math.max(0.1, bcp.Size.Y + lastDragSteps*resizeStep) or bcp.Size.Y,
                        axis=="Z" and math.max(0.1, bcp.Size.Z + lastDragSteps*resizeStep) or bcp.Size.Z
                    )
                    local delta = axis=="X" and (bNewSize.X-bcp.Size.X)
                              or axis=="Y" and (bNewSize.Y-bcp.Size.Y)
                              or (bNewSize.Z-bcp.Size.Z)
                    local bNewCF = bcp.CFrame * CFrame.new(lastHandleData.dir * (delta*0.5))
                    pcall(function() RS.Functions.CommitResize:InvokeServer(block, {bcp, bNewCF, bNewSize}) end)
                end
            end
        end
    end
    destroyPreview()
    if activeHandle and activeHandle.Parent then
        activeHandle.BackgroundTransparency = 0.2
    end
    isDragging      = false
    activeHandle    = nil
    activeTouchId   = nil
    lastDragSteps   = 0
    lastHandleData  = nil
    cachedScreenDir = nil
end)

local liveBox  = nil
local livePart = nil

function M.activate(model)
    resizeBlock = model
    if resizeBox then resizeBox:Destroy(); resizeBox = nil end
    if liveBox   then liveBox:Destroy();  liveBox   = nil end
    if livePart  then livePart:Destroy(); livePart  = nil end
    local cp    = model:FindFirstChild("ColorPart")
    local adorn = cp or model:FindFirstChild("MouseFilterPart") or model
    livePart = Instance.new("Part")
    livePart.Size        = adorn:IsA("BasePart") and adorn.Size or Vector3.new(4.5,4.5,4.5)
    livePart.CFrame      = adorn:IsA("BasePart") and adorn.CFrame or CFrame.new(0,0,0)
    livePart.Anchored    = true
    livePart.CanCollide  = false
    livePart.Transparency = 1
    livePart.Parent      = workspace
    liveBox = Instance.new("SelectionBox")
    liveBox.Color3        = Color3.fromRGB(255, 160, 50)
    liveBox.LineThickness = 0.06
    liveBox.Adornee       = livePart
    liveBox.Parent        = workspace
    resizeBox = liveBox
    M.onPreviewUpdate = function(newCF, newSize)
        if livePart and livePart.Parent then
            livePart.CFrame = newCF
            livePart.Size   = newSize
        end
    end
    spawnHandles(model)
end

function M.deactivate()
    resizeBlock = nil
    if resizeBox then resizeBox:Destroy(); resizeBox = nil end
    if liveBox   then liveBox:Destroy();  liveBox   = nil end
    if livePart  then livePart:Destroy(); livePart  = nil end
    if M._multiLiveParts then
        for _, lpe in ipairs(M._multiLiveParts) do
            if lpe.box  and lpe.box.Parent  then lpe.box:Destroy()  end
            if lpe.part and lpe.part.Parent then lpe.part:Destroy() end
        end
        M._multiLiveParts = {}
    end
    M.onPreviewUpdate = nil
    M._multiBlocks = nil
    clearHandles()
    destroyPreview()
end

function M.activateMulti(models)
    if not models or #models==0 then return end
    M._multiBlocks = models
    M.activate(models[#models])
    -- Add liveParts for non-active blocks
    M._multiLiveParts = M._multiLiveParts or {}
    for i = 1, #models - 1 do
        local m = models[i]
        local ref = m:FindFirstChild("MouseFilterPart") or m:FindFirstChild("ColorPart")
                    or m:FindFirstChildWhichIsA("BasePart")
        if ref and ref:IsA("BasePart") then
            local lp = Instance.new("Part")
            lp.Size=ref.Size; lp.CFrame=ref.CFrame
            lp.Anchored=true; lp.CanCollide=false; lp.Transparency=1
            lp.Parent=workspace
            local lb = Instance.new("SelectionBox")
            lb.Color3=Color3.fromRGB(255,160,50); lb.LineThickness=0.06
            lb.Adornee=lp; lb.Parent=workspace
            table.insert(M._multiLiveParts, {part=lp, box=lb, model=m})
        end
    end
end

function M.setStep(step)
    resizeStep = step
end

_G.ResizeTool = M
