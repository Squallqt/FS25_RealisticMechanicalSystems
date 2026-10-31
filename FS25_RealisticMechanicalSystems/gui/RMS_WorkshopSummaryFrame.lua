-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Summary page: vehicle, condition, service, alerts and fluids
RMS_WorkshopSummaryFrame = {}

local RMS_WorkshopSummaryFrame_mt = Class(RMS_WorkshopSummaryFrame, RMS_WorkshopPage)

---Creates the page
-- @return table page
function RMS_WorkshopSummaryFrame.new()
    return RMS_WorkshopPage.new(nil, RMS_WorkshopSummaryFrame_mt)
end

---Wires the condition card, builds the fact and fluid rows
-- @param table dialog workshop dialog
function RMS_WorkshopSummaryFrame:initialize(dialog)
    RMS_WorkshopSummaryFrame:superClass().initialize(self, dialog)
    self.conditionCard:initialize()
    self.noAlertColor = { unpack(self.summaryNoAlertText.textColor) }
    self.factRows = RMS_Utils.cloneTemplate(self.factRowTemplate, 4)
    self.serviceRows = RMS_Utils.cloneTemplate(self.serviceRowTemplate, 4)
    self.fluidRows = RMS_Utils.cloneTemplate(self.fluidRowTemplate, #RMS_Fluids.CIRCUIT_ORDER)
    for index, row in ipairs(self.fluidRows) do
        row:getDescendantByName("icon"):applyProfile(RMS_Fluids.CIRCUITS[RMS_Fluids.CIRCUIT_ORDER[index]].icon, true)
        row.gaugeWidth = row:getDescendantByName("gauge").size[1]
    end
end

---Hands the vehicle to the condition card too
-- @param table? vehicle vehicle
-- @param string? workshopType workshop
function RMS_WorkshopSummaryFrame:setVehicle(vehicle, workshopType)
    RMS_WorkshopSummaryFrame:superClass().setVehicle(self, vehicle, workshopType)
    self.conditionCard:setVehicle(vehicle)
end

---Writes every card of the page
-- @param table state workshop state of RMS_WorkshopDialog:refresh
function RMS_WorkshopSummaryFrame:refresh(state)
    self.statusBar:setStatus(state)
    self:updateVehicleCard()
    self.conditionCard:refresh()
    self:updateServiceCard()
    self:updateAlert()
    self:updateFluids()
    RMS_Utils.fitValuePills(self)
end

---Writes the identity, age, hours, distance and value of the vehicle
function RMS_WorkshopSummaryFrame:updateVehicleCard()
    local vehicle = self.vehicle
    RMS_Utils.setVehicleIdentity(vehicle, self.vehicleImage, self.vehicleBrandValue, self.vehicleNameValue)
    RMS_Utils.writeVehicleFacts(self.factRows, vehicle, true, self.workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER)
end

---Writes the service ring and the figures it does not carry
function RMS_WorkshopSummaryFrame:updateServiceCard()
    local vehicle = self.vehicle
    local reading = RMS_Utils.getInspectionReading(vehicle)
    self.reading = reading
    self.serviceValue:setText(reading.serviceText)
    self.serviceValue:setTextColor(unpack(reading.serviceColor))
    self.serviceOutdatedText:setVisible(reading.isOutdated)
    self.serviceValueStack:invalidateLayout()

    local lastMaintenanceDate = vehicle:getLastMaintenanceDate()
    local rows = {
        { "rms_ws_label_reliability", RMS_Utils.formatReliability(vehicle.spec_RealisticMechanicalSystems.reliability) },
        { "rms_ws_label_service_access", RMS_Utils.formatServiceAccess(vehicle) },
        { "rms_ws_label_last_maintenance", lastMaintenanceDate ~= nil and RMS_Utils.formatMaintenanceLogDate({ date = lastMaintenanceDate })
            or g_i18n:getText("rms_spec_never") },
        { "rms_ws_label_overhaul_count", string.format("%d", vehicle:getOverhaulPerformedCount()) }
    }
    for index, entry in ipairs(rows) do
        RMS_Utils.writeRow(self.serviceRows[index], g_i18n:getText(entry[1]), entry[2])
    end
    local schedule = vehicle:getServiceSchedule()
    self.relAndMainLabel:setText(RMS_Utils.formatServiceReason(vehicle, schedule))
    self.relAndMainValue:setText(RMS_Utils.formatServiceDeadline(schedule))
end

---Writes the worst known breakdown, or the fault state
function RMS_WorkshopSummaryFrame:updateAlert()
    local vehicle = self.vehicle
    local ids = RMS_Utils.getVisibleBreakdownIds(vehicle)
    local alertId = ids[1]
    self.summaryAlertRow:setVisible(alertId ~= nil)
    self.summaryNoAlertText:setVisible(alertId == nil)

    local alertsTitle = g_i18n:getText("rms_ws_section_alerts")
    if #ids > 1 then
        alertsTitle = string.format("%s · (x%d)", alertsTitle, #ids)
    end
    self.summaryAlertsTitle:setText(alertsTitle)

    if alertId == nil then
        local text, isWarning = RMS_WorkshopInterventionsFrame.getFaultStateText(vehicle)
        self.summaryNoAlertText:setText(text)
        self.summaryNoAlertText:setTextColor(unpack(isWarning and RMS_Breakdowns.COLORS.WARNING or self.noAlertColor))
        return
    end
    local breakdown = vehicle:getActiveBreakdowns()[alertId]
    local _, descriptionText = RMS_Utils.getBreakdownTexts(vehicle, alertId, breakdown)
    local price = vehicle:getBreakdownRepairPrice(alertId, breakdown.stage, RealisticMechanicalSystems.PART_TYPES.OEM, self.workshopType)
    RMS_Utils.fitRowValue(self.summaryAlertPart, self.summaryAlertPricePill, self.summaryAlertPrice, RMS_Utils.getBreakdownPartName(alertId),
        g_i18n:formatMoney(price, 0, true, false))
    self.summaryAlertDescription:setText(descriptionText)
end

---Writes the level of each fluid circuit the vehicle has
function RMS_WorkshopSummaryFrame:updateFluids()
    local vehicle = self.vehicle
    local quantityFormat, unit = g_i18n:getText("rms_inspection_fluid_quantity_format"), g_i18n:getText("unit_literShort")
    for index, row in ipairs(self.fluidRows) do
        local circuit = RMS_Fluids.CIRCUIT_ORDER[index]
        local hasCircuit = RMS_Fluids.hasCircuit(vehicle, circuit)
        row:setVisible(hasCircuit)
        if hasCircuit then
            row:getDescendantByName("title"):setText(g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, circuit)))
            row:getDescendantByName("value"):setText(string.format(quantityFormat, RMS_FluidWorkshop.formatLiters(RMS_Fluids.getLiters(vehicle, circuit)),
                RMS_FluidWorkshop.formatLiters(RMS_Fluids.getCapacity(vehicle, circuit)), unit))
            RMS_Utils.setLevelGauge(row:getDescendantByName("gauge"), row:getDescendantByName("under"), row.gaugeWidth,
                RMS_Fluids.getLevel(vehicle, circuit))
        end
    end
    self.fluidRowsLayout:invalidateLayout()
end

---Draws the service ring
function RMS_WorkshopSummaryFrame:onDrawServiceRing()
    RMS_ProgressRing.renderInArea(self.serviceRingArea, self.reading.serviceRatio, self.reading.isOutdated and RMS_Utils.COLOR.TEXT_DIM or nil)
end

---The condition list
function RMS_WorkshopSummaryFrame:getFocusColumns()
    return { { { self.conditionCard.stateList } } }
end

---The page opens on the tab selector
function RMS_WorkshopSummaryFrame:getFocusEntry()
    return self.dialog.tabPaging
end
