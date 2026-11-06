--==================================================
-- ROTATE SELECTION TEST
-- Diagnostic only: observes native Move/Resize selection.
-- Does not hook or replace native functions.
--==================================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local BuildModeGui = PlayerGui:WaitForChild("BuildModeGui")
local ContextGui = PlayerGui:WaitForChild("ContextActionGui")
local ContextButton = ContextGui
    :WaitForChild("ContextButtonFrame")
    :WaitForChild("ContextActionButton")

local BuildModeFolder = RS:WaitForChild("BuildMode")
local BuildingMode = require(BuildModeFolder:WaitForChild("BuildingMode"))
local PlacementLogic = require(BuildModeFolder:WaitForChild("PlacementLogic"))

local Env = getgenv()

if type(Env.RotateSelectionTestCleanup) == "function" then
    pcall(Env.RotateSelectionTestCleanup)
end

--==================================================
-- FIND CLIENT STATE SAFELY
--==================================================

local ClientState

for attempt = 1, 100 do
    for _, object in ipairs(getgc(true)) do
        if type(object) == "table"
            and rawget(object, "ScreenGui") == BuildModeGui
            and rawget(object, "Toolbar")
            and type(rawget(object, "PlaceBlockAction")) == "function" then
            ClientState = object
            break
        end
    end

    if ClientState then
        break
    end

    task.wait(0.1)
end

assert(ClientState, "[RotateSelectionTest] ClientState not found")

local function Describe(value)
    local valueType = typeof(value)

    if valueType == "Instance" then
        local ok, fullName = pcall(function()
            return value:GetFullName()
        end)
        return ok and fullName or tostring(value)
    end

    if type(value) == "table" then
        return "table: " .. tostring(value)
    end

    return tostring(value)
end

local RelevantNames = {
    "SelectedBlock",
    "Selected",
    "Selection",
    "BoxSelection",
    "MoveHandles",
    "ResizeHandles",
    "Placement",
    "Adornment",
    "Target",
    "Block"
}

local function DumpRelevantState(label)
    print("========== [SELECTION TEST] " .. label .. " ==========")

    for _, name in ipairs(RelevantNames) do
        local value = rawget(ClientState, name)
        if value ~= nil then
            print("[STATE]", name, typeof(value), Describe(value))
        else
            print("[STATE]", name, "nil")
        end
    end

    -- Also report any additional ClientState fields whose names look
    -- related to selection, handles, adornments, or blocks.
    for name, value in pairs(ClientState) do
        if type(name) == "string"
            and not table.find(RelevantNames, name)
            and string.find(string.lower(name), "select", 1, true)
                or (type(name) == "string"
                    and not table.find(RelevantNames, name)
                    and string.find(string.lower(name), "handle", 1, true))
            or (type(name) == "string"
                and not table.find(RelevantNames, name)
                and string.find(string.lower(name), "adorn", 1, true))
            or (type(name) == "string"
                and not table.find(RelevantNames, name)
                and string.find(string.lower(name), "block", 1, true)) then
            print("[STATE+]", name, typeof(value), Describe(value))
        end
    end

    print("========== [END STATE] ==========")
end

--==================================================
-- REPORT CURRENT HOVER RAYCAST
--==================================================

local Placement = PlacementLogic.new()

local function ReportRaycast()
    local ok, result = pcall(function()
        return Placement:Raycast()
    end)

    if not ok then
        warn("[SELECTION TEST] Raycast failed:", result)
        return
    end

    local hit = result and result.Instance
    local model = hit and hit.Parent
    local buildModel = workspace:FindFirstChild("BuildModel")

    if model and model:IsA("Model") and model.Parent == buildModel then
        print("[SELECTION TEST] Raycast block:", model:GetFullName())
    else
        print("[SELECTION TEST] Raycast block: nil")
    end
end

--==================================================
-- OBSERVE THE MAIN ACTION BUTTON
--==================================================

local clickCount = 0
local connection = ContextButton.Activated:Connect(function()
    clickCount += 1
    local thisClick = clickCount

    local currentMode = BuildingMode:Get()
    print("[SELECTION TEST] Main action clicked; mode:",
        currentMode and currentMode.Name or "nil",
        "click:", thisClick
    )

    ReportRaycast()

    -- Run after the native button's Activated listeners.
    task.defer(function()
        task.wait(0.1)
        DumpRelevantState("AFTER MAIN ACTION #" .. thisClick)
    end)
end)

Env.RotateSelectionTestCleanup = function()
    pcall(function()
        connection:Disconnect()
    end)

    pcall(function()
        Placement = nil
    end)

    print("[SELECTION TEST] Cleanup complete")
end

print("================================")
print("[SELECTION TEST] Installed")
print("[SELECTION TEST] No hooks or native functions replaced")
print("[SELECTION TEST] Use native Move or Resize")
print("[SELECTION TEST] Hover a block, press the main action button")
print("[SELECTION TEST] Then send the complete log")
print("================================")
