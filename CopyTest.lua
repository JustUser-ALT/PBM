--==================================================
-- COPY TEST
-- Native Build Mode Toolbar Integration
-- Isolated test; does not modify native Move / Resize tools.
--==================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UIS = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local BuildModeGui = PlayerGui:WaitForChild("BuildModeGui")
local BuildModel = workspace:WaitForChild("BuildModel")

local BuildModeFolder = RS:WaitForChild("BuildMode")
local ModesFolder = BuildModeFolder:WaitForChild("Modes")
local IconsFolder = BuildModeFolder:WaitForChild("Resources"):WaitForChild("BuildingModeIcon")
local EventsFolder = BuildModeFolder:WaitForChild("Events")
local ChangedEvent = EventsFolder:WaitForChild("BuildingModeChanged")
local ShowHint = RS:WaitForChild("Events"):WaitForChild("ShowHint")
local Functions = RS:WaitForChild("Functions")
local PlaceBlock = Functions:WaitForChild("PlaceBlock")
local CommitMove = Functions:WaitForChild("CommitMove")
local CommitResize = Functions:WaitForChild("CommitResize")

local PlacementLogic = require(BuildModeFolder:WaitForChild("PlacementLogic"))
local BoxSelectionAdornment = require(
    RS:WaitForChild("Packages")
        :WaitForChild("CustomAdornments")
        :WaitForChild("BoxSelectionAdornment")
)

local Env = getgenv()
if type(Env.CopyTestCleanup) == "function" then
    pcall(Env.CopyTestCleanup)
end

--==================================================
-- FIND CLIENT STATE
--==================================================

local ClientState
for attempt = 1, 100 do
    for _, object in ipairs(getgc(true)) do
        if type(object) == "table"
            and rawget(object, "ScreenGui") == BuildModeGui
            and rawget(object, "Toolbar") then
            ClientState = object
            break
        end
    end
    if ClientState then break end
    task.wait(0.1)
end
assert(ClientState, "[CopyTest] ClientState not found")

--==================================================
-- BUILDING MODE ENUM
--==================================================

local BuildingMode = require(BuildModeFolder:WaitForChild("BuildingMode"))
local Enumeration = require(BuildModeFolder:WaitForChild("Common"):WaitForChild("Enumeration"))
local BuildingModeEnum = Enumeration.BuildingMode
local EnumItems = rawget(BuildingModeEnum, "__items")
local EnumOrdered = rawget(BuildingModeEnum, "__ordered")
assert(type(EnumItems) == "table" and type(EnumOrdered) == "table", "[CopyTest] Enum registry missing")

local CopyEnum = rawget(EnumItems, "Copy")
local CreatedEnum = false
if not CopyEnum then
    CopyEnum = {
        Name = "Copy",
        Value = 10,
        EnumerationType = "BuildingMode"
    }
    setmetatable(CopyEnum, {
        __tostring = function(self)
            return string.format("Enumeration.%s.%s", self.EnumerationType, self.Name)
        end
    })
    rawset(EnumItems, "Copy", CopyEnum)
    table.insert(EnumOrdered, CopyEnum)
    CreatedEnum = true
end

--==================================================
-- RENDER MODES
--==================================================

local RenderModes
for _, connection in ipairs(getconnections(RunService.RenderStepped)) do
    local fn = connection.Function
    if type(fn) == "function" then
        local ok, upvalues = pcall(debug.getupvalues, fn)
        if ok and type(upvalues) == "table" then
            for _, value in pairs(upvalues) do
                if type(value) == "table"
                    and rawget(value, "Move")
                    and rawget(value, "Resize")
                    and rawget(value, "Select")
                    and rawget(value, "ColorPick") then
                    RenderModes = value
                    break
                end
            end
        end
    end
    if RenderModes then break end
end
assert(RenderModes, "[CopyTest] RenderLoop modes table not found")

--==================================================
-- ICON / TOOLBAR
--==================================================

local CopyIcon = IconsFolder:FindFirstChild("Copy")
local CreatedIcon = false
if not CopyIcon then
    CopyIcon = IconsFolder:WaitForChild("Move"):Clone()
    CopyIcon.Name = "Copy"
    CopyIcon.Parent = IconsFolder
    CreatedIcon = true
end

local Toolbar = ClientState.Toolbar
local BuildingToolbar = Toolbar and Toolbar.BuildingModeToolbar
assert(BuildingToolbar, "[CopyTest] BuildingModeToolbar not found")
local Frame = BuildingToolbar.Instance
local Slots = BuildingToolbar.Slots
assert(Frame and Slots and Slots[6] and Slots[6].Instance, "[CopyTest] Toolbar structure invalid")

local Button = Slots[6].Instance:Clone()
Button.Name = "CopyButton"
Button.LayoutOrder = 7
Button.Position = UDim2.fromOffset(444, 0)
local ButtonIcon = Button:FindFirstChild("Move")
if ButtonIcon then ButtonIcon.Name = "Copy" end

local OriginalFrameSize = Frame.Size
local OriginalSlot7 = Slots[7]
Button.Parent = Frame
Frame.Size = UDim2.fromOffset(524, 80)
Slots[7] = { Instance = Button }

--==================================================
-- COPY MODE STATE / VISUALS
--==================================================

local GOLD = Color3.fromRGB(232, 190, 75)
local DARK_GOLD = Color3.fromRGB(135, 99, 32)
local Camera = workspace.CurrentCamera
local Cleaned = false
local Connections = {}
local CaptureActionName = "JustX_CopyHandleCapture"

local CopyMode = {
    Initialized = false,
    Active = false,
    ClientState = ClientState,
    Placement = nil,
    Outline = nil,
    Target = nil,
    CopiedBlock = nil,
    Moving = false
}

local function GetModelRef(model)
    if not model then return nil end
    return model:FindFirstChild("ColorPart")
        or model:FindFirstChild("MouseFilterPart")
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function FindTemplate(name)
    if Env.CPT_Utils and type(Env.CPT_Utils.findBlockInRS) == "function" then
        local ok, result = pcall(Env.CPT_Utils.findBlockInRS, name)
        if ok and result then return result end
    end

    local categories = {"Basic", "Decoration", "Events", "Items", "Lights", "Links"}
    local blocks = RS:FindFirstChild("Blocks")
    if blocks then
        for _, category in ipairs(categories) do
            local folder = blocks:FindFirstChild(category)
            local item = folder and folder:FindFirstChild(name)
            if item then return item:FindFirstChild(name) or item end
        end
    end

    local npcs = RS:FindFirstChild("BlocksCutscene")
    npcs = npcs and npcs:FindFirstChild("NPCs")
    local npc = npcs and npcs:FindFirstChild(name)
    if npc then return npc:FindFirstChild(name) or npc end
    return nil
end

local function GetScreenPosition(inputObject)
    local position = inputObject.Position
    local inset = GuiService:GetGuiInset()
    return Vector2.new(position.X + inset.X, position.Y + inset.Y)
end

local Handles = {}
local HandleDefinitions = {
    {Axis = "X", Sign = 1}, {Axis = "X", Sign = -1},
    {Axis = "Y", Sign = 1}, {Axis = "Y", Sign = -1},
    {Axis = "Z", Sign = 1}, {Axis = "Z", Sign = -1}
}

local MoveStep = 0.1
local StepGui = Instance.new("ScreenGui")
StepGui.Name = "JustXCopyStepSettings"
StepGui.ResetOnSpawn = false
StepGui.IgnoreGuiInset = true
StepGui.DisplayOrder = 10000

local StepInput = Instance.new("TextBox")
StepInput.Name = "StepInput"
StepInput.Size = UDim2.fromOffset(55, 25)
StepInput.Position = UDim2.new(1, -65, 0.52, 0)
StepInput.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
StepInput.BorderSizePixel = 0
StepInput.TextColor3 = Color3.new(1, 1, 1)
StepInput.Text = "0.1"
StepInput.PlaceholderText = "0.1"
StepInput.Font = Enum.Font.Gotham
StepInput.TextSize = 12
StepInput.ClearTextOnFocus = false
StepInput.Parent = StepGui

local StepCorner = Instance.new("UICorner")
StepCorner.CornerRadius = UDim.new(0, 5)
StepCorner.Parent = StepInput

local GuiParent
pcall(function()
    if type(gethui) == "function" then
        GuiParent = gethui()
    end
end)
StepGui.Parent = GuiParent or game:GetService("CoreGui")

StepInput.FocusLost:Connect(function()
    local value = tonumber(StepInput.Text)
    if not value then
        StepInput.Text = tostring(MoveStep)
        return
    end

    MoveStep = math.clamp(value, 0.1, 10)
    StepInput.Text = tostring(MoveStep)
end)

for index, definition in ipairs(HandleDefinitions) do
    local shaft = Drawing.new("Line")
    shaft.Color = GOLD
    shaft.Thickness = 3
    shaft.Visible = false

    local head = Drawing.new("Triangle")
    head.Color = GOLD
    head.Filled = true
    head.Visible = false

    Handles[index] = {
        Definition = definition,
        Shaft = shaft,
        Head = head,
        ScreenTip = nil
    }
end

local ActiveHandle
local ActiveInputType
local ActiveTouchInput
local IsDragging = false
local DragStartPivot
local DragAxisWorld
local DragStartPointer
local CurrentPointer
local LastAppliedOffset = 0
local HandleHitRadius = 25

local function HideHandles()
    for _, handle in ipairs(Handles) do
        handle.Shaft.Visible = false
        handle.Head.Visible = false
        handle.ScreenTip = nil
    end
end

local function SetActiveHandle(index)
    ActiveHandle = index
    for handleIndex, handle in ipairs(Handles) do
        local active = handleIndex == index
        handle.Head.Color = active and Color3.new(1, 1, 1) or GOLD
        handle.Shaft.Thickness = active and 5 or 3
    end
end

local function FindHandleAt(position)
    local closest
    local distanceLimit = HandleHitRadius
    for index, handle in ipairs(Handles) do
        if handle.Head.Visible then
            local distance = handle.ScreenTip
                and (handle.ScreenTip - position).Magnitude or math.huge
            if distance <= distanceLimit then
                closest = index
                distanceLimit = distance
            end
        end
    end
    return closest
end

local function GetAxisVector(pivot, definition)
    local axis = ({
        X = pivot.RightVector,
        Y = pivot.UpVector,
        Z = -pivot.LookVector
    })[definition.Axis]
    return axis * definition.Sign
end

local function GetHandleDistance(model)
    local size = model:IsA("Model") and model:GetExtentsSize()
        or (GetModelRef(model) and GetModelRef(model).Size)
        or Vector3.new(4.5, 4.5, 4.5)
    return math.max(size.X, size.Y, size.Z) * 0.5 + 2.5
end

local function UpdateHandles()
    local model = CopyMode.CopiedBlock
    if not CopyMode.Active or not CopyMode.Moving or not model or not model.Parent then
        HideHandles()
        return
    end

    Camera = workspace.CurrentCamera
    if not Camera then HideHandles() return end

    local pivot = model:GetPivot()
    local distance = GetHandleDistance(model)
    for index, handle in ipairs(Handles) do
        local worldPoint = pivot.Position + GetAxisVector(pivot, handle.Definition) * distance
        local screenPoint, onScreen = Camera:WorldToViewportPoint(worldPoint)
        local visible = onScreen and screenPoint.Z > 0
        handle.Shaft.Visible = visible
        handle.Head.Visible = visible
        if visible then
            local center, centerVisible = Camera:WorldToViewportPoint(pivot.Position)
            local centerPoint = Vector2.new(center.X, center.Y)
            local tipPoint = Vector2.new(screenPoint.X, screenPoint.Y)
            local direction = (tipPoint - centerPoint).Unit
            local perpendicular = Vector2.new(-direction.Y, direction.X)
            local headLength = 14
            local headWidth = 7
            local basePoint = tipPoint - direction * headLength

            handle.Shaft.From = centerPoint
            handle.Shaft.To = basePoint
            handle.Head.PointA = tipPoint
            handle.Head.PointB = basePoint + perpendicular * headWidth
            handle.Head.PointC = basePoint - perpendicular * headWidth
            handle.ScreenTip = tipPoint
            handle.Shaft.Visible = centerVisible and center.Z > 0
        end
    end
end

local function FinishDrag()
    if IsDragging and CopyMode.CopiedBlock and CopyMode.CopiedBlock.Parent then
        local ok, err = pcall(function()
            CommitMove:InvokeServer(CopyMode.CopiedBlock, CopyMode.CopiedBlock:GetPivot())
        end)
        if not ok then warn("[CopyTest] CommitMove after drag failed:", err) end
    end

    IsDragging = false
    DragStartPivot = nil
    DragAxisWorld = nil
    DragStartPointer = nil
    CurrentPointer = nil
    LastAppliedOffset = 0
end

local function BeginDrag(index, pointer)
    local model = CopyMode.CopiedBlock
    if not model or not model.Parent then return false end

    local pivot = model:GetPivot()
    local axis = GetAxisVector(pivot, Handles[index].Definition)
    local center, onScreen = Camera:WorldToViewportPoint(pivot.Position)
    local endpoint, endpointVisible = Camera:WorldToViewportPoint(
        pivot.Position + axis * 10
    )
    if not onScreen or not endpointVisible or center.Z <= 0 or endpoint.Z <= 0 then
        return false
    end

    local projected = Vector2.new(endpoint.X - center.X, endpoint.Y - center.Y)
    if projected.Magnitude < 2 then return false end

    DragStartPivot = pivot
    DragAxisWorld = axis
    DragStartPointer = pointer
    CurrentPointer = pointer
    LastAppliedOffset = 0
    IsDragging = true
    return true
end

local function ApplyDrag(pointer)
    if not IsDragging or not DragStartPivot or not DragAxisWorld
        or not CopyMode.CopiedBlock or not CopyMode.CopiedBlock.Parent then
        return
    end

    Camera = workspace.CurrentCamera
    if not Camera then return end

    local center = Camera:WorldToViewportPoint(DragStartPivot.Position)
    local endpoint = Camera:WorldToViewportPoint(
        DragStartPivot.Position + DragAxisWorld * 10
    )
    local screenAxis = Vector2.new(endpoint.X - center.X, endpoint.Y - center.Y)
    local pixelsPerStud = screenAxis.Magnitude / 10
    if pixelsPerStud < 0.5 then return end

    local projected = (pointer - DragStartPointer):Dot(screenAxis.Unit)
    local rawOffset = projected / pixelsPerStud
    local offset = math.floor(rawOffset / MoveStep + 0.5) * MoveStep
    if math.abs(offset - LastAppliedOffset) < 0.0001 then return end

    LastAppliedOffset = offset
    local newPivot = DragStartPivot + DragAxisWorld * offset
    CopyMode.CopiedBlock:PivotTo(newPivot)
end

local function CaptureInput(_, inputState, inputObject)
    local inputType = inputObject.UserInputType

    if inputState == Enum.UserInputState.Begin then
        if UIS:GetFocusedTextBox() then
            return Enum.ContextActionResult.Pass
        end
        if inputType ~= Enum.UserInputType.MouseButton1
            and inputType ~= Enum.UserInputType.Touch then
            return Enum.ContextActionResult.Pass
        end

        local index = FindHandleAt(GetScreenPosition(inputObject))
        if not index then return Enum.ContextActionResult.Pass end

        ActiveInputType = inputType
        ActiveTouchInput = inputType == Enum.UserInputType.Touch and inputObject or nil
        CurrentPointer = GetScreenPosition(inputObject)
        SetActiveHandle(index)
        if not BeginDrag(index, CurrentPointer) then
            SetActiveHandle(nil)
            ActiveInputType = nil
            ActiveTouchInput = nil
            return Enum.ContextActionResult.Pass
        end
        return Enum.ContextActionResult.Sink
    end

    if ActiveHandle and inputType == ActiveInputType then
        if inputType == Enum.UserInputType.Touch
            and ActiveTouchInput and inputObject ~= ActiveTouchInput then
            return Enum.ContextActionResult.Pass
        end

        if inputState == Enum.UserInputState.Change then
            CurrentPointer = GetScreenPosition(inputObject)
            return Enum.ContextActionResult.Sink
        end

        if inputState == Enum.UserInputState.End
            or inputState == Enum.UserInputState.Cancel then
            FinishDrag()
            SetActiveHandle(nil)
            ActiveInputType = nil
            ActiveTouchInput = nil
            return Enum.ContextActionResult.Sink
        end
    end

    return Enum.ContextActionResult.Pass
end

CAS:BindActionAtPriority(
    CaptureActionName,
    CaptureInput,
    false,
    3000,
    Enum.UserInputType.MouseButton1,
    Enum.UserInputType.Touch
)

local InputChangedConnection = UIS.InputChanged:Connect(function(inputObject)
    if ActiveHandle and ActiveInputType == Enum.UserInputType.MouseButton1
        and inputObject.UserInputType == Enum.UserInputType.MouseMovement then
        CurrentPointer = GetScreenPosition(inputObject)
    end
end)

local function CreateCopy(source)
    local sourceRef = GetModelRef(source)
    if not sourceRef then
        warn("[CopyTest] Source block reference part not found")
        return nil
    end

    local template = FindTemplate(source.Name)
    if not template then
        warn("[CopyTest] Template not found:", source.Name)
        return nil
    end

    local colorPart = source:FindFirstChild("ColorPart")
    local brickColor = colorPart and colorPart.BrickColor or BrickColor.new("Medium stone grey")
    local material = colorPart and colorPart.Material or Enum.Material.Plastic

    local ok, copy = pcall(function()
        return PlaceBlock:InvokeServer(
            template,
            CFrame.new(0, 10000, 0),
            brickColor,
            material
        )
    end)
    if not ok or not copy then
        warn("[CopyTest] PlaceBlock failed:", copy)
        return nil
    end

    local sourcePivot = sourceRef.CFrame
    local moveOk, moveError = pcall(function()
        CommitMove:InvokeServer(copy, sourcePivot)
    end)
    if not moveOk then
        warn("[CopyTest] Initial CommitMove failed:", moveError)
        return nil
    end

    local defaultSize = Vector3.new(4.5, 4.5, 4.5)
    local sourceBase = source:FindFirstChild("Base")
    local sourceColorPart = source:FindFirstChild("ColorPart")
    local copyBase = copy:FindFirstChild("Base")
    local copyColorPart = copy:FindFirstChild("ColorPart")

    -- Thin Wall is a two-part block. CommitResize needs a part/CFrame/Size
    -- triple for BOTH Base and ColorPart; resizing only ColorPart loses the
    -- wall dimensions when the map is saved and loaded again.
    if sourceBase and sourceColorPart and copyBase and copyColorPart
        and sourceBase:IsA("BasePart") and sourceColorPart:IsA("BasePart")
        and copyBase:IsA("BasePart") and copyColorPart:IsA("BasePart") then
        task.wait(0.05)
        local resizeData = {
            copyBase, sourceBase.CFrame, sourceBase.Size,
            copyColorPart, sourceColorPart.CFrame, sourceColorPart.Size
        }
        local resizeOk, resizeError = pcall(function()
            CommitResize:InvokeServer(copy, resizeData)
        end)
        if not resizeOk then
            warn("[CopyTest] Thin Wall CommitResize failed:", resizeError)
        end
    else
        local size = sourceRef.Size
        if (size - defaultSize).Magnitude > 0.1 then
            task.wait(0.05)
            local copyRef = GetModelRef(copy)
            if copyRef then
                local resizeOk, resizeError = pcall(function()
                    CommitResize:InvokeServer(copy, {copyRef, sourcePivot, size})
                end)
                if not resizeOk then
                    warn("[CopyTest] CommitResize failed:", resizeError)
                end
            end
        end
    end

    return copy
end

--==================================================
-- MODE IMPLEMENTATION
--==================================================

function CopyMode:Init(clientState)
    self.ClientState = clientState
    self.Placement = PlacementLogic.new()
    self.Outline = BoxSelectionAdornment.new()

    local parent = BuildModeGui:WaitForChild("Frame"):WaitForChild("Adornment")
    self.Outline:SetParent(parent)
    self.Outline:SetColor(GOLD)
    self.Outline:SetThickness(0.03)
    self.Outline:SetAdornee(nil)

    self.Initialized = true
    print("[CopyTest] CopyMode initialized")
end

function CopyMode:Enter(clientState)
    self.ClientState = clientState or self.ClientState
    self.Active = true
    self.Target = nil
    self.CopiedBlock = nil
    self.Moving = false
    HideHandles()
    self.Outline:SetAdornee(nil)
    print("[CopyTest] CopyMode entered")
end

function CopyMode:Exit()
    if IsDragging then FinishDrag() end
    SetActiveHandle(nil)
    ActiveInputType = nil
    ActiveTouchInput = nil
    self.Active = false
    self.Target = nil
    self.CopiedBlock = nil
    self.Moving = false
    HideHandles()
    if self.Outline then self.Outline:SetAdornee(nil) end
    print("[CopyTest] CopyMode exited")
end

function CopyMode:Update(dt, clientState)
    if not self.Active or not self.Placement or not self.Outline then return end
    self.ClientState = clientState or self.ClientState

    if IsDragging and ActiveInputType == Enum.UserInputType.Touch and ActiveTouchInput then
        if ActiveTouchInput.UserInputState == Enum.UserInputState.End
            or ActiveTouchInput.UserInputState == Enum.UserInputState.Cancel then
            FinishDrag()
            SetActiveHandle(nil)
            ActiveInputType = nil
            ActiveTouchInput = nil
        else
            CurrentPointer = GetScreenPosition(ActiveTouchInput)
        end
    end

    if IsDragging and CurrentPointer then
        ApplyDrag(CurrentPointer)
    end

    if self.Moving and self.CopiedBlock and self.CopiedBlock.Parent then
        self.Outline:SetColor(GOLD)
        self.Outline:SetThickness(0.1)
        self.Outline:SetAdornee(self.CopiedBlock)
        UpdateHandles()
        return
    end

    HideHandles()
    self.Outline:SetThickness(0.03)

    local ok, result = pcall(function()
        return self.Placement:Raycast()
    end)

    local block
    if ok and result and result.Instance then
        local candidate = result.Instance.Parent
        if candidate and candidate:IsA("Model") and candidate.Parent == BuildModel then
            block = candidate
        end
    end

    if block ~= self.Target then
        self.Target = block
        self.Outline:SetColor(GOLD)
        self.Outline:SetAdornee(block)
    end
end

function CopyMode:Action(clientState)
    if not self.Active then return Enum.ContextActionResult.Sink end
    self.ClientState = clientState or self.ClientState

    -- Second main-button press ends positioning, but keeps the Copy tool active.
    if self.Moving and self.CopiedBlock and self.CopiedBlock.Parent then
        if IsDragging then FinishDrag() end
        self.Moving = false
        self.CopiedBlock = nil
        self.Target = nil
        HideHandles()
        self.Outline:SetThickness(0.03)
        self.Outline:SetAdornee(nil)
        print("[CopyTest] Placement confirmed; ready for next copy")
        return Enum.ContextActionResult.Sink
    end

    local ok, result = pcall(function()
        return self.Placement:Raycast()
    end)
    if not ok or not result or not result.Instance then
        print("[CopyTest] No block under cursor")
        return Enum.ContextActionResult.Sink
    end

    local source = result.Instance.Parent
    if not source or not source:IsA("Model") or source.Parent ~= BuildModel then
        print("[CopyTest] Ignored target outside BuildModel")
        return Enum.ContextActionResult.Sink
    end

    local copy = CreateCopy(source)
    if not copy then return Enum.ContextActionResult.Sink end

    self.CopiedBlock = copy
    self.Moving = true
    self.Target = nil
    self.Outline:SetColor(GOLD)
    self.Outline:SetThickness(0.1)
    self.Outline:SetAdornee(copy)
    UpdateHandles()
    print("[CopyTest] Created copy:", copy:GetFullName())
    return Enum.ContextActionResult.Sink
end

function CopyMode:Destroy()
    if IsDragging then FinishDrag() end
    CAS:UnbindAction(CaptureActionName)
    if InputChangedConnection then
        InputChangedConnection:Disconnect()
        InputChangedConnection = nil
    end
    HideHandles()
    for _, handle in ipairs(Handles) do
        pcall(function() handle.Shaft:Remove() end)
        pcall(function() handle.Head:Remove() end)
    end
    pcall(function() StepGui:Destroy() end)
    if self.Outline then
        pcall(function() self.Outline:Destroy() end)
        self.Outline = nil
    end
    self.Placement = nil
    self.Active = false
    self.Initialized = false
end

local PreviousRenderMode = rawget(RenderModes, "Copy")
RenderModes.Copy = CopyMode
CopyMode:Init(ClientState)

--==================================================
-- MAIN PLACE-BLOCK BUTTON DISPATCH
--==================================================

local OriginalPlaceBlockAction = ClientState.PlaceBlockAction
assert(type(OriginalPlaceBlockAction) == "function", "[CopyTest] PlaceBlockAction missing")

local function CopyPlaceBlockAction(self, ...)
    local currentMode = BuildingMode:Get()
    if currentMode and currentMode.Name == "Copy" then
        return CopyMode:Action(self, ...)
    end
    return OriginalPlaceBlockAction(self, ...)
end
ClientState.PlaceBlockAction = CopyPlaceBlockAction

--==================================================
-- TOOLBAR BUTTON / MODE EVENTS
--==================================================

local function Connect(connection)
    table.insert(Connections, connection)
    return connection
end

Connect(Button.Activated:Connect(function()
    ShowHint:Fire("Selected copy tool")
    BuildingMode:SetMode(CopyEnum)
    Frame.Visible = false
    CAS:UnbindAction("pick_building_mode")
    if type(BuildingToolbar.HideInputIcons) == "function" then
        BuildingToolbar:HideInputIcons()
    end
end))

Connect(ChangedEvent.Event:Connect(function(modeName)
    if modeName == "Copy" then
        if not CopyMode.Active then
            CopyMode:Enter(ClientState)
        end
        task.defer(function()
            if not Cleaned and BuildingMode:Get() == CopyEnum then
                pcall(function() CAS:SetTitle("place_block", "Copy") end)
            end
        end)
    elseif CopyMode.Active then
        CopyMode:Exit()
    end
end))

--==================================================
-- CLEANUP
--==================================================

local function Cleanup()
    if Cleaned then return end
    Cleaned = true

    for _, connection in ipairs(Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(Connections)

    if CopyMode.Active then
        pcall(function() CopyMode:Exit() end)
    end
    pcall(function() CopyMode:Destroy() end)

    if BuildingMode:Get() == CopyEnum then
        pcall(function() BuildingMode:SetMode(Enumeration.BuildingMode.None) end)
    end

    if rawget(RenderModes, "Copy") == CopyMode then
        RenderModes.Copy = PreviousRenderMode
    end
    if ClientState.PlaceBlockAction == CopyPlaceBlockAction then
        ClientState.PlaceBlockAction = OriginalPlaceBlockAction
    end
    if Slots[7] and Slots[7].Instance == Button then
        Slots[7] = OriginalSlot7
    end
    pcall(function() Button:Destroy() end)
    pcall(function() Frame.Size = OriginalFrameSize end)

    if CreatedEnum and rawget(EnumItems, "Copy") == CopyEnum then
        rawset(EnumItems, "Copy", nil)
        for index, item in ipairs(EnumOrdered) do
            if item == CopyEnum then
                table.remove(EnumOrdered, index)
                break
            end
        end
    end
    if CreatedIcon and CopyIcon and CopyIcon.Parent then
        CopyIcon:Destroy()
    end
    print("[CopyTest] Cleanup complete")
end

Env.CopyTestCleanup = Cleanup
Env.CopyTestMode = CopyMode
Env.CopyTestEnum = CopyEnum

print("================================")
print("[CopyTest] Loaded")
print("[CopyTest] Toolbar button: READY")
print("[CopyTest] Gold hover outline: READY")
print("[CopyTest] Copy + CommitMove + CommitResize: READY")
print("[CopyTest] Six local-axis move handles: READY")
print("[CopyTest] Mouse + Touch drag: READY")
print("[CopyTest] Main button toggles positioning / next-copy mode")
print("================================")
