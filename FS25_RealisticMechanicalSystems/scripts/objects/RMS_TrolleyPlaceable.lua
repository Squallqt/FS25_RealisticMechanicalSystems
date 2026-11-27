-- Copyright © 2026 Squallqt. All rights reserved.

---Trolley construction with the diagnostic PC option
RMS_TrolleyPlaceable = {}

local CONFIGURATIONS_KEY = "placeable.rmsDiagnosticTool.rmsDiagnosticPcConfigurations"

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function RMS_TrolleyPlaceable.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PlaceableVehicle, specializations)
end

---Registers the PC option and its XML paths
function RMS_TrolleyPlaceable.initSpecialization()
    if g_iconGenerator == nil then
        g_placeableConfigurationManager:addConfigurationType(RMS_DiagnosticTool.CONFIGURATION,
            g_i18n:getText("rms_diagnostic_configuration"), "rmsDiagnosticTool", PlaceableConfigurationItem)
    end
    PlaceableConfigurationItem.registerXMLPaths(Placeable.xmlSchema, CONFIGURATIONS_KEY,
        CONFIGURATIONS_KEY .. ".rmsDiagnosticPcConfiguration(?)")
end

---Applies a construction's PC option to the trolley it loads
-- @param table data vehicle loading data
-- @param function callback callback of the loading
-- @param table? target target of the callback, the construction for a trolley
function RMS_TrolleyPlaceable.applyPcOption(data, callback, target)
    if type(target) == "table" and target.isa ~= nil and target:isa(Placeable) then
        local option = target.configurations[RMS_DiagnosticTool.CONFIGURATION]
        if option ~= nil then
            data:setConfigurations({ [RMS_DiagnosticTool.CONFIGURATION] = option })
        end
    end
end

---Prices the trolley being placed with its PC option, as it is charged
-- @param table brush construction brush
-- @param function superFunc original function
-- @return float price price of the construction
function RMS_TrolleyPlaceable.getBrushPrice(brush, superFunc)
    if brush.configurations ~= nil and brush.configurations[RMS_DiagnosticTool.CONFIGURATION] ~= nil then
        return g_currentMission.economyManager:getBuyPrice(brush.storeItem, brush.configurations, nil) + brush:getDisplacementCost()
    end
    return superFunc(brush)
end

VehicleLoadingData.load = Utils.prependedFunction(VehicleLoadingData.load, RMS_TrolleyPlaceable.applyPcOption)
ConstructionBrushPlaceable.getPrice = Utils.overwrittenFunction(ConstructionBrushPlaceable.getPrice, RMS_TrolleyPlaceable.getBrushPrice)
