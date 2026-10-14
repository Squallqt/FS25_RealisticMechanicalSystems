-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Fluid containers in the game's object storage: liters, pump and format kept
RMS_FluidStorage = {}

-- record the game keeps of a stored pallet
local PalletRecord = PlaceableObjectStorage.ABSTRACT_OBJECTS_BY_CLASS_NAME.Vehicle

---Tells whether two records hold the same fluid
local function getIsSameFluid(fluid, otherFluid)
    if fluid == nil or otherFluid == nil then
        return fluid == otherFluid
    end
    return fluid.capacity == otherFluid.capacity and fluid.liters == otherFluid.liters and fluid.hasPump == otherFluid.hasPump
end

---Tells whether the game loaded the vehicle a record asked for
local function getIsLoaded(vehicles, vehicleLoadState)
    return vehicleLoadState == VehicleLoadingState.OK and #vehicles > 0
end

PalletRecord.registerXMLPaths = Utils.appendedFunction(PalletRecord.registerXMLPaths, function(schema, basePath)
    schema:register(XMLValueType.FLOAT, basePath .. "#rmsFluidLiters", "Liters left in a stored RMS fluid container")
    schema:register(XMLValueType.FLOAT, basePath .. "#rmsFluidCapacity", "Liters a stored RMS fluid container holds")
    schema:register(XMLValueType.BOOL, basePath .. "#rmsFluidPump", "Whether a pump sits on a stored RMS drum")
end)

PalletRecord.addToStorage = Utils.overwrittenFunction(PalletRecord.addToStorage, function(record, superFunc, storage, object, loadedFromSavegame)
    -- read before the game deletes the container
    local spec = object[RMS_FluidContainer.SPEC_TABLE_NAME]
    local fluid = spec ~= nil and { liters = spec.liters, capacity = spec.capacity, hasPump = spec.hasPump } or nil
    superFunc(record, storage, object, loadedFromSavegame)
    record.palletAttributes.rmsFluid = fluid
end)

PalletRecord.palletVehicleLoaded = Utils.prependedFunction(PalletRecord.palletVehicleLoaded, function(record, vehicles, vehicleLoadState)
    local fluid = record.palletAttributes.rmsFluid
    if fluid ~= nil and getIsLoaded(vehicles, vehicleLoadState) then
        vehicles[1]:setRMSFluidStored(fluid.liters, fluid.hasPump)
    end
end)

PalletRecord.visualPalletVehicleLoaded = Utils.prependedFunction(PalletRecord.visualPalletVehicleLoaded, function(record, vehicles, vehicleLoadState)
    local fluid = record.palletAttributes.rmsFluid
    if fluid ~= nil and fluid.hasPump and getIsLoaded(vehicles, vehicleLoadState) then
        vehicles[1]:setRMSFluidPump(true)
    end
end)

PalletRecord.getIsIdentical = Utils.overwrittenFunction(PalletRecord.getIsIdentical, function(record, superFunc, otherRecord)
    return superFunc(record, otherRecord) and getIsSameFluid(record.palletAttributes.rmsFluid, otherRecord.palletAttributes.rmsFluid)
end)

PalletRecord.getDialogText = Utils.overwrittenFunction(PalletRecord.getDialogText, function(record, superFunc)
    local fluid = record.palletAttributes.rmsFluid
    if fluid == nil then
        return superFunc(record)
    end

    local text = string.format("%s (%s / %s %s)", g_storeManager:getItemByXMLFilename(record.palletAttributes.configFileName).name,
        RMS_FluidWorkshop.formatLiters(fluid.liters), RMS_FluidWorkshop.formatLiters(fluid.capacity), g_i18n:getText("unit_literShort"))
    if fluid.hasPump then
        text = text .. " + " .. g_i18n:getText("rms_drum_pump_name")
    end
    return text
end)

PalletRecord.writeStream = Utils.appendedFunction(PalletRecord.writeStream, function(record, streamId)
    local fluid = record.palletAttributes.rmsFluid
    if streamWriteBool(streamId, fluid ~= nil) then
        streamWriteFloat32(streamId, fluid.liters)
        streamWriteFloat32(streamId, fluid.capacity)
        streamWriteBool(streamId, fluid.hasPump)
        -- a configuration id as the game sends one
        streamWriteUInt16(streamId, record.palletAttributes.configurations.fillUnit - 1)
    end
end)

PalletRecord.readStream = Utils.overwrittenFunction(PalletRecord.readStream, function(streamId, superFunc, connection)
    local record = superFunc(streamId, connection)
    if streamReadBool(streamId) then
        local attributes = record.palletAttributes
        attributes.rmsFluid = { liters = streamReadFloat32(streamId), capacity = streamReadFloat32(streamId), hasPump = streamReadBool(streamId) }
        attributes.configurations = { fillUnit = streamReadUInt16(streamId) + 1 }
    end
    return record
end)

PalletRecord.saveToXMLFile = Utils.appendedFunction(PalletRecord.saveToXMLFile, function(record, storage, xmlFile, key)
    local fluid = record.palletAttributes.rmsFluid
    if fluid ~= nil then
        xmlFile:setValue(key .. "#rmsFluidLiters", fluid.liters)
        xmlFile:setValue(key .. "#rmsFluidCapacity", fluid.capacity)
        xmlFile:setValue(key .. "#rmsFluidPump", fluid.hasPump)
    end
end)

PalletRecord.loadFromXMLFile = Utils.overwrittenFunction(PalletRecord.loadFromXMLFile, function(storage, superFunc, xmlFile, key)
    local storedObjects = storage.spec_objectStorage.storedObjects
    local numStored = #storedObjects
    superFunc(storage, xmlFile, key)

    -- the game stores nothing when the file of the pallet is gone
    local liters = xmlFile:getValue(key .. "#rmsFluidLiters")
    if liters ~= nil and #storedObjects > numStored then
        storedObjects[#storedObjects].palletAttributes.rmsFluid = { liters = liters, capacity = xmlFile:getValue(key .. "#rmsFluidCapacity"),
            hasPump = xmlFile:getValue(key .. "#rmsFluidPump", false) }
    end
end)
