-- uaim v25 | sideways menu + touch + reopen pill + fov + lock + invisible + aim part + silent + aimkill + aimfire + fire delay + magnet + body aim + speed + jump + fly(F) + esp box/line/bold name + esp color/rgb + esp target + chams(hologram) + chams color/rgb + chams target + auto kill | delta / any luau executor
if getgenv and getgenv().__uaim_unload then
    pcall(getgenv().__uaim_unload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local VIM = game:GetService("VirtualInputManager")

local CFG = {
    Aimbot = true,
    FOVEnabled = true,
    FOV = 150,
    FOVMin = 40,
    FOVMax = 600,
    AimPart = "head",       -- "head" | "neck" | "body"
    Silent = false,         -- redirect shots while mouse1 held
    AimKill = false,        -- silent aim, no key needed, fires on delay
    AimFire = false,        -- teleport behind fov enemy + auto fire, no camera
    FireDelay = 0.3,        -- seconds between shots (aimfire + auto kill + aimkill)
    FireMin = 0.1,
    FireMax = 1.0,
    Magnet = false,         -- while mouse1 held, redirect shot to nearest enemy in radius
    MagnetRadius = 90,      -- pixels from crosshair
    MagnetMin = 20,
    MagnetMax = 300,
    BodyAim = false,        -- torso only, for lock + magnet + fire (ignores head)
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
    FlyKey = Enum.KeyCode.F,
    ESPBox = false,
    ESPLine = false,
    ESPName = false,
    ESPColor = "red",       -- name from COLOR_ORDER
    ESPRGB = false,         -- cycles hue every frame
    ESPTarget = "enemies",  -- "enemies" | "friends" | "all"
    Chams = false,          -- hologram highlight through walls
    ChamsColor = "yellow",  -- name from COLOR_ORDER
    ChamsRGB = false,       -- cycles hue every frame
    ChamsTarget = "enemies",-- "enemies" | "friends" | "all"
    AutoKill = false,       -- teleport behind nearest enemy, aim camera, fire
    MenuKey = Enum.KeyCode.RightShift,
    ToggleKey = Enum.KeyCode.RightAlt,
}

local LP = Players.LocalPlayer
local BIND = "uaim_loop"
local alive = true
local conns = {}
local refreshers = {}
local targets = {}      -- combat targets (enemies by team/npc rules)
local visList = {}      -- visual targets: { hum, model, kind }
local lastScan = 0
local lastFire = 0
local lastTeleport = 0
local silentTarget = nil
local origWalk, origJump = 16, 50
local flying = false
local espCache = {}
local chamCache = {}
local lastRenderErr = nil

local CORNERS = {
    Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1),
    Vector3.new(-1, 1, -1),  Vector3.new(-1, 1, 1),
    Vector3.new(1, -1, -1),  Vector3.new(1, -1, 1),
    Vector3.new(1, 1, -1),   Vector3.new(1, 1, 1),
}

-- shared color presets for esp and chams, in cycle order.
-- npc/bot is always pink and ignores preset + rgb.
local COLOR_ORDER = { "red", "orange", "yellow", "green", "cyan", "blue", "magenta", "white" }
local COLORS = {
    red = Color3.fromRGB(255, 80, 80),
    orange = Color3.fromRGB(255, 150, 60),
    yellow = Color3.fromRGB(255, 230, 80),
    green = Color3.fromRGB(90, 255, 120),
    cyan = Color3.fromRGB(80, 230, 255),
    blue = Color3.fromRGB(90, 140, 255),
    magenta = Color3.fromRGB(255, 90, 230),
    white = Color3.fromRGB(255, 255, 255),
}
local NPC_PINK = Color3.fromRGB(255, 105, 180)
local VIS_TARGETS = { "enemies", "friends", "all" }

-- color for a model. npcs are always pink; players use the chosen preset or rgb cycle.
local function colorFor(kind, useRgb, presetName)
    if kind == "npc" then return NPC_PINK end
    if useRgb then
        return Color3.fromHSV((os.clock() * 0.4) % 1, 1, 1)
    end
    return COLORS[presetName] or COLORS.white
end

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

-- body parts
local function rootOf(model)
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
end

local function torsoOf(model)
    return model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("HumanoidRootPart")
end

-- one aim position for the whole script. body aim forces the torso
local function aimPos(model)
    if CFG.BodyAim then
        local torso = torsoOf(model)
        return torso and torso.Position or nil
    end

    local head = model:FindFirstChild("Head")
    local torso = torsoOf(model)

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

-- friend = on your team or on your friends list
local function isFriend(p)
    if LP.Team and p.Team == LP.Team then return true end
    local ok, res = pcall(function() return LP:IsFriendsWith(p.UserId) end)
    return ok and res
end

-- kind for visuals: "npc", "enemy", "friend", or nil for yourself
local function kindOf(model)
    local p = Players:GetPlayerFromCharacter(model)
    if not p then return "npc" end
    if p == LP then return nil end
    if isFriend(p) then return "friend" end
    return "enemy"
end

-- does a target setting ("enemies" | "friends" | "all") include this kind
local function visAllowed(kind, setting)
    if setting == "all" then return true end
    if setting == "enemies" then return kind == "enemy" or kind == "npc" end
    return kind == "friend"
end

-- combat targeting
local function isEnemy(model)
    local p = Players:GetPlayerFromCharacter(model)
    if not p then return CFG.NPCs end
    if p == LP then return false end
    if CFG.TeamCheck and LP.Team and p.Team == LP.Team then return false end
    return true
end

local function scan()
    table.clear(targets)
    table.clear(visList)
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Humanoid") and d.Health > 0 then
            local m = d.Parent
            if m and m:IsA("Model") and m ~= LP.Character then
                local kind = kindOf(m)
                if kind then
                    table.insert(visList, { hum = d, model = m, kind = kind })
                end
                if isEnemy(m) then
                    table.insert(targets, { hum = d, model = m })
                end
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

-- nearest enemy inside the fov circle. returns aim position and the model
local function pickTarget()
    local cam = Workspace.CurrentCamera
    local center = cam.ViewportSize / 2
    local bestPos, bestModel, bestD = nil, nil, CFG.FOV

    for _, t in ipairs(targets) do
        if t.hum.Health > 0 and t.model.Parent then
            local pos = aimPos(t.model)
            if pos then
                local sp, on = cam:WorldToViewportPoint(pos)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d < bestD and visible(pos, t.model) then
                        bestPos, bestModel, bestD = pos, t.model, d
                    end
                end
            end
        end
    end
    return bestPos, bestModel
end

-- nearest enemy to the crosshair within the magnet radius, using the same aim position
local function pickMagnet()
    local cam = Workspace.CurrentCamera
    local center = cam.ViewportSize / 2
    local bestPos, bestD = nil, CFG.MagnetRadius

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

table.insert(conns, RunService.Heartbeat:Connect(function()
    local ok, err = pcall(movementStep)
    if not ok then warn("uaim move: " .. tostring(err)) end
end))

-- nearest enemy by world distance (used by auto kill)
local function nearestEnemy()
    local _, myRoot = getHumRoot()
    if not myRoot then return nil end
    local best, bestD = nil, math.huge
    for _, t in ipairs(targets) do
        local r = rootOf(t.model)
        if t.hum.Health > 0 and r and t.model.Parent then
            local d = (r.Position - myRoot.Position).Magnitude
            if d < bestD then best, bestD = t, d end
        end
    end
    return best
end

-- fires once per fire delay. tool -> Activate, else mouse1 click fallback
-- for weapons that read MouseButton1 (most non-tool guns).
local function fireOnce(now)
    if now - lastFire < CFG.FireDelay then return end
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    lastFire = now
    if tool then
        pcall(function() tool:Activate() end)
    else
        pcall(function()
            VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.02)
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
    end
end

-- shared by auto kill and aimfire: move 3 studs behind the enemy (throttled),
-- return the aim position. the camera is not touched here
local function teleportBehind(model, now)
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and myRoot and hum.Health > 0) then return nil end

    local r = rootOf(model)
    if not r or not r.Parent then return nil end

    local goal = aimPos(model)
    if not goal then return nil end

    if now - lastTeleport > 0.2 and (r.Position - myRoot.Position).Magnitude > 4 then
        pcall(function()
            char:PivotTo(r.CFrame * CFrame.new(0, 0, 3))
            myRoot.AssemblyLinearVelocity = Vector3.zero
        end)
        lastTeleport = now
    end
    return goal
end

-- esp (Drawing API). bold name = two draws offset by 1px
local function espFor(model)
    if not Drawing then return nil end
    local e = espCache[model]
    if e then return e end
    e = {
        box = Drawing.new("Square"),
        line = Drawing.new("Line"),
        name = Drawing.new("Text"),
        name2 = Drawing.new("Text"),
    }
    e.box.Thickness = 1
    e.box.Filled = false
    e.line.Thickness = 1

    e.name.Size = 14
    e.name.Center = true
    e.name.Outline = true
    e.name.Color = Color3.fromRGB(255, 255, 255)

    e.name2.Size = 14
    e.name2.Center = true
    e.name2.Outline = false
    e.name2.Color = Color3.fromRGB(255, 255, 255)

    espCache[model] = e
    return e
end

-- removes the drawings entirely, so nothing can stay on screen
local function destroyEsp(model)
    local e = espCache[model]
    if not e then return end
    pcall(function()
        e.box:Remove()
        e.line:Remove()
        e.name:Remove()
        e.name2:Remove()
    end)
    espCache[model] = nil
end

-- chams: a see-through hologram. a Highlight with a mostly transparent fill
-- and a soft outline, drawn through walls
local function updateCham(model, col)
    local h = chamCache[model]
    if not h then
        h = Instance.new("Highlight")
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillTransparency = 0.78     -- mostly see-through, hologram look
        h.OutlineTransparency = 0.25  -- soft edge line
        chamCache[model] = h
    end
    h.Adornee = model
    h.Parent = model
    h.Enabled = true
    h.FillColor = col
    h.OutlineColor = col
end

-- removes the highlight instance entirely
local function destroyCham(model)
    local h = chamCache[model]
    if h then
        pcall(function() h:Destroy() end)
    end
    chamCache[model] = nil
end

-- returns minX, minY, maxX, maxY of the model's box on screen, or nil
local function screenBox(m, cam)
    local okBB, cf, size = pcall(m.GetBoundingBox, m)
    if not okBB or not cf or not size then return nil end
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, s in ipairs(CORNERS) do
        local p = cf * Vector3.new(s.X * hx, s.Y * hy, s.Z * hz)
        local sp = cam:WorldToViewportPoint(p)
        if sp.Z <= 0 then return nil end
        minX = math.min(minX, sp.X)
        minY = math.min(minY, sp.Y)
        maxX = math.max(maxX, sp.X)
        maxY = math.max(maxY, sp.Y)
    end
    return minX, minY, maxX, maxY
end

-- draws esp and chams for visList. anything not wanted is destroyed, not just hidden
local function updateVisuals(cam)
    local espAny = CFG.ESPBox or CFG.ESPLine or CFG.ESPName
    local keepEsp, keepCham = {}, {}

    for _, v in ipairs(visList) do
        local m = v.model

        -- chams: only when chams is on AND this kind matches chams target.
        -- npc is always pink via colorFor.
        if CFG.Chams and visAllowed(v.kind, CFG.ChamsTarget) then
            keepCham[m] = true
            local okC, errC = pcall(updateCham, m, colorFor(v.kind, CFG.ChamsRGB, CFG.ChamsColor))
            if not okC then warn("uaim chams: " .. tostring(errC)) end
        end

        -- esp: only when at least one esp box/line/name is on AND this kind matches esp target
        if Drawing and espAny and visAllowed(v.kind, CFG.ESPTarget)
            and v.hum.Health > 0 and m.Parent then
            local minX, minY, maxX, maxY = screenBox(m, cam)
            if minX then
                keepEsp[m] = true
                local e = espFor(m)
                local col = colorFor(v.kind, CFG.ESPRGB, CFG.ESPColor)
                local midX = (minX + maxX) / 2

                e.box.Visible = CFG.ESPBox
                e.box.Color = col
                e.box.Position = Vector2.new(minX, minY)
                e.box.Size = Vector2.new(maxX - minX, maxY - minY)

                e.line.Visible = CFG.ESPLine
                e.line.Color = col
                e.line.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                e.line.To = Vector2.new(midX, maxY)

                local p = Players:GetPlayerFromCharacter(m)
                local okPiv, piv = pcall(function() return m:GetPivot().Position end)
                local dist = okPiv and math.floor((cam.CFrame.Position - piv).Magnitude) or 0
                local text = (p and p.Name or m.Name) .. " [" .. dist .. "]"
                local namePos = Vector2.new(midX, minY - 16)

                e.name.Visible = CFG.ESPName
                e.name.Text = text
                e.name.Color = col
                e.name.Position = namePos

                e.name2.Visible = CFG.ESPName
                e.name2.Text = text
                e.name2.Color = col
                e.name2.Position = namePos + Vector2.new(1, 0)
            end
        end
    end

    -- sweep: anything not wanted this frame is removed completely
    for m in pairs(espCache) do
        if not keepEsp[m] then destroyEsp(m) end
    end
    for m in pairs(chamCache) do
        if not keepCham[m] then destroyCham(m) end
    end
end

-- menu gui
local gui = Instance.new("ScreenGui")
gui.Name = "uaim_menu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true
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
frame.Size = UDim2.fromOffset(300, 300)
frame.Position = UDim2.fromOffset(40, 120)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
frame.BorderSizePixel = 0
frame.Visible = true
frame.Parent = gui

-- title bar is a button so the executor reliably registers the press
local title = Instance.new("TextButton")
title.Size = UDim2.new(1, -28, 0, 28)
title.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
title.BorderSizePixel = 0
title.AutoButtonColor = false
title.Text = "  uaim  (drag here)"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.Code
title.TextSize = 15
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.Parent = frame

-- pointer tracking for touch and mouse
local pointerPos = UIS:GetMouseLocation()
local pointerDown = false
local dragging = false
local dragOffset = Vector2.new(0, 0)
local activeSlider = nil

local function inTitle(p)
    local a, s = title.AbsolutePosition, title.AbsoluteSize
    return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

-- start a drag from the press itself, not a delayed button event
local function beginDrag()
    if inTitle(pointerPos) then
        dragging = true
        dragOffset = pointerPos - frame.AbsolutePosition
    end
end

table.insert(conns, UIS.TouchStarted:Connect(function(touch)
    pointerPos = Vector2.new(touch.Position.X, touch.Position.Y)
    pointerDown = true
    beginDrag()
end))
table.insert(conns, UIS.TouchMoved:Connect(function(touch)
    pointerPos = Vector2.new(touch.Position.X, touch.Position.Y)
end))
table.insert(conns, UIS.TouchEnded:Connect(function()
    pointerDown = false
end))
table.insert(conns, UIS.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        pointerPos = Vector2.new(input.Position.X, input.Position.Y)
    end
end))
table.insert(conns, UIS.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        pointerPos = Vector2.new(input.Position.X, input.Position.Y)
        beginDrag()
    end
end))

table.insert(conns, RunService.RenderStepped:Connect(function()
    local held = pointerDown or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)

    if dragging then
        if held then
            local vs = Workspace.CurrentCamera.ViewportSize
            local np = pointerPos - dragOffset
            local x = math.clamp(np.X, 0, math.max(0, vs.X - frame.AbsoluteSize.X))
            local y = math.clamp(np.Y, 0, math.max(0, vs.Y - frame.AbsoluteSize.Y))
            frame.Position = UDim2.fromOffset(x, y)
        else
            dragging = false
        end
    end

    if activeSlider then
        if held then
            activeSlider(pointerPos.X)
        else
            activeSlider = nil
        end
    end
end))

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

-- sideways body: columns scroll left/right, nothing scrolls down
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.new(0, 0, 0, 32)
body.Size = UDim2.new(1, 0, 1, -36)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollingDirection = Enum.ScrollingDirection.X
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.X
body.Parent = frame

local strip = Instance.new("UIListLayout")
strip.FillDirection = Enum.FillDirection.Horizontal
strip.Padding = UDim.new(0, 6)
strip.SortOrder = Enum.SortOrder.LayoutOrder
strip.Parent = body

local stripPad = Instance.new("UIPadding")
stripPad.PaddingLeft = UDim.new(0, 4)
stripPad.PaddingRight = UDim.new(0, 4)
stripPad.Parent = body

local curCol = nil

local function newCol(name)
    local c = Instance.new("Frame")
    c.Size = UDim2.new(0, 140, 1, 0)
    c.BackgroundTransparency = 1
    c.Parent = body

    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 4)
    l.HorizontalAlignment = Enum.HorizontalAlignment.Center
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = c

    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1, -8, 0, 16)
    h.BackgroundTransparency = 1
    h.Text = name
    h.Font = Enum.Font.Code
    h.TextSize = 13
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.TextColor3 = Color3.fromRGB(140, 160, 220)
    h.Parent = c

    curCol = c
end

local function mkBtn(text)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 26)
    b.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
    b.BorderSizePixel = 0
    b.TextColor3 = Color3.fromRGB(230, 230, 230)
    b.Font = Enum.Font.Code
    b.TextSize = 13
    b.Text = text
    b.Parent = curCol
    return b
end

local function toggleRow(label, get, set)
    local b = mkBtn("")
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
    local b = mkBtn("")
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

-- slider row: press the track, then drag. fed by pointerPos every frame
local function sliderRow(label, get, set, min, max, step, fmt)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -8, 0, 36)
    f.BackgroundTransparency = 1
    f.Parent = curCol

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = Color3.fromRGB(230, 230, 230)
    lbl.Parent = f

    local track = Instance.new("TextButton")
    track.Position = UDim2.new(0, 0, 0, 22)
    track.Size = UDim2.new(1, 0, 0, 8)
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    track.BorderSizePixel = 0
    track.AutoButtonColor = false
    track.Text = ""
    track.Parent = f

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(90, 140, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track

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

    track.MouseButton1Down:Connect(function()
        activeSlider = setFromX
        setFromX(pointerPos.X)
    end)

    table.insert(refreshers, refresh)
    refresh()
end

local function fmtInt(v) return tostring(math.floor(v)) end
local function fmtSec(v) return string.format("%.2f", v) end

-- column: aim
newCol("aim")
toggleRow("aimbot", function() return CFG.Aimbot end,
    function(v) CFG.Aimbot = v end)
toggleRow("fov circle", function() return CFG.FOVEnabled end,
    function(v) CFG.FOVEnabled = v end)
sliderRow("fov size", function() return CFG.FOV end,
    function(v) CFG.FOV = v end, CFG.FOVMin, CFG.FOVMax, 10, fmtInt)
cycleRow("aim part", { "head", "neck", "body" },
    function() return CFG.AimPart end,
    function(v) CFG.AimPart = v end)
toggleRow("silent aim", function() return CFG.Silent end,
    function(v) CFG.Silent = v end)
toggleRow("aimkill", function() return CFG.AimKill end,
    function(v) CFG.AimKill = v end)
toggleRow("aimfire", function() return CFG.AimFire end,
    function(v) CFG.AimFire = v end)
sliderRow("fire delay", function() return CFG.FireDelay end,
    function(v) CFG.FireDelay = v end, CFG.FireMin, CFG.FireMax, 0.05, fmtSec)

-- column: magnet
newCol("magnet")
toggleRow("magnet", function() return CFG.Magnet end,
    function(v) CFG.Magnet = v end)
sliderRow("magnet radius", function() return CFG.MagnetRadius end,
    function(v) CFG.MagnetRadius = v end, CFG.MagnetMin, CFG.MagnetMax, 10, fmtInt)
toggleRow("body aim", function() return CFG.BodyAim end,
    function(v) CFG.BodyAim = v end)

-- column: esp (its own target and color)
newCol("esp")
toggleRow("invisible", function() return CFG.Invisible end,
    function(v)
        CFG.Invisible = v
        applyInvis(LP.Character)
    end)
cycleRow("esp target", VIS_TARGETS,
    function() return CFG.ESPTarget end,
    function(v) CFG.ESPTarget = v end)
toggleRow("esp box", function() return CFG.ESPBox end,
    function(v) CFG.ESPBox = v end)
toggleRow("esp line", function() return CFG.ESPLine end,
    function(v) CFG.ESPLine = v end)
toggleRow("esp name", function() return CFG.ESPName end,
    function(v) CFG.ESPName = v end)
cycleRow("esp color", COLOR_ORDER,
    function() return CFG.ESPColor end,
    function(v) CFG.ESPColor = v end)
toggleRow("esp rgb", function() return CFG.ESPRGB end,
    function(v) CFG.ESPRGB = v end)

-- column: chams (its own target, color, rgb)
newCol("chams")
toggleRow("chams", function() return CFG.Chams end,
    function(v) CFG.Chams = v end)
cycleRow("chams target", VIS_TARGETS,
    function() return CFG.ChamsTarget end,
    function(v) CFG.ChamsTarget = v end)
cycleRow("chams color", COLOR_ORDER,
    function() return CFG.ChamsColor end,
    function(v) CFG.ChamsColor = v end)
toggleRow("chams rgb", function() return CFG.ChamsRGB end,
    function(v) CFG.ChamsRGB = v end)

-- column: kill
newCol("kill")
toggleRow("auto kill", function() return CFG.AutoKill end,
    function(v) CFG.AutoKill = v end)

-- column: move
newCol("move")
toggleRow("speed", function() return CFG.Speed end,
    function(v)
        CFG.Speed = v
        if not v then
            local hum = getHumRoot()
            if hum then hum.WalkSpeed = origWalk end
        end
    end)
sliderRow("walk speed", function() return CFG.WalkSpeed end,
    function(v) CFG.WalkSpeed = v end, CFG.WalkMin, CFG.WalkMax, 2, fmtInt)
toggleRow("jump", function() return CFG.Jump end,
    function(v)
        CFG.Jump = v
        if not v then
            local hum = getHumRoot()
            if hum then hum.JumpPower = origJump end
        end
    end)
sliderRow("jump power", function() return CFG.JumpPower end,
    function(v) CFG.JumpPower = v end, CFG.JumpMin, CFG.JumpMax, 5, fmtInt)
toggleRow("fly", function() return CFG.Fly end,
    function(v)
        CFG.Fly = v
        if not v then flying = false end
    end)
do
    local b = mkBtn("")
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
    function(v) CFG.FlySpeed = v end, CFG.FlyMin, CFG.FlyMax, 5, fmtInt)

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

-- auto kill: teleport behind nearest enemy, aim camera at them, fire on delay
local function autoKillStep(now)
    local t = nearestEnemy()
    if not t then return nil end
    local goal = teleportBehind(t.model, now)
    if goal then fireOnce(now) end
    return goal
end

-- one render frame. every mode is evaluated; early return only when the mode
-- owns the camera and would fight another mode's camera write.
local function renderStep()
    local cam = Workspace.CurrentCamera
    if not cam then return end

    local now = os.clock()
    if now - lastScan > 0.2 then
        scan()
        lastScan = now
    end

    ring.Size = UDim2.fromOffset(CFG.FOV * 2, CFG.FOV * 2)
    ring.Visible = CFG.FOVEnabled

    -- autokill: teleport + fire + camera. owns the camera, so it runs alone.
    if CFG.AutoKill then
        local ok, res = pcall(autoKillStep, now)
        if ok and res then
            if (res - cam.CFrame.Position).Magnitude > 0.1 then
                cam.CFrame = CFrame.lookAt(cam.CFrame.Position, res)
            end
            silentTarget = res
        elseif not ok then
            warn("uaim autokill: " .. tostring(res))
        end
        return
    end

    -- aimfire: teleport + fire, camera left alone
    if CFG.AimFire and CFG.FOVEnabled then
        local _, tgtModel = pickTarget()
        if tgtModel then
            local ok, res = pcall(teleportBehind, tgtModel, now)
            if ok and res then
                fireOnce(now)
            elseif not ok then
                warn("uaim aimfire: " .. tostring(res))
            end
        end
    end

    -- magnet: only redirects the shot while mouse1 is held, no camera touch.
    -- does not return, so aimbot lock below still gets a shot at the camera
    -- when magnet isn't currently engaged.
    local magnetTarget = nil
    if CFG.Magnet and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        magnetTarget = pickMagnet()
    end

    -- aimbot lock + silent/aimkill
    local lockTarget = nil
    if CFG.Aimbot and CFG.FOVEnabled then
        lockTarget = pickTarget()
    end

    -- silent redirect: aimkill fires without any mouse input; silent needs mouse1.
    -- magnet, if engaged, wins over the lock for the shot's redirect point.
    local redirect = magnetTarget or lockTarget
    local silentWanted = redirect ~= nil and (
        CFG.AimKill
        or magnetTarget ~= nil
        or (CFG.Silent and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
    )
    silentTarget = silentWanted and redirect or nil

    -- aimkill fires on its own on the fire delay, no tool/key required beyond holding a tool
    if CFG.AimKill and redirect then
        pcall(fireOnce, now)
    end

    -- camera lock: skip when magnet is engaged this frame (would fight the shot),
    -- skip when silent-only (silent/aimkill don't move the camera).
    local silentOnly = CFG.AimKill or CFG.Silent
    if lockTarget and not silentOnly and not magnetTarget then
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, lockTarget)
    end
end

local function runVisuals()
    local cam = Workspace.CurrentCamera
    if cam then
        local ok, err = pcall(updateVisuals, cam)
        if not ok then warn("uaim visuals: " .. tostring(err)) end
    end
end

RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value, function()
    local ok, err = xpcall(renderStep, debug.traceback)
    if not ok and err ~= lastRenderErr then
        lastRenderErr = err
        warn("uaim render: " .. tostring(err))
    end
    runVisuals()
end)

-- unload
if getgenv then
    getgenv().__uaim_unload = function()
        alive = false
        silentTarget = nil
        activeSlider = nil
        dragging = false
        flying = false
        RunService:UnbindFromRenderStep(BIND)
        for _, c in ipairs(conns) do c:Disconnect() end
        for m in pairs(espCache) do destroyEsp(m) end
        for m in pairs(chamCache) do destroyCham(m) end
        CFG.Invisible = false
        CFG.Fly = false
        CFG.Speed = false
        CFG.Jump = false
        CFG.AutoKill = false
        CFG.AimFire = false
        CFG.Magnet = false
        CFG.BodyAim = false
        CFG.Chams = false
        CFG.ChamsRGB = false
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
