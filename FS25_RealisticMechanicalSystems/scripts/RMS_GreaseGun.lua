-- Copyright © 2026 Squallqt. All rights reserved.

---Grease gun emptying a cartridge, one grease point per stroke
RMS_GreaseGun = {}

local modName = g_currentModName
local specName = "spec_" .. modName .. ".rmsGreaseGun"
local modDirectory = g_currentModDirectory

RMS_GreaseGun.TARGET_REFRESH_INTERVAL = 200
RMS_GreaseGun.WARNING_DURATION = 2200
RMS_GreaseGun.BRAND = "SKF"
RMS_GreaseGun.LOAD_ANGLE = math.rad(45)
RMS_GreaseGun.HUD_WIDTH = 560
RMS_GreaseGun.HUD_GUN_HEIGHT = 80
RMS_GreaseGun.HUD_MACHINE_HEIGHT = 172

source(modDirectory .. "events/RMS_GreaseGunEvent.lua")

---Returns the grease one point takes, in ml
-- @return float ml grease of a point (ml)
function RMS_GreaseGun.getPointMl()
    local C = RMS_Config.GREASING
    return C.STROKE_ML * C.STROKES_PER_POINT
end

---Tells whether a node belongs to a machine with greasing
-- @param entityId node node
-- @return boolean isMachine true for a machine with greasing
local function getIsMachineNode(node)
    local vehicle = g_currentMission:getNodeObject(node)
    if vehicle == nil then
        return false
    end
    local machineSpec = vehicle.spec_RealisticMechanicalSystems
    return vehicle.spec_rmsImplementGreasing ~= nil or machineSpec ~= nil and not machineSpec.isExcludedVehicle
end

---Tells whether a node belongs to a grease cartridge
-- @param entityId node node
-- @return boolean isCartridge true for a cartridge
local function getIsCartridgeNode(node)
    local object = g_currentMission:getNodeObject(node)
    return object ~= nil and object.takeRMSGreaseCartridge ~= nil
end

---Tells whether the local player carries the gun
-- @param table handTool grease gun
-- @return boolean isCarried true when the local player carries it
local function getIsLocallyCarried(handTool)
    local player = handTool:getCarryingPlayer()
    return player ~= nil and player.isOwner
end

---Shows a warning to the local player
-- @param string textKey l10n key of the warning
-- @param any ... values of the format of the warning
local function warn(textKey, ...)
    g_currentMission:showBlinkingWarning(string.format(g_i18n:getText(textKey), ...), RMS_GreaseGun.WARNING_DURATION)
end

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function RMS_GreaseGun.prerequisitesPresent(specializations)
    return true
end

---Registers the saved grease of the gun
-- @param table schema savegame schema
-- @param string basePath base path of the hand tool
function RMS_GreaseGun.registerSavegameXMLPaths(schema, basePath)
    schema:register(XMLValueType.FLOAT, basePath .. "." .. modName .. ".rmsGreaseGun#greaseMl", "Grease left in the gun")
end

---Registers the functions of the gun
-- @param table handToolType hand tool type
function RMS_GreaseGun.registerFunctions(handToolType)
    SpecializationUtil.registerFunction(handToolType, "applyRMSGreaseGunState", RMS_GreaseGun.applyRMSGreaseGunState)
end

---Registers the event listeners of the gun
-- @param table handToolType hand tool type
function RMS_GreaseGun.registerEventListeners(handToolType)
    for _, name in ipairs({ "onLoad", "onPostLoad", "onDelete", "onUpdate", "onDraw", "onWriteStream", "onReadStream",
        "onHeldStart", "onHeldEnd", "onRegisterActionEvents" }) do
        SpecializationUtil.registerEventListener(handToolType, name, RMS_GreaseGun)
    end
end

---Called on loading
-- @param table xmlFile file of the hand tool
-- @param string baseDirectory directory of the hand tool
function RMS_GreaseGun:onLoad(xmlFile, baseDirectory)
    local spec = self[specName]
    spec.greaseMl = 0
    spec.targetTimer = 0
    spec.strokeTimer = 0
    spec.isActionDown = false

    if self.isClient then
        RMS_FluidHandTool.registerOverlays()
        local soundsFile = loadXMLFile("rmsGreaseGunSounds", modDirectory .. "sounds/rms_sounds.xml")
        spec.strokeSample = g_soundManager:loadSampleFromXML(soundsFile, "sounds", "greaseGunTool", modDirectory, self.components, 1,
            AudioGroup.VEHICLE, self.i3dMappings, self)
        delete(soundsFile)
    end
end

---Called after loading, reading the saved grease
-- @param table? savegame savegame
function RMS_GreaseGun:onPostLoad(savegame)
    if savegame ~= nil then
        self[specName].greaseMl = savegame.xmlFile:getValue(savegame.key .. "." .. modName .. ".rmsGreaseGun#greaseMl", 0)
    end
end

---Saves the grease left in the gun
-- @param table xmlFile savegame file
-- @param string key key of the specialization
-- @param table usedModNames mods used
function RMS_GreaseGun:saveToXMLFile(xmlFile, key, usedModNames)
    xmlFile:setValue(key .. "#greaseMl", self[specName].greaseMl)
end

---Called on deleting
function RMS_GreaseGun:onDelete()
    local spec = self[specName]
    if spec.strokeSample ~= nil then
        g_soundManager:deleteSample(spec.strokeSample)
    end
end

---Called on server side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_GreaseGun:onWriteStream(streamId, connection)
    streamWriteFloat32(streamId, self[specName].greaseMl)
end

---Called on client side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_GreaseGun:onReadStream(streamId, connection)
    self[specName].greaseMl = streamReadFloat32(streamId)
end

---Greases a point or loads a cartridge for the player carrying the gun
-- @param table handTool grease gun
-- @param table player player asking
-- @param integer kind RMS_GreaseGunEvent.STROKE or LOAD
-- @param table target machine to grease or cartridge to load
function RMS_GreaseGun.serve(handTool, player, kind, target)
    local spec = handTool[specName]
    if handTool:getCarryingPlayer() ~= player then
        return
    end

    local pointMl = RMS_GreaseGun.getPointMl()
    if kind == RMS_GreaseGunEvent.STROKE then
        if spec.greaseMl < pointMl or not RMS_Greasing.greasePoint(target) then
            return
        end
        spec.greaseMl = spec.greaseMl - pointMl
        handTool:applyRMSGreaseGunState(spec.greaseMl, true)
        RMS_GreaseGunEvent.broadcastState(handTool, spec.greaseMl, true)
    elseif spec.greaseMl < pointMl then
        target:takeRMSGreaseCartridge()
        spec.greaseMl = RMS_Config.GREASING.CARTRIDGE_ML
        handTool:applyRMSGreaseGunState(spec.greaseMl, false)
        RMS_GreaseGunEvent.broadcastState(handTool, spec.greaseMl, false)
    end
end

---Keeps the grease left and plays the stroke the gun made
-- @param float greaseMl grease left in the gun (ml)
-- @param boolean isStroke true when the state follows a stroke
function RMS_GreaseGun:applyRMSGreaseGunState(greaseMl, isStroke)
    local spec = self[specName]
    spec.greaseMl = greaseMl
    if isStroke and spec.strokeSample ~= nil then
        RMS_SoundManager.playSample(spec.strokeSample)
        spec.strokeTimer = spec.strokeSample.duration
    end
end

---Sends a stroke, false when nothing is done
-- @param table handTool grease gun
-- @return boolean isSent true once a stroke is sent
local function useGun(handTool)
    local spec = handTool[specName]
    local pointMl = RMS_GreaseGun.getPointMl()
    local vehicle = spec.target
    if vehicle == nil then
        warn("rms_grease_gun_no_vehicle")
    elseif not RMS_Greasing.getSpec(vehicle).isVehicleNeedLubricate then
        warn("rms_grease_gun_lubrication_not_require", vehicle:getFullName())
    elseif RMS_Greasing.getDuePoints(vehicle) == 0 then
        warn("rms_grease_gun_already_lubricated", vehicle:getFullName())
    elseif spec.greaseMl < pointMl then
        warn("rms_grease_gun_empty")
    else
        RMS_GreaseGunEvent.sendRequest(handTool, RMS_GreaseGunEvent.STROKE, vehicle)
        return true
    end
    return false
end

---Finds the cartridge in reach the player faces, without a crosshair
-- @param table player player
-- @return table? cartridge cartridge faced
local function getFacedCartridge(player)
    local x, y, z, dx, dy, dz = player.targeter:getLastLookRay()
    if x == nil then
        return nil
    end
    local faced, facedCos = nil, math.cos(RMS_GreaseGun.LOAD_ANGLE)
    for _, object in pairs(g_currentMission.vehicleSystem.vehicles) do
        if object.takeRMSGreaseCartridge ~= nil then
            local ox, oy, oz = getWorldTranslation(object.rootNode)
            local distance = MathUtil.vector3Length(ox - x, oy - y, oz - z)
            if distance > 0 and distance <= RMS_FluidTransfer.MAX_DISTANCE then
                local cos = ((ox - x) * dx + (oy - y) * dy + (oz - z) * dz) / distance
                if cos >= facedCos then
                    faced, facedCos = object, cos
                end
            end
        end
    end
    return faced
end

---Finds the cartridge or the machine the player aims at
-- @param table handTool grease gun
-- @param table player player
local function updateTarget(handTool, player)
    local spec = handTool[specName]
    local cartridgeNode = player.targeter:getClosestTargetedNodeFromType(RMS_GreaseCartridge)
    local machineNode = player.targeter:getClosestTargetedNodeFromType(RMS_GreaseGun)
    spec.cartridge = cartridgeNode ~= nil and g_currentMission:getNodeObject(cartridgeNode) or nil
    spec.target = spec.cartridge == nil and machineNode ~= nil and g_currentMission:getNodeObject(machineNode) or nil
    if spec.cartridge == nil and spec.target == nil then
        spec.cartridge = getFacedCartridge(player)
    end
    if spec.loadEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.loadEventId, spec.cartridge ~= nil)
    end
end

---Called on update: aims on its interval, pumps while the key is held
-- @param float dt time since the last frame (ms)
function RMS_GreaseGun:onUpdate(dt)
    local spec = self[specName]
    local player = self:getCarryingPlayer()
    if player == nil or not player.isOwner or not self:getIsHeld() then
        return
    end

    spec.targetTimer = spec.targetTimer - dt
    if spec.targetTimer <= 0 then
        spec.targetTimer = RMS_GreaseGun.TARGET_REFRESH_INTERVAL
        updateTarget(self, player)
    end

    if spec.isActionDown then
        spec.strokeTimer = spec.strokeTimer - dt
        if spec.strokeTimer <= 0 then
            spec.isActionDown = useGun(self)
            spec.strokeTimer = spec.strokeSample.duration
        end
    end
end

local WHITE, GREY, TRACK = { 1, 1, 1, 1 }, { 1, 1, 1, 0.6 }, { 1, 1, 1, 0.12 }

---Draws a filled rectangle
-- @param float x left (screen)
-- @param float y bottom (screen)
-- @param float width width (screen)
-- @param float height height (screen)
-- @param table color rgba color
-- @param float? alpha alpha in place of the color's
local function fill(x, y, width, height, color, alpha)
    drawFilledRect(x, y, width, height, color[1], color[2], color[3], alpha or color[4])
end

---Draws the outline of a rectangle
-- @param table hud HUD
-- @param float x left (screen)
-- @param float y bottom (screen)
-- @param float width width (screen)
-- @param float height height (screen)
-- @param table color rgba color
local function outline(hud, x, y, width, height, color)
    local lineX, lineY = hud:scalePixelToScreenWidth(1.5), hud:scalePixelToScreenHeight(1.5)
    fill(x, y, width, lineY, color)
    fill(x, y + height - lineY, width, lineY, color)
    fill(x, y, lineX, height, color)
    fill(x + width - lineX, y, lineX, height, color)
end

---Draws a text, shrunk to a width when one is given
-- @param float x x (screen)
-- @param float y y (screen)
-- @param float size text size
-- @param string value text
-- @param boolean bold true for bold
-- @param table color rgba color
-- @param integer? alignment RenderText alignment, left by default
-- @param float? width width to fit in (screen)
local function text(x, y, size, value, bold, color, alignment, width)
    setTextBold(bold)
    setTextAlignment(alignment or RenderText.ALIGN_LEFT)
    setTextColor(color[1], color[2], color[3], color[4])
    renderText(x, y, width ~= nil and RMS_FluidHandTool.fitTextSize(value, size, width) or size, value)
end

---Returns a height of the panel in screen units
-- @param table hud HUD
-- @param float pixels height in pixels
-- @return float height height (screen)
local function scaledY(hud, pixels)
    return hud:scalePixelToScreenHeight(pixels)
end

---Returns the screen y of a row, some pixels above the foot of the panel
-- @param table hud HUD
-- @param float y foot of the panel
-- @param float pixels height of the row above the foot, in pixels
-- @return float y y of the row (screen)
local function rowY(hud, y, pixels)
    return y + hud:scalePixelToScreenHeight(pixels)
end

local STATUS_TEXTS = { done = "rms_grease_hud_done", due = "rms_inspection_status_grease_due", late = "rms_inspection_status_grease_late" }
local lateRest = { 0, 0, 0, 0.35 }

---Returns the colour of a greasing status
-- @param string state "done", "due" or "late"
-- @return table color rgba color
local function getStatusColor(state)
    if state == "done" then
        return HUD.COLOR.ACTIVE
    end
    return state == "due" and RMS_Breakdowns.COLORS.WARNING or RMS_Breakdowns.COLORS.CRITICAL
end

---Draws the cartridge as a tube, filled by the grease left
-- @param table hud HUD
-- @param float x left (screen)
-- @param float y bottom (screen)
-- @param float width width (screen)
-- @param float height height (screen)
-- @param float share share of grease left, 0 to 1
local function drawCartridge(hud, x, y, width, height, share)
    local inset = hud:scalePixelToScreenWidth(3)
    outline(hud, x, y, width, height, share > 0 and GREY or RMS_Breakdowns.COLORS.CRITICAL)
    local right = math.floor((x + width - inset) / g_pixelSizeX + 0.5)
    local left = right - math.floor((width - inset * 2) * share / g_pixelSizeX + 0.5)
    if left < right then
        local insetY = hud:scalePixelToScreenHeight(3)
        fill(left * g_pixelSizeX, y + insetY, (right - left) * g_pixelSizeX, height - insetY * 2, HUD.COLOR.ACTIVE)
    end
end

---Draws the grease left in ml, right aligned, and returns its width
-- @param table spec gun specialization
-- @param float right right edge (screen)
-- @param float y y (screen)
-- @param float size text size of the grease left
-- @param float smallSize text size of the capacity
-- @return float width width of the text (screen)
local function drawGreaseLeft(spec, right, y, size, smallSize)
    local isEmpty = spec.greaseMl < RMS_GreaseGun.getPointMl()
    local ml = math.floor(spec.greaseMl + 0.5)
    local capacityText = string.format(" / %d %s", RMS_Config.GREASING.CARTRIDGE_ML, g_i18n:getText("rms_unit_milliliterShort"))
    setTextBold(false)
    local capacityWidth = getTextWidth(smallSize, capacityText)
    text(right, y, smallSize, capacityText, false, GREY, RenderText.ALIGN_RIGHT)
    setTextBold(true)
    local mlWidth = getTextWidth(size, tostring(ml))
    text(right - capacityWidth, y, size, tostring(ml), true, isEmpty and RMS_Breakdowns.COLORS.CRITICAL or WHITE, RenderText.ALIGN_RIGHT)
    return capacityWidth + mlWidth
end

---Draws the panel and the brand logo, returning the frame of the panel
-- @param table hud HUD
-- @param float height height of the panel in pixels
-- @return float x left of the panel (screen)
-- @return float y bottom of the panel (screen)
-- @return float width width of the panel (screen)
-- @return float padding inner margin (screen)
local function drawFrame(hud, height)
    local width, padding = hud:scalePixelToScreenWidth(RMS_GreaseGun.HUD_WIDTH), hud:scalePixelToScreenWidth(20)
    local x, y = 0.5 - width * 0.5, g_hudAnchorBottom
    local background = HUD.COLOR.BACKGROUND_DARK
    drawFilledRectRound(x, y, width, hud:scalePixelToScreenHeight(height), 0.25, background[1], background[2], background[3], background[4])
    local logo = RMS_FluidHandTool.logos[RMS_GreaseGun.BRAND]
    logo:setDimension(hud:scalePixelToScreenWidth(44), hud:scalePixelToScreenHeight(44))
    logo:setPosition(x + padding, y + hud:scalePixelToScreenHeight(height - 62))
    logo:render()
    return x, y, width, padding
end

---Draws the cartridge alone, the gun in hand without a machine aimed at
-- @param table handTool grease gun
-- @param table hud HUD
local function drawGunPanel(handTool, hud)
    local spec = handTool[specName]
    local x, y, width, padding = drawFrame(hud, RMS_GreaseGun.HUD_GUN_HEIGHT)
    local right, textX = x + width - padding, x + padding + hud:scalePixelToScreenWidth(56)
    local leftWidth = drawGreaseLeft(spec, right, rowY(hud, y, 54), scaledY(hud, 22), scaledY(hud, 18))
    local room = right - leftWidth - hud:scalePixelToScreenWidth(12) - textX
    text(textX, rowY(hud, y, 54), scaledY(hud, 20), g_i18n:getText("rms_grease_cartridge_typedesc"), true, WHITE, nil, room)
    if spec.greaseMl < RMS_GreaseGun.getPointMl() then
        text(textX, rowY(hud, y, 29), scaledY(hud, 15), g_i18n:getText("rms_grease_gun_empty"), true, RMS_Breakdowns.COLORS.CRITICAL, nil,
            right - textX)
    else
        drawCartridge(hud, textX, rowY(hud, y, 22), hud:scalePixelToScreenWidth(300), scaledY(hud, 12),
            spec.greaseMl / RMS_Config.GREASING.CARTRIDGE_ML)
    end
end

---Draws the greasing of the machine aimed at, one segment per point
-- @param table handTool grease gun
-- @param table hud HUD
local function drawMachinePanel(handTool, hud)
    local spec = handTool[specName]
    local vehicle = spec.target
    local total, due, state = RMS_Greasing.getTotalPoints(vehicle), RMS_Greasing.getDuePoints(vehicle), RMS_Greasing.getStatus(vehicle)
    local done = total - due
    local x, y, width, padding = drawFrame(hud, RMS_GreaseGun.HUD_MACHINE_HEIGHT)
    local right, textX = x + width - padding, x + padding + hud:scalePixelToScreenWidth(56)
    local gap = hud:scalePixelToScreenWidth(12)

    local totalText = string.format(" / %d", total)
    setTextBold(false)
    local totalWidth = getTextWidth(scaledY(hud, 18), totalText)
    text(right, rowY(hud, y, 142), scaledY(hud, 18), totalText, false, GREY, RenderText.ALIGN_RIGHT)
    setTextBold(true)
    local countWidth = totalWidth + getTextWidth(scaledY(hud, 30), tostring(done))
    text(right - totalWidth, rowY(hud, y, 144), scaledY(hud, 30), tostring(done), true, WHITE, RenderText.ALIGN_RIGHT)
    local greasedText = utf8ToUpper(g_i18n:getText("rms_grease_hud_greased"))
    setTextBold(true)
    local greasedWidth = getTextWidth(scaledY(hud, 15), greasedText)
    text(right, rowY(hud, y, 117), scaledY(hud, 15), greasedText, true, GREY, RenderText.ALIGN_RIGHT)
    text(textX, rowY(hud, y, 144), scaledY(hud, 22), g_i18n:getText("rms_grease_hud_title"), true, WHITE, nil, right - countWidth - gap - textX)
    text(textX, rowY(hud, y, 119), scaledY(hud, 16), vehicle:getFullName(), false, GREY, nil, right - greasedWidth - gap - textX)

    local barX, barWidth, barY, barHeight = x + padding, width - padding * 2, rowY(hud, y, 78), scaledY(hud, 16)
    local segmentGap = hud:scalePixelToScreenWidth(RMS_Utils.getSegmentGap(total, 4))
    local critical = RMS_Breakdowns.COLORS.CRITICAL
    local rest = TRACK
    if state == "late" then
        lateRest[1], lateRest[2], lateRest[3] = critical[1], critical[2], critical[3]
        rest = lateRest
    end
    local nextX, nextY, nextWidth, nextHeight = RMS_Utils.drawSegments(barX, barY, barWidth, barHeight, total, done,
        HUD.COLOR.ACTIVE, rest, segmentGap)
    if nextX ~= nil then
        outline(hud, nextX, nextY, nextWidth, nextHeight, state == "late" and critical or WHITE)
    end
    local statusText = utf8ToUpper(g_i18n:getText(STATUS_TEXTS[state]))
    setTextBold(true)
    local statusWidth = getTextWidth(scaledY(hud, 14), statusText)
    text(barX + barWidth, rowY(hud, y, 63), scaledY(hud, 14), statusText, true, getStatusColor(state), RenderText.ALIGN_RIGHT)
    text(barX, rowY(hud, y, 63), scaledY(hud, 14), string.format(g_i18n:getText("rms_grease_gun_points"), due), true, GREY, nil,
        barWidth - statusWidth - gap)
    fill(barX, rowY(hud, y, 47), barWidth, scaledY(hud, 1), WHITE, 0.16)

    local leftWidth = drawGreaseLeft(spec, right, rowY(hud, y, 31), scaledY(hud, 16), scaledY(hud, 16))
    local gaugeWidth = hud:scalePixelToScreenWidth(150)
    local gaugeX = right - leftWidth - gap - gaugeWidth
    drawCartridge(hud, gaugeX, rowY(hud, y, 25), gaugeWidth, scaledY(hud, 12), spec.greaseMl / RMS_Config.GREASING.CARTRIDGE_ML)
    text(barX, rowY(hud, y, 31), scaledY(hud, 16), g_i18n:getText("rms_grease_cartridge_typedesc"), false, GREY, nil, gaugeX - gap - barX)
end

---Shows the cartridge in hand, and the greasing of the machine aimed at
function RMS_GreaseGun:onDraw()
    if not g_currentMission.hud.isVisible then
        return
    end
    local hud, vehicle = RMS_Main.hud, self[specName].target
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    if vehicle ~= nil and RMS_Greasing.getSpec(vehicle).isVehicleNeedLubricate then
        drawMachinePanel(self, hud)
    else
        drawGunPanel(self, hud)
    end
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

---Registers the stroke and load keys
function RMS_GreaseGun:onRegisterActionEvents()
    if not self:getIsActiveForInput(true) then
        return
    end

    local spec = self[specName]
    local _, eventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, RMS_GreaseGun.onAction, true, true, false, true, nil)
    g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventText(eventId, g_i18n:getText("rms_grease_gun_action"))
    local _, loadEventId = self:addActionEvent(InputAction.RMS_TOGGLE_FLUID_CAN, self, RMS_GreaseGun.onLoadAction, true, false, false, false, nil)
    g_inputBinding:setActionEventTextPriority(loadEventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventText(loadEventId, g_i18n:getText("rms_grease_gun_load"))
    g_inputBinding:setActionEventActive(loadEventId, spec.cartridge ~= nil)
    spec.loadEventId = loadEventId
end

---Loads the gun from the cartridge faced, with the key that takes a can
function RMS_GreaseGun:onLoadAction()
    local spec = self[specName]
    if spec.cartridge == nil then
        return
    end
    if spec.greaseMl >= RMS_GreaseGun.getPointMl() then
        warn("rms_grease_gun_not_empty")
    else
        RMS_GreaseGunEvent.sendRequest(self, RMS_GreaseGunEvent.LOAD, spec.cartridge)
    end
end

---A press makes one stroke at once, holding the key pumps on
-- @param string actionName input action
-- @param float inputValue input value
function RMS_GreaseGun:onAction(actionName, inputValue)
    local spec = self[specName]
    local isDown = inputValue ~= 0
    if isDown == spec.isActionDown then
        return
    end

    spec.isActionDown = isDown and useGun(self)
    spec.strokeTimer = spec.strokeSample.duration
end

---Lets the player aim at machines and cartridges with the gun
function RMS_GreaseGun:onHeldStart()
    if getIsLocallyCarried(self) then
        local targeter = self:getCarryingPlayer().targeter
        targeter:addTargetType(RMS_GreaseGun, CollisionFlag.VEHICLE, 0, RMS_FluidTransfer.MAX_DISTANCE)
        targeter:addFilterToTargetType(RMS_GreaseGun, getIsMachineNode)
        targeter:addTargetType(RMS_GreaseCartridge, CollisionFlag.VEHICLE, 0, RMS_FluidTransfer.MAX_DISTANCE)
        targeter:addFilterToTargetType(RMS_GreaseCartridge, getIsCartridgeNode)
    end
end

---Stops aiming once the gun leaves the hand
function RMS_GreaseGun:onHeldEnd()
    local spec = self[specName]
    spec.isActionDown = false
    spec.target, spec.cartridge = nil, nil
    if getIsLocallyCarried(self) then
        local targeter = self:getCarryingPlayer().targeter
        targeter:removeTargetType(RMS_GreaseGun)
        targeter:removeTargetType(RMS_GreaseCartridge)
    end
end
