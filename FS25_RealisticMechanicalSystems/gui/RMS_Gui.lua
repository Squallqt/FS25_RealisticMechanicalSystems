-- Copyright © 2026 Squallqt. All rights reserved.

---Profiles, atlases, frames and screens of the mod, in loading order
RMS_Gui = {}

local modDirectory = g_currentModDirectory

RMS_Gui.ATLASES = {
    { "rms_MenuIcon", "images/menuIcon.xml" },
    { "rms_WorkshopFluids", "gui/rms_workshopFluids.xml" },
    { "rms_LevelGauge", "gui/rms_levelGauge.xml" },
    { "rms_Diagnostic", "gui/rms_diagnostic.xml" },
    { "rms_DiagnosticPc", "gui/rms_diagnosticPc.xml" },
    { "rms_Hud", "hud/rms_hud.xml" },
    { "rms_HudGlass", "hud/rms_hudGlass.xml" },
    { "rms_LampGlow", "hud/rms_lampGlow.xml" },
    { "rms_ProgressRing", "hud/rms_progressRing.xml" },
    { "rms_ChartLine", "gui/rms_chartLine.xml" }
}

-- a frame loads before anything that references it
RMS_Gui.FRAMES = {
    { RMS_ConditionCardFrame, "gui/RMS_ConditionCardFrame.xml" },
    { RMS_WorkshopStatusFrame, "gui/RMS_WorkshopStatusFrame.xml" },
    { RMS_ReportFrame, "gui/RMS_ReportFrame.xml" },
    { RMS_WorkshopSummaryFrame, "gui/RMS_WorkshopSummaryFrame.xml" },
    { RMS_WorkshopDiagnosticFrame, "gui/RMS_WorkshopDiagnosticFrame.xml" },
    { RMS_WorkshopInterventionsFrame, "gui/RMS_WorkshopInterventionsFrame.xml" },
    { RMS_WorkshopRecordFrame, "gui/RMS_WorkshopRecordFrame.xml" }
}

RMS_Gui.DIALOGS = {
    { RMS_WorkshopDialog, "gui/RMS_WorkshopDialog.xml" },
    { RMS_InspectionDialog, "gui/RMS_InspectionDialog.xml" },
    { RMS_SellItemDialog, "gui/RMS_SellItemDialog.xml" },
    { RMS_DiagnosticScreen, "gui/RMS_DiagnosticScreen.xml" },
    { RMS_DebugScreen, "gui/RMS_DebugScreen.xml" }
}

---Returns the file name of a layout, without its folder and extension
-- @param string path path of the layout
-- @return string name file name
local function getName(path)
    return path:match("([%w_]+)%.xml$")
end

---Loads the profiles and the atlases
function RMS_Gui.loadResources()
    g_gui:loadProfiles(modDirectory .. "gui/guiProfiles.xml")
    for _, atlas in ipairs(RMS_Gui.ATLASES) do
        g_overlayManager:addTextureConfigFile(modDirectory .. atlas[2], atlas[1])
    end
end

---Loads the frames, before the fleet page places one in the shop menu
function RMS_Gui.loadFrames()
    for _, entry in ipairs(RMS_Gui.FRAMES) do
        g_gui:loadGui(modDirectory .. entry[2], getName(entry[2]), entry[1].new(), true)
    end
end

---Loads the dialogs, then the strokes they draw
function RMS_Gui.loadScreens()
    for _, entry in ipairs(RMS_Gui.DIALOGS) do
        local dialog = entry[1].new()
        g_gui:loadGui(modDirectory .. entry[2], getName(entry[2]), dialog)
        entry[1].INSTANCE = dialog
    end
    RMS_ProgressRing.createOverlays()
    RMS_Chart.createOverlays()
end

---Deletes the dialogs and the strokes they draw
function RMS_Gui.deleteScreens()
    for _, entry in ipairs(RMS_Gui.DIALOGS) do
        local class, name = entry[1], getName(entry[2])
        -- its own instance, not the one of the game's dialog it extends
        local dialog = rawget(class, "INSTANCE")
        if dialog ~= nil then
            g_gui.guis[name]:delete()
            dialog:delete()
            g_gui.guis[name], g_gui.nameScreenTypes[name] = nil, nil
            g_gui.screens[class], g_gui.screenControllers[class] = nil, nil
            class.INSTANCE = nil
        end
    end
    RMS_ProgressRing.deleteOverlays()
    RMS_Chart.deleteOverlays()
end
