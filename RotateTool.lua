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
local ClientState

for _, object in ipairs(getgc(true)) do
    if typeof(object) == "table" then
        local ok, gui = pcall(function()
            return rawget(object, "ScreenGui")
        end)

        if ok and gui == BuildGui then
            local hasPlacement = rawget(object, "Placement") ~= nil
            local hasMove = rawget(object, "MoveHandles") ~= nil

            if hasPlacement and hasMove then
                ClientState = object
                break
            end
        end
    end
end

if not ClientState then
    warn("[RotateTool] BuildModeClient state not found")
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
local VERSION = "V1.1"

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

    pcall(function() VersionLabel:Remove() end)

    Handles = {}
    CurrentModel = nil
end

print("[RotateTool] " .. VERSION .. " loaded")
print("[RotateTool] Drag a handle around the block to rotate its local axis")
print("[RotateTool] X = blue | Y = green | Z = red")
