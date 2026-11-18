-- Copyright © 2026 Squallqt. All rights reserved.

---Fluid containers in the game's object storage, each drum kept
RMS_FluidStorage = {}

local PalletRecord = PlaceableObjectStorage.ABSTRACT_OBJECTS_BY_CLASS_NAME.Vehicle

---Tells whether two stored containers hold the same liters and pumps
local function getIsSameFluid(fluid, otherFluid)
    if fluid == nil or otherFluid == nil then
        return fluid == otherFluid
    end
    if fluid.capacity ~= otherFluid.capacity or #fluid.slots ~= #otherFluid.slots then
        return false
    end
    for index, slot in ipairs(fluid.slots) do
        local other = otherFluid.slots[index]
        if slot.liters ~= other.liters or slot.hasPump ~= other.hasPump then
            return false
        end
    end
    return true
end

---Tells whether a stored pallet came back as a vehicle
local function getIsLoaded(vehicles, vehicleLoadState)
    return vehicleLoadState == VehicleLoadingState.OK and #vehicles > 0
end

PalletRecord.registerXMLPaths = Utils.appendedFunction(PalletRecord.registerXMLPaths, function(schema, basePath)
    schema:register(XMLValueType.FLOAT, basePath .. "#rmsFluidLiters", "Liters left in a stored RMS fluid container")
    schema:register(XMLValueType.FLOAT, basePath .. "#rmsFluidCapacity", "Liters a stored RMS fluid container holds")
    schema:register(XMLValueType.BOOL, basePath .. "#rmsFluidPump", "Whether a pump sits on a stored RMS drum")
    schema:register(XMLValueType.FLOAT, basePath .. "#rmsFluidLiters2", "Liters left in the second drum of a stored RMS pallet")
    schema:register(XMLValueType.BOOL, basePath .. "#rmsFluidPump2", "Whether a pump sits on the second drum of a stored RMS pallet")
end)

PalletRecord.addToStorage = Utils.overwrittenFunction(PalletRecord.addToStorage, function(record, superFunc, storage, object, loadedFromSavegame)
    local fluid = nil
    if object[RMS_FluidContainer.SPEC_TABLE_NAME] ~= nil then
        fluid = { capacity = object:getRMSFluidCapacity(), slots = {} }
        for index = 1, object:getRMSFluidSlotCount() do
            table.insert(fluid.slots, { liters = object:getRMSFluidLiters(index), hasPump = object:getHasRMSFluidPump(index) })
        end
    end
    superFunc(record, storage, object, loadedFromSavegame)
    record.palletAttributes.rmsFluid = fluid
end)

PalletRecord.palletVehicleLoaded = Utils.prependedFunction(PalletRecord.palletVehicleLoaded, function(record, vehicles, vehicleLoadState)
    local fluid = record.palletAttributes.rmsFluid
    if fluid ~= nil and getIsLoaded(vehicles, vehicleLoadState) then
        vehicles[1]:setRMSFluidStored(fluid.slots)
    end
end)

PalletRecord.visualPalletVehicleLoaded = Utils.prependedFunction(PalletRecord.visualPalletVehicleLoaded, function(record, vehicles, vehicleLoadState)
    local fluid = record.palletAttributes.rmsFluid
    if fluid ~= nil and getIsLoaded(vehicles, vehicleLoadState) then
        vehicles[1]:setRMSFluidStored(fluid.slots)
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

    local levels, hasPump = {}, false
    for _, slot in ipairs(fluid.slots) do
        table.insert(levels, string.format("%s / %s %s", RMS_FluidWorkshop.formatLiters(slot.liters),
            RMS_FluidWorkshop.formatLiters(fluid.capacity), g_i18n:getText("unit_literShort")))
        hasPump = hasPump or slot.hasPump
    end
    local text = string.format("%s (%s)", g_storeManager:getItemByXMLFilename(record.palletAttributes.configFileName).name,
        table.concat(levels, ", "))
    if hasPump then
        text = text .. " + " .. g_i18n:getText("rms_drum_pump_name")
    end
    return text
end)

PalletRecord.writeStream = Utils.appendedFunction(PalletRecord.writeStream, function(record, streamId)
    local fluid = record.palletAttributes.rmsFluid
    if streamWriteBool(streamId, fluid ~= nil) then
        streamWriteFloat32(streamId, fluid.capacity)
        streamWriteUInt8(streamId, #fluid.slots)
        for _, slot in ipairs(fluid.slots) do
            streamWriteFloat32(streamId, slot.liters)
            streamWriteBool(streamId, slot.hasPump)
        end
        streamWriteUInt16(streamId, record.palletAttributes.configurations.fillUnit - 1)
    end
end)

PalletRecord.readStream = Utils.overwrittenFunction(PalletRecord.readStream, function(streamId, superFunc, connection)
    local record = superFunc(streamId, connection)
    if streamReadBool(streamId) then
        local attributes = record.palletAttributes
        local fluid = { capacity = streamReadFloat32(streamId), slots = {} }
        for _ = 1, streamReadUInt8(streamId) do
            table.insert(fluid.slots, { liters = streamReadFloat32(streamId), hasPump = streamReadBool(streamId) })
        end
        attributes.rmsFluid = fluid
        attributes.configurations = { fillUnit = streamReadUInt16(streamId) + 1 }
    end
    return record
end)

PalletRecord.saveToXMLFile = Utils.appendedFunction(PalletRecord.saveToXMLFile, function(record, storage, xmlFile, key)
    local fluid = record.palletAttributes.rmsFluid
    if fluid ~= nil then
        xmlFile:setValue(key .. "#rmsFluidCapacity", fluid.capacity)
        xmlFile:setValue(key .. "#rmsFluidLiters", fluid.slots[1].liters)
        xmlFile:setValue(key .. "#rmsFluidPump", fluid.slots[1].hasPump)
        if fluid.slots[2] ~= nil then
            xmlFile:setValue(key .. "#rmsFluidLiters2", fluid.slots[2].liters)
            xmlFile:setValue(key .. "#rmsFluidPump2", fluid.slots[2].hasPump)
        end
    end
end)

PalletRecord.loadFromXMLFile = Utils.overwrittenFunction(PalletRecord.loadFromXMLFile, function(storage, superFunc, xmlFile, key)
    local storedObjects = storage.spec_objectStorage.storedObjects
    local numStored = #storedObjects
    superFunc(storage, xmlFile, key)

    local liters = xmlFile:getValue(key .. "#rmsFluidLiters")
    if liters ~= nil and #storedObjects > numStored then
        local fluid = { capacity = xmlFile:getValue(key .. "#rmsFluidCapacity"),
            slots = { { liters = liters, hasPump = xmlFile:getValue(key .. "#rmsFluidPump", false) } } }
        local liters2 = xmlFile:getValue(key .. "#rmsFluidLiters2")
        if liters2 ~= nil then
            table.insert(fluid.slots, { liters = liters2, hasPump = xmlFile:getValue(key .. "#rmsFluidPump2", false) })
        end
        storedObjects[#storedObjects].palletAttributes.rmsFluid = fluid
    end
end)
