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

local BuildingMode

for _, object in ipairs(getgc(true)) do
    if type(object) == "table"
    and type(rawget(object, "SetMode")) == "function"
    and type(rawget(object, "Get")) == "function"
    and type(rawget(object, "_stack")) == "table" then
        BuildingMode = object
        break
    end
end

assert(BuildingMode, "[RotateTest] BuildingMode object not found")

--==================================================
-- FIND ENUMERATION
--==================================================

local Enumeration

for _, object in ipairs(getgc(true)) do
    if type(object) == "table" then
        local enumTypes = rawget(object, "_EnumTypes")

        if enumTypes and enumTypes.BuildingMode then
            Enumeration = object
            break
        end
    end
end

assert(Enumeration, "[RotateTest] Enumeration not found")

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
-- FIX NATIVE PLACE-BLOCK TITLE
-- BuildModeClient calls SetTitle("place_block", titles[mode]).
-- Add the missing Rotate title to the native title lookup table.
--==================================================

local BuildEnum = BuildingModeEnum.Build
local DestroyEnum = BuildingModeEnum.Destroy
local ResizeEnum = BuildingModeEnum.Resize
local MoveEnum = BuildingModeEnum.Move
local ColorPickEnum = BuildingModeEnum.ColorPick
local ColorFillEnum = BuildingModeEnum.ColorFill

local TitleTable
local TitleTableScore = 0

for _, fn in ipairs(getgc(true)) do
    if type(fn) == "function" then
        local infoOk, info = pcall(debug.getinfo, fn)
        local source = infoOk and info and info.source or ""

        if string.find(source, "BuildModeClient", 1, true) then
            for upvalueIndex = 1, 16 do
                local upvalueOk, value = pcall(debug.getupvalue, fn, upvalueIndex)

                if not upvalueOk or value == nil then
                    break
                end

                if type(value) == "table" then
                    local score = 0

                    for _, enumItem in ipairs({
                        BuildEnum,
                        DestroyEnum,
                        ResizeEnum,
                        MoveEnum,
                        ColorPickEnum,
                        ColorFillEnum
                    }) do
                        if enumItem and type(rawget(value, enumItem)) == "string" then
                            score = score + 1
                        end
                    end

                    if score > TitleTableScore then
                        TitleTable = value
                        TitleTableScore = score
                    end
                end
            end
        end
    end
end

local PreviousRotateTitle
local PatchedTitle = false

if TitleTable and TitleTableScore >= 3 then
    PreviousRotateTitle = rawget(TitleTable, RotateEnum)
    rawset(TitleTable, RotateEnum, "Rotate")
    PatchedTitle = true
    print("[RotateTest] Native Rotate title patched; matched entries:", TitleTableScore)
else
    warn("[RotateTest] Could not identify native title table; title fix not applied")
end

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
-- ROTATE MODE TEST STUB
-- Keep gizmo implementation separate until integration is stable.
--==================================================

local RotateMode = {
    Initialized = false,
    Active = false,
    ClientState = nil
}

function RotateMode:Init(clientState)
    self.ClientState = clientState
    self.Initialized = true
    print("[RotateTest] RotateMode.Init")
end

function RotateMode:Enter(clientState)
    self.ClientState = clientState or self.ClientState
    self.Active = true
    print("[RotateTest] RotateMode.Enter")
end

function RotateMode:Exit()
    self.Active = false
    print("[RotateTest] RotateMode.Exit")
end

function RotateMode:Update(dt, clientState)
    if not self.Active then
        return
    end
    -- Rotation gizmo will be integrated after toolbar testing.
end

function RotateMode:Action(clientState)
    if not self.Active then
        return
    end
    -- Rotation input will be integrated after toolbar testing.
end

local PreviousRenderMode = rawget(RenderModes, "Rotate")
RenderModes.Rotate = RotateMode
RotateMode:Init(ClientState)

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
    elseif RotateMode.Active then
        print("[RotateTest] Another mode selected:", modeName)
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

    if BuildingMode:Get() == RotateEnum then
        pcall(function()
            BuildingMode:SetMode(Enumeration.BuildingMode.None)
        end)
    end

    if rawget(RenderModes, "Rotate") == RotateMode then
        RenderModes.Rotate = PreviousRenderMode
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
print("[RotateTest] Title patch:", PatchedTitle)
print("[RotateTest] Click Rotate to test")
print("================================")
