-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Return of a leased machine: wash, overdue service and repairs billed
RMS_Leasing = {}

---Share of the deposit a full wash costs
RMS_Leasing.WASH_DEPOSIT_SHARE = 0.3

---Charges of a return, in the order of the dialog
RMS_Leasing.CHARGES = {
    { key = "overdueMaintenance", label = "rms_sell_dialog_overdue_maintenance_penalty" },
    { key = "repair", label = "rms_sell_dialog_repair_penalty" },
    { key = "washing", label = "rms_sell_dialog_washing_penalty" }
}

---Tells whether the extended leasing mod is loaded
function RMS_Leasing.hasExtendedLeasing()
    return g_modIsLoaded["FS25_ExtendedLeasing"] == true
end

---Hooks the sale of the shop and its server event
function RMS_Leasing.preLoad(_mission)
    SellVehicleEvent.run = Utils.overwrittenFunction(SellVehicleEvent.run, RMS_Leasing.onSellVehicleEventRun)
    ShopController.sell = Utils.overwrittenFunction(ShopController.sell, RMS_Leasing.onShopControllerSell)
end

---Hooks the mod into the mission load
function RMS_Leasing.init()
    Mission00.load = Utils.prependedFunction(Mission00.load, RMS_Leasing.preLoad)
end

---Tells whether RMS tracks the vehicle
function RMS_Leasing.isRMSVehicle(vehicle)
    return vehicle ~= nil
        and vehicle.spec_RealisticMechanicalSystems ~= nil
        and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle
end

---Tells whether the vehicle is leased
function RMS_Leasing.isLeasedVehicle(vehicle)
    return vehicle ~= nil and vehicle.propertyState == VehiclePropertyState.LEASED
end

---Tells whether the vehicle is both leased and tracked by RMS
function RMS_Leasing.isSupportedVehicle(vehicle)
    return RMS_Leasing.isRMSVehicle(vehicle) and RMS_Leasing.isLeasedVehicle(vehicle)
end

---Deposit of the lease, as EconomyManager takes it
local function getDeposit(vehicle)
    return MathUtil.round(vehicle:getPrice() * EconomyManager.DEFAULT_LEASING_DEPOSIT_FACTOR, 0)
end

---Dealer price of the lightest maintenance, by how overdue it is
local function getOverdueServiceCost(vehicle)
    local rms = RealisticMechanicalSystems
    local threshold = RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    local overdue = math.max(threshold - vehicle:getServiceLevel(), 0) / threshold
    if overdue == 0 then
        return 0
    end

    local price = 0
    local maintenanceType = vehicle:getMaintenanceTypes()[1]
    for _, line in ipairs(vehicle:getMaintenancePriceLines(maintenanceType, rms.PART_TYPES.OEM, rms.WORKSHOP.DEALER, true)) do
        price = price + line.price
    end
    return overdue * price
end

---What the machine owes on return, before any mod takes a part over
local function getCosts(vehicle)
    local rms = RealisticMechanicalSystems
    local dirt = vehicle.getDirtAmount ~= nil and math.min(vehicle:getDirtAmount(), 1) or 0
    return {
        overdueMaintenance = getOverdueServiceCost(vehicle),
        repair = vehicle:getServicePrice(rms.STATUS.REPAIR, rms.REPAIR_TYPES.MEDIUM, rms.PART_TYPES.OEM, false, rms.WORKSHOP.DEALER, true),
        washing = getDeposit(vehicle) * RMS_Leasing.WASH_DEPOSIT_SHARE * dirt
    }
end

---Return costs owed (raw), shown (display), billed (charge), and rows
function RMS_Leasing.getReturnBreakdown(vehicle)
    local isTracked = RMS_Leasing.isRMSVehicle(vehicle)
    local costs = isTracked and getCosts(vehicle) or {}
    local breakdown = {
        hasExtendedLeasing = RMS_Leasing.hasExtendedLeasing(),
        raw = {},
        display = { total = 0 },
        charge = { total = 0 },
        rows = {}
    }

    for _, charge in ipairs(RMS_Leasing.CHARGES) do
        local cost = costs[charge.key] or 0
        local billed = -cost
        -- Extended Leasing bills the wash itself
        if charge.key == "washing" and breakdown.hasExtendedLeasing then
            billed = 0
        end
        breakdown.raw[charge.key] = cost
        breakdown.display[charge.key] = -cost
        breakdown.display.total = breakdown.display.total - cost
        breakdown.charge[charge.key] = billed
        breakdown.charge.total = breakdown.charge.total + billed
        table.insert(breakdown.rows, { label = charge.label, key = charge.key, value = -cost })
    end

    -- Extended Leasing refunds the deposit itself
    if isTracked and breakdown.hasExtendedLeasing then
        local deposit = getDeposit(vehicle)
        breakdown.display.deposit = deposit
        breakdown.display.total = breakdown.display.total + deposit
        table.insert(breakdown.rows, { label = "rms_sell_dialog_deposit_refund", key = "deposit", value = deposit })
    end

    return breakdown
end

---Asks a leased RMS vehicle back through the mod dialog
function RMS_Leasing.onShopControllerSell(self, superFunc, storeItem, concreteItem, isDirectSell)
    if concreteItem == nil or concreteItem == ShopDisplayItem.NO_CONCRETE_ITEM or not RMS_Leasing.isSupportedVehicle(concreteItem) then
        superFunc(self, storeItem, concreteItem, isDirectSell)
        return
    end

    self.isSelling = true
    self.currentSellStoreItem = storeItem
    self.currentSellItem = concreteItem
    RMS_SellItemDialog.show(concreteItem, self.onSellCallback, self, isDirectSell)
end

---Bills the return charges on the server
function RMS_Leasing.onSellVehicleEventRun(self, superFunc, connection)
    local vehicle = self.vehicle

    -- Restore the native constant after Float32 transport.
    if not connection:getIsServer() and RMS_Leasing.isRMSVehicle(vehicle)
        and vehicle.propertyState == VehiclePropertyState.OWNED then
        self.multiplier = self.isDirectSell and EconomyManager.DIRECT_SELL_MULTIPLIER or 1
    end

    if connection:getIsServer() or not RMS_Leasing.isSupportedVehicle(vehicle) then
        superFunc(self, connection)
        return
    end

    -- Read before SellVehicleEvent.run deletes the vehicle
    local farmId = vehicle:getOwnerFarmId()
    local isReturned = g_currentMission:getHasPlayerPermission(Farm.PERMISSION.SELL_VEHICLE, connection, farmId)
        and not vehicle:getIsInUse(connection)
    local total = isReturned and RMS_Leasing.getReturnBreakdown(vehicle).charge.total or 0

    superFunc(self, connection)

    if total ~= 0 and farmId ~= FarmManager.SPECTATOR_FARM_ID then
        g_currentMission:addMoney(total, farmId, MoneyType.VEHICLE_RUNNING_COSTS, true, true)
    end
end

RMS_Leasing.init()
