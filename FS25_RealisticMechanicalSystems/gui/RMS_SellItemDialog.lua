-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Return of a leased machine, asked as the sell dialog of the game
RMS_SellItemDialog = {}

local RMS_SellItemDialog_mt = Class(RMS_SellItemDialog, YesNoDialog)

---Writes an amount with its sign, none at zero
local function formatSignedMoney(amount)
    local sign = amount > 0 and "+" or amount < 0 and "-" or ""
    return sign .. g_i18n:formatMoney(math.abs(amount), 0, true, false)
end

---Colours a credit green, a charge red, nothing grey
local function setAmountColor(element, amount)
    local COLOR = RMS_Utils.COLOR
    element:setTextColor(unpack(amount > 0 and COLOR.HIGHLIGHT or amount < 0 and COLOR.ALERT or COLOR.TEXT_DIM))
end

---Creates the dialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog dialog
function RMS_SellItemDialog.new(target, customMt)
    local self = YesNoDialog.new(target, customMt or RMS_SellItemDialog_mt)
    self.costRows = {}
    return self
end

---Wires the list of the costs
function RMS_SellItemDialog:onCreate()
    RMS_SellItemDialog:superClass().onCreate(self)
    self.costList:setDataSource(self)
    self.costList:setDelegate(self)
end

---Asks to confirm the return, as SellItemDialog.show asks a sale
-- @param table vehicle leased machine
-- @param function callback called with the target, the answer and the argument
-- @param table? target callback target
-- @param any? args argument of the callback
function RMS_SellItemDialog.show(vehicle, callback, target, args)
    local self = RMS_SellItemDialog.INSTANCE
    self:setVehicle(vehicle)
    self:setCallback(callback, target, args)
    g_gui:showDialog("RMS_SellItemDialog")
end

---Writes the machine and the cost of its return, line by line
-- @param table vehicle leased machine
function RMS_SellItemDialog:setVehicle(vehicle)
    self.vehicleImageElement:setImageFilename(vehicle:getImageFilename())
    self.vehicleNameElement:setText(vehicle:getFullName())
    -- the title and the name share the width of the longer one
    self.headerTextLayout:setSize(math.max(self.dialogTitleElement.size[1], self.vehicleNameElement.size[1]), nil)
    self.headerTextLayout:invalidateLayout()
    self.headerLayout:invalidateLayout()

    local breakdown = RMS_Leasing.getReturnBreakdown(vehicle)
    self.costRows = {}
    for _, row in ipairs(breakdown.rows) do
        table.insert(self.costRows, { label = g_i18n:getText(row.label), amount = MathUtil.round(row.value) })
    end
    local total = MathUtil.round(breakdown.display.total)
    RMS_Utils.fitValuePill(self.totalAmountPill, self.totalAmountElement, nil, formatSignedMoney(total))
    setAmountColor(self.totalAmountElement, total)
    self.costList:reloadData()
end

---Number of cost lines
function RMS_SellItemDialog:getNumberOfItemsInSection()
    return #self.costRows
end

---Writes a cost line, its amount coloured
function RMS_SellItemDialog:populateCellForItemInSection(_list, _section, index, cell)
    local row = self.costRows[index]
    local value = cell:getAttribute("costValue")
    RMS_Utils.fitRowValue(cell:getAttribute("costLabel"), cell:getAttribute("costValuePill"), value, row.label, formatSignedMoney(row.amount))
    setAmountColor(value, row.amount)
end
