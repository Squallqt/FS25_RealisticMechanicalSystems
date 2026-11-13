-- Copyright © 2026 Squallqt. All rights reserved.

---Interventions page: the choices, the order and its recap
RMS_WorkshopInterventionsFrame = {}

local RMS_WorkshopInterventionsFrame_mt = Class(RMS_WorkshopInterventionsFrame, RMS_WorkshopPage)

local STATUS = RealisticMechanicalSystems.STATUS

local ACTIONS = {
    { service = STATUS.INSPECTION, label = "rms_ws_action_choice_inspection", icon = "rms_workshopActionIcon", slice = "gui.icon_vehicleDealer_search" },
    { service = STATUS.MAINTENANCE, label = "rms_ws_action_choice_maintenance", icon = "rms_workshopMaintenanceActionIcon" },
    { service = STATUS.REPAIR, label = "rms_ws_action_choice_repair", icon = "rms_workshopActionIcon", slice = "gui.contextAction_icon_repairAlert" },
    { service = STATUS.OVERHAUL, label = "rms_ws_action_choice_overhaul", icon = "rms_workshopActionIcon", slice = "gui.icon_ingameMenu_options" },
    { service = STATUS.REFILL, label = "rms_ws_action_choice_refill", icon = "rms_workshopOilActionIcon" },
    { service = STATUS.BODYWORK, label = "rms_ws_action_choice_bodywork", icon = "rms_workshopActionIcon", slice = "gui.icon_vehicleDealer_machines" },
    { service = STATUS.REMAP, label = "rms_ws_action_choice_remap", icon = "rms_workshopActionIcon", slice = "gui.storeAttribute_power" }
}

-- a line of the recap sheet in reference pixels
local SHEET_WIDTH, SHEET_GAP = 348, 8
local RECAP_FIGURES = {
    { label = "rms_option_menu_duration_text", field = "duration" },
    { label = "rms_ws_label_finish_time", field = "finish" }
}

-- table geometry in reference pixels, as laid out in the XML
local TABLE_WIDTH, TABLE_HEIGHT, LABEL_WIDTH, COLUMN_GAP = 619, 472, 220, 8
local ORDER_WIDTH, NOTE_TEXT_X = 647, 26
local HEADER, FREQUENCY, ROW, BOTTOM = 112, 16, 44, 8
local MAX_ROWS, MAX_COLUMNS = 8, 3
local CELL_PROFILES = { [2] = "rms_workshopLevelCellDone", [1] = "rms_workshopLevelCellLight", [0] = "rms_workshopLevelCellNone" }
local SYSTEM_WIDTH, SYSTEM_HEIGHT, SYSTEM_GAP, SYSTEMS_PER_ROW, MAX_SYSTEMS = 148, 48, 9, 4, 8
local QUALITY_WIDTH, QUALITY_GAP, QUALITY_GAUGE_MIN = 201, 8, 0.04
-- top of a card's moving lines in px: a part, filters, a price alone
local QUALITY_LAYOUTS = {
    part = { origin = 78, factory = 110, delta = 129 },
    filter = { origin = 55, delta = 71 },
    bare = { delta = 55 }
}
-- card height in px, its name's top margin kept under its last line
local QUALITY_HEIGHTS = { [QUALITY_LAYOUTS.part] = 154, [QUALITY_LAYOUTS.filter] = 96, [QUALITY_LAYOUTS.bare] = 80 }
local COLOR_ROW, COLOR_GAP = 77, 8
local COVER_TEXTS = {
    warranty = { price = "rms_option_menu_warranty_repair_text", fluids = "rms_fluid_warranty_covered" },
    lease = { price = "rms_option_menu_lease_service_text", fluids = "rms_fluid_lease_covered" }
}
-- flat rates whose option names the work alone: a full repaint, a remap
local FLAT_RATE_NAMED = { [STATUS.BODYWORK] = true, [STATUS.REMAP] = true }
-- the slider lane stays kept: rows never change width
local QUOTE_WIDTH, QUOTE_HEIGHT, QUOTE_LIST, QUOTE_ROW_WIDTH = 372, 202, 166, 334
-- $preset_colorDisabled and $preset_fs25_colorMainDark
local COLOR_DISABLED = { 0.3, 0.3, 0.3, 1 }
local COLOR_MAIN_DARK = { 0.00439, 0.00478, 0.00368, 1 }

-- remap chart, in reference pixels of its area
local CHART_WIDTH, CHART_HEIGHT = 647, 278
local PLOT_LEFT, PLOT_RIGHT, PLOT_TOP, PLOT_BOTTOM = 62, 573, 16, 238
local CHART_INTERVALS = 6
local POWER_STEPS = { 10, 20, 25, 50, 100, 200, 250, 500 }
local TORQUE_STEPS = { 50, 100, 200, 250, 500, 1000, 2000 }
local RPM_STEPS = { 100, 200, 250, 500, 1000 }
-- band of gained power filled two screen pixels at a time
local BAND_STEP = 2
local CHART_GREY = { 0.20156, 0.20156, 0.20156, 1 }
local CHART_GRID = { 0.89627, 0.92158, 0.81485, 0.07 }
local CHART_AXIS = { 0.89627, 0.92158, 0.81485, 0.16 }
local CHART_FILL = { 0.22323, 0.40724, 0.00368, 0.16 }
local CHART_PILL_STOCK = { 0.04231, 0.04231, 0.04231, 1 }
local CHART_BLOCK = { 0.0123, 0.0123, 0.0123, 1 }
-- legend: colour for remapped or stock, dash for torque
local LEGEND = {
    { key = "rms_remap_legend_remapped", color = RMS_Utils.COLOR.HIGHLIGHT },
    { key = "rms_remap_legend_stock", color = CHART_GREY },
    { key = "rms_remap_legend_power", color = RMS_Utils.COLOR.TEXT },
    { key = "rms_remap_legend_torque", color = RMS_Utils.COLOR.TEXT, isDashed = true }
}

---Fault state of a machine with no identified fault
function RMS_WorkshopInterventionsFrame.getFaultStateText(vehicle)
    if RealisticMechanicalSystems.getHasUnidentifiedWarning(vehicle) then
        return g_i18n:getText("rms_ws_info_warning_unidentified"), true
    end
    return g_i18n:getText("rms_ws_info_no_breakdowns"), false
end

---Says why an intervention has nothing to do here
function RMS_WorkshopInterventionsFrame.getUnavailableText(vehicle, serviceType, workshopType)
    if serviceType == STATUS.REPAIR and not RMS_Utils.hasSelectedVisibleBreakdown(vehicle)
        and #RealisticMechanicalSystems.getPreventiveParts(vehicle) == 0 then
        for id, breakdown in pairs(vehicle:getActiveBreakdowns()) do
            if breakdown.isVisible and RMS_Breakdowns.BreakdownRegistry[id].isSelectable then
                return g_i18n:getText("rms_ws_reason_repair_unselected"), false
            end
        end
        return RMS_WorkshopInterventionsFrame.getFaultStateText(vehicle)
    elseif serviceType == STATUS.OVERHAUL and #RMS_Utils.getEligibleOverhaulSystems(vehicle) == 0 then
        return g_i18n:getText("rms_ws_reason_overhaul_none"), false
    elseif serviceType == STATUS.BODYWORK and workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE then
        return g_i18n:getText("rms_ws_reason_bodywork_mobile"), false
    elseif serviceType == STATUS.REFILL and not RMS_FluidWorkshop.getIsTopUpOffered(workshopType) then
        return g_i18n:getText("rms_ws_reason_refill_dealer"), false
    elseif serviceType == STATUS.REMAP then
        local _, refusal = RMS_EngineRemap.getAvailability(vehicle, workshopType)
        if refusal ~= nil then
            return g_i18n:getText(RMS_FluidWorkshop.RESULT_TEXT_KEYS[RMS_FluidWorkshop.REMAP_REFUSALS[refusal]]), false
        end
    end
    return nil, false
end

---Tells whether the workshop never does an intervention, its card greyed
function RMS_WorkshopInterventionsFrame.getIsRefusedHere(vehicle, serviceType, workshopType)
    if serviceType == STATUS.REPAIR or serviceType == STATUS.OVERHAUL or serviceType == STATUS.REMAP then
        return false
    end
    return RMS_WorkshopInterventionsFrame.getUnavailableText(vehicle, serviceType, workshopType) ~= nil
end

local cloneTemplate = RMS_Utils.cloneTemplate

-- each layout of the cells hooks a block's first focusable to scroll
local function keepInPlaceOnFocus(element)
    if element.scrollingFocusEnter_orig ~= nil then
        element.onFocusEnter = element.scrollingFocusEnter_orig
    end
end

local formatPower = RMS_Utils.formatPower

local function formatTorque(nm)
    return string.format(g_i18n:getText("rms_remap_torque_format"), g_i18n:formatNumber(MathUtil.round(nm), 0))
end

-- @param float duration duration in hours
local function formatServiceDuration(serviceType, duration, format)
    if duration > 0 and RealisticMechanicalSystems.getIsServiceInstant(serviceType) then
        return g_i18n:getText("rms_option_menu_duration_instant")
    end
    return format(duration)
end

---Writes a price, or who pays it when the farm does not
-- @param string? coverKey "warranty" or "lease"
local function formatPrice(price, coverKey)
    if price == nil then
        return g_i18n:getText("rms_fluid_service_price_unavailable")
    elseif coverKey ~= nil and price <= RMS_Fluids.EPSILON then
        return g_i18n:getText(COVER_TEXTS[coverKey].price)
    end
    return g_i18n:formatMoney(price, 0, true, false)
end

local function getLostWarranty(vehicle, offer, isRestore)
    local lines = {}
    if offer.factoryTerm then
        local months, hours = vehicle:getWarrantyLimits()
        table.insert(lines, { label = string.format(g_i18n:getText("rms_ws_warranty_terms"), months, g_i18n:formatNumber(hours, 0)) })
    end
    local names, expiries = {}, {}
    for _, part in ipairs(isRestore and {} or offer.coveredParts) do
        if names[part.expiry] == nil then
            names[part.expiry] = {}
            table.insert(expiries, part.expiry)
        end
        table.insert(names[part.expiry], RMS_Utils.getBreakdownPartName(part.id, vehicle))
    end
    for _, expiry in ipairs(expiries) do
        for _, name in ipairs(names[expiry]) do
            table.insert(lines, { note = name })
        end
        table.insert(lines, { note = string.format(g_i18n:getText("rms_warranty_part"), expiry - vehicle.age) })
    end
    table.insert(lines, { note = g_i18n:getText(isRestore and "rms_remap_warranty_not_back" or "rms_remap_warranty_lost_detail") })
    return { label = g_i18n:getText("rms_ws_warranty_title"), value = g_i18n:getText("rms_remap_warranty_lost"), isLoss = not isRestore,
        lines = lines }
end

---Creates the page
function RMS_WorkshopInterventionsFrame.new()
    local self = RMS_WorkshopPage.new(nil, RMS_WorkshopInterventionsFrame_mt)
    self.quoteLines = {}
    self.colorRows = {}
    self.choices = {}
    return self
end

---Deletes the page and its color row template
function RMS_WorkshopInterventionsFrame:delete()
    self.colorTemplate:delete()
    RMS_WorkshopInterventionsFrame:superClass().delete(self)
end

---Builds the table, the cards and the rows from their templates
function RMS_WorkshopInterventionsFrame:initialize(dialog)
    RMS_WorkshopInterventionsFrame:superClass().initialize(self, dialog)
    self.unitX, self.unitY = self.optionTable.size[1] / TABLE_WIDTH, self.optionTable.size[2] / TABLE_HEIGHT
    self.quoteUnitX, self.quoteUnitY = self.quoteBlock.size[1] / QUOTE_WIDTH, self.quoteBlock.size[2] / QUOTE_HEIGHT
    self.restriction:setTextColor(unpack(RMS_Utils.COLOR.ALERT))

    self.tableRows = cloneTemplate(self.rowTemplate, MAX_ROWS)
    self.tableColumns = cloneTemplate(self.columnTemplate, MAX_COLUMNS)
    for _, column in ipairs(self.tableColumns) do
        column.cells = cloneTemplate(column:getDescendantByName("cell"), MAX_ROWS)
    end
    self.systemCards = cloneTemplate(self.systemTemplate, MAX_SYSTEMS)
    for index, card in ipairs(self.systemCards) do
        local row, slot = math.floor((index - 1) / SYSTEMS_PER_ROW), (index - 1) % SYSTEMS_PER_ROW
        card:setPosition(slot * (SYSTEM_WIDTH + SYSTEM_GAP) * self.unitX, -row * (SYSTEM_HEIGHT + SYSTEM_GAP) * self.unitY)
    end
    self.qualityCards = cloneTemplate(self.qualityTemplate, #RealisticMechanicalSystems.PART_TYPES_ORDER)
    for index, card in ipairs(self.qualityCards) do
        card:setPosition((index - 1) * (QUALITY_WIDTH + QUALITY_GAP) * self.unitX, 0)
    end
    for _, cards in ipairs({ self.systemCards, self.qualityCards }) do
        for _, card in ipairs(cards) do
            RMS_Utils.insetCardBackground(card)
        end
    end
    self.refillRows = cloneTemplate(self.refillTemplate, #RMS_Fluids.CIRCUIT_ORDER)
    for index, row in ipairs(self.refillRows) do
        row:getDescendantByName("icon"):applyProfile(RMS_Fluids.CIRCUITS[RMS_Fluids.CIRCUIT_ORDER[index]].icon, true)
        row.gaugeWidth = row:getDescendantByName("gauge").size[1]
    end
    self.colorTemplate:unlinkElement()
    self.remapTileElements = cloneTemplate(self.remapTileTemplate, 3)
    for index, tile in ipairs(self.remapTileElements) do
        tile:setPosition((index - 1) * (self.remapTiles.size[1] - tile.size[1]) / 2, 0)
    end
    self.remapNoteElements = cloneTemplate(self.remapNoteTemplate, 2)
    for index, note in ipairs(self.remapNoteElements) do
        note:setPosition((index - 1) * (self.remapNotes.size[1] - note.size[1]), 0)
    end
    self:buildRemapLegend()

    self.actionButtons = cloneTemplate(self.actionButtonTemplate, #ACTIONS)
    for index, entry in ipairs(ACTIONS) do
        local button = self.actionButtons[index]
        button:setText(g_i18n:getText(entry.label))
        local icon = button:getDescendantByName("icon")
        icon:applyProfile(entry.icon)
        if entry.slice ~= nil then
            icon:setImageSlice(nil, entry.slice)
        end
        RMS_Utils.fitIcon(icon)
    end
    RMS_Utils.fitIcon(self.readyIcon)
    RMS_Utils.fitIcon(self.refillEmptyIcon)
    self.recapFigures = cloneTemplate(self.recapFigureTemplate, #RECAP_FIGURES)

    for _, group in ipairs({ self.actionButtons, self.tableColumns, self.systemCards, self.qualityCards }) do
        for _, button in ipairs(group) do
            RMS_Utils.mirrorSelectionToChildren(button)
        end
    end
    self.quoteList:setDataSource(self)
    self.quoteList:setDelegate(self)
    self.cornerNameColor = { unpack(self.cornerName.textColor) }
    self.readyHintColor = { unpack(self.readyHint.textColor) }
    self.tableWidth = TABLE_WIDTH
end

---Lays out the remap chart legend, one stroke and name per entry
function RMS_WorkshopInterventionsFrame:buildRemapLegend()
    local swatchTemplate, textTemplate = self.remapSwatchTemplate, self.remapLegendTextTemplate
    swatchTemplate:unlinkElement()
    textTemplate:unlinkElement()
    for _, entry in ipairs(LEGEND) do
        swatchTemplate:clone(self.remapLegend).legendEntry = entry
        local text = textTemplate:clone(self.remapLegend)
        text:setText(g_i18n:getText(entry.key))
        text:setTextColor(unpack(entry.color))
    end
    swatchTemplate:delete()
    textTemplate:delete()
    self.remapLegend:invalidateLayout()
end

---Opens on no order when the vehicle changes
function RMS_WorkshopInterventionsFrame:setVehicle(vehicle, workshopType)
    RMS_WorkshopInterventionsFrame:superClass().setVehicle(self, vehicle, workshopType)
    self.serviceType, self.refusedService = nil, nil
end

---Opens an intervention, or says why it has nothing to do here
function RMS_WorkshopInterventionsFrame:selectService(serviceType)
    local vehicle, workshopType = self.vehicle, self.workshopType
    self.serviceType, self.refusedService = nil, nil
    if RMS_WorkshopInterventionsFrame.getUnavailableText(vehicle, serviceType, workshopType) ~= nil then
        self.refusedService = serviceType
        return
    end
    local order = RMS_WorkshopOrders.ORDERS[serviceType]
    self.serviceType = serviceType
    self.choice = order.getDefaultChoice ~= nil and order.getDefaultChoice(vehicle, workshopType) or nil
    self.bodyworkColors = {}
    if serviceType == STATUS.OVERHAUL then
        self.optionTwo = RMS_Utils.getEligibleOverhaulSystems(vehicle)[1]
    elseif serviceType == STATUS.MAINTENANCE or serviceType == STATUS.REPAIR then
        self.optionTwo = RealisticMechanicalSystems.PART_TYPES.OEM
    else
        self.optionTwo = nil
    end
    self.resetScroll = true
end

---Returns the method and quality the open order imposes, if any
function RMS_WorkshopInterventionsFrame:getImposed()
    local order = RMS_WorkshopOrders.ORDERS[self.serviceType]
    if order ~= nil and order.getImposed ~= nil then
        return order.getImposed(self.vehicle, self.workshopType)
    end
end

---Whether a choice of the open order is a quick fix, which fits no part
local function getIsQuickFix(frame, choice)
    return frame.serviceType == STATUS.REPAIR and choice == RealisticMechanicalSystems.REPAIR_TYPES.LOW
end

---Second option a choice of the open order sends
function RMS_WorkshopInterventionsFrame:getOptionTwo(choice)
    if self.serviceType == STATUS.OVERHAUL then
        return choice == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL and self.optionTwo or "NONE"
    elseif self.serviceType == STATUS.BODYWORK then
        return choice == RMS_Bodywork.FULL and RMS_Bodywork.encodeColors(self.vehicle, self.bodyworkColors) or nil
    elseif getIsQuickFix(self, choice) then
        return "NONE"
    elseif self.serviceType == STATUS.MAINTENANCE or self.serviceType == STATUS.REPAIR then
        return self.optionTwo
    end
    return nil
end

---Writes the choices, the order and the recap
function RMS_WorkshopInterventionsFrame:refresh(state)
    self.state = state
    self.statusBar:setStatus(state)
    if self.serviceType ~= nil and RMS_WorkshopInterventionsFrame.getUnavailableText(self.vehicle, self.serviceType, self.workshopType) ~= nil then
        self:selectService(self.serviceType)
    end
    self:updateActions()
    local hasOrder = self.serviceType ~= nil and not state.isUnderService
    self.readyPanel:setVisible(not hasOrder and not state.isUnderService)
    self.progressPanel:setVisible(state.isUnderService)
    self.remapPanel:setVisible(hasOrder and self.serviceType == STATUS.REMAP)
    self.orderScroll:setVisible(hasOrder and self.serviceType ~= STATUS.REMAP)
    self.orderSliderBox:setVisible(false)
    -- a service the workshop cannot do keeps its start button, greyed
    self.startButton:setVisible(hasOrder or self.refusedService ~= nil and not state.isUnderService)
    if state.isUnderService then
        self:updateProgress()
    elseif not hasOrder then
        self:updateReady()
    elseif self.serviceType == STATUS.REMAP then
        self:updateRemap()
    else
        self:updateOrder()
    end
    RMS_Utils.fitValuePills(self)
end

---Selects the open choice, greys the ones this workshop refuses
function RMS_WorkshopInterventionsFrame:updateActions()
    for index, button in ipairs(self.actionButtons) do
        local serviceType = ACTIONS[index].service
        local isRefused = RMS_WorkshopInterventionsFrame.getIsRefusedHere(self.vehicle, serviceType, self.workshopType)
        local suffix = isRefused and "Refused" or ""
        button:applyProfile("rms_workshopActionChoice" .. suffix, true)
        button:getDescendantByName("background"):applyProfile("rms_workshopActionBg" .. suffix, true)
        local icon = button:getDescendantByName("icon")
        icon:setImageColor(nil, unpack(isRefused and COLOR_DISABLED or RMS_Utils.COLOR.HIGHLIGHT))
        icon:setImageColor(GuiOverlay.STATE_SELECTED, unpack(isRefused and COLOR_DISABLED or COLOR_MAIN_DARK))
        button:setDisabled(not self.state.isOpen or self.state.isUnderService)
        button:setSelected(not self.state.isUnderService and (self.serviceType == serviceType or self.refusedService == serviceType))
        RMS_Utils.centerActionContent(button)
    end
    self.actionButtons[1].parent:invalidateLayout()
end

---Writes what the workshop waits for, or why a choice has nothing to do
function RMS_WorkshopInterventionsFrame:updateReady()
    local text, isWarning = nil, false
    if self.refusedService ~= nil then
        text, isWarning = RMS_WorkshopInterventionsFrame.getUnavailableText(self.vehicle, self.refusedService, self.workshopType)
    end
    local titleKeys = { [STATUS.REPAIR] = "rms_ws_action_choice_repair", [STATUS.OVERHAUL] = "rms_ws_overhaul_unavailable",
        [STATUS.BODYWORK] = "rms_ws_action_choice_bodywork", [STATUS.REFILL] = "rms_ws_action_choice_refill",
        [STATUS.REMAP] = "rms_remap_unavailable" }
    local isRefusedHere = self.refusedService ~= nil
        and RMS_WorkshopInterventionsFrame.getIsRefusedHere(self.vehicle, self.refusedService, self.workshopType)
    local isClosed = self.refusedService == nil and not self.state.isOpen
    if isClosed then
        text = string.format(g_i18n:getText("rms_ws_status_closed_hint"), RMS_Utils.formatFinishTime(RMS_Config.WORKSHOP.OPEN_HOUR),
            RMS_Utils.formatFinishTime(RMS_Config.WORKSHOP.CLOSE_HOUR))
    end
    self.readyIcon:setImageColor(nil, unpack((isRefusedHere or isClosed) and COLOR_DISABLED or RMS_Utils.COLOR.HIGHLIGHT))
    self.readyTitle:setText(g_i18n:getText(titleKeys[self.refusedService] or isClosed and "rms_ws_status_closed" or "rms_ws_status_ready_title"))
    self.readyHint:setText(text or g_i18n:getText("rms_ws_status_ready_hint"))
    self.readyHint:setTextColor(unpack(isWarning and RMS_Breakdowns.COLORS.WARNING or self.readyHintColor))
    self.startButton:setDisabled(true)
    self:writeRecap({ type = g_i18n:getText(self.state.isOpen and "rms_ws_status_open" or "rms_ws_status_closed"),
        options = g_i18n:getText(self.workshopType), isRefused = self.refusedService ~= nil })
end

---Writes the running intervention and what it costs
function RMS_WorkshopInterventionsFrame:updateProgress()
    local vehicle = self.vehicle
    local spec = vehicle.spec_RealisticMechanicalSystems
    local options = {}
    if spec.serviceOptionOne ~= nil and spec.serviceOptionOne ~= "NONE" then
        table.insert(options, RMS_Utils.formatServiceOption(vehicle, spec.currentState, spec.serviceOptionOne, spec.workshopType))
    end
    if spec.currentState ~= STATUS.BODYWORK and spec.serviceOptionTwo ~= nil and spec.serviceOptionTwo ~= "NONE" then
        table.insert(options, g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, spec.serviceOptionTwo)))
    end
    local optionText = #options > 0 and table.concat(options, " · ") or "-"
    self.progressName:setText(RMS_Utils.formatServiceState(spec.currentState))
    self.progressDetail:setText(optionText)
    self:writeRecap({ type = RMS_Utils.formatServiceState(spec.currentState), options = optionText,
        priceLabel = g_i18n:getText("rms_ws_label_committed_cost"), price = g_i18n:formatMoney(spec.pendingServicePrice, 0, true, false),
        finish = RMS_Utils.formatFinishTime(vehicle:getServiceFinishTime()),
        quote = self:getServiceQuote(spec.currentState, spec.serviceOptionOne, spec.serviceOptionTwo, spec.pendingServiceInvoice,
            spec.workshopType) })
end

---Draws the progress of the running intervention
function RMS_WorkshopInterventionsFrame:onDrawProgressRing()
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local ratio = spec.pendingProgressTotalTime > 0 and math.clamp(spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime, 0, 1) or 0
    local percent = math.floor(ratio * 100)
    if percent ~= self.drawnPercent then
        self.drawnPercent = percent
        self.progressValue:setText(string.format("%d %%", percent))
    end
    RMS_ProgressRing.renderInArea(self.progressRingArea, percent / 100)
end

---Writes every part of the order the open intervention shows
function RMS_WorkshopInterventionsFrame:updateOrder()
    local vehicle, workshopType, serviceType = self.vehicle, self.workshopType, self.serviceType
    local order = RMS_WorkshopOrders.ORDERS[serviceType]
    self.choices = order.getChoices ~= nil and order.getChoices(vehicle) or {}
    if #self.choices > 0 and RMS_Utils.getKeyByValue(self.choices, self.choice) == nil then
        self.choice = self.choices[1]
    end
    if order.isChoiceLocked ~= nil and order.isChoiceLocked(vehicle, self.choice, workshopType) then
        self.choice = order.getDefaultChoice(vehicle, workshopType)
    end
    local imposedChoice, imposedQuality = self:getImposed()
    self.choice, self.optionTwo = imposedChoice or self.choice, imposedQuality or self.optionTwo
    local optionTwo = self:getOptionTwo(self.choice)
    local hasTable = #self.choices > 0

    self.prompt:setVisible(order.promptKey ~= nil)
    self.prompt:setText(order.promptKey ~= nil and g_i18n:getText(order.promptKey) or "")
    self.optionTable:setVisible(hasTable)
    if hasTable then
        self:updateTable(order)
    end
    self.noteBlock:setVisible(order.noteKey ~= nil)
    self.footer:setVisible(order.footerKeys ~= nil)
    if order.footerKeys ~= nil then
        self.footer:setText(g_i18n:getText(order.footerKeys[1]) .. " " .. g_i18n:getText(order.footerKeys[2]))
    end
    local isAllowed = RMS_FluidWorkshop.getWorkshopAvailability(vehicle, serviceType, workshopType, self.choice)
    local refusalKey = isAllowed and order.getRefusalKey ~= nil and order.getRefusalKey(vehicle, workshopType, self.choice) or nil
    self.restriction:setVisible(not isAllowed or refusalKey ~= nil)
    self.restriction:setText(not isAllowed and RMS_FluidWorkshop.getWorkshopRestrictionText(vehicle, serviceType, workshopType, self.choice)
        or refusalKey ~= nil and g_i18n:getText(refusalKey) or "")

    self:updateSecondOption(order)
    self:updateRefill()
    self:updateColors()

    local coverKey = RMS_WorkshopOrders.getCoverKey(vehicle, serviceType, self.choice, optionTwo, workshopType)
    local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, serviceType, workshopType, self.choice, optionTwo)
    local duration = vehicle:getServiceDuration(serviceType, self.choice, optionTwo, workshopType)
    local priceText = formatPrice(price, coverKey)
    local typeText = RMS_Utils.formatServiceState(serviceType)
    if serviceType == STATUS.REFILL then
        typeText = g_i18n:getText("rms_fluid_refill_work_order")
    end
    self:writeRecap({
        type = typeText,
        options = self:getRecapOptions(optionTwo),
        price = priceText,
        duration = formatServiceDuration(serviceType, duration, RMS_Utils.formatShortDuration),
        finish = RMS_Utils.formatFinishTime(vehicle:getServiceFinishTime(serviceType, self.choice, optionTwo, workshopType)),
        quote = self:getQuote(optionTwo, coverKey)
    })

    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, self.choice, optionTwo)
    local isValid = self.choice ~= nil or (serviceType == STATUS.REFILL and #requirements > 0)
    if serviceType == STATUS.OVERHAUL then
        isValid = self.choice ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL or self.optionTwo ~= nil
    elseif serviceType == STATUS.BODYWORK then
        isValid = RMS_Bodywork.isAllowed(vehicle, workshopType, self.choice, optionTwo)
    end
    self.startButton:setDisabled(not isValid or not isAllowed or not self.state.isOpen or price == nil or self.hasStockShortage)

    self.orderScroll:invalidateLayout()
    for _, group in ipairs({ self.tableColumns, self.systemCards, self.qualityCards }) do
        for _, button in ipairs(group) do
            keepInPlaceOnFocus(button)
        end
    end
    for _, row in pairs(self.colorRows) do
        keepInPlaceOnFocus(row:getDescendantByName("button"))
    end
    if self.resetScroll then
        self.orderScroll:scrollTo(0, false)
        self.resetScroll = false
    end
    self.orderScroll:raiseSliderUpdateEvent()
    local hasSlider = self.orderSlider.needsSlider == true
    self.orderSliderBox:setVisible(hasSlider)
    -- a fitting order takes the lane of the hidden slider
    local width = hasSlider and TABLE_WIDTH or ORDER_WIDTH
    if hasTable and width ~= self.tableWidth then
        self.tableWidth = width
        self:updateTable(order)
    end
    if order.noteKey ~= nil then
        self:updateNote(g_i18n:getText(order.noteKey))
    end
end

---Centers the note of the table, its icon before its text
function RMS_WorkshopInterventionsFrame:updateNote(text)
    local ux, width = self.unitX, self.tableWidth
    self.noteBlock:setSize(width * ux, nil)
    self.noteText:setSize((width - NOTE_TEXT_X) * ux, nil)
    self.noteText:setText(text)
    self.noteIcon:setPosition((width * ux - self.noteText:getTextWidth()) / 2 - NOTE_TEXT_X / 2 * ux, nil)
end

---Lays the table out and writes each row and column
function RMS_WorkshopInterventionsFrame:updateTable(order)
    local vehicle, choices = self.vehicle, self.choices
    local ux, uy = self.unitX, self.unitY
    local rows = order.getRows(vehicle, self.workshopType, self.optionTwo)
    local header = HEADER + (order.getFrequency ~= nil and FREQUENCY or 0)
    local height = header + #rows * ROW + BOTTOM
    self.optionTable:setSize(self.tableWidth * ux, height * uy)

    local corner = order.getCorner(vehicle, self.workshopType)
    self.cornerLabel:setText(g_i18n:getText(corner.label))
    self.cornerName:setText(corner.name)
    self.cornerName:setTextColor(unpack(corner.isWarning and RMS_Breakdowns.COLORS.WARNING or corner.isHighlight and self.cornerNameColor
        or RMS_Utils.COLOR.TEXT))
    self.cornerReason:setText(corner.reason)
    self.cornerReason:setTextColor(unpack(corner.isReasonWarning and RMS_Breakdowns.COLORS.WARNING or RMS_Utils.COLOR.TEXT_DIM))

    for index, element in ipairs(self.tableRows) do
        local row = rows[index]
        element:setVisible(row ~= nil)
        if row ~= nil then
            local detail = row.detailText or (row.detail ~= nil and g_i18n:getText(row.detail) or "")
            local x = row.icon ~= nil and 34 or 0
            local icon, name, detailElement = element:getDescendantByName("icon"), element:getDescendantByName("name"), element:getDescendantByName("detail")
            element:setPosition(0, -(header + (index - 1) * ROW) * uy)
            icon:setVisible(row.icon ~= nil)
            if row.icon ~= nil then
                icon:applyProfile(row.icon, true)
                icon:setPosition(0, -9 * uy)
                icon:setSize(26 * ux, 26 * uy)
            end
            name:setPosition(x * ux, -(detail ~= "" and 5 or 12) * uy)
            name:setSize((LABEL_WIDTH - x) * ux, nil)
            name:setText(row.text or g_i18n:getText(row.name))
            detailElement:setVisible(detail ~= "")
            detailElement:setPosition(x * ux, -24 * uy)
            detailElement:setSize((LABEL_WIDTH - x) * ux, nil)
            detailElement:setText(detail)
        end
    end

    local width = (self.tableWidth - LABEL_WIDTH - COLUMN_GAP * #choices) / #choices
    local imposedChoice = self:getImposed()
    for column, button in ipairs(self.tableColumns) do
        local choice = choices[column]
        button:setVisible(choice ~= nil)
        if choice ~= nil then
            local isLocked = imposedChoice ~= nil and choice ~= imposedChoice
                or order.isChoiceLocked ~= nil and order.isChoiceLocked(vehicle, choice, self.workshopType)
            button:setDisabled(isLocked)
            local optionTwo = self:getOptionTwo(choice)
            local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, self.serviceType, self.workshopType, choice, optionTwo)
            local duration = vehicle:getServiceDuration(self.serviceType, choice, optionTwo, self.workshopType)
            local badgeKey = order.getBadge ~= nil and order.getBadge(vehicle, choice, optionTwo, self.workshopType) or nil
            button:setPosition((LABEL_WIDTH + COLUMN_GAP + (column - 1) * (width + COLUMN_GAP)) * ux, 0)
            button:setSize(width * ux, height * uy)
            button:setSelected(choice == self.choice)
            button:getDescendantByName("frame"):setSize(width * ux, height * uy)
            RMS_Utils.insetCardBackground(button)
            for _, name in ipairs({ "badge", "badgeText" }) do
                local badge = button:getDescendantByName(name)
                badge:setVisible(badgeKey ~= nil)
                badge:setPosition((width / 2 - 52) * ux, nil)
            end
            button:getDescendantByName("badgeText"):setText(badgeKey ~= nil and g_i18n:getText(badgeKey) or "")
            button:getDescendantByName("frequency"):setVisible(order.getFrequency ~= nil)
            button:getDescendantByName("price"):setPosition(nil, -(header - 46) * uy)
            button:getDescendantByName("duration"):setPosition(nil, -(header - 22) * uy)
            local texts = {
                name = order.getColumnName ~= nil and order.getColumnName(vehicle, choice) or g_i18n:getText(choice),
                frequency = order.getFrequency ~= nil and order.getFrequency(vehicle, choice, choices) or "",
                price = price ~= nil and not isLocked and g_i18n:formatMoney(price, 0, true, false) or "-",
                duration = not isLocked and formatServiceDuration(self.serviceType, duration, RMS_Utils.formatShortDuration) or ""
            }
            for name, text in pairs(texts) do
                local element = button:getDescendantByName(name)
                element:setSize((width - 8) * ux, nil)
                element:setText(text)
            end
            for index, cell in ipairs(button.cells) do
                local row = rows[index]
                cell:setVisible(row ~= nil)
                if row ~= nil then
                    local text, kind = row.getCell(choice)
                    local textElement = cell:getDescendantByName("text")
                    cell:setPosition(0, -(header + (index - 1) * ROW) * uy)
                    cell:setSize(width * ux, nil)
                    cell:getDescendantByName("rule"):setSize((width - 20) * ux, nil)
                    textElement:applyProfile(CELL_PROFILES[kind], true)
                    textElement:setPosition(4 * ux, -12 * uy)
                    textElement:setSize((width - 8) * ux, 20 * uy)
                    textElement:setText(text)
                end
            end
        end
    end
end

---Writes the systems of a partial overhaul, or the part qualities
function RMS_WorkshopInterventionsFrame:updateSecondOption(order)
    local vehicle = self.vehicle
    local isPartial = self.serviceType == STATUS.OVERHAUL and self.choice == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
    local hasQualities = order.qualityPromptKey ~= nil and not getIsQuickFix(self, self.choice)
    local promptKey = hasQualities and order.qualityPromptKey or isPartial and order.systemPromptKey or nil
    self.secondPrompt:setVisible(promptKey ~= nil)
    self.secondPrompt:setText(promptKey ~= nil and g_i18n:getText(promptKey) or "")
    self.systemRow:setVisible(isPartial)
    self.qualityRow:setVisible(hasQualities)

    if isPartial then
        local systems = RMS_Utils.getEligibleOverhaulSystems(vehicle)
        self.systemValues = systems
        local rowCount = math.ceil(#systems / SYSTEMS_PER_ROW)
        for index, card in ipairs(self.systemCards) do
            local system = systems[index]
            card:setVisible(system ~= nil)
            card:setSelected(system ~= nil and system == self.optionTwo)
            card:getDescendantByName("name"):setText(system ~= nil and g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, system)) or "")
        end
        self.systemRow:setSize(nil, (rowCount * SYSTEM_HEIGHT + (rowCount - 1) * SYSTEM_GAP) * self.unitY)
    end
    if hasQualities then
        self:updateQualities()
    end
end

-- info={origin, warranty, isCovered, wear, factory, isFactoryKept}
local function getQualityPartInfo(frame, quality)
    local R, vehicle, workshopType = RealisticMechanicalSystems, frame.vehicle, frame.workshopType
    local OEM = R.PART_TYPES.OEM
    local newPart = g_i18n:getText("rms_ws_quality_new_part")
    -- the warranty repairs every fault: original parts that keep its cover
    if vehicle:isWarrantyRepairCovered(workshopType) then
        local monthsLeft = RMS_WorkshopOrders.getPartWarrantyMonthsLeft(vehicle, workshopType)
        return { origin = newPart, isCovered = true, wear = 0,
            warranty = monthsLeft < math.huge and string.format(g_i18n:getText("rms_ws_quality_part_warranty"), monthsLeft)
                or g_i18n:getText("rms_ws_quality_factory_warranty") }
    end
    local minimum, maximum, count, guaranteed = R.getUsedPartOfferSummary(vehicle, frame.choice, workshopType)
    if count == 0 then
        return nil
    end
    -- a lease or a remap honours none
    local isHonoured = vehicle.propertyState ~= VehiclePropertyState.LEASED and not vehicle.spec_RealisticMechanicalSystems.warrantyVoided
    local isFactoryRunning = isHonoured and R.getIsWithinWarrantyLimits(vehicle)
    local info = { origin = newPart, warranty = "rms_ws_quality_no_warranty", isCovered = false, wear = 0 }
    if quality == R.PART_TYPES.USED then
        info.origin = minimum == maximum and string.format(g_i18n:getText("rms_ws_quality_donor"), minimum)
            or string.format(g_i18n:getText("rms_ws_quality_donors"), minimum, maximum)
        -- the most worn part the order fits
        info.wear = maximum * RMS_Config.CORE.BASE_SYSTEMS_WEAR
        if guaranteed == count then
            info.warranty, info.isCovered = "rms_ws_quality_used_warranty", true
        elseif guaranteed > 0 then
            info.warranty = "rms_ws_quality_partial_warranty"
        end
    elseif quality == OEM then
        local hasPart = false
        for _, line in ipairs(vehicle:getRepairPriceLines(frame.choice, quality, workshopType)) do
            hasPart = hasPart or not line.warranty and RMS_Consumables.getFilterOfBreakdown(line.breakdownId) == nil
        end
        if hasPart and isHonoured and workshopType == R.WORKSHOP.DEALER then
            info.warranty, info.isCovered = "rms_ws_quality_oem_warranty", true
        elseif hasPart and isFactoryRunning then
            info.warranty, info.isCovered = "rms_ws_quality_factory_warranty", true
        end
    end
    -- a part not original leaves the factory warranty while it runs
    if isFactoryRunning and (quality ~= OEM or info.warranty ~= "rms_ws_quality_factory_warranty") then
        info.isFactoryKept = quality == OEM
        info.factory = g_i18n:getText(quality == OEM and "rms_ws_quality_factory_kept" or "rms_ws_quality_factory_lost")
    end
    info.warranty = g_i18n:getText(info.warranty)
    return info
end

local FILTER_DEFECT_KEYS = {
    [RealisticMechanicalSystems.PART_TYPES.USED] = "rms_ws_quality_filter_often",
    [RealisticMechanicalSystems.PART_TYPES.AFTERMARKET] = "rms_ws_quality_filter_sometimes",
    [RealisticMechanicalSystems.PART_TYPES.OEM] = "rms_ws_quality_filters_sound"
}

-- info={origin}: how often a filter of the quality is defective
local function getQualityFilterInfo(frame, quality)
    if #RMS_Consumables.getDefectiveFilterCandidates(frame.vehicle, frame.choice) == 0 then
        return nil
    end
    return { origin = g_i18n:getText(FILTER_DEFECT_KEYS[quality]) }
end

---Writes the part quality cards of a maintenance or a repair
function RMS_WorkshopInterventionsFrame:updateQualities()
    local vehicle, serviceType = self.vehicle, self.serviceType
    local OEM = RealisticMechanicalSystems.PART_TYPES.OEM
    local _, imposedQuality = self:getImposed()
    local prices = {}
    for _, quality in ipairs(RealisticMechanicalSystems.PART_TYPES_ORDER) do
        prices[quality] = RMS_FluidWorkshop.getTransactionPrice(vehicle, serviceType, self.workshopType, self.choice, quality)
    end
    local isRepair = serviceType == STATUS.REPAIR
    local infos, layouts, height = {}, {}, 0
    for index, quality in ipairs(RealisticMechanicalSystems.PART_TYPES_ORDER) do
        local isLocked = imposedQuality ~= nil and quality ~= imposedQuality
        -- a card the order cannot take keeps its layout, greyed
        if isRepair then
            infos[index] = not isLocked and getQualityPartInfo(self, quality) or nil
            layouts[index] = QUALITY_LAYOUTS.part
        else
            infos[index] = not isLocked and getQualityFilterInfo(self, quality) or nil
            layouts[index] = infos[index] ~= nil and QUALITY_LAYOUTS.filter or QUALITY_LAYOUTS.bare
        end
        height = math.max(height, QUALITY_HEIGHTS[layouts[index]])
    end
    self.qualityRow:setSize(nil, height * self.unitY)
    for index, card in ipairs(self.qualityCards) do
        local quality = RealisticMechanicalSystems.PART_TYPES_ORDER[index]
        local isLocked = imposedQuality ~= nil and quality ~= imposedQuality
        local price = not isLocked and prices[quality] or nil
        local delta = ""
        if quality == OEM then
            delta = g_i18n:getText("rms_ws_quality_reference")
        elseif price ~= nil and prices[OEM] ~= nil and math.abs(price - prices[OEM]) >= 0.5 then
            local gap = price - prices[OEM]
            delta = string.format(g_i18n:getText("rms_ws_quality_delta"), (gap < 0 and "-" or "+") .. g_i18n:formatMoney(math.abs(gap), 0, true, false))
        end
        local info, layout = infos[index], layouts[index]
        card:setSize(nil, height * self.unitY)
        card:getDescendantByName("frame"):setSize(nil, height * self.unitY)
        RMS_Utils.insetCardBackground(card)
        card:setSelected(quality == self.optionTwo)
        card:setDisabled(isLocked)
        card:getDescendantByName("name"):setText(g_i18n:getText(serviceType == STATUS.MAINTENANCE and RMS_FluidWorkshop.getConsumableQualityKey(quality)
            or RMS_Utils.getSystemLabel(vehicle, quality)))
        card:getDescendantByName("price"):setText(price ~= nil and g_i18n:formatMoney(price, 0, true, false) or "-")
        for name, top in pairs(layout) do
            card:getDescendantByName(name):setPosition(nil, -top * self.unitY)
        end
        for _, name in ipairs({ "wearLabel", "wear", "gaugeTrack", "gauge", "warranty", "rule" }) do
            card:getDescendantByName(name):setVisible(layout == QUALITY_LAYOUTS.part)
        end
        card:getDescendantByName("delta"):setText(delta)

        local originElement, warrantyElement, factoryElement = card:getDescendantByName("origin"), card:getDescendantByName("warranty"),
            card:getDescendantByName("factory")
        originElement:setVisible(info ~= nil)
        originElement:setText(info ~= nil and info.origin or "")
        factoryElement:setVisible(info ~= nil and info.factory ~= nil)
        factoryElement:applyProfile(info ~= nil and info.isFactoryKept and "rms_workshopQualityWarrantyCovered" or "rms_workshopQualityWarranty", true)
        factoryElement:setText(info ~= nil and info.factory or "")
        if layout == QUALITY_LAYOUTS.part then
            local wearElement, gauge = card:getDescendantByName("wear"), card:getDescendantByName("gauge")
            warrantyElement:setVisible(info ~= nil)
            gauge:setVisible(info ~= nil and info.wear > 0)
            if info == nil then
                wearElement:setText("-")
            else
                warrantyElement:applyProfile(info.isCovered and "rms_workshopQualityWarrantyCovered" or "rms_workshopQualityWarranty", true)
                warrantyElement:setText(info.warranty)
                local condition = 1 - info.wear
                local ideal, high, mid, low = unpack(RMS_Utils.CONDITION_LEVELS)
                wearElement:setText(string.format("%d%%", math.floor(info.wear * 100 + 0.5)))
                wearElement:setTextColor(RMS_Utils.getValueColor(condition, ideal, high, mid, low, false))
                gauge.color = { RMS_Utils.getGaugeColor(condition, ideal, high, mid, low, false) }
                gauge.gaugeWidth = gauge.gaugeWidth or gauge.size[1]
                gauge:setSize(math.clamp(info.wear, QUALITY_GAUGE_MIN, 1) * gauge.gaugeWidth, nil)
            end
        end
    end
end

---Writes the fluids a top up adds
function RMS_WorkshopInterventionsFrame:updateRefill()
    local isRefill = self.serviceType == STATUS.REFILL
    local vehicle = self.vehicle
    local requirements = isRefill and RMS_FluidWorkshop.getTransactionRequirements(vehicle, STATUS.REFILL, nil, nil) or {}
    local litersByCircuit = RMS_Fluids.getRequiredLitersByCircuit(requirements)
    local hasRequirements = next(litersByCircuit) ~= nil
    local unit = g_i18n:getText("unit_literShort")
    self.refillEmpty:setVisible(isRefill and not hasRequirements)
    self.refillSupply:setVisible(isRefill and hasRequirements)
    self.refillSupply:setText(g_i18n:getText("rms_fluid_refill_dealer_supply"))
    self.refillRowsBox:setVisible(isRefill and hasRequirements)
    for index, row in ipairs(self.refillRows) do
        local circuit = RMS_Fluids.CIRCUIT_ORDER[index]
        local liters = math.max(litersByCircuit[circuit] or 0, 0)
        row:setVisible(liters > RMS_Fluids.EPSILON)
        if liters > RMS_Fluids.EPSILON then
            local capacity, current = RMS_Fluids.getCapacity(vehicle, circuit), RMS_Fluids.getLiters(vehicle, circuit)
            row:getDescendantByName("name"):setText(g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, circuit)))
            row:getDescendantByName("level"):setText(string.format(g_i18n:getText("rms_inspection_fluid_quantity_format"),
                RMS_FluidWorkshop.formatLiters(current), RMS_FluidWorkshop.formatLiters(capacity), unit))
            row:getDescendantByName("amount"):setText(string.format("+ %s %s", RMS_FluidWorkshop.formatLiters(liters), unit))
            RMS_Utils.setLevelGauge(row:getDescendantByName("gauge"), row:getDescendantByName("under"), row.gaugeWidth,
                capacity > RMS_Fluids.EPSILON and math.clamp(current / capacity, 0, 1) or 0)
        end
    end
    self.refillRowsBox:invalidateLayout()
end

---Writes one color zone of a repaint
function RMS_WorkshopInterventionsFrame:updateColorRow(zone, row)
    local vehicle, selection = self.vehicle, self.bodyworkColors[zone]
    local choices = RMS_Bodywork.getColorChoices(vehicle, zone, self.bodyworkColors)
    local customChoice = RMS_Bodywork.getCustomColorChoice(vehicle, zone, self.bodyworkColors)
    local current = vehicle.configurations[zone]
    local shown
    for _, choice in ipairs(choices) do
        if choice.index == selection or (shown == nil and choice.index == current) then
            shown = choice
        end
    end
    local isCustomSelected = type(selection) == "table" and customChoice ~= nil and customChoice.index == selection.index
    local currentCustomColor
    if customChoice ~= nil and current == customChoice.index then
        local data = vehicle.configurationData[zone]
        if data ~= nil and data[customChoice.index] ~= nil and RMS_Bodywork.isValidColor(data[customChoice.index].color) then
            currentCustomColor = data[customChoice.index].color
        end
    end
    local showCurrentCustom = currentCustomColor ~= nil and (selection == nil or selection == 0 or selection == customChoice.index)
    local uiColor = isCustomSelected and selection.color or showCurrentCustom and currentCustomColor or shown ~= nil and shown.item.uiColor or nil
    local item = (isCustomSelected or showCurrentCustom) and customChoice.item or shown ~= nil and shown.item or nil
    local material = item ~= nil and item.isMetallic and "Metallic" or item ~= nil and item.isMat and "Matte" or "Glossy"
    local hasChoices = #choices > 0 or customChoice ~= nil
    local button = row:getDescendantByName("button")
    row:setVisible(hasChoices)
    button:setDisabled(not hasChoices)
    local image = button:getDescendantByName("colorImage")
    image:setVisible(uiColor ~= nil)
    if uiColor ~= nil then
        image:setImageColor(nil, uiColor[1], uiColor[2], uiColor[3], 1)
    end
    for _, kind in ipairs({ "Metallic", "Glossy", "Matte" }) do
        button:getDescendantByName("colorImage" .. kind):setVisible(uiColor ~= nil and material == kind)
    end
    return hasChoices
end

---Writes the color zones of a full repaint at the dealer
function RMS_WorkshopInterventionsFrame:updateColors()
    local vehicle = self.vehicle
    local choosesColors = self.serviceType == STATUS.BODYWORK and self.choice == RMS_Bodywork.FULL
        and self.workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
    local zones = choosesColors and RMS_Bodywork.getColorZones(vehicle) or {}
    for zone, row in pairs(self.colorRows) do
        row:delete()
        self.colorRows[zone] = nil
    end
    local hasColors, shownRows = false, 0
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    for _, zone in ipairs(zones) do
        local row = self.colorTemplate:clone(self.colorRowsBox)
        RMS_Utils.registerFocus(row)
        row:getDescendantByName("button").colorZone = zone
        self.colorRows[zone] = row
        local items = storeItem.configurations[zone]
        row:getDescendantByName("title"):setText(items ~= nil and items[1] ~= nil and items[1].overwrittenTitle
            or g_vehicleConfigurationManager:getConfigurationDescByName(zone).title)
        if self:updateColorRow(zone, row) then
            hasColors, shownRows = true, shownRows + 1
        end
    end
    self.colorsPrompt:setVisible(choosesColors)
    self.colorRowsBox:setVisible(hasColors)
    self.colorRowsBox:setSize(nil, (shownRows * COLOR_ROW + math.max(shownRows - 1, 0) * COLOR_GAP) * self.unitY)
    self.colorRowsBox:invalidateLayout()
    self.noColorPanel:setVisible(choosesColors and not hasColors)
end

---Options of the open order, as the recap names them
function RMS_WorkshopInterventionsFrame:getRecapOptions(optionTwo)
    local vehicle, serviceType = self.vehicle, self.serviceType
    if serviceType == STATUS.REFILL then
        return g_i18n:getText("rms_fluid_refill_dealer_supply")
    end
    local options = {}
    if self.choice ~= nil then
        table.insert(options, RMS_Utils.formatServiceOption(vehicle, serviceType, self.choice, self.workshopType))
    end
    if serviceType == STATUS.MAINTENANCE and RMS_FluidWorkshop.getConsumableQualityKey(optionTwo) ~= nil then
        table.insert(options, g_i18n:getText(RMS_FluidWorkshop.getConsumableQualityKey(optionTwo)))
    elseif (serviceType == STATUS.REPAIR or serviceType == STATUS.OVERHAUL) and optionTwo ~= nil and optionTwo ~= "NONE" then
        table.insert(options, g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, optionTwo)))
    end
    return #options > 0 and table.concat(options, " · ") or "-"
end

---Quote of a service from its bill; a flat rate describes its work
-- @return table groups label, price and lines of each group
function RMS_WorkshopInterventionsFrame:getServiceQuote(serviceType, choice, optionTwo, invoice, workshopType)
    local vehicle = self.vehicle
    local groups = RMS_FluidWorkshop.getQuoteGroups(vehicle, serviceType, choice, optionTwo, invoice, workshopType)
    if #groups > 0 or invoice == nil or invoice[1] == nil or invoice[1].kind ~= "service" then
        return groups
    end
    -- a flat rate: its labour, then what its order table says it covers
    local option = RMS_Utils.formatServiceOption(vehicle, serviceType, choice, workshopType)
    local label = FLAT_RATE_NAMED[serviceType] and option or string.format("%s · %s", RMS_Utils.formatServiceState(serviceType), option)
    local group = { label = label, price = tonumber(invoice[1].price) or 0, lines = {} }
    local hours = RealisticMechanicalSystems.getServiceWorkHours(vehicle, serviceType, choice, optionTwo, workshopType)
    if hours > 0 then
        table.insert(group.lines, { kind = "sub", label = RMS_FluidWorkshop.formatLabour(hours) })
    end
    local order = RMS_WorkshopOrders.ORDERS[serviceType]
    for _, row in ipairs(order ~= nil and order.getRows ~= nil and order.getRows(vehicle, workshopType, optionTwo) or {}) do
        local text, level = row.getCell(choice)
        if level ~= nil and level > 0 then
            table.insert(group.lines, { kind = "bullet", label = string.format("%s · %s", row.name ~= nil and g_i18n:getText(row.name)
                or row.text, text) })
        end
    end
    return { group }
end

---Lines of the quote of the open order, gathered by group
function RMS_WorkshopInterventionsFrame:getQuote(optionTwo, coverKey)
    local vehicle, serviceType, workshopType = self.vehicle, self.serviceType, self.workshopType
    local invoice = RMS_FluidWorkshop.getTransactionInvoice(vehicle, serviceType, workshopType, self.choice, optionTwo)
    local requirements = RMS_FluidWorkshop.getTransactionRequirements(vehicle, serviceType, self.choice, optionTwo)
    local shortages = RMS_FluidWorkshop.getStockShortages(vehicle, g_workshopScreen.sellingPoint, workshopType,
        { { serviceType = serviceType, requirements = requirements, optionOne = self.choice, optionTwo = optionTwo } })
    self.hasStockShortage = next(shortages) ~= nil
    local groups = self:getServiceQuote(serviceType, self.choice, optionTwo, invoice, workshopType)
    for _, group in ipairs(groups) do
        for index = #group.lines, 1, -1 do
            local circuit = group.lines[index].circuit
            if circuit ~= nil then
                group.isFluids = true
                if shortages[circuit] ~= nil then
                    local missingKey = circuit == "engineOil" and RMS_Fluids.getNeedsLowAshOil(vehicle)
                        and "rms_fluid_stock_missing_low_ash" or "rms_fluid_stock_missing"
                    table.insert(group.lines, index + 1, { isAlert = true, label = string.format(g_i18n:getText(missingKey),
                        RMS_FluidWorkshop.formatLiters(shortages[circuit]) .. " " .. g_i18n:getText("unit_literShort")) })
                end
            end
        end
        if group.isFluids and not self.hasStockShortage and (coverKey ~= nil or workshopType ~= RealisticMechanicalSystems.WORKSHOP.DEALER) then
            table.insert(group.lines, { kind = "note", label = g_i18n:getText(coverKey ~= nil and COVER_TEXTS[coverKey].fluids
                or "rms_fluid_stock_required") })
        end
    end
    return groups
end

---Writes the recap: type, options, vehicle, price, time, quote
function RMS_WorkshopInterventionsFrame:writeRecap(recap)
    self.recapType:setText(recap.type)
    self.recapOptions:setText(recap.options or "-")
    self.recapVehicle:setText(self.vehicle:getFullName())
    self.recapPriceLabel:setText(recap.priceLabel or g_i18n:getText("rms_option_menu_price_text"))
    self.recapPrice:setText(recap.price or "-")
    for index, entry in ipairs(RECAP_FIGURES) do
        -- the label takes its width, the value the rest, right aligned
        local figure = self.recapFigures[index]
        local label, value = figure:getDescendantByName("label"), figure:getDescendantByName("figure")
        label:setSize(figure.size[1], nil)
        label:setText(g_i18n:getText(entry.label))
        local unit = figure.size[1] / SHEET_WIDTH
        -- a pixel to spare: a box the width of its text shrinks it
        local labelWidth, gap = label:getTextWidth() + unit, SHEET_GAP * unit
        label:setSize(labelWidth, nil)
        value:setPosition(labelWidth + gap, nil)
        value:setSize(figure.size[1] - labelWidth - gap, nil)
        value:setText(recap[entry.field] or "-")
    end

    local rows, height = RMS_FluidWorkshop.getQuoteRows(recap.quote or {})
    self.quoteLines = rows
    -- the block keeps its place, empty or not
    local isEmpty = #rows == 0
    self.quoteList:setVisible(not isEmpty)
    self.quoteEmptyTitle:setVisible(isEmpty)
    self.quoteEmptyText:setVisible(isEmpty)
    self.quoteEmptyTitle:setText(g_i18n:getText(recap.isRefused and "rms_ws_quote_empty_title_refused" or "rms_ws_quote_empty_title"))
    self.quoteEmptyText:setText(g_i18n:getText(recap.isRefused and "rms_ws_quote_empty_text_refused" or "rms_ws_quote_empty_text"))
    self.quoteSliderBox:setVisible(height > QUOTE_LIST)
    RMS_Utils.reloadListTemplates(self.quoteList)
end

---Rows of the quote
function RMS_WorkshopInterventionsFrame:getNumberOfItemsInSection()
    return #self.quoteLines
end

---Template of a row of the quote
function RMS_WorkshopInterventionsFrame:getCellTypeForItemInSection(_list, _section, index)
    return RMS_FluidWorkshop.getQuoteCellType(self.quoteLines[index])
end

---Writes a row of the quote
function RMS_WorkshopInterventionsFrame:populateCellForItemInSection(_list, _section, index, cell)
    RMS_FluidWorkshop.populateQuoteCell(cell, self.quoteLines[index], self.quoteUnitX, QUOTE_ROW_WIDTH)
end

---Writes the remap offer: figures, bench curves, notes and recap
function RMS_WorkshopInterventionsFrame:updateRemap()
    local vehicle, workshopType, remap = self.vehicle, self.workshopType, STATUS.REMAP
    local offer = RMS_EngineRemap.getOffer(vehicle, workshopType)
    local isRestore = offer.option == RMS_EngineRemap.RESTORE
    local green, light = RMS_Utils.COLOR.HIGHLIGHT, RMS_Utils.COLOR.TEXT
    self.choice = offer.option
    self.remapOffer = offer
    self.remapCurve = RMS_EngineRemap.getCurve(vehicle, not isRestore and workshopType or nil)

    local shownHp, otherHp, shownTorque, otherTorque = offer.remapHp, offer.stockHp, offer.remapTorque, offer.stockTorque
    if isRestore then
        shownHp, otherHp, shownTorque, otherTorque = otherHp, shownHp, otherTorque, shownTorque
    end
    local referenceFormat = g_i18n:getText(isRestore and "rms_remap_today_format" or "rms_remap_stock_format")
    local tiles = {
        { "rms_remap_max_power", formatPower(shownHp), string.format(referenceFormat, formatPower(otherHp)), isRestore and light or green },
        { "rms_remap_max_torque", formatTorque(shownTorque), string.format(referenceFormat, formatTorque(otherTorque)), isRestore and light or green }
    }
    if isRestore and offer.isDealer then
        table.insert(tiles, { "rms_ws_warranty_title", g_i18n:getText("rms_remap_warranty_lost"), "", RMS_Utils.COLOR.ALERT })
    elseif isRestore then
        local monthsLeft = math.max(offer.freeRestoreUntil - 1 - vehicle.age, 0)
        local period = (g_currentMission.environment.currentPeriod - 1 + monthsLeft) % 12 + 1
        table.insert(tiles, { "rms_remap_free_restore", string.format(g_i18n:getText("rms_remap_until_format"), g_i18n:formatPeriod(period, false)),
            string.format(g_i18n:getText("rms_remap_then_format"), g_i18n:formatMoney(offer.restorePrice, 0, true, false)), green })
    else
        table.insert(tiles, { "rms_remap_gain", string.format(g_i18n:getText("rms_remap_gain_format"), math.floor(offer.gain * 100 + 0.5)),
            -- the difference of the two figures shown, not their rounded difference
            "+" .. formatPower(MathUtil.round(offer.remapHp) - MathUtil.round(offer.stockHp)) .. " · +"
                .. formatTorque(MathUtil.round(offer.remapTorque) - MathUtil.round(offer.stockTorque)), light })
    end
    for index, tile in ipairs(self.remapTileElements) do
        local data = tiles[index]
        tile:getDescendantByName("label"):setText(g_i18n:getText(data[1]))
        local value = tile:getDescendantByName("value")
        value:setText(data[2])
        value:setTextColor(unpack(data[4]))
        tile:getDescendantByName("note"):setText(data[3])
    end

    local chartTitles = { [false] = { [false] = "rms_remap_curves_announced", [true] = "rms_remap_curves_measured" },
        [true] = { [false] = "rms_remap_curves_maker", [true] = "rms_remap_curves_dealer_measured" } }
    self.remapChartTitle:setText(g_i18n:getText(chartTitles[offer.isDealer][isRestore]))
    local notes = isRestore and { { "gui.storeAttribute_info", "rms_remap_note_restored" }, { "gui.storeAttribute_fuel", "rms_remap_note_same_fuel" } }
        or { { "gui.storeAttribute_fuel", "rms_remap_note_fuel" }, offer.isBeyondBlock and { "gui.storeAttribute_condition", "rms_remap_note_overload" }
            or { "gui.storeAttribute_info", offer.isDealer and "rms_remap_note_stock_kept_dealer" or "rms_remap_note_stock_kept" } }
    for index, note in ipairs(self.remapNoteElements) do
        note:getDescendantByName("icon"):setImageSlice(nil, notes[index][1])
        note:getDescendantByName("text"):setText(g_i18n:getText(notes[index][2]))
    end

    local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, remap, workshopType, offer.option, nil)
    local duration = vehicle:getServiceDuration(remap, offer.option, nil, workshopType)
    local quote = self:getQuote(nil, nil)
    -- the warranty a remap takes, or the factory term a restore leaves lost
    if isRestore and offer.warrantyVoided and offer.factoryTerm or not isRestore and offer.warrantyActive then
        table.insert(quote, getLostWarranty(vehicle, offer, isRestore))
    end
    self:writeRecap({
        type = isRestore and g_i18n:getText("rms_remap_restore") or RMS_Utils.formatServiceState(remap),
        options = RMS_Utils.formatServiceOption(vehicle, remap, offer.option, workshopType),
        price = price == 0 and g_i18n:getText("rms_remap_free") or g_i18n:formatMoney(price, 0, true, false),
        duration = formatServiceDuration(remap, duration, RMS_Utils.formatShortDuration),
        finish = RMS_Utils.formatFinishTime(vehicle:getServiceFinishTime(remap, offer.option, nil, workshopType)),
        quote = quote
    })
    self.startButton:setDisabled(not self.state.isOpen or offer.refusal ~= nil or price == nil)
end

---Draws the stroke of a legend entry, dashed for torque
function RMS_WorkshopInterventionsFrame:onDrawLegendSwatch(element)
    local entry = element.legendEntry
    local x, width = element.absPosition[1], element.absSize[1]
    local y = element.absPosition[2] + element.absSize[2] * 0.5
    local pixel = element.absSize[2] * g_screenHeight / 20
    if entry.isDashed then
        for dash = 0, 2 do
            RMS_Chart.drawLine(x + width * dash * 10 / 26, y, x + width * (dash * 10 + 6) / 26, y, 2.2 * pixel, entry.color)
        end
    else
        RMS_Chart.drawLine(x, y, x + width, y, 3 * pixel, entry.color)
    end
end

local function getAxisScale(low, high, steps)
    for _, step in ipairs(steps) do
        local bottom = math.floor(low / step) * step
        if bottom + CHART_INTERVALS * step >= high then
            return bottom, step
        end
    end
    local step = steps[#steps]
    return math.floor(low / step) * step, step
end

local function drawAxisText(x, y, size, text, color, isBold, alignment)
    setTextBold(isBold)
    setTextColor(color[1], color[2], color[3], color[4])
    setTextAlignment(alignment)
    renderText(x, y, size, text)
end

local function drawPill(x, y, text, size, background, textColor)
    setTextBold(true)
    local width = getTextWidth(size, text) + size * 1.2 * g_screenHeight / g_screenWidth
    local height = size * 1.8
    local radius = height * 0.5 * g_screenHeight / g_screenWidth
    drawFilledRect(x - width * 0.5 + radius, y - height * 0.5, width - 2 * radius, height, background[1], background[2], background[3], background[4])
    RMS_Chart.drawDisc(x - width * 0.5 + radius, y, height * g_screenHeight, background)
    RMS_Chart.drawDisc(x + width * 0.5 - radius, y, height * g_screenHeight, background)
    setTextColor(textColor[1], textColor[2], textColor[3], textColor[4])
    setTextAlignment(RenderText.ALIGN_CENTER)
    renderText(x, y, size, text)
end

---Draws stock and remapped power and torque over the engine speed
function RMS_WorkshopInterventionsFrame:onDrawRemapChart()
    local curve, offer, area = self.remapCurve, self.remapOffer, self.remapChartArea
    local unitX, unitY = area.absSize[1] / CHART_WIDTH, area.absSize[2] / CHART_HEIGHT
    local left, top = area.absPosition[1], area.absPosition[2] + area.absSize[2]
    local px = function(value) return left + value * unitX end
    local py = function(value) return top - value * unitY end
    local pixel = unitY * g_screenHeight

    local rpms = curve.rpm
    local rpmLow = math.floor(rpms[1] / 50) * 50
    local rpmHigh = math.ceil(rpms[#rpms] / 50) * 50 + 50
    local _, rpmStep = getAxisScale(0, rpmHigh - rpmLow, RPM_STEPS)
    local powerBottom, powerStep = getAxisScale(math.min(unpack(curve.stockHp)), math.max(unpack(curve.remapHp)), POWER_STEPS)
    local torqueBottom, torqueStep = getAxisScale(math.min(unpack(curve.stockTorque)), math.max(unpack(curve.remapTorque)), TORQUE_STEPS)
    local plotHeight = PLOT_BOTTOM - PLOT_TOP
    local x = function(rpm) return px(PLOT_LEFT + (rpm - rpmLow) / (rpmHigh - rpmLow) * (PLOT_RIGHT - PLOT_LEFT)) end
    local yPower = function(hp) return py(PLOT_BOTTOM - (hp - powerBottom) / (CHART_INTERVALS * powerStep) * plotHeight) end
    local yTorque = function(nm) return py(PLOT_BOTTOM - (nm - torqueBottom) / (CHART_INTERVALS * torqueStep) * plotHeight) end

    for index = 0, CHART_INTERVALS do
        local y = py(PLOT_BOTTOM - index * plotHeight / CHART_INTERVALS)
        local color = index == 0 and CHART_AXIS or CHART_GRID
        drawFilledRect(px(PLOT_LEFT), y, px(PLOT_RIGHT) - px(PLOT_LEFT), 1 / g_screenHeight, color[1], color[2], color[3], color[4])
    end
    for rpm = math.ceil(rpmLow / 100) * 100, rpms[#rpms], 100 do
        drawFilledRect(x(rpm), py(PLOT_BOTTOM), 1 / g_screenWidth, py(PLOT_TOP) - py(PLOT_BOTTOM), CHART_GRID[1], CHART_GRID[2], CHART_GRID[3],
            CHART_GRID[4])
    end

    local xs, stockPower, remapPower, stockTorque, remapTorque = {}, {}, {}, {}, {}
    for index, rpm in ipairs(rpms) do
        xs[index] = x(rpm)
        stockPower[index], remapPower[index] = yPower(curve.stockHp[index]), yPower(curve.remapHp[index])
        stockTorque[index], remapTorque[index] = yTorque(curve.stockTorque[index]), yTorque(curve.remapTorque[index])
    end
    local step, point = BAND_STEP / g_screenWidth, 1
    for bandX = xs[1], xs[#xs] - step, step do
        while xs[point + 1] < bandX do
            point = point + 1
        end
        local share = (bandX - xs[point]) / (xs[point + 1] - xs[point])
        local low = stockPower[point] + (stockPower[point + 1] - stockPower[point]) * share
        local high = remapPower[point] + (remapPower[point + 1] - remapPower[point]) * share
        drawFilledRect(bandX, low, step, high - low, CHART_FILL[1], CHART_FILL[2], CHART_FILL[3], CHART_FILL[4])
    end
    RMS_Chart.drawCurve(xs, stockTorque, 2 * pixel, CHART_GREY, 6 * pixel)
    RMS_Chart.drawCurve(xs, remapTorque, 2.2 * pixel, RMS_Utils.COLOR.HIGHLIGHT, 6 * pixel)
    RMS_Chart.drawCurve(xs, stockPower, 2.4 * pixel, CHART_GREY)
    RMS_Chart.drawCurve(xs, remapPower, 3 * pixel, RMS_Utils.COLOR.HIGHLIGHT)

    local peakX = x(curve.peakRpm)
    local peakStock, peakRemap = yPower(offer.stockHp), yPower(offer.remapHp)
    RMS_Chart.drawDisc(peakX, peakStock, 9 * pixel, CHART_GREY)
    RMS_Chart.drawDisc(peakX, peakStock, 4.6 * pixel, CHART_BLOCK)
    RMS_Chart.drawDisc(peakX, peakRemap, 10 * pixel, RMS_Utils.COLOR.HIGHLIGHT)
    RMS_Chart.drawDisc(peakX, peakRemap, 5 * pixel, CHART_BLOCK)

    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    local textSize = 12 * unitY
    for index = 0, CHART_INTERVALS do
        local y = py(PLOT_BOTTOM - index * plotHeight / CHART_INTERVALS)
        local isTop = index == CHART_INTERVALS
        local power, torque = powerBottom + index * powerStep, torqueBottom + index * torqueStep
        drawAxisText(px(PLOT_LEFT - 8), y, textSize, isTop and formatPower(power) or g_i18n:formatNumber(power, 0),
            isTop and RMS_Utils.COLOR.TEXT or CHART_GREY, isTop, RenderText.ALIGN_RIGHT)
        drawAxisText(px(PLOT_RIGHT + 8), y, textSize, isTop and formatTorque(torque) or g_i18n:formatNumber(torque, 0),
            isTop and RMS_Utils.COLOR.TEXT or CHART_GREY, isTop, RenderText.ALIGN_LEFT)
    end
    local labelY = py(PLOT_BOTTOM + 17)
    for rpm = math.ceil(rpmLow / rpmStep) * rpmStep, rpmHigh - rpmStep * 0.75, rpmStep do
        drawAxisText(x(rpm), labelY, textSize, g_i18n:formatNumber(rpm, 0), CHART_GREY, false, RenderText.ALIGN_CENTER)
    end
    drawAxisText(px(PLOT_RIGHT), labelY, textSize, g_i18n:getText("unit_rpmShort"), RMS_Utils.COLOR.TEXT, true, RenderText.ALIGN_RIGHT)

    local pillSize = 13 * unitY
    drawPill(peakX, peakRemap + 22 * unitY, formatPower(offer.remapHp), pillSize, RMS_Utils.COLOR.HIGHLIGHT, COLOR_MAIN_DARK)
    drawPill(peakX, peakStock + 20 * unitY, formatPower(offer.stockHp), pillSize, CHART_PILL_STOCK, RMS_Utils.COLOR.TEXT)

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
end

---Opens the intervention of a clicked choice
function RMS_WorkshopInterventionsFrame:onClickAction(button)
    self.dialog:selectService(ACTIONS[RMS_Utils.getKeyByValue(self.actionButtons, button)].service)
end

---Picks the option of a clicked column
function RMS_WorkshopInterventionsFrame:onClickColumn(button)
    self.choice = self.choices[button.templateIndex]
    self.dialog:refresh()
end

---Picks the system of a partial overhaul
function RMS_WorkshopInterventionsFrame:onClickSystem(button)
    self.optionTwo = self.systemValues[button.templateIndex]
    self.dialog:refresh()
end

---Picks a part quality
function RMS_WorkshopInterventionsFrame:onClickQuality(button)
    self.optionTwo = RealisticMechanicalSystems.PART_TYPES_ORDER[button.templateIndex]
    self.dialog:refresh()
end

---Opens the color picker of a zone
function RMS_WorkshopInterventionsFrame:onClickColor(button)
    local zone, vehicle = button.colorZone, self.vehicle
    local choices = RMS_Bodywork.getColorChoices(vehicle, zone, self.bodyworkColors)
    local customChoice = RMS_Bodywork.getCustomColorChoice(vehicle, zone, self.bodyworkColors)
    local selection = self.bodyworkColors[zone]
    local currentIndex = type(selection) == "table" and selection.index or selection
    if currentIndex == nil or currentIndex == 0 then
        currentIndex = vehicle.configurations[zone]
    end
    local colors, defaultIndex, defaultMaterial = {}, nil, nil
    for position, choice in ipairs(choices) do
        local item = choice.item
        local material = item.isMetallic and "metallic" or item.isMat and "matte" or "glossy"
        colors[position] = { name = item.name, color = item.color, material = material, materialTemplateName = item.materialTemplateName }
        if choice.index == currentIndex then
            defaultIndex, defaultMaterial = position, material
        end
    end
    local customColor
    if type(selection) == "table" then
        customColor = { selection.color[1], selection.color[2], selection.color[3], ColorPickerDialog.MATERIAL_GLOSSY }
    elseif customChoice ~= nil and currentIndex == customChoice.index then
        local data = vehicle.configurationData[zone]
        if data ~= nil and data[currentIndex] ~= nil and RMS_Bodywork.isValidColor(data[currentIndex].color) then
            local color = data[currentIndex].color
            customColor = { color[1], color[2], color[3], ColorPickerDialog.MATERIAL_GLOSSY }
        end
    end
    ColorPickerDialog.show(function(_, selectedIndex, _, customColorData)
        if self.vehicle == vehicle and self.serviceType == STATUS.BODYWORK then
            self:onColorPicked(zone, choices, selectedIndex, customColorData)
        end
    end, self, nil, colors, defaultIndex, defaultMaterial, customColor, customChoice ~= nil, false, true)
end

---Applies the color picked for a zone, and drops the ones it rules out
function RMS_WorkshopInterventionsFrame:onColorPicked(zone, choices, selectedIndex, customColorData)
    local vehicle = self.vehicle
    if customColorData ~= nil then
        local customChoice = RMS_Bodywork.getCustomColorChoice(vehicle, zone, self.bodyworkColors)
        local color = customColorData.customColor
        if customChoice == nil or color == nil or not RMS_Bodywork.isValidColor(color) then
            return
        end
        self.bodyworkColors[zone] = { index = customChoice.index, color = { color[1], color[2], color[3] } }
    elseif choices[selectedIndex] ~= nil then
        self.bodyworkColors[zone] = choices[selectedIndex].index
    else
        return
    end
    for _, otherZone in ipairs(RMS_Bodywork.getColorZones(vehicle)) do
        local other = self.bodyworkColors[otherZone]
        if otherZone ~= zone and other ~= nil and other ~= 0 then
            local isStillOffered = false
            if type(other) == "table" then
                local customChoice = RMS_Bodywork.getCustomColorChoice(vehicle, otherZone, self.bodyworkColors)
                isStillOffered = customChoice ~= nil and customChoice.index == other.index
            else
                for _, choice in ipairs(RMS_Bodywork.getColorChoices(vehicle, otherZone, self.bodyworkColors)) do
                    isStillOffered = isStillOffered or choice.index == other
                end
            end
            if not isStillOffered then
                self.bodyworkColors[otherZone] = 0
            end
        end
    end
    self.dialog:refresh()
end

---Starts the order; a remap costing time or warranty is confirmed
function RMS_WorkshopInterventionsFrame:onClickStart()
    local vehicle = self.vehicle
    if self.serviceType == STATUS.REMAP and self.choice == RMS_EngineRemap.REMAP then
        local sentences = {}
        if not RealisticMechanicalSystems.getIsServiceInstant(STATUS.REMAP) then
            local duration = vehicle:getServiceDuration(STATUS.REMAP, self.choice, nil, self.workshopType)
            table.insert(sentences, string.format(g_i18n:getText("rms_remap_confirm_format"), vehicle:getFullName(), RMS_Utils.formatDuration(duration)))
        end
        if self.remapOffer.warrantyActive then
            table.insert(sentences, g_i18n:getText("rms_remap_confirm_warranty"))
        end
        if #sentences > 0 then
            YesNoDialog.show(self.onRemapConfirm, self, table.concat(sentences, "\n"), g_i18n:getText("rms_remap_confirm_title"), nil, nil,
                DialogElement.TYPE_WARNING)
            return
        end
    end
    self:startOrder()
end

---Starts the remap once the player confirmed it
function RMS_WorkshopInterventionsFrame:onRemapConfirm(yes)
    if yes then
        self:startOrder()
    end
end

---Sends the open order and leaves it
function RMS_WorkshopInterventionsFrame:startOrder()
    if RMS_WorkshopOrders.start(self.vehicle, self.workshopType, self.serviceType, self.choice, self:getOptionTwo(self.choice)) then
        self.serviceType = nil
        self.dialog:refresh()
    end
end

---Leaves the open order for the choice list
function RMS_WorkshopInterventionsFrame:goBack()
    if self.serviceType == nil and self.refusedService == nil then
        return false
    end
    self.serviceType, self.refusedService = nil, nil
    self.dialog:refresh()
    return true
end

---The choices, the order, then the start button
function RMS_WorkshopInterventionsFrame:getFocusColumns()
    local actions = {}
    for _, button in ipairs(self.actionButtons) do
        table.insert(actions, { button })
    end
    local systemRows = { {}, {} }
    for index, card in ipairs(self.systemCards) do
        table.insert(systemRows[math.ceil(index / SYSTEMS_PER_ROW)], card)
    end
    local order = { self.tableColumns, systemRows[1], systemRows[2], self.qualityCards }
    for _, row in pairs(self.colorRows) do
        table.insert(order, { row:getDescendantByName("button") })
    end
    return { actions, order, { { self.startButton } } }
end

---The selected column, when the order shows one
function RMS_WorkshopInterventionsFrame:getFocusEntry()
    for index, column in ipairs(self.tableColumns) do
        if column:getIsVisible() and self.choices[index] == self.choice then
            return column
        end
    end
    return nil
end
