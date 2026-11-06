--[[
    RotateTool.lua
    JustUser-ALT/PBM
    Visual prototype 2 — six local-axis rotation handles.

    Test scope:
    - Reads the currently selected Build Mode block.
    - Draws six colored circular handles around its pivot:
      X = blue (left/right), Y = green (up/down), Z = red (front/back).
    - Handles follow the block's local orientation.
    - Does not rotate blocks or change Build Mode.
    - Does not create or modify game UI.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VERSION = "V1.3"

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local BuildGui = PlayerGui:WaitForChild("BuildModeGui")
local BuildModel = workspace:WaitForChild("BuildModel")

-- Clean up a previous run.
if getgenv().RotateVisualCleanup then
    pcall(getgenv().RotateVisualCleanup)
end

if not Drawing then
    warn("[RotateTool] Drawing API unavailable")
    return
end

-- Find the live BuildModeClient state.
-- Only ScreenGui identity is required; Placement/MoveHandles are not used here.
local ClientState
local StateCandidates = {}
local GuiTables = {}

for _, object in ipairs(getgc(true)) do
    if typeof(object) == "table" then
        local ok, gui = pcall(function()
            return rawget(object, "ScreenGui")
        end)

        if ok and gui ~= nil then
            table.insert(GuiTables, {Object = object, Gui = gui})
            if gui == BuildGui then
                table.insert(StateCandidates, object)
            end
        end
    end
end

if #StateCandidates > 0 then
    local bestScore = -1

    for _, candidate in ipairs(StateCandidates) do
        local score = 0
        if rawget(candidate, "SelectedBlock") ~= nil then score = score + 4 end
        if rawget(candidate, "Placement") ~= nil then score = score + 1 end
        if rawget(candidate, "MoveHandles") ~= nil then score = score + 1 end

        if score > bestScore then
            bestScore = score
            ClientState = candidate
        end
    end

    print("[RotateTool] BuildModeClient candidates: " .. tostring(#StateCandidates))
    if #StateCandidates > 1 then
        for index, candidate in ipairs(StateCandidates) do
            local keys = {}
            for key in pairs(candidate) do
                if #keys >= 20 then
                    table.insert(keys, "...")
                    break
                end
                table.insert(keys, tostring(key))
            end
            print("[RotateTool] Candidate " .. tostring(index) .. " keys: " .. table.concat(keys, ", "))
        end
    end
else
    warn("[RotateTool] Exact BuildModeGui state not found. Tables containing ScreenGui:")
    for index, entry in ipairs(GuiTables) do
        if index > 12 then
            warn("[RotateTool] Additional ScreenGui tables omitted")
            break
        end

        local gui = entry.Gui
        local description = tostring(gui)
        pcall(function()
            description = gui:GetFullName()
        end)
        warn("[RotateTool] ScreenGui table " .. tostring(index) .. ": " .. description)
    end
end

if not ClientState then
    warn("[RotateTool] BuildModeClient state not found; cannot read SelectedBlock")
    return
end

local Camera = workspace.CurrentCamera
local HandleRadius = 13
local OutlineRadius = 15
local HandleDistance = 0
local CurrentModel

-- Axis colors: X blue, Y green, Z red.
local AxisColors = {
    X = Color3.fromRGB(65, 155, 255),
    Y = Color3.fromRGB(75, 235, 115),
    Z = Color3.fromRGB(255, 75, 75)
}

local HandleDefinitions = {
    {Name = "Right", Axis = "X", Sign = 1},
    {Name = "Left", Axis = "X", Sign = -1},
    {Name = "Top", Axis = "Y", Sign = 1},
    {Name = "Bottom", Axis = "Y", Sign = -1},
    {Name = "Front", Axis = "Z", Sign = -1},
    {Name = "Back", Axis = "Z", Sign = 1}
}

local VersionLabel = Drawing.new("Text")
VersionLabel.Text = VERSION
VersionLabel.Size = 16
VersionLabel.Position = Vector2.new(12, 12)
VersionLabel.Color = Color3.fromRGB(255, 255, 255)
VersionLabel.Outline = true
VersionLabel.Center = false
VersionLabel.Visible = true
pcall(function() VersionLabel.ZIndex = 100 end)

local Handles = {}
local ActiveHandle
local ActiveInputType
local ActiveTouchInput
local IsDragging = false
local DragStartPivot
local DragAxisWorld
local DragCenterScreen
local LastPointerAngle
local TotalDragAngle = 0
local CurrentPointer
local CaptureActionName = "JustX_RotateHandleCapture"
local HitRadius = 26
local RotationRingSegments = 48
local RotationRingRadius = 0.9
local RotationRing = {}

for index, definition in ipairs(HandleDefinitions) do
    local outline = Drawing.new("Circle")
    outline.Color = Color3.fromRGB(15, 18, 24)
    outline.Thickness = 2
    outline.NumSides = 24
    outline.Radius = OutlineRadius
    outline.Filled = true
    outline.Transparency = 1
    outline.Visible = false

    local fill = Drawing.new("Circle")
    fill.Color = AxisColors[definition.Axis]
    fill.Thickness = 1
    fill.NumSides = 24
    fill.Radius = HandleRadius
    fill.Filled = true
    fill.Transparency = 1
    fill.Visible = false

    Handles[index] = {
        Definition = definition,
        Outline = outline,
        Fill = fill
    }
end

-- A single projected 3D ring is shown only while a handle is held.
for index = 1, RotationRingSegments do
    local line = Drawing.new("Line")
    line.Color = Color3.new(1, 1, 1)
    line.Thickness = 2
    line.Transparency = 1
    line.Visible = false
    pcall(function() line.ZIndex = 90 end)
    RotationRing[index] = line
end

local function HideRotationRing()
    for _, line in ipairs(RotationRing) do
        line.Visible = false
    end
end

local function UpdateRotationRing()
    if not IsDragging or not DragStartPivot or not DragAxisWorld or not Camera then
        HideRotationRing()
        return
    end

    local axis = DragAxisWorld.Unit
    local reference = math.abs(axis:Dot(Vector3.new(0, 1, 0))) > 0.95
        and Vector3.new(1, 0, 0)
        or Vector3.new(0, 1, 0)
    local basisA = axis:Cross(reference).Unit
    local basisB = axis:Cross(basisA).Unit
    local center = DragStartPivot.Position
    local radius = math.max(HandleDistance * RotationRingRadius, 1)

    local projected = {}
    for index = 1, RotationRingSegments do
        local angle = ((index - 1) / RotationRingSegments) * math.pi * 2
        local worldPoint = center
            + basisA * (math.cos(angle) * radius)
            + basisB * (math.sin(angle) * radius)
        local screenPoint = Camera:WorldToViewportPoint(worldPoint)
        projected[index] = {
            Position = Vector2.new(screenPoint.X, screenPoint.Y),
            Visible = screenPoint.Z > 0
        }
    end

    local ringColor = AxisColors[Handles[ActiveHandle].Definition.Axis]
    for index, line in ipairs(RotationRing) do
        local nextIndex = index % RotationRingSegments + 1
        local first = projected[index]
        local second = projected[nextIndex]

        line.Color = ringColor
        line.From = first.Position
        line.To = second.Position
        line.Visible = first.Visible and second.Visible
    end
end

local function HideHandles()
    for _, handle in ipairs(Handles) do
        handle.Outline.Visible = false
        handle.Fill.Visible = false
    end
end

local function GetModelSize(model)
    if model:IsA("Model") then
        return model:GetExtentsSize()
    elseif model:IsA("BasePart") then
        return model.Size
    end

    return Vector3.new(4, 4, 4)
end

local function SetModel(model)
    CurrentModel = model

    if not model then
        HandleDistance = 0
        HideHandles()
        return
    end

    local size = GetModelSize(model)
    HandleDistance = math.max(size.X, size.Y, size.Z) * 0.65 + 0.5
end


local function GetScreenPosition(inputObject)
    -- Touch positions are offset relative to Drawing viewport coordinates
    -- on this client. Add the top-left GUI inset to align the coordinate spaces.
    local position = inputObject.Position
    local inset = GuiService:GetGuiInset()
    return Vector2.new(position.X + inset.X, position.Y + inset.Y)
end

local function FindHandleAt(position)
    local closestIndex
    local closestDistance = HitRadius

    for index, handle in ipairs(Handles) do
        if handle.Fill.Visible then
            local distance = (handle.Fill.Position - position).Magnitude
            if distance <= closestDistance then
                closestDistance = distance
                closestIndex = index
            end
        end
    end

    return closestIndex
end

local function GetPointerAngle(position, center)
    local offset = position - center
    return math.atan2(offset.Y, offset.X)
end

local function ApplyDrag(position)
    if not IsDragging or not DragStartPivot or not DragAxisWorld or not DragCenterScreen then
        return
    end

    local angle = GetPointerAngle(position, DragCenterScreen)
    local delta = angle - LastPointerAngle

    if delta > math.pi then
        delta = delta - math.pi * 2
    elseif delta < -math.pi then
        delta = delta + math.pi * 2
    end

    LastPointerAngle = angle
    TotalDragAngle = TotalDragAngle - delta

    local rotation = CFrame.fromAxisAngle(DragAxisWorld, TotalDragAngle)
    local pivotPosition = DragStartPivot.Position
    CurrentModel:PivotTo(
        CFrame.new(pivotPosition)
        * rotation
        * CFrame.new(-pivotPosition)
        * DragStartPivot
    )
end

local function BeginDrag(handleIndex, position)
    local definition = Handles[handleIndex].Definition
    DragStartPivot = CurrentModel:GetPivot()
    DragAxisWorld = ({
        X = DragStartPivot.RightVector,
        Y = DragStartPivot.UpVector,
        Z = -DragStartPivot.LookVector
    })[definition.Axis]

    local center, onScreen = Camera:WorldToViewportPoint(DragStartPivot.Position)
    if not onScreen or center.Z <= 0 then
        DragStartPivot = nil
        DragAxisWorld = nil
        return false
    end

    DragCenterScreen = Vector2.new(center.X, center.Y)
    LastPointerAngle = GetPointerAngle(position, DragCenterScreen)
    TotalDragAngle = 0
    IsDragging = true
    UpdateRotationRing()
    return true
end

local function FinishDrag()
    if IsDragging and CurrentModel and CurrentModel.Parent then
        local commitMove = ReplicatedStorage:FindFirstChild("Functions")
            and ReplicatedStorage.Functions:FindFirstChild("CommitMove")

        if commitMove then
            local ok, err = pcall(function()
                commitMove:InvokeServer(CurrentModel, CurrentModel:GetPivot())
            end)
            if not ok then
                warn("[RotateTool] CommitMove failed: " .. tostring(err))
            end
        else
            warn("[RotateTool] ReplicatedStorage.Functions.CommitMove not found")
        end
    end

    IsDragging = false
    HideRotationRing()
    DragStartPivot = nil
    DragAxisWorld = nil
    DragCenterScreen = nil
    LastPointerAngle = nil
    TotalDragAngle = 0
end

local function SetActiveHandle(index)
    ActiveHandle = index

    for handleIndex, handle in ipairs(Handles) do
        local active = handleIndex == index

        handle.Fill.Radius = active and 18 or HandleRadius
        handle.Outline.Radius = active and 21 or OutlineRadius
        handle.Fill.Color = active and Color3.new(1, 1, 1) or AxisColors[handle.Definition.Axis]
        handle.Outline.Color = active and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(15, 18, 24)
        handle.Fill.Thickness = active and 3 or 1
        handle.Outline.Thickness = active and 3 or 2
    end
end

local function CaptureInput(_, inputState, inputObject)
    local inputType = inputObject.UserInputType

    if inputState == Enum.UserInputState.Begin then
        if inputType ~= Enum.UserInputType.MouseButton1
            and inputType ~= Enum.UserInputType.Touch then
            return Enum.ContextActionResult.Pass
        end

        local pointer = GetScreenPosition(inputObject)
        local handleIndex = FindHandleAt(pointer)

        if not handleIndex then
            return Enum.ContextActionResult.Pass
        end

        ActiveInputType = inputType
        ActiveTouchInput = inputType == Enum.UserInputType.Touch and inputObject or nil
        CurrentPointer = pointer
        SetActiveHandle(handleIndex)
        if not BeginDrag(handleIndex, pointer) then
            SetActiveHandle(nil)
            ActiveInputType = nil
            ActiveTouchInput = nil
            return Enum.ContextActionResult.Pass
        end

        return Enum.ContextActionResult.Sink
    end

    if ActiveHandle then
        if inputType == ActiveInputType then
            if inputType == Enum.UserInputType.Touch
                and ActiveTouchInput
                and inputObject ~= ActiveTouchInput then
                return Enum.ContextActionResult.Pass
            end

            if inputState == Enum.UserInputState.Change then
                if inputType == Enum.UserInputType.Touch then
                    CurrentPointer = GetScreenPosition(inputObject)
                end
                return Enum.ContextActionResult.Sink
            end

            if inputState == Enum.UserInputState.End
                or inputState == Enum.UserInputState.Cancel then
                FinishDrag()
                SetActiveHandle(nil)
                ActiveInputType = nil
                ActiveTouchInput = nil
                CurrentPointer = nil
            end

            return Enum.ContextActionResult.Sink
        end
    end

    return Enum.ContextActionResult.Pass
end

ContextActionService:BindActionAtPriority(
    CaptureActionName,
    CaptureInput,
    false,
    3000,
    Enum.UserInputType.MouseButton1,
    Enum.UserInputType.Touch
)

local InputChangedConnection = UserInputService.InputChanged:Connect(function(inputObject)
    if ActiveHandle and ActiveInputType == Enum.UserInputType.MouseButton1
        and inputObject.UserInputType == Enum.UserInputType.MouseMovement then
        CurrentPointer = GetScreenPosition(inputObject)
    elseif ActiveHandle and ActiveInputType == Enum.UserInputType.Touch
        and ActiveTouchInput then
        CurrentPointer = GetScreenPosition(ActiveTouchInput)
    end
end)

local Connection

Connection = RunService.RenderStepped:Connect(function()
    if ActiveHandle and ActiveInputType == Enum.UserInputType.Touch and ActiveTouchInput then
        CurrentPointer = GetScreenPosition(ActiveTouchInput)
    end

    if IsDragging and CurrentPointer then
        ApplyDrag(CurrentPointer)
    end
    UpdateRotationRing()
    if not ClientState or not BuildModel.Parent then
        HideHandles()
        return
    end

    local selected = ClientState.SelectedBlock

    if typeof(selected) ~= "Instance"
        or not selected:IsDescendantOf(BuildModel) then
        if CurrentModel then
            SetModel(nil)
        else
            HideHandles()
        end
        return
    end

    if selected ~= CurrentModel then
        SetModel(selected)
    end

    if not CurrentModel or not CurrentModel.Parent then
        SetModel(nil)
        return
    end

    Camera = workspace.CurrentCamera
    if not Camera then
        HideHandles()
        return
    end

    local pivot = CurrentModel:GetPivot()
    local center = pivot.Position
    local axes = {
        X = pivot.RightVector,
        Y = pivot.UpVector,
        Z = -pivot.LookVector
    }

    for index, handle in ipairs(Handles) do
        local definition = handle.Definition
        local worldPosition = center
            + axes[definition.Axis] * (HandleDistance * definition.Sign)

        local screenPosition, onScreen =
            Camera:WorldToViewportPoint(worldPosition)

        local visible = onScreen and screenPosition.Z > 0

        handle.Outline.Visible = visible
        handle.Fill.Visible = visible

        if visible then
            local position = Vector2.new(screenPosition.X, screenPosition.Y)
            handle.Outline.Position = position
            handle.Fill.Position = position
        end
    end
end)

getgenv().RotateVisualCleanup = function()
    if Connection then
        Connection:Disconnect()
        Connection = nil
    end
    if InputChangedConnection then
        InputChangedConnection:Disconnect()
        InputChangedConnection = nil
    end

    FinishDrag()
    ContextActionService:UnbindAction(CaptureActionName)
    ActiveHandle = nil
    ActiveInputType = nil
    ActiveTouchInput = nil

    for _, handle in ipairs(Handles) do
        pcall(function() handle.Outline:Remove() end)
        pcall(function() handle.Fill:Remove() end)
    end
    for _, line in ipairs(RotationRing) do
        pcall(function() line:Remove() end)
    end

    pcall(function() VersionLabel:Remove() end)

    Handles = {}
    CurrentModel = nil
end

print("[RotateTool] " .. VERSION .. " loaded")
print("[RotateTool] Hold a handle to show its rotation-axis ring")
print("[RotateTool] Drag a handle around the block to rotate its local axis")
print("[RotateTool] X = blue | Y = green | Z = red")
