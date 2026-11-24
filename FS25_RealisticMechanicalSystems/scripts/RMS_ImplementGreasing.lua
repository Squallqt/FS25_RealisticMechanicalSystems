-- Copyright © 2026 Squallqt. All rights reserved.

---Implement greasing, counted on the days the implement worked
RMS_ImplementGreasing = {}

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function RMS_ImplementGreasing.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Attachable, specializations)
        and SpecializationUtil.hasSpecialization(Wearable, specializations)
end

---Registers the saved greasing state
function RMS_ImplementGreasing.initSpecialization()
    Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).rmsImplementGreasing#greasing",
        "Grease points due, hours run and delay per interval")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).rmsImplementGreasing#headerTurnedHour",
        "Hour of play a header last turned")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.BOOL, "vehicles.vehicle(?).rmsImplementGreasing#limiterSeized",
        "Slip clutch of a header seized by standing")
end

---Registers the overwritten functions of the greasing
-- @param table vehicleType vehicle type
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

---Registers the event listeners of the greasing
-- @param table vehicleType vehicle type
function RMS_ImplementGreasing.registerEventListeners(vehicleType)
    for _, name in ipairs({ "onLoad", "onPostLoad", "onReadStream", "onWriteStream", "onReadUpdateStream", "onWriteUpdateStream" }) do
        SpecializationUtil.registerEventListener(vehicleType, name, RMS_ImplementGreasing)
    end
end

---Called on loading
-- @param table? savegame savegame
function RMS_ImplementGreasing:onLoad(savegame)
    self.spec_rmsImplementGreasing.dirtyFlag = self:getNextDirtyFlag()
end

---Called after loading, reading the saved greasing
-- @param table? savegame savegame
function RMS_ImplementGreasing:onPostLoad(savegame)
    RMS_Greasing.initialize(self)
    if self.spec_powerTakeOffs ~= nil and next(self.spec_powerTakeOffs.inputPowerTakeOffs) ~= nil then
        RMS_Greasing.getImplementPtoRating(self)
    end
    if savegame ~= nil then
        local spec, key = self.spec_rmsImplementGreasing, savegame.key .. ".rmsImplementGreasing"
        RMS_Greasing.deserialize(self, savegame.xmlFile:getValue(key .. "#greasing"))
        spec.headerTurnedHour = savegame.xmlFile:getValue(key .. "#headerTurnedHour")
        spec.isLimiterSeized = savegame.xmlFile:getValue(key .. "#limiterSeized", false)
    end
end

---Saves the greasing of an implement that has grease points
-- @param table xmlFile savegame file
-- @param string key key of the specialization
-- @param table usedModNames mods used
function RMS_ImplementGreasing:saveToXMLFile(xmlFile, key, usedModNames)
    if RMS_Greasing.getTiers(self) ~= nil then
        local spec = self.spec_rmsImplementGreasing
        xmlFile:setValue(key .. "#greasing", RMS_Greasing.serialize(self))
        if spec.headerTurnedHour ~= nil then
            xmlFile:setValue(key .. "#headerTurnedHour", spec.headerTurnedHour)
        end
        if spec.isLimiterSeized then
            xmlFile:setValue(key .. "#limiterSeized", true)
        end
    end
end

---Called on client side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_ImplementGreasing:onReadStream(streamId, connection)
    RMS_Greasing.deserialize(self, streamReadString(streamId))
end

---Called on server side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_ImplementGreasing:onWriteStream(streamId, connection)
    streamWriteString(streamId, RMS_Greasing.serialize(self))
end

---Called on client side on update
-- @param integer streamId stream id
-- @param integer timestamp timestamp
-- @param Connection connection connection
function RMS_ImplementGreasing:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        RMS_ImplementGreasing.onReadStream(self, streamId, connection)
    end
end

---Called on server side on update
-- @param integer streamId stream id
-- @param Connection connection connection
-- @param integer dirtyMask dirty mask
function RMS_ImplementGreasing:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer()
        and streamWriteBool(streamId, bit32.band(dirtyMask, self.spec_rmsImplementGreasing.dirtyFlag) ~= 0) then
        RMS_ImplementGreasing.onWriteStream(self, streamId, connection)
    end
end

---Marks the day worked when the implement works, carried idle not
-- @param function superFunc original function
-- @param float operatingTime operating time (ms)
-- @param boolean? isLoading true while loading
function RMS_ImplementGreasing:setOperatingTime(superFunc, operatingTime, isLoading)
    if self.isServer and not isLoading and self.propertyState ~= VehiclePropertyState.MISSION and RMS_Greasing.getIsWorking(self) then
        RMS_Greasing.update(self, operatingTime - self.operatingTime)
    end
    self.spec_rmsImplementGreasing.isFeeding = false
    superFunc(self, operatingTime, isLoading)
end

---Notes a tank emptied by the tool it feeds, a front tank by its drill
-- @param function superFunc original function
-- @param integer farmId farm
-- @param integer fillUnitIndex fill unit
-- @param float fillLevelDelta change of the fill level
-- @param any ... other arguments of the game's function
-- @return float delta change applied
function RMS_ImplementGreasing:addFillUnitFillLevel(superFunc, farmId, fillUnitIndex, fillLevelDelta, ...)
    if fillLevelDelta < 0 then
        self.spec_rmsImplementGreasing.isFeeding = true
    end
    return superFunc(self, farmId, fillUnitIndex, fillLevelDelta, ...)
end

---Wears the implement faster while its greasing is late
-- @param function superFunc original function
-- @param float dt time since the last frame (ms)
-- @return float damage damage of the frame
function RMS_ImplementGreasing:updateDamageAmount(superFunc, dt)
    return superFunc(self, dt) * RMS_Greasing.getWearFactor(self)
end

---Counts each bale a wrapper drops against its intervals in bales
-- @param function superFunc original function
-- @param integer id state change of the wrapper
-- @param integer? nearestBaleServerId bale concerned
function RMS_ImplementGreasing:doStateChange(superFunc, id, nearestBaleServerId)
    superFunc(self, id, nearestBaleServerId)
    if self.isServer and id == BaleWrapper.CHANGE_WRAPPER_BALE_DROPPED then
        RMS_Greasing.onBaleWrapped(self)
    end
end

---Greases every point, as the workshop does with a machine's service
-- @param function superFunc original function
function RMS_ImplementGreasing:repairVehicle(superFunc)
    superFunc(self)
    if self.isServer then
        RMS_Greasing.greaseAll(self)
    end
end
