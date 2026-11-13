-- Copyright © 2026 Squallqt. All rights reserved.

---Server-authoritative workshop stock allocation and service transaction
RMS_FluidWorkshop = {}

RMS_FluidWorkshop.RESULT = {
    OK = "OK",
    MOBILE_DIAGNOSTIC = "MOBILE_DIAGNOSTIC",
    MOBILE_HEAVY_WORK = "MOBILE_HEAVY_WORK",
    MOBILE_HIGH_VOLTAGE = "MOBILE_HIGH_VOLTAGE",
    INVALID = "INVALID",
    WORKSHOP_NOT_FOUND = "WORKSHOP_NOT_FOUND",
    STOCK_INSUFFICIENT = "STOCK_INSUFFICIENT",
    PRICE_UNAVAILABLE = "PRICE_UNAVAILABLE",
    NOT_ENOUGH_MONEY = "NOT_ENOUGH_MONEY",
    SERVICE_REFUSED = "SERVICE_REFUSED",
    CONSUMPTION_FAILED = "CONSUMPTION_FAILED",
    REMAP_DEALER = "REMAP_DEALER",
    REMAP_LEASED = "REMAP_LEASED",
    REMAP_NOT_ELIGIBLE = "REMAP_NOT_ELIGIBLE"
}

RMS_FluidWorkshop.sellingPoints = {}

RMS_FluidWorkshop.RESULT_TEXT_KEYS = {
    WORKSHOP_NOT_FOUND = "rms_fluid_service_workshop_not_found",
    STOCK_INSUFFICIENT = "rms_fluid_service_stock_insufficient",
    PRICE_UNAVAILABLE = "rms_fluid_service_price_unavailable",
    NOT_ENOUGH_MONEY = "shop_messageNotEnoughMoneyToBuy",
    SERVICE_REFUSED = "rms_fluid_service_refused",
    CONSUMPTION_FAILED = "rms_fluid_service_consumption_failed",
    MOBILE_DIAGNOSTIC = "rms_mobile_workshop_diagnostic_required",
    MOBILE_HEAVY_WORK = "rms_mobile_workshop_heavy_work_required",
    MOBILE_HIGH_VOLTAGE = "rms_mobile_workshop_high_voltage_required",
    REMAP_TOP = "rms_remap_refusal_top",
    REMAP_BY_TUNER = "rms_remap_refusal_restore_tuner",
    REMAP_BY_DEALER = "rms_remap_refusal_restore_dealer",
    REMAP_LEASED = "rms_remap_refusal_leased",
    REMAP_NOT_ELIGIBLE = "rms_remap_refusal_not_eligible",
    INVALID = "rms_fluid_service_refused"
}

RMS_FluidWorkshop.REMAP_REFUSALS = { top = "REMAP_TOP", byTuner = "REMAP_BY_TUNER", byDealer = "REMAP_BY_DEALER", leased = "REMAP_LEASED",
    notEligible = "REMAP_NOT_ELIGIBLE" }

local function getIsBreakdownCoveredByRepair(breakdownId, breakdown, repairType)
    local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if definition == nil or definition.isSelectable ~= true or breakdown == nil
        or breakdown.isSelectedForRepair ~= true or breakdown.isVisible ~= true then
        return false
    end

    if repairType == RealisticMechanicalSystems.REPAIR_TYPES.LOW then
        return breakdown.isActive == true
    end
    return repairType == RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
        or repairType == RealisticMechanicalSystems.REPAIR_TYPES.HIGH
end

local function collectCoveredRepairBreakdowns(vehicle, repairType)
    local result = {}
    for breakdownId, breakdown in pairs(vehicle:getActiveBreakdowns() or {}) do
        if getIsBreakdownCoveredByRepair(breakdownId, breakdown, repairType) then
            table.insert(result, breakdownId)
        end
    end
    table.sort(result)
    return result
end

---Returns the share of a repair fluid the warranty does not supply
function RMS_FluidWorkshop.getUncoveredFluidShare(vehicle, requirement, serviceType, workshopType)
    if serviceType ~= RealisticMechanicalSystems.STATUS.REPAIR then return 1 end
    local ids = requirement.breakdownIds or {}
    if #ids == 0 then return vehicle:isWarrantyRepairCovered(workshopType) and 0 or 1 end
    local total, uncovered = 0, 0
    for _, id in ipairs(ids) do
        local debt = vehicle.spec_RealisticMechanicalSystems.fluidLeakLossDebt[id] or 0
        total = total + debt
        if not vehicle:isWarrantyRepairCovered(workshopType, id) then uncovered = uncovered + debt end
    end
    return total > 0 and uncovered / total or 0
end

local function getStockRequirements(vehicle, requirements, serviceType, workshopType)
    local result = {}
    for _, requirement in ipairs(requirements) do
        local share = RMS_FluidWorkshop.getUncoveredFluidShare(vehicle, requirement, serviceType, workshopType)
        if share > 0 then
            local line = RMS_Utils.shallowCopy(requirement)
            line.liters = requirement.liters * share
            table.insert(result, line)
        end
    end
    return result
end

---Tells whether a workshop tops the fluids up
function RMS_FluidWorkshop.getIsTopUpOffered(workshopType)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
end

---Returns workshop equipment requirements.
function RMS_FluidWorkshop.getWorkshopAvailability(vehicle, serviceType, workshopType, optionOne)
    local workshops = RealisticMechanicalSystems.WORKSHOP
    if serviceType == RealisticMechanicalSystems.STATUS.REMAP then
        local isAllowed, refusal = RMS_EngineRemap.getAvailability(vehicle, workshopType, optionOne)
        if refusal ~= nil then return false, RMS_FluidWorkshop.REMAP_REFUSALS[refusal] end
        return isAllowed, not isAllowed and "INVALID" or nil
    end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil
        or workshopType ~= workshops.MOBILE and workshopType ~= workshops.OWN
        or not RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED then
        return true
    end
    local isMobile = workshopType == workshops.MOBILE
    local hasDiagnosticTool = RMS_DiagnosticTool.getConnectedTool(vehicle) ~= nil
    local states = RealisticMechanicalSystems.STATUS
    if serviceType == states.MAINTENANCE then return true end
    if serviceType == states.OVERHAUL then
        if isMobile then return false, "MOBILE_HEAVY_WORK", optionOne end
        return true
    end
    if serviceType == states.INSPECTION then
        if hasDiagnosticTool then return true end
        if optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE then
            return false, "MOBILE_DIAGNOSTIC", optionOne
        end
        if optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD then
            local spec = vehicle.spec_RealisticMechanicalSystems
            if spec.isElectricVehicle or RMS_Utils.getUsesEngineECUProfile(vehicle) then
                return false, "MOBILE_DIAGNOSTIC", optionOne
            end
        end
        return true
    end
    if serviceType == states.REPAIR then
        for _, id in ipairs(collectCoveredRepairBreakdowns(vehicle, optionOne)) do
            local requirement = RMS_Config.MAINTENANCE.REPAIR_OPERATIONS[id].mobileRequirement
            if requirement == "MOBILE_DIAGNOSTIC" and not hasDiagnosticTool
                or requirement ~= nil and requirement ~= "MOBILE_DIAGNOSTIC" and isMobile then
                return false, requirement, RMS_Utils.getBreakdownPartKey(vehicle, RMS_Breakdowns.BreakdownRegistry[id])
            end
        end
    end
    return true
end

---Formats missing workshop equipment.
function RMS_FluidWorkshop.getWorkshopRestrictionText(vehicle, serviceType, workshopType, optionOne)
    local allowed, reason, operation = RMS_FluidWorkshop.getWorkshopAvailability(vehicle, serviceType, workshopType, optionOne)
    if allowed then return "" end
    return string.format(g_i18n:getText(reason == "MOBILE_DIAGNOSTIC" and "rms_workshop_diagnostic_blocked" or "rms_mobile_workshop_operation_blocked"),
        g_i18n:getText(operation or serviceType), g_i18n:getText(RMS_FluidWorkshop.RESULT_TEXT_KEYS[reason]))
end

---Returns the exact fluid requirements used by a workshop transaction
function RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    if vehicle == nil then
        return {}
    end

    local selectedBreakdowns = serviceType == RealisticMechanicalSystems.STATUS.REPAIR
        and collectCoveredRepairBreakdowns(vehicle, optionOne) or {}
    return RMS_Fluids.getServiceRequirements(vehicle, serviceType, optionOne, optionTwo, selectedBreakdowns)
end

-- Four decimals preserve volumes above EPSILON (0.0001 L).
local MAX_LITER_DECIMAL_PLACES = 4

---Formats a fluid quantity without rounding a small positive volume to zero
function RMS_FluidWorkshop.formatLiters(liters)
    local value = math.max(tonumber(liters) or 0, 0)
    local decimalPlaces = 1

    while decimalPlaces < MAX_LITER_DECIMAL_PLACES and value > 0
        and math.floor(value * (10 ^ decimalPlaces)) == 0 do
        decimalPlaces = decimalPlaces + 1
    end

    return g_i18n:formatNumber(value, decimalPlaces)
end

local MODE_TEXT_KEYS = {
    topUp = "rms_fluid_mode_top_up",
    replace = "rms_fluid_mode_replace",
    repair = "rms_fluid_mode_repair"
}

---Formats one fluid operation as its circuit, liters and performed operation
function RMS_FluidWorkshop.formatRequirement(vehicle, circuit, liters, mode, compact)
    return string.format(
        "%s %s %s (%s)",
        g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, circuit, compact)),
        RMS_FluidWorkshop.formatLiters(liters),
        g_i18n:getText("unit_literShort"),
        g_i18n:getText(MODE_TEXT_KEYS[mode] or "rms_fluid_mode_top_up")
    )
end

---Shows a localized service transaction failure
function RMS_FluidWorkshop.showResult(result)
    local key = RMS_FluidWorkshop.RESULT_TEXT_KEYS[result]
    if key ~= nil then
        InfoDialog.show(g_i18n:getText(key))
    end
end

local function getIsScreenOnlyMobileWorkshop(workshopType)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE
        and g_modIsLoaded["FS25_mobileWorkshop"] == true
end

local function getRootVehicle(object)
    if object == nil then
        return nil
    end
    if object.getRootVehicle ~= nil then
        return object:getRootVehicle()
    end
    return object.rootVehicle or object
end

local function getDistance(objectA, objectB)
    local nodeA = objectA ~= nil and (objectA.rootNode or objectA.nodeId) or nil
    local nodeB = objectB ~= nil and (objectB.rootNode or objectB.nodeId) or nil
    if nodeA == nil or nodeB == nil then
        return math.huge
    end
    local ax, ay, az = getWorldTranslation(nodeA)
    local bx, by, bz = getWorldTranslation(nodeB)
    return MathUtil.vector3Length(ax - bx, ay - by, az - bz)
end

---Tells whether a vehicle touches the native workshop vehicle zone
function RMS_FluidWorkshop.getIsVehicleInSellingPoint(vehicle, sellingPoint)
    local targetRoot = getRootVehicle(vehicle)
    if targetRoot == nil or sellingPoint == nil then
        return false
    end

    for shapeId, inRange in pairs(sellingPoint.vehicleShapesInRange or {}) do
        if inRange and entityExists(shapeId) then
            local object = g_currentMission.nodeToObject[shapeId]
            if getRootVehicle(object) == targetRoot then
                return true
            end
        end
    end
    return false
end

---Finds the workshop selling point containing the vehicle
function RMS_FluidWorkshop.findSellingPoint(vehicle, workshopType, preferred)
    local function matchesWorkshopType(sellingPoint)
        return workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER and not sellingPoint.ownWorkshop
            or workshopType == RealisticMechanicalSystems.WORKSHOP.OWN and sellingPoint.ownWorkshop and not sellingPoint.mobileWorkshop
            or workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE and sellingPoint.mobileWorkshop
    end

    if preferred ~= nil and matchesWorkshopType(preferred)
        and RMS_FluidWorkshop.getIsVehicleInSellingPoint(vehicle, preferred) then
        return preferred
    end

    for _, sellingPoint in ipairs(RMS_FluidWorkshop.sellingPoints) do
        if matchesWorkshopType(sellingPoint) and RMS_FluidWorkshop.getIsVehicleInSellingPoint(vehicle, sellingPoint) then
            return sellingPoint
        end
    end
    return nil
end

---Collects the farm's containers in the native workshop vehicle zone
function RMS_FluidWorkshop.collectContainers(vehicle, sellingPoint, farmId)
    local containers = {}
    local seen = {}

    for shapeId, inRange in pairs(sellingPoint ~= nil and sellingPoint.vehicleShapesInRange or {}) do
        if inRange and entityExists(shapeId) then
            local object = g_currentMission.nodeToObject[shapeId]
            object = getRootVehicle(object)
            if object ~= nil and not seen[object] and object[RMS_FluidContainer.SPEC_TABLE_NAME] ~= nil
                and object:getOwnerFarmId() == farmId and object:getRMSFluidLiters() > RMS_Fluids.EPSILON then
                seen[object] = true
                table.insert(containers, {
                    object = object,
                    productKey = object:getRMSFluidProductKey(),
                    available = object:getRMSFluidLiters(),
                    percentage = object:getRMSFluidPercentage(),
                    distance = getDistance(object, vehicle),
                    networkId = NetworkUtil.getObjectId(object) or 0
                })
            end
        end
    end
    return containers
end

-- @return table? allocations liters per container, nil on shortage
-- @return table shortages missing liters by circuit
function RMS_FluidWorkshop.allocateStock(vehicle, sellingPoint, farmId, requirements)
    local containers = RMS_FluidWorkshop.collectContainers(vehicle, sellingPoint, farmId)
    local allocations = {}
    local shortages = {}

    for _, requirement in ipairs(requirements or {}) do
        local candidates = {}
        for _, container in ipairs(containers) do
            if container.available > RMS_Fluids.EPSILON
                and RMS_Fluids.getIsProductCompatible(container.productKey, requirement.circuit)
                and RMS_Fluids.getIsProductSuited(vehicle, container.productKey, requirement.circuit) then
                table.insert(candidates, container)
            end
        end

        table.sort(candidates, function(a, b)
            if math.abs(a.percentage - b.percentage) > RMS_Fluids.EPSILON then
                return a.percentage < b.percentage
            end
            if math.abs(a.distance - b.distance) > RMS_Fluids.EPSILON then
                return a.distance < b.distance
            end
            return a.networkId < b.networkId
        end)

        local remaining = math.max(tonumber(requirement.liters) or 0, 0)
        for _, container in ipairs(candidates) do
            if remaining <= RMS_Fluids.EPSILON then
                break
            end
            local amount = math.min(container.available, remaining)
            table.insert(allocations, {
                container = container.object,
                liters = amount
            })
            container.available = container.available - amount
            remaining = remaining - amount
        end

        if remaining > RMS_Fluids.EPSILON then
            shortages[requirement.circuit] = (shortages[requirement.circuit] or 0) + remaining
        end
    end
    return next(shortages) == nil and allocations or nil, shortages
end

local function getIsFluidSupplied(vehicle, serviceType, workshopType)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
        or serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE and vehicle:isLeaseMaintenanceCovered(workshopType)
end

---Tells what a farm or mobile workshop zone lacks to run a service
-- @param table jobs in their order, each { serviceType, requirements, optionOne, optionTwo }
function RMS_FluidWorkshop.getStockShortages(vehicle, sellingPoint, workshopType, jobs)
    local lines = {}
    for _, job in ipairs(jobs) do
        if not getIsFluidSupplied(vehicle, job.serviceType, workshopType) then
            for _, line in ipairs(getStockRequirements(vehicle, job.requirements, job.serviceType, workshopType)) do
                table.insert(lines, line)
            end
        end
    end
    local _, shortages = RMS_FluidWorkshop.allocateStock(vehicle,
        RMS_FluidWorkshop.findSellingPoint(vehicle, workshopType, sellingPoint), vehicle:getOwnerFarmId(), lines)
    return shortages
end

local function getDealerPricePerLiter(vehicle, circuit)
    local cheapestPerLiter = nil
    for productKey, product in pairs(RMS_Fluids.PRODUCTS) do
        if product.isStoreItem == true and product.compatibleCircuits[circuit]
            and RMS_Fluids.getIsProductSuited(vehicle, productKey, circuit) then
            for _, capacity in ipairs(product.capacities) do
                if capacity >= 200 and product.storePrices ~= nil and product.storePrices[capacity] ~= nil then
                    local perLiter = product.storePrices[capacity] / capacity
                    cheapestPerLiter = cheapestPerLiter == nil and perLiter or math.min(cheapestPerLiter, perLiter)
                end
            end
        end
    end
    return cheapestPerLiter ~= nil and RMS_Utils.getGamePrice(cheapestPerLiter) or nil
end

---Returns the dealer price of the reserved fluids
function RMS_FluidWorkshop.getDealerFluidPrice(vehicle, requirements)
    local total = 0
    for circuit, liters in pairs(RMS_Fluids.getRequiredLitersByCircuit(requirements)) do
        local pricePerLiter = getDealerPricePerLiter(vehicle, circuit)
        if pricePerLiter == nil then
            return nil
        end
        total = total + liters * pricePerLiter
    end
    return total
end

---Builds the invoice lines of a service
-- @return table lines kind, key, mode, liters and price of each line
function RMS_FluidWorkshop.buildInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo, servicePrice, requirements, isFluidBilled)
    local lines = {}

    if serviceType == RealisticMechanicalSystems.STATUS.REPAIR then
        for _, repairLine in ipairs(vehicle:getRepairPriceLines(optionOne, optionTwo, workshopType)) do
            table.insert(lines, { kind = repairLine.isPreventive and "preventive" or "repair", key = repairLine.breakdownId, liters = 0,
                price = repairLine.price,
                warrantyReason = repairLine.warrantyReason, labour = repairLine.labour, hours = repairLine.labourHours,
                parts = repairLine.parts, kit = repairLine.kit, worn = repairLine.worn, gross = repairLine.gross,
                partType = repairLine.partType, repairType = repairLine.repairType, ownParts = repairLine.ownParts,
                kitParts = repairLine.kitParts, wornParts = repairLine.wornParts, months = repairLine.warrantyReason == "part"
                    and vehicle.spec_RealisticMechanicalSystems.partWarranty[repairLine.breakdownId] - vehicle.age or nil })
        end
    elseif serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        for _, maintenanceLine in ipairs(vehicle:getMaintenancePriceLines(optionOne, optionTwo, workshopType)) do
            table.insert(lines, { kind = maintenanceLine.kind, key = maintenanceLine.key or "", liters = 0, price = maintenanceLine.price })
        end
    elseif serviceType ~= RealisticMechanicalSystems.STATUS.REFILL then
        table.insert(lines, { kind = "service", key = "", liters = 0, price = servicePrice })
    end

    for _, requirement in ipairs(requirements or {}) do
        local liters = math.max(tonumber(requirement.liters) or 0, 0)
        if liters > RMS_Fluids.EPSILON then
            table.insert(lines, {
                kind = "fluid",
                key = requirement.circuit,
                mode = requirement.mode,
                liters = liters,
                price = isFluidBilled and liters * RMS_FluidWorkshop.getUncoveredFluidShare(
                    vehicle, requirement, serviceType, workshopType) * getDealerPricePerLiter(vehicle, requirement.circuit) or 0
            })
        end
    end

    return lines
end

local function getTransactionServicePrice(vehicle, serviceType, workshopType, optionOne, optionTwo)
    if serviceType == RealisticMechanicalSystems.STATUS.REFILL then
        return 0
    end
    return math.max(tonumber(vehicle:getServicePrice(serviceType, optionOne, optionTwo, workshopType)) or 0, 0)
end

local function getIsFluidBilled(vehicle, serviceType, workshopType)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
        and not (serviceType == RealisticMechanicalSystems.STATUS.REPAIR and vehicle:isWarrantyRepairCovered(workshopType))
        and not (serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE and vehicle:isLeaseMaintenanceCovered(workshopType))
end

---Returns the displayed transaction price, dealer fluids included
function RMS_FluidWorkshop.getTransactionPrice(vehicle, serviceType, workshopType, optionOne, optionTwo)
    if vehicle == nil then
        return nil
    end

    local servicePrice = getTransactionServicePrice(vehicle, serviceType, workshopType, optionOne, optionTwo)
    if not getIsFluidBilled(vehicle, serviceType, workshopType) then
        return servicePrice
    end

    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    if RMS_FluidWorkshop.getDealerFluidPrice(vehicle, requirements) == nil then return nil end
    local total = 0
    for _, line in ipairs(RMS_FluidWorkshop.buildInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo,
        servicePrice, requirements, true)) do total = total + line.price end
    return total
end

---Returns the bill a service would charge, line by line
function RMS_FluidWorkshop.getTransactionInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo)
    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    local isFluidBilled = getIsFluidBilled(vehicle, serviceType, workshopType)
    if isFluidBilled and RMS_FluidWorkshop.getDealerFluidPrice(vehicle, requirements) == nil then
        return nil
    end
    return RMS_FluidWorkshop.buildInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo,
        getTransactionServicePrice(vehicle, serviceType, workshopType, optionOne, optionTwo), requirements, isFluidBilled)
end

-- warranty status of a repaired part, by reason
local WARRANTY_STATUS = {
    factory = "rms_ws_quote_warranty_covered", part = "rms_ws_quote_warranty_covered", used = "rms_ws_quote_warranty_used",
    expired = "rms_ws_quote_warranty_expired", own = "rms_ws_quote_warranty_own", lease = "rms_ws_quote_warranty_lease",
    remapped = "rms_ws_quote_warranty_remapped"
}
local WARRANTY_PAYS = { factory = true, part = true, used = true }
-- reasons the warranty repairs the part for, its own way
local COVERING = { factory = true, part = true }
-- the warranty that repairs the part, named before its status
local WARRANTY_LABELS = { factory = "rms_ws_quote_warranty_label_factory", part = "rms_ws_quote_warranty_label_part" }

---Says what the warranty does for a repaired part
-- @param string reason warranty reason of its line
-- @return string status words that follow the warranty label
-- @return boolean isCovered true when the warranty pays for the part
-- @return string label the warranty the status speaks of
function RMS_FluidWorkshop.getWarrantyStatus(reason)
    local label = g_i18n:getText(WARRANTY_LABELS[reason] or "rms_ws_quote_warranty_label")
    if RealisticMechanicalSystems.getIsWarrantyRefusal(reason) then
        return string.format(g_i18n:getText("rms_ws_quote_warranty_refused"), g_i18n:getText("rms_warranty_" .. reason)), false, label
    end
    return g_i18n:getText(WARRANTY_STATUS[reason]), WARRANTY_PAYS[reason] == true, label
end

-- the warranty that pays a fault, named on its green line of the quote
local COVER_NAMES = { factory = "rms_ws_quote_cover_factory", part = "rms_ws_quote_cover_part", used = "rms_ws_quote_cover_used" }

local CONSUMABLE_QUALITY_KEYS = { USED = "rms_spec_consumable_types_used", AFTERMARKET = "rms_spec_consumable_types_aftermarket",
    OEM = "rms_spec_consumable_types_oem" }

---Names a quality of filters and fluids, nil for none
function RMS_FluidWorkshop.getConsumableQualityKey(partType)
    return CONSUMABLE_QUALITY_KEYS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, partType) or ""]
end

---Labour of a quote line, its hours to a tenth under ten
function RMS_FluidWorkshop.formatLabour(hours)
    return string.format(g_i18n:getText("rms_ws_quote_labour"), g_i18n:formatNumber(hours, hours < 10 and 1 or 0))
end

---Adds to a repair group what its fault costs, then its warranty
local function addRepairLines(vehicle, group, line, price, workshopType)
    local R = RealisticMechanicalSystems
    local function sub(label, amount, isCovered)
        table.insert(group.lines, { kind = "sub", label = label, price = amount, isCovered = isCovered })
    end
    local function bullets(parts)
        for _, partId in ipairs(parts) do
            table.insert(group.lines, { kind = "bullet", label = RMS_Utils.getBreakdownPartName(partId, vehicle) })
        end
    end
    local reason = line.warrantyReason
    -- a bill logged before the quote split its costs keeps its price alone
    if line.labour ~= nil then
        local quality = g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, line.partType))
        if line.labour > 0 then
            sub(RMS_FluidWorkshop.formatLabour(line.hours), line.labour)
        end
        if line.repairType == R.REPAIR_TYPES.LOW then
            sub(g_i18n:getText("rms_ws_quote_supplies"), line.parts)
        else
            sub(string.format(g_i18n:getText(line.kind == "preventive" and "rms_ws_quote_preventive" or "rms_ws_quote_parts_fault"), quality),
                line.parts)
            bullets(line.ownParts)
            if #line.kitParts > 0 then
                local kit = R.getRenewalGroup(line.key)
                sub(string.format(g_i18n:getText("rms_ws_quote_rebuild_" .. kit.key), quality), line.kit)
                bullets(line.kitParts)
            end
            if #line.wornParts > 0 then
                sub(string.format(g_i18n:getText("rms_ws_quote_worn_parts"), quality), line.worn)
                bullets(line.wornParts)
            end
        end
        local covered = line.gross - price
        if COVER_NAMES[reason] ~= nil and covered > 0 then
            group.isFree = price <= 0
            local name = g_i18n:getText(COVER_NAMES[reason])
            -- a part still under its own warranty says for how long
            if reason == "part" and line.months ~= nil then
                name = string.format("%s · %s", name, string.format(g_i18n:getText(line.months == 1 and "rms_service_month"
                    or "rms_service_months"), line.months))
            end
            sub(name, -covered, true)
            local key = reason == "used" and "rms_ws_quote_cover_part_only"
                or (price > 0 and workshopType == R.WORKSHOP.MOBILE) and "rms_warranty_mobile" or "rms_ws_quote_cover_full"
            table.insert(group.lines, { kind = "note", label = g_i18n:getText(key), isCovered = key == "rms_ws_quote_cover_full" })
            return
        end
    end
    -- an ended warranty is left to the corner of the table
    if reason ~= nil and reason ~= "expired" and (WARRANTY_STATUS[reason] ~= nil or R.getIsWarrantyRefusal(reason)) then
        local status, isCovered, label = RMS_FluidWorkshop.getWarrantyStatus(reason)
        group.isFree = isCovered and price <= 0
        table.insert(group.lines, { kind = "note", label = label .. " " .. status, isCovered = isCovered, isWarning = not isCovered })
    end
end

---Builds the quote of a service from its bill, as each page shows it
-- @param string? workshopType workshop that does or did the work
-- @return table groups label, price, isFree and lines (kind sub, bullet or note) of each group
function RMS_FluidWorkshop.getQuoteGroups(vehicle, serviceType, optionOne, optionTwo, invoice, workshopType)
    local R = RealisticMechanicalSystems
    local groups, maintenance, fluids = {}, nil, nil
    -- beside a paid fault, one the warranty repairs says how
    local hasCovered, hasPaid = false, false
    for _, line in ipairs(invoice or {}) do
        if line.kind == "repair" then
            hasCovered = hasCovered or COVERING[line.warrantyReason] == true
            hasPaid = hasPaid or COVERING[line.warrantyReason] == nil
        end
    end
    for _, line in ipairs(invoice or {}) do
        local price = tonumber(line.price) or 0
        if (line.kind == "repair" or line.kind == "preventive") and serviceType == R.STATUS.REPAIR then
            local label = RMS_Utils.getBreakdownPartName(line.key, vehicle)
            if hasCovered and hasPaid and COVERING[line.warrantyReason] then
                label = string.format("%s · %s · %s", label, g_i18n:getText(R.REPAIR_TYPES.MEDIUM), g_i18n:getText(R.PART_TYPES.OEM))
            end
            local group = { label = label, price = price, lines = {} }
            table.insert(groups, group)
            addRepairLines(vehicle, group, line, price, workshopType)
        elseif line.kind == "labour" or line.kind == "filters" or line.kind == "repair" then
            if maintenance == nil then
                maintenance = { label = RMS_Utils.formatServiceOption(vehicle, serviceType, optionOne, workshopType), price = 0, lines = {} }
                table.insert(groups, maintenance)
            end
            maintenance.price = maintenance.price + price
            if line.kind == "labour" then
                table.insert(maintenance.lines, { kind = "sub", label = RMS_FluidWorkshop.formatLabour(R.getServiceWorkHours(vehicle, serviceType, optionOne)),
                    price = price })
            elseif line.kind == "filters" then
                local qualityKey = RMS_FluidWorkshop.getConsumableQualityKey(optionTwo)
                table.insert(maintenance.lines, { kind = "sub", price = price, label = qualityKey ~= nil
                    and string.format(g_i18n:getText("rms_ws_quote_filters"), g_i18n:getText(qualityKey)) or g_i18n:getText("rms_log_invoice_filters") })
                for _, name in ipairs(RMS_WorkshopOrders.getFittedFilters(vehicle, optionOne)) do
                    table.insert(maintenance.lines, { kind = "bullet", label = name })
                end
            else
                table.insert(maintenance.lines, { kind = "sub", label = RMS_Utils.getBreakdownPartName(line.key, vehicle), price = price })
            end
        elseif line.kind == "fluid" then
            if fluids == nil then
                fluids = { label = g_i18n:getText("rms_ws_section_fluids"), lines = {}, priced = 0 }
                table.insert(groups, fluids)
            end
            table.insert(fluids.lines, { kind = "sub", label = RMS_FluidWorkshop.formatRequirement(vehicle, line.key, line.liters, line.mode, true),
                price = price > 0 and price or nil, circuit = line.key })
            if price > 0 then
                fluids.price, fluids.priced = (fluids.price or 0) + price, fluids.priced + 1
            end
        elseif line.kind == "service" then
            local labelKey = (serviceType == R.STATUS.BODYWORK or serviceType == R.STATUS.REMAP) and optionOne or "rms_log_invoice_workshop_flat_rate"
            table.insert(groups, { label = g_i18n:getText(labelKey), price = price, lines = {} })
        end
    end
    -- a flat rate alone repeats the price
    if #groups == 1 and invoice[1].kind == "service" then
        return {}
    end
    -- a fluid billed alone or by a repair leaves its amount to its head
    if fluids ~= nil and (fluids.priced == 1 or serviceType == R.STATUS.REPAIR) then
        for _, line in ipairs(fluids.lines) do
            line.price = nil
        end
    end
    return groups
end

-- quote rows in reference pixels, as in their list templates
local QUOTE_HEAD, QUOTE_HEAD_GAP, QUOTE_LINE, QUOTE_NOTE = 20, 7, 17, 16
local QUOTE_INDENT, QUOTE_NOTE_X, QUOTE_BULLET_TEXT, QUOTE_AMOUNT, QUOTE_GAP = 12, 24, 37, 62, 6
-- textColor of rms_workshopRecapQuoteName
local COLOR_QUOTE_LINE = { 0.5028, 0.5028, 0.5028, 1 }

---Whether a quote line is drawn as a note: a bullet or a sentence
local function getIsQuoteNote(line)
    return line.kind == "bullet" or line.kind == "note" or line.note ~= nil
end

---Lays the groups of a quote out as the rows of its list
-- @return table rows heads and lines of the groups, in order
-- @return number height of the rows in reference pixels
function RMS_FluidWorkshop.getQuoteRows(groups)
    local rows, height = {}, 0
    for index, group in ipairs(groups) do
        table.insert(rows, { isHead = true, isFirst = index == 1, label = group.label, price = group.price, value = group.value,
            isLoss = group.isLoss, isFree = group.isFree })
        height = height + QUOTE_HEAD + (index == 1 and 0 or QUOTE_HEAD_GAP)
        for _, line in ipairs(group.lines) do
            table.insert(rows, line)
            height = height + (getIsQuoteNote(line) and QUOTE_NOTE or QUOTE_LINE)
        end
    end
    return rows, height
end

---Names the list template that draws a row of a quote
function RMS_FluidWorkshop.getQuoteCellType(row)
    if row == nil then
        return "quoteLine"
    elseif row.isHead then
        return row.isFirst and "quoteHead" or "quoteHeadGap"
    elseif row.isAlert then
        return "quoteAlert"
    end
    return getIsQuoteNote(row) and "quoteNote" or "quoteLine"
end

---Writes a row of a quote into its list cell
-- @param float ux screen width of a reference pixel
-- @param number width width of the rows in reference pixels
function RMS_FluidWorkshop.populateQuoteCell(cell, row, ux, width)
    local green = RMS_Utils.COLOR.HIGHLIGHT
    if row.isAlert then
        cell:getAttribute("quoteAlertText"):setText(row.label)
        return
    elseif getIsQuoteNote(row) then
        local note, isBullet = cell:getAttribute("quoteNoteText"), row.kind == "bullet"
        local textX = isBullet and QUOTE_BULLET_TEXT or QUOTE_NOTE_X
        cell:getAttribute("quoteNoteBullet"):setVisible(isBullet)
        note:setPosition(textX * ux, nil)
        note:setSize((width - textX) * ux, nil)
        -- a list reuses its cells: each colour is set each time
        note:setTextColor(unpack(row.isCovered and green or row.isWarning and RMS_Breakdowns.COLORS.WARNING or COLOR_QUOTE_LINE))
        note:setText(row.label or row.note)
        return
    end
    local name, amount = cell:getAttribute("quoteName"), cell:getAttribute("quoteAmount")
    local nameX = row.isHead and 0 or QUOTE_INDENT
    if row.isHead and not row.isFirst then
        cell:getAttribute("quoteRule"):setSize(width * ux, nil)
    end
    if row.isHead then
        amount:setTextColor(unpack(row.isLoss and RMS_Utils.COLOR.ALERT or row.isFree and green or RMS_Utils.COLOR.TEXT))
    else
        name:setTextColor(unpack(row.isCovered and green or COLOR_QUOTE_LINE))
        amount:setTextColor(unpack((row.isCovered or row.isFree) and green or COLOR_QUOTE_LINE))
    end
    -- a line without an amount takes the width of the row
    local amountRoom = (row.isHead or row.price ~= nil or row.value ~= nil) and QUOTE_AMOUNT + QUOTE_GAP or 0
    name:setSize((width - nameX - amountRoom) * ux, nil)
    name:setText(row.label)
    amount:setPosition((width - QUOTE_AMOUNT) * ux, nil)
    amount:setText(row.value or row.price ~= nil and g_i18n:formatMoney(row.price, 0, true, false) or "")
end

---Starts, consumes and charges one service as a single server transaction
function RMS_FluidWorkshop.tryStartService(vehicle, sellingPoint, serviceType, workshopType, optionOne, optionTwo, requestingFarmId)
    if g_server == nil or vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return false, RMS_FluidWorkshop.RESULT.INVALID
    end

    if RealisticMechanicalSystems.isMissionVehicle(vehicle)
        or vehicle:getCurrentStatus() ~= RealisticMechanicalSystems.STATUS.READY
        or (vehicle.spec_RealisticMechanicalSystems.maintenanceTimer or 0) ~= 0 then
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    if requestingFarmId ~= nil and requestingFarmId ~= vehicle:getOwnerFarmId() then
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    if serviceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        local eligibleSystems = RMS_Utils.getEligibleOverhaulSystems(vehicle)
        if #eligibleSystems == 0 or (optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
            and RMS_Utils.getKeyByValue(eligibleSystems, optionTwo) == nil) then
            return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
        end
    end

    if serviceType == RealisticMechanicalSystems.STATUS.BODYWORK
        and not RMS_Bodywork.isAllowed(vehicle, workshopType, optionOne, optionTwo) then
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    local isAllowed, refusal = RMS_FluidWorkshop.getWorkshopAvailability(vehicle, serviceType, workshopType, optionOne)
    if not isAllowed then return false, RMS_FluidWorkshop.RESULT[refusal] end

    sellingPoint = RMS_FluidWorkshop.findSellingPoint(vehicle, workshopType, sellingPoint)
    if sellingPoint == nil and not getIsScreenOnlyMobileWorkshop(workshopType) then
        return false, RMS_FluidWorkshop.RESULT.WORKSHOP_NOT_FOUND
    end

    local farmId = vehicle:getOwnerFarmId()
    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    local allocations = {}
    local isFluidBilled = getIsFluidBilled(vehicle, serviceType, workshopType)

    if getIsFluidSupplied(vehicle, serviceType, workshopType) then
        if isFluidBilled then
            if RMS_FluidWorkshop.getDealerFluidPrice(vehicle, requirements) == nil then
                return false, RMS_FluidWorkshop.RESULT.PRICE_UNAVAILABLE
            end
        end
    else
        allocations = RMS_FluidWorkshop.allocateStock(vehicle, sellingPoint, farmId,
            getStockRequirements(vehicle, requirements, serviceType, workshopType))
        if allocations == nil then
            return false, RMS_FluidWorkshop.RESULT.STOCK_INSUFFICIENT
        end
    end

    local servicePrice = getTransactionServicePrice(vehicle, serviceType, workshopType, optionOne, optionTwo)
    local totalPrice = 0
    local invoice = RMS_FluidWorkshop.buildInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo,
        servicePrice, requirements, isFluidBilled)
    for _, line in ipairs(invoice) do totalPrice = totalPrice + line.price end
    if totalPrice > 0 and (g_currentMission:getMoney(farmId) or 0) < totalPrice then
        return false, RMS_FluidWorkshop.RESULT.NOT_ENOUGH_MONEY
    end

    local touched = {}
    for _, allocation in ipairs(allocations) do
        if not touched[allocation.container] then
            touched[allocation.container] = true
            allocation.container:beginRMSFluidTransaction()
        end
    end

    local started = vehicle:initService(serviceType, workshopType, optionOne, optionTwo)
    if not started then
        for container in pairs(touched) do
            container:endRMSFluidTransaction(false)
        end
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    if RMS_Fluids.serializeServiceRequirements(requirements)
        ~= RMS_Fluids.serializeServiceRequirements(vehicle.spec_RealisticMechanicalSystems.pendingFluidRequirements) then
        for container in pairs(touched) do
            container:endRMSFluidTransaction(false)
        end
        vehicle:cancelService()
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    local consumed = {}
    local consumptionSucceeded = true
    for _, allocation in ipairs(allocations) do
        local removed = allocation.container:removeRMSFluidLiters(allocation.liters)
        table.insert(consumed, {
            container = allocation.container,
            liters = removed
        })
        if math.abs(removed - allocation.liters) > RMS_Fluids.EPSILON then
            consumptionSucceeded = false
            break
        end
    end

    if not consumptionSucceeded then
        for _, entry in ipairs(consumed) do
            entry.container:restoreRMSFluidLiters(entry.liters)
        end
        for container in pairs(touched) do
            container:endRMSFluidTransaction(false)
        end
        vehicle:cancelService()
        return false, RMS_FluidWorkshop.RESULT.CONSUMPTION_FAILED
    end

    for container in pairs(touched) do
        container:endRMSFluidTransaction(true)
    end
    vehicle.spec_RealisticMechanicalSystems.pendingServicePrice = totalPrice
    vehicle.spec_RealisticMechanicalSystems.pendingServiceInvoice = invoice
    if totalPrice > 0 then
        g_currentMission:addMoney(-totalPrice, farmId, MoneyType.VEHICLE_RUNNING_COSTS, true, true)
    end
    return true, RMS_FluidWorkshop.RESULT.OK
end

VehicleSellingPoint.load = Utils.appendedFunction(VehicleSellingPoint.load, function(self)
    table.insert(RMS_FluidWorkshop.sellingPoints, self)
end)

VehicleSellingPoint.delete = Utils.appendedFunction(VehicleSellingPoint.delete, function(self)
    for index, sellingPoint in ipairs(RMS_FluidWorkshop.sellingPoints) do
        if sellingPoint == self then
            table.remove(RMS_FluidWorkshop.sellingPoints, index)
            return
        end
    end
end)
