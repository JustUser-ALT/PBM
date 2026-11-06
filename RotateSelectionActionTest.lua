-- RotateSelectionActionTest.lua
-- Run AFTER RotateTest.lua. Tests selection using the main Move/Resize action button.
-- Does not hook native functions and does not touch MoveHandles or ResizeHandles.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local BuildModeGui = PlayerGui:WaitForChild("BuildModeGui")

local Common = ReplicatedStorage:WaitForChild("BuildMode"):WaitForChild("Common")
local BuildingMode = require(Common:WaitForChild("BuildingMode"))

local function log(...)
    print("[ROTATE SELECTION TEST]", ...)
end

-- Stop a previous copy of this diagnostic first.
if getgenv().RotateSelectionActionTestCleanup then
    pcall(getgenv().RotateSelectionActionTestCleanup)
end

local ClientState
for _, object in ipairs(getgc(true)) do
    if type(object) == "table"
        and rawget(object, "ScreenGui") == BuildModeGui
        and rawget(object, "Toolbar")
        and type(rawget(object, "PlaceBlockAction")) == "function"
        and rawget(object, "Placement")
        and rawget(object, "BoxSelection") then
        ClientState = object
        break
    end
end

if not ClientState then
    warn("[ROTATE SELECTION TEST] ClientState not found. Is RotateTest.lua running?")
    return
end

local OriginalPlaceBlockAction = ClientState.PlaceBlockAction
local OriginalSelectedBlock = ClientState.SelectedBlock
local BoxSelection = ClientState.BoxSelection
local OriginalBoxColor = Color3.new(0, 0, 1)

local alive = true
local renderConnection

local function isRotateMode()
    local mode = BuildingMode:Get()
    return mode ~= nil and mode.Name == "Rotate"
end

local function rotateAction(self, ...)
    if not isRotateMode() then
        return OriginalPlaceBlockAction(self, ...)
    end

    local result = self.Placement:Raycast()
    if not result then
        self.SelectedBlock = nil
        log("Raycast miss -> selection cleared")
        return Enum.ContextActionResult.Sink
    end

    local block = result.Instance and result.Instance.Parent
    if not block then
        self.SelectedBlock = nil
        log("Raycast has no parent -> selection cleared")
        return Enum.ContextActionResult.Sink
    end

    if self.SelectedBlock == block then
        self.SelectedBlock = nil
        log("Deselected:", block:GetFullName())
    elseif block.Parent == workspace:FindFirstChild("BuildModel") then
        self.SelectedBlock = block
        log("Selected:", block:GetFullName())
    else
        log("Ignored target outside workspace.BuildModel:", block:GetFullName())
    end

    return Enum.ContextActionResult.Sink
end

ClientState.PlaceBlockAction = rotateAction

renderConnection = RunService.RenderStepped:Connect(function()
    if not alive then
        return
    end

    if not isRotateMode() then
        return
    end

    local selected = ClientState.SelectedBlock
    if selected and selected.Parent then
        BoxSelection:SetColor(Color3.fromRGB(170, 85, 255))
        BoxSelection:SetAdornee(selected)
    else
        BoxSelection:SetAdornee(nil)
    end
end)

getgenv().RotateSelectionActionTestCleanup = function()
    if not alive then
        return
    end
    alive = false

    if renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end

    if ClientState.PlaceBlockAction == rotateAction then
        ClientState.PlaceBlockAction = OriginalPlaceBlockAction
    end

    ClientState.SelectedBlock = OriginalSelectedBlock
    BoxSelection:SetAdornee(nil)
    BoxSelection:SetColor(OriginalBoxColor)

    getgenv().RotateSelectionActionTestCleanup = nil
    log("Cleanup complete; previous dispatcher restored")
end

log("Installed")
log("Switch to Rotate, aim at a block, then press the MAIN Move/Resize action button.")
log("Click the same block again to deselect; click empty space to clear selection.")
log("Cleanup: getgenv().RotateSelectionActionTestCleanup()")
