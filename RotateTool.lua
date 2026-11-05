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
local HandleRadius = 11
local OutlineRadius = 13
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

local Handles = {}
local ActiveHandle
local ActiveInputType
local ActiveTouchInput
local CaptureActionName = "JustX_RotateHandleCapture"
local HitRadius = 23

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
    local position = inputObject.Position
    local inset = GuiService:GetGuiInset()
    return Vector2.new(position.X - inset.X, position.Y - inset.Y)
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

local function SetActiveHandle(index)
    ActiveHandle = index

    for handleIndex, handle in ipairs(Handles) do
        local active = handleIndex == index

        handle.Fill.Radius = active and 16 or HandleRadius
        handle.Outline.Radius = active and 19 or OutlineRadius
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

        local handleIndex = FindHandleAt(GetScreenPosition(inputObject))

        if not handleIndex then
            return Enum.ContextActionResult.Pass
        end

        ActiveInputType = inputType
        ActiveTouchInput = inputType == Enum.UserInputType.Touch and inputObject or nil
        SetActiveHandle(handleIndex)

        return Enum.ContextActionResult.Sink
    end

    if ActiveHandle then
        if inputType == ActiveInputType then
            if inputType == Enum.UserInputType.Touch
                and ActiveTouchInput
                and inputObject ~= ActiveTouchInput then
                return Enum.ContextActionResult.Pass
            end

            if inputState == Enum.UserInputState.End
                or inputState == Enum.UserInputState.Cancel then
                SetActiveHandle(nil)
                ActiveInputType = nil
                ActiveTouchInput = nil
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

local Connection

Connection = RunService.RenderStepped:Connect(function()
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

    ContextActionService:UnbindAction(CaptureActionName)
    ActiveHandle = nil
    ActiveInputType = nil
    ActiveTouchInput = nil

    for _, handle in ipairs(Handles) do
        pcall(function() handle.Outline:Remove() end)
        pcall(function() handle.Fill:Remove() end)
    end

    Handles = {}
    CurrentModel = nil
end

print("[RotateTool] Six-handle visual prototype loaded")
print("[RotateTool] X = blue | Y = green | Z = red")
print("[RotateTool] Select a block using Move or Resize")
