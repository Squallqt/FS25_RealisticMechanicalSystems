-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

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
    CONSUMPTION_FAILED = "CONSUMPTION_FAILED"
}

-- every loaded selling point in load order, placeable or workshop vehicle
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
    INVALID = "rms_fluid_service_refused"
}

---Tells whether a breakdown is covered by the requested player repair
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

---Collects the deterministically ordered breakdown ids covered by a repair
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


---Tells whether a workshop tops the fluids up
-- @param string workshopType workshop type
-- @return boolean isOffered true at the dealer
function RMS_FluidWorkshop.getIsTopUpOffered(workshopType)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
end

---Returns what a mobile workshop lacks for a selection, and the operation blocked
function RMS_FluidWorkshop.getMobileWorkshopAvailability(vehicle, serviceType, workshopType, optionOne)
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil
        or workshopType ~= RealisticMechanicalSystems.WORKSHOP.MOBILE
        or not RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED then
        return true
    end
    local states = RealisticMechanicalSystems.STATUS
    if serviceType == states.MAINTENANCE then return true end
    if serviceType == states.OVERHAUL then return false, "MOBILE_HEAVY_WORK", optionOne end
    if serviceType == states.INSPECTION then
        if optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE then
            return false, "MOBILE_DIAGNOSTIC", optionOne
        end
        if optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD then
            local spec = vehicle.spec_RealisticMechanicalSystems
            -- the electronic systems RMS represents, not a whole brand
            if spec.isElectricVehicle or RMS_Utils.getUsesEngineECUProfile(vehicle) then
                return false, "MOBILE_DIAGNOSTIC", optionOne
            end
        end
        return true
    end
    if serviceType == states.REPAIR then
        for _, id in ipairs(collectCoveredRepairBreakdowns(vehicle, optionOne)) do
            local operation = RMS_Config.MAINTENANCE.REPAIR_OPERATIONS[id]
            local requirement = operation.mobileRequirement
            if requirement then
                local definition = RMS_Breakdowns.BreakdownRegistry[id]
                return false, requirement, definition.part
            end
        end
    end
    return true
end

---Formats the refusal of a mobile workshop
function RMS_FluidWorkshop.getMobileWorkshopRestrictionText(vehicle, serviceType, workshopType, optionOne)
    local allowed, reason, operation = RMS_FluidWorkshop.getMobileWorkshopAvailability(vehicle, serviceType, workshopType, optionOne)
    if allowed then return "" end
    return string.format(g_i18n:getText("rms_mobile_workshop_operation_blocked"),
        g_i18n:getText(operation or serviceType), g_i18n:getText(RMS_FluidWorkshop.RESULT_TEXT_KEYS[reason]))
end

---Returns the exact fluid requirements used by a workshop transaction
-- @param table vehicle vehicle
-- @param string serviceType service status
-- @param string? optionOne first service option
-- @param string? optionTwo second service option
-- @return table requirements ordered requirements
function RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    if vehicle == nil then
        return {}
    end

    local selectedBreakdowns = serviceType == RealisticMechanicalSystems.STATUS.REPAIR
        and collectCoveredRepairBreakdowns(vehicle, optionOne) or {}
    return RMS_Fluids.getServiceRequirements(vehicle, serviceType, optionOne, optionTwo, selectedBreakdowns)
end

-- four decimals keep volumes above RMS_Fluids.EPSILON (0.0001 L)
local MAX_LITER_DECIMAL_PLACES = 4

---Formats a fluid quantity without rounding a small positive volume to zero
-- @param float liters fluid quantity
-- @return string formatted quantity
function RMS_FluidWorkshop.formatLiters(liters)
    local value = math.max(tonumber(liters) or 0, 0)
    local decimalPlaces = 1

    while decimalPlaces < MAX_LITER_DECIMAL_PLACES and value > 0
        and math.floor(value * (10 ^ decimalPlaces)) == 0 do
        decimalPlaces = decimalPlaces + 1
    end

    return g_i18n:formatNumber(value, decimalPlaces)
end

local CIRCUIT_TEXT_KEYS = {
    engineOil = "rms_inspection_engine_oil",
    coolant = "rms_inspection_coolant",
    transmissionOil = "rms_inspection_transmission_oil",
    hydraulicFluid = "rms_inspection_hydraulic_fluid"
}

local MODE_TEXT_KEYS = {
    topUp = "rms_fluid_mode_top_up",
    replace = "rms_fluid_mode_replace",
    repair = "rms_fluid_mode_repair"
}

---Formats one fluid operation as its circuit, liters and performed operation
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @param float liters fluid quantity
-- @param string? mode performed operation
-- @param boolean? compact true for the short name of a common transmission and hydraulic sump
-- @return string text localized requirement
function RMS_FluidWorkshop.formatRequirement(vehicle, circuit, liters, mode, compact)
    local key = RMS_Fluids.getCircuitTextKey(vehicle, circuit, CIRCUIT_TEXT_KEYS[circuit] or circuit)
    if compact and key == RMS_Fluids.COMMON_SUMP_TEXT_KEY then
        key = "rms_fluid_hud_transmissionHydraulic"
    end
    return string.format(
        "%s %s %s (%s)",
        g_i18n:getText(key),
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

---
local function getIsScreenOnlyMobileWorkshop(workshopType)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE
        and g_modIsLoaded["FS25_mobileWorkshop"] == true
end

---
local function getRootVehicle(object)
    if object == nil then
        return nil
    end
    if object.getRootVehicle ~= nil then
        return object:getRootVehicle()
    end
    return object.rootVehicle or object
end

---
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
    ---
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

---Allocates stock per container without changing game state, with what is missing
-- @return table? allocations liters drawn from each container, nil when a fluid runs short
-- @return table shortages liters missing by circuit, empty when the stock covers every requirement
function RMS_FluidWorkshop.allocateStock(vehicle, sellingPoint, farmId, requirements)
    local containers = RMS_FluidWorkshop.collectContainers(vehicle, sellingPoint, farmId)
    local allocations = {}
    local shortages = {}

    for _, requirement in ipairs(requirements or {}) do
        local candidates = {}
        for _, container in ipairs(containers) do
            if container.available > RMS_Fluids.EPSILON
                and RMS_Fluids.getIsProductCompatible(container.productKey, requirement.circuit) then
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

---Tells whether the workshop brings the fluids of a service
local function getIsFluidSupplied(vehicle, serviceType, workshopType)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
        or serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE and vehicle:isLeaseMaintenanceCovered(workshopType)
end

---Tells what a farm or mobile workshop zone lacks to run a service
-- @param table vehicle vehicle
-- @param table? sellingPoint workshop the screen is opened on
-- @param string serviceType service status
-- @param string workshopType workshop type
-- @param table requirements fluids the service needs
-- @return table shortages liters missing by circuit, empty when the workshop brings the fluids and when the stock
function RMS_FluidWorkshop.getStockShortages(vehicle, sellingPoint, serviceType, workshopType, requirements)
    if getIsFluidSupplied(vehicle, serviceType, workshopType) then
        return {}
    end
    local _, shortages = RMS_FluidWorkshop.allocateStock(vehicle,
        RMS_FluidWorkshop.findSellingPoint(vehicle, workshopType, sellingPoint), vehicle:getOwnerFarmId(), requirements)
    return shortages
end

---Returns the dealer price of a liter of a circuit, from its cheapest drum
local function getDealerPricePerLiter(circuit)
    local cheapestPerLiter = nil
    for _, product in pairs(RMS_Fluids.PRODUCTS) do
        if product.isStoreItem == true and product.compatibleCircuits[circuit] then
            for _, capacity in ipairs(product.capacities) do
                if capacity >= 200 and product.storePrices ~= nil and product.storePrices[capacity] ~= nil then
                    local perLiter = product.storePrices[capacity] / capacity
                    cheapestPerLiter = cheapestPerLiter == nil and perLiter or math.min(cheapestPerLiter, perLiter)
                end
            end
        end
    end
    return cheapestPerLiter
end

---Returns the dealer price of the reserved fluids
function RMS_FluidWorkshop.getDealerFluidPrice(requirements)
    local total = 0
    for circuit, liters in pairs(RMS_Fluids.getRequiredLitersByCircuit(requirements)) do
        local pricePerLiter = getDealerPricePerLiter(circuit)
        if pricePerLiter == nil then
            return nil
        end
        total = total + liters * pricePerLiter
    end
    return total
end

---Builds the invoice lines of a service
-- @param table vehicle vehicle
-- @param string serviceType service status
-- @param string? workshopType workshop type
-- @param string? optionOne first service option
-- @param string? optionTwo second service option
-- @param float servicePrice charged procedure price
-- @param table requirements fluid requirements of the service
-- @param boolean isFluidBilled true when the dealer supplies and bills the fluids
-- @return table lines kind, key, mode, liters and price of each line
function RMS_FluidWorkshop.buildInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo, servicePrice, requirements, isFluidBilled)
    local lines = {}

    if serviceType == RealisticMechanicalSystems.STATUS.REPAIR then
        for _, repairLine in ipairs(vehicle:getRepairPriceLines(optionOne, optionTwo, workshopType)) do
            table.insert(lines, { kind = "repair", key = repairLine.breakdownId, liters = 0, price = repairLine.price })
        end
    elseif serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        for _, maintenanceLine in ipairs(vehicle:getMaintenancePriceLines(optionOne, optionTwo, workshopType)) do
            table.insert(lines, { kind = maintenanceLine.kind, key = "", liters = 0, price = maintenanceLine.price })
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
                price = isFluidBilled and liters * getDealerPricePerLiter(requirement.circuit) or 0
            })
        end
    end

    return lines
end

---Returns the procedure charge when fluid supply is not priced separately
local function getTransactionServicePrice(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree)
    if serviceType == RealisticMechanicalSystems.STATUS.REFILL then
        return 0
    end
    return math.max(tonumber(vehicle:getServicePrice(serviceType, optionOne, optionTwo, optionThree, workshopType)) or 0, 0)
end

---Tells whether the fluids of a service are bought from the dealer
local function getIsFluidBilled(vehicle, serviceType, workshopType, optionOne, optionTwo)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
        and not (serviceType == RealisticMechanicalSystems.STATUS.REPAIR
            and vehicle:isWarrantyRepairCovered(optionOne, optionTwo, workshopType))
        and not (serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE and vehicle:isLeaseMaintenanceCovered(workshopType))
end

---Returns the displayed transaction price, dealer fluids included
function RMS_FluidWorkshop.getTransactionPrice(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree)
    if vehicle == nil then
        return nil
    end

    local servicePrice = getTransactionServicePrice(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree)
    if not getIsFluidBilled(vehicle, serviceType, workshopType, optionOne, optionTwo) then
        return servicePrice
    end

    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    local dealerFluidPrice = RMS_FluidWorkshop.getDealerFluidPrice(requirements)
    return dealerFluidPrice ~= nil and servicePrice + dealerFluidPrice or nil
end

---Returns the bill a service would charge, line by line
-- @return table? lines invoice lines, nil while a fluid the dealer bills has no price
function RMS_FluidWorkshop.getTransactionInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree)
    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    local isFluidBilled = getIsFluidBilled(vehicle, serviceType, workshopType, optionOne, optionTwo)
    if isFluidBilled and RMS_FluidWorkshop.getDealerFluidPrice(requirements) == nil then
        return nil
    end
    return RMS_FluidWorkshop.buildInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo,
        getTransactionServicePrice(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree), requirements, isFluidBilled)
end

---Lists the rows of a bill, the repairs of one part merged
-- @param table vehicle vehicle
-- @param string serviceType service type
-- @param string? optionOne first service option, naming a bodywork
-- @param table invoice invoice lines
-- @return table rows kind, label and price of each row
function RMS_FluidWorkshop.getInvoiceRows(vehicle, serviceType, optionOne, invoice)
    local rows = {}
    local repairRowsByLabel = {}
    for _, line in ipairs(invoice) do
        local price = tonumber(line.price) or 0
        if line.kind == "service" then
            local labelKey = serviceType == RealisticMechanicalSystems.STATUS.BODYWORK and optionOne
                or "rms_log_invoice_workshop_flat_rate"
            table.insert(rows, { kind = line.kind, label = g_i18n:getText(labelKey), price = price })
        elseif line.kind == "labour" or line.kind == "filters" then
            table.insert(rows, { kind = line.kind, label = g_i18n:getText("rms_log_invoice_" .. line.kind), price = price })
        elseif line.kind == "repair" then
            local breakdownDef = RMS_Breakdowns.BreakdownRegistry[line.key]
            local partKey = breakdownDef ~= nil and (breakdownDef.part or breakdownDef.system) or "rms_log_repair_desc_generic"
            local label = g_i18n:getText(partKey)
            if repairRowsByLabel[label] ~= nil then
                repairRowsByLabel[label].price = repairRowsByLabel[label].price + price
            else
                repairRowsByLabel[label] = { kind = line.kind, label = label, price = price }
                table.insert(rows, repairRowsByLabel[label])
            end
        elseif line.kind == "fluid" then
            table.insert(rows, { kind = line.kind, label = RMS_FluidWorkshop.formatRequirement(vehicle, line.key, line.liters, line.mode, true),
                price = price > 0 and price or nil, circuit = line.key })
        end
    end

    -- a lone flat rate is already the price shown above
    if #rows == 1 and invoice[1].kind == "service" then
        return {}
    end
    return rows
end

---Starts, consumes and charges one service as a single server transaction
function RMS_FluidWorkshop.tryStartService(vehicle, sellingPoint, serviceType, workshopType, optionOne, optionTwo, optionThree, requestingFarmId)
    if g_server == nil or vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return false, RMS_FluidWorkshop.RESULT.INVALID
    end

    if vehicle:getCurrentStatus() ~= RealisticMechanicalSystems.STATUS.READY
        or (vehicle.spec_RealisticMechanicalSystems.maintenanceTimer or 0) ~= 0 then
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    if requestingFarmId ~= nil and requestingFarmId ~= vehicle:getOwnerFarmId() then
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    if serviceType == RealisticMechanicalSystems.STATUS.OVERHAUL and optionThree == true then
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

    local isAllowed, refusal = RMS_FluidWorkshop.getMobileWorkshopAvailability(vehicle, serviceType, workshopType, optionOne)
    if not isAllowed then return false, RMS_FluidWorkshop.RESULT[refusal] end

    sellingPoint = RMS_FluidWorkshop.findSellingPoint(vehicle, workshopType, sellingPoint)
    if sellingPoint == nil and not getIsScreenOnlyMobileWorkshop(workshopType) then
        return false, RMS_FluidWorkshop.RESULT.WORKSHOP_NOT_FOUND
    end

    local farmId = vehicle:getOwnerFarmId()
    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    local allocations = {}
    local dealerFluidPrice = 0
    local isFluidBilled = getIsFluidBilled(vehicle, serviceType, workshopType, optionOne, optionTwo)

    if getIsFluidSupplied(vehicle, serviceType, workshopType) then
        if isFluidBilled then
            dealerFluidPrice = RMS_FluidWorkshop.getDealerFluidPrice(requirements)
            if dealerFluidPrice == nil then
                return false, RMS_FluidWorkshop.RESULT.PRICE_UNAVAILABLE
            end
        end
    else
        allocations = RMS_FluidWorkshop.allocateStock(vehicle, sellingPoint, farmId, requirements)
        if allocations == nil then
            return false, RMS_FluidWorkshop.RESULT.STOCK_INSUFFICIENT
        end
    end

    local servicePrice = getTransactionServicePrice(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree)
    local totalPrice = servicePrice + dealerFluidPrice
    local invoice = RMS_FluidWorkshop.buildInvoice(vehicle, serviceType, workshopType, optionOne, optionTwo,
        servicePrice, requirements, isFluidBilled)
    if (g_currentMission:getMoney(farmId) or 0) < totalPrice then
        return false, RMS_FluidWorkshop.RESULT.NOT_ENOUGH_MONEY
    end

    local touched = {}
    for _, allocation in ipairs(allocations) do
        if not touched[allocation.container] then
            touched[allocation.container] = true
            allocation.container:beginRMSFluidTransaction()
        end
    end

    local started = vehicle:initService(serviceType, workshopType, optionOne, optionTwo, optionThree)
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
