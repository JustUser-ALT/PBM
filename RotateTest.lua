--==================================================
-- ROTATE TEST
-- Native Build Mode Toolbar Integration
-- Isolated test; does not modify Rotate.lua
--==================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")

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

--==================================================
-- CLEANUP PREVIOUS TEST
--==================================================

if type(Env.RotateTestCleanup) == "function" then
    pcall(Env.RotateTestCleanup)
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

    if ClientState then
        break
    end

    task.wait(0.1)
end

assert(ClientState, "[RotateTest] ClientState not found")

--==================================================
-- FIND BUILDING MODE
--==================================================

local BuildingModeModule = BuildModeFolder:WaitForChild("BuildingMode")
local BuildingMode = require(BuildingModeModule)

assert(
    type(BuildingMode.SetMode) == "function",
    "[RotateTest] BuildingMode.SetMode missing"
)

print("[RotateTest] BuildingMode found:", BuildingMode)

--==================================================
-- FIND ENUMERATION
--==================================================

local Enumeration = require(BuildModeFolder:WaitForChild("Common"):WaitForChild("Enumeration"))
assert(type(Enumeration) == "table" and Enumeration.BuildingMode, "[RotateTest] Enumeration module invalid")

local BuildingModeEnum = Enumeration.BuildingMode
local EnumItems = rawget(BuildingModeEnum, "__items")
local EnumOrdered = rawget(BuildingModeEnum, "__ordered")

assert(type(EnumItems) == "table", "[RotateTest] Enum items table not found")
assert(type(EnumOrdered) == "table", "[RotateTest] Enum ordered table not found")

local RotateEnum = rawget(EnumItems, "Rotate")
local CreatedEnum = false

if not RotateEnum then
    RotateEnum = {
        Name = "Rotate",
        Value = 9,
        EnumerationType = "BuildingMode"
    }

    setmetatable(RotateEnum, {
        __tostring = function(self)
            return string.format("Enumeration.%s.%s", self.EnumerationType, self.Name)
        end
    })

    rawset(EnumItems, "Rotate", RotateEnum)
    table.insert(EnumOrdered, RotateEnum)
    CreatedEnum = true
end

print("[RotateTest] Enum registered:", tostring(RotateEnum))

--==================================================
-- NATIVE PLACE-BLOCK TITLE
-- BuildModeClient's native title table is local to its event callback.
-- SetTitle is applied after the native BuildingModeChanged listeners.
--==================================================

local TitlePatchReady = true

--==================================================
-- REGISTER ROTATE ICON
--==================================================

local RotateIcon = IconsFolder:FindFirstChild("Rotate")
local CreatedIcon = false

if not RotateIcon then
    RotateIcon = IconsFolder:WaitForChild("Move"):Clone()
    RotateIcon.Name = "Rotate"
    RotateIcon.Parent = IconsFolder
    CreatedIcon = true
end

--==================================================
-- FIND RENDER LOOP MODES
--==================================================

local RenderModes

for _, connection in ipairs(getconnections(RunService.RenderStepped)) do
    local fn = connection.Function

    if type(fn) == "function" then
        local success, upvalues = pcall(debug.getupvalues, fn)

        if success and type(upvalues) == "table" then
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

    if RenderModes then
        break
    end
end

assert(RenderModes, "[RotateTest] RenderLoop modes table not found")

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
    Target = nil
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
    self.Active = false
    self.Target = nil

    if self.Outline then
        pcall(function()
            self.Outline:SetAdornee(nil)
        end)
    end

    print("[RotateTest] RotateMode.Exit")
end

function RotateMode:Update(dt, clientState)
    if not self.Active or not self.Placement or not self.Outline then
        return
    end

    self.ClientState = clientState or self.ClientState

    local raycastOk, result = pcall(function()
        return self.Placement:Raycast()
    end)

    local block = nil

    if raycastOk and result and result.Instance then
        local hit = result.Instance
        local candidate = hit.Parent
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
        return
    end
    -- Rotation input will be integrated after hover selection testing.
end

function RotateMode:Destroy()
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

    if PatchedTitle and TitleTable then
        rawset(TitleTable, RotateEnum, PreviousRotateTitle)
    end

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
print("[RotateTest] Title patch:", PatchedTitle)
print("[RotateTest] Click Rotate to test")
print("================================")
