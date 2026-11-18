-- Copyright © 2026 Squallqt. All rights reserved.

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

---Returns an interval in its unit, its hours in worked days
function RMS_Greasing.getInterval(tier)
    local unit = RMS_Greasing.getUnit(tier)
    if unit ~= "day" then
        return tier[unit]
    elseif tier.hours == nil then
        return 1
    end
    return math.max(math.floor(tier.hours / RMS_Config.GREASING.DAY_HOURS + 0.5), 1)
end

---Tells whether a joint type hitches a towed implement
local function getIsTowingJoint(jointType)
    return jointType == AttacherJoints.JOINTTYPE_TRAILER or jointType == AttacherJoints.JOINTTYPE_TRAILERLOW
        or jointType == AttacherJoints.JOINTTYPE_TRAILERSADDLED or jointType == AttacherJoints.JOINTTYPE_TRAILERCAR
        or jointType == AttacherJoints.JOINTTYPE_SEMITRAILER or jointType == AttacherJoints.JOINTTYPE_SEMITRAILERHOOK
        or jointType == AttacherJoints.JOINTTYPE_SEMITRAILERCAR
end

---Returns the wheels of a towed chassis
-- @return integer wheels of its own chassis, 0 when mounted, hooked or set on a carrier
local function getChassisWheels(vehicle)
    local wheels, attachable = vehicle.spec_wheels, vehicle.spec_attachable
    if wheels == nil or #wheels.wheels < 2 or attachable == nil then
        return 0
    end
    for _, joint in ipairs(attachable.inputAttacherJoints or {}) do
        if getIsTowingJoint(joint.jointType) then
            return #wheels.wheels
        end
    end
    return 0
end

---Tells whether a moving tool swings or is pushed by its own ram
local function getIsArm(tool)
    if tool.rotSpeed ~= nil or tool.rotMax ~= nil then
        return true
    end
    for _, dependent in ipairs(tool.dependentPartData or {}) do
        if dependent.part ~= nil and (dependent.part.numTranslatingParts or 0) > 0 then
            return true
        end
    end
    return false
end

---Returns the arms the cylinders move
-- @return integer arms a cylinder moves, sliding tines not
local function getArmCount(vehicle)
    local count = 0
    for _, tool in ipairs(vehicle.spec_cylindered ~= nil and vehicle.spec_cylindered.movingTools or {}) do
        if getIsArm(tool) then
            count = count + 1
        end
    end
    return count
end

---Returns the working width of the fitted configuration, 0 when unknown
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

---Tells whether a trailer tips to the left and the right as well as to the rear
local function getIsThreeWayTipper(vehicle)
    local trailer = vehicle.spec_trailer
    if trailer == nil or g_i18n == nil then
        return false
    end
    local left, right = g_i18n:getText("info_tipSideLeft"), g_i18n:getText("info_tipSideRight")
    local hasLeft, hasRight = false, false
    for _, tipSide in ipairs(trailer.tipSides or {}) do
        hasLeft = hasLeft or tipSide.name == left
        hasRight = hasRight or tipSide.name == right
    end
    return hasLeft and hasRight
end

---Tells whether a baler presses small square bales
local function getIsSmallBaler(vehicle)
    local baler = vehicle.spec_baler
    local baleType = baler ~= nil and baler.baleTypes ~= nil and baler.baleTypes[1] or nil
    return baleType ~= nil and not baleType.isRoundBale and baleType.width <= RMS_Config.GREASING.SMALL_BALE_WIDTH
end

---Returns the build of a rake from its file
-- @return string? build rotors, belts or wheels, nil once closed
-- @return integer count the rotors its file declares
local function getRakeBuild(vehicle)
    local xmlFile = vehicle.xmlFile
    if vehicle.spec_windrower == nil or xmlFile == nil or xmlFile.handle == nil then
        return nil, 0
    end
    local rotors, index = 0, 0
    while hasXMLProperty(xmlFile.handle, string.format("vehicle.windrower.animationNodes.animationNode(%d)", index)) do
        if getXMLString(xmlFile.handle, string.format("vehicle.windrower.animationNodes.animationNode(%d)#class", index)) == "RotationAnimationSpikes" then
            rotors = rotors + 1
        end
        index = index + 1
    end
    local effect = 0
    while hasXMLProperty(xmlFile.handle, string.format("vehicle.windrower.effects.effect(%d)", effect)) do
        local node = 0
        while hasXMLProperty(xmlFile.handle, string.format("vehicle.windrower.effects.effect(%d).effectNode(%d)", effect, node)) do
            local key = string.format("vehicle.windrower.effects.effect(%d).effectNode(%d).motionPathEffect#isPickup", effect, node)
            if getXMLString(xmlFile.handle, key) == "true" then
                return "belts", rotors
            end
            node = node + 1
        end
        effect = effect + 1
    end
    return rotors > 0 and "rotors" or "wheels", rotors
end

---Returns the family a category entry gives the implement
local function resolveFamily(vehicle, entry)
    if type(entry) ~= "table" then
        return entry
    elseif entry.byWidth ~= nil then
        local width = getWorkingWidth(vehicle)
        if width == 0 and entry.unknown ~= nil then
            return resolveFamily(vehicle, entry.unknown)
        end
        for _, band in ipairs(entry.byWidth) do
            if width <= band[1] then
                return resolveFamily(vehicle, band[2])
            end
        end
        return nil
    elseif entry.trailed ~= nil then
        return resolveFamily(vehicle, getChassisWheels(vehicle) > 0 and entry.trailed or entry.mounted)
    elseif entry.baleLoader ~= nil then
        return vehicle.spec_baleLoader ~= nil and entry.baleLoader or entry.flatbed
    elseif entry.threeWay ~= nil then
        return getIsThreeWayTipper(vehicle) and entry.threeWay or entry.rear
    elseif entry.smallBales ~= nil then
        return getIsSmallBaler(vehicle) and entry.smallBales or entry.bigBales
    elseif entry.belts ~= nil then
        return entry[getRakeBuild(vehicle) or "rotors"]
    end
    return resolveFamily(vehicle, getArmCount(vehicle) > 0 and entry.moving or entry.fixed)
end

---Returns the rotors of a rake
-- @return integer rotors of a rake, by its width when its file is closed
local function getRakeRotors(vehicle)
    local _, rotors = getRakeBuild(vehicle)
    if rotors > 0 then
        return rotors
    end
    local width = getWorkingWidth(vehicle)
    return width > 10.5 and 4 or width > 5 and 2 or 1
end

---Returns the points an interval of the family gives the implement
-- @return integer points of the organs the implement carries
local function getOrganPoints(vehicle, tier, wheels, arms)
    if tier.organ == "chassis" and wheels == 0 or tier.organ == "tandem" and wheels < 4 then
        return 0
    end
    local points = tier.points
    if tier.noticeRows ~= nil then
        local width = getWorkingWidth(vehicle)
        local rows = width > 0 and math.min(math.max(math.floor(width / tier.rowWidth + 0.5), 1), tier.noticeRows) or tier.noticeRows
        points = points + (rows - tier.noticeRows) * tier.rowPoints
    end
    if tier.unitWidth ~= nil then
        local width = getWorkingWidth(vehicle)
        points = points * (width > 0 and math.max(math.floor(width / tier.unitWidth + 0.5), 1) or tier.units)
    end
    if tier.perRotor ~= nil then
        local rotors = getRakeRotors(vehicle)
        points = tier.organ == "rotors" and rotors < 2 and 0 or points * rotors
    end
    if tier.perWheel ~= nil then
        points = tier.perWheel * wheels
    end
    if tier.perArm ~= nil then
        points = math.min(points, tier.perArm * arms)
    end
    return points
end

---Returns the greasing family of an implement, by its organs when its category gives none
local function getImplementFamily(vehicle)
    local C = RMS_Config.GREASING
    local powerConsumer = vehicle.spec_powerConsumer
    local isDriven = powerConsumer ~= nil and powerConsumer.ptoRpm > 0
    local wheels, arms = getChassisWheels(vehicle), getArmCount(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    for _, categoryName in ipairs(storeItem ~= nil and storeItem.categoryNames or {}) do
        local entry = C.IMPLEMENT_CATEGORY_FAMILIES[string.upper(categoryName)]
        if entry ~= nil then
            local family = resolveFamily(vehicle, entry)
            if family == false or family ~= nil and isDriven then
                return family
            end
            for _, tier in ipairs(family ~= nil and C.FAMILIES[family] or {}) do
                if getOrganPoints(vehicle, tier, wheels, arms) > 0 then
                    return family
                end
            end
            break
        end
    end
    if wheels > 0 then
        return "IMP_TRAILER"
    elseif arms > 0 then
        return "IMP_LOADER_TOOL"
    elseif isDriven then
        return "IMP_DRIVEN"
    end
end

---Adds an interval, joined to one of the same unit and length
local function addTier(tiers, tier)
    for index, other in ipairs(tiers) do
        if not other.isDriveline and not tier.isDriveline and RMS_Greasing.getUnit(other) == RMS_Greasing.getUnit(tier)
            and RMS_Greasing.getInterval(other) == RMS_Greasing.getInterval(tier) then
            tiers[index] = { points = other.points + tier.points, hours = other.hours, months = other.months, bales = other.bales }
            return
        end
    end
    table.insert(tiers, tier)
end

---Returns the intervals of an implement, its cardan joined, false without points
local function getImplementTiers(vehicle)
    local C = RMS_Config.GREASING
    local family = getImplementFamily(vehicle)
    local wheels, arms = getChassisWheels(vehicle), getArmCount(vehicle)
    local tiers = {}
    for _, tier in ipairs(family and C.FAMILIES[family] or {}) do
        local points = getOrganPoints(vehicle, tier, wheels, arms)
        if points > 0 then
            addTier(tiers, { points = points, hours = tier.hours, months = tier.months, bales = tier.bales, isDriveline = tier.isDriveline })
        end
    end
    local powerConsumer = vehicle.spec_powerConsumer
    if family and powerConsumer ~= nil and powerConsumer.ptoRpm > 0 and not C.CARDAN_INCLUDED[family] then
        for _, cardanTier in ipairs(C.CARDAN) do
            local merged = false
            for index, tier in ipairs(tiers) do
                if not merged and RMS_Greasing.getUnit(tier) == RMS_Greasing.getUnit(cardanTier)
                    and RMS_Greasing.getInterval(tier) == RMS_Greasing.getInterval(cardanTier) then
                    tiers[index] = { points = tier.points + cardanTier.points, hours = tier.hours, isDriveline = true }
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

---Returns the greasing state, reset when the intervals changed
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

---Updates the wear factor, the due points and the lubrication level
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

---Marks the day worked, telling the clients once a day
-- @param float operatingDt running time since last call in ms
function RMS_Greasing.update(vehicle, operatingDt)
    if RMS_Greasing.getTiers(vehicle) ~= nil and operatingDt > 0 and not getState(vehicle).workedToday then
        getState(vehicle).workedToday = true
        refresh(vehicle, true)
    end
end

---Returns true once the vehicle has worked that day
function RMS_Greasing.getIsWorkedToday(vehicle)
    return getState(vehicle).workedToday
end

---Returns true while the vehicle itself works, idle not
function RMS_Greasing.getIsWorking(vehicle)
    local implementSpec = vehicle.spec_rmsImplementGreasing
    if vehicle:doCheckSpeedLimit() or implementSpec ~= nil and implementSpec.isFeeding
        or vehicle.getIsTurnedOn ~= nil and vehicle:getIsTurnedOn()
        or vehicle.getDoConsumePtoPower ~= nil and vehicle:getDoConsumePtoPower()
        or vehicle.spec_leveler ~= nil and vehicle.spec_leveler.lastFillLevelMoved > 0 then
        return true
    end
    for _, tool in ipairs(vehicle.spec_cylindered ~= nil and vehicle.spec_cylindered.movingTools or {}) do
        -- lastAnimSpeed only on animated tools
        if tool.lastRotSpeed ~= 0 or tool.lastTransSpeed ~= 0 or (tool.lastAnimSpeed or 0) ~= 0 then
            return true
        end
    end
    return false
end

---Tells whether an implement rolls behind, a raised tool not
local function getIsTowed(child)
    return getIsTowingJoint(child:getActiveInputAttacherJoint().jointType)
end

---Tells whether the machine or what follows it works, a header trailer on the road not
local function getIsMachineWorking(vehicle)
    local isTowing = false
    for _, child in ipairs(vehicle:getChildVehicles()) do
        if RMS_Greasing.getIsWorking(child) then
            return true
        end
        isTowing = isTowing or child ~= vehicle and getIsTowed(child)
    end
    return isTowing and vehicle.spec_turnOnVehicle == nil and vehicle:getLastSpeed() > RMS_Config.GREASING.TOWING_MIN_SPEED
end

---Marks the day worked while the machine or what follows it works
-- @param float operatingDt running time since last call in ms
function RMS_Greasing.updateMachine(vehicle, operatingDt)
    if operatingDt > 0 and RMS_Greasing.getTiers(vehicle) ~= nil and not getState(vehicle).workedToday and getIsMachineWorking(vehicle) then
        RMS_Greasing.update(vehicle, operatingDt)
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

---Returns the interval greasing the driveline of a header
-- @return integer? index the interval greasing the driveline of a header
local function getDrivelineTier(vehicle)
    for index, tier in ipairs(RMS_Greasing.getTiers(vehicle) or {}) do
        if tier.isDriveline then
            return index
        end
    end
    return nil
end

---Returns the game hour
-- @return number hour of play since the first day
local function getGameHour()
    local environment = g_currentMission.environment
    return environment.currentMonotonicDay * 24 + environment.dayTime / 3600000
end

---Notes the hour a header turned, its slip clutch kept free
function RMS_Greasing.onHeaderTurned(header)
    local spec = RMS_Greasing.getSpec(header)
    if spec ~= nil then
        spec.headerTurnedHour = getGameHour()
    end
end

---Tells whether a header stood long enough to seize its slip clutch
function RMS_Greasing.getIsLimiterSeized(header)
    local spec = RMS_Greasing.getSpec(header)
    return spec ~= nil and spec.isLimiterSeized == true
end

---Returns how many times faster a header wears for its greasing
function RMS_Greasing.getHeaderWearFactor(header)
    local spec = RMS_Greasing.getSpec(header)
    return spec ~= nil and spec.greasingWearFactor or 1
end

---Seizes the slip clutch of a header left standing, its driveline due
function RMS_Greasing.onHourChanged(vehicle)
    local spec, index = RMS_Greasing.getSpec(vehicle), getDrivelineTier(vehicle)
    if index == nil or spec.isLimiterSeized or spec.headerTurnedHour == nil then
        return
    end
    -- SEIZE_DAYS of the calendar, a month lasting the days set per period
    local C = RMS_Config.CORE.HEADER_DRIVE
    if getGameHour() - spec.headerTurnedHour > C.SEIZE_DAYS / C.DAYS_PER_MONTH * g_currentMission.environment.daysPerPeriod * 24 then
        spec.isLimiterSeized = true
        local state = getState(vehicle)
        state.due[index], state.late[index] = RMS_Greasing.getTiers(vehicle)[index].points, 0
        refresh(vehicle, true)
    end
end

---Frees the slip clutch once the driveline is greased
local function releaseLimiter(vehicle)
    local spec, index = RMS_Greasing.getSpec(vehicle), getDrivelineTier(vehicle)
    if spec.isLimiterSeized and index ~= nil and getState(vehicle).due[index] == 0 then
        spec.isLimiterSeized = false
        RMS_Greasing.onHeaderTurned(vehicle)
    end
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
    releaseLimiter(vehicle)
    refresh(vehicle)
    return true
end

---Greases every point, as a workshop service does
function RMS_Greasing.greaseAll(vehicle)
    local state = getState(vehicle)
    for index in ipairs(state.due) do
        state.due[index], state.elapsed[index], state.late[index] = 0, 0, 0
    end
    releaseLimiter(vehicle)
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
