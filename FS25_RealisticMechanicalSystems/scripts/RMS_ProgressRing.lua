-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Progress ring of the mod, an arc filling clockwise over a track
RMS_ProgressRing = {}
RMS_ProgressRing.modDirectory = g_currentModDirectory
RMS_ProgressRing.RADIUS = 107 / 256
RMS_ProgressRing.DOT = 32 / 256
RMS_ProgressRing.SEGMENTS = 90
RMS_ProgressRing.PERCENT_TEXT_SHARE = 0.22
RMS_ProgressRing.THIN_DOT = 16 / 256

---Loads the ring atlas and its overlays
function RMS_ProgressRing.register()
    g_overlayManager:addTextureConfigFile(RMS_ProgressRing.modDirectory .. "hud/rms_progressRing.xml", "rms_ProgressRing")
    RMS_ProgressRing.track = g_overlayManager:createOverlay("rms_ProgressRing.ring", 0, 0, 0, 0)
    RMS_ProgressRing.dot = g_overlayManager:createOverlay("rms_ProgressRing.dot", 0, 0, 0, 0)
end

---Draws the ring with its arc filled to the given ratio and its percentage inside
-- @param float centerX horizontal center in screen space
-- @param float centerY vertical center in screen space
-- @param float width ring width in screen space
-- @param float height ring height in screen space
-- @param float ratio progress between 0 and 1
-- @param boolean? showText true to render the percentage inside the ring
-- @param float? dotShare arc thickness as a share of the ring box, the baked ring image when nil
function RMS_ProgressRing.render(centerX, centerY, width, height, ratio, showText, dotShare)
    local grey = Dashboard.COLORS.GREY
    local green = HUD.COLOR.ACTIVE
    local dot = RMS_ProgressRing.dot
    local segments = math.ceil(RMS_ProgressRing.SEGMENTS * RMS_ProgressRing.DOT / (dotShare or RMS_ProgressRing.DOT))
    local step = (2 * math.pi) / segments
    local dotWidth = width * (dotShare or RMS_ProgressRing.DOT)
    local dotHeight = height * (dotShare or RMS_ProgressRing.DOT)
    local radiusX, radiusY = width * RMS_ProgressRing.RADIUS, height * RMS_ProgressRing.RADIUS

    ---Places the dot on the ring at an angle and draws it
    -- @param float angle angle from the top of the ring, clockwise
    local function renderDotAt(angle)
        dot:setPosition(centerX + math.sin(angle) * radiusX - dotWidth * 0.5, centerY + math.cos(angle) * radiusY - dotHeight * 0.5)
        dot:render()
    end

    dot:setDimension(dotWidth, dotHeight)

    if dotShare == nil then
        local track = RMS_ProgressRing.track

        track:setDimension(width, height)
        track:setPosition(centerX - width * 0.5, centerY - height * 0.5)
        track:setColor(grey[1], grey[2], grey[3], 1)
        track:render()
    else
        dot:setColor(grey[1], grey[2], grey[3], 1)
        for segment = 0, segments - 1 do
            renderDotAt(segment * step)
        end
    end

    dot:setColor(green[1], green[2], green[3], 1)

    local sweep = math.clamp(ratio, 0, 1) * 2 * math.pi
    local angle = 0

    while angle < sweep do
        renderDotAt(angle)
        angle = angle + step
    end

    renderDotAt(sweep)

    if showText ~= false then
        local percentSize = height * RMS_ProgressRing.PERCENT_TEXT_SHARE

        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(1, 1, 1, 1)
        renderText(centerX, centerY - percentSize * 0.4, percentSize, string.format("%d%%", math.floor(ratio * 100)))
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(false)
    end
end
