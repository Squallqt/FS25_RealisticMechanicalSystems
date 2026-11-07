-- Copyright © 2026 Squallqt. All rights reserved.

---Trolley construction with the diagnostic PC option
RMS_TrolleyPlaceable = {}

local CONFIGURATIONS_KEY = "placeable.rmsDiagnosticTool.rmsDiagnosticPcConfigurations"

function RMS_TrolleyPlaceable.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PlaceableVehicle, specializations)
end

function RMS_TrolleyPlaceable.initSpecialization()
    if g_iconGenerator == nil then
        g_placeableConfigurationManager:addConfigurationType(RMS_DiagnosticTool.CONFIGURATION,
            g_i18n:getText("rms_diagnostic_configuration"), "rmsDiagnosticTool", PlaceableConfigurationItem)
    end
    PlaceableConfigurationItem.registerXMLPaths(Placeable.xmlSchema, CONFIGURATIONS_KEY,
        CONFIGURATIONS_KEY .. ".rmsDiagnosticPcConfiguration(?)")
end

---Applies a construction's PC option to the trolley it loads
function RMS_TrolleyPlaceable.applyPcOption(data, callback, target)
    if type(target) == "table" and target.isa ~= nil and target:isa(Placeable) and target.configurations ~= nil then
        local option = target.configurations[RMS_DiagnosticTool.CONFIGURATION]
        if option ~= nil then
            data:setConfigurations({ [RMS_DiagnosticTool.CONFIGURATION] = option })
        end
    end
end

---Prices the trolley being placed with its PC option, as it is charged
function RMS_TrolleyPlaceable.getBrushPrice(brush, superFunc)
    if brush.configurations ~= nil and brush.configurations[RMS_DiagnosticTool.CONFIGURATION] ~= nil then
        return g_currentMission.economyManager:getBuyPrice(brush.storeItem, brush.configurations, nil) + brush:getDisplacementCost()
    end
    return superFunc(brush)
end

VehicleLoadingData.load = Utils.prependedFunction(VehicleLoadingData.load, RMS_TrolleyPlaceable.applyPcOption)
ConstructionBrushPlaceable.getPrice = Utils.overwrittenFunction(ConstructionBrushPlaceable.getPrice, RMS_TrolleyPlaceable.getBrushPrice)
