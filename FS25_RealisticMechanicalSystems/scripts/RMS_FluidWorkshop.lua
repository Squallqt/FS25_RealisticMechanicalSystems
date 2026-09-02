-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Server-authoritative workshop stock allocation and service transaction
RMS_FluidWorkshop = {}

RMS_FluidWorkshop.RESULT = {
    OK = "OK",
    INVALID = "INVALID",
    WORKSHOP_NOT_FOUND = "WORKSHOP_NOT_FOUND",
    STOCK_INSUFFICIENT = "STOCK_INSUFFICIENT",
    PRICE_UNAVAILABLE = "PRICE_UNAVAILABLE",
    NOT_ENOUGH_MONEY = "NOT_ENOUGH_MONEY",
    SERVICE_REFUSED = "SERVICE_REFUSED",
    CONSUMPTION_FAILED = "CONSUMPTION_FAILED"
}

-- every loaded selling point, in load order, whatever carries it, a placeable or a workshop vehicle
RMS_FluidWorkshop.sellingPoints = {}

RMS_FluidWorkshop.RESULT_TEXT_KEYS = {
    WORKSHOP_NOT_FOUND = "rms_fluid_service_workshop_not_found",
    STOCK_INSUFFICIENT = "rms_fluid_service_stock_insufficient",
    PRICE_UNAVAILABLE = "rms_fluid_service_price_unavailable",
    NOT_ENOUGH_MONEY = "shop_messageNotEnoughMoneyToBuy",
    SERVICE_REFUSED = "rms_fluid_service_refused",
    CONSUMPTION_FAILED = "rms_fluid_service_consumption_failed",
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

---Tells whether the mobile workshop accepts a procedure at the vehicle maintainability
-- @param table? vehicle vehicle
-- @param string? serviceType service status constant
-- @param string? workshopType workshop type
-- @param string? optionOne first service option
-- @return boolean isAllowed true outside the mobile workshop or when restrictions are off
function RMS_FluidWorkshop.getMobileWorkshopAvailability(vehicle, serviceType, workshopType, optionOne)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if vehicle == nil or spec == nil or workshopType ~= RealisticMechanicalSystems.WORKSHOP.MOBILE then
        return true
    end

    if not RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED then
        return true
    end

    local serviceKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.STATUS, serviceType)
    local optionValues
    if serviceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        optionValues = RealisticMechanicalSystems.INSPECTION_TYPES
    elseif serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        optionValues = RealisticMechanicalSystems.MAINTENANCE_TYPES
    elseif serviceType == RealisticMechanicalSystems.STATUS.REPAIR then
        optionValues = RealisticMechanicalSystems.REPAIR_TYPES
    elseif serviceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        optionValues = RealisticMechanicalSystems.OVERHAUL_TYPES
    end
    local optionKey = optionValues ~= nil and RMS_Utils.getKeyByValue(optionValues, optionOne) or nil
    local limits = RMS_Config.WORKSHOP.MOBILE_WORKSHOP_SERVICES_BY_MAINTAINABILITY
    local serviceLimits = limits ~= nil and serviceKey ~= nil and limits[serviceKey] or nil
    local requiredMaintainability = serviceLimits ~= nil and optionKey ~= nil and serviceLimits[optionKey] or 0

    return (tonumber(spec.maintainability) or 0) >= requiredMaintainability
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

---Returns the context-specific label for transaction fluid requirements
-- @param string? workshopType workshop type
-- @return string textKey localization key
function RMS_FluidWorkshop.getRequirementsTextKey(workshopType)
    if workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER then
        return "rms_fluid_dealer_billed"
    end
    return "rms_fluid_stock_required"
end

---Formats transaction fluid requirements for service option dialogs
-- @param table? requirements ordered requirements
-- @return string text localized circuit labels, liters and performed operations
function RMS_FluidWorkshop.formatTransactionRequirements(requirements)
    local textKeys = {
        engineOil = "rms_inspection_engine_oil",
        coolant = "rms_inspection_coolant",
        transmissionOil = "rms_inspection_transmission_oil",
        hydraulicFluid = "rms_inspection_hydraulic_fluid"
    }
    local modeTextKeys = {
        topUp = "rms_fluid_mode_top_up",
        replace = "rms_fluid_mode_replace",
        repair = "rms_fluid_mode_repair"
    }
    local unit = g_i18n:getText("unit_literShort")
    local values = {}

    for _, requirement in ipairs(requirements or {}) do
        local circuit = requirement.circuit
        local liters = math.max(tonumber(requirement.liters) or 0, 0)
        local modeTextKey = modeTextKeys[requirement.mode]
        if liters > RMS_Fluids.EPSILON then
            table.insert(values, string.format(
                "%s %s %s (%s)",
                g_i18n:getText(textKeys[circuit] or circuit),
                g_i18n:formatNumber(liters, 1),
                unit,
                g_i18n:getText(modeTextKey or "rms_fluid_mode_top_up")
            ))
        end
    end

    return table.concat(values, " · ")
end

---Shows a localized service transaction failure
function RMS_FluidWorkshop.showResult(result)
    local key = RMS_FluidWorkshop.RESULT_TEXT_KEYS[result]
    if key ~= nil and InfoDialog ~= nil and InfoDialog.show ~= nil then
        InfoDialog.show(g_i18n:getText(key))
    end
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

---Tells whether a root vehicle currently touches the native workshop vehicle zone
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
    if preferred ~= nil and RMS_FluidWorkshop.getIsVehicleInSellingPoint(vehicle, preferred) then
        return preferred
    end

    for _, sellingPoint in ipairs(RMS_FluidWorkshop.sellingPoints) do
        local matchesType = workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER and not sellingPoint.ownWorkshop
            or workshopType == RealisticMechanicalSystems.WORKSHOP.OWN and sellingPoint.ownWorkshop and not sellingPoint.mobileWorkshop
            or workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE and sellingPoint.mobileWorkshop
        if matchesType and RMS_FluidWorkshop.getIsVehicleInSellingPoint(vehicle, sellingPoint) then
            return sellingPoint
        end
    end
    return nil
end

---Finds the first loaded workshop containing the vehicle and returns its native type
function RMS_FluidWorkshop.findCurrentSellingPoint(vehicle)
    for _, sellingPoint in ipairs(RMS_FluidWorkshop.sellingPoints) do
        if RMS_FluidWorkshop.getIsVehicleInSellingPoint(vehicle, sellingPoint) then
            if sellingPoint.mobileWorkshop then
                return sellingPoint, RealisticMechanicalSystems.WORKSHOP.MOBILE
            elseif sellingPoint.ownWorkshop then
                return sellingPoint, RealisticMechanicalSystems.WORKSHOP.OWN
            end
            return sellingPoint, RealisticMechanicalSystems.WORKSHOP.DEALER
        end
    end
    return nil, nil
end

---Collects eligible farm-owned containers from the native workshop vehicle zone
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

---Creates deterministic per-container allocations without changing game state
function RMS_FluidWorkshop.allocateStock(vehicle, sellingPoint, farmId, requirements)
    local containers = RMS_FluidWorkshop.collectContainers(vehicle, sellingPoint, farmId)
    local allocations = {}

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
            return nil
        end
    end
    return allocations
end

---Returns the dealer price of reserved fluids from immutable drum prices
function RMS_FluidWorkshop.getDealerFluidPrice(requirements)
    local total = 0
    for circuit, liters in pairs(RMS_Fluids.getRequiredLitersByCircuit(requirements)) do
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
        if cheapestPerLiter == nil then
            return nil
        end
        total = total + liters * cheapestPerLiter
    end
    return total
end

---Returns the displayed transaction price, including dealer-supplied fluids
function RMS_FluidWorkshop.getTransactionPrice(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree)
    if vehicle == nil then
        return nil
    end

    local servicePrice = math.max(tonumber(vehicle:getServicePrice(serviceType, optionOne, optionTwo, optionThree, workshopType)) or 0, 0)
    if workshopType ~= RealisticMechanicalSystems.WORKSHOP.DEALER then
        return servicePrice
    end

    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    local dealerFluidPrice = RMS_FluidWorkshop.getDealerFluidPrice(requirements)
    return dealerFluidPrice ~= nil and servicePrice + dealerFluidPrice or nil
end

---Starts, consumes and charges one service as a single server transaction
function RMS_FluidWorkshop.tryStartService(vehicle, sellingPoint, serviceType, workshopType, optionOne, optionTwo, optionThree)
    if g_server == nil or vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return false, RMS_FluidWorkshop.RESULT.INVALID
    end

    if vehicle:getCurrentStatus() ~= RealisticMechanicalSystems.STATUS.READY
        or (vehicle.spec_RealisticMechanicalSystems.maintenanceTimer or 0) ~= 0 then
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    if not RMS_FluidWorkshop.getMobileWorkshopAvailability(vehicle, serviceType, workshopType, optionOne) then
        return false, RMS_FluidWorkshop.RESULT.SERVICE_REFUSED
    end

    sellingPoint = RMS_FluidWorkshop.findSellingPoint(vehicle, workshopType, sellingPoint)
    if sellingPoint == nil then
        return false, RMS_FluidWorkshop.RESULT.WORKSHOP_NOT_FOUND
    end

    local farmId = vehicle:getOwnerFarmId()
    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, optionOne, optionTwo)
    local allocations = {}
    local dealerFluidPrice = 0

    if workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER then
        dealerFluidPrice = RMS_FluidWorkshop.getDealerFluidPrice(requirements)
        if dealerFluidPrice == nil then
            return false, RMS_FluidWorkshop.RESULT.PRICE_UNAVAILABLE
        end
    else
        allocations = RMS_FluidWorkshop.allocateStock(vehicle, sellingPoint, farmId, requirements)
        if allocations == nil then
            return false, RMS_FluidWorkshop.RESULT.STOCK_INSUFFICIENT
        end
    end

    local servicePrice = math.max(tonumber(vehicle:getServicePrice(serviceType, optionOne, optionTwo, optionThree, workshopType)) or 0, 0)
    local totalPrice = servicePrice + dealerFluidPrice
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
        local removed, fillType = allocation.container:removeRMSFluidLiters(allocation.liters, farmId)
        table.insert(consumed, {
            container = allocation.container,
            liters = removed,
            fillType = fillType
        })
        if math.abs(removed - allocation.liters) > RMS_Fluids.EPSILON then
            consumptionSucceeded = false
            break
        end
    end

    if not consumptionSucceeded then
        for _, entry in ipairs(consumed) do
            entry.container:restoreRMSFluidLiters(entry.liters, farmId, entry.fillType)
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
