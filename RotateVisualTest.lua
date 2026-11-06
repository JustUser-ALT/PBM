-- RotateVisualTest.lua
-- Run AFTER RotateTest.lua and RotateSelectionActionTest.lua.
-- Tests the existing native BoxSelection and MoveHandles visuals only.
-- Does not modify Rotate.lua or hook native functions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local buildModeGui = playerGui:WaitForChild("BuildModeGui")
local buildModeFolder = ReplicatedStorage:WaitForChild("BuildMode")
local BuildingMode = require(buildModeFolder:WaitForChild("BuildingMode"))

local function log(...)
    print("[ROTATE VISUAL TEST]", ...)
end

-- Remove a previous run of this diagnostic.
if getgenv().RotateVisualTestCleanup then
    pcall(getgenv().RotateVisualTestCleanup)
end

local clientState
for _, object in ipairs(getgc(true)) do
    if type(object) == "table"
        and rawget(object, "ScreenGui") == buildModeGui
        and rawget(object, "Toolbar")
        and type(rawget(object, "PlaceBlockAction")) == "function"
        and rawget(object, "Placement")
        and rawget(object, "BoxSelection")
        and rawget(object, "MoveHandles") then
        clientState = object
        break
    end
end

assert(clientState, "[ROTATE VISUAL TEST] ClientState not found")

local boxSelection = clientState.BoxSelection
local moveHandles = clientState.MoveHandles
local purple = Color3.fromRGB(170, 85, 255)
local blue = Color3.new(0, 0, 1)

local connection
local lastSelected
local lastStatus

local function isRotateMode()
    local mode = BuildingMode:Get()
    return mode and mode.Name == "Rotate"
end

connection = RunService.RenderStepped:Connect(function()
    if not isRotateMode() then
        if lastSelected then
            pcall(function() boxSelection:SetAdornee(nil) end)
            pcall(function() moveHandles:SetAdornee(nil) end)
            lastSelected = nil
            lastStatus = nil
            log("Rotate exited; test visuals cleared")
        end
        return
    end

    local selected = clientState.SelectedBlock
    if not selected or not selected.Parent then
        if lastSelected then
            pcall(function() boxSelection:SetAdornee(nil) end)
            pcall(function() moveHandles:SetAdornee(nil) end)
            lastSelected = nil
            lastStatus = nil
            log("Selection cleared")
        end
        return
    end

    local boxOk, boxError = pcall(function()
        boxSelection:SetColor(purple)
        boxSelection:SetAdornee(selected)
    end)

    local handlesOk, handlesError = pcall(function()
        moveHandles:SetAdornee(selected)
    end)

    if selected ~= lastSelected or not lastStatus then
        log("Selected:", selected:GetFullName())
        log("BoxSelection:", boxOk, boxError or "")
        log("MoveHandles:", handlesOk, handlesError or "")
        lastSelected = selected
        lastStatus = true
    end
end)

getgenv().RotateVisualTestCleanup = function()
    if connection then
        connection:Disconnect()
        connection = nil
    end

    pcall(function() boxSelection:SetAdornee(nil) end)
    pcall(function() boxSelection:SetColor(blue) end)
    pcall(function() moveHandles:SetAdornee(nil) end)

    getgenv().RotateVisualTestCleanup = nil
    log("Cleanup complete")
end

log("Installed")
log("Switch to Rotate, select one block with the MAIN action button, then inspect the purple outline and handles.")
log("Cleanup: getgenv().RotateVisualTestCleanup()")
