local State = require('state')
local state = State:new()
state:init()

local Dyno = require('dyno')
local dyno = Dyno:new()

local kwConversion = 1.34102209

local colorWhite = rgbm(255,255,255,255)
local colorRed = rgbm(255,0,0,255)
local colorGreen = rgbm(0,255,0,255)
local colorGold = rgbm(215, 255, 0, 255)

local inputBgColor = rgbm(0.2, 0.2, 0.2, 0.75)

local svec = vec2(194, 276)
local angleMin = 0.72 * math.pi
local angleMax = 2    * math.pi
local angleGap = angleMax - angleMin

--- 
--- MAIN LOOP
--- 

function windowMain(dt)
    drawBaseTacho()
    drawNeedle()
    drawRedline()
    drawRpmNumbers()

    drawGearNumber()
    drawAssists()
    drawTransmissionType()
    drawSpeedLabel()
    drawInputBars()
    drawTorqueBias()
    drawTurboGauge()
    drawHpReader()
    drawSidebar()

    local power = ac.getCar().drivetrainPower * kwConversion
    ac.debug("Drivetrain Power", power)
end

-- HELPERS

function drawBaseTacho()
    local gaugeVec = svec - vec2(174, 156)
    ui.drawImage("img/gauge.png", gaugeVec, gaugeVec + vec2(380, 380))
end

function drawNeedle()
    local needleAngle = angleMin + angleGap * (state.rpm / state.maxRpmCeil)
    local needleVec = createOffsetVec(142, needleAngle)
    ui.drawSimpleLine(svec + needleVec * 0.33, svec + needleVec, colorRed, 5)

    if state.gear ~= 0 and state.gear ~= -1 and state.gear ~= #state.effectiveGears then
        local nudgeAngle = angleMin + angleGap * (state.optimalShiftPoints[state.gear] / state.maxRpmCeil)

        -- Optimal speed nudge
        local nudgeVec = createOffsetVec(135, nudgeAngle)
        ui.drawSimpleLine(svec + nudgeVec, svec + nudgeVec + createOffsetVec(10, nudgeAngle), colorGold, 10)
    end
end

function drawRedline()
    local staticPortion = angleGap * (state.maxRpmCeil - state.maxRpm) / state.maxRpmCeil -- E.g. redline at 8700 but gauge goes to 9000 -> include the part between them
    local angleRedlineStart = angleMin + angleGap * state.peakRpm / state.maxRpmCeil - staticPortion
    drawArc(svec, 147, 153, angleRedlineStart, angleMax, rgbm.colors.red, 1000)
end

function drawRpmNumbers()
    local rpmAngle = angleMin
    local rpmInts = state.maxRpmCeil/1000
    local incrementAngle = angleGap / (rpmInts)

    local rpmOffset = 125
    local rpmRadius = vec2(10,10)
    for i=0,rpmInts do
        local centerVec = svec + vec2(rpmOffset * math.cos(rpmAngle), rpmOffset * math.sin(rpmAngle))
        ui.drawImage("img/digits/" .. i .. ".png", centerVec - rpmRadius, centerVec + rpmRadius)
        rpmAngle = rpmAngle + incrementAngle
    end
end

function drawGearNumber()
    local gearRadius = vec2(16,16)
    ui.drawImage("img/digits/" .. state.gearString .. ".png", svec - gearRadius, svec + gearRadius)
end

function drawAssists()
    local assistRadius = vec2(24,24)

    local tcsVec = svec + vec2(-20,95)
    ui.drawImage("img/tcs.png", tcsVec - assistRadius, tcsVec + assistRadius, assistColor(state.tcsStatus))
    local absVec = svec + vec2(30, 95)
    ui.drawImage("img/abs.png", absVec - assistRadius, absVec + assistRadius, assistColor(state.absStatus))
end

function drawTransmissionType()
    -- Transmission type label (M/t, S/t, A/t) 
    -- -> Static MT label
    local transLabel = svec + vec2(125, 25)
    local transSize = vec2(30,10)
    ui.drawImage("img/mt.png", transLabel - transSize, transLabel + transSize)
end

function drawSpeedLabel()
    local speedLabel = svec + vec2(120, 100)
    local speedSize = vec2(30,10)
    ui.drawImage("img/kmh.png", speedLabel - speedSize, speedLabel + speedSize)

    local speedDigit = svec + vec2(132, 63)
    local speedDigitSize = vec2(20,20)
    for _, digit in ipairs(state.speedDigits) do
        ui.drawImage("img/digits/" .. digit .. ".png", speedDigit - speedDigitSize, speedDigit + speedDigitSize)
        speedDigit = speedDigit - vec2(40, 0)
    end
end

function drawInputBars()
    local inputBackground = svec + vec2(160, 12)
    local inputBackgroundSize = vec2(40, 100)
    ui.drawRectFilled(inputBackground, inputBackground + inputBackgroundSize, inputBgColor)

    local bars = {{"green", state.throttle}, {"red", state.brake}, {"blue", state.clutch}}

    local barStart = svec + vec2(175,107)
    local barSize = vec2(10, 90)

    for i=1, #bars do
        barSize = vec2(10, 90*bars[i][2])
        ui.drawImage("img/gradient_" .. bars[i][1] .. ".png", barStart - barSize, barStart, rgbm.colors.white)
        barStart = barStart + vec2(10,0)
    end
end

function drawTorqueBias()
    local biasBackground = svec + vec2(210,12)
    local biasBackgroundSize = vec2(30,100)
    ui.drawRectFilled(biasBackground, biasBackground + biasBackgroundSize, inputBgColor)

    local biasStart = biasBackground + vec2(15, 8 + 86*(1-state.torqueBias))
    local biasSize = vec2(8, 2)
    ui.drawRectFilled(biasStart - biasSize, biasStart + biasSize, rgbm.colors.white)
end

function drawTurboGauge()
    ac.debug("Turbo %", state.turboBoost / state.maxTurboBoost)

    local turboVec = svec + vec2(10, -250)
    local turboSize = vec2(100,100)
    ui.drawImage("img/turbo.png", turboVec, turboVec + turboSize)

    local turboTextVec = turboVec + vec2(23, 40)
    local turboString = string.format("%.2f", state.turboBoost) .. " Bar"
    local turboTextFontSize = 15
    ui.dwriteDrawText(turboString, turboTextFontSize, turboTextVec)

    local turboStartAngle = 0.5*math.pi
    local turboEndAngle = turboStartAngle + 1.5*math.pi*state.turboPercent
    drawArc(turboTextVec + vec2(26,9), 45, 50, 0.5*math.pi, turboEndAngle, rgbm.colors.white, 1000)
end

function drawHpReader()
    local readerFontSize = 15
    local readerTextSize = vec2(100,20)

    local actualHpVec = svec + vec2(150,120)
    local actualHpString = "HP: " .. string.format("%.0f", state.horsePower)
    ui.dwriteDrawTextClipped(actualHpString, readerFontSize, actualHpVec, actualHpVec + readerTextSize)

    local maxHpVec = svec + vec2(150,140)
    local maxHpString = "Max HP: " .. string.format("%.0f", state.maxHorsepower)
    ui.dwriteDrawTextClipped(maxHpString, readerFontSize, maxHpVec, maxHpVec + readerTextSize)
end

function drawSidebar()
    drawArc(svec, 160, 200, -0.3*math.pi, 0, rgbm(0,0,0,.25), 500)

    local engineVec = svec + vec2(163,-40)
    local engineSize = vec2(30,30)
    ui.drawImage("img/enginestart.png", engineVec, engineVec + engineSize, colorWhite)

    local headlightsVec = svec + vec2(148, -96)
    local headlightsSize = vec2(28,28)
    ui.drawImage("img/lighton.png", headlightsVec, headlightsVec + headlightsSize, rgbm(1,1,1,.5))

    local plusVec = svec + vec2(112, -146)
    local plusSize = vec2(28,28)
    ui.drawImage("img/plus.png", plusVec, plusVec + plusSize, colorWhite)
end

-- HELPERS

function createOffsetVec(offset, angle)
    return vec2(offset*math.cos(angle), offset*math.sin(angle))
end

function assistColor(status)
    if status == 0 then
        return rgbm.colors.transparent
    elseif status == 1 then
        return rgbm.colors.yellow
    elseif status == 2 then
        return rgbm.colors.red
    end
end

-- Needs a lot of segments to look good :/
function drawArc(center, innerR, outerR, a0, a1, color, segments)
    segments = segments or 64
    local step = (a1 - a0) / segments

    for i = 0, segments - 1 do
        local ang0 = a0 + step * i
        local ang1 = a0 + step * (i + 1)

        local cos0, sin0 = math.cos(ang0), math.sin(ang0)
        local cos1, sin1 = math.cos(ang1), math.sin(ang1)

        local p1 = center + vec2(cos0 * innerR, sin0 * innerR)
        local p2 = center + vec2(cos0 * outerR, sin0 * outerR)
        local p3 = center + vec2(cos1 * outerR, sin1 * outerR)
        local p4 = center + vec2(cos1 * innerR, sin1 * innerR)

        -- Two triangles per segment
        ui.drawTriangleFilled(p1, p2, p3, color)
        ui.drawTriangleFilled(p1, p3, p4, color)
    end
end


function script.update(dt)
    state:update(dt)
    dyno:update(dt)
end



-- ac.getCarIndexInFront(carMainIndex, distance)

-- absInAction boolean @Physics-only (see `ac.CarState.physicsAvailable`)
-- tractionControlInAction boolean @Physics-only (see `ac.CarState.physicsAvailable`)
-- autoShift boolean @Returns `true` if automatic shifting is active. Physics-only (see `ac.CarState.physicsAvailable`)
-- function ac.getCarGearLabel(carIndex) end
-- autoClutch boolean @Returns `true` if auto-clutch is active. Physics-only (see `ac.CarState.physicsAvailable`) 