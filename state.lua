local State = {}
State.__index = State

function State:new()
    self = setmetatable({}, State)

    -- Options
    self.measureBoost = true

    -- Dynamic
    self.rpm = 0
    self.speedKmh = 0
    self.gear = 0
    self.gearString = ''
    self.throttle = 0
    self.clutch = 0
    self.brake = 0
    self.turboBoost = 0
    self.turboPercent = 0
    self.horsePower = 0
    self.torqueBias = 0

    -- 0 : INACTIVE | 1 : ACTIVE | 2 : OFF
    self.absStatus = 0
    self.tcsStatus = 0

    -- Static
    self.maxRpm = 0
    self.maxTurboBoost = 0
    self.peakRpm = 0
    self.maxHorsepower = 0
    self.effectiveGears = {}
    self.enginePosition = 0

    self.torqueCurve = {}
    self.powerCurve = {}

    self.optimalShiftPoints = {}

    return self
end

function State:update(dt)
    local car = ac.getCar(0)
    if car == nil then return end

    self.rpm = car.rpm
    self.speedKmh = math.floor(car.speedKmh)

    self.speedDigits = {}
    for d in tostring(self.speedKmh):gmatch(".") do
        table.insert(self.speedDigits, 1, tonumber(d))
    end

    self.absStatus = self:assistHelper(car.absMode, car.absInAction)
    self.tcsStatus = self:assistHelper(car.tractionControlModes, car.tractionControlInAction)

    self.gear = car.gear
    self.gearString = ac.getCarGearLabel(0)
    self.throttle = car.gas
    self.clutch = 1 - car.clutch -- </3
    self.brake = car.brake
    self.turboBoost = car.turboBoost
    self.turboPercent = self.turboBoost / self.maxTurboBoost
    self.horsePower = self:readCurveAtRpm(self.powerCurve, self.rpm)

    if self.measureBoost then
        if car.turboBoost > self.maxTurboBoost then
            self.maxTurboBoost = car.turboBoost
        end
    end

    self:calculateAwdBias()
    ac.debug("State", self)
end

function State:init()
    local car = ac.getCar(0)
    local carPhys = ac.getCarPhysics(0)
    local engine = ac.INIConfig.carData(0, "engine.ini")

    -- Round up to nearest 1000
    self.maxRpm = engine:get("ENGINE_DATA","LIMITER",8000)
    self.maxRpmCeil = math.ceil(self.maxRpm / 1000) * 1000

    if not self.measureBoost then
        self.maxTurboBoost = engine:get("TURBO_0","DISPLAY_MAX_BOOST",2)
    end

    local drivetrain = ac.INIConfig.carData(0, "drivetrain.ini")
    self.drivetrain = drivetrain:get("TRACTION", "TYPE", "RWD")

    --self.enginePosition = car.enginePosition

    local gearCount = drivetrain:get("GEARS", "COUNT", 6)
    local finalDrive = drivetrain:get("GEARS", "FINAL", 1.0)
    local gears = {}
    for i = 1, gearCount do
        gears[i] = drivetrain:get("GEARS", "GEAR_" .. i, 1.0) * finalDrive
    end
    self.effectiveGears = gears

    -- Preferably auto update gear ratios when setup changes!!
    --local gearss = car.gearRatios
    --gearss = car.finalRatio
    --ac.log(gearss)

    local carName = ac.getCarID(0)
    local path = "content/cars/" .. carName .. "/ui/ui_car.json"
    local absPath = io.findFile(path)
    local file = io.open(absPath, "r")
    if not file then
        ac.log("Failed to open ui_car.json")
        return
    end

    local contents = file:read("*all")
    file:close()

    local data = JSON.parse(contents)
    self.torqueCurve = data.torqueCurve
    self.powerCurve = data.powerCurve

    -- Ensure all curves are parsed to integers
    for i = 1, #self.torqueCurve do
        local point = self.torqueCurve[i]

        point[1] = tonumber(point[1]) -- rpm
        point[2] = tonumber(point[2]) -- torque
    end
    for i = 1, #self.powerCurve do
        local point = self.powerCurve[i]

        point[1] = tonumber(point[1]) -- rpm
        point[2] = tonumber(point[2]) -- power
    end

    self.maxHorsepower, self.peakRpm = self:calculatePeakRpm()

    self:calculateOptimalShiftPoints()
    ac.log(self.optimalShiftPoints)
    ac.debug("Torque Curve", self.torqueCurve)
    ac.debug("Power Curve", self.powerCurve)
end

function State:assistHelper(mode, inAction)
    if mode == 0 then
        return 2
    else
        if inAction then
            return 1
        else
            return 0
        end
    end
end

function State:calculatePeakRpm()
    local maxHP = -1
    local maxRpm = -1
    for i = 1, #self.powerCurve do
        if self.powerCurve[i][2] > maxHP then
            maxHP = self.powerCurve[i][2]
            maxRpm = self.powerCurve[i][1]
        end
    end
    return maxHP, maxRpm
end

-- Using the notion: wheelTorque now <= wheelTorque after shift
function State:calculateOptimalShiftPoints()
    local roundTo = 50

    local shiftPoints = {}
    local gearCount = #self.effectiveGears

    if gearCount < 2 or #self.torqueCurve < 2 then
        return shiftPoints
    end

    for gear = 1, gearCount - 1 do
        local gNow  = self.effectiveGears[gear]
        local gNext = self.effectiveGears[gear + 1]

        local prevRpm, prevDiff = nil, nil

        for i = 1, #self.torqueCurve do
            local rpm = self.torqueCurve[i][1]
            if rpm > self.maxRpm then
                goto continue
            end

            local torqueNow = self.torqueCurve[i][2]

            local wheelNow = torqueNow * gNow
            local rpmAfter = rpm * (gNext / gNow)

            if rpmAfter <= self.maxRpm then
                local torqueAfter = self:readCurveAtRpm(self.torqueCurve, rpmAfter)
                local wheelAfter = torqueAfter * gNext
                local diff = wheelAfter - wheelNow

                if prevDiff and prevDiff < 0 and diff >= 0 then
                    local alpha = -prevDiff / (diff - prevDiff)
                    shiftPoints[gear] = prevRpm + alpha * (rpm - prevRpm)
                    shiftPoints[gear] = math.floor(shiftPoints[gear] / roundTo) * roundTo
                    break
                end

                prevRpm = rpm
                prevDiff = diff
            end
            ::continue::
        end


        -- Fallback
        shiftPoints[gear] = shiftPoints[gear] or self.maxRpm
    end

    self.optimalShiftPoints = shiftPoints
    return shiftPoints
end

function State:readCurveAtRpm(curve, rpm)
    for i = 1, #curve - 1 do
        local r1, t1 = curve[i][1], curve[i][2]
        local r2, t2 = curve[i+1][1], curve[i+1][2]

        if rpm >= r1 and rpm <= r2 then
            local alpha = (rpm - r1) / (r2 - r1)
            return t1 + alpha * (t2 - t1)
        end
    end

    -- Clamp to ends
    if rpm < curve[1][1] then
        return curve[1][2]
    end

    return curve[#curve][2]
end

function State:calculateAwdBias()
    local function getDrivenTorque(i)
        -- Clamp to 0 so it doesnt go negative (Full RWD / FWD)
        -- Negate because for some reason, the values are negative
        return math.max(0, -ac.getCarPhysics(0).wheels[i].feedbackTorque)
    end

    local fl = getDrivenTorque(0)
    local fr = getDrivenTorque(1)
    local rl = getDrivenTorque(2)
    local rr = getDrivenTorque(3)

    local front = fl + fr
    local rear = rl + rr
    local total = front + rear

    local bias = 0
    if total > 1 then
        bias = front / total
    end
    self.torqueBias = bias
end

return State