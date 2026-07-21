repeat task.wait() until game:IsLoaded()

if getgenv()._Hi then
    local old = getgenv()._Hi
    if old.Connections then
        for _, c in pairs(old.Connections) do
            pcall(function() c:Disconnect() end)
        end
    end
    if old.Window then pcall(function() old.Window:Destroy() end) end
    if old.HookRestore then pcall(old.HookRestore) end
    if old.CaptureUnhook then pcall(old.CaptureUnhook) end
    getgenv()._Hi = nil
end

getgenv()._Hi = { Connections = {}, Window = nil, HookRestore = nil, CaptureUnhook = nil }
local _GHi = getgenv()._Hi
local function Track(c)
    local C = _GHi.Connections
    C[#C + 1] = c
    return c
end

local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local VIS = game:GetService("VirtualInputManager")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Alive = workspace.Alive

local Aerodynamic = false
local Aerodynamic_Time = tick()

local CapturedRemote, CapturedUUID, CapturedHash = nil, nil, nil
local RemoteCaptured = false
local CapOldNC, CapOldFS = nil, nil

local CachedCF, CachedEvts, CachedMouse = nil, nil, nil

local AutoSpamEnabled = false
local Parried = false
local Parries = 0
local CurrentBallId = nil

local Selected_Parry_Type = "Custom"
getgenv().Parry_Accuracy = getgenv().Parry_Accuracy or 0

--============================
-- Remote capture
--============================
local function CaptureUnhook()
    if CapOldNC then
        pcall(function() hookmetamethod(game, "__namecall", CapOldNC) end)
        CapOldNC = nil
    end
    if CapOldFS then
        pcall(function()
            local r = Instance.new("RemoteEvent")
            hookfunction(r.FireServer, CapOldFS)
            r:Destroy()
        end)
        CapOldFS = nil
    end
end
_GHi.CaptureUnhook = CaptureUnhook

local function MatchCapture(a)
    return #a >= 7 and type(a[1]) == "string" and type(a[2]) == "string"
        and type(a[3]) == "number" and typeof(a[4]) == "CFrame"
end

local function OnCapture(remote, a)
    if RemoteCaptured then return end
    CapturedUUID, CapturedHash, CapturedRemote = a[1], a[2], remote
    RemoteCaptured = true
    task.defer(CaptureUnhook)
    warn("[Hi] Remote captured! Hash: " .. CapturedHash)
end

local function InstallCaptureHooks()
    if RemoteCaptured or CapOldNC then return end

    CapOldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if not RemoteCaptured and getnamecallmethod() == "FireServer"
            and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
            local a = { ... }
            if MatchCapture(a) then OnCapture(self, a) end
        end
        return CapOldNC(self, ...)
    end))

    pcall(function()
        local r = Instance.new("RemoteEvent")
        CapOldFS = hookfunction(r.FireServer, newcclosure(function(self, ...)
            if not RemoteCaptured and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
                local a = { ... }
                if MatchCapture(a) then OnCapture(self, a) end
            end
            return CapOldFS(self, ...)
        end))
        r:Destroy()
    end)

    task.delay(0.5, function()
        if not RemoteCaptured then warn("[Hi] Capture timeout") end
        CaptureUnhook()
    end)
end

local function FireParry()
    if not RemoteCaptured then
        InstallCaptureHooks()
        VIS:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.delay(0.02, function() VIS:SendKeyEvent(false, Enum.KeyCode.F, false, game) end)
        return true
    end

    if not CapturedRemote or not CachedCF then return false end
    CapturedRemote:FireServer(CapturedUUID, CapturedHash, 0.05, CachedCF, CachedEvts, CachedMouse, false)
    return true
end

local function SpamFire()
    if not AutoSpamEnabled then return end
    if not RemoteCaptured or not CapturedRemote or not CachedCF then return end
    CapturedRemote:FireServer(CapturedUUID, CapturedHash, 0.05, CachedCF, CachedEvts, CachedMouse, false)
end

--============================
-- Targeting / CFrame builder
--============================
local function ClosestPlayer()
    local Best, BSq = nil, 1e36
    local PP = Player.Character and Player.Character.PrimaryPart
    if not PP then return nil end

    local myPos = PP.Position
    for _, E in ipairs(Alive:GetChildren()) do
        if tostring(E) ~= tostring(Player) and E.PrimaryPart then
            local d = (myPos - E.PrimaryPart.Position).Magnitude
            local dsq = d * d
            if dsq < BSq then
                BSq = dsq
                Best = E
            end
        end
    end
    return Best
end

local function BuildParryCFrame()
    local Cam = workspace.CurrentCamera
    if not Cam then return end

    local CF = Cam.CFrame
    local Ev = {}
    for _, v in ipairs(Alive:GetChildren()) do
        local pp = v.PrimaryPart
        if pp then Ev[tostring(v)] = Cam:WorldToScreenPoint(pp.Position) end
    end

    local ML
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        local VS = Cam.ViewportSize
        ML = { VS.X * 0.5, VS.Y * 0.5 }
    else
        local M = UserInputService:GetMouseLocation()
        ML = { M.X, M.Y }
    end

    local Root = Player.Character and Player.Character.PrimaryPart
    local ST = Selected_Parry_Type

    if ST == "Straight" then
        local A = ClosestPlayer()
        if A and A.PrimaryPart and Root then
            CF = CFrame.new(Root.Position, A.PrimaryPart.Position)
        end
    elseif ST == "Dot" then
        local A = ClosestPlayer()
        if A and A.PrimaryPart and Root then
            local ev = A.PrimaryPart.AssemblyLinearVelocity
            local d = (A.PrimaryPart.Position - Root.Position).Magnitude
            CF = CFrame.new(Root.Position, A.PrimaryPart.Position + ev * (d / 250))
        end
    elseif ST == "Backwards" then
        if Root then
            local B, R = -CF.LookVector, CF.RightVector
            local S = (math.random() - 0.5) * 1.2
            local Dir = Vector3.new(B.X + R.X * S, B.Y - 0.4, B.Z + R.Z * S)
            if Dir.Magnitude > 0.001 then Dir = Dir.Unit end
            CF = CFrame.new(Root.Position, Root.Position + Dir * 500)
        end
    elseif ST == "Random" then
        CF = CFrame.new(CF.Position, Vector3.new(math.random(-3000, 3000), math.random(-3000, 3000), math.random(-3000, 3000)))
    else
        CF = Cam.CFrame
    end

    CachedCF, CachedEvts, CachedMouse = CF, Ev, ML
end
Track(RunService.RenderStepped:Connect(BuildParryCFrame))

--============================
-- Optimized anti-curve + perfect timing engine
--============================
local CurveState = {
    PrevVel = nil,
    PrevDot = nil,
    HoldUntil = 0,
    LastParry = 0,
}

local function SafeUnit(v)
    local m = v.Magnitude
    if m < 1e-6 then return Vector3.zero, 0 end
    return v / m, m
end

local function PingSec()
    return math.clamp(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000, 0.01, 0.4)
end

local function IsLikelyCurve(ball, root)
    local vel = ball.AssemblyLinearVelocity
    local vDir, speed = SafeUnit(vel)
    if speed < 30 then
        CurveState.PrevVel = vel
        return false
    end

    local toMe = root.Position - ball.Position
    local dirToMe, dist = SafeUnit(toMe)
    if dist < 1 then
        CurveState.PrevVel = vel
        return false
    end

    local dot = dirToMe:Dot(vDir)

    -- never curve-block when projectile is not going toward us
    if dot <= 0.02 then
        CurveState.PrevVel = vel
        CurveState.PrevDot = dot
        return false
    end

    if CurveState.PrevVel then
        local prevDir = CurveState.PrevVel.Unit
        local align = math.clamp(prevDir:Dot(vDir), -1, 1)
        local turnAngle = math.deg(math.acos(align))

        local dynamicTurn = 16 + math.clamp(dist * 0.035, 0, 20)
        local dotDrop = CurveState.PrevDot and (CurveState.PrevDot - dot) or 0

        if turnAngle > dynamicTurn and dotDrop > 0.045 then
            CurveState.HoldUntil = tick() + 0.09
        end
    end

    CurveState.PrevVel = vel
    CurveState.PrevDot = dot

    if tick() < CurveState.HoldUntil then
        return true
    end

    return false
end

local function ShouldPerfectParry(ball, root)
    local now = tick()
    if (now - CurveState.LastParry) < 0.075 then
        return false
    end

    local vel = ball.AssemblyLinearVelocity
    local vDir, speed = SafeUnit(vel)
    if speed <= 1 then return false end

    local toMe = root.Position - ball.Position
    local dirToMe, dist = SafeUnit(toMe)
    if dist <= 0.5 then return false end

    local dot = dirToMe:Dot(vDir)
    if dot <= 0.04 then return false end

    if IsLikelyCurve(ball, root) then
        return false
    end

    -- time to impact (tti)
    local tti = dist / speed
    local p = PingSec()

    -- tight late window; user slider shifts this tiny bit
    local userShift = math.clamp(getgenv().Parry_Accuracy, 0, 6) * 0.0025
    local lead = (0.026 + p * 0.72) + userShift
    local slack = 0.018 + p * 0.24

    if tti <= (lead + slack) and tti >= (lead - 0.03) then
        CurveState.LastParry = now
        return true
    end

    return false
end

--============================
-- Game logic
--============================
local Auto_Parry = {}
local Connections_Manager = {}
local Closest_Entity = nil

function Auto_Parry.Get_Balls()
    local Balls = {}
    for _, obj in ipairs(workspace.Balls:GetChildren()) do
        if obj:GetAttribute("realBall") then
            obj.CanCollide = false
            Balls[#Balls + 1] = obj
        end
    end
    return Balls
end

function Auto_Parry.Get_Ball()
    for _, obj in ipairs(workspace.Balls:GetChildren()) do
        if obj:GetAttribute("realBall") then
            obj.CanCollide = false
            return obj
        end
    end
end

function Auto_Parry.Closest_Player()
    local Max_Distance = math.huge
    for _, Entity in ipairs(workspace.Alive:GetChildren()) do
        if tostring(Entity) ~= tostring(Player) and Entity.PrimaryPart then
            local Distance = Player:DistanceFromCharacter(Entity.PrimaryPart.Position)
            if Distance < Max_Distance then
                Max_Distance = Distance
                Closest_Entity = Entity
            end
        end
    end
    return Closest_Entity
end

function Auto_Parry:Get_Entity_Properties()
    Auto_Parry.Closest_Player()
    if not Closest_Entity or not Closest_Entity.PrimaryPart then return false end

    return {
        Velocity = Closest_Entity.PrimaryPart.AssemblyLinearVelocity,
        Direction = (Player.Character.PrimaryPart.Position - Closest_Entity.PrimaryPart.Position).Unit,
        Distance = (Player.Character.PrimaryPart.Position - Closest_Entity.PrimaryPart.Position).Magnitude,
    }
end

function Auto_Parry:Get_Ball_Properties()
    local Ball = Auto_Parry.Get_Ball()
    if not Ball then return false end

    local v = Ball.AssemblyLinearVelocity
    local bDir = (Player.Character.PrimaryPart.Position - Ball.Position).Unit
    local bDist = (Player.Character.PrimaryPart.Position - Ball.Position).Magnitude
    local bDot = bDir:Dot((v.Magnitude > 0 and v.Unit) or Vector3.zero)

    return {
        Velocity = v,
        Direction = bDir,
        Distance = bDist,
        Dot = bDot,
    }
end

function Auto_Parry:Spam_Service()
    local Ball = Auto_Parry.Get_Ball()
    if not Ball then return 0 end

    Auto_Parry.Closest_Player()
    if not Closest_Entity or not Closest_Entity.PrimaryPart then return 0 end

    local Velocity = Ball.AssemblyLinearVelocity
    local Speed = Velocity.Magnitude
    if Speed <= 0 then return 0 end

    local Direction = (Player.Character.PrimaryPart.Position - Ball.Position).Unit
    local Dot = Direction:Dot(Velocity.Unit)
    local Target_Position = Closest_Entity.PrimaryPart.Position
    local Target_Distance = Player:DistanceFromCharacter(Target_Position)

    local Maximum_Spam_Distance = self.Ping + math.min(Speed / 6.5, 95)
    if self.Entity_Properties and self.Entity_Properties.Distance > Maximum_Spam_Distance then return 0 end
    if self.Ball_Properties and self.Ball_Properties.Distance > Maximum_Spam_Distance then return 0 end
    if Target_Distance > Maximum_Spam_Distance then return 0 end

    local Maximum_Speed = 5 - math.min(Speed / 5, 5)
    local Maximum_Dot = math.clamp(Dot, -1, 0) * Maximum_Speed
    return Maximum_Spam_Distance - Maximum_Dot
end

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/RiqWhatever/Amfer/refs/heads/main/src/Amfer.lua"))()
local Window = Fluent:CreateWindow({
    Title = "Hi",
    SubTitle = "",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.RightControl,
})
_GHi.Window = Window

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "sword" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

Tabs.Main:AddToggle("Auto_Parry", {
    Title = "Auto Parry",
    Default = false,
    Callback = function(state)
        if state then
            Connections_Manager["Auto Parry"] = RunService.PreSimulation:Connect(function()
                local Character = Player.Character
                local Root = Character and Character.PrimaryPart
                if not Root or Parried then return end

                if Aerodynamic then
                    if tick() - Aerodynamic_Time > 0.6 then
                        Aerodynamic = false
                        Aerodynamic_Time = tick()
                    end
                    return
                end

                local Balls = Auto_Parry.Get_Balls()
                if #Balls == 0 then return end

                local pName = tostring(Player)
                for i = 1, #Balls do
                    local Ball = Balls[i]
                    if Ball and Ball.Parent and Ball:GetAttribute("target") == pName then
                        if ShouldPerfectParry(Ball, Root) then
                            Parried = true
                            CurrentBallId = Ball:GetDebugId()
                            FireParry()
                            Parries = Parries + 1
                            break
                        end
                    end
                end
            end)
        else
            if Connections_Manager["Auto Parry"] then
                Connections_Manager["Auto Parry"]:Disconnect()
                Connections_Manager["Auto Parry"] = nil
            end
        end
    end,
})

Tabs.Main:AddDropdown("Parry_Type", {
    Title = "Parry Type",
    Values = { "Custom", "Random", "Backwards", "Straight", "Dot" },
    Default = 1,
    Callback = function(Value)
        Selected_Parry_Type = Value
    end,
})

Tabs.Main:AddSlider("Parry_Accuracy", {
    Title = "Parry Accuracy",
    Default = 0,
    Min = 0,
    Max = 100,
    Rounding = 1,
    Callback = function(Value)
        getgenv().Parry_Accuracy = Value / 20
    end,
})

Tabs.Main:AddToggle("Auto_Spam", {
    Title = "Auto Spam",
    Default = false,
    Callback = function(state)
        AutoSpamEnabled = state
        if state then
            Connections_Manager["Auto Spam"] = RunService.PreSimulation:Connect(function()
                if not AutoSpamEnabled then return end
                if not Player.Character or not Player.Character.PrimaryPart then return end

                local Ball = Auto_Parry.Get_Ball()
                if not Ball then return end

                local Zoomies = Ball:FindFirstChild("zoomies")
                if not Zoomies then return end

                Auto_Parry.Closest_Player()
                if not Closest_Entity or not Closest_Entity.PrimaryPart then return end

                local Ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                local Ping_Threshold = math.clamp(Ping / 10, 10, 16)
                local Ball_Properties = Auto_Parry:Get_Ball_Properties()
                local Entity_Properties = Auto_Parry:Get_Entity_Properties()
                if not Entity_Properties or not Ball_Properties then return end

                local Spam_Accuracy = Auto_Parry.Spam_Service({
                    Ball_Properties = Ball_Properties,
                    Entity_Properties = Entity_Properties,
                    Ping = Ping_Threshold,
                })

                local Distance = Player:DistanceFromCharacter(Ball.Position)
                local Target_Position = Closest_Entity.PrimaryPart.Position
                local Target_Distance = Player:DistanceFromCharacter(Target_Position)

                if Target_Distance > Spam_Accuracy or Distance > Spam_Accuracy then return end
                if Distance <= Spam_Accuracy and Parries > 1 then
                    SpamFire()
                end
            end)
        else
            if Connections_Manager["Auto Spam"] then
                Connections_Manager["Auto Spam"]:Disconnect()
                Connections_Manager["Auto Spam"] = nil
            end
        end
    end,
})

Tabs.Settings:AddToggle("No_Render", {
    Title = "No Render",
    Default = false,
    Callback = function(state)
        local scripts = Player:FindFirstChild("PlayerScripts")
        if scripts and scripts:FindFirstChild("EffectScripts") and scripts.EffectScripts:FindFirstChild("ClientFX") then
            scripts.EffectScripts.ClientFX.Disabled = state
        end

        if state then
            Connections_Manager["No Render"] = workspace.Runtime.ChildAdded:Connect(function(Value)
                Debris:AddItem(Value, 0)
            end)
        else
            if Connections_Manager["No Render"] then
                Connections_Manager["No Render"]:Disconnect()
                Connections_Manager["No Render"] = nil
            end
        end
    end,
})

Track(workspace.Runtime.ChildAdded:Connect(function(Value)
    if Value.Name == "Tornado" then
        Aerodynamic_Time = tick()
        Aerodynamic = true
    end
end))

Track(workspace.Balls.ChildAdded:Connect(function(Ball)
    Parried = false
    CurrentBallId = nil
    Parries = 0

    task.wait(0.1)
    if Ball and Ball.Parent and Ball:GetAttribute("realBall") then
        Track(Ball:GetAttributeChangedSignal("target"):Connect(function()
            if Ball:GetAttribute("target") == tostring(Player) then
                Parried = false
                CurrentBallId = nil
            end
        end))
    end
end))

Track(workspace.Balls.ChildRemoved:Connect(function()
    Parries = 0
    Parried = false
    CurrentBallId = nil
end))

for _, Ball in ipairs(workspace.Balls:GetChildren()) do
    if Ball:GetAttribute("realBall") then
        Track(Ball:GetAttributeChangedSignal("target"):Connect(function()
            if Ball:GetAttribute("target") == tostring(Player) then
                Parried = false
                CurrentBallId = nil
            end
        end))
    end
end

_GHi.HookRestore = function()
    CaptureUnhook()
end
