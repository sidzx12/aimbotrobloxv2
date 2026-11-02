-- universal aimbot | delta / any luau executor
if getgenv and getgenv().__uaim_unload then
    pcall(getgenv().__uaim_unload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CFG = {
    Enabled = true,
    TeamCheck = true,
    WallCheck = true,
    FOV = 150,
    Smoothing = 0.15,       -- 0 = instant snap, higher = slower
    AimPart = "Head",
    ToggleKey = Enum.KeyCode.RightAlt,
    HoldMouse2 = true,      -- aim only while rmb held
    ShowFOV = true,
}

local LP = Players.LocalPlayer
local Cam = Workspace.CurrentCamera
local enabled = CFG.Enabled
local BIND = "universal_aim"

local circle
if Drawing then
    circle = Drawing.new("Circle")
    circle.Thickness = 1
    circle.NumSides = 64
    circle.Filled = false
    circle.Color = Color3.fromRGB(255, 255, 255)
    circle.Visible = CFG.ShowFOV
end

local function isAlive(model)
    local hum = model and model:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function isEnemy(p)
    if not CFG.TeamCheck then return true end
    return p.Team == nil or p.Team ~= LP.Team
end

local function isVisible(part, model)
    if not CFG.WallCheck then return true end
    local origin = Cam.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character, Cam }
    local hit = Workspace:Raycast(origin, part.Position - origin, params)
    return hit == nil or hit.Instance:IsDescendantOf(model)
end

local function getTarget()
    local best, bestDist = nil, CFG.FOV
    local center = Vector2.new(Cam.ViewportSize.X / 2, Cam.ViewportSize.Y / 2)

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isEnemy(p) and p.Character and isAlive(p.Character) then
            local part = p.Character:FindFirstChild(CFG.AimPart)
            if part then
                local pos, onScreen = Cam:WorldToViewportPoint(part.Position)
                if onScreen and pos.Z > 0 then
                    local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
                    if d < bestDist and isVisible(part, p.Character) then
                        best, bestDist = part, d
                    end
                end
            end
        end
    end
    return best
end

local function holding()
    if not CFG.HoldMouse2 then return true end
    return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

local keyConn = UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.ToggleKey then
        enabled = not enabled
    end
end)

RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function()
    Cam = Workspace.CurrentCamera
    if circle then
        circle.Position = Vector2.new(Cam.ViewportSize.X / 2, Cam.ViewportSize.Y / 2)
        circle.Radius = CFG.FOV
        circle.Visible = CFG.ShowFOV and enabled
    end

    if not enabled or not holding() then return end

    local part = getTarget()
    if part then
        local goal = CFrame.lookAt(Cam.CFrame.Position, part.Position)
        Cam.CFrame = Cam.CFrame:Lerp(goal, 1 - CFG.Smoothing)
    end
end)

if getgenv then
    getgenv().__uaim_unload = function()
        RunService:UnbindFromRenderStep(BIND)
        keyConn:Disconnect()
        if circle then circle:Remove() end
    end
end
