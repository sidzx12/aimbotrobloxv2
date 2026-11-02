-- universal aimbot v2 | menu + fov + invisible | delta / any luau executor
if getgenv and getgenv().__uaim_unload then
    pcall(getgenv().__uaim_unload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local CFG = {
    Aimbot = true,
    TeamCheck = true,
    WallCheck = true,
    FOVEnabled = true,
    FOV = 150,
    FOVMin = 40,
    FOVMax = 600,
    Smoothing = 0.15,       -- 0 = snap, 0.95 = very slow
    AimPart = "Head",
    Invisible = false,
    HoldMouse2 = true,
    MenuKey = Enum.KeyCode.RightShift,
    ToggleKey = Enum.KeyCode.RightAlt,
}

local LP = Players.LocalPlayer
local Cam = Workspace.CurrentCamera
local BIND = "universal_aim"
local conns = {}

-- fov circle
local circle
if Drawing then
    circle = Drawing.new("Circle")
    circle.Thickness = 1
    circle.NumSides = 64
    circle.Filled = false
    circle.Color = Color3.fromRGB(255, 255, 255)
end

-- invisible (local only)
local function setLocalInvis(part)
    part.LocalTransparencyModifier = CFG.Invisible and 1 or 0
end

local function applyInvisChar(char)
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then setLocalInvis(d) end
    end
end

local function watchChar(char)
    applyInvisChar(char)
    table.insert(conns, char.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then setLocalInvis(d) end
    end))
end

if LP.Character then watchChar(LP.Character) end
table.insert(conns, LP.CharacterAdded:Connect(watchChar))

-- targeting
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

-- menu
local gui = Instance.new("ScreenGui")
gui.Name = "uaim_menu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
local okParent = pcall(function() gui.Parent = (gethui and gethui()) or CoreGui end)
if not okParent or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Name = "main"
frame.Size = UDim2.fromOffset(230, 330)
frame.Position = UDim2.fromOffset(40, 200)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 28)
title.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
title.BorderSizePixel = 0
title.Text = "  uaim"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.Code
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.Parent = frame

local list = Instance.new("Frame")
list.Position = UDim2.new(0, 0, 0, 32)
list.Size = UDim2.new(1, 0, 1, -36)
list.BackgroundTransparency = 1
list.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = list

local function mkBtn(parent, text)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -12, 0, 26)
    b.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
    b.BorderSizePixel = 0
    b.TextColor3 = Color3.fromRGB(230, 230, 230)
    b.Font = Enum.Font.Code
    b.TextSize = 14
    b.Text = text
    b.Parent = parent
    return b
end

local function toggleRow(label, get, set)
    local b = mkBtn(list, "")
    local function refresh() b.Text = label .. ": " .. (get() and "on" or "off") end
    b.MouseButton1Click:Connect(function()
        set(not get())
        refresh()
    end)
    refresh()
end

local function stepRow(label, get, set, step, min, max, fmt)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -12, 0, 26)
    f.BackgroundTransparency = 1
    f.Parent = list

    local minus = mkBtn(f, "-")
    minus.Size = UDim2.new(0, 30, 1, 0)
    local plus = mkBtn(f, "+")
    plus.Size = UDim2.new(0, 30, 1, 0)
    plus.Position = UDim2.new(1, -30, 0, 0)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -68, 1, 0)
    lbl.Position = UDim2.new(0, 34, 0, 0)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 14
    lbl.TextColor3 = Color3.fromRGB(230, 230, 230)
    lbl.Parent = f

    local function refresh() lbl.Text = label .. " " .. fmt(get()) end
    local function bump(d)
        set(math.clamp(get() + d, min, max))
        refresh()
    end
    minus.MouseButton1Click:Connect(function() bump(-step) end)
    plus.MouseButton1Click:Connect(function() bump(step) end)
    refresh()
end

toggleRow("aimbot", function() return CFG.Aimbot end,
    function(v) CFG.Aimbot = v end)
toggleRow("fov circle", function() return CFG.FOVEnabled end,
    function(v) CFG.FOVEnabled = v end)
stepRow("fov size", function() return CFG.FOV end,
    function(v) CFG.FOV = v end, 10, CFG.FOVMin, CFG.FOVMax,
    function(v) return tostring(math.floor(v)) end)
stepRow("smoothing", function() return CFG.Smoothing end,
    function(v) CFG.Smoothing = v end, 0.05, 0, 0.95,
    function(v) return string.format("%.2f", v) end)
toggleRow("invisible", function() return CFG.Invisible end,
    function(v)
        CFG.Invisible = v
        applyInvisChar(LP.Character)
    end)
toggleRow("team check", function() return CFG.TeamCheck end,
    function(v) CFG.TeamCheck = v end)
toggleRow("wall check", function() return CFG.WallCheck end,
    function(v) CFG.WallCheck = v end)

-- input
table.insert(conns, UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.ToggleKey then
        CFG.Aimbot = not CFG.Aimbot
    elseif input.KeyCode == CFG.MenuKey then
        gui.Enabled = not gui.Enabled
    end
end))

-- main loop
RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function()
    Cam = Workspace.CurrentCamera

    if circle then
        circle.Position = Vector2.new(Cam.ViewportSize.X / 2, Cam.ViewportSize.Y / 2)
        circle.Radius = CFG.FOV
        circle.Visible = CFG.FOVEnabled
    end

    if not CFG.Aimbot or not holding() then return end

    local part = getTarget()
    if part then
        local goal = CFrame.lookAt(Cam.CFrame.Position, part.Position)
        Cam.CFrame = Cam.CFrame:Lerp(goal, 1 - CFG.Smoothing)
    end
end)

-- unload
if getgenv then
    getgenv().__uaim_unload = function()
        RunService:UnbindFromRenderStep(BIND)
        for _, c in ipairs(conns) do c:Disconnect() end
        CFG.Invisible = false
        applyInvisChar(LP.Character)
        if circle then circle:Remove() end
        gui:Destroy()
    end
end
