-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle diagnostic screen.
RMS_DiagnosticScreen = {}
RMS_DiagnosticScreen.INSTANCE = nil
RMS_DiagnosticScreen.PAGE = { CONNECTION = 1, SCAN = 2 }

local RMS_DiagnosticScreen_mt = Class(RMS_DiagnosticScreen, MessageDialog)
local modDirectory = g_currentModDirectory
local PAGE = RMS_DiagnosticScreen.PAGE

local REFRESH_MS = 250
local COLOR = {
    TEXT = { 0.0452, 0.0452, 0.0452, 1 },
    GREY = { 0.2346, 0.2346, 0.1981, 1 },
    OK = { 0.1144, 0.2747, 0, 1 },
    RED = { 0.6308, 0.0343, 0.0423, 1 }
}
local MACHINE_STATE_COLORS = { ok = COLOR.OK, plugged = COLOR.OK, moving = COLOR.RED }
local shownTexts = setmetatable({}, { __mode = "k" })

---Sets a text only when it changes; every setText lays it out again
-- @param table element text element or button
-- @param string text text
local function setText(element, text)
    if shownTexts[element] ~= text then
        shownTexts[element] = text
        element:setText(text)
    end
end

---Loads the screen layout and stores the shared instance
function RMS_DiagnosticScreen.register()
    local screen = RMS_DiagnosticScreen.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_DiagnosticScreen.xml", "RMS_DiagnosticScreen", screen)
    RMS_DiagnosticScreen.INSTANCE = screen
end

---Create instance of RMS_DiagnosticScreen
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table screen instance of class RMS_DiagnosticScreen
function RMS_DiagnosticScreen.new(target, customMt)
    local self = MessageDialog.new(target, customMt or RMS_DiagnosticScreen_mt)
    self.tool = nil
    self.page = PAGE.CONNECTION
    self.machines = {}
    self.rows = {}
    self.refreshTimer = 0
    return self
end

-- @param table tool trolley
function RMS_DiagnosticScreen.show(tool)
    local screen = RMS_DiagnosticScreen.INSTANCE
    screen.tool = tool
    screen.page = RMS_DiagnosticTool.getTarget(tool) ~= nil and PAGE.SCAN or PAGE.CONNECTION
    g_gui:showDialog("RMS_DiagnosticScreen")
end

local function getMachinePath(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local parts = {}
    if storeItem ~= nil then
        local category = g_storeManager:getCategoryByName(storeItem.categoryName)
        if category ~= nil then
            table.insert(parts, utf8ToUpper(category.title))
        end
        local brand = g_brandManager:getBrandByIndex(storeItem.brandIndex)
        if brand ~= nil and brand.title ~= nil then
            table.insert(parts, utf8ToUpper(brand.title))
        end
    end
    table.insert(parts, vehicle:getName())
    return "> " .. table.concat(parts, "   > ")
end

local function getMachines(tool)
    local target = RMS_DiagnosticTool.getTarget(tool)
    local machines = {}
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec ~= nil and not spec.isExcludedVehicle and vehicle:getOwnerFarmId() == tool:getOwnerFarmId() then
            local distance = RMS_BatteryCharger.getDistance(tool, vehicle)
            if distance <= RMS_BatteryCharger.MAX_DISTANCE then
                local reason = vehicle == target and "plugged" or RMS_DiagnosticTool.validate(tool, vehicle)
                if reason ~= "unavailable" and reason ~= "access" and reason ~= "distance" then
                    table.insert(machines, { vehicle = vehicle, distance = distance, reason = reason })
                end
            end
        end
    end
    table.sort(machines, function(a, b) return a.distance < b.distance end)
    return machines
end

local function getCodeText(entry)
    if entry.spn == nil then
        return g_i18n:getText("rms_diagnostic_uncoded")
    end
    return string.format("%s. %s.", RMS_DiagnosticTool.getSpnName(entry.spn), g_i18n:getText("rms_diagnostic_fmi_" .. entry.fmi))
end

local function getScanRows(tool, target, controllers)
    local spec = tool[RMS_DiagnosticTool.SPEC_TABLE_NAME]
    local SCAN = RMS_DiagnosticTool.SCAN
    local rows = {}
    if spec.scanState ~= SCAN.RUNNING and spec.scanState ~= SCAN.DONE then
        return rows, 0, 0
    end
    local entries = {}
    for _, fault in ipairs(spec.scanFaults) do
        local entry = RMS_DiagnosticTool.getFaultEntry(target, fault.breakdownId, fault.isCritical)
        local ecu = entry.ecu or "DASHBOARD"
        entries[ecu] = entries[ecu] or {}
        table.insert(entries[ecu], entry)
    end
    local answered = spec.scanState == SCAN.DONE and #controllers
        or math.floor(RMS_DiagnosticTool.getScanProgress(tool) * #controllers)
    for index, ecu in ipairs(controllers) do
        local codes = index <= answered and entries[ecu] or {}
        table.insert(rows, { ecu = ecu, codes = codes, isAnswered = index <= answered, isQuerying = index == answered + 1 })
        for _, entry in ipairs(codes) do
            table.insert(rows, { entry = entry })
        end
    end
    return rows, answered, #controllers
end

---Returns a key identifying a list's rows
local function getRowsSignature(rows)
    local parts = {}
    for _, row in ipairs(rows) do
        table.insert(parts, row.entry ~= nil and (row.entry.breakdownId .. tostring(row.entry.fmi))
            or string.format("%s%d%s%s", row.ecu or row.vehicle and row.vehicle.id or "", row.codes and #row.codes or 0,
                tostring(row.isAnswered or row.reason), tostring(row.isQuerying or row.distanceText)))
    end
    return table.concat(parts, "|")
end

local function getDetailFields(target, entry, isLicenceValid)
    local fields = {}
    local definition = RMS_Breakdowns.BreakdownRegistry[entry.breakdownId]
    local systemName = definition ~= nil and g_i18n:getText(RMS_Utils.getSystemLabel(target, entry.system or definition.system)) or ""
    if entry.spn == nil then
        table.insert(fields, { g_i18n:getText("rms_diagnostic_system_label"), systemName })
        return fields, g_i18n:getText("rms_diagnostic_note_uncoded")
    end
    table.insert(fields, { g_i18n:getText("rms_diagnostic_ecu_label"), g_i18n:getText("rms_diagnostic_ecu_" .. string.lower(entry.ecu)) })
    table.insert(fields, { string.format(g_i18n:getText("rms_diagnostic_spn_label"), entry.spn), RMS_DiagnosticTool.getSpnName(entry.spn) })
    table.insert(fields, { string.format(g_i18n:getText("rms_diagnostic_fmi_label"), entry.fmi), g_i18n:getText("rms_diagnostic_fmi_" .. entry.fmi) })
    if not isLicenceValid then
        return fields, g_i18n:getText("rms_diagnostic_note_no_licence")
    end
    if not RealisticMechanicalSystems.getBreakdownNeedsDiagnosticTool(entry.breakdownId) then
        table.insert(fields, { g_i18n:getText("rms_diagnostic_system_label"), systemName })
        return fields, g_i18n:getText("rms_diagnostic_note_inspection")
    end
    local operation = RMS_Config.MAINTENANCE.REPAIR_OPERATIONS[entry.breakdownId]
    local hours = RealisticMechanicalSystems.getRepairLabourHours(target, entry.breakdownId, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM)
    table.insert(fields, { g_i18n:getText("rms_diagnostic_part_label"), g_i18n:getText(definition.part) })
    table.insert(fields, { g_i18n:getText("rms_diagnostic_repair_time_label"), RMS_Utils.formatDuration(hours) })
    table.insert(fields, { g_i18n:getText("rms_diagnostic_where_label"),
        g_i18n:getText(operation.category == "highVoltage" and "rms_diagnostic_where_high_voltage" or "rms_diagnostic_where_diagnostic") })
    return fields, nil
end

---Shows the help of the selected code beside the list
function RMS_DiagnosticScreen:updateDetail()
    local index = self.codeList.selectedIndex
    local row = self.rows[index]
    if row ~= nil and row.entry == nil then
        row = #row.codes > 0 and self.rows[index + 1] or nil
    end
    local entry = row ~= nil and row.entry or nil
    local target = RMS_DiagnosticTool.getTarget(self.tool)
    self.detailPanel:setVisible(entry ~= nil and target ~= nil)
    if entry == nil or target == nil then
        return
    end
    setText(self.detailCode, entry.spn ~= nil and string.format("SPN %d    FMI %d", entry.spn, entry.fmi)
        or g_i18n:getText("rms_diagnostic_uncoded_title"))
    setText(self.detailText, getCodeText(entry))
    local fields, note = getDetailFields(target, entry, RMS_DiagnosticTool.getIsLicenceValid(self.tool))
    for fieldIndex = 1, #self.detailLabel do
        local field = fields[fieldIndex]
        self.detailLabel[fieldIndex]:setVisible(field ~= nil)
        self.detailValue[fieldIndex]:setVisible(field ~= nil)
        if field ~= nil then
            setText(self.detailLabel[fieldIndex], field[1])
            setText(self.detailValue[fieldIndex], field[2])
        end
    end
    self.detailNoteLine:setVisible(note ~= nil)
    self.detailNote:setVisible(note ~= nil)
    setText(self.detailNote, note or "")
end

function RMS_DiagnosticScreen:refreshScanPage(target)
    local spec = self.tool[RMS_DiagnosticTool.SPEC_TABLE_NAME]
    local SCAN = RMS_DiagnosticTool.SCAN
    if self.controllersTarget ~= target then
        self.controllersTarget, self.controllers = target, RMS_DiagnosticTool.getControllers(target)
    end
    local rows, answered, total = getScanRows(self.tool, target, self.controllers)
    local isPowered = RMS_DiagnosticTool.getIsPowered(target)
    local voltage = string.format(g_i18n:getText("rms_diagnostic_voltage"),
        g_i18n:formatNumber(target.spec_RealisticMechanicalSystems.systemVoltageV, 1))
    if spec.scanState == SCAN.RUNNING then
        setText(self.headerText, string.format(g_i18n:getText("rms_diagnostic_scan_running"), answered, total))
        setText(self.headerValue, voltage)
    elseif spec.scanState == SCAN.DONE then
        setText(self.headerText, g_i18n:getText("rms_diagnostic_scan_done"))
        setText(self.headerValue, string.format(g_i18n:getText("rms_diagnostic_detected"), total, total) .. "      " .. voltage)
    else
        setText(self.headerText, g_i18n:getText(spec.scanState == SCAN.INTERRUPTED and "rms_diagnostic_scan_interrupted"
            or isPowered and "rms_diagnostic_scan_idle" or "rms_battery_isolator_open"))
        setText(self.headerValue, voltage)
    end

    local signature = getRowsSignature(rows)
    if signature ~= self.rowsSignature then
        self.rowsSignature = signature
        self.rows = rows
        RMS_Utils.reloadListTemplates(self.codeList)
    end
    local hasRows = #rows > 0
    self.codeList:setVisible(hasRows)
    self.emptyIcon:setVisible(not hasRows)
    self.emptyText:setVisible(not hasRows)
    self.legendLine:setVisible(hasRows)
    self.legendIcon:setVisible(hasRows)
    self.legendText:setVisible(hasRows)
    setText(self.scanButton, g_i18n:getText(spec.scanState == SCAN.NONE and "rms_diagnostic_scan_start" or "rms_diagnostic_scan_again"))
    self.scanButton:setVisible(spec.scanState ~= SCAN.RUNNING)
    self.scanButton:setDisabled(not isPowered)
    self:updateDetail()
end

function RMS_DiagnosticScreen:refreshConnectionPage()
    local machines = getMachines(self.tool)
    for _, machine in ipairs(machines) do
        machine.distanceText = g_i18n:formatNumber(machine.distance, 1) .. " m"
    end
    local signature = getRowsSignature(machines)
    if signature ~= self.machinesSignature then
        local selected = self.machines[self.machineList.selectedIndex]
        self.machinesSignature = signature
        self.machines = machines
        self.machineList:reloadData()
        for index, machine in ipairs(machines) do
            if selected ~= nil and machine.vehicle == selected.vehicle then
                self.machineList:setSelectedItem(1, index, false, true)
            end
        end
    end
    self.machineList:setVisible(#machines > 0)
    self.machineEmptyText:setVisible(#machines == 0)
    setText(self.headerText, g_i18n:getText("rms_diagnostic_connection_hint"))
    setText(self.headerValue, string.format(g_i18n:getText("rms_diagnostic_reach"),
        g_i18n:formatNumber(RMS_BatteryCharger.MAX_DISTANCE, 0) .. " m"))
end

---Refreshes the whole screen from the trolley
function RMS_DiagnosticScreen:refresh()
    local target = RMS_DiagnosticTool.getTarget(self.tool)
    if target == nil and self.page == PAGE.SCAN then
        self.page = PAGE.CONNECTION
    end
    self.connectionPage:setVisible(self.page == PAGE.CONNECTION)
    self.scanPage:setVisible(self.page == PAGE.SCAN)
    self.menuConnectionMark:setVisible(self.page == PAGE.CONNECTION)
    self.menuScanMark:setVisible(self.page == PAGE.SCAN)
    self.menuConnectionButton:setSelected(self.page == PAGE.CONNECTION)
    self.menuScanButton:setSelected(self.page == PAGE.SCAN)
    self.menuScanButton:setDisabled(target == nil)

    if self.page == PAGE.CONNECTION then
        self:refreshConnectionPage()
    else
        self:refreshScanPage(target)
    end

    local selected = self.machines[self.machineList.selectedIndex]
    local shown = target or self.page == PAGE.CONNECTION and selected ~= nil and selected.vehicle or nil
    setText(self.pathText, shown ~= nil and getMachinePath(shown) or "")
    setText(self.connectButton, g_i18n:getText(target ~= nil and "rms_diagnostic_disconnect" or "rms_diagnostic_connect"))
    self.connectButton:setDisabled(target == nil and (selected == nil or selected.reason ~= "ok"))

    local isLicenceValid = RMS_DiagnosticTool.getIsLicenceValid(self.tool)
    if isLicenceValid then
        local period, year = RMS_DiagnosticTool.getLicenceEnd(self.tool)
        setText(self.licenceText, string.format(g_i18n:getText("rms_diagnostic_licence_end"), g_i18n:formatPeriod(period), year))
    else
        setText(self.licenceText, g_i18n:getText("rms_diagnostic_licence_expired"))
    end
    self.renewButton:setVisible(not isLicenceValid)
    setText(self.renewButton, string.format(g_i18n:getText("rms_diagnostic_licence_renew"),
        g_i18n:formatMoney(RMS_DiagnosticTool.getLicencePrice(), 0, true, true)))
    local environment = g_currentMission.environment
    setText(self.timeText, string.format("%02d:%02d", environment.currentHour, environment.currentMinute))
    local focusKey = self.page .. tostring(isLicenceValid)
    if focusKey ~= self.focusKey then
        self.focusKey = focusKey
        self:updateFocusLinks()
    end
end

function RMS_DiagnosticScreen:updateFocusLinks()
    local columns = { { { self.menuConnectionButton }, { self.menuScanButton } } }
    if self.page == PAGE.CONNECTION then
        table.insert(columns, { { self.machineList } })
    else
        table.insert(columns, { { self.codeList } })
        table.insert(columns, { { self.scanButton } })
    end
    if self.renewButton:getIsVisible() then
        table.insert(columns, { { self.renewButton } })
    end
    self.focusEntry = RMS_Utils.linkFocusColumns(self.connectButton, columns)
    FocusManager:linkElements(self.connectButton, FocusManager.BOTTOM, self.focusEntry)
    RMS_Utils.keepFocusShown(self.focusEntry)
end

function RMS_DiagnosticScreen:update(dt)
    RMS_DiagnosticScreen:superClass().update(self, dt)
    if self.tool == nil then
        return
    end
    if not RMS_BatteryCharger.getIsAlive(self.tool) then
        self:close()
        return
    end
    self.refreshTimer = self.refreshTimer - dt
    if self.refreshTimer <= 0 then
        self.refreshTimer = REFRESH_MS
        self:refresh()
    end
end

---Returns the number of rows of a list
function RMS_DiagnosticScreen:getNumberOfItemsInSection(list, section)
    return list == self.machineList and #self.machines or #self.rows
end

---Tells the code list which template a row takes
function RMS_DiagnosticScreen:getCellTypeForItemInSection(list, section, index)
    if list == self.machineList then
        return "machineRow"
    end
    local row = self.rows[index]
    return row ~= nil and row.entry ~= nil and "codeRow" or "systemRow"
end

---Fills one row of a list
function RMS_DiagnosticScreen:populateCellForItemInSection(list, section, index, cell)
    if list == self.machineList then
        local machine = self.machines[index]
        cell:getAttribute("machineName"):setText(machine.vehicle:getFullName())
        cell:getAttribute("machineDistance"):setText(machine.distanceText)
        local state = cell:getAttribute("machineState")
        state:setText(g_i18n:getText("rms_diagnostic_state_" .. machine.reason))
        state:setTextColor(unpack(MACHINE_STATE_COLORS[machine.reason] or COLOR.GREY))
        return
    end
    local row = self.rows[index]
    if row.entry ~= nil then
        cell:getAttribute("codeSpn"):setText(row.entry.spn ~= nil and string.format("SPN %d", row.entry.spn) or "")
        cell:getAttribute("codeFmi"):setText(row.entry.spn ~= nil and string.format("FMI %d", row.entry.fmi) or "")
        cell:getAttribute("codeText"):setText(getCodeText(row.entry))
        return
    end
    cell:getAttribute("systemName"):setText(g_i18n:getText("rms_diagnostic_ecu_" .. string.lower(row.ecu)))
    local hasCodes = #row.codes > 0
    local state = cell:getAttribute("systemState")
    state:setVisible(not hasCodes)
    state:setText(g_i18n:getText(row.isAnswered and "rms_diagnostic_no_fault"
        or row.isQuerying and "rms_diagnostic_querying" or "rms_diagnostic_waiting"))
    state:setTextColor(unpack(row.isAnswered and COLOR.OK or COLOR.GREY))
    cell:getAttribute("systemWarning"):setVisible(hasCodes)
    cell:getAttribute("systemCount"):setVisible(hasCodes)
    cell:getAttribute("systemCount"):setText("x" .. #row.codes)
end

function RMS_DiagnosticScreen:onListSelectionChanged(list, section, index)
    if list == self.codeList then
        self:updateDetail()
    else
        self.refreshTimer = 0
    end
end

---Selects a machine to plug into
function RMS_DiagnosticScreen:onClickMachine(list, section, index)
    self.refreshTimer = 0
end

---Plugs the PC into the selected machine, or unplugs it
function RMS_DiagnosticScreen:onClickConnect()
    local action = RMS_DiagnosticTool.ACTION
    if RMS_DiagnosticTool.getTarget(self.tool) ~= nil then
        RMS_DiagnosticRequestEvent.send(self.tool, nil, action.UNPLUG)
        return
    end
    local selected = self.machines[self.machineList.selectedIndex]
    if selected ~= nil and selected.reason == "ok" then
        RMS_DiagnosticRequestEvent.send(self.tool, selected.vehicle, action.PLUG)
        self.page = PAGE.SCAN
        self.refreshTimer = 0
    end
end

---Renews the expired licence of the software, at its yearly price
function RMS_DiagnosticScreen:onClickRenew()
    RMS_DiagnosticRequestEvent.send(self.tool, nil, RMS_DiagnosticTool.ACTION.RENEW)
end

---Starts a scan of the machine the PC is plugged into
function RMS_DiagnosticScreen:onClickScan()
    RMS_DiagnosticRequestEvent.send(self.tool, nil, RMS_DiagnosticTool.ACTION.SCAN)
end

---Shows the connection page
function RMS_DiagnosticScreen:onClickConnectionPage()
    self.page = PAGE.CONNECTION
    self.refreshTimer = 0
end

---Shows the scan page
function RMS_DiagnosticScreen:onClickScanPage()
    self.page = PAGE.SCAN
    self.refreshTimer = 0
end

---Closes the PC
function RMS_DiagnosticScreen:onClickBack()
    self:close()
end

function RMS_DiagnosticScreen:inputEvent(action, value, eventUsed)
    if action == InputAction.MENU_BACK and not eventUsed then
        self:close()
        return true
    end
    return RMS_DiagnosticScreen:superClass().inputEvent(self, action, value, eventUsed)
end

---Wires the lists to the screen
function RMS_DiagnosticScreen:onCreate()
    self.machineList:setDataSource(self)
    self.machineList:setDelegate(self)
    self.codeList:setDataSource(self)
    self.codeList:setDelegate(self)
end

---Fills the screen from the trolley and focuses its first control
function RMS_DiagnosticScreen:onOpen()
    RMS_DiagnosticScreen:superClass().onOpen(self)
    self.machines, self.rows = {}, {}
    self.machinesSignature, self.rowsSignature = nil, nil
    self.controllersTarget, self.focusKey = nil, nil
    self.refreshTimer = REFRESH_MS
    self:refresh()
    FocusManager:setFocus(self.focusEntry)
end

---Blurs the game behind the PC
function RMS_DiagnosticScreen:getBlurArea()
    return 0, 0, 1, 1
end

---Releases the trolley
function RMS_DiagnosticScreen:onClose()
    self.tool = nil
    RMS_DiagnosticScreen:superClass().onClose(self)
end
