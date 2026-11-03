-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Grease gun emptying a real cartridge, one grease point per stroke
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
function RMS_GreaseGun.getPointMl()
    local C = RMS_Config.GREASING
    return C.STROKE_ML * C.STROKES_PER_POINT
end

local function getIsMachineNode(node)
    local vehicle = g_currentMission:getNodeObject(node)
    if vehicle == nil then
        return false
    end
    local machineSpec = vehicle.spec_RealisticMechanicalSystems
    return vehicle.spec_rmsImplementGreasing ~= nil or machineSpec ~= nil and not machineSpec.isExcludedVehicle
end

local function getIsCartridgeNode(node)
    local object = g_currentMission:getNodeObject(node)
    return object ~= nil and object.takeRMSGreaseCartridge ~= nil
end

local function getIsLocallyCarried(handTool)
    local player = handTool:getCarryingPlayer()
    return player ~= nil and player.isOwner
end

local function warn(textKey, ...)
    g_currentMission:showBlinkingWarning(string.format(g_i18n:getText(textKey), ...), RMS_GreaseGun.WARNING_DURATION)
end

function RMS_GreaseGun.prerequisitesPresent(specializations)
    return true
end

function RMS_GreaseGun.registerSavegameXMLPaths(schema, basePath)
    schema:register(XMLValueType.FLOAT, basePath .. "." .. modName .. ".rmsGreaseGun#greaseMl", "Grease left in the gun")
end

function RMS_GreaseGun.registerFunctions(handToolType)
    SpecializationUtil.registerFunction(handToolType, "applyRMSGreaseGunState", RMS_GreaseGun.applyRMSGreaseGunState)
end

function RMS_GreaseGun.registerEventListeners(handToolType)
    for _, name in ipairs({ "onLoad", "onPostLoad", "onDelete", "onUpdate", "onDraw", "onWriteStream", "onReadStream",
        "onHeldStart", "onHeldEnd", "onRegisterActionEvents" }) do
        SpecializationUtil.registerEventListener(handToolType, name, RMS_GreaseGun)
    end
end

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

function RMS_GreaseGun:onPostLoad(savegame)
    if savegame ~= nil then
        self[specName].greaseMl = savegame.xmlFile:getValue(savegame.key .. "." .. modName .. ".rmsGreaseGun#greaseMl", 0)
    end
end

function RMS_GreaseGun:saveToXMLFile(xmlFile, key, usedModNames)
    xmlFile:setValue(key .. "#greaseMl", self[specName].greaseMl)
end

function RMS_GreaseGun:onDelete()
    local spec = self[specName]
    if spec.strokeSample ~= nil then
        g_soundManager:deleteSample(spec.strokeSample)
    end
end

function RMS_GreaseGun:onWriteStream(streamId, connection)
    streamWriteFloat32(streamId, self[specName].greaseMl)
end

function RMS_GreaseGun:onReadStream(streamId, connection)
    self[specName].greaseMl = streamReadFloat32(streamId)
end

---Greases a point or loads a cartridge for the player carrying the gun
function RMS_GreaseGun.serve(handTool, player, kind, target)
    local spec = handTool[specName]
    if spec == nil or handTool:getCarryingPlayer() ~= player then
        return
    end

    local pointMl = RMS_GreaseGun.getPointMl()
    if kind == RMS_GreaseGunEvent.STROKE then
        if spec.greaseMl < pointMl or RMS_Greasing.getSpec(target) == nil or not RMS_Greasing.greasePoint(target) then
            return
        end
        spec.greaseMl = spec.greaseMl - pointMl
        handTool:applyRMSGreaseGunState(spec.greaseMl, true)
        RMS_GreaseGunEvent.broadcastState(handTool, spec.greaseMl, true)
    elseif target.takeRMSGreaseCartridge ~= nil and spec.greaseMl < pointMl then
        target:takeRMSGreaseCartridge()
        spec.greaseMl = RMS_Config.GREASING.CARTRIDGE_ML
        handTool:applyRMSGreaseGunState(spec.greaseMl, false)
        RMS_GreaseGunEvent.broadcastState(handTool, spec.greaseMl, false)
    end
end

---Keeps the grease left and plays the stroke the gun made
function RMS_GreaseGun:applyRMSGreaseGunState(greaseMl, isStroke)
    local spec = self[specName]
    spec.greaseMl = greaseMl
    if isStroke and spec.strokeSample ~= nil then
        RMS_SoundManager.playSample(spec.strokeSample)
        spec.strokeTimer = spec.strokeSample.duration
    end
end

---Sends a stroke, false when nothing is done
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

---Returns the points greased since aiming at the machine, out of all
-- @return integer done, integer total, string state done, due or late
function RMS_GreaseGun.getGreasingProgress(handTool)
    local spec = handTool[specName]
    local vehicle = spec.target
    local due = RMS_Greasing.getDuePoints(vehicle)
    if spec.progressVehicle ~= vehicle or due > spec.progressDue then
        spec.progressVehicle, spec.progressDone = vehicle, 0
    elseif due < spec.progressDue then
        spec.progressDone = spec.progressDone + spec.progressDue - due
    end
    spec.progressDue = due
    local state = due == 0 and "done" or RMS_Greasing.getSpec(vehicle).lubricationLevel > 0 and "due" or "late"
    return spec.progressDone, spec.progressDone + due, state
end

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

local function fill(x, y, width, height, color, alpha)
    drawFilledRect(x, y, width, height, color[1], color[2], color[3], alpha or color[4] or 1)
end

local function outline(hud, x, y, width, height, color)
    local lineX, lineY = hud:scalePixelToScreenWidth(1.5), hud:scalePixelToScreenHeight(1.5)
    fill(x, y, width, lineY, color)
    fill(x, y + height - lineY, width, lineY, color)
    fill(x, y, lineX, height, color)
    fill(x + width - lineX, y, lineX, height, color)
end

local function text(x, y, size, value, bold, color, alignment, width)
    setTextBold(bold)
    setTextAlignment(alignment or RenderText.ALIGN_LEFT)
    setTextColor(color[1], color[2], color[3], color[4] or 1)
    renderText(x, y, width ~= nil and RMS_FluidHandTool.fitTextSize(value, size, width) or size, value)
end

---Draws the cartridge as a tube, filled by the grease left
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

---Draws the panel and the SKF logo, returning the frame of the panel
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
local function drawGunPanel(handTool, hud)
    local spec = handTool[specName]
    local x, y, width, padding = drawFrame(hud, RMS_GreaseGun.HUD_GUN_HEIGHT)
    local right, textX = x + width - padding, x + padding + hud:scalePixelToScreenWidth(56)
    local function rowY(pixels) return y + hud:scalePixelToScreenHeight(pixels) end
    local function size(pixels) return hud:scalePixelToScreenHeight(pixels) end
    local leftWidth = drawGreaseLeft(spec, right, rowY(54), size(22), size(18))
    local room = right - leftWidth - hud:scalePixelToScreenWidth(12) - textX
    text(textX, rowY(54), size(20), g_i18n:getText("rms_grease_cartridge_typedesc"), true, WHITE, nil, room)
    if spec.greaseMl < RMS_GreaseGun.getPointMl() then
        text(textX, rowY(29), size(15), g_i18n:getText("rms_grease_gun_empty"), true, RMS_Breakdowns.COLORS.CRITICAL, nil, right - textX)
    else
        drawCartridge(hud, textX, rowY(22), hud:scalePixelToScreenWidth(300), size(12), spec.greaseMl / RMS_Config.GREASING.CARTRIDGE_ML)
    end
end

---Draws the greasing of the machine aimed at, one segment per point
local function drawMachinePanel(handTool, hud)
    local spec = handTool[specName]
    local done, total, state = RMS_GreaseGun.getGreasingProgress(handTool)
    local x, y, width, padding = drawFrame(hud, RMS_GreaseGun.HUD_MACHINE_HEIGHT)
    local right, textX = x + width - padding, x + padding + hud:scalePixelToScreenWidth(56)
    local gap = hud:scalePixelToScreenWidth(12)
    local function rowY(pixels) return y + hud:scalePixelToScreenHeight(pixels) end
    local function size(pixels) return hud:scalePixelToScreenHeight(pixels) end
    local status = ({ done = { "rms_grease_hud_done", HUD.COLOR.ACTIVE }, due = { "rms_inspection_status_grease_due", RMS_Breakdowns.COLORS.WARNING },
        late = { "rms_inspection_status_grease_late", RMS_Breakdowns.COLORS.CRITICAL } })[state]

    local countWidth = 0
    if total > 0 then
        local totalText = string.format(" / %d", total)
        setTextBold(false)
        local totalWidth = getTextWidth(size(18), totalText)
        text(right, rowY(142), size(18), totalText, false, GREY, RenderText.ALIGN_RIGHT)
        setTextBold(true)
        countWidth = totalWidth + getTextWidth(size(30), tostring(done))
        text(right - totalWidth, rowY(144), size(30), tostring(done), true, WHITE, RenderText.ALIGN_RIGHT)
    end
    local statusText = utf8ToUpper(g_i18n:getText(status[1]))
    setTextBold(true)
    local statusWidth = getTextWidth(size(15), statusText)
    text(right, rowY(117), size(15), statusText, true, status[2], RenderText.ALIGN_RIGHT)
    text(textX, rowY(144), size(22), g_i18n:getText("rms_grease_hud_title"), true, WHITE, nil, right - countWidth - gap - textX)
    text(textX, rowY(119), size(16), spec.target:getFullName(), false, GREY, nil, right - statusWidth - gap - textX)

    local barX, barWidth, barY, barHeight = x + padding, width - padding * 2, rowY(78), size(16)
    local segmentGap = hud:scalePixelToScreenWidth(RMS_Utils.getSegmentGap(total, 4))
    local critical = RMS_Breakdowns.COLORS.CRITICAL
    local rest = state == "late" and { critical[1], critical[2], critical[3], 0.35 } or TRACK
    local nextX, nextY, nextWidth, nextHeight = RMS_Utils.drawSegments(barX, barY, barWidth, barHeight, math.max(total, 1),
        total == 0 and 1 or done, HUD.COLOR.ACTIVE, rest, segmentGap)
    if nextX ~= nil then
        outline(hud, nextX, nextY, nextWidth, nextHeight, state == "late" and critical or WHITE)
    end
    text(barX, rowY(63), size(14), string.format(g_i18n:getText("rms_grease_gun_points"), total - done), true, GREY, nil, barWidth)
    fill(barX, rowY(47), barWidth, size(1), WHITE, 0.16)

    local leftWidth = drawGreaseLeft(spec, right, rowY(31), size(16), size(16))
    local gaugeWidth = hud:scalePixelToScreenWidth(150)
    local gaugeX = right - leftWidth - gap - gaugeWidth
    drawCartridge(hud, gaugeX, rowY(25), gaugeWidth, size(12), spec.greaseMl / RMS_Config.GREASING.CARTRIDGE_ML)
    text(barX, rowY(31), size(16), g_i18n:getText("rms_grease_cartridge_typedesc"), false, GREY, nil, gaugeX - gap - barX)
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
