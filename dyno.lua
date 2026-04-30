local Dyno = {}
Dyno.__index = Dyno
local delta = 0.01 -- Compensate for graining   

function Dyno:new()
    self = setmetatable({}, Dyno)
    self.recent = 0
    self.samples = {}
    self.history = {}
    return self
end

function Dyno:update(dt)
    local car = ac.getCar()
    local gas = car.gas
    local speed = car.speedKmh
    if gas < delta then  -- Run ended
        if #self.samples > 60 then
            table.insert(self.history, self.samples)
            --ac.debug("Samples", self.history)
        end
        self.samples = {}
    elseif speed >= self.recent and speed > delta then
        self.recent = speed
        table.insert(self.samples, speed)
    end
end

function Dyno:init()

end

return Dyno