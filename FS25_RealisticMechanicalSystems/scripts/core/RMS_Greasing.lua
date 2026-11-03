-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Machine and implement greasing, an interval's points due together
RMS_Greasing = {}

local HOUR_MS = 60 * 60 * 1000

---Returns the specialization holding the greasing
function RMS_Greasing.getSpec(vehicle)
    return vehicle.spec_RealisticMechanicalSystems or vehicle.spec_rmsImplementGreasing
end

---Returns what an interval counts: hours, worked days, months or bales
function RMS_Greasing.getUnit(tier)
    if tier.hours ~= nil then
        return "hours"
    elseif tier.months ~= nil then
        return "months"
    elseif tier.bales ~= nil then
        return "bales"
    end
    return "day"
end

local function resolveFamily(vehicle, entry)
    if type(entry) ~= "table" then
        return entry
    elseif entry.trailed ~= nil then
        local wheels = vehicle.spec_wheels
        return wheels ~= nil and #wheels.wheels >= 2 and entry.trailed or entry.mounted
    end
    local cylindered = vehicle.spec_cylindered
    if cylindered ~= nil and #cylindered.movingTools > 0 then
        return entry.moving
    end
    return entry.fixed
end

local function getImplementFamily(vehicle)
    local C = RMS_Config.GREASING
    local wheels, cylindered, powerConsumer = vehicle.spec_wheels, vehicle.spec_cylindered, vehicle.spec_powerConsumer
    local isDriven = powerConsumer ~= nil and powerConsumer.ptoRpm > 0
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    for _, categoryName in ipairs(storeItem ~= nil and storeItem.categoryNames or {}) do
        local entry = C.IMPLEMENT_CATEGORY_FAMILIES[string.upper(categoryName)]
        if entry ~= nil then
            local family = resolveFamily(vehicle, entry)
            if family == false or family ~= nil and (#C.FAMILIES[family] > 0 or isDriven) then
                return family
            end
            break
        end
    end
    if wheels ~= nil and #wheels.wheels >= 2 then
        return "IMP_TRAILER"
    elseif cylindered ~= nil and #cylindered.movingTools > 0 then
        return "IMP_LOADER_TOOL"
    elseif isDriven then
        return "IMP_DRIVEN"
    end
end

local function getWorkingWidth(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return 0
    end
    StoreItemUtil.loadSpecsFromXML(storeItem)
    local width = Vehicle.getSpecValueWorkingWidthConfig(storeItem, vehicle, vehicle.configurations, nil, true) or 0
    if width == 0 and storeItem.specs.workingWidth ~= nil then
        width = storeItem.specs.workingWidth.width
    end
    return width
end

local function getImplementTiers(vehicle)
    local C = RMS_Config.GREASING
    local family = getImplementFamily(vehicle)
    local tiers = {}
    for _, tier in ipairs(family and C.FAMILIES[family] or {}) do
        if tier.noticeRows ~= nil then
            local width = getWorkingWidth(vehicle)
            local rows = width > 0 and math.min(math.max(math.floor(width / tier.rowWidth + 0.5), 1), tier.noticeRows) or tier.noticeRows
            tier = { points = tier.points + (rows - tier.noticeRows) * tier.rowPoints, hours = tier.hours }
        end
        table.insert(tiers, tier)
    end
    local powerConsumer = vehicle.spec_powerConsumer
    if family and powerConsumer ~= nil and powerConsumer.ptoRpm > 0 and not C.CARDAN_INCLUDED[family] then
        for _, cardanTier in ipairs(C.CARDAN) do
            local merged = false
            for index, tier in ipairs(tiers) do
                if not merged and RMS_Greasing.getUnit(tier) == RMS_Greasing.getUnit(cardanTier) and tier.hours == cardanTier.hours then
                    tiers[index] = { points = tier.points + cardanTier.points, hours = tier.hours }
                    merged = true
                end
            end
            if not merged then
                table.insert(tiers, cardanTier)
            end
        end
    end
    return #tiers > 0 and tiers or false
end

---Returns the greasing intervals, nil without grease points
function RMS_Greasing.getTiers(vehicle)
    local spec = RMS_Greasing.getSpec(vehicle)
    if spec.greasingTiers == nil then
        local C = RMS_Config.GREASING
        if vehicle.spec_RealisticMechanicalSystems ~= nil then
            local family = C.CATEGORY_FAMILIES[RMS_Fluids.getVehicleCategory(vehicle)]
            spec.greasingTiers = family ~= nil and C.FAMILIES[family] or false
        else
            spec.greasingTiers = getImplementTiers(vehicle)
        end
    end
    return spec.greasingTiers or nil
end

---Returns an interval in its unit, hours of the meter for hours
function RMS_Greasing.getInterval(vehicle, tier)
    local unit = RMS_Greasing.getUnit(tier)
    if unit == "day" then
        return 1
    elseif unit ~= "hours" then
        return tier[unit]
    end
    return tier.hours / RMS_Config.SERVICE_REFERENCE_HOURS * vehicle:getServiceReferenceInterval()
end

local function getState(vehicle)
    local spec = RMS_Greasing.getSpec(vehicle)
    local tiers = RMS_Greasing.getTiers(vehicle)
    if spec.greasing == nil or #spec.greasing.due ~= #(tiers or {}) then
        spec.greasing = { due = {}, elapsed = {}, late = {}, workedToday = false }
        for index in ipairs(tiers or {}) do
            spec.greasing.due[index], spec.greasing.elapsed[index], spec.greasing.late[index] = 0, 0, 0
        end
    end
    return spec.greasing
end

local function refresh(vehicle)
    local spec = RMS_Greasing.getSpec(vehicle)
    local state, tiers = getState(vehicle), RMS_Greasing.getTiers(vehicle) or {}
    local duePoints, lateShare = 0, 0
    for index, tier in ipairs(tiers) do
        duePoints = duePoints + state.due[index]
        if state.due[index] > 0 then
            lateShare = math.max(lateShare, state.late[index] / RMS_Greasing.getInterval(vehicle, tier))
        end
    end

    spec.greasingLateShare = lateShare
    local lubricationLevel = 1 - math.min(lateShare, 1)
    if duePoints ~= spec.greasingDuePoints or math.abs(lubricationLevel - (spec.lubricationLevel or 1)) >= 0.005 then
        spec.greasingDuePoints = duePoints
        spec.lubricationLevel = lubricationLevel
        if vehicle.spec_RealisticMechanicalSystems ~= nil then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
        elseif vehicle.isServer then
            vehicle:raiseDirtyFlags(spec.dirtyFlag)
        end
    end
end

---Sets up the greasing state once the machine's category is known
function RMS_Greasing.initialize(vehicle)
    local spec = RMS_Greasing.getSpec(vehicle)
    spec.isVehicleNeedLubricate = RMS_Greasing.getTiers(vehicle) ~= nil
    refresh(vehicle)
end

---Returns the share of joints run dry, Weibull of the grease life
local function getDryShare(intervals)
    local shape = math.log(math.log(0.9) / math.log(0.99)) / math.log(RMS_Config.GREASING.GREASE_L10_INTERVALS)
    local scale = (-math.log(0.99)) ^ (-1 / shape)
    return 1 - math.exp(-(intervals / scale) ^ shape)
end

---Returns how many times faster a late greased vehicle wears
function RMS_Greasing.getWearFactor(vehicle)
    local lateShare = RMS_Greasing.getSpec(vehicle).greasingLateShare or 0
    if lateShare <= 0 then
        return 1
    end
    local dryAtInterval = getDryShare(1)
    local dryShare = (getDryShare(1 + lateShare) - dryAtInterval) / (1 - dryAtInterval)
    return 1 + dryShare * (RMS_Config.GREASING.DRY_WEAR_FACTOR - 1)
end

---Counts a unit: delay on due intervals, run on the others
-- @param string unit hours, months or bales
local function advance(vehicle, unit, amount)
    local tiers = RMS_Greasing.getTiers(vehicle)
    if tiers == nil or amount <= 0 then
        return
    end

    local state = getState(vehicle)
    for index, tier in ipairs(tiers) do
        local tierUnit = RMS_Greasing.getUnit(tier)
        if state.due[index] > 0 then
            if tierUnit == unit then
                state.late[index] = state.late[index] + amount
            end
        elseif tierUnit == unit then
            state.elapsed[index] = state.elapsed[index] + amount
            local interval = RMS_Greasing.getInterval(vehicle, tier)
            if state.elapsed[index] >= interval then
                state.due[index] = tier.points
                state.late[index] = state.elapsed[index] - interval
            end
        end
    end
    refresh(vehicle)
end

---Counts running time against each interval and the delay of due ones
-- @param float operatingDt engine running time since last call in ms
function RMS_Greasing.update(vehicle, operatingDt)
    if RMS_Greasing.getTiers(vehicle) == nil or operatingDt <= 0 then
        return
    end
    getState(vehicle).workedToday = true
    advance(vehicle, "hours", operatingDt / HOUR_MS)
end

---Counts a month of the calendar against the monthly intervals
function RMS_Greasing.onPeriodChanged(vehicle)
    advance(vehicle, "months", 1)
end

---Counts a bale wrapped against the intervals in bales
function RMS_Greasing.onBaleWrapped(vehicle)
    advance(vehicle, "bales", 1)
end

---Makes the daily points due after a day of work, a day later if left
function RMS_Greasing.onDayChanged(vehicle)
    local tiers = RMS_Greasing.getTiers(vehicle)
    if tiers == nil then
        return
    end

    local state = getState(vehicle)
    for index, tier in ipairs(tiers) do
        if RMS_Greasing.getUnit(tier) == "day" and state.workedToday then
            if state.due[index] > 0 then
                state.late[index] = state.late[index] + 1
            else
                state.due[index] = tier.points
                state.late[index] = 0
            end
        end
    end
    state.workedToday = false
    refresh(vehicle)
end

---Greases the due point of the latest interval
-- @return boolean greased false when no point is due
function RMS_Greasing.greasePoint(vehicle)
    local state, tiers, latest, latestShare = getState(vehicle), RMS_Greasing.getTiers(vehicle) or {}, nil, -1
    for index, tier in ipairs(tiers) do
        local share = state.late[index] / RMS_Greasing.getInterval(vehicle, tier)
        if state.due[index] > 0 and share > latestShare then
            latest, latestShare = index, share
        end
    end
    if latest == nil then
        return false
    end

    state.due[latest] = state.due[latest] - 1
    if state.due[latest] == 0 then
        state.elapsed[latest], state.late[latest] = 0, 0
    end
    refresh(vehicle)
    return true
end

---Greases every point, as a workshop service does
function RMS_Greasing.greaseAll(vehicle)
    local state = getState(vehicle)
    for index in ipairs(state.due) do
        state.due[index], state.elapsed[index], state.late[index] = 0, 0, 0
    end
    refresh(vehicle)
end

---Leaves a share of each interval before its points fall due
-- @param float share 1 just greased, 0 every point due now
function RMS_Greasing.setIntervalLeft(vehicle, share)
    local state = getState(vehicle)
    for index, tier in ipairs(RMS_Greasing.getTiers(vehicle) or {}) do
        state.due[index], state.late[index] = share == 0 and tier.points or 0, 0
        state.elapsed[index] = share == 0 and 0 or (1 - share) * RMS_Greasing.getInterval(vehicle, tier)
    end
    refresh(vehicle)
end

---Returns each interval: points, unit, length, due, run and delay
function RMS_Greasing.getTierStates(vehicle)
    local state, states = getState(vehicle), {}
    for index, tier in ipairs(RMS_Greasing.getTiers(vehicle) or {}) do
        table.insert(states, { points = tier.points, unit = RMS_Greasing.getUnit(tier), interval = RMS_Greasing.getInterval(vehicle, tier),
            due = state.due[index], elapsed = state.elapsed[index], late = state.late[index] })
    end
    return states
end

---Returns all the grease points of a machine, every interval together
function RMS_Greasing.getTotalPoints(vehicle)
    local total = 0
    for _, tier in ipairs(RMS_Greasing.getTiers(vehicle) or {}) do
        total = total + tier.points
    end
    return total
end

---Returns the grease points still to grease
function RMS_Greasing.getDuePoints(vehicle)
    return RMS_Greasing.getSpec(vehicle).greasingDuePoints or 0
end

---Writes "due:elapsed:late" per interval, then the worked day
function RMS_Greasing.serialize(vehicle)
    local state, parts = getState(vehicle), {}
    for index in ipairs(state.due) do
        table.insert(parts, string.format("%d:%.4f:%.4f", state.due[index], state.elapsed[index], state.late[index]))
    end
    table.insert(parts, state.workedToday and "1" or "0")
    return table.concat(parts, " ")
end

---Reads a saved state, kept only when it matches the machine's intervals
function RMS_Greasing.deserialize(vehicle, text)
    local state, tiers, parts = getState(vehicle), RMS_Greasing.getTiers(vehicle) or {}, {}
    for part in string.gmatch(text or "", "%S+") do
        table.insert(parts, part)
    end
    if #parts ~= #tiers + 1 then
        return
    end

    for index, tier in ipairs(tiers) do
        local due, elapsed, late = string.match(parts[index], "^(%d+):([%d%.]+):([%d%.]+)$")
        if due == nil then
            return
        end
        state.due[index] = math.min(tonumber(due), tier.points)
        state.elapsed[index], state.late[index] = tonumber(elapsed), tonumber(late)
    end
    state.workedToday = parts[#parts] == "1"
    refresh(vehicle)
end
