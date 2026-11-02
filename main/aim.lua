-- uaim v4 | menu + hide + fov + invisible + npc + aim part + silent + aimkill + aimfire | delta / any luau executor
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
    NPCs = true,
    FOVEnabled = true,
    FOV = 150,
    FOVMin = 40,
    FOVMax = 600,
    Smoothing = 0.15,       -- 0 = snap, 0.95 = very slow
    AimPart = "head",       -- "head" | "neck" | "body"
    Silent = false,         -- redirect shots while mouse1 held
    AimKill = false,        -- silent aim, no key needed
    AimFire = false,        -- pin ammo/clip values on held tool
    Invisible = false,
    HoldMouse2 = true,
    MenuKey = Enum.KeyCode.RightShift,
    ToggleKey = Enum.KeyCode.RightAlt,
}

local LP = Players.LocalPlayer
local BIND = "uaim_loop"
local alive = true
local conns = {}
local refreshers = {}
local targets = {}
local lastScan = 0
local lastAmmo = 0
local silentTarget = nil
local ammoVal = {}     -- value instance -> highest seen
local ammoAttr = {}    -- tool -> { attrName = highest seen }

local function refreshAll()
    for _, f in ipairs(refreshers) do f() end
end

-- invisible (local only)
local function setInvisPart(d)
    if d:IsA("BasePart") then
        d.LocalTransparencyModifier = CFG.Invisible and 1 or 0
    end
end

local function applyInvis(char)
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do setInvisPart(d) end
end

local function watchChar(char)
    applyInvis(char)
    table.insert(conns, char.DescendantAdded:Connect(setInvisPart))
end

if LP.Character then watchChar(LP.Character) end
table.insert(conns, LP.CharacterAdded:Connect(watchChar))

-- aim position per part choice
local function aimPos(model)
    local head = model:FindFirstChild("Head")
    local torso = model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("HumanoidRootPart")

    if CFG.AimPart == "head" and head then
        return head.Position
    elseif CFG.AimPart == "neck" and head then
        return head.Position - Vector3.new(0, head.Size.Y * 0.5, 0)
    elseif torso then
        return torso.Position
    elseif head then
        return head.Position
    end
    return nil
end

-- targeting
local function isEnemy(model)
    local p = Players:GetPlayerFromCharacter(model)
    if not p then return CFG.NPCs end
    if p == LP then return false end
    if CFG.TeamCheck and LP.Team and p.Team == LP.Team then return false end
    return true
end

local function scan()
    table.clear(targets)
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Humanoid") and d.Health > 0 then
            local m = d.Parent
            if m and m:IsA("Model") and m ~= LP.Character and isEnemy(m) then
                table.insert(targets, { hum = d, model = m })
            end
        end
    end
end

local function visible(pos, model)
    if not CFG.WallCheck then return true end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local dir = pos - origin

    local ignore = { cam }
    if LP.Character then table.insert(ignore, LP.Character) end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true

    for _ = 1, 8 do
        params.FilterDescendantsInstances = ignore
        local ray = Workspace:Raycast(origin, dir, params)
        if not ray then return true end
        if ray.Instance:IsDescendantOf(model) then return true end
        if ray.Instance.CanCollide and ray.Instance.Transparency < 0.9 then
            return false
        end
        table.insert(ignore, ray.Instance)
    end
    return false
end

local function pickTarget()
    local cam = Workspace.CurrentCamera
    local center = cam.ViewportSize / 2
    local bestPos, bestD = nil, CFG.FOV

    for _, t in ipairs(targets) do
        if t.hum.Health > 0 and t.model.Parent then
            local pos = aimPos(t.model)
            if pos then
                local sp, on = cam:WorldToViewportPoint(pos)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d < bestD and visible(pos, t.model) then
                        bestPos, bestD = pos, d
                    end
                end
            end
        end
    end
    return bestPos
end

-- silent aim hook (goes inert after unload via alive flag)
local oldNamecall
local okHook, errHook = pcall(function()
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if not alive or not silentTarget or checkcaller() or self ~= Workspace then
            return oldNamecall(self, ...)
        end

        local method = getnamecallmethod()
        local cam = Workspace.CurrentCamera
        local args = table.pack(...)

        if method == "Raycast" then
            local origin, dir = args[1], args[2]
            if typeof(origin) == "Vector3" and typeof(dir) == "Vector3"
                and (origin - cam.CFrame.Position).Magnitude < 20 then
                local toT = silentTarget - origin
                if toT.Magnitude > 0 then
                    args[2] = toT.Unit * dir.Magnitude
                    return oldNamecall(self, table.unpack(args, 1, args.n))
                end
            end
        elseif method == "FindPartOnRay"
            or method == "FindPartOnRayWithIgnoreList"
            or method == "FindPartOnRayWithWhitelist" then
            local ray = args[1]
            if typeof(ray) == "Ray" and (ray.Origin - cam.CFrame.Position).Magnitude < 20 then
                local toT = silentTarget - ray.Origin
                if toT.Magnitude > 0 then
                    args[1] = Ray.new(ray.Origin, toT.Unit * ray.Direction.Magnitude)
                    return oldNamecall(self, table.unpack(args, 1, args.n))
                end
            end
        end

        return oldNamecall(self, ...)
    end))
end)
if not okHook then
    warn("uaim: silent hook failed, executor lacks hookmetamethod - " .. tostring(errHook))
end

-- aimfire: pin ammo-like values on the held tool
local AMMO_PAT = { "ammo", "clip", "mag", "bullet", "round" }

local function isAmmoName(n)
    n = n:lower()
    for _, p in ipairs(AMMO_PAT) do
        if n:find(p, 1, true) then return true end
    end
    return false
end

local function pinAmmo()
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return end

    for _, d in ipairs(tool:GetDescendants()) do
        if (d:IsA("IntValue") or d:IsA("NumberValue")) and isAmmoName(d.Name) then
            local top = math.max(ammoVal[d] or 0, d.Value)
            ammoVal[d] = top
            if d.Value < top then d.Value = top end
        end
    end

    local attrs = ammoAttr[tool] or {}
    ammoAttr[tool] = attrs
    for name, val in pairs(tool:GetAttributes()) do
        if type(val) == "number" and isAmmoName(name) then
            local top = math.max(attrs[name] or 0, val)
            attrs[name] = top
            if val < top then tool:SetAttribute(name, top) end
        end
    end
end

-- fov ring (gui, resizes live)
local ringGui = Instance.new("ScreenGui")
ringGui.Name = "uaim_fov"
ringGui.IgnoreGuiInset = true
ringGui.ResetOnSpawn = false
ringGui.DisplayOrder = 998

local ring = Instance.new("Frame")
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Position = UDim2.fromScale(0.5, 0.5)
ring.Size = UDim2.fromOffset(CFG.FOV * 2, CFG.FOV * 2)
ring.BackgroundTransparency = 1
ring.Parent = ringGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = ring

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Parent = ring

-- menu
local gui = Instance.new("ScreenGui")
gui.Name = "uaim_menu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
local okParent = pcall(function()
    gui.Parent = (gethui and gethui()) or CoreGui
end)
if not okParent or not gui.Parent then
    gui.Parent = LP:WaitForChild("PlayerGui")
end

local frame = Instance.new("Frame")
frame.Name = "main"
frame.Size = UDim2.fromOffset(230, 400)
frame.Position = UDim2.fromOffset(40, 200)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -28, 0, 28)
title.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
title.BorderSizePixel = 0
title.Text = "  uaim"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.Code
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.Parent = frame

local hideBtn = Instance.new("TextButton")
hideBtn.Size = UDim2.fromOffset(28, 28)
hideBtn.Position = UDim2.new(1, -28, 0, 0)
hideBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
hideBtn.BorderSizePixel = 0
hideBtn.Text = "x"
hideBtn.Font = Enum.Font.Code
hideBtn.TextSize = 15
hideBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
hideBtn.Parent = frame
hideBtn.MouseButton1Click:Connect(function()
    frame.Visible = false
end)

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
    local function refresh()
        b.Text = label .. ": " .. (get() and "on" or "off")
    end
    b.MouseButton1Click:Connect(function()
        set(not get())
        refreshAll()
    end)
    table.insert(refreshers, refresh)
    refresh()
end

local function cycleRow(label, opts, get, set)
    local b = mkBtn(list, "")
    local function refresh()
        b.Text = label .. ": " .. get()
    end
    b.MouseButton1Click:Connect(function()
        local idx = 1
        for i, v in ipairs(opts) do
            if v == get() then idx = i end
        end
        set(opts[idx % #opts + 1])
        refreshAll()
    end)
    table.insert(refreshers, refresh)
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

    local function refresh()
        lbl.Text = label .. " " .. fmt(get())
    end
    local function bump(d)
        set(math.clamp(get() + d, min, max))
        refreshAll()
    end
    minus.MouseButton1Click:Connect(function() bump(-step) end)
    plus.MouseButton1Click:Connect(function() bump(step) end)
    table.insert(refreshers, refresh)
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
cycleRow("aim part", { "head", "neck", "body" },
    function() return CFG.AimPart end,
    function(v) CFG.AimPart = v end)
toggleRow("silent aim", function() return CFG.Silent end,
    function(v) CFG.Silent = v end)
toggleRow("aimkill", function() return CFG.AimKill end,
    function(v) CFG.AimKill = v end)
toggleRow("aimfire", function() return CFG.AimFire end,
    function(v) CFG.AimFire = v end)
toggleRow("invisible", function() return CFG.Invisible end,
    function(v)
        CFG.Invisible = v
        applyInvis(LP.Character)
    end)
toggleRow("team check", function() return CFG.TeamCheck end,
    function(v) CFG.TeamCheck = v end)
toggleRow("wall check", function() return CFG.WallCheck end,
    function(v) CFG.WallCheck = v end)
toggleRow("npc targets", function() return CFG.NPCs end,
    function(v) CFG.NPCs = v end)

-- input
table.insert(conns, UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.ToggleKey then
        CFG.Aimbot = not CFG.Aimbot
        refreshAll()
    elseif input.KeyCode == CFG.MenuKey then
        frame.Visible = not frame.Visible
    end
end))

-- main loop (after the game's camera scripts so nothing overwrites the aim)
RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value, function()
    local cam = Workspace.CurrentCamera
    if not cam then return end

    local now = os.clock()
    if now - lastScan > 0.2 then
        scan()
        lastScan = now
    end
    if CFG.AimFire and now - lastAmmo > 0.05 then
        pinAmmo()
        lastAmmo = now
    end

    ring.Size = UDim2.fromOffset(CFG.FOV * 2, CFG.FOV * 2)
    ring.Visible = CFG.FOVEnabled

    local wantSilent = CFG.AimKill or (CFG.Silent and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
    local wantAim = CFG.Aimbot and (not CFG.HoldMouse2 or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))

    local tgt = nil
    if wantSilent or wantAim then
        tgt = pickTarget()
    end

    silentTarget = wantSilent and tgt or nil

    if wantAim and tgt then
        local goal = CFrame.lookAt(cam.CFrame.Position, tgt)
        cam.CFrame = cam.CFrame:Lerp(goal, 1 - CFG.Smoothing)
    end
end)

-- unload
if getgenv then
    getgenv().__uaim_unload = function()
        alive = false
        silentTarget = nil
        RunService:UnbindFromRenderStep(BIND)
        for _, c in ipairs(conns) do c:Disconnect() end
        CFG.Invisible = false
        applyInvis(LP.Character)
        gui:Destroy()
        ringGui:Destroy()
    end
end

refreshAll()
