-- Optimized Auto-Parry core (light anti-curve + late/perfect timing bias)
-- Drop-in helpers for Blade Ball style scripts.

local Stats = game:GetService("Stats")

local AP = {}
AP.__index = AP

function AP.new(player)
    return setmetatable({
        Player = player,
        LastParryAt = 0,
        LastCurveFlipAt = 0,
        PrevVelocity = nil,
        PrevDot = nil,
    }, AP)
end

local function getPingMs()
    return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
end

local function safeUnit(v)
    local m = v.Magnitude
    if m < 1e-5 then
        return Vector3.zero, 0
    end
    return v / m, m
end

-- Low-cost curve detector:
-- detects sudden angular acceleration / direction flips while ball is travelling toward player.
function AP:IsLikelyCurving(ball, root)
    local vel = ball.AssemblyLinearVelocity
    local vDir, speed = safeUnit(vel)
    if speed < 25 then
        self.PrevVelocity = vel
        return false
    end

    local toPlayer = root.Position - ball.Position
    local pDir, dist = safeUnit(toPlayer)
    if dist < 1 then
        self.PrevVelocity = vel
        return false
    end

    local dot = pDir:Dot(vDir)

    -- If ball is not moving toward us, never curve-block (avoids false positives).
    if dot <= 0.02 then
        self.PrevVelocity = vel
        self.PrevDot = dot
        return false
    end

    local curving = false
    if self.PrevVelocity then
        local prevDir = self.PrevVelocity.Unit
        local align = math.clamp(prevDir:Dot(vDir), -1, 1)
        local turnAngle = math.deg(math.acos(align))

        -- Dynamic angle threshold: stricter at close range, looser far away.
        local angleThreshold = 18 + math.clamp(dist * 0.03, 0, 18)

        -- Dot drop = ball suddenly no longer heading straight at us.
        local dotDrop = self.PrevDot and (self.PrevDot - dot) or 0

        if turnAngle > angleThreshold and dotDrop > 0.05 then
            curving = true
            self.LastCurveFlipAt = os.clock()
        end
    end

    self.PrevVelocity = vel
    self.PrevDot = dot

    -- Small hold to ignore immediate post-curve fake windows.
    if (os.clock() - self.LastCurveFlipAt) < 0.085 then
        return true
    end

    return curving
end

-- "Late but safe" parry gate:
-- avoids early parry by using time-to-impact + ping window and approach checks.
function AP:ShouldParry(ball, root)
    local now = os.clock()
    if (now - self.LastParryAt) < 0.075 then
        return false
    end

    local vel = ball.AssemblyLinearVelocity
    local vDir, speed = safeUnit(vel)
    if speed < 1 then
        return false
    end

    local toPlayer = root.Position - ball.Position
    local pDir, dist = safeUnit(toPlayer)
    if dist < 0.5 then
        return false
    end

    local dot = pDir:Dot(vDir)
    if dot <= 0.04 then
        return false
    end

    if self:IsLikelyCurving(ball, root) then
        return false
    end

    local pingSec = math.clamp(getPingMs() / 1000, 0.01, 0.35)
    local tti = dist / speed

    -- Narrow trigger window near impact: high consistency, minimal early parry.
    local lead = 0.028 + (pingSec * 0.7)
    local lateSlack = 0.018 + (pingSec * 0.25)

    if tti <= (lead + lateSlack) and tti >= (lead - 0.03) then
        self.LastParryAt = now
        return true
    end

    return false
end

return AP
