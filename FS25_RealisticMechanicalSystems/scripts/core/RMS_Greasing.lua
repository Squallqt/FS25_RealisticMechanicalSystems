-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Machine and implement greasing, an interval's points due together
RMS_Greasing = {}

---Returns the specialization holding the greasing
function RMS_Greasing.getSpec(vehicle)
    return vehicle.spec_RealisticMechanicalSystems or vehicle.spec_rmsImplementGreasing
end

---Returns what an interval counts: worked days, months or bales
function RMS_Greasing.getUnit(tier)
    if tier.months ~= nil then
        return "months"
    elseif tier.bales ~= nil then
        return "bales"
    end
    return "day"
end

---Returns an interval in its unit, the hours of a notice in worked days
function RMS_Greasing.getInterval(tier)
    local unit = RMS_Greasing.getUnit(tier)
    if unit ~= "day" then
        return tier[unit]
    elseif tier.hours == nil then
        return 1
    end
    return math.max(math.floor(tier.hours / RMS_Config.GREASING.DAY_HOURS + 0.5), 1)
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
                if not merged and RMS_Greasing.getUnit(tier) == RMS_Greasing.getUnit(cardanTier)
                    and RMS_Greasing.getInterval(tier) == RMS_Greasing.getInterval(cardanTier) then
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

---Returns the share of joints run dry since the due date
local function getDryShare(lateShare)
    local shape = math.log(math.log(0.9) / math.log(0.99)) / math.log(RMS_Config.GREASING.GREASE_L10_INTERVALS)
    local scale = (-math.log(0.99)) ^ (-1 / shape)
    local function dry(intervals)
        return 1 - math.exp(-(intervals / scale) ^ shape)
    end
    return (dry(1 + lateShare) - dry(1)) / (1 - dry(1))
end

-- @param boolean? isCounted true once a day, month or bale counted, or a service
local function refresh(vehicle, isCounted)
    local spec = RMS_Greasing.getSpec(vehicle)
    local state, tiers = getState(vehicle), RMS_Greasing.getTiers(vehicle) or {}
    local duePoints, totalPoints, lateShare, dryPoints = 0, 0, 0, 0
    for index, tier in ipairs(tiers) do
        duePoints = duePoints + state.due[index]
        totalPoints = totalPoints + tier.points
        if state.due[index] > 0 and state.late[index] > 0 then
            local share = state.late[index] / RMS_Greasing.getInterval(tier)
            lateShare = math.max(lateShare, share)
            dryPoints = dryPoints + state.due[index] * getDryShare(share)
        end
    end

    spec.greasingWearFactor = totalPoints > 0 and 1 + dryPoints / totalPoints * (RMS_Config.GREASING.DRY_WEAR_FACTOR - 1) or 1
    local lubricationLevel = 1 - math.min(lateShare, 1)
    if isCounted or duePoints ~= spec.greasingDuePoints or lubricationLevel ~= (spec.lubricationLevel or 1) then
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

---Returns how many times faster a late greased vehicle wears
function RMS_Greasing.getWearFactor(vehicle)
    return RMS_Greasing.getSpec(vehicle).greasingWearFactor or 1
end

---Returns done, due on the day points fall due, late once delayed
function RMS_Greasing.getStatus(vehicle)
    local spec = RMS_Greasing.getSpec(vehicle)
    if (spec.greasingDuePoints or 0) == 0 then
        return "done"
    end
    return (spec.lubricationLevel or 1) < 1 and "late" or "due"
end

---Counts a unit: delay on due intervals, run on the others
-- @param string unit day, months or bales
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
            local interval = RMS_Greasing.getInterval(tier)
            if state.elapsed[index] >= interval then
                state.due[index] = tier.points
                state.late[index] = state.elapsed[index] - interval
            end
        end
    end
    refresh(vehicle, true)
end

---Marks the day worked once the machine or implement has run
-- @param float operatingDt running time since last call in ms
function RMS_Greasing.update(vehicle, operatingDt)
    if RMS_Greasing.getTiers(vehicle) ~= nil and operatingDt > 0 then
        getState(vehicle).workedToday = true
    end
end

---Counts a month of the calendar against the monthly intervals
function RMS_Greasing.onPeriodChanged(vehicle)
    advance(vehicle, "months", 1)
end

---Counts a bale wrapped against the intervals in bales
function RMS_Greasing.onBaleWrapped(vehicle)
    advance(vehicle, "bales", 1)
end

---Counts a worked day against the intervals in days, idle days not
function RMS_Greasing.onDayChanged(vehicle)
    local state = getState(vehicle)
    if state.workedToday then
        state.workedToday = false
        advance(vehicle, "day", 1)
    end
end

---Greases the due point of the latest interval
-- @return boolean greased false when no point is due
function RMS_Greasing.greasePoint(vehicle)
    local state, tiers, latest, latestShare = getState(vehicle), RMS_Greasing.getTiers(vehicle) or {}, nil, -1
    for index, tier in ipairs(tiers) do
        local share = state.late[index] / RMS_Greasing.getInterval(tier)
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
    refresh(vehicle, true)
end

---Leaves a share of each interval before its points fall due
-- @param float share 1 just greased, 0 every point due now
function RMS_Greasing.setIntervalLeft(vehicle, share)
    local state = getState(vehicle)
    for index, tier in ipairs(RMS_Greasing.getTiers(vehicle) or {}) do
        state.due[index], state.late[index] = share == 0 and tier.points or 0, 0
        state.elapsed[index] = share == 0 and 0 or (1 - share) * RMS_Greasing.getInterval(tier)
    end
    refresh(vehicle, true)
end

---Returns each interval: points, unit, length, due, run and delay
function RMS_Greasing.getTierStates(vehicle)
    local state, states = getState(vehicle), {}
    for index, tier in ipairs(RMS_Greasing.getTiers(vehicle) or {}) do
        table.insert(states, { points = tier.points, unit = RMS_Greasing.getUnit(tier), interval = RMS_Greasing.getInterval(tier),
            due = state.due[index], elapsed = state.elapsed[index], late = state.late[index] })
    end
    return states
end

-- greasing units from the most frequent: worked days, months, bales
local UNIT_RANK = { day = 1, months = 2, bales = 3 }

---Returns the intervals with the latest due, the next and the shortest
function RMS_Greasing.read(vehicle)
    local greasing = { tiers = RMS_Greasing.getTierStates(vehicle), total = RMS_Greasing.getTotalPoints(vehicle),
        due = RMS_Greasing.getDuePoints(vehicle), state = RMS_Greasing.getStatus(vehicle) }
    for _, tier in ipairs(greasing.tiers) do
        if tier.due > 0 then
            if greasing.latest == nil or tier.late / tier.interval > greasing.latest.late / greasing.latest.interval then
                greasing.latest = tier
            end
        elseif (tier.unit ~= "day" or tier.interval > 1) and (greasing.next == nil
            or 1 - tier.elapsed / tier.interval < 1 - greasing.next.elapsed / greasing.next.interval) then
            greasing.next = tier
        end
        if greasing.frequent == nil or UNIT_RANK[tier.unit] < UNIT_RANK[greasing.frequent.unit]
            or tier.unit == greasing.frequent.unit and tier.interval < greasing.frequent.interval then
            greasing.frequent = tier
        end
    end
    return greasing
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
