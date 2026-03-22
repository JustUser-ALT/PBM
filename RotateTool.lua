local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse  = player:GetMouse()

local selectedBlock   = nil
local rotateStep      = 45
local handleButtons   = {}
local ringContainers  = {}
local isPressing      = false
local isDragging      = false
local holdTimer       = 0
local HOLD_TIME       = 0.25
local activeHandle    = nil
local dragStartScreen = nil
local lastSteps       = 0
local cachedScreenDir = nil
local cachedAxDef     = nil
local DRAG_SENS       = 0.55
local activeTouchId   = nil
local previewParts    = {}
local previewCF       = nil
local originalTransp  = {}

local AXIS_DEFS = {
    {
        id      = "X",
        color   = Color3.fromRGB(210, 50,  50),
        rotAxis = Vector3.new(1, 0, 0),
        ringU   = Vector3.new(0, 1, 0),
        ringV   = Vector3.new(0, 0, 1),
        dot1    = Vector3.new( 0, 0, 1),
        dot2    = Vector3.new( 0, 0,-1),
    },
    {
        id      = "Y",
        color   = Color3.fromRGB(50,  210, 60),
        rotAxis = Vector3.new(0, 1, 0),
        ringU   = Vector3.new(1, 0, 0),
        ringV   = Vector3.new(0, 0, 1),
        dot1    = Vector3.new( 1, 0, 0),
        dot2    = Vector3.new(-1, 0, 0),
    },
    {
        id      = "Z",
        color   = Color3.fromRGB(60,  110, 230),
        rotAxis = Vector3.new(0, 0, 1),
        ringU   = Vector3.new(1, 0, 0),
        ringV   = Vector3.new(0, 1, 0),
        dot1    = Vector3.new( 0, 1, 0),
        dot2    = Vector3.new( 0,-1, 0),
    },
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

local function getDragDir(cf, axDef)
    local tangent = axDef.ringU
    local s0 = camera:WorldToScreenPoint(cf.Position)
    local s1 = camera:WorldToScreenPoint(cf.Position + tangent * 10)
    local sd  = Vector2.new(s1.X - s0.X, s1.Y - s0.Y)
    if sd.Magnitude < 0.5 then
        s1 = camera:WorldToScreenPoint(cf.Position + axDef.ringV * 10)
        sd = Vector2.new(s1.X - s0.X, s1.Y - s0.Y)
    end
    if sd.Magnitude < 0.5 then return nil end
    return sd / sd.Magnitude
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
        ghost.Name         = "RotateGhost"
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
                ghost.Name="RotateGhost"; ghost.Parent=workspace
                table.insert(previewParts, ghost)
            end
        end
    end
end

local M = {}

local function updatePreview(model, axDef, totalSteps)
    if not model or #previewParts == 0 then return end
    local cf = getModelCF(model)
    if not cf then return end
    local angle = math.rad(rotateStep * totalSteps)
    local rotCF = CFrame.fromAxisAngle(axDef.rotAxis, angle)
    if M._multiBlocks then
        -- Update preview for all multi blocks
        local ghostIdx = 1
        for _, block in ipairs(M._multiBlocks) do
            local bcf = getModelCF(block); if not bcf then continue end
            local bpos = bcf.Position
            local newBCF = CFrame.new(bpos) * rotCF * (bcf - bpos)
            for _, desc in ipairs(block:GetDescendants()) do
                if desc:IsA("BasePart") and desc.Name ~= "MouseFilterPart"
                   and (multiOrigTransp[desc] or 0) < 1 then
                    if previewParts[ghostIdx] then
                        previewParts[ghostIdx].CFrame = newBCF * bcf:ToObjectSpace(desc.CFrame)
                    end
                    ghostIdx = ghostIdx + 1
                end
            end
            -- Update liveBox
            if M._multiLiveParts then
                for _, lpe in ipairs(M._multiLiveParts) do
                    if lpe.model == block and lpe.part and lpe.part.Parent then
                        lpe.part.CFrame = newBCF
                    end
                end
            end
        end
    else
        local pos   = cf.Position
        local newCF = CFrame.new(pos) * rotCF * (cf - pos)
        previewCF   = newCF
        local srcs  = getVisualParts(model)
        for i, ghost in ipairs(previewParts) do
            local src = srcs[i]; if not src then continue end
            ghost.CFrame = newCF * cf:ToObjectSpace(src.CFrame)
        end
        if M.onPreviewUpdate then M.onPreviewUpdate(newCF, nil) end
    end
end

local function commitRotate()
    if not selectedBlock then return end
    if M._multiBlocks and cachedAxDef and lastSteps ~= 0 then
        local angle = math.rad(rotateStep * lastSteps)
        local rotCF = CFrame.fromAxisAngle(cachedAxDef.rotAxis, angle)
        for _, block in ipairs(M._multiBlocks) do
            local cf = getModelCF(block)
            if cf then
                local pos = cf.Position
                local newCF = CFrame.new(pos) * rotCF * (cf - pos)
                pcall(function() RS.Functions.CommitMove:InvokeServer(block, newCF) end)
            end
        end
    elseif previewCF then
        pcall(function() RS.Functions.CommitMove:InvokeServer(selectedBlock, previewCF) end)
    end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "RotateTool"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.AutoLocalize   = false
screenGui.Parent         = player.PlayerGui

local function uiCorner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local RING_SEGS  = 48
local RING_THICK = 3
local DOT_SIZE   = 26

local function destroyGizmos()
    for _, rc in ipairs(ringContainers) do
        if rc.container and rc.container.Parent then rc.container:Destroy() end
    end
    ringContainers = {}
    for _, h in ipairs(handleButtons) do
        if h.button and h.button.Parent then h.button:Destroy() end
    end
    handleButtons = {}
end

local function hideRing(rc)
    for _, seg in ipairs(rc.segs) do seg.Visible = false end
end

local function clearHandles()
    isPressing      = false
    isDragging      = false
    holdTimer       = 0
    cachedScreenDir = nil
    cachedAxDef     = nil
    lastSteps       = 0
    activeHandle    = nil
    activeTouchId   = nil
    destroyGizmos()
    destroyPreview()
end

local function spawnHandles(model)
    clearHandles()
    if not model then return end
    for _, axDef in ipairs(AXIS_DEFS) do
        local container = Instance.new("Frame")
        container.Size                  = UDim2.new(1, 0, 1, 0)
        container.BackgroundTransparency = 1
        container.BorderSizePixel       = 0
        container.ZIndex                = 6
        container.Parent                = screenGui
        local segs = {}
        for i = 1, RING_SEGS do
            local seg = Instance.new("Frame")
            seg.BackgroundColor3     = axDef.color
            seg.BackgroundTransparency = 0.25
            seg.BorderSizePixel      = 0
            seg.ZIndex               = 6
            seg.Visible              = false
            seg.Parent               = container
            table.insert(segs, seg)
        end
        table.insert(ringContainers, {axDef=axDef, container=container, segs=segs})

        for dotIdx = 1, 2 do
            local btn = Instance.new("TextButton")
            btn.Size             = UDim2.new(0, DOT_SIZE, 0, DOT_SIZE)
            btn.AnchorPoint      = Vector2.new(0.5, 0.5)
            btn.Position         = UDim2.new(0, -300, 0, -300)
            btn.BackgroundColor3 = axDef.color
            btn.BackgroundTransparency = 0.1
            btn.Text             = ""
            btn.BorderSizePixel  = 0
            btn.ZIndex           = 12
            btn.Visible          = false
            btn.Parent           = screenGui
            uiCorner(btn, 999)
            local stroke = Instance.new("UIStroke")
            stroke.Color       = Color3.fromRGB(255, 255, 255)
            stroke.Transparency = 0.5
            stroke.Thickness   = 1.5
            stroke.Parent      = btn

            local captured = axDef
            btn.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.Touch and
                   input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
                if activeHandle ~= nil then return end
                activeTouchId   = input
                isPressing      = true
                isDragging      = false
                holdTimer       = 0
                lastSteps       = 0
                cachedScreenDir = nil
                cachedAxDef     = captured
                dragStartScreen = Vector2.new(input.Position.X, input.Position.Y)
                activeHandle    = btn
                btn.BackgroundTransparency = 0.0
            end)
            table.insert(handleButtons, {button=btn, axDef=axDef, dotIdx=dotIdx})
        end
    end
end

RunService.RenderStepped:Connect(function(dt)
    if isPressing and not isDragging then
        holdTimer = holdTimer + dt
        if holdTimer >= HOLD_TIME then
            isDragging = true
            lastSteps  = 0
            if selectedBlock and cachedAxDef then
                local cf = getModelCF(selectedBlock)
                if cf then cachedScreenDir = getDragDir(cf, cachedAxDef) end
            end
            if M._multiBlocks then
                buildPreviewMulti(M._multiBlocks)
            else
                buildPreview(selectedBlock)
            end
        end
    end

    if selectedBlock and #ringContainers > 0 then
        local cf  = getModelCF(selectedBlock)
        local sz  = getModelSize(selectedBlock)
        if cf then
            local r   = math.max(sz.X, sz.Y, sz.Z) * 0.5 + 2.8
            local sp0 = camera:WorldToScreenPoint(cf.Position)

            for _, rc in ipairs(ringContainers) do
                local ax = rc.axDef
                if sp0.Z <= 0 then hideRing(rc); continue end
                local n   = #rc.segs
                local pts = {}
                for i = 0, n do
                    local t  = (i / n) * math.pi * 2
                    local wp = cf.Position
                        + ax.ringU * (math.cos(t) * r)
                        + ax.ringV * (math.sin(t) * r)
                    local sp = camera:WorldToScreenPoint(wp)
                    table.insert(pts, {x=sp.X, y=sp.Y, vis=sp.Z > 0})
                end
                local isActive = activeHandle ~= nil and cachedAxDef == ax
                local transp   = isActive and 0.05 or 0.25
                for i = 1, n do
                    local p1  = pts[i]; local p2 = pts[i+1]
                    local seg = rc.segs[i]
                    if not p1.vis or not p2.vis then seg.Visible = false; continue end
                    local midX = (p1.x + p2.x) * 0.5
                    local midY = (p1.y + p2.y) * 0.5
                    local dx   = p2.x - p1.x
                    local dy   = p2.y - p1.y
                    local len  = math.sqrt(dx*dx + dy*dy)
                    seg.Size     = UDim2.new(0, len+1, 0, RING_THICK)
                    seg.Position = UDim2.new(0, midX-(len+1)*0.5, 0, midY-RING_THICK*0.5)
                    seg.Rotation = math.deg(math.atan2(dy, dx))
                    seg.BackgroundColor3 = ax.color
                    seg.BackgroundTransparency = transp
                    seg.Visible = true
                end
            end

            for _, h in ipairs(handleButtons) do
                local ax  = h.axDef
                local dir = h.dotIdx == 1 and ax.dot1 or ax.dot2
                local wp  = cf.Position + dir * r
                local sp, vis = camera:WorldToScreenPoint(wp)
                h.button.Visible = vis and sp.Z > 0
                if h.button.Visible then
                    h.button.Position = UDim2.new(0, sp.X, 0, sp.Y)
                end
            end
        end
    elseif #ringContainers > 0 then
        for _, rc in ipairs(ringContainers) do hideRing(rc) end
    end
end)

UIS.InputChanged:Connect(function(input)
    if not isDragging or not cachedScreenDir or not cachedAxDef then return end
    if activeTouchId and input ~= activeTouchId then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and
       input.UserInputType ~= Enum.UserInputType.Touch then return end
    local cur   = Vector2.new(input.Position.X, input.Position.Y)
    local proj  = (cur - dragStartScreen):Dot(cachedScreenDir)
    local total = math.floor(proj * DRAG_SENS / rotateStep)
    if total ~= lastSteps then
        lastSteps = total
        updatePreview(selectedBlock, cachedAxDef, total)
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch and
       input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if activeTouchId ~= nil and input ~= activeTouchId then return end
    if isDragging and lastSteps ~= 0 then
        commitRotate()
        -- Update livePart positions to match new rotated positions
        if M._multiBlocks and M._multiLiveParts and cachedAxDef then
            local angle = math.rad(rotateStep * lastSteps)
            local rotCF = CFrame.fromAxisAngle(cachedAxDef.rotAxis, angle)
            for _, lpe in ipairs(M._multiLiveParts) do
                local cf = getModelCF(lpe.model)
                if cf and lpe.part and lpe.part.Parent then
                    local pos = cf.Position
                    local newCF = CFrame.new(pos) * rotCF * (cf - pos)
                    lpe.part.CFrame = newCF
                end
            end
        end
    end
    destroyPreview()
    if activeHandle and activeHandle.Parent then
        activeHandle.BackgroundTransparency = 0.1
    end
    isPressing      = false
    isDragging      = false
    holdTimer       = 0
    cachedScreenDir = nil
    lastSteps       = 0
    activeHandle    = nil
    cachedAxDef     = nil
    activeTouchId   = nil
end)

local liveBox  = nil
local livePart = nil

function M.activate(model)
    selectedBlock = model
    if liveBox  then liveBox:Destroy();  liveBox  = nil end
    if livePart then livePart:Destroy(); livePart = nil end
    local cf = getModelCF(model)
    local mfp = model:FindFirstChild("MouseFilterPart")
    local sz  = mfp and mfp.Size or Vector3.new(4.5,4.5,4.5)
    livePart = Instance.new("Part")
    livePart.Size        = sz
    livePart.CFrame      = cf or CFrame.new(0,0,0)
    livePart.Anchored    = true
    livePart.CanCollide  = false
    livePart.Transparency = 1
    livePart.Parent      = workspace
    liveBox = Instance.new("SelectionBox")
    liveBox.Color3        = Color3.fromRGB(255, 100, 160)
    liveBox.LineThickness = 0.06
    liveBox.Adornee       = livePart
    liveBox.Parent        = workspace
    M.onPreviewUpdate = function(newCF, _)
        if livePart and livePart.Parent then
            livePart.CFrame = newCF
        end
    end
    spawnHandles(model)
end

function M.deactivate()
    selectedBlock = nil
    if liveBox  then liveBox:Destroy();  liveBox  = nil end
    if livePart then livePart:Destroy(); livePart = nil end
    if M._multiAnchor and M._multiAnchor.Parent then M._multiAnchor:Destroy() end
    M._multiAnchor = nil
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
    M.deactivate()
    M._multiBlocks = models
    -- Compute center of all models
    local sumPos = Vector3.new(0,0,0)
    for _, m in ipairs(models) do
        local cf = getModelCF(m); if cf then sumPos=sumPos+cf.Position end
    end
    local center = sumPos / #models
    -- Create anchor at center for handle positioning
    local anchor = Instance.new("Part")
    anchor.Size=Vector3.new(4.5,4.5,4.5); anchor.CFrame=CFrame.new(center)
    anchor.Anchored=true; anchor.CanCollide=false; anchor.Transparency=1
    anchor.Parent=workspace
    selectedBlock = anchor
    M._multiAnchor = anchor
    -- Create livePart+liveBox per block
    M._multiLiveParts = {}
    for _, m in ipairs(models) do
        local mfp = m:FindFirstChild("MouseFilterPart")
        local sz = mfp and mfp.Size or Vector3.new(4.5,4.5,4.5)
        local cf = getModelCF(m)
        if cf then
            local lp = Instance.new("Part")
            lp.Size=sz; lp.CFrame=cf
            lp.Anchored=true; lp.CanCollide=false; lp.Transparency=1
            lp.Parent=workspace
            local lb = Instance.new("SelectionBox")
            lb.Color3=Color3.fromRGB(255,100,160); lb.LineThickness=0.06
            lb.Adornee=lp; lb.Parent=workspace
            table.insert(M._multiLiveParts, {part=lp, box=lb, model=m})
        end
    end
    M.onPreviewUpdate = nil
    spawnHandles(anchor)
end

function M.setStep(step)
    -- Rotate uses degrees, not units. Keep default 45 unless explicitly set via setRotateStep
end

function M.setRotateStep(deg)
    rotateStep = deg
end

_G.RotateTool = M
