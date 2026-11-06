--==================================================
-- ROTATE TEST
-- Native Build Mode Toolbar Integration
-- Isolated test; does not modify Rotate.lua
--==================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local BuildModeGui = PlayerGui:WaitForChild("BuildModeGui")

local BuildModeFolder = RS:WaitForChild("BuildMode")
local ModesFolder = BuildModeFolder:WaitForChild("Modes")
local IconsFolder = BuildModeFolder:WaitForChild("Resources"):WaitForChild("BuildingModeIcon")
local EventsFolder = BuildModeFolder:WaitForChild("Events")
local ChangedEvent = EventsFolder:WaitForChild("BuildingModeChanged")
local ShowHint = RS:WaitForChild("Events"):WaitForChild("ShowHint")

-- Independent hover raycast and outline modules.
local PlacementLogic = require(BuildModeFolder:WaitForChild("PlacementLogic"))
local BoxSelectionAdornment = require(
    RS:WaitForChild("Packages")
        :WaitForChild("CustomAdornments")
        :WaitForChild("BoxSelectionAdornment")
)

local Env = getgenv()

-- Rotation gizmo uses the Drawing-based handles from RotateTool.lua.
assert(Drawing, "[RotateTest] Drawing API unavailable")
local BuildModel = workspace:WaitForChild("BuildModel")
local Camera = workspace.CurrentCamera
local VERSION = "V1.6"
local HandleRadius = 13
local OutlineRadius = 15

-- Rotation gizmo visuals and interaction, adapted from RotateTool.lua.
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
local RotationRingRadius = 0.55
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
-- The ring plane contains the selected handle axis, so it passes through that axis pair.
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

    local pivot = DragStartPivot
    local selectedAxis = Handles[ActiveHandle].Definition.Axis
    local basisA, basisB

    if selectedAxis == "X" then
        basisA = pivot.RightVector
        basisB = pivot.UpVector
    elseif selectedAxis == "Y" then
        basisA = pivot.UpVector
        basisB = -pivot.LookVector
    else
        basisA = -pivot.LookVector
        basisB = pivot.RightVector
    end

    local center = pivot.Position
    local radius = math.max(HandleDistance, 1)

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
    -- The ring plane contains the selected marker axis. Its normal is
    -- therefore the actual rotation axis for this handle.
    DragAxisWorld = ({
        X = -DragStartPivot.LookVector,
        Y = DragStartPivot.RightVector,
        Z = DragStartPivot.UpVector
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
        local commitMove = RS:FindFirstChild("Functions")
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

local InputChangedConnection = UserInputService.InputChanged:Connect(function(inputObject)
    if ActiveHandle and ActiveInputType == Enum.UserInputType.MouseButton1
        and inputObject.UserInputType == Enum.UserInputType.MouseMovement then
        CurrentPointer = GetScreenPosition(inputObject)
    elseif ActiveHandle and ActiveInputType == Enum.UserInputType.Touch
        and ActiveTouchInput then
        CurrentPointer = GetScreenPosition(ActiveTouchInput)
    end
end)


local function UpdateGizmo()
    if not CurrentModel or not CurrentModel.Parent or not Camera then
        HideHandles()
        HideRotationRing()
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

    for _, handle in ipairs(Handles) do
        local definition = handle.Definition
        local worldPosition = center
            + axes[definition.Axis] * (HandleDistance * definition.Sign)
        local screenPosition, onScreen = Camera:WorldToViewportPoint(worldPosition)
        local visible = onScreen and screenPosition.Z > 0

        handle.Outline.Visible = visible
        handle.Fill.Visible = visible

        if visible then
            local position = Vector2.new(screenPosition.X, screenPosition.Y)
            handle.Outline.Position = position
            handle.Fill.Position = position
        end
    end

    UpdateRotationRing()
end

local function UpdateSelectedModel(selected)
    if typeof(selected) ~= "Instance"
        or not selected:IsDescendantOf(BuildModel) then
        SetModel(nil)
        return
    end

    if selected ~= CurrentModel then
        SetModel(selected)
    end
end

--==================================================
-- ROTATE MODE
-- Independent hover outline only; rotation gizmo remains unimplemented.
--==================================================

local RotateMode = {
    Initialized = false,
    Active = false,
    ClientState = nil,
    Placement = nil,
    Outline = nil,
    Target = nil,
    Handles = Handles,
    RotationRing = RotationRing
}

function RotateMode:Init(clientState)
    self.ClientState = clientState

    self.Placement = PlacementLogic.new()
    self.Outline = BoxSelectionAdornment.new()

    local adornmentParent = BuildModeGui:WaitForChild("Frame"):WaitForChild("Adornment")

    self.Outline:SetParent(adornmentParent)
    self.Outline:SetColor(Color3.fromRGB(170, 85, 255))
    self.Outline:SetThickness(0.03)
    self.Outline:SetAdornee(nil)

    self.Initialized = true
    print("[RotateTest] RotateMode.Init; hover outline ready")
end

function RotateMode:Enter(clientState)
    self.ClientState = clientState or self.ClientState
    self.Active = true
    self.Target = nil

    if self.Outline then
        pcall(function()
            self.Outline:SetAdornee(nil)
        end)
    end

    print("[RotateTest] RotateMode.Enter")
end

function RotateMode:Exit()
    if IsDragging then
        FinishDrag()
    end
    SetActiveHandle(nil)
    ActiveInputType = nil
    ActiveTouchInput = nil
    CurrentPointer = nil
    SetModel(nil)
    HideHandles()
    HideRotationRing()

    self.Active = false
    self.Target = nil

    if self.Outline then
        pcall(function()
            self.Outline:SetAdornee(nil)
        end)
    end

    if self.ClientState then
        pcall(function()
            self.ClientState.BoxSelection:SetAdornee(nil)
            self.ClientState.BoxSelection:SetColor(Color3.new(0, 0, 1))
            self.ClientState.MoveHandles:SetAdornee(nil)
            self.ClientState.SelectedBlock = nil
        end)
    end

    print("[RotateTest] RotateMode.Exit")
end

function RotateMode:Update(dt, clientState)
    if not self.Active or not self.Placement or not self.Outline then
        return
    end

    self.ClientState = clientState or self.ClientState

    local state = self.ClientState
    local boxSelection = state and state.BoxSelection
    if not state or not boxSelection then
        return
    end

    -- RenderLoop clears BoxSelection before every mode Update.
    -- Re-apply the selected outline here, after that clear.
    local selected = state.SelectedBlock
    if selected and selected.Parent then
        boxSelection:SetColor(Color3.fromRGB(170, 85, 255))
        boxSelection:SetAdornee(selected)
        self.Outline:SetAdornee(nil)
        self.Target = nil

        UpdateSelectedModel(selected)
        if ActiveHandle and ActiveInputType == Enum.UserInputType.Touch and ActiveTouchInput then
            CurrentPointer = GetScreenPosition(ActiveTouchInput)
        end
        if IsDragging and CurrentPointer then
            ApplyDrag(CurrentPointer)
        end
        UpdateGizmo()
        return
    end

    if IsDragging then
        FinishDrag()
        SetActiveHandle(nil)
        ActiveInputType = nil
        ActiveTouchInput = nil
        CurrentPointer = nil
    end
    SetModel(nil)
    HideRotationRing()
    boxSelection:SetAdornee(nil)

    local raycastOk, result = pcall(function()
        return self.Placement:Raycast()
    end)

    local block = nil

    if raycastOk and result and result.Instance then
        local candidate = result.Instance.Parent
        local buildModel = workspace:FindFirstChild("BuildModel")

        if candidate
            and candidate:IsA("Model")
            and buildModel
            and candidate.Parent == buildModel then
            block = candidate
        end
    end

    if block ~= self.Target then
        self.Target = block

        local outlineOk, outlineError = pcall(function()
            self.Outline:SetAdornee(block)
        end)

        if not outlineOk then
            warn("[RotateTest] Hover outline error:", outlineError)
        else
            print(
                "[RotateTest] Hover target:",
                block and block:GetFullName() or "nil"
            )
        end
    end
end

function RotateMode:Action(clientState)
    if not self.Active then
        return Enum.ContextActionResult.Sink
    end

    self.ClientState = clientState or self.ClientState

    local state = self.ClientState
    if not state or not self.Placement then
        return Enum.ContextActionResult.Sink
    end

    local raycastOk, result = pcall(function()
        return self.Placement:Raycast()
    end)

    if not raycastOk or not result or not result.Instance then
        state.SelectedBlock = nil
        print("[RotateTest] Selection cleared: raycast miss")
        return Enum.ContextActionResult.Sink
    end

    local block = result.Instance.Parent
    local buildModel = workspace:FindFirstChild("BuildModel")

    if not block or not buildModel or block.Parent ~= buildModel then
        print("[RotateTest] Ignored target outside BuildModel")
        return Enum.ContextActionResult.Sink
    end

    if state.SelectedBlock == block then
        state.SelectedBlock = nil
        print("[RotateTest] Deselected:", block:GetFullName())
    else
        state.SelectedBlock = block
        print("[RotateTest] Selected:", block:GetFullName())
    end

    return Enum.ContextActionResult.Sink
end

function RotateMode:Destroy()
    if IsDragging then
        FinishDrag()
    end
    CAS:UnbindAction(CaptureActionName)
    if InputChangedConnection then
        InputChangedConnection:Disconnect()
        InputChangedConnection = nil
    end
    HideHandles()
    HideRotationRing()
    for _, handle in ipairs(Handles) do
        pcall(function() handle.Outline:Remove() end)
        pcall(function() handle.Fill:Remove() end)
    end
    for _, line in ipairs(RotationRing) do
        pcall(function() line:Remove() end)
    end
    pcall(function() VersionLabel:Remove() end)

    self.Active = false
    self.Target = nil

    if self.Outline then
        pcall(function()
            self.Outline:Destroy()
        end)
        self.Outline = nil
    end

    self.Placement = nil
    self.Initialized = false
end

local PreviousRenderMode = rawget(RenderModes, "Rotate")
RenderModes.Rotate = RotateMode
RotateMode:Init(ClientState)

CAS:BindActionAtPriority(
    CaptureActionName,
    CaptureInput,
    false,
    3000,
    Enum.UserInputType.MouseButton1,
    Enum.UserInputType.Touch
)

--==================================================
-- ROUTE THE MAIN PLACE-BLOCK BUTTON TO ROTATE
-- Preserve the original dispatcher for every native mode.
--==================================================

local OriginalPlaceBlockAction = ClientState.PlaceBlockAction
assert(
    type(OriginalPlaceBlockAction) == "function",
    "[RotateTest] ClientState.PlaceBlockAction missing"
)

local function RotatePlaceBlockAction(self, ...)
    local currentMode = BuildingMode:Get()

    if currentMode and currentMode.Name == "Rotate" then
        return RotateMode:Action(self, ...)
    end

    return OriginalPlaceBlockAction(self, ...)
end

ClientState.PlaceBlockAction = RotatePlaceBlockAction

--==================================================
-- FIND NATIVE TOOLBAR
--==================================================

local Toolbar = ClientState.Toolbar
local BuildingToolbar = Toolbar and Toolbar.BuildingModeToolbar

assert(BuildingToolbar, "[RotateTest] BuildingModeToolbar not found")

local Frame = BuildingToolbar.Instance
local Slots = BuildingToolbar.Slots

assert(Frame and Slots, "[RotateTest] Toolbar structure invalid")
assert(Slots[6] and Slots[6].Instance, "[RotateTest] Move button not found")

--==================================================
-- CREATE ROTATE BUTTON
--==================================================

local Button = Slots[6].Instance:Clone()
Button.Name = "RotateButton"
Button.LayoutOrder = 7
Button.Position = UDim2.fromOffset(444, 0)

local ButtonIcon = Button:FindFirstChild("Move")
if ButtonIcon then
    ButtonIcon.Name = "Rotate"
end

local OriginalFrameSize = Frame.Size
local OriginalSlot7 = Slots[7]

Button.Parent = Frame
Frame.Size = UDim2.fromOffset(524, 80)

Slots[7] = {
    Instance = Button
}

--==================================================
-- CONNECTIONS / NATIVE SELECTION BEHAVIOR
--==================================================

local Connections = {}

local function Connect(connection)
    table.insert(Connections, connection)
    return connection
end

local SelectedModeName = "rotate tool"

Connect(Button.Activated:Connect(function()
    print("[RotateTest] Rotate button pressed")

    -- Match the native toolbar button's feedback.
    ShowHint:Fire(string.format("Selected %s", SelectedModeName))

    -- Select the custom enum mode.
    BuildingMode:SetMode(RotateEnum)

    -- Match the native toolbar button's close/cleanup behavior.
    Frame.Visible = false
    CAS:UnbindAction("pick_building_mode")

    if type(BuildingToolbar.HideInputIcons) == "function" then
        BuildingToolbar:HideInputIcons()
    end

    print("[RotateTest] Rotate selected")
end))

Connect(ChangedEvent.Event:Connect(function(modeName)
    if modeName == "Rotate" then
        print("[RotateTest] BuildingModeChanged: Rotate")
        if not RotateMode.Active then
            RotateMode:Enter(ClientState)
        end

        -- BuildModeClient has no native title for the custom enum item.
        -- Defer until its listener has attempted the native SetTitle call.
        task.defer(function()
            if not Cleaned and BuildingMode:Get() == RotateEnum then
                local ok, err = pcall(function()
                    CAS:SetTitle("place_block", "Rotate")
                end)
                if not ok then
                    warn("[RotateTest] Could not set main button title:", err)
                end
            end
        end)
    elseif RotateMode.Active then
        print("[RotateTest] Another mode selected:", modeName)
        RotateMode:Exit()
    end
end))

--==================================================
-- CLEANUP
--==================================================

local Cleaned = false

local function Cleanup()
    if Cleaned then
        return
    end

    Cleaned = true

    for _, connection in ipairs(Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(Connections)

    if RotateMode.Active then
        pcall(function()
            RotateMode:Exit(ClientState)
        end)
    end

    pcall(function()
        RotateMode:Destroy()
    end)

    if BuildingMode:Get() == RotateEnum then
        pcall(function()
            BuildingMode:SetMode(Enumeration.BuildingMode.None)
        end)
    end

    if rawget(RenderModes, "Rotate") == RotateMode then
        RenderModes.Rotate = PreviousRenderMode
    end

    if ClientState.PlaceBlockAction == RotatePlaceBlockAction then
        ClientState.PlaceBlockAction = OriginalPlaceBlockAction
    end

    if Slots[7] and Slots[7].Instance == Button then
        Slots[7] = OriginalSlot7
    end

    pcall(function()
        Button:Destroy()
    end)

    pcall(function()
        Frame.Size = OriginalFrameSize
    end)

    if CreatedEnum and rawget(EnumItems, "Rotate") == RotateEnum then
        rawset(EnumItems, "Rotate", nil)

        for index, item in ipairs(EnumOrdered) do
            if item == RotateEnum then
                table.remove(EnumOrdered, index)
                break
            end
        end
    end

    if CreatedIcon and RotateIcon and RotateIcon.Parent then
        RotateIcon:Destroy()
    end

    print("[RotateTest] Cleanup complete")
end

--==================================================
-- GLOBAL REFERENCES
--==================================================

Env.RotateTestCleanup = Cleanup
Env.RotateTestMode = RotateMode
Env.RotateTestEnum = RotateEnum

print("================================")
print("[RotateTest] Loaded")
print("[RotateTest] Enum: OK")
print("[RotateTest] Icon: OK")
print("[RotateTest] RenderLoop: OK")
print("[RotateTest] Toolbar button: OK")
print("[RotateTest] Hover outline: READY")
print("[RotateTest] Main action dispatch: OK")
print("[RotateTest] Title listener: READY")
print("[RotateTest] Click Rotate to test")
print("================================")
