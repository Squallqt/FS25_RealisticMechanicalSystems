-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle production-year lookup.
RMS_VehicleYears = {}

RMS_VehicleYears.DEFAULT_YEAR = 2000

RMS_VehicleYears.SCR_MIN_YEAR = 2011

local resolvedYears = {}
local knownYears = {}

---Builds the lookup key of a store item
local function getStoreItemKey(storeItem)
    local prefix = ""

    if storeItem.customEnvironment ~= nil and string.find(storeItem.baseDir, "pdlc") == nil then
        prefix = storeItem.customEnvironment .. "/"
    end

    return string.lower(prefix .. string.gsub(storeItem.rawXMLFilename, "\\", "/"))
end

---Reads the production year declared in a vehicle xml
local function getDeclaredYear(xmlFilename)
    local xmlFile = XMLFile.load("RMS_VehicleYear", xmlFilename)
    local year = tonumber(xmlFile:getString("vehicle.storeData.year"))
    xmlFile:delete()

    return year
end

---Returns the production year of a store item, caching the result
-- @param table storeItem store item
-- @return integer year production year
-- @return boolean isKnown true when XML or the generated table supplies the year
function RMS_VehicleYears.getYear(storeItem)
    local key = getStoreItemKey(storeItem)
    local year = resolvedYears[key]

    if year == nil then
        year = getDeclaredYear(storeItem.xmlFilename) or RMS_VehicleYearsData[key]
        knownYears[key] = year ~= nil
        year = year or RMS_VehicleYears.DEFAULT_YEAR
        resolvedYears[key] = year
    end

    return year, knownYears[key]
end

---Returns the production year of a vehicle, raised to the SCR era with AdBlue
-- @param table? vehicle vehicle
-- @param table storeItem store item
-- @return integer year production year
-- @return boolean isKnown year supplied by XML or lookup table
function RMS_VehicleYears.getVehicleYear(vehicle, storeItem)
    local year, isKnown = RMS_VehicleYears.getYear(storeItem)
    if year >= RMS_VehicleYears.SCR_MIN_YEAR then
        return year, isKnown
    end

    local motorizedSpec = vehicle ~= nil and vehicle.spec_motorized or nil
    local consumers = motorizedSpec ~= nil and motorizedSpec.consumersByFillTypeName or nil
    if consumers == nil or consumers["DEF"] == nil then
        return year, isKnown
    end

    return RMS_VehicleYears.SCR_MIN_YEAR, isKnown
end
