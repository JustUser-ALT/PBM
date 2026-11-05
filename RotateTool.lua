--[[
    RotateTool.lua
    JustUser-ALT/PBM
    Visual prototype 1 — local-axis X/Y/Z rings.

    Test scope:
    - Reads the currently selected Build Mode block.
    - Draws three local-axis rings using Drawing.
    - Does not rotate blocks or change Build Mode.
    - Does not create or modify game UI.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
local SegmentCount = 64
local Thickness = 4

local AxisColors = {
    Color3.fromRGB(255, 65, 65),
    Color3.fromRGB(75, 255, 110),
    Color3.fromRGB(75, 155, 255)
}

local Rings = {}

for axis = 1, 3 do
    Rings[axis] = {}

    for segment = 1, SegmentCount do
        local line = Drawing.new("Line")
        line.Color = AxisColors[axis]
        line.Thickness = Thickness
        line.Transparency = 1
        line.Visible = false

        Rings[axis][segment] = line
    end
end

local CurrentModel
local CurrentRadius = 3

local function HideRings()
    for axis = 1, 3 do
        for _, line in ipairs(Rings[axis]) do
            line.Visible = false
        end
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
        HideRings()
        return
    end

    local size = GetModelSize(model)
    CurrentRadius = math.max(size.X, size.Y, size.Z) * 0.75 + 0.5
end

local function DrawRing(axis, center, basisA, basisB)
    for i = 1, SegmentCount do
        local a1 = ((i - 1) / SegmentCount) * math.pi * 2
        local a2 = (i / SegmentCount) * math.pi * 2

        local p1 = center + (
            basisA * math.cos(a1) +
            basisB * math.sin(a1)
        ) * CurrentRadius

        local p2 = center + (
            basisA * math.cos(a2) +
            basisB * math.sin(a2)
        ) * CurrentRadius

        local screen1, visible1 = Camera:WorldToViewportPoint(p1)
        local screen2, visible2 = Camera:WorldToViewportPoint(p2)

        local line = Rings[axis][i]

        if visible1 and visible2
            and screen1.Z > 0 and screen2.Z > 0 then

            line.From = Vector2.new(screen1.X, screen1.Y)
            line.To = Vector2.new(screen2.X, screen2.Y)
            line.Visible = true
        else
            line.Visible = false
        end
    end
end

local Connection

Connection = RunService.RenderStepped:Connect(function()
    if not ClientState or not BuildModel.Parent then
        HideRings()
        return
    end

    local selected = ClientState.SelectedBlock

    if typeof(selected) ~= "Instance"
        or not selected:IsDescendantOf(BuildModel) then

        if CurrentModel then
            SetModel(nil)
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

    local pivot = CurrentModel:GetPivot()
    local center = pivot.Position

    local right = pivot.RightVector
    local up = pivot.UpVector
    local look = -pivot.LookVector

    -- X: YZ plane
    DrawRing(1, center, up, look)

    -- Y: XZ plane
    DrawRing(2, center, right, look)

    -- Z: XY plane
    DrawRing(3, center, right, up)
end)

getgenv().RotateVisualCleanup = function()
    if Connection then
        Connection:Disconnect()
        Connection = nil
    end

    for axis = 1, 3 do
        for _, line in ipairs(Rings[axis]) do
            pcall(function()
                line:Remove()
            end)
        end
    end

    Rings = {}
    CurrentModel = nil
end

print("[RotateTool] Visual prototype loaded")
print("[RotateTool] Select a block using Move or Resize")
