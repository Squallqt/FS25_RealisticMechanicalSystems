-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Grease cartridges bought by the unit, a carton holding two and more
RMS_GreaseCartridge = {}
RMS_GreaseCartridge.SPEC_NAME = "FS25_RealisticMechanicalSystems.rmsGreaseCartridge"
RMS_GreaseCartridge.SPEC_TABLE_NAME = "spec_" .. RMS_GreaseCartridge.SPEC_NAME
RMS_GreaseCartridge.COUNT_BITS = 8

function RMS_GreaseCartridge.prerequisitesPresent(specializations)
    return true
end

function RMS_GreaseCartridge.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("RMSGreaseCartridge")
    schema:register(XMLValueType.NODE_INDEX, "vehicle.rmsGreaseCartridge.cartridge(?)#node", "Cartridge of the carton shown while it is left")
    schema:setXMLSpecializationType()

    Vehicle.xmlSchemaSavegame:register(XMLValueType.INT,
        "vehicles.vehicle(?)." .. RMS_GreaseCartridge.SPEC_NAME .. "#count", "Cartridges left")
end

function RMS_GreaseCartridge.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getRMSGreaseCartridgeCount", RMS_GreaseCartridge.getRMSGreaseCartridgeCount)
    SpecializationUtil.registerFunction(vehicleType, "takeRMSGreaseCartridge", RMS_GreaseCartridge.takeRMSGreaseCartridge)
end

function RMS_GreaseCartridge.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", RMS_GreaseCartridge.showInfo)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMeshNodes", RMS_GreaseCartridge.getMeshNodes)
end

function RMS_GreaseCartridge.registerEventListeners(vehicleType)
    for _, name in ipairs({ "onLoad", "saveToXMLFile", "onReadStream", "onWriteStream", "onReadUpdateStream", "onWriteUpdateStream" }) do
        SpecializationUtil.registerEventListener(vehicleType, name, RMS_GreaseCartridge)
    end
end

local function applyCount(cartridge)
    local spec = cartridge[RMS_GreaseCartridge.SPEC_TABLE_NAME]
    for index, node in ipairs(spec.cartridgeNodes) do
        setVisibility(node, index <= spec.count)
    end
end

function RMS_GreaseCartridge:onLoad(savegame)
    local spec = self[RMS_GreaseCartridge.SPEC_TABLE_NAME]
    -- the n-th quantity of the shop is n cartridges
    spec.count = self.configurations.design
    if savegame ~= nil then
        spec.count = savegame.xmlFile:getValue(savegame.key .. "." .. RMS_GreaseCartridge.SPEC_NAME .. "#count", spec.count)
    end
    spec.cartridgeNodes = {}
    for _, key in self.xmlFile:iterator("vehicle.rmsGreaseCartridge.cartridge") do
        local node = self.xmlFile:getValue(key .. "#node", nil, self.components, self.i3dMappings)
        table.insert(spec.cartridgeNodes, node)
    end
    spec.dirtyFlag = self:getNextDirtyFlag()
    applyCount(self)
end

function RMS_GreaseCartridge:saveToXMLFile(xmlFile, key, usedModNames)
    xmlFile:setValue(key .. "#count", self[RMS_GreaseCartridge.SPEC_TABLE_NAME].count)
end

function RMS_GreaseCartridge:onWriteStream(streamId, connection)
    streamWriteUIntN(streamId, self[RMS_GreaseCartridge.SPEC_TABLE_NAME].count, RMS_GreaseCartridge.COUNT_BITS)
end

function RMS_GreaseCartridge:onReadStream(streamId, connection)
    self[RMS_GreaseCartridge.SPEC_TABLE_NAME].count = streamReadUIntN(streamId, RMS_GreaseCartridge.COUNT_BITS)
    applyCount(self)
end

function RMS_GreaseCartridge:onWriteUpdateStream(streamId, connection, dirtyMask)
    local spec = self[RMS_GreaseCartridge.SPEC_TABLE_NAME]
    if not connection:getIsServer() and streamWriteBool(streamId, bit32.band(dirtyMask, spec.dirtyFlag) ~= 0) then
        streamWriteUIntN(streamId, spec.count, RMS_GreaseCartridge.COUNT_BITS)
    end
end

function RMS_GreaseCartridge:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        self[RMS_GreaseCartridge.SPEC_TABLE_NAME].count = streamReadUIntN(streamId, RMS_GreaseCartridge.COUNT_BITS)
        applyCount(self)
    end
end

function RMS_GreaseCartridge:getRMSGreaseCartridgeCount()
    return self[RMS_GreaseCartridge.SPEC_TABLE_NAME].count
end

---Takes one cartridge out on the server, an empty object leaves
function RMS_GreaseCartridge:takeRMSGreaseCartridge()
    local spec = self[RMS_GreaseCartridge.SPEC_TABLE_NAME]
    spec.count = spec.count - 1
    if spec.count <= 0 then
        self:delete()
    else
        applyCount(self)
        self:raiseDirtyFlags(spec.dirtyFlag)
    end
end

---Gives the straps the body bought: one cartridge or its carton
function RMS_GreaseCartridge:getMeshNodes(superFunc)
    local mapping = self.configurations.design == 1 and "singleCartridgeBody" or "cartonBody"
    return { self.i3dMappings[mapping].nodeId }
end

function RMS_GreaseCartridge:showInfo(superFunc, box)
    superFunc(self, box)
    box:addLine(g_i18n:getText("rms_grease_cartridge_count"), tostring(self:getRMSGreaseCartridgeCount()))
end
