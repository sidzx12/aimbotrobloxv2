-- uaim v7 | menu + scroll + sliders + reopen pill + fov + lock + invisible + aim part + silent + aimkill + aimfire + speed + jump + fly(F) | delta / any luau executor
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
    FOVEnabled = true,
    FOV = 150,
    FOVMin = 40,
    FOVMax = 600,
    AimPart = "head",       -- "head" | "neck" | "body"
    Silent = false,         -- redirect shots while mouse1 held
    AimKill = false,        -- silent aim, no key needed
    AimFire = false,        -- pin ammo/clip values on held tool
    Invisible = false,
    TeamCheck = true,
    NPCs = true,
    WallCheck = false,
    Speed = false,
    WalkSpeed = 16,
    WalkMin = 16,
    WalkMax = 200,
    Jump = false,
    JumpPower = 50,
    JumpMin = 50,
    JumpMax = 300,
    Fly = false,            -- feature gate (menu)
    FlySpeed = 60,
    FlyMin = 10,
    FlyMax = 300,
    FlyKey = Enum.KeyCode.F, -- starts/stops flying while fly is on
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
local ammoVal = {}
local ammoAttr = {}
local origWalk, origJump = 16, 50
local flying = false

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
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        origWalk = hum.WalkSpeed
        origJump = hum.JumpPower
    end
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

-- nearest enemy inside the fov circle
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

-- silent aim hook (inert after unload via alive flag)
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

-- movement: speed, jump, fly
local function getHumRoot()
    local char = LP.Character
    if not char then return nil, nil end
    return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function movementStep()
    local hum, root = getHumRoot()
    if not hum or hum.Health <= 0 then return end

    if CFG.Speed then
        hum.WalkSpeed = CFG.WalkSpeed
    end
    if CFG.Jump then
        hum.UseJumpPower = true
        hum.JumpPower = CFG.JumpPower
    end

    -- fly only when the fly feature is on AND the fly key has started it
    if CFG.Fly and flying and root then
        local move = hum.MoveDirection
        local vy = 0
        if UIS:IsKeyDown(Enum.KeyCode.Space) then
            vy = 1
        elseif UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
            vy = -1
        end
        root.AssemblyLinearVelocity = Vector3.new(
            move.X * CFG.FlySpeed,
            vy * CFG.FlySpeed,
            move.Z * CFG.FlySpeed
        )
    end
end

table.insert(conns, RunService.Heartbeat:Connect(movementStep))

-- menu gui
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

-- fov ring (gui, resizes live)
local ringGui = Instance.new("ScreenGui")
ringGui.Name = "uaim_fov"
ringGui.IgnoreGuiInset = true
ringGui.ResetOnSpawn = false
ringGui.DisplayOrder = 998
ringGui.Parent = gui.Parent

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

local frame = Instance.new("Frame")
frame.Name = "main"
frame.Size = UDim2.fromOffset(250, 440)
frame.Position = UDim2.fromOffset(40, 120)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BorderSizePixel = 0
frame.Visible = true
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -28, 0, 28)
title.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
title.BorderSizePixel = 0
title.Text = "  uaim  (drag here)"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.Code
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.Active = true
title.Parent = frame

-- manual drag from the title bar (so sliders and scrolling don't fight it)
do
    local dragging, startMouse, startPos
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            startMouse = input.Position
            startPos = frame.Position
        end
    end)
    table.insert(conns, UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - startMouse
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    table.insert(conns, UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))
end

-- reopen pill, shown when the menu is tucked away
local pill = Instance.new("TextButton")
pill.Size = UDim2.fromOffset(64, 24)
pill.Position = UDim2.fromOffset(10, 10)
pill.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
pill.BorderSizePixel = 0
pill.Text = "uaim"
pill.Font = Enum.Font.Code
pill.TextSize = 14
pill.TextColor3 = Color3.fromRGB(240, 240, 240)
pill.Visible = false
pill.Parent = gui

local function setMenu(v)
    frame.Visible = v
    pill.Visible = not v
end

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
hideBtn.MouseButton1Click:Connect(function() setMenu(false) end)
pill.MouseButton1Click:Connect(function() setMenu(true) end)

-- scrolling body
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.new(0, 0, 0, 32)
body.Size = UDim2.new(1, 0, 1, -36)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 2)
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = body

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
    local b = mkBtn(body, "")
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
    local b = mkBtn(body, "")
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

-- slider row: drag the track, or click anywhere on it
local function sliderRow(label, get, set, min, max, step, fmt)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -12, 0, 36)
    f.BackgroundTransparency = 1
    f.Parent = body

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = Color3.fromRGB(230, 230, 230)
    lbl.Parent = f

    local track = Instance.new("Frame")
    track.Position = UDim2.new(0, 0, 0, 22)
    track.Size = UDim2.new(1, 0, 0, 8)
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    track.BorderSizePixel = 0
    track.Active = true
    track.Parent = f

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(90, 140, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track

    local dragging = false

    local function refresh()
        local v = get()
        lbl.Text = label .. " " .. fmt(v)
        fill.Size = UDim2.new(math.clamp((v - min) / (max - min), 0, 1), 0, 1, 0)
    end

    local function setFromX(x)
        local r = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local v = min + r * (max - min)
        v = math.floor(v / step + 0.5) * step
        set(math.clamp(v, min, max))
        refreshAll()
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    table.insert(conns, UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            setFromX(input.Position.X)
        end
    end))
    table.insert(conns, UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))

    table.insert(refreshers, refresh)
    refresh()
end

toggleRow("aimbot", function() return CFG.Aimbot end,
    function(v) CFG.Aimbot = v end)
toggleRow("fov circle", function() return CFG.FOVEnabled end,
    function(v) CFG.FOVEnabled = v end)
sliderRow("fov size", function() return CFG.FOV end,
    function(v) CFG.FOV = v end, CFG.FOVMin, CFG.FOVMax, 10,
    function(v) return tostring(math.floor(v)) end)
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
toggleRow("speed", function() return CFG.Speed end,
    function(v)
        CFG.Speed = v
        if not v then
            local hum = getHumRoot()
            if hum then hum.WalkSpeed = origWalk end
        end
    end)
sliderRow("walk speed", function() return CFG.WalkSpeed end,
    function(v) CFG.WalkSpeed = v end, CFG.WalkMin, CFG.WalkMax, 2,
    function(v) return tostring(math.floor(v)) end)
toggleRow("jump", function() return CFG.Jump end,
    function(v)
        CFG.Jump = v
        if not v then
            local hum = getHumRoot()
            if hum then hum.JumpPower = origJump end
        end
    end)
sliderRow("jump power", function() return CFG.JumpPower end,
    function(v) CFG.JumpPower = v end, CFG.JumpMin, CFG.JumpMax, 5,
    function(v) return tostring(math.floor(v)) end)
toggleRow("fly", function() return CFG.Fly end,
    function(v)
        CFG.Fly = v
        if not v then flying = false end
    end)
-- fly key status: shows whether flying, and can also start/stop it
do
    local b = mkBtn(body, "")
    local function refresh()
        b.Text = "fly key [F]: " .. (flying and "flying" or "landed")
    end
    b.MouseButton1Click:Connect(function()
        if CFG.Fly then flying = not flying end
        refreshAll()
    end)
    table.insert(refreshers, refresh)
    refresh()
end
sliderRow("fly speed", function() return CFG.FlySpeed end,
    function(v) CFG.FlySpeed = v end, CFG.FlyMin, CFG.FlyMax, 5,
    function(v) return tostring(math.floor(v)) end)

-- input
table.insert(conns, UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.ToggleKey then
        CFG.Aimbot = not CFG.Aimbot
        refreshAll()
    elseif input.KeyCode == CFG.MenuKey then
        setMenu(not frame.Visible)
    elseif input.KeyCode == CFG.FlyKey then
        if CFG.Fly then
            flying = not flying
            refreshAll()
        end
    end
end))

-- main loop (after the game's camera scripts so nothing overwrites the lock)
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

    -- features only arm once aimbot and fov are both on
    local armed = CFG.Aimbot and CFG.FOVEnabled
    local tgt = armed and pickTarget() or nil

    local silentOn = tgt ~= nil and (CFG.AimKill
        or (CFG.Silent and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)))
    silentTarget = silentOn and tgt or nil

    -- lock straight onto the nearest enemy in fov (no smoothing).
    -- silent/aimkill redirect the shot instead of moving the camera.
    if tgt and not silentOn then
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, tgt)
    end
end)

-- unload
if getgenv then
    getgenv().__uaim_unload = function()
        alive = false
        silentTarget = nil
        flying = false
        RunService:UnbindFromRenderStep(BIND)
        for _, c in ipairs(conns) do c:Disconnect() end
        CFG.Invisible = false
        CFG.Fly = false
        CFG.Speed = false
        CFG.Jump = false
        applyInvis(LP.Character)
        local hum = getHumRoot()
        if hum then
            hum.WalkSpeed = origWalk
            hum.JumpPower = origJump
        end
        gui:Destroy()
        ringGui:Destroy()
    end
end

refreshAll()
