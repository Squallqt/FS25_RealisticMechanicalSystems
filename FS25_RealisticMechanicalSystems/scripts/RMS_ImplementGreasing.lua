-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Implement greasing, counted on the days the implement worked
RMS_ImplementGreasing = {}

function RMS_ImplementGreasing.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Attachable, specializations)
        and SpecializationUtil.hasSpecialization(Wearable, specializations)
end

function RMS_ImplementGreasing.initSpecialization()
    Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).rmsImplementGreasing#greasing",
        "Grease points due, hours run and delay per interval")
end

function RMS_ImplementGreasing.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setOperatingTime", RMS_ImplementGreasing.setOperatingTime)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateDamageAmount", RMS_ImplementGreasing.updateDamageAmount)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "repairVehicle", RMS_ImplementGreasing.repairVehicle)
    if SpecializationUtil.hasSpecialization(BaleWrapper, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "doStateChange", RMS_ImplementGreasing.doStateChange)
    end
    if SpecializationUtil.hasSpecialization(FillUnit, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "addFillUnitFillLevel", RMS_ImplementGreasing.addFillUnitFillLevel)
    end
end

function RMS_ImplementGreasing.registerEventListeners(vehicleType)
    for _, name in ipairs({ "onLoad", "onPostLoad", "onReadStream", "onWriteStream", "onReadUpdateStream", "onWriteUpdateStream" }) do
        SpecializationUtil.registerEventListener(vehicleType, name, RMS_ImplementGreasing)
    end
end

function RMS_ImplementGreasing:onLoad(savegame)
    self.spec_rmsImplementGreasing.dirtyFlag = self:getNextDirtyFlag()
end

function RMS_ImplementGreasing:onPostLoad(savegame)
    RMS_Greasing.initialize(self)
    if savegame ~= nil then
        RMS_Greasing.deserialize(self, savegame.xmlFile:getValue(savegame.key .. ".rmsImplementGreasing#greasing"))
    end
end

function RMS_ImplementGreasing:saveToXMLFile(xmlFile, key, usedModNames)
    if RMS_Greasing.getTiers(self) ~= nil then
        xmlFile:setValue(key .. "#greasing", RMS_Greasing.serialize(self))
    end
end

function RMS_ImplementGreasing:onReadStream(streamId, connection)
    RMS_Greasing.deserialize(self, streamReadString(streamId))
end

function RMS_ImplementGreasing:onWriteStream(streamId, connection)
    streamWriteString(streamId, RMS_Greasing.serialize(self))
end

function RMS_ImplementGreasing:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        RMS_ImplementGreasing.onReadStream(self, streamId, connection)
    end
end

function RMS_ImplementGreasing:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer()
        and streamWriteBool(streamId, bit32.band(dirtyMask, self.spec_rmsImplementGreasing.dirtyFlag) ~= 0) then
        RMS_ImplementGreasing.onWriteStream(self, streamId, connection)
    end
end

---Returns true while the implement itself works, carried idle not
local function getIsWorking(self)
    if self:doCheckSpeedLimit() or self.spec_rmsImplementGreasing.isFeeding
        or self.getIsTurnedOn ~= nil and self:getIsTurnedOn()
        or self.getDoConsumePtoPower ~= nil and self:getDoConsumePtoPower()
        or self.spec_leveler ~= nil and self.spec_leveler.lastFillLevelMoved > 0 then
        return true
    end
    for _, tool in ipairs(self.spec_cylindered ~= nil and self.spec_cylindered.movingTools or {}) do
        -- lastAnimSpeed only on animated tools
        if tool.lastRotSpeed ~= 0 or tool.lastTransSpeed ~= 0 or (tool.lastAnimSpeed or 0) ~= 0 then
            return true
        end
    end
    return false
end

---Marks the day worked when the implement works, carried idle not
function RMS_ImplementGreasing:setOperatingTime(superFunc, operatingTime, isLoading)
    if self.isServer and not isLoading and self.propertyState ~= VehiclePropertyState.MISSION and getIsWorking(self) then
        RMS_Greasing.update(self, operatingTime - self.operatingTime)
    end
    self.spec_rmsImplementGreasing.isFeeding = false
    superFunc(self, operatingTime, isLoading)
end

---Notes a tank emptied by the tool it feeds, a front tank by its drill
function RMS_ImplementGreasing:addFillUnitFillLevel(superFunc, farmId, fillUnitIndex, fillLevelDelta, ...)
    if fillLevelDelta < 0 then
        self.spec_rmsImplementGreasing.isFeeding = true
    end
    return superFunc(self, farmId, fillUnitIndex, fillLevelDelta, ...)
end

---Wears the implement faster while its greasing is late
function RMS_ImplementGreasing:updateDamageAmount(superFunc, dt)
    return superFunc(self, dt) * RMS_Greasing.getWearFactor(self)
end

---Counts each bale a wrapper drops against its intervals in bales
function RMS_ImplementGreasing:doStateChange(superFunc, id, nearestBaleServerId)
    superFunc(self, id, nearestBaleServerId)
    if self.isServer and id == BaleWrapper.CHANGE_WRAPPER_BALE_DROPPED then
        RMS_Greasing.onBaleWrapped(self)
    end
end

---Greases every point, as the workshop does with a machine's service
function RMS_ImplementGreasing:repairVehicle(superFunc)
    superFunc(self)
    if self.isServer then
        RMS_Greasing.greaseAll(self)
    end
end
