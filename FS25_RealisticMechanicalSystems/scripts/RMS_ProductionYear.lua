-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Production year of a store item.
RMS_ProductionYear = {}

RMS_ProductionYear.DEFAULT_YEAR = 2000

RMS_ProductionYear.SCR_MIN_YEAR = 2011

RMS_ProductionYear.SOURCE = { FILE = "file", REFERENCE = "reference", UNKNOWN = "unknown" }

-- English texts of the game's series name keys, params split by "|"
RMS_ProductionYear.SERIES_NAMES = {
    shopItem_seriesX = "%s Series",
    shopItem_seriesXAdd = "%s Series %s",
    shopItem_seriesXUpper = "%s SERIES"
}

local resolved = {}

---Builds the cache key of a store item, its reference key outside dlcs
local function getStoreItemKey(storeItem)
    local prefix = storeItem.customEnvironment ~= nil and storeItem.customEnvironment .. "/" or ""
    return string.lower(prefix .. string.gsub(storeItem.rawXMLFilename, "\\", "/"))
end

---Reads the production year and English shop name of a vehicle xml
local function getDeclaredData(xmlFilename)
    local xmlFile = XMLFile.load("RMS_ProductionYear", xmlFilename)
    local year = tonumber(xmlFile:getString("vehicle.storeData.year"))
    local name = xmlFile:getString("vehicle.storeData.name.en") or xmlFile:getString("vehicle.storeData.name")
    local params = xmlFile:getString("vehicle.storeData.name#params")
    xmlFile:delete()

    local seriesName = name ~= nil and RMS_ProductionYear.SERIES_NAMES[string.match(name, "^%$l10n_(.+)$") or ""] or nil
    if seriesName ~= nil then
        local values = {}
        for value in string.gmatch(params or "", "[^|]+") do
            table.insert(values, value)
        end
        name = string.format(seriesName, unpack(values))
    end
    return year, name
end

---Builds the reference key of a dlc machine from brand and shop name
local function getDlcNameKey(storeItem, name)
    local brand = g_brandManager:getBrandByIndex(storeItem.brandIndex)
    if brand == nil or name == nil or string.find(name, "^%$l10n_") ~= nil then
        return nil
    end

    local brandPart = string.gsub(string.lower(brand.name), "[^%w]", "")
    local namePart = string.gsub(string.lower(name), "[^%w]", "")
    return "pdlc:" .. brandPart .. "|" .. namePart
end

---Returns the production year of a store item, caching the result
-- @param table storeItem store item
-- @return integer year production year
-- @return string source RMS_ProductionYear.SOURCE value
function RMS_ProductionYear.getYear(storeItem)
    local key = getStoreItemKey(storeItem)
    local entry = resolved[key]

    if entry == nil then
        local SOURCE = RMS_ProductionYear.SOURCE
        local declaredYear, name = getDeclaredData(storeItem.xmlFilename)
        entry = { year = declaredYear, source = SOURCE.FILE }
        if entry.year == nil then
            -- any dlc machine is matched by brand and English shop name
            local referenceKey = key
            if string.find(storeItem.baseDir, "pdlc") ~= nil then
                referenceKey = getDlcNameKey(storeItem, name)
            end
            entry.year = referenceKey ~= nil and RMS_ProductionYearData[referenceKey] or nil
            entry.source = SOURCE.REFERENCE
        end
        if entry.year == nil then
            entry.year, entry.source = RMS_ProductionYear.DEFAULT_YEAR, SOURCE.UNKNOWN
        end
        resolved[key] = entry
    end

    return entry.year, entry.source
end

---Returns the production year, raised to the SCR era with AdBlue
-- @param table storeItem store item
-- @param boolean usesDef true when the machine takes AdBlue
-- @return integer year production year
-- @return string source RMS_ProductionYear.SOURCE value
function RMS_ProductionYear.getRaisedYear(storeItem, usesDef)
    local year, source = RMS_ProductionYear.getYear(storeItem)
    if usesDef and year < RMS_ProductionYear.SCR_MIN_YEAR then
        return RMS_ProductionYear.SCR_MIN_YEAR, source
    end

    return year, source
end

---Returns the vehicle year, raised to the SCR era with AdBlue
-- @param table? vehicle vehicle
-- @param table storeItem store item
-- @return integer year production year
-- @return string source RMS_ProductionYear.SOURCE value
function RMS_ProductionYear.getVehicleYear(vehicle, storeItem)
    local motorizedSpec = vehicle ~= nil and vehicle.spec_motorized or nil
    local consumers = motorizedSpec ~= nil and motorizedSpec.consumersByFillTypeName or nil
    return RMS_ProductionYear.getRaisedYear(storeItem, consumers ~= nil and consumers["DEF"] ~= nil)
end
